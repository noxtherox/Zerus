import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseDocument } from "yaml";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const clientId = process.argv[2];
if (!clientId || !/^\d+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$/.test(clientId)) {
  throw new Error("Usage: node scripts/configure-google-drive-ios.mjs YOUR_IOS_CLIENT_ID.apps.googleusercontent.com");
}
const scheme = clientId.split(".").reverse().join(".");
const projectPath = join(root, "src-tauri/gen/apple/project.yml");
if (existsSync(projectPath)) {
  const project = parseDocument(readFileSync(projectPath, "utf8"));
  if (project.errors.length) throw new Error("Could not parse the iOS project configuration.");
  const properties = ["targets", "app_iOS", "info", "properties"];
  const existing = project.getIn([...properties, "CFBundleURLTypes"]);
  const types = (existing?.toJSON() ?? []).filter((type) => type.CFBundleURLName !== "com.zerus.notes.google-drive");
  types.push({ CFBundleURLName: "com.zerus.notes.google-drive", CFBundleURLSchemes: [scheme] });
  project.setIn([...properties, "CFBundleURLTypes"], types);
  project.setIn([...properties, "ZerusGoogleDriveClientID"], clientId);
  writeFileSync(projectPath, project.toString({ lineWidth: 0, flowCollectionPadding: false }));
  console.log("Configured Google Drive in the iOS project generator");
}
const temporary = mkdtempSync(join(tmpdir(), "zerus-google-ios-"));
try {
  for (const relative of ["src-tauri/Info.ios.plist", "src-tauri/gen/apple/app_iOS/Info.plist"]) {
    const path = join(root, relative);
    if (!existsSync(path)) continue;
    const json = join(temporary, "Info.json");
    execFileSync("plutil", ["-convert", "json", "-o", json, path]);
    const plist = JSON.parse(readFileSync(json, "utf8"));
    plist.ZerusGoogleDriveClientID = clientId;
    plist.CFBundleURLTypes = (plist.CFBundleURLTypes ?? []).filter((type) => type.CFBundleURLName !== "com.zerus.notes.google-drive");
    plist.CFBundleURLTypes.push({ CFBundleURLName: "com.zerus.notes.google-drive", CFBundleURLSchemes: [scheme] });
    writeFileSync(json, JSON.stringify(plist));
    execFileSync("plutil", ["-convert", "xml1", "-o", path, json]);
    execFileSync("plutil", ["-lint", path]);
    console.log(`Configured Google Drive in ${relative}`);
  }
} finally { rmSync(temporary, { recursive: true, force: true }); }
