import { beforeEach, expect, it, vi } from 'vitest';
import { exportDesktopSettings, desktopSettingsSnapshot } from './desktop-settings-transfer';
import { save } from '@tauri-apps/plugin-dialog';
import { writeFile } from '@tauri-apps/plugin-fs';
vi.mock('@tauri-apps/api/core', () => ({ isTauri: () => true }));
vi.mock('@tauri-apps/api/webview', () => ({ getCurrentWebview: vi.fn() }));
vi.mock('@tauri-apps/plugin-dialog', () => ({ save: vi.fn() }));
vi.mock('@tauri-apps/plugin-fs', () => ({ writeFile: vi.fn() }));
const values = new Map<string,string>();
beforeEach(() => {
  vi.clearAllMocks(); values.clear();
  vi.stubGlobal('localStorage', { getItem: (key:string) => values.get(key) ?? null });
});
it('exports the selected desktop settings through the save dialog without private account or vault data', async () => {
  const palette = { accent:'#123456', link:'#234567', text:'#345678', editorBg:'#456789', surface:'#56789a', sidebarBg:'#6789ab', sidebarFg:'#789abc' };
  for (const [key,value] of Object.entries({ 'zerus-date-format':'MM/DD/YYYY', 'zerus.interfaceZoom':'125', 'zerus.noteWidth':'60', 'zerus.noteAlignment':'left', 'zerus.codeBlocks':'true', 'zerus.noteLinkShortcuts':'false', 'zerus-theme-preferences':JSON.stringify({ mode:'dark',lightTheme:palette,darkTheme:palette }), 'zerus-saved-themes':JSON.stringify([{name:'Imported café',theme:palette}]), 'zerus.apiKey':'secret', 'zerus.fileLocations':'private paths' })) values.set(key,value);
  vi.mocked(save).mockResolvedValue('/chosen/settings.json');
  expect(await exportDesktopSettings()).toBe('saved');
  const [path,data] = vi.mocked(writeFile).mock.calls[0]; expect(path).toBe('/chosen/settings.json');
  expect(JSON.parse(new TextDecoder().decode(data as Uint8Array))).toEqual({ format:'zerus-desktop-settings',version:1,settings:{dateFormat:'MM/DD/YYYY',interfaceZoom:125,noteWidth:60,noteAlignment:'left',codeBlocks:true,noteLinkShortcuts:false,appearance:'dark',lightTheme:palette,darkTheme:palette,savedThemes:[{name:'Imported café',theme:palette}]}});
  expect(vi.mocked(writeFile)).toHaveBeenCalledTimes(1);
});
it('keeps cancellation read-only and uses the normal preference defaults', async () => {
  vi.mocked(save).mockResolvedValue(null);
  expect(await exportDesktopSettings()).toBe('cancelled'); expect(writeFile).not.toHaveBeenCalled();
  expect(JSON.parse(desktopSettingsSnapshot()).settings).toMatchObject({dateFormat:'DD/MM/YYYY',interfaceZoom:100,noteWidth:75,noteAlignment:'center',codeBlocks:false,noteLinkShortcuts:true,appearance:'system'});
});

it('exports only the selected vault preferences through the same save transport without its absolute path', async () => {
  const vault = '/private/owner/Selected Vault';
  values.set('zerus.defaultNoteType.' + vault, JSON.stringify(['Work', 'Research']));
  values.set('zerus.noteTypeOrder.' + vault, JSON.stringify(['Work', 'Work/Research', 'Inbox']));
  values.set('zerus.keptOpenNoteTypes.v1.' + vault, JSON.stringify(['Work/Research']));
  values.set('zerus.hideSubtypeNotes.' + vault, 'true');
  values.set('zerus.defaultNoteType./other-vault', JSON.stringify(['Other']));
  vi.mocked(save).mockResolvedValue('/chosen/vault-settings.json');
  expect(await exportDesktopSettings(vault)).toBe('saved');
  const text = new TextDecoder().decode(vi.mocked(writeFile).mock.calls[0][1] as Uint8Array);
  expect(JSON.parse(text).vault).toEqual({ name:'Selected Vault', defaultNoteFolder:'Work/Research', folderOrder:['Work','Work/Research','Inbox'], keptOpenFolders:['Work/Research'], hideSubtypeNotes:true });
  expect(text).not.toContain('/private/owner'); expect(text).not.toContain('Other');
  expect(JSON.parse(desktopSettingsSnapshot()).vault).toBeUndefined();
});
