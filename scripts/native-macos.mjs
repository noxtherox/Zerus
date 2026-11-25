#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseDeveloperIdApplications, resolveSigningIdentity, resolveNotaryCredentials } from './macos-release-utils.mjs';
import { verifyNativeMacApp, verifyNativeMacDmg } from './native-macos-artifact.mjs';
import { prepareNativeCLI } from './native-macos-cli.mjs';
import { prepareNativeIcons } from './native-macos-icons.mjs';
import { loadNativeUpdateChannel, nativeUpdateBuildSettings, signNativeMacApp } from './native-macos-updates.mjs';

if (process.platform !== 'darwin') throw new Error('The native macOS app must be built on macOS.');
const action = process.argv[2] ?? 'build';
const local = process.argv.includes('--local');
const production = (action === 'dmg' && !local) || action === 'channel';
const hasUpdateOverride = process.env.ZERUS_NATIVE_UPDATE_FEED_URL !== undefined || process.env.ZERUS_NATIVE_UPDATE_PUBLIC_KEY !== undefined;
const channel = production && !hasUpdateOverride ? loadNativeUpdateChannel(resolve('native-macos/update-channel.json')) : undefined;
const updateSettings = nativeUpdateBuildSettings(process.env, { required: production, channel });
if (action === 'channel') {
  console.log(JSON.stringify({ source: channel ? 'native-macos/update-channel.json' : 'explicit environment', settings: updateSettings }, null, 2));
  process.exit(0);
}
const output = resolve('artifacts/native-macos');
const derived = resolve(output, 'DerivedData');
const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit' });
mkdirSync(output, { recursive: true });
run('xcode-select', ['-p']);
run('xcodebuild', ['-version']);
prepareNativeCLI();
await prepareNativeIcons();
run('xcodegen', ['generate', '--spec', 'native-macos/project.yml']);
const common = ['-project', 'native-macos/ZerusMac.xcodeproj', '-scheme', 'ZerusMac', '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', derived, 'CODE_SIGNING_ALLOWED=NO', 'ARCHS=arm64', ...updateSettings];
if (action === 'test') { run('xcodebuild', [...common, '-configuration', 'Debug', 'test']); process.exit(0); }
if (!['build', 'dmg'].includes(action)) throw new Error('Use build, test or dmg.');
// Fail before expensive packaging if distribution credentials are incomplete.
let identity = '-', credentials;
if (action === 'dmg' && !local) {
  const installed = execFileSync('security', ['find-identity', '-v', '-p', 'codesigning'], { encoding: 'utf8' });
  identity = resolveSigningIdentity(process.env.APPLE_SIGNING_IDENTITY, parseDeveloperIdApplications(installed));
  credentials = resolveNotaryCredentials(process.env);
  if (credentials.kind === 'App Store Connect API key' && !existsSync(process.env.APPLE_API_KEY_PATH)) throw new Error('APPLE_API_KEY_PATH does not exist.');
}
run('xcodebuild', [...common, '-configuration', 'Release', 'build']);
const built = resolve(derived, 'Build/Products/Release/Zerus.app');
if (action === 'build') { console.log(`Native app: ${built}`); process.exit(0); }
const staging = resolve(output, 'dmg-staging');
rmSync(staging, { recursive: true, force: true }); mkdirSync(staging, { recursive: true });
const app = resolve(staging, 'Zerus.app');
run('ditto', [built, app]);
rmSync(resolve(app, 'Contents/Resources/CLI'), { recursive: true, force: true });
run('ditto', ['native-macos/Resources/CLI', resolve(app, 'Contents/Resources/CLI')]);
mkdirSync(resolve(app, 'Contents/Resources'), { recursive: true });
copyFileSync('src-tauri/icons/icon.icns', resolve(app, 'Contents/Resources/Zerus.icns'));
run('/usr/libexec/PlistBuddy', ['-c', 'Add :CFBundleIconFile string Zerus', resolve(app, 'Contents/Info.plist')]);
signNativeMacApp(app, identity, local);
run('codesign', ['--verify', '--deep', '--strict', '--verbose=2', app]);
const appReceipt = verifyNativeMacApp(app, { local });
const plist = execFileSync('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleShortVersionString', resolve(app, 'Contents/Info.plist')], { encoding: 'utf8' }).trim();
symlinkSync('/Applications', resolve(staging, 'Applications'));
const buildNumber = execFileSync('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleVersion', resolve(app, 'Contents/Info.plist')], { encoding: 'utf8' }).trim();
const dmg = resolve(output, `Zerus-${plist}-${buildNumber}-arm64${local ? '-local' : ''}.dmg`);
const receipt = resolve(output, `artifact-${buildNumber}${local ? '-local' : ''}.json`);
const candidate = resolve(output, `.Zerus-${plist}-${buildNumber}${local ? '-local' : ''}.pending.dmg`);
rmSync(receipt, { force: true });
rmSync(receipt + '.pending', { force: true });
rmSync(candidate, { force: true });
run('hdiutil', ['create', '-volname', 'Zerus', '-srcfolder', staging, '-ov', '-format', 'UDZO', candidate]);
run('hdiutil', ['verify', candidate]);
if (!local) {
  run('codesign', ['--force', '--sign', identity, '--timestamp', candidate]);
  rmSync(resolve(output, `notarization-${buildNumber}.json`), { force: true });
  const submitted = execFileSync('xcrun', ['notarytool', 'submit', candidate, ...credentials.args, '--wait', '--output-format', 'json'], { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  writeFileSync(resolve(output, `notarization-${buildNumber}.json`), submitted);
  const result = JSON.parse(submitted);
  if (result.status !== 'Accepted') throw new Error(`Notarization ${result.status}. Submission: ${result.id}. See artifacts/native-macos/notarization-${buildNumber}.json.`);
  run('xcrun', ['stapler', 'staple', candidate]);
  run('xcrun', ['stapler', 'validate', candidate]);
  run('spctl', ['--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', candidate]);
}
const mountedReceipt = verifyNativeMacDmg(candidate, { local });
if (mountedReceipt.executableSha256 !== appReceipt.executableSha256) throw new Error('DMG executable differs from the verified staging app.');
writeFileSync(receipt + '.pending', JSON.stringify({
  ...mountedReceipt,
  source: { head: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(), workingTreeDirty: execFileSync('git', ['status', '--porcelain'], { encoding: 'utf8' }).trim().length > 0, exactSourceSnapshotRecorded: false },
  dmg: { name: dmg.split('/').at(-1), sha256: createHash('sha256').update(readFileSync(candidate)).digest('hex') },
  notarization: local ? 'not-submitted' : 'accepted-and-stapled',
  installedUIVerification: 'not-performed-by-packager',
}, null, 2) + '\n');
renameSync(candidate, dmg);
renameSync(receipt + '.pending', receipt);
console.log(`DMG: ${dmg}`);
