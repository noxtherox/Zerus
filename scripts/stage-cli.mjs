import { execFile } from "node:child_process";
import { chmod, copyFile, mkdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";

const windows = process.platform === "win32";
const executable = windows ? "zerus.exe" : "zerus";
const source = join("src-tauri", "target", "release", executable);
const directory = join("src-tauri", "binaries");
const destination = join(directory, executable);
const manifest = await readFile(join("src-tauri", "crates", "zerus-cli", "Cargo.toml"), "utf8");
const expectedVersion = manifest.match(/^version\s*=\s*"([^"]+)"/m)?.[1];
if (!expectedVersion) throw new Error("Could not read the Zerus CLI version");
const { stdout } = await promisify(execFile)(source, ["--version"]);
if (stdout.trim() !== `zerus ${expectedVersion}`) {
  throw new Error(`CLI binary is stale: expected zerus ${expectedVersion}, received ${stdout.trim()}`);
}

await mkdir(directory, { recursive: true });
await copyFile(source, destination);
if (!windows) await chmod(destination, 0o755);
console.log(`Staged ${destination} (${expectedVersion})`);
