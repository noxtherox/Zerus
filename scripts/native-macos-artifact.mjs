import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { parse } from 'yaml';
import { verifyNativeCLI } from './native-macos-cli.mjs';
import { verifyNativeIcons } from './native-macos-icons.mjs';
import { nativeUpdateBuildSettings, sparkleCodePaths } from './native-macos-updates.mjs';

export function verifyNativeMacApp(app, { local, spec = 'native-macos/project.yml' } = {}) {
  const project = parse(readFileSync(spec, 'utf8'));
  const base = project.settings.base;
  const target = project.targets.ZerusMac.settings.base;
  const plist = JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', resolve(app, 'Contents/Info.plist')], { encoding: 'utf8' }));
  const expected = {
    CFBundleIdentifier: target.PRODUCT_BUNDLE_IDENTIFIER,
    CFBundleShortVersionString: String(base.MARKETING_VERSION),
    CFBundleVersion: String(base.CURRENT_PROJECT_VERSION),
    CFBundleExecutable: target.PRODUCT_NAME,
    CFBundlePackageType: 'APPL',
    LSMinimumSystemVersion: String(base.MACOSX_DEPLOYMENT_TARGET),
  };
  for (const [key, value] of Object.entries(expected)) {
    if (plist[key] !== value) throw new Error(`Native app ${key}: expected ${value}, received ${plist[key]}.`);
  }
  if (!plist.CFBundleSupportedPlatforms?.includes('MacOSX')) throw new Error('Native app is not a macOS bundle.');
  // Inspect the delivered plist: source declarations alone do not prove that
  // Finder and pasteboard routing survived Xcode resource generation/packaging.
  const documentTypes = plist.CFBundleDocumentTypes;
  if (!Array.isArray(documentTypes) || documentTypes.some(type => type?.LSHandlerRank !== 'Alternate')) throw new Error('Native app document handlers must be declared as Alternate without replacing default applications.');
  for (const extension of ['md', 'markdown', 'pdf', 'doc', 'docx', 'rtf', 'txt', 'odt', 'xls', 'xlsx', 'csv', 'ppt', 'pptx', 'pages', 'numbers', 'key', '*']) {
    const role = ['md', 'markdown'].includes(extension) ? 'Editor' : 'Viewer';
    if (!documentTypes.some(type => type.CFBundleTypeRole === role && Array.isArray(type.CFBundleTypeExtensions) && type.CFBundleTypeExtensions.includes(extension))) throw new Error(`Native app document handler is missing ${extension} (${role}).`);
  }
  if (!documentTypes.some(type => type.CFBundleTypeRole === 'Viewer' && Array.isArray(type.LSItemContentTypes) && type.LSItemContentTypes.includes('public.data'))) throw new Error('Native app generic document handler must accept public.data.');
  const dragTypes = ['com.zerus.notes.native.board-item', 'com.zerus.notes.native.folder-order'];
  for (const identifier of dragTypes) {
    if (!Array.isArray(plist.UTExportedTypeDeclarations) || !plist.UTExportedTypeDeclarations.some(type => type?.UTTypeIdentifier === identifier && Array.isArray(type.UTTypeConformsTo) && type.UTTypeConformsTo.includes('public.data'))) throw new Error(`Native app drag type must declare public.data conformance: ${identifier}.`);
  }
  if (basename(plist.CFBundleExecutable) !== plist.CFBundleExecutable) throw new Error('Invalid native app executable name.');
  const executable = resolve(app, 'Contents/MacOS', plist.CFBundleExecutable);
  const architectures = execFileSync('lipo', ['-archs', executable], { encoding: 'utf8' }).trim().split(/\s+/).sort();
  if (architectures.join(',') !== 'arm64') throw new Error(`Unexpected native app architectures: ${architectures.join(',')}.`);
  execFileSync('codesign', ['--verify', '--deep', '--strict', app], { stdio: 'pipe' });
  const signature = spawnSync('codesign', ['--display', '--verbose=4', app], { encoding: 'utf8' });
  if (signature.error) throw signature.error;
  if (signature.status !== 0) throw new Error('Could not inspect native app signature.');
  const adHoc = /^Signature=adhoc$/m.test(signature.stderr);
  const team = signature.stderr.match(/^TeamIdentifier=(.+)$/m)?.[1];
  if (local !== undefined && adHoc !== local) throw new Error('Native app signing channel differs from the requested build channel.');
  if (!adHoc && !/^Authority=Developer ID Application: /m.test(signature.stderr)) throw new Error('Native app does not have a Developer ID Application signature.');
  if (!adHoc && team !== String(base.DEVELOPMENT_TEAM)) throw new Error('Native app signature belongs to a different development team.');
  nativeUpdateBuildSettings({ ZERUS_NATIVE_UPDATE_FEED_URL: plist.SUFeedURL, ZERUS_NATIVE_UPDATE_PUBLIC_KEY: plist.SUPublicEDKey }, { required: local === false });
  if (plist.SURequireSignedFeed !== true || plist.SUVerifyUpdateBeforeExtraction !== true || plist.SUAllowsAutomaticUpdates !== false) throw new Error('Native update verification/installation policy is missing.');
  const framework = resolve(app, 'Contents/Frameworks/Sparkle.framework');
  const sparklePlist = JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', resolve(framework, 'Resources/Info.plist')], { encoding: 'utf8' }));
  const sparkleVersion = String(project.packages.Sparkle.exactVersion);
  if (sparklePlist.CFBundleShortVersionString !== sparkleVersion) throw new Error('Bundled Sparkle version differs from the pinned dependency.');
  for (const relative of sparkleCodePaths) {
    const path = resolve(framework, relative);
    execFileSync('codesign', ['--verify', '--strict', path], { stdio: 'pipe' });
    const nested = spawnSync('codesign', ['--display', '--verbose=4', path], { encoding: 'utf8' });
    if (nested.status !== 0 || /^Signature=adhoc$/m.test(nested.stderr) !== adHoc || (!adHoc && nested.stderr.match(/^TeamIdentifier=(.+)$/m)?.[1] !== team)) throw new Error('Sparkle signing channel/team differs from the app.');
  }
  const cliDirectory = resolve(app, 'Contents/Resources/CLI');
  const cli = verifyNativeCLI(cliDirectory);
  const stagedCLI = verifyNativeCLI(resolve('native-macos/Resources/CLI'));
  if (cli.version !== stagedCLI.version || cli.skillVersion !== stagedCLI.skillVersion || cli.skillSha256 !== stagedCLI.skillSha256 || cli.stagedExecutableSha256 !== stagedCLI.executableSha256) throw new Error('The app contains stale CLI resources; rebuild it from the freshly staged tools.');
  execFileSync('codesign', ['--verify', '--strict', resolve(cliDirectory, 'zerus')], { stdio: 'pipe' });
  const cliSignature = spawnSync('codesign', ['--display', '--verbose=4', resolve(cliDirectory, 'zerus')], { encoding: 'utf8' });
  if (cliSignature.status !== 0 || /^Signature=adhoc$/m.test(cliSignature.stderr) !== adHoc || (!adHoc && cliSignature.stderr.match(/^TeamIdentifier=(.+)$/m)?.[1] !== team)) throw new Error('Native CLI signing channel/team differs from the app.');
  return {
    schemaVersion: 1,
    cli,
    documentOpening: { markdownRole: 'Editor', documentRole: 'Viewer', handlerRank: 'Alternate' },
    dragTypes,
    folderIcons: verifyNativeIcons(resolve(app, 'Contents/Resources/FolderIcons')),
    updater: { frameworkVersion: sparkleVersion, configured: Boolean(plist.SUFeedURL), signedFeedRequired: true, nestedSignaturesVerified: true },
    bundleIdentifier: plist.CFBundleIdentifier,
    version: plist.CFBundleShortVersionString,
    build: plist.CFBundleVersion,
    minimumMacOS: plist.LSMinimumSystemVersion,
    architectures,
    signing: adHoc ? 'ad-hoc' : 'developer-id',
    executableSha256: createHash('sha256').update(readFileSync(executable)).digest('hex'),
    signatureVerified: true,
  };
}

export function verifyNativeMacDmg(dmg, options) {
  const mount = mkdtempSync(join(tmpdir(), 'zerus-native-artifact-'));
  let attached = false;
  try {
    execFileSync('hdiutil', ['attach', '-readonly', '-nobrowse', '-mountpoint', mount, dmg], { stdio: 'pipe' });
    attached = true;
    return verifyNativeMacApp(join(mount, 'Zerus.app'), options);
  } finally {
    if (attached) execFileSync('hdiutil', ['detach', mount], { stdio: 'pipe' });
    if (existsSync(mount)) rmdirSync(mount);
  }
}
