import { isTauri } from '@tauri-apps/api/core';
import { save } from '@tauri-apps/plugin-dialog';
import { writeFile } from '@tauri-apps/plugin-fs';
import { loadDateFormat } from './date-format';
import { loadInterfaceZoom } from './interface-preferences';
import { loadNoteWidth, loadNoteAlignment, loadDefaultNoteType, loadNoteTypeOrder, loadKeptOpenNoteTypes, loadHideSubtypeNotes } from './note-preferences';
import { loadCodeBlocksEnabled, loadNoteLinkShortcutsEnabled } from './editor-preferences';
import { loadThemePreferences, loadSavedThemes } from './theme';

/** Portable, explicit allowlist: no vault contents, accounts or connection data. */
export function desktopSettingsSnapshot(vaultLocation?: string | null): string {
  const themes = loadThemePreferences();
  return JSON.stringify({
    format: 'zerus-desktop-settings', version: 1,
    ...(vaultLocation ? { vault: {
      name: vaultLocation.replace(/\\/g, '/').split('/').filter(Boolean).at(-1) ?? 'Vault',
      defaultNoteFolder: loadDefaultNoteType(vaultLocation).join('/'),
      folderOrder: loadNoteTypeOrder(vaultLocation),
      keptOpenFolders: loadKeptOpenNoteTypes(vaultLocation),
      hideSubtypeNotes: loadHideSubtypeNotes(vaultLocation),
    } } : {}),
    settings: {
      dateFormat: loadDateFormat(), interfaceZoom: loadInterfaceZoom(),
      noteWidth: loadNoteWidth(), noteAlignment: loadNoteAlignment(),
      codeBlocks: loadCodeBlocksEnabled(), noteLinkShortcuts: loadNoteLinkShortcutsEnabled(),
      appearance: themes.mode, lightTheme: themes.lightTheme, darkTheme: themes.darkTheme,
      savedThemes: loadSavedThemes(),
    },
  }, null, 2) + '\n';
}

export async function exportDesktopSettings(vaultLocation?: string | null): Promise<'saved' | 'cancelled'> {
  const bytes = new TextEncoder().encode(desktopSettingsSnapshot(vaultLocation));
  if (isTauri()) {
    const destination = await save({ defaultPath: 'Zerus-desktop-settings.json', filters: [{ name: 'Zerus desktop settings', extensions: ['json'] }] });
    if (!destination) return 'cancelled';
    await writeFile(destination, bytes);
  } else {
    const url = URL.createObjectURL(new Blob([bytes], { type: 'application/json' }));
    const anchor = document.createElement('a'); anchor.href = url; anchor.download = 'Zerus-desktop-settings.json';
    try { anchor.click(); } finally { setTimeout(() => URL.revokeObjectURL(url), 0); }
  }
  return 'saved';
}
