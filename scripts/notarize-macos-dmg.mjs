#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { resolveNotaryCredentials } from "./macos-release-utils.mjs";

export function findNewestMacosDmg(minimumMtime = 0) {
  const config = JSON.parse(
    readFileSync(resolve("src-tauri/tauri.conf.json"), "utf8"),
  );
  const targetRoot = resolve("src-tauri/target");
  const bundleRoots = [resolve(targetRoot, "release/bundle")];
  if (existsSync(targetRoot)) {
    for (const entry of readdirSync(targetRoot, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        bundleRoots.push(resolve(targetRoot, entry.name, "release/bundle"));
      }
    }
  }

  const candidates = bundleRoots.flatMap((bundleRoot) => {
    const directory = resolve(bundleRoot, "dmg");
    return existsSync(directory)
      ? readdirSync(directory)
          .filter(
            (name) =>
              name.startsWith(`${config.productName}_${config.version}_`) &&
              name.endsWith(".dmg"),
          )
          .map((name) => resolve(directory, name))
          .filter((path) => statSync(path).mtimeMs >= minimumMtime)
      : [];
  });

  if (candidates.length === 0) {
    throw new Error("No matching newly built macOS DMG was found.");
  }
  return candidates.sort(
    (left, right) => statSync(right).mtimeMs - statSync(left).mtimeMs,
  )[0];
}

export function notarizeNewestMacosDmg(environment, minimumMtime = 0) {
  const credentials = resolveNotaryCredentials(environment);
  if (
    credentials.kind === "App Store Connect API key" &&
    !existsSync(environment.APPLE_API_KEY_PATH)
  ) {
    throw new Error(
      `APPLE_API_KEY_PATH does not exist: ${environment.APPLE_API_KEY_PATH}`,
    );
  }

  const dmgPath = findNewestMacosDmg(minimumMtime);
  console.log(`Submitting DMG for notarization: ${dmgPath}`);
  execFileSync(
    "xcrun",
    ["notarytool", "submit", dmgPath, ...credentials.args, "--wait"],
    { stdio: "inherit" },
  );
  execFileSync("xcrun", ["stapler", "staple", dmgPath], {
    stdio: "inherit",
  });
  return dmgPath;
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
  if (process.platform !== "darwin") {
    throw new Error("DMG notarization must run on macOS.");
  }
  notarizeNewestMacosDmg(process.env);
}
