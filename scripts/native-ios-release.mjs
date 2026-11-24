#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, mkdirSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';
const root = fileURLToPath(new URL('../', import.meta.url));
function run(command, args, capture = false) {
  const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit' });
  if (result.error || result.status !== 0) throw new Error(result.error?.message ?? result.stderr ?? `${command} failed`);
  return result.stdout;
}
const spec = join(root, 'native-ios/project.yml');
const archiveRoot = join(root, 'artifacts/native-ios/archives');
const plist = path => JSON.parse(run('plutil', ['-convert', 'json', '-o', '-', path], true));
try {
  run('pnpm', ['platform:verify']);
  run('pnpm', ['ios:native:verify']);
  run('xcode-select', ['-p']);
  run('xcodebuild', ['-version']);
  run('xcrun', ['devicectl', 'list', 'devices', '--timeout', '5']);
  run('xcodegen', ['generate', '--spec', 'native-ios/project.yml']);
  const common = ['-project', 'native-ios/ZerusNative.xcodeproj', '-scheme', 'ZerusNative', '-configuration', 'Release', '-destination', 'generic/platform=iOS'];
  run('xcodebuild', [...common, '-showBuildSettings'], true);
  const source = readFileSync(spec, 'utf8');
  const config = parse(source);
  const configured = Number(config.settings.base.CURRENT_PROJECT_VERSION);
  const legacy = Number(JSON.parse(readFileSync(join(root, 'src-tauri/tauri.conf.json'))).bundle.iOS.bundleVersion);
  const archives = [archiveRoot, join(root, 'src-tauri/gen/apple/build')].flatMap(dir => existsSync(dir) ? readdirSync(dir).filter(n => n.endsWith('.xcarchive')).map(n => join(dir, n)) : []);
  const completed = archives.filter(a => existsSync(join(a, 'Info.plist'))).map(a => Number(run('/usr/libexec/PlistBuddy', ['-c', 'Print :ApplicationProperties:CFBundleVersion', join(a, 'Info.plist')], true).trim()));
  const latest = Math.max(legacy, ...completed);
  const build = Math.max(configured, latest + 1);
  if (!Number.isSafeInteger(build) || build < 1) throw new Error('Invalid build number');
  console.log(`Native production release ${config.settings.base.MARKETING_VERSION} (${build})`);
  if (process.argv.includes('--dry-run')) process.exit(0);
  writeFileSync(spec, source.replace(/CURRENT_PROJECT_VERSION: \d+/, `CURRENT_PROJECT_VERSION: ${build}`));
  run('xcodegen', ['generate', '--spec', 'native-ios/project.yml']);
  mkdirSync(archiveRoot, { recursive: true });
  const archive = resolve(archiveRoot, `Zerus-${build}.xcarchive`);
  run('xcodebuild', [...common, 'archive', '-archivePath', archive, '-allowProvisioningUpdates']);
  const applications = join(archive, 'Products/Applications');
  const app = join(applications, readdirSync(applications).find(n => n.endsWith('.app')));
  const info = plist(join(app, 'Info.plist'));
  if (info.CFBundleIdentifier !== 'com.zerus.notes' || String(info.CFBundleVersion) !== String(build) || info.CFBundleShortVersionString !== String(config.settings.base.MARKETING_VERSION) || info.UIApplicationSceneManifest?.UIApplicationSupportsMultipleScenes !== true) throw new Error('Archived app metadata or SwiftUI lifecycle mismatch');
  run('codesign', ['--verify', '--deep', '--strict', app]);
  run('pnpm', ['testflight', '--', '--archive', archive, '--export-only']);
  console.log(`Archived and exported build ${build}. Run pnpm testflight to upload.`);
} catch (error) { console.error(error.message); process.exitCode = 1; }
