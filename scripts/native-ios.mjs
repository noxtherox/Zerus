import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const action = args.shift() ?? 'build';
const option = (name) => { const index = args.indexOf(name); return index < 0 ? undefined : args[index + 1]; };
const device = option('--device');
const simulator = option('--simulator');
const derived = path.join(root, 'artifacts/native-ios', simulator ? 'simulator' : 'device');
const configuration = simulator ? 'Debug' : 'Release';
const app = path.join(derived, 'Build/Products', `${configuration}-${simulator ? 'iphonesimulator' : 'iphoneos'}`, 'ZerusNative.app');
function run(command, argv, capture = false) {
  const result = spawnSync(command, argv, { cwd: root, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(capture ? result.stderr || result.stdout : `${command} failed (${result.status}).`);
  return result.stdout;
}
function verifyApp() {
  if (!existsSync(app)) throw new Error(`No native build exists at ${app}. Run pnpm ios:native:build first.`);
  run('codesign', ['--verify', '--deep', '--strict', app]);
  const plist = JSON.parse(run('plutil', ['-convert', 'json', '-o', '-', path.join(app, 'Info.plist')], true));
  if (plist.CFBundleIdentifier !== 'com.zerus.notes.native' || plist.UIApplicationSceneManifest?.UIApplicationSupportsMultipleScenes !== true) {
    throw new Error('The native app has an unexpected identity or missing SwiftUI scene lifecycle.');
  }
  if (device) {
    const xml = run('security', ['cms', '-D', '-i', path.join(app, 'embedded.mobileprovision')], true);
    const converted = spawnSync('plutil', ['-extract', 'ProvisionedDevices', 'json', '-o', '-', '-'], { input: xml, encoding: 'utf8' });
    if (converted.status !== 0) throw new Error('Could not inspect the native provisioning profile.');
    const provisionedDevices = JSON.parse(converted.stdout);
    if (!provisionedDevices.includes(device)) {
      throw new Error(`This iPhone is not in the signed profile. Run pnpm ios:native:build --device ${device}.`);
    }
  }
  console.log(`Verified native SwiftUI app: ${app}`);
}
try {
  if (!['build', 'test', 'install'].includes(action)) throw new Error('Usage: native-ios.mjs build | test --simulator <UDID> | install --device <UDID>');
  if (action === 'install') {
    if (!device) throw new Error('Specify the intended physical iPhone with --device <UDID>.');
    verifyApp();
    const output = path.join(root, 'artifacts/native-ios/device-details.json');
    mkdirSync(path.dirname(output), { recursive: true });
    run('xcrun', ['devicectl', 'device', 'info', 'details', '--device', device, '--timeout', '15', '--json-output', output], true);
    const details = JSON.parse(readFileSync(output, 'utf8')).result;
    const state = details.properties ?? details.deviceProperties;
    if (JSON.stringify(state).toLowerCase().includes('"developermodestatus":"disabled"')) {
      throw new Error('Enable Developer Mode on the iPhone in Settings → Privacy & Security, restart, and confirm before installing.');
    }
    run('xcrun', ['devicectl', 'device', 'install', 'app', '--device', device, '--timeout', '60', app]);
    run('xcrun', ['devicectl', 'device', 'process', 'launch', '--device', device, '--terminate-existing', 'com.zerus.notes.native']);
    console.log('Installed and launched Zerus Native. Physical stability verification is still required.');
  } else {
    if (action === 'test' && !simulator) throw new Error('Tests require --simulator <UDID>; they never run against your physical vault.');
    run('pnpm', ['ios:native:verify']);
    run('xcode-select', ['-p']);
    run('xcodebuild', ['-version']);
    run('xcrun', ['devicectl', 'list', 'devices', '--timeout', '5']);
    run('xcodegen', ['generate', '--spec', 'native-ios/project.yml']);
    const common = ['-project', 'native-ios/ZerusNative.xcodeproj', '-scheme', 'ZerusNative', '-configuration', configuration,
      '-destination', simulator ? `platform=iOS Simulator,id=${simulator}` : device ? `platform=iOS,id=${device}` : 'generic/platform=iOS', '-derivedDataPath', derived];
    run('xcodebuild', [...common, '-showBuildSettings'], true);
    run('xcodebuild', [...common, ...(action === 'test' ? ['test', '-collect-test-diagnostics', 'never', ...(args.includes('--unit-only') ? ['-only-testing:ZerusNativeTests'] : [])] : simulator ? ['build'] : ['clean', 'build']), ...(simulator ? ['CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-'] : ['-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration'])]);
    if (!simulator) verifyApp();
  }
} catch (error) {
  console.error(`Native iOS: ${error.message}`);
  process.exitCode = 1;
}
