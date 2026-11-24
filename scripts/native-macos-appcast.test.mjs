import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { verifyNativeAppcast } from './native-macos-appcast.mjs';
import { loadNativeUpdateChannel, nativeUpdateBuildSettings } from './native-macos-updates.mjs';

test('production update configuration supplies one approved channel without mixing partial overrides', () => {
  const root = mkdtempSync(join(tmpdir(), 'zerus-native-channel-'));
  try {
    mkdirSync(join(root, 'native-macos'));
    const file = join(root, 'native-macos/update-channel.json');
    const key = Buffer.alloc(32, 1).toString('base64'), otherKey = Buffer.alloc(32, 2).toString('base64');
    const channel = { schemaVersion: 1, feedURL: 'https://updates.example.invalid/native/feed.xml', publicKey: key, signingAccount: 'native-test', downloadPrefix: 'https://updates.example.invalid/native/' };
    const write = value => writeFileSync(file, JSON.stringify(value));
    write(channel);
    const approved = loadNativeUpdateChannel(file);
    assert.deepEqual(nativeUpdateBuildSettings({}, { required: true, channel: approved }), [
      'ZERUS_NATIVE_UPDATE_FEED_URL=https://updates.example.invalid/native/feed.xml', `ZERUS_NATIVE_UPDATE_PUBLIC_KEY=${key}`,
    ]);
    if (process.platform === 'darwin') {
      const env = { ...process.env };
      delete env.ZERUS_NATIVE_UPDATE_FEED_URL; delete env.ZERUS_NATIVE_UPDATE_PUBLIC_KEY;
      const read = () => JSON.parse(execFileSync(process.execPath, [fileURLToPath(new URL('./native-macos.mjs', import.meta.url)), 'channel'], { cwd: root, env, encoding: 'utf8' }));
      assert.deepEqual(read(), { source: 'native-macos/update-channel.json', settings: [
        'ZERUS_NATIVE_UPDATE_FEED_URL=https://updates.example.invalid/native/feed.xml', `ZERUS_NATIVE_UPDATE_PUBLIC_KEY=${key}`,
      ] }, 'The public packaging preflight loads the approved channel without a build or resource staging');
      env.ZERUS_NATIVE_UPDATE_FEED_URL = 'https://override.example.invalid/appcast.xml';
      assert.throws(read, /native HTTPS XML appcast/, 'The packaging boundary must refuse a partial explicit override');
    }
    assert.deepEqual(nativeUpdateBuildSettings({}), [], 'Internal builds remain unconfigured unless a channel is supplied');
    assert.deepEqual(nativeUpdateBuildSettings({ ZERUS_NATIVE_UPDATE_FEED_URL: 'https://override.example.invalid/appcast.xml', ZERUS_NATIVE_UPDATE_PUBLIC_KEY: otherKey }, { required: true, channel: approved }), [
      'ZERUS_NATIVE_UPDATE_FEED_URL=https://override.example.invalid/appcast.xml', `ZERUS_NATIVE_UPDATE_PUBLIC_KEY=${otherKey}`,
    ]);
    for (const env of [{ ZERUS_NATIVE_UPDATE_FEED_URL: 'https://override.example.invalid/appcast.xml' }, { ZERUS_NATIVE_UPDATE_PUBLIC_KEY: otherKey }, { ZERUS_NATIVE_UPDATE_FEED_URL: '', ZERUS_NATIVE_UPDATE_PUBLIC_KEY: '' }]) {
      assert.throws(() => nativeUpdateBuildSettings(env, { required: true, channel: approved }), /native HTTPS XML appcast/, 'An explicit incomplete channel cannot silently borrow production values');
    }
    for (const [change, error] of [
      [{ privateKey: 'must-not-be-a-public-config-field' }, /must contain only/],
      [{ schemaVersion: 2 }, /must contain only/],
      [{ signingAccount: '' }, /must contain only/],
      [{ feedURL: 'https://updates.example.invalid/latest.json' }, /native HTTPS XML appcast/],
      [{ publicKey: 'invalid' }, /canonical 32-byte/],
      [{ downloadPrefix: 'http://updates.example.invalid/native/' }, /HTTPS directory/],
      [{ downloadPrefix: 'https://updates.example.invalid/native/?token=unexpected' }, /without credentials/],
    ]) {
      write({ ...channel, ...change }); assert.throws(() => loadNativeUpdateChannel(file), error);
    }
  } finally { rmSync(root, { recursive: true, force: true }); }
});

// This is a signed-feed protocol owner. Generation with the actual pinned
// Sparkle tool and a signed app is a separate macOS artifact acceptance check.
test('native update verification binds signed UTF-8 feed and archive to the intended app/channel', { skip: process.platform !== 'darwin' }, () => {
  const root = mkdtempSync(join(tmpdir(), 'zerus-appcast-contract-'));
  try {
    const pair = generateKeyPairSync('ed25519');
    const rawPublic = pair.publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
    const archive = join(root, 'update.zip'), feed = join(root, 'appcast.xml');
    const bytes = Buffer.from('Owned native archive fixture.');
    const signature = sign(null, bytes, pair.privateKey).toString('base64');
    const expected = { publicKey: rawPublic, version: '1.2.3', build: '42', minimumMacOS: '26.0', downloadURL: 'https://updates.example.invalid/native/update.zip' };
    const payload = ({ build = '42', url = expected.downloadURL, count = 1, doctype = false } = {}) => Buffer.from(`<?xml version="1.0"?>${doctype ? '<!DOCTYPE rss SYSTEM "https://never-fetch.example.invalid/type.dtd">' : ''}<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><title>Native α</title>${Array.from({ length: count }, () => `<item><sparkle:version>${build}</sparkle:version><sparkle:shortVersionString>1.2.3</sparkle:shortVersionString><sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion><sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements><enclosure url="${url}" length="${bytes.length}" sparkle:edSignature="${signature}" /></item>`).join('')}</channel></rss>`);
    const writeFeed = data => writeFileSync(feed, Buffer.concat([data, Buffer.from(`<!-- sparkle-signatures:\nedSignature: ${sign(null, data, pair.privateKey).toString('base64')}\nlength: ${data.length}\n-->\n`)]));
    const reset = () => { writeFileSync(archive, bytes); writeFeed(payload()); };
    reset();
    const valid = verifyNativeAppcast(feed, archive, expected);
    assert.equal(valid.signedFeedVerified, true); assert.equal(valid.archiveSignatureVerified, true);
    assert.equal(valid.archiveBytes, bytes.length); assert.equal(valid.downloadURL, expected.downloadURL);
    const other = generateKeyPairSync('ed25519').publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
    const cases = [
      ['archive content changes at the same length', () => writeFileSync(archive, Buffer.concat([Buffer.from('X'), bytes.subarray(1)])), expected, /Archive signature does not match/],
      ['archive length changes', () => writeFileSync(archive, Buffer.concat([bytes, Buffer.from('!')])), expected, /length differs/],
      ['signed feed is removed', () => writeFileSync(feed, payload()), expected, /no signed-feed trailer/],
      ['signed feed text is changed', () => { const data = payload({ build: '43' }); const original = payload(); writeFileSync(feed, Buffer.concat([data, Buffer.from(`<!-- sparkle-signatures:\nedSignature: ${sign(null, original, pair.privateKey).toString('base64')}\nlength: ${data.length}\n-->\n`)])); }, expected, /Appcast signature does not match/],
      ['a different public key is bundled', () => {}, { ...expected, publicKey: other }, /Appcast signature does not match/],
      ['a validly signed item targets another build', () => writeFeed(payload({ build: '43' })), expected, /version differs/],
      ['a validly signed item targets another download channel', () => writeFeed(payload({ url: 'https://other.example.invalid/update.zip' })), expected, /download URL differs/],
      ['duplicate signed items are supplied', () => writeFeed(payload({ count: 2 })), expected, /one native release/],
      ['a signed feed declares an external document type', () => writeFeed(payload({ doctype: true })), expected, /must not declare an external document type/],
    ];
    for (const [name, mutate, context, error] of cases) {
      reset(); mutate();
      assert.throws(() => verifyNativeAppcast(feed, archive, context), error, name);
    }
  } finally { rmSync(root, { recursive: true, force: true }); }
});
