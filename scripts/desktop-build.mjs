import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

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
  // Local builds should not depend on an unlocked Developer ID private key.
  // Tauri treats `-` as an ad-hoc macOS signing identity. An explicitly
  // supplied identity still opts into distribution signing.
  ...(process.platform === "darwin"
    ? { APPLE_SIGNING_IDENTITY: process.env.APPLE_SIGNING_IDENTITY ?? "-" }
    : {}),
};

execFileSync("node", ["scripts/verify-platform-config.mjs"], {
  cwd: process.cwd(),
  stdio: "inherit",
});

execFileSync("node", ["scripts/verify-updater-key.mjs"], {
  cwd: process.cwd(),
  env: environment,
  stdio: "inherit",
});

if (process.platform === "darwin" && environment.APPLE_SIGNING_IDENTITY === "-") {
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
    "Using ad-hoc macOS signing without notarization for this local build. Set APPLE_SIGNING_IDENTITY to create a distribution-signed build.",
  );
}

execFileSync("pnpm", ["exec", "tauri", "build", ...process.argv.slice(2)], {
  env: environment,
  stdio: "inherit",
});

if (process.platform === "darwin") {
  execFileSync("node", ["scripts/verify-macos-build.mjs"], {
    cwd: process.cwd(),
    stdio: "inherit",
  });
}
