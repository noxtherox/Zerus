import { existsSync, readFileSync } from 'node:fs';
import { dirname, isAbsolute, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const appRoot = resolve(root, 'native-ios');
const project = parse(readFileSync(resolve(appRoot, 'project.yml'), 'utf8'));
const app = project.targets?.ZerusNative;
const fail = (message) => { throw new Error(`Native iOS configuration check failed: ${message}`); };
const inside = (parent, path) => {
  const rel = relative(parent, path);
  return rel === '' || (!rel.startsWith('..') && !isAbsolute(rel));
};

if (app?.settings?.base?.PRODUCT_BUNDLE_IDENTIFIER !== 'com.zerus.notes.native') {
  fail('the SwiftUI preview must keep its separate application identity');
}
if (app?.info?.properties?.UIApplicationSceneManifest?.UIApplicationSupportsMultipleScenes !== true) {
  fail('the SwiftUI app must retain its scene lifecycle');
}
for (const entry of app.sources ?? []) {
  const path = resolve(appRoot, typeof entry === 'string' ? entry : entry.path);
  if (!inside(appRoot, path) || !existsSync(path)) {
    fail(`app sources and resources must exist inside native-ios: ${relative(root, path)}`);
  }
}
for (const [name, dependency] of Object.entries(project.packages ?? {})) {
  if (!dependency.path) continue;
  const path = resolve(appRoot, dependency.path);
  if (!inside(resolve(root, 'packages/apple'), path) || !existsSync(resolve(path, 'Package.swift'))) {
    fail(`${name} must reference a shared Apple package with a Package.swift`);
  }
}
for (const name of ['ZerusIOSServices', 'ZerusChatGPTCore']) {
  if (!project.packages?.[name]?.path || !app.dependencies?.some((entry) => entry.package === name)) {
    fail(`the app must depend on the shared ${name} package`);
  }
}
if (!existsSync(resolve(appRoot, 'Resources/Assets.xcassets/AppIcon.appiconset/Contents.json'))) {
  fail('the SwiftUI app must own its app icon assets');
}
console.log('Native iOS configuration boundaries verified.');
