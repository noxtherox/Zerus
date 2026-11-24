import { buildSync } from 'esbuild';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Generate from the actual desktop catalog, including its aliases, labels,
// featured ordering and suggestion rules. Native never needs a web runtime.
export async function prepareNativeIcons() {
  const stage = resolve('artifacts/native-macos'); mkdirSync(stage, { recursive: true });
  const module = resolve(stage, 'icon-catalog-stage.mjs');
  const bundled = buildSync({ stdin: { contents: `export { TABLER_ICON_ENTRIES as entries } from './src/lib/tabler-icon-catalog.ts'; export { TYPE_ICON_KEYWORDS as keywords } from './src/lib/type-icons.ts';`, resolveDir: process.cwd() }, bundle: true, packages: 'external', platform: 'node', format: 'esm', write: false });
  writeFileSync(module, bundled.outputFiles[0].contents);
  const { entries, keywords } = await import(pathToFileURL(module).href);
  const { createElement } = await import('react');
  const { renderToStaticMarkup } = await import('react-dom/server');
  const icons = entries.map(({ name, label, searchText, Icon }) => ({ name, label, searchText, svg: renderToStaticMarkup(createElement(Icon, { size: 24, stroke: 1.8, color: '#000000' })) }));
  if (icons.length < 5000 || new Set(icons.map(x => x.name)).size !== icons.length) throw new Error('The desktop icon catalog is incomplete or ambiguous.');
  const directory = resolve('native-macos/Resources/FolderIcons'); mkdirSync(directory, { recursive: true });
  const data = JSON.stringify({ version: 1, icons, keywords }) + '\n';
  const license = readFileSync(resolve('node_modules/@tabler/icons-react/LICENSE'));
  writeFileSync(resolve(directory, 'catalog.json'), data); writeFileSync(resolve(directory, 'LICENSE'), license);
  const manifest = { version: 1, iconCount: icons.length, catalogSha256: createHash('sha256').update(data).digest('hex'), licenseSha256: createHash('sha256').update(license).digest('hex') };
  writeFileSync(resolve(directory, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  return manifest;
}
export function verifyNativeIcons(directory) {
  const manifest = JSON.parse(readFileSync(resolve(directory, 'manifest.json'), 'utf8'));
  for (const [file, key] of [['catalog.json','catalogSha256'],['LICENSE','licenseSha256']]) {
    if (createHash('sha256').update(readFileSync(resolve(directory, file))).digest('hex') !== manifest[key]) throw new Error('Native folder icon resource does not match its manifest: ' + file);
  }
  const fresh = JSON.parse(readFileSync(resolve('native-macos/Resources/FolderIcons/manifest.json'), 'utf8'));
  if (JSON.stringify(manifest) !== JSON.stringify(fresh)) throw new Error('The app contains a stale folder icon catalog. Rebuild from current desktop resources.');
  return manifest;
}
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) console.log(JSON.stringify(await prepareNativeIcons()));
