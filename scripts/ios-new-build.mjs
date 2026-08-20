#!/usr/bin/env node

import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const root = resolve(dirname(new URL(import.meta.url).pathname), "..");
const tauriConfigPath = join(root, "src-tauri/tauri.conf.json");
const projectPath = join(root, "src-tauri/gen/apple/project.yml");
const infoPlistPath = join(root, "src-tauri/gen/apple/app_iOS/Info.plist");
const archiveRoot = join(root, "src-tauri/gen/apple/build");
const organizerArchiveRoot = join(
  homedir(),
  "Library/Developer/Xcode/Archives",
);
const dryRun = process.argv.includes("--dry-run");

function fail(message) {
  console.error(`\nerror: ${message}`);
  process.exit(1);
}

function run(command, args, capture = false) {
  const result = spawnSync(command, args, {
    cwd: root,
    encoding: "utf8",
    stdio: capture ? "pipe" : "inherit",
  });
  if (result.error) fail(`${command} could not run: ${result.error.message}`);
  if (result.status !== 0) {
    if (capture && result.stderr) process.stderr.write(result.stderr);
    fail(`${command} exited with status ${result.status}`);
  }
  return capture ? result.stdout.trim() : "";
}

function newestArchive() {
  if (!existsSync(archiveRoot)) return null;
  return (
    readdirSync(archiveRoot, { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && entry.name.endsWith(".xcarchive"))
      .map((entry) => join(archiveRoot, entry.name))
      .sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs)[0] ?? null
  );
}

function archiveBuild(archive) {
  if (!archive) return null;
  const value = run(
    "/usr/libexec/PlistBuddy",
    ["-c", "Print :ApplicationProperties:CFBundleVersion", join(archive, "Info.plist")],
    true,
  );
  const build = Number(value);
  if (!Number.isSafeInteger(build) || build < 1) {
    fail(`archive has an invalid build number: ${value}`);
  }
  return build;
}

function archiveVersion(archive) {
  return run(
    "/usr/libexec/PlistBuddy",
    [
      "-c",
      "Print :ApplicationProperties:CFBundleShortVersionString",
      join(archive, "Info.plist"),
    ],
    true,
  );
}

function verifySignedArchive(archive) {
  const team = run(
    "/usr/libexec/PlistBuddy",
    ["-c", "Print :ApplicationProperties:Team", join(archive, "Info.plist")],
    true,
  );
  if (!team) {
    fail("archive has no signing team");
  }

  const applicationsDir = join(archive, "Products/Applications");
  const appName = readdirSync(applicationsDir).find((name) => name.endsWith(".app"));
  if (!appName) {
    fail("archive does not contain an application bundle");
  }
  run("/usr/bin/codesign", ["--verify", "--deep", "--strict", join(applicationsDir, appName)]);
}

function copyToXcodeOrganizer(archive, version, build) {
  const date = new Date().toLocaleDateString("en-CA", {
    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
  });
  const destination = join(
    organizerArchiveRoot,
    date,
    `Zerus ${version} (${build}).xcarchive`,
  );

  if (existsSync(destination)) {
    console.log(`Xcode Organizer archive already exists at ${destination}`);
    return;
  }

  mkdirSync(dirname(destination), { recursive: true });
  cpSync(archive, destination, { recursive: true });
  console.log(`Copied archive for Xcode Organizer to ${destination}`);
}

const configText = readFileSync(tauriConfigPath, "utf8");
const config = JSON.parse(configText);
const configuredIdentifier = config.identifier;
const projectText = readFileSync(projectPath, "utf8");
const generatedIdentifier = projectText.match(
  /\bPRODUCT_BUNDLE_IDENTIFIER:\s*([^\s]+)/,
)?.[1];
if (!configuredIdentifier || generatedIdentifier !== configuredIdentifier) {
  fail(
    `tauri.conf.json configures ${configuredIdentifier ?? "no bundle identifier"}, but generated project.yml configures ${generatedIdentifier ?? "no bundle identifier"}. Reconcile the iOS project before building.`,
  );
}
const configuredBuild = Number(config.bundle?.iOS?.bundleVersion);
if (!Number.isSafeInteger(configuredBuild) || configuredBuild < 1) {
  fail("bundle.iOS.bundleVersion must be a positive integer");
}

const archive = newestArchive();
const lastBuilt = archiveBuild(archive);
if (lastBuilt !== null && lastBuilt > configuredBuild) {
  fail(
    `latest archive is build ${lastBuilt}, ahead of configured build ${configuredBuild}; reconcile the release record first`,
  );
}

// If configuration was already advanced but that archive never completed,
// retry the prepared number instead of skipping another build number.
const targetBuild = lastBuilt === configuredBuild ? configuredBuild + 1 : configuredBuild;
const action = targetBuild === configuredBuild ? "retry" : "advance";
console.log(
  `${dryRun ? "Would" : "Will"} ${action} from configured build ${configuredBuild} to build ${targetBuild}; latest completed local archive is ${lastBuilt ?? "none"}.`,
);

if (dryRun) process.exit(0);

const configMatch = /(\"iOS\"\s*:\s*\{[\s\S]*?\"bundleVersion\"\s*:\s*\")([^\"]+)(\")/;
if (!configMatch.test(configText)) {
  fail("could not locate bundle.iOS.bundleVersion in tauri.conf.json");
}
writeFileSync(
  tauriConfigPath,
  configText.replace(
    configMatch,
    (_match, prefix, _oldBuild, suffix) =>
      `${prefix}${targetBuild}${suffix}`,
  ),
);

const projectMatch = /(\bCFBundleVersion:\s*[\"']?)([^\s\"']+)([\"']?)/;
if (!projectMatch.test(projectText)) {
  fail("could not locate CFBundleVersion in project.yml");
}
writeFileSync(
  projectPath,
  projectText.replace(
    projectMatch,
    (_match, prefix, _oldBuild, suffix) =>
      `${prefix}${targetBuild}${suffix}`,
  ),
);
run("/usr/libexec/PlistBuddy", [
  "-c",
  `Set :CFBundleVersion ${targetBuild}`,
  infoPlistPath,
]);

run("pnpm", ["build"]);
const completedArchive = join(
  archiveRoot,
  `Zerus-${targetBuild}-${Date.now()}.xcarchive`,
);
run("xcodebuild", [
  "archive",
  "-project",
  join(root, "src-tauri/gen/apple/app.xcodeproj"),
  "-scheme",
  "app_iOS",
  "-configuration",
  "release",
  "-destination",
  "generic/platform=iOS",
  "-archivePath",
  completedArchive,
  "-allowProvisioningUpdates",
  `DEVELOPMENT_TEAM=TX9RYY52XR`,
  "CODE_SIGN_STYLE=Automatic",
]);

const completedBuild = archiveBuild(completedArchive);
if (completedBuild !== targetBuild) {
  fail(
    `build completed, but newest archive is ${completedBuild ?? "missing"} instead of ${targetBuild}`,
  );
}
verifySignedArchive(completedArchive);

copyToXcodeOrganizer(completedArchive, archiveVersion(completedArchive), targetBuild);

run("pnpm", ["testflight", "--", "--export-only"]);
console.log(
  `Build ${targetBuild} is archived and exported. Run pnpm testflight to upload it.`,
);
