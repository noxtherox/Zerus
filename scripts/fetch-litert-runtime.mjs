import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const VERSION = "0.15.0";
const ARCHIVE_SHA256 = "d23cf189ce8f6bb2556c0a023805e245d1ec862434e501eb60f353488033c1b5";
const DYLIB_SHA256 = "11967ad0aeaa9efe66bc08b15881a7342cff52f5f54d6bd0b2bb68b7264a639e";
const SIGNED_DYLIB_SHA256 = "26c4899d600a6074bd15ac27ab30ea9e82e7f742def53bedb2f0be1474b11956";
const LICENSE_SHA256 = "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4";
const URL = `https://github.com/google-ai-edge/LiteRT-LM/releases/download/v${VERSION}/CLiteRTLM_mac.xcframework.zip`;
const LICENSE_URL = `https://raw.githubusercontent.com/google-ai-edge/LiteRT-LM/v${VERSION}/LICENSE`;
const destination = join(import.meta.dirname, "..", "src-tauri", "vendor", "litert-lm", "libCLiteRTLM_mac.dylib");
const licenseDestination = join(import.meta.dirname, "..", "src-tauri", "vendor", "litert-lm", "LICENSE.txt");

function sha256(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

if (process.platform !== "darwin") process.exit(0);
let runtimeDigest = existsSync(destination) ? sha256(destination) : null;
if (runtimeDigest === DYLIB_SHA256) {
  execFileSync("codesign", ["--force", "--sign", "-", destination]);
  runtimeDigest = sha256(destination);
}
const runtimeReady = runtimeDigest === SIGNED_DYLIB_SHA256;
const licenseReady = existsSync(licenseDestination) && sha256(licenseDestination) === LICENSE_SHA256;
if (runtimeReady && licenseReady) {
  chmodSync(destination, 0o644);
  process.exit(0);
}

const work = join(tmpdir(), `zerus-litert-${process.pid}`);
const archive = join(work, "runtime.zip");
const unpacked = join(work, "unpacked");
const universal = join(unpacked, "CLiteRTLM_mac.xcframework", "macos-arm64_x86_64", "libCLiteRTLM_mac.dylib");
const thinned = join(work, "libCLiteRTLM_mac.dylib");

rmSync(work, { recursive: true, force: true });
mkdirSync(unpacked, { recursive: true });
try {
  mkdirSync(join(import.meta.dirname, "..", "src-tauri", "vendor", "litert-lm"), { recursive: true });
  if (!runtimeReady) {
    console.log(`Downloading LiteRT-LM runtime v${VERSION}…`);
    execFileSync("curl", ["-fL", "--retry", "3", URL, "-o", archive], { stdio: "inherit" });
    if (sha256(archive) !== ARCHIVE_SHA256) throw new Error("LiteRT-LM archive checksum mismatch");
    execFileSync("unzip", ["-q", archive, "-d", unpacked]);
    execFileSync("lipo", ["-thin", "arm64", universal, "-output", thinned]);
    if (sha256(thinned) !== DYLIB_SHA256) throw new Error("LiteRT-LM runtime checksum mismatch");
    renameSync(thinned, destination);
    chmodSync(destination, 0o644);
    execFileSync("xattr", ["-c", destination]);
    execFileSync("codesign", ["--force", "--sign", "-", destination]);
    if (sha256(destination) !== SIGNED_DYLIB_SHA256) throw new Error("LiteRT-LM signed runtime checksum mismatch");
  }
  if (!licenseReady) {
    execFileSync("curl", ["-fsSL", LICENSE_URL, "-o", licenseDestination]);
    if (sha256(licenseDestination) !== LICENSE_SHA256) throw new Error("LiteRT-LM license checksum mismatch");
  }
  console.log("LiteRT-LM runtime is ready.");
} finally {
  rmSync(work, { recursive: true, force: true });
}
