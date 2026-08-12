#!/usr/bin/env node

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const root = resolve(dirname(new URL(import.meta.url).pathname), "..");
const archiveRoot = join(root, "src-tauri/gen/apple/build");
const generatedProject = join(root, "src-tauri/gen/apple/project.yml");
const tauriConfig = join(root, "src-tauri/tauri.conf.json");
const exportOptions = join(
  root,
  "src-tauri/gen/apple/ExportOptions-TestFlight.plist",
);
const localConfig = join(root, ".appstoreconnect.local");

function fail(message) {
  console.error(`\nerror: ${message}`);
  process.exit(1);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: root,
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit",
    input: options.input,
  });

  if (result.error) fail(`${command} could not run: ${result.error.message}`);
  if (result.status !== 0) {
    if (options.capture && result.stderr) process.stderr.write(result.stderr);
    fail(`${command} exited with status ${result.status}`);
  }
  return options.capture ? result.stdout.trim() : "";
}

function loadLocalConfig() {
  if (!existsSync(localConfig)) return;

  for (const rawLine of readFileSync(localConfig, "utf8").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const match = line.match(/^([A-Z][A-Z0-9_]*)=(.*)$/);
    if (!match || process.env[match[1]]) continue;
    let value = match[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    process.env[match[1]] = value;
  }
}

function plistValue(path, key) {
  return run("/usr/libexec/PlistBuddy", ["-c", `Print :${key}`, path], {
    capture: true,
  });
}

function collectArchives(path) {
  if (!existsSync(path)) return [];
  const entries = readdirSync(path, { withFileTypes: true });
  const archives = [];
  for (const entry of entries) {
    const entryPath = join(path, entry.name);
    if (entry.isDirectory() && entry.name.endsWith(".xcarchive")) {
      archives.push(entryPath);
    }
  }
  return archives;
}

function newestArchive() {
  const archives = collectArchives(archiveRoot).sort(
    (a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs,
  );
  if (!archives.length) {
    fail(`no .xcarchive was found under ${archiveRoot}`);
  }
  return archives[0];
}

function archiveMetadata(archive) {
  const info = join(archive, "Info.plist");
  if (!existsSync(info)) fail(`archive has no Info.plist: ${archive}`);
  const metadata = {
    version: plistValue(
      info,
      "ApplicationProperties:CFBundleShortVersionString",
    ),
    build: plistValue(info, "ApplicationProperties:CFBundleVersion"),
  };
  const applicationPath = plistValue(
    info,
    "ApplicationProperties:ApplicationPath",
  );
  const appInfo = join(archive, "Products", applicationPath, "Info.plist");
  if (!existsSync(appInfo)) fail(`archive has no embedded app Info.plist: ${appInfo}`);
  const embedded = {
    version: plistValue(appInfo, "CFBundleShortVersionString"),
    build: plistValue(appInfo, "CFBundleVersion"),
  };
  if (
    metadata.version !== embedded.version ||
    metadata.build !== embedded.build
  ) {
    fail(
      `archive metadata says ${metadata.version} (${metadata.build}), but its embedded app says ${embedded.version} (${embedded.build}). Rebuild the archive before exporting it.`,
    );
  }
  return metadata;
}

function configuredReleaseMetadata() {
  const config = JSON.parse(readFileSync(tauriConfig, "utf8"));
  const version = config.version;
  const build = config.bundle?.iOS?.bundleVersion;
  const project = readFileSync(generatedProject, "utf8");
  const generatedBuild = project.match(
    /\bCFBundleVersion:\s*["']?([^\s"']+)/,
  )?.[1];
  if (!version || !build) {
    fail("could not read the configured release version/build number");
  }
  if (String(build) !== generatedBuild) {
    fail(
      `tauri.conf.json configures build ${build}, but generated project.yml configures ${generatedBuild ?? "no build number"}. Regenerate the iOS project before building.`,
    );
  }
  return { version: String(version), build: String(build) };
}

function findIpa(path) {
  if (!existsSync(path)) return null;
  return (
    readdirSync(path)
      .filter((name) => name.endsWith(".ipa"))
      .map((name) => join(path, name))[0] ?? null
  );
}

function ipaMetadata(ipa) {
  const entries = run("zipinfo", ["-1", ipa, "Payload/*.app/Info.plist"], {
    capture: true,
  }).split("\n");
  const infoEntry = entries.find(Boolean);
  if (!infoEntry) fail(`could not find the app Info.plist inside ${ipa}`);
  const plist = spawnSync("unzip", ["-p", ipa, infoEntry], {
    cwd: root,
    encoding: null,
  });
  if (plist.status !== 0) fail(`could not read app metadata from ${ipa}`);

  const extract = (key) =>
    run("plutil", ["-extract", key, "raw", "-o", "-", "-"], {
      capture: true,
      input: plist.stdout,
    });
  return {
    version: extract("CFBundleShortVersionString"),
    build: extract("CFBundleVersion"),
  };
}

function resolveApiKeyPath(keyId) {
  if (process.env.ASC_KEY_PATH) return resolve(process.env.ASC_KEY_PATH);
  const file = `AuthKey_${keyId}.p8`;
  const roots = [
    process.env.API_PRIVATE_KEYS_DIR,
    join(homedir(), ".appstoreconnect/private_keys"),
    join(homedir(), ".private_keys"),
    join(homedir(), "private_keys"),
    join(root, "private_keys"),
  ].filter(Boolean);
  return roots.map((dir) => join(dir, file)).find(existsSync) ?? null;
}

function authArgs() {
  loadLocalConfig();
  const keyId = process.env.ASC_KEY_ID;
  const issuerId = process.env.ASC_ISSUER_ID;
  if (!keyId || !issuerId) {
    fail(
      `App Store Connect credentials are not configured. Create ${localConfig} with ASC_KEY_ID and ASC_ISSUER_ID; see docs/testflight-cli.md.`,
    );
  }
  const keyPath = resolveApiKeyPath(keyId);
  if (!keyPath) {
    fail(
      `AuthKey_${keyId}.p8 was not found. Put it in ~/.appstoreconnect/private_keys or set ASC_KEY_PATH.`,
    );
  }
  return [
    "--api-key",
    keyId,
    "--api-issuer",
    issuerId,
    "--p8-file-path",
    keyPath,
  ];
}

function usage() {
  console.log(`Usage: pnpm testflight -- [options]

Exports the newest signed Xcode archive, validates it, and uploads it to
App Store Connect/TestFlight without opening Xcode.

Options:
  --archive PATH    Use a specific .xcarchive
  --ipa PATH        Reuse an already-exported IPA
  --export-only     Export and verify the IPA, but do not contact Apple
  --skip-validation
                    Upload without running altool validation first
  -h, --help        Show this help

Credentials are read from environment variables or .appstoreconnect.local.
See docs/testflight-cli.md for the one-time setup.`);
}

const args = process.argv.slice(2);
if (args.includes("--help") || args.includes("-h")) {
  usage();
  process.exit(0);
}

function option(name) {
  const index = args.indexOf(name);
  if (index === -1) return null;
  if (!args[index + 1] || args[index + 1].startsWith("--")) {
    fail(`${name} requires a path`);
  }
  return resolve(root, args[index + 1]);
}

const exportOnly = args.includes("--export-only");
const skipValidation = args.includes("--skip-validation");
let ipa = option("--ipa");

if (ipa && !existsSync(ipa)) fail(`IPA does not exist: ${ipa}`);

if (!ipa) {
  const archive = option("--archive") ?? newestArchive();
  if (!existsSync(archive)) fail(`archive does not exist: ${archive}`);
  const metadata = archiveMetadata(archive);
  const configured = configuredReleaseMetadata();
  if (
    metadata.version !== configured.version ||
    metadata.build !== configured.build
  ) {
    fail(
      `archive is ${metadata.version} (${metadata.build}), but the release configuration is ${configured.version} (${configured.build}). Rebuild, or use --ipa to intentionally retry an already-exported binary.`,
    );
  }
  const exportPath = join(
    root,
    "artifacts/testflight",
    `${metadata.version}-${metadata.build}`,
  );
  ipa = findIpa(exportPath);

  console.log(
    `Using ${basename(archive)} (version ${metadata.version}, build ${metadata.build})`,
  );
  if (ipa) {
    console.log(`Reusing ${ipa}`);
  } else {
    console.log(`Exporting signed IPA to ${exportPath}`);
    run("xcodebuild", [
      "-exportArchive",
      "-archivePath",
      archive,
      "-exportPath",
      exportPath,
      "-exportOptionsPlist",
      exportOptions,
    ]);
    ipa = findIpa(exportPath);
    if (!ipa) fail(`Xcode reported success but no IPA exists in ${exportPath}`);
  }
}

const metadata = ipaMetadata(ipa);
console.log(`Verified ${ipa} (version ${metadata.version}, build ${metadata.build})`);

if (exportOnly) {
  console.log("Export complete; upload was intentionally skipped.");
  process.exit(0);
}

const authentication = authArgs();
if (!skipValidation) {
  console.log("Validating with App Store Connect...");
  run("xcrun", [
    "altool",
    "--validate-app",
    "-f",
    ipa,
    ...authentication,
    "--output-format",
    "json",
  ]);
}

console.log("Uploading to App Store Connect/TestFlight...");
run("xcrun", [
  "altool",
  "--upload-app",
  "-f",
  ipa,
  ...authentication,
  "--show-progress",
  "--output-format",
  "json",
]);
console.log(
  `Upload accepted for version ${metadata.version}, build ${metadata.build}. Apple will process it before it appears in TestFlight.`,
);
