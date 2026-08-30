import { DEFAULT_TYPE, parseTypePath, typeKey } from "@/lib/note-utils";

const DEFAULT_TYPE_STORAGE_PREFIX = "zerus.defaultNoteType.";
const TYPE_ORDER_STORAGE_PREFIX = "zerus.noteTypeOrder.";
const HIDE_SUBTYPE_NOTES_STORAGE_PREFIX = "zerus.hideSubtypeNotes.";
const NOTE_WIDTH_STORAGE_KEY = "zerus.noteWidth";
const NOTE_ALIGNMENT_STORAGE_KEY = "zerus.noteAlignment";
const PROPERTIES_PANEL_KEEP_OPEN_STORAGE_KEY = "zerus.propertiesPanelKeepOpen";
const FILE_HUB_EXPANSION_STORAGE_KEY = "zerus.fileHubExpansion.v1";
const HTML_PREVIEW_MODE_STORAGE_KEY = "zerus.htmlPreviewMode.v1";

export type FileHubExpandedSection = "preview" | "markdown";
export type HtmlPreviewMode = "link" | "safe" | "full";
export interface HtmlPreviewPreference {
  mode: HtmlPreviewMode;
  fingerprint: string | null;
}

export const NOTE_WIDTH_OPTIONS = [100, 85, 75, 60] as const;
export type NoteWidth = (typeof NOTE_WIDTH_OPTIONS)[number];
export const DEFAULT_NOTE_WIDTH: NoteWidth = 75;
export const NOTE_ALIGNMENT_OPTIONS = ["left", "center"] as const;
export type NoteAlignment = (typeof NOTE_ALIGNMENT_OPTIONS)[number];
export const DEFAULT_NOTE_ALIGNMENT: NoteAlignment = "center";

function storageKey(vaultLocation: string | null): string {
  return `${DEFAULT_TYPE_STORAGE_PREFIX}${vaultLocation ?? "unknown"}`;
}

function typeOrderStorageKey(vaultLocation: string | null): string {
  return `${TYPE_ORDER_STORAGE_PREFIX}${vaultLocation ?? "browser"}`;
}

function hideSubtypeNotesStorageKey(vaultLocation: string | null): string {
  return `${HIDE_SUBTYPE_NOTES_STORAGE_PREFIX}${vaultLocation ?? "browser"}`;
}

function isNoteWidth(value: unknown): value is NoteWidth {
  return NOTE_WIDTH_OPTIONS.some((option) => option === value);
}

function isNoteAlignment(value: unknown): value is NoteAlignment {
  return NOTE_ALIGNMENT_OPTIONS.some((option) => option === value);
}

function fileHubExpansionPreferences(): Record<string, FileHubExpandedSection> {
  try {
    const saved = JSON.parse(
      localStorage.getItem(FILE_HUB_EXPANSION_STORAGE_KEY) ?? "{}",
    ) as unknown;
    if (!saved || typeof saved !== "object" || Array.isArray(saved)) return {};
    return Object.fromEntries(
      Object.entries(saved).filter(
        (entry): entry is [string, FileHubExpandedSection] =>
          entry[1] === "preview" || entry[1] === "markdown",
      ),
    );
  } catch {
    return {};
  }
}

function htmlPreviewPreferences(): Record<string, HtmlPreviewPreference> {
  try {
    const saved = JSON.parse(
      localStorage.getItem(HTML_PREVIEW_MODE_STORAGE_KEY) ?? "{}",
    ) as unknown;
    if (!saved || typeof saved !== "object" || Array.isArray(saved)) return {};
    return Object.fromEntries(Object.entries(saved).flatMap(([id, value]) => {
      if (value === "link" || value === "safe" || value === "full") {
        return [[id, { mode: value, fingerprint: null }]];
      }
      if (!value || typeof value !== "object" || Array.isArray(value)) return [];
      const candidate = value as { mode?: unknown; fingerprint?: unknown };
      if (candidate.mode !== "link" && candidate.mode !== "safe" && candidate.mode !== "full") return [];
      return [[id, {
        mode: candidate.mode,
        fingerprint: typeof candidate.fingerprint === "string" ? candidate.fingerprint : null,
      }]];
    }));
  } catch {
    return {};
  }
}

export function loadHtmlPreviewMode(fileHubId: string): HtmlPreviewMode | null {
  return loadHtmlPreviewPreference(fileHubId)?.mode ?? null;
}

export function loadHtmlPreviewPreference(fileHubId: string): HtmlPreviewPreference | null {
  return htmlPreviewPreferences()[fileHubId] ?? null;
}

export function saveHtmlPreviewMode(
  fileHubId: string,
  mode: HtmlPreviewMode,
  fingerprint: string | null = null,
): void {
  if (!fileHubId) return;
  try {
    localStorage.setItem(
      HTML_PREVIEW_MODE_STORAGE_KEY,
      JSON.stringify({
        ...htmlPreviewPreferences(),
        [fileHubId]: { mode, fingerprint: mode === "full" ? fingerprint : null },
      }),
    );
  } catch {
    // Persistence is best-effort; the selected preview still applies this session.
  }
}

/** Loads which half of a PDF or HTML file hub is expanded on this device. */
export function loadFileHubExpandedSection(
  fileHubId: string,
): FileHubExpandedSection | null {
  return fileHubExpansionPreferences()[fileHubId] ?? null;
}

/** Persists the expansion independently for each attached file. */
export function saveFileHubExpandedSection(
  fileHubId: string,
  section: FileHubExpandedSection | null,
): void {
  if (!fileHubId) return;
  try {
    const saved = fileHubExpansionPreferences();
    if (section) saved[fileHubId] = section;
    else delete saved[fileHubId];
    localStorage.setItem(FILE_HUB_EXPANSION_STORAGE_KEY, JSON.stringify(saved));
  } catch {
    // Persistence is best-effort; the selected expansion still applies this session.
  }
}

/** Loads the app-wide note column width saved on this device. */
export function loadNoteWidth(): NoteWidth {
  try {
    const saved = Number(localStorage.getItem(NOTE_WIDTH_STORAGE_KEY));
    return isNoteWidth(saved) ? saved : DEFAULT_NOTE_WIDTH;
  } catch {
    return DEFAULT_NOTE_WIDTH;
  }
}

/** Applies a note width immediately to every editor. */
export function applyNoteWidth(width: NoteWidth): void {
  document.documentElement.style.setProperty("--zerus-note-width", `${width}%`);
}

/** Saves and applies the app-wide note width. */
export function saveNoteWidth(width: NoteWidth): void {
  applyNoteWidth(width);
  try {
    localStorage.setItem(NOTE_WIDTH_STORAGE_KEY, String(width));
  } catch {
    // Persistence is best-effort; the chosen width still applies this session.
  }
}

/** Applies the saved note width once during startup. */
export function initNoteWidth(): void {
  applyNoteWidth(loadNoteWidth());
}

/** Loads the app-wide note alignment saved on this device. */
export function loadNoteAlignment(): NoteAlignment {
  try {
    const saved = localStorage.getItem(NOTE_ALIGNMENT_STORAGE_KEY);
    return isNoteAlignment(saved) ? saved : DEFAULT_NOTE_ALIGNMENT;
  } catch {
    return DEFAULT_NOTE_ALIGNMENT;
  }
}

/** Applies a note alignment immediately to every editor. */
export function applyNoteAlignment(alignment: NoteAlignment): void {
  document.documentElement.style.setProperty(
    "--zerus-note-margin-inline",
    alignment === "center" ? "auto" : "0 auto",
  );
}

/** Saves and applies the app-wide note alignment. */
export function saveNoteAlignment(alignment: NoteAlignment): void {
  applyNoteAlignment(alignment);
  try {
    localStorage.setItem(NOTE_ALIGNMENT_STORAGE_KEY, alignment);
  } catch {
    // Persistence is best-effort; the alignment still applies this session.
  }
}

/** Applies the saved note alignment once during startup. */
export function initNoteAlignment(): void {
  applyNoteAlignment(loadNoteAlignment());
}

/** Loads whether the properties panel should stay open when changing notes. */
export function loadPropertiesPanelKeepOpen(): boolean {
  try {
    return localStorage.getItem(PROPERTIES_PANEL_KEEP_OPEN_STORAGE_KEY) === "true";
  } catch {
    return false;
  }
}

/** Persists the properties-panel behavior on this device. */
export function savePropertiesPanelKeepOpen(keepOpen: boolean): void {
  try {
    localStorage.setItem(
      PROPERTIES_PANEL_KEEP_OPEN_STORAGE_KEY,
      String(keepOpen),
    );
  } catch {
    // Persistence is best-effort; the selected behavior still applies this session.
  }
}


/** Loads the type used for notes created from All Notes in this vault. */
export function loadDefaultNoteType(vaultLocation: string | null): string[] {
  if (!vaultLocation) return [...DEFAULT_TYPE];
  try {
    const raw = localStorage.getItem(storageKey(vaultLocation));
    if (!raw) return [...DEFAULT_TYPE];
    const saved = JSON.parse(raw) as unknown;
    if (!Array.isArray(saved) || !saved.every((part) => typeof part === "string")) {
      return [...DEFAULT_TYPE];
    }
    const typePath = parseTypePath(saved.join("/"));
    return typePath.length ? typePath : [...DEFAULT_TYPE];
  } catch {
    return [...DEFAULT_TYPE];
  }
}

/** Saves the default independently for each vault on this device. */
export function saveDefaultNoteType(
  vaultLocation: string | null,
  typePath: string[],
): void {
  if (!vaultLocation || !typePath.length) return;
  try {
    localStorage.setItem(storageKey(vaultLocation), JSON.stringify(typePath));
  } catch {
    // Persistence is best-effort; the selected type still applies this session.
  }
}

/** Loads the user-defined order of type paths for a vault. */
export function loadNoteTypeOrder(vaultLocation: string | null): string[] {
  try {
    const raw = localStorage.getItem(typeOrderStorageKey(vaultLocation));
    if (!raw) return [];
    const saved = JSON.parse(raw) as unknown;
    if (!Array.isArray(saved)) return [];
    const unique = new Set<string>();
    for (const value of saved) {
      if (typeof value !== "string") continue;
      const normalized = typeKey(parseTypePath(value));
      if (normalized) unique.add(normalized);
    }
    return [...unique];
  } catch {
    return [];
  }
}

/** Saves type order independently for each vault on this device. */
export function saveNoteTypeOrder(
  vaultLocation: string | null,
  order: string[],
): void {
  try {
    localStorage.setItem(typeOrderStorageKey(vaultLocation), JSON.stringify(order));
  } catch {
    // Persistence is best-effort; the chosen order still applies this session.
  }
}

/** Loads whether a selected type should exclude notes from nested sub-types. */
export function loadHideSubtypeNotes(vaultLocation: string | null): boolean {
  try {
    return localStorage.getItem(hideSubtypeNotesStorageKey(vaultLocation)) === "true";
  } catch {
    return false;
  }
}

/** Saves the nested sub-type visibility independently for each vault. */
export function saveHideSubtypeNotes(
  vaultLocation: string | null,
  hidden: boolean,
): void {
  try {
    localStorage.setItem(hideSubtypeNotesStorageKey(vaultLocation), String(hidden));
  } catch {
    // Persistence is best-effort; the selected visibility still applies this session.
  }
}
