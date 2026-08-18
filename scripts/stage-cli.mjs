import { chmod, copyFile, mkdir } from "node:fs/promises";
import { join } from "node:path";

const windows = process.platform === "win32";
const executable = windows ? "zerus.exe" : "zerus";
const source = join("src-tauri", "target", "release", executable);
const directory = join("src-tauri", "binaries");
const destination = join(directory, executable);

await mkdir(directory, { recursive: true });
await copyFile(source, destination);
if (!windows) await chmod(destination, 0o755);
console.log(`Staged ${destination}`);
