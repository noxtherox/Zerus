import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import {
  parseDeveloperIdApplications,
  resolveNotaryCredentials,
  resolveSigningIdentity,
} from "./macos-release-utils.mjs";
import { notarizeNewestMacosDmg } from "./notarize-macos-dmg.mjs";

const localBuild = process.argv.includes("--local");
const tauriArgs = process.argv
  .slice(2)
  .filter((argument) => argument !== "--local");
const releaseBuild = process.platform === "darwin" && !localBuild;
const buildStartedAt = Date.now();

const keyPath = join(homedir(), ".tauri", "zerus-updater.key");

let privateKey;
try {
  privateKey = readFileSync(keyPath, "utf8").trim();
} catch {
  console.error(`Updater signing key not found at ${keyPath}`);
  console.error("Restore the key before building updater artifacts.");
  process.exit(1);
}

if (!privateKey) {
  console.error(`Updater signing key is empty: ${keyPath}`);
  process.exit(1);
}

const environment = {
  ...process.env,
  CI: process.env.CI ?? "true",
  TAURI_SIGNING_PRIVATE_KEY: privateKey,
  TAURI_SIGNING_PRIVATE_KEY_PASSWORD:
    process.env.TAURI_SIGNING_PRIVATE_KEY_PASSWORD ?? "",
  ...(process.platform === "darwin"
    ? { APPLE_SIGNING_IDENTITY: process.env.APPLE_SIGNING_IDENTITY }
    : {}),
};

let notaryCredentials;
if (releaseBuild) {
  const identityOutput = execFileSync(
    "security",
    ["find-identity", "-v", "-p", "codesigning"],
    { encoding: "utf8" },
  );
  environment.APPLE_SIGNING_IDENTITY = resolveSigningIdentity(
    process.env.APPLE_SIGNING_IDENTITY,
    parseDeveloperIdApplications(identityOutput),
  );
  notaryCredentials = resolveNotaryCredentials(environment);
  console.log(
    `Release signing identity: ${environment.APPLE_SIGNING_IDENTITY}`,
  );
  console.log(`Notarization authentication: ${notaryCredentials.kind}`);
} else if (process.platform === "darwin") {
  if (process.env.APPLE_SIGNING_IDENTITY) {
    throw new Error(
      "Do not set APPLE_SIGNING_IDENTITY with --local; local builds are explicitly ad-hoc.",
    );
  }
  environment.APPLE_SIGNING_IDENTITY = "-";
}

execFileSync("node", ["scripts/verify-platform-config.mjs"], {
  cwd: process.cwd(),
  stdio: "inherit",
});

execFileSync("node", ["scripts/verify-updater-key.mjs"], {
  cwd: process.cwd(),
  env: environment,
  stdio: "inherit",
});

if (process.platform === "darwin" && localBuild) {
  // Tauri automatically notarizes whenever Apple credentials are present.
  // An ad-hoc build cannot be notarized, so keep ambient release credentials
  // out of the local build instead of submitting an artifact Apple will reject.
  for (const name of [
    "APPLE_API_ISSUER",
    "APPLE_API_KEY",
    "APPLE_API_KEY_PATH",
    "APPLE_ID",
    "APPLE_PASSWORD",
    "APPLE_TEAM_ID",
  ]) {
    delete environment[name];
  }

  console.log(
    "Using explicitly requested ad-hoc macOS signing without notarization.",
  );
}

execFileSync("pnpm", ["exec", "tauri", "build", ...tauriArgs], {
  env: environment,
  stdio: "inherit",
});

if (process.platform === "darwin") {
  if (releaseBuild) {
    notarizeNewestMacosDmg(environment, buildStartedAt - 5_000);
  }

  execFileSync(
    "node",
    [
      "scripts/verify-macos-build.mjs",
      ...(releaseBuild ? ["--require-notarized"] : []),
    ],
    {
      cwd: process.cwd(),
      stdio: "inherit",
    },
  );
}
