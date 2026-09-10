import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const xml = (value) => String(value).replace(/[<>&"']/g, (character) => ({
  "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;", "'": "&apos;",
})[character]);

export function storeIdentity(env, development = false) {
  const keys = ["MS_STORE_IDENTITY_NAME", "MS_STORE_PUBLISHER", "MS_STORE_PUBLISHER_DISPLAY_NAME"];
  const values = keys.map((key) => env[key]?.trim());
  if (values.some(Boolean) && !values.every(Boolean)) {
    throw new Error(`Set all three Store identity values: ${keys.join(", ")}`);
  }
  if (!values.every(Boolean)) {
    if (!development) throw new Error(`Missing Partner Center identity: ${keys.join(", ")}. See docs/WINDOWS.md.`);
    return { name: "Zerus.Development", publisher: "CN=Zerus Development", displayName: "Zerus Development" };
  }
  if (!/^[A-Za-z0-9.-]{3,50}$/.test(values[0])) throw new Error("Invalid MS_STORE_IDENTITY_NAME");
  if (!values[1].startsWith("CN=")) throw new Error("MS_STORE_PUBLISHER must be the Partner Center distinguished name starting with CN=");
  return { name: values[0], publisher: values[1], displayName: values[2] };
}

export function msixVersion(version) {
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)) throw new Error("MSIX requires a stable major.minor.patch version");
  if (version.split(".").some((part) => Number(part) > 65535)) throw new Error("MSIX version components must fit in 16 bits");
  const [major, minor, patch] = version.split(".").map(Number);
  // Store major versions cannot be zero. Offset every major, including 1.x+,
  // so future app versions always sort above existing Store packages.
  if (major >= 65535) throw new Error("MSIX major offset must fit in 16 bits");
  return `${major + 1}.${minor}.${patch}.0`;
}

export function manifest(version, identity) {
  return `<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
 xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
 xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
 IgnorableNamespaces="uap rescap">
 <Identity Name="${xml(identity.name)}" Publisher="${xml(identity.publisher)}" Version="${msixVersion(version)}" ProcessorArchitecture="x64" />
 <Properties>
  <DisplayName>Zerus</DisplayName>
  <PublisherDisplayName>${xml(identity.displayName)}</PublisherDisplayName>
  <Description>Local-first Markdown notes, links, and files you own.</Description>
  <Logo>Assets\\StoreLogo.png</Logo>
 </Properties>
 <Resources><Resource Language="en-US" /></Resources>
 <Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" /></Dependencies>
 <Applications>
  <Application Id="Zerus" Executable="Zerus.exe" EntryPoint="Windows.FullTrustApplication">
   <uap:VisualElements DisplayName="Zerus" Description="Local-first Markdown notes" BackgroundColor="transparent"
    Square150x150Logo="Assets\\Square150x150Logo.png" Square44x44Logo="Assets\\Square44x44Logo.png" />
  </Application>
 </Applications>
 <Capabilities><rescap:Capability Name="runFullTrust" /></Capabilities>
</Package>
`;
}

function main() {
  const development = process.argv.includes("--development");
  const identity = storeIdentity(process.env, development);
  const config = JSON.parse(readFileSync(join(root, "src-tauri/tauri.conf.json"), "utf8"));
  msixVersion(config.version);
  if (process.platform !== "win32" || process.arch !== "x64") throw new Error("Build MSIX on x64 Windows with the Windows SDK installed.");
  // Compile a separate Store frontend, with in-app updates disabled.
  execFileSync("cmd.exe", ["/d", "/s", "/c", "pnpm exec tauri build --no-bundle"], {
    cwd: root, stdio: "inherit", env: { ...process.env, VITE_DISTRIBUTION: "ms-store" },
  });
  const release = join(root, "src-tauri/target/release");
  const output = join(release, "bundle/msix");
  const staging = join(output, "staging");
  rmSync(output, { recursive: true, force: true });
  mkdirSync(join(staging, "Assets"), { recursive: true });
  mkdirSync(join(staging, "binaries"), { recursive: true });
  // Cargo's desktop target is named app; the CLI helper is zerus.exe.
  copyFileSync(join(release, `${config.mainBinaryName ?? "app"}.exe`), join(staging, "Zerus.exe"));
  copyFileSync(join(root, "src-tauri/binaries/zerus.exe"), join(staging, "binaries/zerus.exe"));
  for (const file of readdirSync(release).filter((file) => file.toLowerCase().endsWith(".dll"))) {
    copyFileSync(join(release, file), join(staging, file));
  }
  for (const file of ["StoreLogo.png", "Square150x150Logo.png", "Square44x44Logo.png"]) {
    copyFileSync(join(root, "src-tauri/icons", file), join(staging, "Assets", file));
  }
  writeFileSync(join(staging, "AppxManifest.xml"), manifest(config.version, identity));
  const artifact = join(output, `Zerus_${config.version}_x64${development ? "_development" : "_store"}.msix`);
  execFileSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", join(root, "scripts/pack-msix.ps1"), "-Staging", staging, "-Output", artifact], { stdio: "inherit" });
  console.log(`Unsigned MSIX: ${artifact}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
