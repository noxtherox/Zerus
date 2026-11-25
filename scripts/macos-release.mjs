#!/usr/bin/env node
// Builds, notarizes and publishes the native macOS release for the tag at HEAD:
// the DMG is attached to the GitHub release `vX.Y.Z` (shared with the Windows
// installer that CI attaches), and the signed Sparkle ZIP/appcast replace the
// single-release feed on the `native-macos` release that installed apps poll.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { loadNativeUpdateChannel } from './native-macos-updates.mjs';

const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit' });
const out = (cmd, args) => execFileSync(cmd, args, { encoding: 'utf8' }).trim();
const succeeds = (cmd, args) => { try { execFileSync(cmd, args, { stdio: 'ignore' }); return true; } catch { return false; } };

if (process.platform !== 'darwin') throw new Error('The macOS release must be built on macOS.');
if (out('git', ['status', '--porcelain'])) throw new Error('Commit or stash local changes before building the macOS release.');
const project = readFileSync('native-macos/project.yml', 'utf8');
const version = project.match(/^\s*MARKETING_VERSION:\s*([0-9.]+)\s*$/m)?.[1];
const build = project.match(/^\s*CURRENT_PROJECT_VERSION:\s*(\d+)\s*$/m)?.[1];
if (!version || !build) throw new Error('Cannot read the native version from native-macos/project.yml.');
const tag = `v${version}`;
if (!out('git', ['tag', '--points-at', 'HEAD']).split('\n').includes(tag)) {
  throw new Error(`HEAD must be the release tag ${tag}. Run \`pnpm release ${version}\` first, or check out ${tag}.`);
}

const channel = loadNativeUpdateChannel(resolve('native-macos/update-channel.json'));
const feedTag = new URL(channel.downloadPrefix).pathname.split('/').filter(Boolean).at(-1);
const updateDir = resolve(`artifacts/native-macos/update-${version}-${build}`);
if (existsSync(updateDir)) throw new Error(`${updateDir} already exists. Remove it only if that build was never published.`);

run('node', ['scripts/native-macos.mjs', 'dmg']);
const dmg = resolve('artifacts/native-macos', `Zerus-${version}-${build}-arm64.dmg`);
if (!existsSync(dmg)) throw new Error(`Expected DMG is missing: ${dmg}`);
const app = resolve('artifacts/native-macos/dmg-staging/Zerus.app');
const appcast = ['scripts/native-macos-appcast.mjs'];
run('node', [...appcast, 'prepare', '--app', app, '--output', updateDir, '--download-prefix', channel.downloadPrefix, '--account', channel.signingAccount]);
run('node', [...appcast, 'verify', '--app', app, '--output', updateDir, '--download-prefix', channel.downloadPrefix]);
const updateFiles = readdirSync(updateDir).filter(name => /\.(zip|xml)$/.test(name)).map(name => join(updateDir, name));
if (updateFiles.length !== 2) throw new Error('Expected exactly one update ZIP and one appcast.');

// CI may not have created the versioned release yet; whichever side runs first creates it.
if (!succeeds('gh', ['release', 'view', tag])) {
  run('gh', ['release', 'create', tag, '--verify-tag', '--title', `Zerus ${tag}`, '--notes',
    'Download the DMG for Apple Silicon Macs on macOS 26 or later, or the unsigned EXE installer for Windows. The macOS app is signed, notarized and updates itself automatically.']);
}
run('gh', ['release', 'upload', tag, dmg, '--clobber']);

// The feed release is infrastructure, never the "latest" download page.
if (!succeeds('gh', ['release', 'view', feedTag])) {
  run('gh', ['release', 'create', feedTag, '--target', 'main', '--latest=false', '--title', 'macOS update feed',
    '--notes', 'Sparkle update feed for installed macOS copies. Download Zerus from the latest versioned release instead.']);
}
// Upload the archive before the feed so the feed never points at a missing ZIP.
run('gh', ['release', 'upload', feedTag, updateFiles.find(f => f.endsWith('.zip')), '--clobber']);
run('gh', ['release', 'upload', feedTag, updateFiles.find(f => f.endsWith('.xml')), '--clobber']);
console.log(`Published ${tag} for macOS: ${dmg}\nUpdate feed: ${channel.feedURL}`);
