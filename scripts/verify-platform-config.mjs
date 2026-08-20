#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const readJson = (path) =>
  JSON.parse(readFileSync(resolve(root, path), "utf8"));
const fail = (message) => {
  throw new Error(`Platform configuration check failed: ${message}`);
};

const shared = readJson("src-tauri/tauri.conf.json");
const macOS = readJson("src-tauri/tauri.macos.conf.json");
const iOS = readJson("src-tauri/tauri.ios.conf.json");
const windows = readJson("src-tauri/tauri.windows.conf.json");

if (shared.build?.beforeBuildCommand !== "pnpm build") {
  fail("the shared build hook must remain platform-neutral");
}
if (shared.bundle?.macOS || shared.bundle?.windows || shared.bundle?.resources) {
  fail("desktop bundle settings must live in platform-specific overlays");
}
if (macOS.build?.beforeBuildCommand !== "pnpm build && pnpm cli:bundle && pnpm macos:sign-binaries") {
  fail("the macOS overlay must own CLI bundling and helper signing");
}
if (macOS.bundle?.macOS?.entitlements !== "entitlements.macos.plist") {
  fail("macOS must use entitlements.macos.plist");
}
if (!macOS.bundle?.resources?.includes("binaries/*")) {
  fail("the macOS overlay must bundle desktop helper binaries");
}
if (iOS.build?.beforeBuildCommand !== "pnpm build") {
  fail("the iOS overlay must not run desktop build hooks");
}
if (!Array.isArray(iOS.bundle?.resources) || iOS.bundle.resources.length !== 0) {
  fail("the iOS overlay must not bundle desktop helper binaries");
}
if (windows.build?.beforeBuildCommand !== "pnpm build && pnpm cli:bundle") {
  fail("the Windows overlay must own CLI bundling without macOS signing");
}
if (!windows.bundle?.resources?.includes("binaries/*")) {
  fail("the Windows overlay must bundle desktop helper binaries");
}

const macEntitlements = readFileSync(
  resolve(root, "src-tauri/entitlements.macos.plist"),
  "utf8",
);
const iOSEntitlements = readFileSync(
  resolve(root, "src-tauri/gen/apple/app_iOS/app_iOS.entitlements"),
  "utf8",
);

for (const forbidden of [
  "keychain-access-groups",
  "application-identifier",
  "com.apple.developer.team-identifier",
]) {
  if (macEntitlements.includes(`<key>${forbidden}</key>`)) {
    fail(`${forbidden} belongs in mobile provisioning, not macOS entitlements`);
  }
}
if (!iOSEntitlements.includes("<key>keychain-access-groups</key>")) {
  fail("the iOS entitlement file must retain its keychain access group");
}

console.log("Platform configuration boundaries verified.");
