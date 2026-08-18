#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

if (process.platform !== "darwin") {
  console.log("Skipping macOS helper signing on this platform.");
  process.exit(0);
}

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const config = JSON.parse(
  readFileSync(resolve(root, "src-tauri/tauri.conf.json"), "utf8"),
);
const identity =
  process.env.APPLE_SIGNING_IDENTITY ??
  config.bundle?.macOS?.signingIdentity;

if (!identity) {
  console.log("Skipping macOS helper signing: no signing identity configured.");
  process.exit(0);
}

const binaries = [
  resolve(root, "src-tauri/binaries/zerus"),
  resolve(root, "src-tauri/vendor/mlx/zerus-mlx"),
];

for (const binary of binaries) {
  if (!existsSync(binary)) {
    throw new Error(`Required macOS helper binary is missing: ${binary}`);
  }

  const args = ["--force", "--sign", identity];
  if (identity !== "-") {
    args.push("--timestamp", "--options", "runtime");
  }
  args.push(binary);

  execFileSync("codesign", args, { stdio: "inherit" });
  execFileSync(
    "codesign",
    ["--verify", "--strict", "--verbose=2", binary],
    { stdio: "inherit" },
  );
}

console.log(`Signed ${binaries.length} macOS helper binaries with ${identity}.`);
