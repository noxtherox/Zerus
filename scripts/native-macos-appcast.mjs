import { execFileSync } from 'node:child_process';
import { createHash, createPublicKey, verify as verifySignature } from 'node:crypto';
import { constants, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve, sep } from 'node:path';
import { pathToFileURL } from 'node:url';
import { tmpdir } from 'node:os';
import { verifyNativeMacApp } from './native-macos-artifact.mjs';
import { nativeUpdateBuildSettings } from './native-macos-updates.mjs';

const sparkleNamespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle';
const tools = resolve('artifacts/native-macos/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin');
const hash = file => createHash('sha256').update(readFileSync(file)).digest('hex');
function httpsPrefix(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('An HTTPS download prefix is required.'); }
  if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || url.search || url.hash || !url.pathname.endsWith('/')) throw new Error('Download prefix must be an HTTPS directory URL without credentials, query or fragment.');
  return url.href;
}
function rawKey(value, length, label) {
  const bytes = Buffer.from(value ?? '', 'base64');
  if (bytes.length !== length || bytes.toString('base64') !== value) throw new Error(`Invalid ${label}.`);
  return bytes;
}
function publicKey(value) {
  return createPublicKey({ key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), rawKey(value, 32, 'native public key')]), format: 'der', type: 'spki' });
}
function checkSignature(key, data, value, label) {
  if (!verifySignature(null, data, key, rawKey(value, 64, `${label} signature`))) throw new Error(`${label} signature does not match the app's native public key.`);
}
function xml(file, expression) {
  return execFileSync('/usr/bin/xmllint', ['--nonet', '--xpath', expression, file], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

// Also used by the public verify command before an already-prepared channel is uploaded.
export function verifyNativeAppcast(feed, archive, expected) {
  if (statSync(feed).size > 4 * 1024 * 1024 || statSync(archive).size > 512 * 1024 * 1024) throw new Error('Native appcast or update archive exceeds the verification limit (4 MiB / 512 MiB).');
  const data = readFileSync(feed), key = publicKey(expected.publicKey);
  const tail = data.toString('utf8').match(/<!-- sparkle-signatures:\s*\nedSignature: ([A-Za-z0-9+/=]+)\s*\nlength: ([0-9]+)\s*\n-->\s*$/);
  if (!tail) throw new Error('Native appcast has no signed-feed trailer.');
  const length = Number(tail[2]);
  if (!Number.isSafeInteger(length) || length < 1 || length >= data.length || data.subarray(length).toString('utf8') !== tail[0]) throw new Error('Native appcast signed length does not match its payload.');
  checkSignature(key, data.subarray(0, length), tail[1], 'Appcast');
  if (/<!DOCTYPE/i.test(data.toString('utf8'))) throw new Error('Native appcasts must not declare an external document type.');
  const item = '/rss/channel/item';
  if (xml(feed, `count(${item})`) !== '1' || xml(feed, `count(${item}/enclosure)`) !== '1') throw new Error('Expected one native release and one update enclosure.');
  const element = name => `string(${item}/*[local-name()='${name}' and namespace-uri()='${sparkleNamespace}'])`;
  for (const [name, value] of [['version', expected.build], ['shortVersionString', expected.version], ['minimumSystemVersion', expected.minimumMacOS], ['hardwareRequirements', 'arm64']]) {
    if (xml(feed, element(name)) !== value) throw new Error(`Native appcast ${name} differs from the verified app.`);
  }
  if (xml(feed, `string(${item}/enclosure/@url)`) !== expected.downloadURL) throw new Error('Native update download URL differs from the requested channel.');
  const bytes = readFileSync(archive);
  if (xml(feed, `string(${item}/enclosure/@length)`) !== String(bytes.length)) throw new Error('Native update length differs from the archive.');
  const signature = xml(feed, `string(${item}/enclosure/@*[local-name()='edSignature' and namespace-uri()='${sparkleNamespace}'])`);
  checkSignature(key, bytes, signature, 'Archive');
  return { signedFeedVerified: true, archiveSignatureVerified: true, archiveBytes: bytes.length, archiveSha256: hash(archive), appcastSha256: hash(feed), downloadURL: expected.downloadURL };
}

function context(app, prefix, local) {
  const receipt = verifyNativeMacApp(app, { local });
  const plist = JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', join(app, 'Contents/Info.plist')], { encoding: 'utf8' }));
  nativeUpdateBuildSettings({ ZERUS_NATIVE_UPDATE_FEED_URL: plist.SUFeedURL, ZERUS_NATIVE_UPDATE_PUBLIC_KEY: plist.SUPublicEDKey }, { required: true });
  const feedURL = new URL(plist.SUFeedURL), feedName = basename(feedURL.pathname);
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*\.xml$/.test(feedName)) throw new Error('Native feed filename must be a plain XML filename.');
  const archiveName = `Zerus-${receipt.version}-${receipt.build}-arm64.zip`;
  return { receipt, feedName, archiveName, downloadPrefix: httpsPrefix(prefix), appSealSha256: hash(join(app, 'Contents/_CodeSignature/CodeResources')), feedURL: feedURL.href, expected: { ...receipt, publicKey: plist.SUPublicEDKey, downloadURL: new URL(archiveName, httpsPrefix(prefix)).href } };
}

function matchArchiveApp(actual, expected) {
  if (actual.receipt.executableSha256 !== expected.receipt.executableSha256 || actual.appSealSha256 !== expected.appSealSha256) throw new Error('Native update archive contains a different app than the verified input bundle.');
}
function verifyArchiveApp(archive, expected, local) {
  const names = execFileSync('unzip', ['-Z1', archive], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 }).trim().split('\n');
  if (names.some(name => name.startsWith('/') || name.includes('\\') || name.split('/').includes('..') || !(name === 'Zerus.app' || name.startsWith('Zerus.app/') || name === '__MACOSX' || name.startsWith('__MACOSX/')))) throw new Error('Native update archive has unexpected paths outside its app bundle.');
  const directory = mkdtempSync(join(tmpdir(), 'zerus-native-update-verify-'));
  try {
    execFileSync('ditto', ['-x', '-k', archive, directory]);
    const app = join(directory, 'Zerus.app');
    matchArchiveApp(context(app, expected.downloadPrefix, local), expected);
    if (!local) {
      execFileSync('xcrun', ['stapler', 'validate', app], { stdio: 'pipe' });
      execFileSync('spctl', ['--assess', '--type', 'execute', '--verbose=2', app], { stdio: 'pipe' });
    }
    return true;
  } finally { rmSync(directory, { recursive: true, force: true }); }
}

export function prepareNativeAppcast({ app, output, downloadPrefix, account, keyFile, local = false }) {
  if (process.platform !== 'darwin') throw new Error('Native update preparation requires macOS.');
  if (Boolean(account) === Boolean(keyFile)) throw new Error('Choose exactly one explicit native signing account or private key file.');
  if (keyFile && (!statSync(keyFile).isFile() || (statSync(keyFile).mode & 0o077) !== 0)) throw new Error('The native private key file must be a regular file readable only by its owner.');
  const prefix = httpsPrefix(downloadPrefix);
  const source = realpathSync(app), destination = join(realpathSync(dirname(output)), basename(output));
  if (destination === source || destination.startsWith(source + sep)) throw new Error('Native update output must be outside the input app bundle.');
  if (existsSync(output)) throw new Error('Native update output must be a new directory; existing feeds are never overwritten or pruned.');
  if (!existsSync(join(tools, 'generate_appcast'))) throw new Error('Pinned Sparkle tools are unavailable. Build the native app first.');
  // Reserve output exclusively. Keep partial failures visibly unaccepted; only
  // a successful receipt authorizes using the files as a prepared release.
  mkdirSync(output);
  const stage = mkdtempSync(join(output, '.pending-'));
  try {
    const stagedApp = join(stage, 'Zerus.app');
    execFileSync('ditto', [app, stagedApp]);
    const details = context(stagedApp, prefix, local);
    if (!local) {
      execFileSync('xcrun', ['stapler', 'staple', stagedApp], { stdio: 'pipe' });
      execFileSync('xcrun', ['stapler', 'validate', stagedApp], { stdio: 'pipe' });
      execFileSync('spctl', ['--assess', '--type', 'execute', '--verbose=2', stagedApp], { stdio: 'pipe' });
    }
    const archives = join(stage, 'archives'); mkdirSync(archives);
    const archive = join(archives, details.archiveName), feed = join(archives, details.feedName);
    execFileSync('ditto', ['-c', '-k', '--sequesterRsrc', '--keepParent', stagedApp, archive]);
    const signing = keyFile ? ['--ed-key-file', resolve(keyFile)] : ['--account', account];
    try {
      execFileSync(join(tools, 'generate_appcast'), [...signing, '--download-url-prefix', prefix, '--maximum-deltas', '0', '-o', feed, archives], { stdio: 'pipe' });
    } catch { throw new Error('Sparkle appcast generation failed. Check access to the explicitly selected native signing key.'); }
    const verification = verifyNativeAppcast(feed, archive, details.expected);
    const archiveAppVerified = verifyArchiveApp(archive, details, local);
    // Recheck the complete sealed staged app, not just its executable, after archiving.
    matchArchiveApp(context(stagedApp, prefix, local), details);
    for (const file of [archive, feed]) copyFileSync(file, join(output, basename(file)), constants.COPYFILE_EXCL);
    const receipt = { schemaVersion: 1, mode: local ? 'local-qa' : 'developer-id', app: details.receipt, appSealSha256: details.appSealSha256, archiveAppVerified, feedURL: details.feedURL, appcast: details.feedName, archive: details.archiveName, ...verification, published: false, notarization: local ? 'not-checked-local-qa' : 'app-ticket-stapled-and-gatekeeper-accepted' };
    writeFileSync(join(output, 'native-update-receipt.json'), JSON.stringify(receipt, null, 2) + '\n', { flag: 'wx' });
    return receipt;
  } finally { rmSync(stage, { recursive: true, force: true }); }
}

function argumentsFor(argv) {
  const command = argv.shift();
  if (!['prepare', 'verify'].includes(command)) throw new Error('Use prepare or verify with --app, --output and --download-prefix. Preparation also requires --account or --key-file. --local is QA only.');
  const options = {};
  for (let i = 0; i < argv.length; i++) {
    const name = argv[i];
    if (name === '--local') { options.local = true; continue; }
    const key = { '--app': 'app', '--output': 'output', '--download-prefix': 'downloadPrefix', '--account': 'account', '--key-file': 'keyFile' }[name];
    if (!key || !argv[i + 1] || argv[i + 1].startsWith('--') || key in options) throw new Error(`Invalid or repeated native update option: ${name}`);
    options[key] = argv[++i];
  }
  if (!options.app || !options.output || !options.downloadPrefix) throw new Error('--app, --output and --download-prefix are required.');
  if (command === 'verify' && (options.account || options.keyFile)) throw new Error('Verification uses only the bundled public key; do not provide signing credentials.');
  options.app = resolve(options.app); options.output = resolve(options.output);
  return { command, options };
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  if (process.argv.length === 3 && process.argv[2] === '--help') {
    console.log('Native Sparkle update artifacts (no upload or DMG creation)\n\nprepare --app APP --output NEW_DIRECTORY --download-prefix HTTPS_DIRECTORY_URL (--account NATIVE_ACCOUNT | --key-file PRIVATE_FILE) [--local]\nverify --app APP --output PREPARED_DIRECTORY --download-prefix HTTPS_DIRECTORY_URL [--local]\n\nProduction mode requires a configured Developer ID app and notarization ticket. --local accepts ad-hoc QA apps only. Signing keys are never required for verify.');
  } else try {
    const { command, options } = argumentsFor(process.argv.slice(2));
    const receipt = command === 'prepare' ? prepareNativeAppcast(options) : (() => {
      const details = context(options.app, options.downloadPrefix, options.local ?? false);
      const archive = join(options.output, details.archiveName);
      const verified = verifyNativeAppcast(join(options.output, details.feedName), archive, details.expected);
      return { ...verified, archiveAppVerified: verifyArchiveApp(archive, details, options.local ?? false) };
    })();
    console.log(JSON.stringify(receipt, null, 2));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
