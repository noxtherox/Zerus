import { chmod, cp, mkdir, readdir, rm } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";
import process from "node:process";

if (process.platform !== "darwin") process.exit(0);

const root = process.cwd();
const packageDir = path.join(root, "src-mlx");
const outputDir = path.join(root, "src-tauri", "vendor", "mlx");
const derivedDataDir = path.join(packageDir, ".xcode-build");
const build = spawnSync(
  "xcodebuild",
  [
    "-quiet",
    "-scheme",
    "ZerusMLX",
    "-destination",
    "platform=macOS,arch=arm64",
    "-configuration",
    "Release",
    "-derivedDataPath",
    derivedDataDir,
    "-skipPackagePluginValidation",
    "-skipMacroValidation",
    "build",
  ],
  { cwd: packageDir, stdio: "inherit" },
);
if (build.status !== 0) process.exit(build.status ?? 1);

const binaryPath = path.join(derivedDataDir, "Build", "Products", "Release");

async function makeWritable(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      await chmod(entryPath, 0o755);
      await makeWritable(entryPath);
    } else {
      await chmod(entryPath, entry.name === "zerus-mlx" ? 0o755 : 0o644);
    }
  }
}

await rm(outputDir, { recursive: true, force: true });
await mkdir(outputDir, { recursive: true });
await cp(path.join(binaryPath, "ZerusMLX"), path.join(outputDir, "zerus-mlx"));
for (const entry of await readdir(binaryPath, { withFileTypes: true })) {
  if (entry.isDirectory() && entry.name.endsWith(".bundle")) {
    await cp(path.join(binaryPath, entry.name), path.join(outputDir, entry.name), {
      recursive: true,
    });
  }
}
await makeWritable(outputDir);

console.log(`Staged ${path.relative(root, path.join(outputDir, "zerus-mlx"))}`);
