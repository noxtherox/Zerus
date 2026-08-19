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
};

execFileSync("pnpm", ["exec", "tauri", "build", ...process.argv.slice(2)], {
  env: environment,
  stdio: "inherit",
});
