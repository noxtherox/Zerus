#!/usr/bin/env node

import { execFileSync, spawnSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

if (process.platform !== "darwin") {
  console.log("Skipping macOS artifact verification on this platform.");
  process.exit(0);
}

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const config = JSON.parse(
  readFileSync(resolve(root, "src-tauri/tauri.conf.json"), "utf8"),
);
const launch = process.argv.includes("--launch");
const requireNotarized = process.argv.includes("--require-notarized");
const explicitAppIndex = process.argv.indexOf("--app");
const explicitApp =
  explicitAppIndex === -1 ? undefined : process.argv[explicitAppIndex + 1];

if (explicitAppIndex !== -1 && !explicitApp) {
  throw new Error("--app requires a path");
}

const targetRoot = resolve(root, "src-tauri/target");
const bundleRoots = [resolve(targetRoot, "release/bundle")];
if (existsSync(targetRoot)) {
  for (const entry of readdirSync(targetRoot, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      bundleRoots.push(resolve(targetRoot, entry.name, "release/bundle"));
    }
  }
}

const appName = `${config.productName}.app`;
const appCandidates = explicitApp
  ? [resolve(explicitApp)]
  : bundleRoots
      .map((bundleRoot) => resolve(bundleRoot, "macos", appName))
      .filter(existsSync);

if (appCandidates.length === 0) {
  throw new Error(`No built ${appName} was found under ${targetRoot}`);
}

const appPath = appCandidates.sort(
  (left, right) => statSync(right).mtimeMs - statSync(left).mtimeMs,
)[0];
const run = (command, args, options = {}) =>
  execFileSync(command, args, { encoding: "utf8", ...options });

run("codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath], {
  stdio: "inherit",
});
if (requireNotarized) {
  const signatureInspection = spawnSync(
    "codesign",
    ["-d", "--verbose=4", appPath],
    { encoding: "utf8" },
  );
  if (signatureInspection.status !== 0) {
    throw new Error(`Could not inspect the app signature: ${signatureInspection.stderr}`);
  }
  const signatureDetails = `${signatureInspection.stdout}${signatureInspection.stderr}`;
  const expectedAuthority =
    "Authority=Developer ID Application: Tiago Honrado Rio Pereira (TX9RYY52XR)";
  if (!signatureDetails.includes(expectedAuthority)) {
    throw new Error("macOS artifact is not signed with the Zerus Developer ID identity");
  }
  if (!signatureDetails.includes("TeamIdentifier=TX9RYY52XR")) {
    throw new Error("macOS artifact does not have the expected Apple Team ID");
  }
  if (!signatureDetails.includes("runtime")) {
    throw new Error("macOS artifact does not have Hardened Runtime enabled");
  }
  run("xcrun", ["stapler", "validate", appPath], { stdio: "inherit" });
  run("spctl", ["--assess", "--type", "execute", "--verbose=4", appPath], {
    stdio: "inherit",
  });
}
const entitlements = run("codesign", ["-d", "--entitlements", ":-", appPath], {
  stdio: ["ignore", "pipe", "ignore"],
});
if (entitlements.includes("<key>keychain-access-groups</key>")) {
  throw new Error(
    "macOS artifact contains keychain-access-groups; ad-hoc builds cannot launch with this restricted entitlement",
  );
}

const infoPlist = resolve(appPath, "Contents/Info.plist");
const identifier = run("/usr/libexec/PlistBuddy", [
  "-c",
  "Print :CFBundleIdentifier",
  infoPlist,
]).trim();
if (identifier !== config.identifier) {
  throw new Error(
    `macOS artifact identifier is ${identifier}, expected ${config.identifier}`,
  );
}
const executableName = run("/usr/libexec/PlistBuddy", [
  "-c",
  "Print :CFBundleExecutable",
  infoPlist,
]).trim();

const bundleRoot = dirname(dirname(appPath));
const dmgDirectory = resolve(bundleRoot, "dmg");
const dmgCandidates = existsSync(dmgDirectory)
  ? readdirSync(dmgDirectory)
      .filter(
        (name) =>
          name.startsWith(`${config.productName}_${config.version}_`) &&
          name.endsWith(".dmg"),
      )
      .map((name) => resolve(dmgDirectory, name))
      .sort((left, right) => statSync(right).mtimeMs - statSync(left).mtimeMs)
  : [];

if (dmgCandidates.length === 0) {
  console.log(`Verified ${appPath}; no DMG was requested for this build.`);
  process.exit(0);
}

const dmgPath = dmgCandidates[0];
const mountPath = mkdtempSync(join(tmpdir(), "zerus-verify-mount-"));
const copyRoot = mkdtempSync(join(tmpdir(), "zerus-verify-copy-"));
const copiedApp = resolve(copyRoot, appName);
let mounted = false;

try {
  run("hdiutil", ["verify", dmgPath], { stdio: "inherit" });
  run(
    "hdiutil",
    ["attach", dmgPath, "-readonly", "-nobrowse", "-mountpoint", mountPath],
    { stdio: "ignore" },
  );
  mounted = true;
  run("ditto", ["--rsrc", "--extattr", resolve(mountPath, appName), copiedApp]);
  run("codesign", ["--verify", "--deep", "--strict", "--verbose=2", copiedApp], {
    stdio: "inherit",
  });
  if (requireNotarized) {
    run("xcrun", ["stapler", "validate", copiedApp], { stdio: "inherit" });
    run(
      "spctl",
      ["--assess", "--type", "execute", "--verbose=4", copiedApp],
      { stdio: "inherit" },
    );
  }

  if (launch) {
    run("open", ["-n", copiedApp]);
    const executable = resolve(copiedApp, "Contents/MacOS", executableName);
    let pid;
    for (let attempt = 0; attempt < 5 && !pid; attempt += 1) {
      try {
        pid = Number(
          run("pgrep", ["-f", executable])
            .trim()
            .split("\n")[0],
        );
      } catch {
        run("sleep", ["1"]);
      }
    }
    if (!pid) {
      throw new Error("Launch Services accepted the app but no process started");
    }
    process.kill(pid, "SIGTERM");
    console.log(`Launch smoke test passed for ${basename(dmgPath)}.`);
  }
} finally {
  if (mounted) {
    try {
      run("hdiutil", ["detach", mountPath], { stdio: "ignore" });
    } catch {
      // Preserve the primary verification error if detaching also fails.
    }
  }
  rmSync(mountPath, { recursive: true, force: true });
  rmSync(copyRoot, { recursive: true, force: true });
}

console.log(
  `Verified macOS app identity, entitlements, signature, DMG, and installer copy: ${dmgPath}`,
);
