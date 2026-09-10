import { execFileSync } from "node:child_process";
import { copyFileSync, mkdtempSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const output = mkdtempSync(join(tmpdir(), "zerus-windows-icons-"));
try {
  execFileSync(process.execPath, [
    join(root, "node_modules/@tauri-apps/cli/tauri.js"),
    "icon", join(root, "src-tauri/icons/windows-icon.svg"), "--output", output,
  ], { cwd: root, stdio: "inherit" });
  // Tauri generates every platform: install only Windows resources.
  for (const name of readdirSync(output)) {
    if (name === "icon.ico" || name === "StoreLogo.png" || /^Square\d+x\d+Logo\.png$/.test(name)) {
      copyFileSync(join(output, name), join(root, "src-tauri/icons", name));
    }
  }
} finally {
  rmSync(output, { recursive: true, force: true });
}
