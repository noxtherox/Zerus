import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";

const version = process.argv[2];
const semverPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

if (!version || !semverPattern.test(version)) {
  console.error("Usage: pnpm release <major.minor.patch>");
  process.exit(1);
}

const run = (command, args, options = {}) =>
  execFileSync(command, args, { encoding: "utf8", stdio: "inherit", ...options });
const output = (command, args) =>
  execFileSync(command, args, { encoding: "utf8" }).trim();

if (output("git", ["branch", "--show-current"]) !== "main") {
  throw new Error("Releases must be created from main.");
}
if (output("git", ["status", "--porcelain"])) {
  throw new Error("Commit or stash local changes before creating a release.");
}

run("git", ["fetch", "origin", "main", "--tags"]);
if (output("git", ["rev-parse", "HEAD"]) !== output("git", ["rev-parse", "origin/main"])) {
  throw new Error("main must exactly match origin/main before creating a release.");
}

const tag = `v${version}`;
if (output("git", ["tag", "--list", tag])) {
  throw new Error(`${tag} already exists.`);
}

const configPath = "src-tauri/tauri.conf.json";
const cargoPath = "src-tauri/Cargo.toml";
const lockPath = "src-tauri/Cargo.lock";
const appleProjectPath = "src-tauri/gen/apple/project.yml";
const appleInfoPath = "src-tauri/gen/apple/app_iOS/Info.plist";
const nativeMacPath = "native-macos/project.yml";
const config = JSON.parse(readFileSync(configPath, "utf8"));
const currentVersion = config.version;
const currentParts = currentVersion.split(".").map(Number);
const nextParts = version.split(".").map(Number);
const firstDifference = nextParts.findIndex(
  (part, index) => part !== currentParts[index],
);
const isNewer =
  firstDifference !== -1 &&
  nextParts[firstDifference] > currentParts[firstDifference];

if (!isNewer) {
  throw new Error(`Version ${version} must be newer than ${currentVersion}.`);
}

// The native macOS app shares the release version; its build number only grows.
const nativeMac = readFileSync(nativeMacPath, "utf8");
const nativeVersion = nativeMac.match(/^(\s*MARKETING_VERSION:\s*)([0-9.]+)\s*$/m)?.[2];
const nativeBuild = Number(nativeMac.match(/^\s*CURRENT_PROJECT_VERSION:\s*(\d+)\s*$/m)?.[1]);
if (!nativeVersion || !Number.isSafeInteger(nativeBuild)) {
  throw new Error(`Cannot read the native macOS version from ${nativeMacPath}.`);
}
const nativeParts = nativeVersion.split(".").map(Number);
const nativeDifference = nextParts.findIndex((part, index) => part !== nativeParts[index]);
if (nativeDifference === -1 || nextParts[nativeDifference] < nativeParts[nativeDifference]) {
  throw new Error(`Version ${version} must be newer than the native macOS version ${nativeVersion}.`);
}
const nextNativeMac = nativeMac
  .replace(/^(\s*MARKETING_VERSION:\s*)[0-9.]+(\s*)$/m, `$1${version}$2`)
  .replace(/^(\s*CURRENT_PROJECT_VERSION:\s*)\d+(\s*)$/m, `$1${nativeBuild + 1}$2`);

run("pnpm", ["updater-key:verify"]);
run("pnpm", ["build"]);
run("pnpm", ["exec", "vitest", "run", "--exclude", ".claude/**"]);

const cargo = readFileSync(cargoPath, "utf8");
const nextCargo = cargo.replace(
  new RegExp(`(\\[package\\][\\s\\S]*?name = "app"\\nversion = ")${currentVersion}("\\n)`),
  `$1${version}$2`,
);

const lock = readFileSync(lockPath, "utf8");
const nextLock = lock.replace(
  new RegExp(`(name = "app"\\nversion = ")${currentVersion}("\\n)`),
  `$1${version}$2`,
);

const appleProject = readFileSync(appleProjectPath, "utf8");
const nextAppleProject = appleProject.replace(
  /(CFBundleShortVersionString:\s*)\d+\.\d+\.\d+/,
  `$1${version}`,
);

const appleInfo = readFileSync(appleInfoPath, "utf8");
const nextAppleInfo = appleInfo.replace(
  /(<key>CFBundleShortVersionString<\/key>\s*<string>)\d+\.\d+\.\d+(<\/string>)/,
  `$1${version}$2`,
);

if (
  nextCargo === cargo ||
  nextLock === lock ||
  nextAppleProject === appleProject ||
  nextAppleInfo === appleInfo ||
  nextNativeMac === nativeMac
) {
  throw new Error("Could not locate every version field; no release was created.");
}

config.version = version;
writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
writeFileSync(cargoPath, nextCargo);
writeFileSync(lockPath, nextLock);
writeFileSync(appleProjectPath, nextAppleProject);
writeFileSync(appleInfoPath, nextAppleInfo);
writeFileSync(nativeMacPath, nextNativeMac);

run("cargo", ["check", "--manifest-path", cargoPath, "-p", "app"]);
run("git", [
  "add",
  configPath,
  cargoPath,
  lockPath,
  appleProjectPath,
  appleInfoPath,
  nativeMacPath,
]);
run("git", ["commit", "-m", `Release ${tag}`]);
run("git", ["tag", "-a", tag, "-m", `Zerus ${tag}`]);
run("git", ["push", "--atomic", "origin", "main", `refs/tags/${tag}`]);

console.log(`${tag} pushed. GitHub Actions is building the Windows installer.`);
console.log("Run `pnpm macos:release` now to build, notarize and publish the macOS DMG and update feed.");
