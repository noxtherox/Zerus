import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { signNativeCLI } from './native-macos-cli.mjs';

export function loadNativeUpdateChannel(file) {
  if (statSync(file).size > 16 * 1024) throw new Error('Native update channel configuration exceeds 16 KiB.');
  const channel = JSON.parse(readFileSync(file, 'utf8'));
  const fields = ['schemaVersion', 'feedURL', 'publicKey', 'signingAccount', 'downloadPrefix'];
  if (!channel || Array.isArray(channel) || typeof channel !== 'object' || channel.schemaVersion !== 1 || Object.keys(channel).some(key => !fields.includes(key)) ||
      !['feedURL', 'publicKey', 'signingAccount', 'downloadPrefix'].every(key => typeof channel[key] === 'string') || !/^[A-Za-z0-9._-]{1,128}$/.test(channel.signingAccount)) {
    throw new Error('Native update channel must contain only its version, public feed/key, signing account and download directory.');
  }
  nativeUpdateBuildSettings({}, { required: true, channel });
  let prefix;
  try { prefix = new URL(channel.downloadPrefix); } catch { throw new Error('Native update download prefix must be an HTTPS directory.'); }
  if (prefix.protocol !== 'https:' || !prefix.hostname || prefix.username || prefix.password || prefix.search || prefix.hash || !prefix.pathname.endsWith('/')) throw new Error('Native update download prefix must be an HTTPS directory without credentials, query or fragment.');
  return Object.freeze(channel);
}

export function nativeUpdateBuildSettings(env = process.env, { required = false, channel } = {}) {
  // A partial explicit override is an error, never a key/feed mixed with the
  // approved channel. Artifact verification passes only the actual bundle keys.
  const explicit = env.ZERUS_NATIVE_UPDATE_FEED_URL !== undefined || env.ZERUS_NATIVE_UPDATE_PUBLIC_KEY !== undefined;
  const feed = (explicit ? env.ZERUS_NATIVE_UPDATE_FEED_URL ?? '' : channel?.feedURL ?? '').trim();
  const key = (explicit ? env.ZERUS_NATIVE_UPDATE_PUBLIC_KEY ?? '' : channel?.publicKey ?? '').trim();
  if (!feed && !key && !required) return [];
  let url;
  try { url = new URL(feed); } catch { throw new Error('A native HTTPS XML appcast and Ed25519 public key are required.'); }
  if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || url.hash || !url.pathname.toLowerCase().endsWith('.xml') || Buffer.from(key, 'base64').length !== 32 || Buffer.from(key, 'base64').toString('base64') !== key) throw new Error('A native HTTPS XML appcast and canonical 32-byte Ed25519 public key are required.');
  return [`ZERUS_NATIVE_UPDATE_FEED_URL=${feed}`, `ZERUS_NATIVE_UPDATE_PUBLIC_KEY=${key}`];
}

export const sparkleCodePaths = [
  'Versions/B/Autoupdate',
  'Versions/B/Updater.app',
  'Versions/B/XPCServices/Downloader.xpc',
  'Versions/B/XPCServices/Installer.xpc',
  '',
];

// Sign from the nested helpers outward. --deep is for verification, never signing.
export function signNativeMacApp(app, identity, local) {
  const run = args => execFileSync('codesign', args, { stdio: 'inherit' });
  const options = local ? [] : ['--timestamp', '--options', 'runtime'];
  const framework = resolve(app, 'Contents/Frameworks/Sparkle.framework');
  for (const relative of sparkleCodePaths) run(['--force', '--sign', identity, ...options, '--preserve-metadata=entitlements', resolve(framework, relative)]);
  signNativeCLI(resolve(app, 'Contents/Resources/CLI'), identity, local);
  run(['--force', '--sign', identity, ...options, app]);
  run(['--verify', '--deep', '--strict', app]);
}
