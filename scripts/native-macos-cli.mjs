import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmodSync, copyFileSync, lstatSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const run = (command, args) => execFileSync(command, args, { stdio: 'inherit' });
export function verifyNativeCLI(directory) {
  const record = JSON.parse(readFileSync(resolve(directory, 'manifest.json'), 'utf8'));
  if (record.schemaVersion !== 1 || typeof record.version !== 'string' || typeof record.skillVersion !== 'string' || !/^\d+\.\d+\.\d+$/.test(record.version) || !/^\d+$/.test(record.skillVersion) || !/^[a-f0-9]{64}$/.test(record.stagedExecutableSha256)) throw new Error('Native CLI resource manifest is invalid.');
  for (const [name, hash] of [['zerus', record.executableSha256], ['SKILL.md', record.skillSha256]]) {
    const path = resolve(directory, name), stat = lstatSync(path);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 50 * 1024 * 1024 || digest(readFileSync(path)) !== hash) throw new Error(`Native CLI resource ${name} is missing or changed.`);
  }
  const arch = execFileSync('lipo', ['-archs', resolve(directory, 'zerus')], { encoding: 'utf8' }).trim();
  if (arch !== 'arm64') throw new Error(`Native CLI must be arm64, received ${arch}`);
  return record;
}
export function prepareNativeCLI() {
  run('cargo', ['build', '--manifest-path', 'src-tauri/Cargo.toml', '-p', 'zerus-cli', '--release', '--locked']);
  const source = resolve('src-tauri/target/release/zerus');
  const version = readFileSync('src-tauri/crates/zerus-cli/Cargo.toml', 'utf8').match(/^version\s*=\s*"([^"]+)"/m)?.[1];
  if (!version || execFileSync(source, ['--version'], { encoding: 'utf8' }).trim() !== `zerus ${version}`) throw new Error('The native CLI executable version does not match Cargo.toml.');
  const skill = readFileSync('src-tauri/skills/zerus-skill.md');
  const skillVersion = skill.toString('utf8').match(/^  version: "(\d+)"$/m)?.[1];
  if (!skillVersion) throw new Error('The bundled Zerus skill version is missing.');
  const directory = resolve('native-macos/Resources/CLI'); rmSync(directory, { recursive: true, force: true }); mkdirSync(directory, { recursive: true });
  copyFileSync(source, resolve(directory, 'zerus')); chmodSync(resolve(directory, 'zerus'), 0o755);
  run('codesign', ['--force', '--sign', '-', resolve(directory, 'zerus')]);
  writeFileSync(resolve(directory, 'SKILL.md'), skill);
  writeFileSync(resolve(directory, 'manifest.json'), JSON.stringify({ schemaVersion: 1, version, skillVersion, executableSha256: digest(readFileSync(resolve(directory, 'zerus'))), stagedExecutableSha256: digest(readFileSync(resolve(directory, 'zerus'))), skillSha256: digest(skill) }, null, 2) + '\n');
  verifyNativeCLI(directory);
  console.log(`Native CLI ${version} and skill ${skillVersion} staged.`);
}
export function signNativeCLI(directory, identity, local) {
  verifyNativeCLI(directory);
  run('codesign', ['--force', '--sign', identity, ...(local ? [] : ['--timestamp', '--options', 'runtime']), resolve(directory, 'zerus')]);
  const manifest = resolve(directory, 'manifest.json'), record = JSON.parse(readFileSync(manifest, 'utf8'));
  record.executableSha256 = digest(readFileSync(resolve(directory, 'zerus')));
  writeFileSync(manifest, JSON.stringify(record, null, 2) + '\n');
  run('codesign', ['--verify', '--strict', resolve(directory, 'zerus')]);
  verifyNativeCLI(directory);
}
if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  if (process.argv[2] !== 'stage') throw new Error('Use native-macos-cli.mjs stage.');
  prepareNativeCLI();
}
