import { useSyncExternalStore } from "react";
import { invoke, isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import { openPath } from "@tauri-apps/plugin-opener";
import {
  readFile,
  readTextFile,
  remove as removeFsFile,
  stat,
  watch,
  writeTextFile,
  type UnwatchFn,
  type WatchEvent,
} from "@tauri-apps/plugin-fs";
import {
  DEFAULT_TYPE,
  MAX_TYPE_DEPTH,
  TRASH_DIR,
  type Note,
  fileStem,
  getAllTypePaths,
  isExternalNote,
  isSavedLinkNote,
  isRemoteUrl,
  isTrashed,
  logicalPath,
  normalizeFsPath,
  noteAbsolutePath,
  noteSnippet,
  noteTitle,
  noteTypePath,
  notesOfTypeKey,
  sanitizeFileStem,
  typeKey,
} from "@/lib/note-utils";
import {
  type NoteAttachment,
  getNoteAttachments,
  setNoteAttachments,
} from "@/lib/note-attachments";
import {
  type PropertyValue,
  getNoteProperties,
  noteBody,
  renameContentProperty,
  setContentProperty,
  withBody,
} from "@/lib/frontmatter";
import {
  isReservedZerusProperty,
  readZerusMetadata,
  setZerusState,
} from "@/lib/zerus-metadata";
import {
  type PropertyDef,
  type PropertySchemas,
  listPropertyValue,
  listSelections,
  propertyDefinitionOwner,
} from "@/lib/properties";
import {
  type TypeIcons,
  isTypeIconValue,
  suggestIconForType,
} from "@/lib/type-icons";
import type { VaultBackend, VaultFile, VaultFileEntry } from "@/lib/vault/backend";
import { BrowserVault } from "@/lib/vault/browser";
import { DesktopVault } from "@/lib/vault/desktop";
import { MobileFolderVault, MobileVault } from "@/lib/vault/mobile";
import {
  clearMobileVaultFolder,
  openMobileFile,
  pickMobileExternalNotes,
  pickMobileFiles,
  pickMobileFileLocationFolder,
  pickMobileVaultFolder,
  restoreMobileVaultFolder,
} from "@/lib/mobile-vault-picker";
import { showError } from "@/utils/toast";
import { mobileDiagnostic } from "@/lib/mobile-diagnostics";
import {
  loadDefaultNoteType,
} from "@/lib/note-preferences";
import {
  fileNameFromPath,
  getFileHubReference,
  isMarkdownFilePath,
  mostSpecificLocation,
  normalizeRelativeFilePath,
  parseFileLocations,
  pathInsideRoot,
  removeFileHubReference,
  resolveFileHubReference,
  serializeFileLocations,
  setFileHubReference,
  type FileHubReference,
  type FileLocationDefinition,
  type ResolvedFileHub,
} from "@/lib/file-hubs";
import {
  getLinkHubReference,
  linkDisplayName,
  removeLinkHubReference,
  setLinkHubReference,
  withLinkMarkdown,
} from "@/lib/link-hubs";
import { normalizeExternalUrl, openExternalUrl } from "@/lib/external-links";
import {
  normalizeTypeViewConfig,
  normalizeTypeViewConfigs,
  type TypeViewConfig,
  type TypeViewConfigs,
} from "@/lib/note-views";
import {
  loadDesktopVaults,
  rememberDesktopVault,
  type DesktopVaultEntry,
} from "@/lib/vault-registry";
import {
  DEFAULT_HISTORY_SETTINGS,
  type HistorySettings,
  type HistorySource,
  type NoteHistoryVersion,
  clearAllHistory as clearAllStoredHistory,
  clearNoteHistory as clearStoredNoteHistory,
  listNoteHistory,
  loadHistorySettings,
  materializeHistoryImages,
  preserveCurrentZerusMetadata,
  recordNoteHistory,
  saveHistorySettings,
  updateHistoryVersion,
} from "@/lib/note-history";
import { ImageUrlCache } from "@/lib/image-url-cache";
import {
  createImageMutationQueue,
  imageReferenceCount,
  loadedNotesShareImage,
  moveImageWithRollback,
  unloadedNotesReferenceImage,
} from "@/lib/image-lifecycle";

const VAULT_PATH_KEY = "zerus.vaultPath";
const EXTERNAL_PATHS_KEY = "zerus.externalPaths";
const FILE_LOCATION_MAPPINGS_KEY = "zerus.fileLocationMappings.v1";
const FILE_HUB_MAPPINGS_KEY = "zerus.fileHubMappings.v1";
const STARTUP_CACHE_KEY_PREFIX = "zerus.startupCache.v1.";
const SAVED_LINKS_DIR = ".zerus/links";
const SAVED_LINKS_INDEX_PATH = ".zerus/links.json";
const TRASHED_IMAGES_INDEX_PATH = ".zerus/trashed-images.json";
const FLUSH_DELAY_MS = 5_000;
const MOBILE_NOTE_PAGE_SIZE = 30;

function isManagedSavedLink(note: Note): boolean {
  return isSavedLinkNote(note) && note.path.startsWith(`${SAVED_LINKS_DIR}/`);
}

export interface VaultState {
  status: "booting" | "pick-vault" | "loading" | "ready" | "error";
  /** Where notes are stored — absolute folder path on desktop. */
  location: string | null;
  isDesktop: boolean;
  notes: Note[];
  /** Recoverable image attachments currently held in Zerus Trash. */
  trashedImages: TrashedImage[];
  /** Total non-trashed vault notes, including notes whose bodies are not loaded yet. */
  totalNoteCount: number;
  /** Direct note totals keyed by exact type path. */
  typeNoteCounts: Readonly<Record<string, number>>;
  isNotePaginationEnabled: boolean;
  hasMoreNotes: boolean;
  isLoadingMoreNotes: boolean;
  /** Types that exist as folders even without notes in them (empty types). */
  extraTypes: string[][];
  /** Property definitions, keyed by top-level type key ("work"). */
  schemas: PropertySchemas;
  /** Custom Tabler icon per type, keyed by full type key ("work/projects"). */
  typeIcons: TypeIcons;
  /** Portable view configuration per folder-backed note type. */
  typeViews: TypeViewConfigs;
  /** Synced names/IDs for portable base folders. Absolute roots stay local. */
  fileLocations: FileLocationDefinition[];
  /** Notes temporarily locked while a close or move operation commits. */
  busyNoteIds: ReadonlySet<string>;
  /** Notes whose real disk content has not arrived during startup refresh. */
  loadingNoteIds: ReadonlySet<string>;
  /** The cached note index is visible while the desktop vault refreshes. */
  isRefreshing: boolean;
  /** Simultaneous editor and disk edits awaiting an explicit user choice. */
  conflicts: Readonly<Record<string, NoteConflict>>;
  historySettings: HistorySettings;
  historyError: string | null;
  error: string | null;
}

export interface TrashedImage {
  id: string;
  name: string;
  originalPath: string;
  trashPath: string;
  deletedAt: string;
  /** Note and source used to reattach the image when restored from Trash. */
  noteId?: string;
  markdown?: string;
}

export interface NoteConflict {
  noteId: string;
  currentContent: string;
  diskContent: string | null;
  diskPath: string;
  kind: "modified" | "deleted";
}

let state: VaultState = {
  status: "booting",
  location: null,
  isDesktop: false,
  notes: [],
  trashedImages: [],
  totalNoteCount: 0,
  typeNoteCounts: {},
  isNotePaginationEnabled: false,
  hasMoreNotes: false,
  isLoadingMoreNotes: false,
  extraTypes: [],
  schemas: {},
  typeIcons: {},
  typeViews: {},
  fileLocations: [],
  busyNoteIds: new Set(),
  loadingNoteIds: new Set(),
  isRefreshing: false,
  conflicts: {},
  historySettings: DEFAULT_HISTORY_SETTINGS,
  historyError: null,
  error: null,
};

let backend: VaultBackend | null = null;
let mobileNoteEntries: VaultFileEntry[] = [];
let mobileNoteLoad: Promise<void> | null = null;
let initialized = false;
const listeners = new Set<() => void>();
const pendingFlush = new Map<string, ReturnType<typeof setTimeout>>();
const inFlightFlush = new Map<string, Promise<boolean>>();
const diskSnapshots = new Map<string, string>();
const externalPathRegistry = new Map<string, string>();
let desktopCloseHookInstalled = false;
let closingAfterFlush = false;
let desktopOpenHookInstalled = false;
let desktopOpenDrain: Promise<void> | null = null;
let desktopSyncTimer: ReturnType<typeof setInterval> | null = null;
let desktopSyncDebounceTimer: ReturnType<typeof setTimeout> | null = null;
let desktopSyncInFlight = false;
let desktopSyncRequested = false;
let desktopWatchGeneration = 0;
let stopDesktopWatch: UnwatchFn | null = null;
const desktopVaultChangeListeners = new Set<() => void>();
let typeViewsWriteInFlight: Promise<void> = Promise.resolve();
const pendingDesktopOpenPaths: string[] = [];
const pendingStartupNoteLoads = new Map<string, Promise<void>>();
const startupEditedNoteIds = new Set<string>();
const pendingHistorySource = new Map<string, HistorySource>();
const historyWarnings = new Set<string>();
interface SuspendedVaultConflict {
  note: Note;
  conflict: NoteConflict;
}
const suspendedDesktopConflicts = new Map<string, SuspendedVaultConflict[]>();
const desktopOpenListeners = new Set<
  (
    ids: string[],
    firstNoteIsExternal: boolean,
    firstNoteIsFileHub: boolean,
  ) => void
>();

function conflictNoteKey(note: Note): string {
  return note.externalPath
    ? `external:${normalizeFsPath(note.externalPath)}`
    : `vault:${normalizeFsPath(note.path)}`;
}

/** Keeps unresolved edits alive while another desktop vault is open. */
function suspendCurrentDesktopConflicts(): void {
  if (backend?.kind !== "desktop" || !state.location) return;
  const suspended = Object.values(state.conflicts).flatMap((conflict) => {
    const note = state.notes.find((candidate) => candidate.id === conflict.noteId);
    return note ? [{ note: { ...note }, conflict: { ...conflict } }] : [];
  });
  if (suspended.length) suspendedDesktopConflicts.set(state.location, suspended);
  else suspendedDesktopConflicts.delete(state.location);
}

function restoreDesktopConflicts(
  location: string,
  notes: Note[],
): { notes: Note[]; conflicts: Record<string, NoteConflict> } {
  const suspended = suspendedDesktopConflicts.get(location);
  if (!suspended?.length) return { notes, conflicts: {} };

  suspendedDesktopConflicts.delete(location);
  const restoredNotes = [...notes];
  const conflicts: Record<string, NoteConflict> = {};
  for (const saved of suspended) {
    const key = conflictNoteKey(saved.note);
    const index = restoredNotes.findIndex((note) => conflictNoteKey(note) === key);
    const diskNote = index >= 0 ? restoredNotes[index] : saved.note;
    const note = {
      ...diskNote,
      content: saved.conflict.currentContent,
      updatedAt: saved.note.updatedAt,
    };
    if (index >= 0) restoredNotes[index] = note;
    else restoredNotes.push(note);
    conflicts[note.id] = {
      ...saved.conflict,
      noteId: note.id,
      diskPath: noteAbsolutePath(note, location) ?? saved.conflict.diskPath,
    };
  }
  return { notes: restoredNotes, conflicts };
}

function emit() {
  listeners.forEach((listener) => listener());
}

function historyOriginId(): string {
  const key = "zerus.historyOriginId.v1";
  try {
    const existing = localStorage.getItem(key);
    if (existing) return existing;
    const created = crypto.randomUUID();
    localStorage.setItem(key, created);
    return created;
  } catch {
    return "session";
  }
}

function localHistorySource(): HistorySource {
  if (backend?.kind === "mobile") return "mobile";
  if (backend?.kind === "browser") return "browser";
  return "desktop";
}

async function recordHistorySafely(
  noteId: string,
  before: string,
  after: string,
  source: HistorySource,
): Promise<void> {
  const targetBackend = backend;
  const note = state.notes.find((candidate) => candidate.id === noteId);
  if (!targetBackend || !note || isExternalNote(note)) return;
  try {
    await recordNoteHistory(targetBackend, {
      noteId,
      before,
      after,
      source,
      originId: historyOriginId(),
      settings: state.historySettings,
    });
    historyWarnings.delete(noteId);
    if (state.historyError) setState({ historyError: null });
  } catch (error) {
    const message = `Version history needs repair: ${String(error)}`;
    setState({ historyError: message });
    if (!historyWarnings.has(noteId)) {
      historyWarnings.add(noteId);
      showError(message);
    }
  }
}

function setState(patch: Partial<VaultState>) {
  state = { ...state, ...patch };
  emit();
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useVault(): VaultState {
  return useSyncExternalStore(subscribe, () => state);
}

export function getNotes(): Note[] {
  return state.notes;
}

export function prioritizeNoteLoad(id: string): Promise<void> {
  if (!state.loadingNoteIds.has(id) || !(backend instanceof DesktopVault)) {
    return Promise.resolve();
  }
  const existing = pendingStartupNoteLoads.get(id);
  if (existing) return existing;
  const activeBackend = backend;
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note) return Promise.resolve();
  const operation = activeBackend
    .loadFile(note.path)
    .then((file) => {
      if (backend !== activeBackend) return;
      const current = state.notes.find((candidate) => candidate.id === id);
      if (!current) return;
      const loaded = noteFromVaultFile(
        file,
        loadPinnedPaths(),
        loadArchivedPaths(),
        id,
      );
      diskSnapshots.set(id, file.content);
      const loadingNoteIds = new Set(state.loadingNoteIds);
      loadingNoteIds.delete(id);
      setState({
        notes: state.notes.map((candidate) =>
          candidate.id === id ? loaded : candidate,
        ),
        loadingNoteIds,
      });
    })
    .catch((error) => {
      console.error("Zerus: failed to prioritize startup note", error);
    })
    .finally(() => {
      pendingStartupNoteLoads.delete(id);
    });
  pendingStartupNoteLoads.set(id, operation);
  return operation;
}

/** Active vault access for vault-local feature metadata such as chat history. */
export function getVaultBackend(): VaultBackend | null {
  return backend;
}

function loadStringMap(key: string): Record<string, string> {
  try {
    const parsed = JSON.parse(localStorage.getItem(key) ?? "{}") as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    return Object.fromEntries(
      Object.entries(parsed).filter(
        (entry): entry is [string, string] => typeof entry[1] === "string",
      ),
    );
  } catch {
    return {};
  }
}

function saveStringMap(key: string, value: Record<string, string>) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Device-local mappings are best effort and can always be recreated.
  }
}

export function getFileLocationMappings(): Record<string, string> {
  return loadStringMap(FILE_LOCATION_MAPPINGS_KEY);
}

export function getFileHubMappings(): Record<string, string> {
  return loadStringMap(FILE_HUB_MAPPINGS_KEY);
}

function setFileLocationMapping(id: string, path: string | null) {
  const mappings = getFileLocationMappings();
  if (path) mappings[id] = path;
  else delete mappings[id];
  saveStringMap(FILE_LOCATION_MAPPINGS_KEY, mappings);
  setState({});
}

export function setFileHubMapping(id: string, path: string | null) {
  const mappings = getFileHubMappings();
  if (path) mappings[id] = path;
  else delete mappings[id];
  saveStringMap(FILE_HUB_MAPPINGS_KEY, mappings);
  setState({});
}

// ---- note display state, persisted per vault ------------------------------

function pinnedStorageKey(): string {
  return `zerus.pinned.${state.location ?? "browser"}`;
}

function loadPinnedPaths(): Set<string> {
  try {
    const raw = localStorage.getItem(pinnedStorageKey());
    if (raw) return new Set(JSON.parse(raw) as string[]);
  } catch {
    // ignore
  }
  return new Set();
}

function savePinnedPaths() {
  try {
    const paths = state.notes
      .filter((note) => note.pinned && !isExternalNote(note))
      .map((note) => logicalPath(note));
    localStorage.setItem(pinnedStorageKey(), JSON.stringify(paths));
  } catch {
    // ignore
  }
}

function archivedStorageKey(): string {
  return `zerus.archived.${state.location ?? "browser"}`;
}

function loadArchivedPaths(): Set<string> {
  try {
    const raw = localStorage.getItem(archivedStorageKey());
    if (raw) return new Set(JSON.parse(raw) as string[]);
  } catch {
    // ignore malformed or unavailable local storage
  }
  return new Set();
}

function saveArchivedPaths() {
  try {
    const paths = state.notes
      .filter((note) => note.archived && !isExternalNote(note) && !isTrashed(note))
      .map((note) => logicalPath(note));
    localStorage.setItem(archivedStorageKey(), JSON.stringify(paths));
  } catch {
    // ignore unavailable local storage
  }
}

function saveNoteDisplayState() {
  savePinnedPaths();
  saveArchivedPaths();
}

// ---- external notes, persisted as absolute paths across vaults -------------

function loadExternalPaths(): string[] {
  try {
    const raw = localStorage.getItem(EXTERNAL_PATHS_KEY);
    if (raw) {
      const parsed: unknown = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        return parsed.filter(
          (path): path is string => typeof path === "string",
        );
      }
    }
  } catch {
    // ignore malformed or unavailable storage
  }
  return [];
}

function saveExternalPaths() {
  try {
    localStorage.setItem(
      EXTERNAL_PATHS_KEY,
      JSON.stringify([...externalPathRegistry.values()]),
    );
  } catch {
    // ignore unavailable storage
  }
}

function registerExternalPath(path: string) {
  externalPathRegistry.set(normalizeFsPath(path), path);
}

function forgetExternalPath(path: string) {
  externalPathRegistry.delete(normalizeFsPath(path));
}

async function canonicalizeFsPath(path: string): Promise<string> {
  if (!isTauri()) return path;
  try {
    return await invoke<string>("canonicalize_path", { path });
  } catch {
    return path;
  }
}

function externalFileName(path: string): string {
  return path.split(/[\\/]/).pop() || "Untitled.md";
}

async function readExternalNote(path: string): Promise<Note> {
  const [content, info] = await Promise.all([readTextFile(path), stat(path)]);
  return {
    id: crypto.randomUUID(),
    path: externalFileName(path),
    externalPath: path,
    content,
    pinned: false,
    archived: false,
    createdAt: (info.birthtime ?? info.mtime ?? new Date()).toISOString(),
    updatedAt: (info.mtime ?? new Date()).toISOString(),
  };
}

async function loadExternalNotes(): Promise<Note[]> {
  for (const path of loadExternalPaths()) registerExternalPath(path);
  const paths = [...externalPathRegistry.values()];
  const distinctPaths = new Map<string, string>();
  let registryChanged = false;
  for (const path of paths) {
    const canonicalPath = await canonicalizeFsPath(path);
    distinctPaths.set(normalizeFsPath(canonicalPath), canonicalPath);
    if (canonicalPath !== path) {
      forgetExternalPath(path);
      registerExternalPath(canonicalPath);
      registryChanged = true;
    }
  }
  if (registryChanged) saveExternalPaths();
  const loaded = await Promise.all(
    [...distinctPaths.values()].map(async (path) => {
      try {
        return await readExternalNote(path);
      } catch {
        return null;
      }
    }),
  );
  return loaded.filter((note): note is Note => note !== null);
}

async function loadSavedLinkPaths(fromBackend: VaultBackend): Promise<string[]> {
  try {
    const parsed: unknown = JSON.parse(
      await fromBackend.readText(SAVED_LINKS_INDEX_PATH),
    );
    if (!Array.isArray(parsed)) return [];
    return [
      ...new Set(
        parsed.filter(
          (path): path is string =>
            typeof path === "string" &&
            path.startsWith(`${SAVED_LINKS_DIR}/`),
        ),
      ),
    ];
  } catch {
    return [];
  }
}

async function saveSavedLinkPaths(paths: string[]): Promise<void> {
  if (!backend) return;
  await backend.write(SAVED_LINKS_INDEX_PATH, JSON.stringify(paths, null, 2));
}

async function loadSavedLinkNotes(fromBackend: VaultBackend): Promise<Note[]> {
  const paths = await loadSavedLinkPaths(fromBackend);
  const loaded = await Promise.all(
    paths.map(async (path) => {
      try {
        const file = fromBackend.loadFiles
          ? (await fromBackend.loadFiles([path]))[0]
          : {
              path,
              content: await fromBackend.readText(path),
              updatedAt: new Date().toISOString(),
            };
        if (!file || !getLinkHubReference(file.content)) return null;
        return noteFromVaultFile(
          file,
          new Set(),
          new Set(),
        );
      } catch {
        return null;
      }
    }),
  );
  const notes = loaded.filter((note): note is Note => note !== null);
  if (notes.length !== paths.length) {
    await saveSavedLinkPaths(notes.map((note) => note.path));
  }
  return notes;
}

// ---- vault lifecycle -------------------------------------------------------

const SCHEMAS_PATH = ".zerus/properties.json";

async function loadSchemas(
  fromBackend: VaultBackend,
): Promise<PropertySchemas> {
  try {
    const raw = await fromBackend.readText(SCHEMAS_PATH);
    const parsed = JSON.parse(raw) as PropertySchemas;
    if (!parsed || typeof parsed !== "object") return {};
    return parsed;
  } catch {
    return {}; // missing or unreadable — start empty
  }
}

const TYPE_ICONS_PATH = ".zerus/type-icons.json";
const TYPE_VIEWS_PATH = ".zerus/views.json";
const FILE_LOCATIONS_PATH = ".zerus/file-locations.json";

async function loadTypeIcons(fromBackend: VaultBackend): Promise<TypeIcons> {
  try {
    const raw = await fromBackend.readText(TYPE_ICONS_PATH);
    const parsed = JSON.parse(raw) as TypeIcons;
    if (!parsed || typeof parsed !== "object") return {};
    // Keep current Tabler values and legacy emoji; drop obsolete Lucide names.
    const typeIcons: TypeIcons = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (isTypeIconValue(value)) typeIcons[key] = value;
    }
    return typeIcons;
  } catch {
    return {}; // missing or unreadable — start empty
  }
}

async function loadTypeViews(
  fromBackend: VaultBackend,
): Promise<TypeViewConfigs> {
  try {
    return normalizeTypeViewConfigs(
      JSON.parse(await fromBackend.readText(TYPE_VIEWS_PATH)),
    );
  } catch {
    return {};
  }
}

async function loadFileLocations(
  fromBackend: VaultBackend,
): Promise<FileLocationDefinition[]> {
  try {
    return parseFileLocations(await fromBackend.readText(FILE_LOCATIONS_PATH));
  } catch {
    return [];
  }
}

interface StartupCachedNote {
  id: string;
  path: string;
  title: string;
  snippet: string;
  pinned: boolean;
  archived: boolean;
  createdAt?: string;
  updatedAt: string;
}

interface StartupVaultCache {
  version: 1;
  location: string;
  notes: StartupCachedNote[];
  extraTypes: string[][];
  schemas: PropertySchemas;
  typeIcons: TypeIcons;
  typeViews?: TypeViewConfigs;
  fileLocations: FileLocationDefinition[];
}

function startupCacheKey(location: string): string {
  return `${STARTUP_CACHE_KEY_PREFIX}${location}`;
}

function loadStartupCache(location: string): StartupVaultCache | null {
  try {
    const parsed = JSON.parse(
      localStorage.getItem(startupCacheKey(location)) ?? "null",
    ) as StartupVaultCache | null;
    if (
      !parsed ||
      parsed.version !== 1 ||
      parsed.location !== location ||
      !Array.isArray(parsed.notes) ||
      !Array.isArray(parsed.extraTypes)
    ) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

function cachedNotePlaceholder(note: StartupCachedNote): Note {
  return {
    id: note.id,
    path: note.path,
    content: `# ${note.title}\n\n${note.snippet}`,
    pinned: note.pinned,
    archived: note.archived,
    createdAt: note.createdAt ?? note.updatedAt,
    updatedAt: note.updatedAt,
  };
}

function saveStartupCache(
  location: string,
  notes: Note[],
  extraTypes: string[][],
  schemas: PropertySchemas,
  typeIcons: TypeIcons,
  typeViews: TypeViewConfigs,
  fileLocations: FileLocationDefinition[],
) {
  const cachedNotes = notes
    .filter((note) => !isExternalNote(note))
    .map<StartupCachedNote>((note) => ({
      id: note.id,
      path: note.path,
      title: noteTitle(note),
      snippet: noteSnippet(note),
      pinned: note.pinned,
      archived: note.archived === true,
      createdAt: note.createdAt ?? note.updatedAt,
      updatedAt: note.updatedAt,
    }))
    .sort((left, right) => {
      if (left.pinned !== right.pinned) return left.pinned ? -1 : 1;
      return right.updatedAt.localeCompare(left.updatedAt);
    });
  const cache: StartupVaultCache = {
    version: 1,
    location,
    notes: cachedNotes,
    extraTypes,
    schemas,
    typeIcons,
    typeViews,
    fileLocations,
  };
  try {
    localStorage.setItem(startupCacheKey(location), JSON.stringify(cache));
  } catch {
    // The startup index is an optional speed-up and can always be rebuilt.
  }
}

function noteFromVaultFile(
  file: Awaited<ReturnType<DesktopVault["loadFile"]>>,
  pinnedPaths: Set<string>,
  archivedPaths: Set<string>,
  existingId?: string,
): Note {
  const metadata = readZerusMetadata(file.content);
  return {
    id: existingId ?? metadata.id ?? crypto.randomUUID(),
    path: file.path,
    content: file.content,
    pinned: metadata.pinned || pinnedPaths.has(file.path),
    archived: metadata.archived || archivedPaths.has(file.path),
    createdAt: file.createdAt ?? file.updatedAt,
    updatedAt: file.updatedAt,
  };
}

function summarizeMobileEntries(entries: VaultFileEntry[]) {
  const typeNoteCounts: Record<string, number> = {};
  let totalNoteCount = 0;
  for (const entry of entries) {
    if (
      entry.path.startsWith(`${TRASH_DIR}/`) ||
      entry.path === "assets" ||
      entry.path.startsWith("assets/")
    ) {
      continue;
    }
    totalNoteCount += 1;
    const key = entry.path
      .split("/")
      .slice(0, -1)
      .slice(0, MAX_TYPE_DEPTH)
      .join("/");
    if (key) typeNoteCounts[key] = (typeNoteCounts[key] ?? 0) + 1;
  }
  return { totalNoteCount, typeNoteCounts };
}

function isPageableMobileEntry(entry: VaultFileEntry): boolean {
  return (
    !entry.path.startsWith(`${TRASH_DIR}/`) &&
    entry.path !== "assets" &&
    !entry.path.startsWith("assets/")
  );
}

function sortMobileEntries() {
  mobileNoteEntries.sort(
    (a, b) =>
      new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime() ||
      a.path.localeCompare(b.path),
  );
}

function updateMobileEntry(previousPath: string, nextPath: string, updatedAt: string) {
  if (!state.isNotePaginationEnabled) return;
  const entry = mobileNoteEntries.find((candidate) => candidate.path === previousPath);
  if (entry) {
    entry.path = nextPath;
    entry.updatedAt = updatedAt;
  } else if (isPageableMobileEntry({ path: nextPath, updatedAt })) {
    mobileNoteEntries.push({ path: nextPath, updatedAt });
  }
  mobileNoteEntries = mobileNoteEntries.filter(isPageableMobileEntry);
  sortMobileEntries();
}

function removeMobileEntry(path: string) {
  if (!state.isNotePaginationEnabled) return;
  mobileNoteEntries = mobileNoteEntries.filter((entry) => entry.path !== path);
}

function loadedMobilePaths(): Set<string> {
  return new Set(
    state.notes.filter((note) => !isExternalNote(note)).map((note) => note.path),
  );
}

async function loadVault(nextBackend: VaultBackend) {
  mobileDiagnostic("store.vault.load.started", {
    kind: nextBackend.kind,
    location: nextBackend.location,
  });
  stopWatchingDesktopVault();
  backend = nextBackend;
  mobileNoteEntries = [];
  mobileNoteLoad = null;
  clearImageUrlCache();
  pendingStartupNoteLoads.clear();
  startupEditedNoteIds.clear();
  setState({
    status: "loading",
    location: nextBackend.location,
    isDesktop: nextBackend.kind === "desktop",
    notes: [],
    trashedImages: [],
    totalNoteCount: 0,
    typeNoteCounts: {},
    isNotePaginationEnabled: false,
    hasMoreNotes: false,
    isLoadingMoreNotes: false,
    extraTypes: [],
    schemas: {},
    typeIcons: {},
    typeViews: {},
    fileLocations: [],
    busyNoteIds: new Set(),
    loadingNoteIds: new Set(),
    isRefreshing: false,
    conflicts: {},
    historySettings: DEFAULT_HISTORY_SETTINGS,
    historyError: null,
    error: null,
  });
  try {
    const startupCache =
      nextBackend.kind === "desktop"
        ? loadStartupCache(nextBackend.location)
        : null;
    if (startupCache) {
      const cachedNotes = startupCache.notes.map(cachedNotePlaceholder);
      setState({
        status: "ready",
        notes: cachedNotes,
        extraTypes: startupCache.extraTypes,
        schemas: startupCache.schemas,
        typeIcons: startupCache.typeIcons,
        typeViews: normalizeTypeViewConfigs(startupCache.typeViews),
        fileLocations: startupCache.fileLocations,
        loadingNoteIds: new Set(cachedNotes.map((note) => note.id)),
        isRefreshing: true,
      });
    }
    const pinned = loadPinnedPaths();
    const archived = loadArchivedPaths();
    const applyPriorityFiles = (
      files: Awaited<ReturnType<DesktopVault["loadAll"]>>,
    ) => {
      if (backend !== nextBackend || files.length === 0) return;
      const existingByPath = new Map(
        state.notes.map((note) => [note.path, note] as const),
      );
      const loadedByPath = new Map(
        files.map((file) => {
          const existing = existingByPath.get(file.path);
          const note = noteFromVaultFile(file, pinned, archived, existing?.id);
          diskSnapshots.set(note.id, file.content);
          return [file.path, note] as const;
        }),
      );
      const notes = state.notes.length
        ? [
            ...state.notes.map((note) => loadedByPath.get(note.path) ?? note),
            ...[...loadedByPath.values()].filter(
              (note) => !existingByPath.has(note.path),
            ),
          ]
        : [...loadedByPath.values()];
      const loadedIds = new Set([...loadedByPath.values()].map((note) => note.id));
      const loadingNoteIds = new Set(state.loadingNoteIds);
      for (const id of loadedIds) loadingNoteIds.delete(id);
      setState({
        status: "ready",
        notes,
        loadingNoteIds,
        isRefreshing: true,
      });
    };
    const priorityPaths = startupCache?.notes
      .filter(
        (note) =>
          !note.archived && !note.path.startsWith(`${TRASH_DIR}/`),
      )
      .map((note) => note.path);
    const canPage =
      nextBackend.kind === "mobile" &&
      nextBackend.listNoteEntries !== undefined &&
      nextBackend.loadFiles !== undefined;
    const [
      noteSource,
      savedLinkNotes,
      schemas,
      dirs,
      typeIcons,
      typeViews,
      fileLocations,
      historySettings,
      trashedImages,
    ] = await Promise.all([
      canPage
        ? nextBackend.listNoteEntries!()
        : nextBackend instanceof DesktopVault
        ? nextBackend.loadAll({
            priorityPaths,
            onPriorityLoaded: applyPriorityFiles,
          })
        : nextBackend.loadAll(),
      loadSavedLinkNotes(nextBackend),
      loadSchemas(nextBackend),
      nextBackend.listDirs(),
      loadTypeIcons(nextBackend),
      loadTypeViews(nextBackend),
      loadFileLocations(nextBackend),
      loadHistorySettings(nextBackend),
      loadTrashedImages(nextBackend),
    ]);
    if (canPage) {
      mobileNoteEntries = (noteSource as VaultFileEntry[]).filter(isPageableMobileEntry);
    }
    const files = canPage
      ? await nextBackend.loadFiles!(
          mobileNoteEntries.slice(0, MOBILE_NOTE_PAGE_SIZE).map((entry) => entry.path),
        )
      : (noteSource as VaultFile[]);
    const vaultNotes: Note[] = files.map((file) => {
      const edited = state.notes.find(
        (note) =>
          note.path === file.path && startupEditedNoteIds.has(note.id),
      );
      const loaded = noteFromVaultFile(file, pinned, archived, edited?.id);
      return edited
        ? {
            ...loaded,
            content: edited.content,
            pinned: edited.pinned,
            archived: edited.archived,
            updatedAt: edited.updatedAt,
          }
        : loaded;
    });
    let externalNotes =
      nextBackend.kind === "browser" ? [] : await loadExternalNotes();
    if (externalNotes.length) {
      const vaultPaths = new Set(
        await Promise.all(
          vaultNotes.map(async (note) =>
            normalizeFsPath(
              await canonicalizeFsPath(
                noteAbsolutePath(note, nextBackend.location) ?? "",
              ),
            ),
          ),
        ),
      );
      const duplicates = externalNotes.filter((note) =>
        vaultPaths.has(normalizeFsPath(note.externalPath as string)),
      );
      for (const note of duplicates) {
        forgetExternalPath(note.externalPath as string);
      }
      if (duplicates.length) saveExternalPaths();
      externalNotes = externalNotes.filter(
        (note) => !vaultPaths.has(normalizeFsPath(note.externalPath as string)),
      );
    }
    // folders are types — except the assets folder, which holds images
    const extraTypes = dirs
      .filter((dir) => dir !== IMAGE_DIR && !dir.startsWith(`${IMAGE_DIR}/`))
      .map((dir) => dir.split("/").slice(0, MAX_TYPE_DEPTH));
    let loadedNotes = [...externalNotes, ...savedLinkNotes, ...vaultNotes];
    const mobileSummary = canPage
      ? summarizeMobileEntries(mobileNoteEntries)
      : { totalNoteCount: vaultNotes.filter((note) => !isTrashed(note)).length, typeNoteCounts: {} };
    const restoredSession =
      nextBackend.kind === "desktop"
        ? restoreDesktopConflicts(nextBackend.location, loadedNotes)
        : { notes: loadedNotes, conflicts: {} };
    loadedNotes = restoredSession.notes;
    diskSnapshots.clear();
    for (const note of loadedNotes) {
      const restoredConflict = restoredSession.conflicts[note.id];
      if (restoredConflict) {
        if (restoredConflict.diskContent !== null) {
          diskSnapshots.set(note.id, restoredConflict.diskContent);
        }
        continue;
      }
      if (startupEditedNoteIds.has(note.id)) {
        const diskFile = files.find((file) => file.path === note.path);
        if (diskFile) diskSnapshots.set(note.id, diskFile.content);
      } else {
        diskSnapshots.set(note.id, note.content);
      }
    }
    const editedIds = [...startupEditedNoteIds].filter((id) =>
      loadedNotes.some((note) => note.id === id),
    );
    setState({
      status: "ready",
      notes: loadedNotes,
      totalNoteCount: mobileSummary.totalNoteCount,
      typeNoteCounts: mobileSummary.typeNoteCounts,
      isNotePaginationEnabled: canPage,
      hasMoreNotes: canPage && files.length < mobileNoteEntries.length,
      isLoadingMoreNotes: false,
      extraTypes,
      schemas,
      typeIcons,
      typeViews,
      fileLocations,
      historySettings,
      trashedImages,
      conflicts: restoredSession.conflicts,
      loadingNoteIds: new Set(),
      isRefreshing: false,
    });
    startupEditedNoteIds.clear();
    for (const id of editedIds) {
      pendingFlush.set(
        id,
        setTimeout(() => void flushNote(id), FLUSH_DELAY_MS),
      );
    }
    if (nextBackend.kind === "desktop") {
      void watchDesktopVault(nextBackend.location);
      saveStartupCache(
        nextBackend.location,
        vaultNotes,
        extraTypes,
        schemas,
        typeIcons,
        typeViews,
        fileLocations,
      );
      void invoke("cli_register_vault", {
        vaultPath: nextBackend.location,
      }).catch((error) => reportError("register vault with CLI", error));
    }
    mobileDiagnostic("store.vault.load.resolved", {
      notes: loadedNotes.length,
      directories: dirs.length,
    });
    void drainDesktopOpenPaths();
  } catch (error) {
    mobileDiagnostic("store.vault.load.failed", { error });
    setState({
      status: "error",
      loadingNoteIds: new Set(),
      isRefreshing: false,
      error: String(error),
    });
  }
}

async function loadNextMobileNoteBatch(limit = MOBILE_NOTE_PAGE_SIZE): Promise<void> {
  if (
    !backend?.loadFiles ||
    backend.kind !== "mobile" ||
    state.status !== "ready"
  ) return;
  if (mobileNoteLoad) return mobileNoteLoad;
  const loadedPaths = loadedMobilePaths();
  const paths = mobileNoteEntries
    .filter((entry) => !loadedPaths.has(entry.path))
    .slice(0, limit)
    .map((entry) => entry.path);
  if (!paths.length) {
    setState({ hasMoreNotes: false, isLoadingMoreNotes: false });
    return;
  }
  setState({ isLoadingMoreNotes: true });
  mobileNoteLoad = (async () => {
    try {
      const files = await backend!.loadFiles!(paths);
      const pinned = loadPinnedPaths();
      const archived = loadArchivedPaths();
      const existingPaths = loadedMobilePaths();
      const added = files
        .filter((file) => !existingPaths.has(file.path))
        .map((file) => noteFromVaultFile(file, pinned, archived));
      for (const note of added) diskSnapshots.set(note.id, note.content);
      const notes = [...state.notes, ...added].sort(
        (a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime(),
      );
      const afterPaths = new Set(notes.map((note) => note.path));
      setState({
        notes,
        hasMoreNotes: mobileNoteEntries.some((entry) => !afterPaths.has(entry.path)),
        isLoadingMoreNotes: false,
      });
    } catch (error) {
      setState({ isLoadingMoreNotes: false });
      reportError("load more notes", error);
    } finally {
      mobileNoteLoad = null;
    }
  })();
  return mobileNoteLoad;
}

export async function loadMoreNotes(): Promise<void> {
  await loadNextMobileNoteBatch();
}

/** Loads remaining mobile note bodies so content search and local retrieval are complete. */
export async function loadAllNotes(): Promise<boolean> {
  while (state.hasMoreNotes) {
    const loadedBefore = loadedMobilePaths().size;
    await loadNextMobileNoteBatch(MOBILE_NOTE_PAGE_SIZE);
    if (loadedMobilePaths().size === loadedBefore) break;
  }
  return !state.hasMoreNotes;
}

export function initStore() {
  if (initialized) return;
  initialized = true;
  if (isTauri()) {
    if (isIOSRuntime()) {
      void (async () => {
        try {
          const saved = await restoreMobileVaultFolder();
          if (saved) {
            await loadVault(await MobileFolderVault.restore(saved.url, saved.name));
            return;
          }
        } catch {
          await clearMobileVaultFolder();
        }

        const localVault = await MobileVault.restore();
        if (localVault) {
          await loadVault(localVault);
          return;
        }
        setState({ status: "pick-vault", location: null, error: null });
      })()
        .catch((error) => setState({ status: "error", error: String(error) }));
      return;
    }
    installDesktopCloseHook();
    installDesktopOpenHook();
    installDesktopFileSync();
    const saved = localStorage.getItem(VAULT_PATH_KEY);
    if (saved) {
      rememberDesktopVault(saved);
      void loadVault(new DesktopVault(saved));
    } else {
      setState({ status: "pick-vault", isDesktop: true });
    }
  } else {
    void loadVault(new BrowserVault());
  }
}

function isIOSRuntime(): boolean {
  return isTauri() && /iPhone|iPad|iPod/i.test(navigator.userAgent);
}

async function canChangeMobileVault(): Promise<boolean> {
  return !backend || (await flushAll());
}

export async function locateMobileVault(): Promise<boolean> {
  if (!isIOSRuntime()) return false;
  mobileDiagnostic("store.locate.started");
  if (!(await canChangeMobileVault())) return false;
  try {
    const selected = await pickMobileVaultFolder();
    if (!selected) {
      mobileDiagnostic("store.locate.cancelled");
      return false;
    }
    mobileDiagnostic("store.locate.selection-received", { name: selected.name });
    const vault = await MobileFolderVault.locate(selected.url, selected.name);
    if (!vault) {
      await clearMobileVaultFolder();
      setState({
        status: backend ? state.status : "pick-vault",
        error: "Could not open that vault.",
      });
      return false;
    }
    await loadVault(vault);
    mobileDiagnostic("store.locate.completed", { status: state.status });
    return state.status === "ready";
  } catch (error) {
    setState({
      status: backend ? state.status : "pick-vault",
      error: `Could not open that vault: ${String(error)}`,
    });
    return false;
  }
}

export async function createMobileVaultAtLocation(): Promise<boolean> {
  if (!isIOSRuntime()) return false;
  if (!(await canChangeMobileVault())) return false;
  const selected = await pickMobileVaultFolder();
  if (!selected) return false;
  await loadVault(await MobileFolderVault.create(selected.url, selected.name));
  return state.status === "ready";
}

export async function createMobileVaultOnDevice(): Promise<boolean> {
  if (!isIOSRuntime()) return false;
  if (!(await canChangeMobileVault())) return false;
  await clearMobileVaultFolder();
  await loadVault(await MobileVault.open());
  return state.status === "ready";
}

export function getDesktopVaults(): DesktopVaultEntry[] {
  return loadDesktopVaults(state.location);
}

export function getDesktopVaultConflictCount(path: string): number {
  if (path === state.location) return Object.keys(state.conflicts).length;
  return suspendedDesktopConflicts.get(path)?.length ?? 0;
}

export async function switchDesktopVault(path: string): Promise<boolean> {
  if (!path || !isTauri() || isIOSRuntime()) return false;
  if (backend?.kind === "desktop" && state.location === path) return true;
  if (backend && !(await flushAll({ allowConflicts: true }))) return false;
  suspendCurrentDesktopConflicts();
  localStorage.setItem(VAULT_PATH_KEY, path);
  rememberDesktopVault(path);
  await loadVault(new DesktopVault(path));
  return state.status === "ready";
}

export async function chooseVaultFolder(): Promise<boolean> {
  const folder = await openDialog({
    directory: true,
    title: "Choose your Zerus vault folder",
  });
  if (typeof folder !== "string" || !folder) return false;
  return switchDesktopVault(folder);
}

export async function reloadVault() {
  if (!backend) return;
  if (!(await flushAll())) return;
  await loadVault(backend);
}

/** Reconciles changes made outside Zerus when the desktop app regains focus. */
export async function refreshVaultFromDisk() {
  await synchronizeDesktopFiles();
}

/** Notifies stores with files outside the note index when the vault changes. */
export function onDesktopVaultChanged(listener: () => void): () => void {
  desktopVaultChangeListeners.add(listener);
  return () => desktopVaultChangeListeners.delete(listener);
}

function relativePathKey(path: string): string {
  return normalizeFsPath(path);
}

const DESKTOP_SYNC_FALLBACK_MS = 60_000;
const DESKTOP_SYNC_DEBOUNCE_MS = 250;
const DESKTOP_WATCH_DEBOUNCE_MS = 500;

function notifyDesktopVaultChanged() {
  for (const listener of desktopVaultChangeListeners) listener();
}

function desktopWatchEventIsRelevant(event: WatchEvent): boolean {
  if (typeof event.type === "object" && "access" in event.type) return false;
  return event.paths.some((path) => {
    const normalized = path.replace(/\\/g, "/").toLowerCase();
    const metadataIndex = normalized.lastIndexOf("/.zerus/");
    if (metadataIndex < 0) return true;
    const metadataPath = normalized.slice(metadataIndex + "/.zerus/".length);
    return (
      metadataPath === "tasks.json" ||
      metadataPath === "file-locations.json"
    );
  });
}

function requestDesktopFileSync() {
  if (
    document.visibilityState !== "visible" ||
    state.status !== "ready" ||
    backend?.kind !== "desktop"
  ) {
    return;
  }
  if (desktopSyncDebounceTimer) clearTimeout(desktopSyncDebounceTimer);
  desktopSyncDebounceTimer = setTimeout(() => {
    desktopSyncDebounceTimer = null;
    notifyDesktopVaultChanged();
    if (desktopSyncInFlight) {
      desktopSyncRequested = true;
      return;
    }
    void synchronizeDesktopFiles();
  }, DESKTOP_SYNC_DEBOUNCE_MS);
}

function stopWatchingDesktopVault() {
  desktopWatchGeneration += 1;
  stopDesktopWatch?.();
  stopDesktopWatch = null;
}

async function watchDesktopVault(location: string) {
  if (backend?.kind !== "desktop" || backend.location !== location) return;
  const generation = ++desktopWatchGeneration;
  stopDesktopWatch?.();
  stopDesktopWatch = null;
  try {
    const unwatch = await watch(
      location,
      (event) => {
        if (
          generation === desktopWatchGeneration &&
          backend?.kind === "desktop" &&
          backend.location === location &&
          desktopWatchEventIsRelevant(event)
        ) {
          requestDesktopFileSync();
        }
      },
      { recursive: true, delayMs: DESKTOP_WATCH_DEBOUNCE_MS },
    );
    if (
      generation !== desktopWatchGeneration ||
      backend?.kind !== "desktop" ||
      backend.location !== location
    ) {
      unwatch();
      return;
    }
    stopDesktopWatch = unwatch;
  } catch (error) {
    console.warn(
      "Zerus: native vault watcher unavailable; using fallback sync",
      error,
    );
  }
}

function installDesktopFileSync() {
  if (desktopSyncTimer) return;
  desktopSyncTimer = setInterval(
    requestDesktopFileSync,
    DESKTOP_SYNC_FALLBACK_MS,
  );
}

interface DesktopSyncBasisEntry {
  id: string;
  path: string;
  externalPath: string | undefined;
  content: string;
  diskSnapshot: string | undefined;
}

function captureDesktopSyncBasis(): DesktopSyncBasisEntry[] {
  return state.notes.map((note) => ({
    id: note.id,
    path: note.path,
    externalPath: note.externalPath,
    content: note.content,
    diskSnapshot: diskSnapshots.get(note.id),
  }));
}

function desktopSyncBasisIsCurrent(basis: DesktopSyncBasisEntry[]): boolean {
  return (
    basis.length === state.notes.length &&
    basis.every((entry, index) => {
      const note = state.notes[index];
      return (
        note?.id === entry.id &&
        note.path === entry.path &&
        note.externalPath === entry.externalPath &&
        note.content === entry.content &&
        diskSnapshots.get(note.id) === entry.diskSnapshot
      );
    })
  );
}

export async function synchronizeDesktopFiles() {
  if (
    desktopSyncInFlight ||
    state.status !== "ready" ||
    backend?.kind !== "desktop"
  ) {
    return;
  }
  desktopSyncRequested = false;
  desktopSyncInFlight = true;
  const activeBackend = backend;
  const syncBasis = captureDesktopSyncBasis();
  try {
    const externalNotes = state.notes.filter(isExternalNote);
    const [files, dirs, externalFiles, fileLocations] = await Promise.all([
      activeBackend.loadAll(),
      activeBackend.listDirs(),
      Promise.all(
        externalNotes.map(async (note) => {
          try {
            const [content, info] = await Promise.all([
              readTextFile(note.externalPath as string),
              stat(note.externalPath as string),
            ]);
            return {
              id: note.id,
              content,
              updatedAt: (info.mtime ?? new Date()).toISOString(),
            };
          } catch {
            return { id: note.id, content: null, updatedAt: null };
          }
        }),
      ),
      loadFileLocations(activeBackend),
    ]);
    if (backend !== activeBackend || state.status !== "ready") return;
    // The filesystem scan is asynchronous. If Zerus edited, saved, renamed,
    // added, or removed a note while it was in progress, its results may describe
    // the disk from before Zerus's own write. Ignore that stale scan and let
    // the next poll compare against the new snapshot.
    if (!desktopSyncBasisIsCurrent(syncBasis)) return;

    const latestNotes = [...state.notes];
    const nextConflicts = { ...state.conflicts };
    const filesByPath = new Map(
      files.map((file) => [relativePathKey(file.path), file] as const),
    );
    const matchedFilePaths = new Set<string>();
    let notesChanged = false;
    let registryChanged = false;

    const conflictFor = (
      note: Note,
      diskContent: string | null,
      kind: NoteConflict["kind"],
    ) => {
      cancelPendingFlush(note.id);
      nextConflicts[note.id] = {
        noteId: note.id,
        currentContent: note.content,
        diskContent,
        diskPath: noteDiskPath(note),
        kind,
      };
    };

    // Preserve a note's session identity across straightforward external renames.
    const unmatchedFiles = new Set(files.map((file) => relativePathKey(file.path)));
    for (let index = 0; index < latestNotes.length; index += 1) {
      const note = latestNotes[index];
      if (isExternalNote(note) || isManagedSavedLink(note)) continue;
      const key = relativePathKey(note.path);
      if (filesByPath.has(key)) {
        unmatchedFiles.delete(key);
        continue;
      }
      if (pendingFlush.has(note.id) || inFlightFlush.has(note.id)) continue;
      const snapshot = diskSnapshots.get(note.id);
      if (snapshot === undefined || note.content !== snapshot) continue;
      const candidates = [...unmatchedFiles]
        .map((candidateKey) => filesByPath.get(candidateKey))
        .filter((file) => file?.content === snapshot);
      if (candidates.length !== 1) continue;
      const renamedFile = candidates[0] as (typeof files)[number];
      const renamedKey = relativePathKey(renamedFile.path);
      unmatchedFiles.delete(renamedKey);
      matchedFilePaths.add(renamedKey);
      latestNotes[index] = {
        ...note,
        path: renamedFile.path,
        content: renamedFile.content,
        updatedAt: renamedFile.updatedAt,
      };
      diskSnapshots.set(note.id, renamedFile.content);
      delete nextConflicts[note.id];
      notesChanged = true;
    }

    for (let index = latestNotes.length - 1; index >= 0; index -= 1) {
      const note = latestNotes[index];
      if (isExternalNote(note) || isManagedSavedLink(note)) continue;
      const key = relativePathKey(note.path);
      const file = filesByPath.get(key);
      if (file) {
        matchedFilePaths.add(key);
        const snapshot = diskSnapshots.get(note.id);
        if (file.content === snapshot) continue;
        if (pendingFlush.has(note.id) || inFlightFlush.has(note.id)) continue;
        if (nextConflicts[note.id] || note.content !== snapshot) {
          conflictFor(note, file.content, "modified");
          continue;
        }
        const historyContent = readZerusMetadata(file.content).id
          ? file.content
          : setZerusState(file.content, { id: note.id });
        if (historyContent !== file.content) {
          await activeBackend.write(note.path, historyContent);
        }
        await recordHistorySafely(
          note.id,
          snapshot ?? note.content,
          historyContent,
          "external",
        );
        latestNotes[index] = {
          ...note,
          content: historyContent,
          updatedAt: file.updatedAt,
        };
        diskSnapshots.set(note.id, historyContent);
        notesChanged = true;
        continue;
      }

      if (pendingFlush.has(note.id) || inFlightFlush.has(note.id)) continue;
      const snapshot = diskSnapshots.get(note.id);
      if (nextConflicts[note.id] || note.content !== snapshot) {
        conflictFor(note, null, "deleted");
        continue;
      }
      latestNotes.splice(index, 1);
      diskSnapshots.delete(note.id);
      delete nextConflicts[note.id];
      notesChanged = true;
    }

    for (const file of files) {
      const key = relativePathKey(file.path);
      if (matchedFilePaths.has(key)) continue;
      const note: Note = {
        id: crypto.randomUUID(),
        path: file.path,
        content: file.content,
        pinned: false,
        archived: false,
        createdAt: file.createdAt ?? file.updatedAt,
        updatedAt: file.updatedAt,
      };
      latestNotes.push(note);
      diskSnapshots.set(note.id, note.content);
      notesChanged = true;
    }

    for (const externalFile of externalFiles) {
      const index = latestNotes.findIndex(
        (note) => note.id === externalFile.id && isExternalNote(note),
      );
      if (index < 0) continue;
      const note = latestNotes[index];
      if (pendingFlush.has(note.id) || inFlightFlush.has(note.id)) continue;
      const snapshot = diskSnapshots.get(note.id);
      if (externalFile.content === null) {
        if (nextConflicts[note.id] || note.content !== snapshot) {
          conflictFor(note, null, "deleted");
        } else {
          latestNotes.splice(index, 1);
          diskSnapshots.delete(note.id);
          delete nextConflicts[note.id];
          forgetExternalPath(note.externalPath as string);
          registryChanged = true;
          notesChanged = true;
        }
        continue;
      }
      if (externalFile.content === snapshot) continue;
      if (nextConflicts[note.id] || note.content !== snapshot) {
        conflictFor(note, externalFile.content, "modified");
      } else {
        latestNotes[index] = {
          ...note,
          content: externalFile.content,
          updatedAt: externalFile.updatedAt ?? new Date().toISOString(),
        };
        diskSnapshots.set(note.id, externalFile.content);
        notesChanged = true;
      }
    }

    const extraTypes = dirs
      .filter((dir) => dir !== IMAGE_DIR && !dir.startsWith(`${IMAGE_DIR}/`))
      .map((dir) => dir.split("/").slice(0, MAX_TYPE_DEPTH));
    const typesChanged =
      JSON.stringify(extraTypes) !== JSON.stringify(state.extraTypes);
    const conflictsChanged =
      JSON.stringify(nextConflicts) !== JSON.stringify(state.conflicts);
    const locationsChanged =
      JSON.stringify(fileLocations) !== JSON.stringify(state.fileLocations);
    const uniqueNotes = [
      ...new Map(
        latestNotes.map((note) => [
          isExternalNote(note)
            ? `external:${note.externalPath}`
            : `path:${note.path}`,
          note,
        ]),
      ).values(),
    ];
    if (uniqueNotes.length !== latestNotes.length) notesChanged = true;
    if (notesChanged || typesChanged || conflictsChanged || locationsChanged) {
      setState({
        notes: uniqueNotes,
        extraTypes: typesChanged ? extraTypes : state.extraTypes,
        conflicts: nextConflicts,
        fileLocations: locationsChanged ? fileLocations : state.fileLocations,
      });
      if (notesChanged) saveNoteDisplayState();
    }
    if (registryChanged) saveExternalPaths();
  } catch (error) {
    console.error("Zerus: failed to synchronize files", error);
  } finally {
    desktopSyncInFlight = false;
    if (desktopSyncRequested) {
      desktopSyncRequested = false;
      void synchronizeDesktopFiles();
    }
  }
}

// ---- path helpers ----------------------------------------------------------

function takenPaths(exceptId?: string): Set<string> {
  const paths = new Set(
    state.notes
      .filter((note) => note.id !== exceptId && !isExternalNote(note))
      .map((note) => note.path.toLowerCase()),
  );
  if (state.isNotePaginationEnabled) {
    mobileNoteEntries.forEach((entry) => paths.add(entry.path.toLowerCase()));
  }
  return paths;
}

function uniquePath(dir: string, stem: string, exceptId?: string): string {
  const taken = takenPaths(exceptId);
  const prefix = dir ? `${dir}/` : "";
  for (let n = 0; ; n++) {
    const candidate = `${prefix}${stem}${n === 0 ? "" : ` ${n + 1}`}.md`;
    if (!taken.has(candidate.toLowerCase())) return candidate;
  }
}

async function writeUniquePathOnDisk(
  dir: string,
  stem: string,
  content: string,
  exceptId?: string,
  currentPath?: string,
): Promise<string> {
  if (!backend) throw new Error("Vault is unavailable");
  const taken = takenPaths(exceptId);
  const prefix = dir ? `${dir}/` : "";
  for (let n = 0; ; n++) {
    const candidate = `${prefix}${stem}${n === 0 ? "" : ` ${n + 1}`}.md`;
    if (taken.has(candidate.toLowerCase())) continue;
    if (candidate === currentPath) return candidate;
    try {
      await backend.writeNew(candidate, content);
      return candidate;
    } catch (error) {
      // Another process may have claimed the candidate after our last reload.
      if (await backend.exists(candidate)) continue;
      throw error;
    }
  }
}

function isSafeTypePath(typePath: string[]): boolean {
  return (
    typePath.length > 0 &&
    typePath.length <= MAX_TYPE_DEPTH &&
    typePath.every(
      (segment) =>
        segment.length > 0 &&
        segment !== "." &&
        segment !== ".." &&
        !/[\\/\0]/.test(segment),
    )
  );
}

function updateNote(id: string, patch: Partial<Note>) {
  const previous = state.notes.find((note) => note.id === id);
  const notes = state.notes.map((note) =>
    note.id === id ? { ...note, ...patch } : note,
  );
  if (previous && patch.path && patch.path !== previous.path) {
    updateMobileEntry(previous.path, patch.path, patch.updatedAt ?? previous.updatedAt);
  }
  const summary = state.isNotePaginationEnabled
    ? summarizeMobileEntries(mobileNoteEntries)
    : {
        totalNoteCount: notes.filter(
          (note) => !isExternalNote(note) && !isTrashed(note),
        ).length,
      };
  setState({
    notes,
    ...summary,
  });
}

function setNoteBusy(id: string, busy: boolean) {
  const busyNoteIds = new Set(state.busyNoteIds);
  if (busy) busyNoteIds.add(id);
  else busyNoteIds.delete(id);
  setState({ busyNoteIds });
}

function reportError(action: string, error: unknown) {
  console.error(`Zerus: failed to ${action}`, error);
  showError(`Failed to ${action}: ${error}`);
}

// ---- content editing with debounced file sync ------------------------------

function noteDiskPath(note: Note): string {
  return noteAbsolutePath(note, state.location) ?? note.path;
}

function cancelPendingFlush(id: string) {
  const timer = pendingFlush.get(id);
  if (timer) clearTimeout(timer);
  pendingFlush.delete(id);
}

function setNoteConflict(
  note: Note,
  diskContent: string | null,
  kind: NoteConflict["kind"],
) {
  cancelPendingFlush(note.id);
  setState({
    conflicts: {
      ...state.conflicts,
      [note.id]: {
        noteId: note.id,
        currentContent: note.content,
        diskContent,
        diskPath: noteDiskPath(note),
        kind,
      },
    },
  });
}

function clearNoteConflict(id: string) {
  if (!state.conflicts[id]) return;
  const conflicts = { ...state.conflicts };
  delete conflicts[id];
  setState({ conflicts });
}

async function readNoteFromDisk(note: Note): Promise<string | null> {
  try {
    if (note.externalPath) return await readTextFile(note.externalPath);
    if (!backend || !(await backend.exists(note.path))) return null;
    return await backend.readText(note.path);
  } catch {
    return null;
  }
}

async function diskStillMatchesSnapshot(note: Note): Promise<boolean> {
  const snapshot = diskSnapshots.get(note.id);
  if (snapshot === undefined) return true;
  const diskContent = await readNoteFromDisk(note);
  if (diskContent === snapshot) return true;
  setNoteConflict(note, diskContent, diskContent === null ? "deleted" : "modified");
  return false;
}

export function updateNoteContent(id: string, content: string) {
  if (
    closingAfterFlush ||
    state.busyNoteIds.has(id) ||
    state.loadingNoteIds.has(id)
  ) {
    return;
  }
  updateNote(id, { content, updatedAt: new Date().toISOString() });
  if (state.isRefreshing) {
    startupEditedNoteIds.add(id);
    return;
  }
  const conflict = state.conflicts[id];
  if (conflict) {
    setState({
      conflicts: {
        ...state.conflicts,
        [id]: { ...conflict, currentContent: content },
      },
    });
    return;
  }
  const existing = pendingFlush.get(id);
  if (existing) clearTimeout(existing);
  pendingFlush.set(
    id,
    setTimeout(() => void flushNote(id), FLUSH_DELAY_MS),
  );
}

/** Writes the freshest content to disk after any earlier write for this note. */
async function persistNote(
  id: string,
  force = false,
  recreateMissing = false,
): Promise<boolean> {
  let note = state.notes.find((candidate) => candidate.id === id);
  if (!note) return true;
  try {
    if (!force) {
      if (state.conflicts[id]) return false;
      if (!(await diskStillMatchesSnapshot(note))) return false;
    }
    if (note.externalPath) {
      await writeTextFile(note.externalPath, note.content);
      diskSnapshots.set(id, note.content);
      return true;
    }
    if (!backend) return false;
    const previousContent = diskSnapshots.get(id) ?? note.content;
    if (!readZerusMetadata(note.content).id) {
      const content = setZerusState(note.content, { id: note.id });
      note = { ...note, content };
      updateNote(id, { content });
    }
    const historySource = pendingHistorySource.get(id) ?? localHistorySource();
    if (isSavedLinkNote(note)) {
      await backend.write(note.path, note.content);
      diskSnapshots.set(id, note.content);
      pendingHistorySource.delete(id);
      await recordHistorySafely(id, previousContent, note.content, historySource);
      return true;
    }
    let path = note.path;
    const desiredStem = sanitizeFileStem(noteTitle(note));
    if (
      !recreateMissing &&
      desiredStem !== fileStem(note.path) &&
      !isTrashed(note)
    ) {
      const dir = note.path.split("/").slice(0, -1).join("/");
      const target = await writeUniquePathOnDisk(
        dir,
        desiredStem,
        note.content,
        id,
        note.path,
      );
      if (target !== note.path) {
        try {
          await backend.removeFile(note.path);
        } catch (error) {
          await backend.removeFile(target).catch(() => {});
          throw error;
        }
        path = target;
        updateNote(id, { path });
        saveNoteDisplayState();
      }
    }
    await backend.write(path, note.content);
    diskSnapshots.set(id, note.content);
    pendingHistorySource.delete(id);
    await recordHistorySafely(id, previousContent, note.content, historySource);
    return true;
  } catch (error) {
    reportError("save note", error);
    return false;
  }
}

async function flushNote(id: string): Promise<boolean> {
  pendingFlush.delete(id);
  const previous = inFlightFlush.get(id) ?? Promise.resolve(true);
  const operation = previous.then(() => persistNote(id));
  inFlightFlush.set(id, operation);
  const saved = await operation;
  if (inFlightFlush.get(id) === operation) inFlightFlush.delete(id);
  return saved;
}

async function flushUntilIdle(id: string): Promise<boolean> {
  do {
    const timer = pendingFlush.get(id);
    if (timer) clearTimeout(timer);
    if (!(await flushNote(id))) return false;
  } while (pendingFlush.has(id) || inFlightFlush.has(id));
  return true;
}

/** Immediately persists all pending debounced note edits. */
export async function flushPendingWrites(): Promise<boolean> {
  return flushAll();
}

async function flushAll(
  options: { allowConflicts?: boolean } = {},
): Promise<boolean> {
  const conflictIds = new Set(Object.keys(state.conflicts));
  const suspendedConflictCount = [...suspendedDesktopConflicts.values()].reduce(
    (total, conflicts) => total + conflicts.length,
    0,
  );
  if (
    !options.allowConflicts &&
    (conflictIds.size > 0 || suspendedConflictCount > 0)
  ) {
    showError(
      suspendedConflictCount > 0
        ? "Switch back to vaults marked Needs review and resolve their note changes before closing Zerus."
        : "Resolve note changes from disk before closing Zerus.",
    );
    return false;
  }
  let saved = true;
  for (const id of [...startupEditedNoteIds]) {
    if (conflictIds.has(id)) continue;
    if (await flushUntilIdle(id)) startupEditedNoteIds.delete(id);
    else saved = false;
  }
  do {
    const ids = new Set(
      [...pendingFlush.keys(), ...inFlightFlush.keys()].filter(
        (id) => !conflictIds.has(id),
      ),
    );
    for (const id of ids) {
      if (!(await flushUntilIdle(id))) saved = false;
    }
  } while (
    [...pendingFlush.keys(), ...inFlightFlush.keys()].some(
      (id) => !conflictIds.has(id),
    )
  );
  await typeViewsWriteInFlight;
  return saved;
}

export async function resolveNoteConflict(
  id: string,
  resolution: "disk" | "current",
): Promise<boolean> {
  const conflict = state.conflicts[id];
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!conflict || !note) return false;

  if (resolution === "disk") {
    if (conflict.diskContent === null) {
      diskSnapshots.delete(id);
      clearNoteConflict(id);
      if (note.externalPath) {
        forgetExternalPath(note.externalPath);
        saveExternalPaths();
      }
      setState({ notes: state.notes.filter((candidate) => candidate.id !== id) });
      return true;
    }
    const previousContent = note.content;
    const diskContent = note.externalPath || readZerusMetadata(conflict.diskContent).id
      ? conflict.diskContent
      : setZerusState(conflict.diskContent, { id: note.id });
    if (!note.externalPath && backend && diskContent !== conflict.diskContent) {
      await backend.write(note.path, diskContent);
    }
    diskSnapshots.set(id, diskContent);
    updateNote(id, {
      content: diskContent,
      updatedAt: new Date().toISOString(),
    });
    clearNoteConflict(id);
    await recordHistorySafely(id, previousContent, diskContent, "external");
    return true;
  }

  clearNoteConflict(id);
  const saved = await persistNote(id, true, conflict.kind === "deleted");
  if (!saved) {
    setNoteConflict(note, conflict.diskContent, conflict.kind);
    return false;
  }
  return true;
}

export function getNoteConflict(id: string): NoteConflict | null {
  return state.conflicts[id] ?? null;
}

export async function getNoteHistoryVersions(
  id: string,
): Promise<NoteHistoryVersion[]> {
  if (!backend) return [];
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note || isExternalNote(note)) return [];
  return listNoteHistory(backend, id);
}

export async function setNoteHistoryVersion(
  noteId: string,
  versionId: string,
  patch: { kept?: boolean; label?: string | null },
): Promise<void> {
  if (!backend) return;
  await updateHistoryVersion(backend, noteId, versionId, patch);
}

export async function restoreNoteHistoryVersion(
  noteId: string,
  versionId: string,
): Promise<boolean> {
  if (!backend) return false;
  const note = state.notes.find((candidate) => candidate.id === noteId);
  if (!note || isExternalNote(note)) return false;
  if (!(await flushUntilIdle(noteId))) return false;
  const version = (await listNoteHistory(backend, noteId)).find(
    (candidate) => candidate.id === versionId,
  );
  if (!version || version.incomplete) return false;
  try {
    const withImages = await materializeHistoryImages(backend, version);
    const content = preserveCurrentZerusMetadata(withImages, note.content);
    if (content === note.content) return true;
    pendingHistorySource.set(noteId, "restore");
    updateNoteContent(noteId, content);
    return flushUntilIdle(noteId);
  } catch (error) {
    reportError("restore note version", error);
    return false;
  }
}

export async function clearNoteVersionHistory(noteId: string): Promise<void> {
  if (!backend) return;
  await clearStoredNoteHistory(backend, noteId);
}

export async function updateVersionHistorySettings(
  settings: HistorySettings,
): Promise<void> {
  if (!backend) return;
  const historySettings = await saveHistorySettings(backend, settings);
  setState({ historySettings });
}

export async function clearVaultVersionHistory(): Promise<void> {
  if (!backend) return;
  await clearAllStoredHistory(backend);
}

function installDesktopCloseHook() {
  if (desktopCloseHookInstalled) return;
  desktopCloseHookInstalled = true;
  const appWindow = getCurrentWindow();
  void appWindow
    .onCloseRequested(async (event) => {
      if (closingAfterFlush) return;
      event.preventDefault();
      closingAfterFlush = true;
      if (!(await flushAll())) {
        closingAfterFlush = false;
        return;
      }
      // `close()` emits another close-request event. Re-entering that event from
      // inside this handler can leave the native close request waiting forever
      // on macOS. The request has already been approved after the flush, so
      // force the window to close without emitting the event again.
      await appWindow.destroy();
      closingAfterFlush = false;
    })
    .catch((error) => reportError("install safe close handler", error));
}

async function collectPendingDesktopOpenPaths() {
  const paths = await invoke<string[]>("take_pending_open_files");
  if (!paths.length) return;
  pendingDesktopOpenPaths.push(...paths);
  await drainDesktopOpenPaths();
}

function installDesktopOpenHook() {
  if (desktopOpenHookInstalled) return;
  desktopOpenHookInstalled = true;
  void listen("zerus-open-files", () => {
    void collectPendingDesktopOpenPaths().catch((error) =>
      reportError("open file from desktop", error),
    );
  })
    .then(() => collectPendingDesktopOpenPaths())
    .catch((error) => reportError("install desktop file-open handler", error));
}

async function drainDesktopOpenPaths(): Promise<void> {
  if (state.status !== "ready" || pendingDesktopOpenPaths.length === 0) return;
  if (desktopOpenDrain) return desktopOpenDrain;

  desktopOpenDrain = (async () => {
    while (state.status === "ready" && pendingDesktopOpenPaths.length > 0) {
      const paths = pendingDesktopOpenPaths.splice(0);
      // Markdown files are editable external notes. Every other file is kept
      // opaque and represented by a safe linked-file note.
      const notePaths = paths.filter(isMarkdownFilePath);
      const documentPaths = paths.filter((path) => !isMarkdownFilePath(path));
      const ids = [
        ...(await openDocumentPathsFromDesktop(documentPaths)),
        ...(await openExternalPaths(notePaths)),
      ];
      if (!ids.length) continue;
      const firstNote = state.notes.find((note) => note.id === ids[0]);
      const firstNoteIsExternal = firstNote
        ? isExternalNote(firstNote)
        : false;
      desktopOpenListeners.forEach((listener) =>
        listener(ids, firstNoteIsExternal, !!firstNote && !!getFileHubReference(firstNote)),
      );
    }
  })().finally(() => {
    desktopOpenDrain = null;
  });
  return desktopOpenDrain;
}

export async function openDocumentPathsFromDesktop(
  paths: string[],
): Promise<string[]> {
  const ids: string[] = [];
  for (const path of paths) {
    const note = await createUnmanagedFileHubNote(
      loadDefaultNoteType(state.location),
      path,
    );
    if (note) ids.push(note.id);
  }
  return ids;
}

export function onDesktopNotesOpened(
  listener: (
    ids: string[],
    firstNoteIsExternal: boolean,
    firstNoteIsFileHub: boolean,
  ) => void,
): () => void {
  desktopOpenListeners.add(listener);
  return () => desktopOpenListeners.delete(listener);
}

if (typeof window !== "undefined" && !isTauri()) {
  window.addEventListener("beforeunload", () => {
    void flushAll();
  });
}

// ---- external note operations ---------------------------------------------

/** Opens one or more markdown files without assigning them a vault type. */
export async function openExternalNotes(): Promise<string[]> {
  if (!isTauri()) return [];
  if (isIOSRuntime()) {
    const paths = (await pickMobileExternalNotes()).map((file) => file.path);
    return openExternalPaths(paths);
  }
  let picked: string | string[] | null;
  try {
    picked = await openDialog({
      multiple: true,
      title: "Open external markdown notes",
      filters: [{ name: "Markdown", extensions: ["md", "markdown"] }],
    });
  } catch (error) {
    reportError("open external notes", error);
    return [];
  }
  if (!picked) return [];
  const desktopPaths = typeof picked === "string" ? [picked] : picked;
  return openExternalPaths(desktopPaths);
}

async function openExternalPaths(paths: string[]): Promise<string[]> {
  const openedIds: string[] = [];
  const newNotes: Note[] = [];

  const distinctPaths = new Map<string, string>();
  for (const path of await Promise.all(paths.map(canonicalizeFsPath))) {
    distinctPaths.set(normalizeFsPath(path), path);
  }
  const vaultNotesByPath = new Map(
    await Promise.all(
      state.notes
        .filter((note) => !isExternalNote(note))
        .map(async (note) => [
          normalizeFsPath(
            await canonicalizeFsPath(
              noteAbsolutePath(note, state.location) ?? "",
            ),
          ),
          note.id,
        ] as const),
    ),
  );
  for (const [normalizedPath, path] of distinctPaths) {
    const existingExternal = state.notes.find(
      (note) =>
        !!note.externalPath &&
        normalizeFsPath(note.externalPath) === normalizedPath,
    );
    if (existingExternal) {
      registerExternalPath(path);
      openedIds.push(existingExternal.id);
      continue;
    }
    const existingVaultId = vaultNotesByPath.get(normalizedPath);
    if (existingVaultId) {
      openedIds.push(existingVaultId);
      continue;
    }
    try {
      const note = await readExternalNote(path);
      registerExternalPath(path);
      newNotes.push(note);
      openedIds.push(note.id);
    } catch (error) {
      reportError(`open ${externalFileName(path)}`, error);
    }
  }

  if (newNotes.length) {
    for (const note of newNotes) diskSnapshots.set(note.id, note.content);
    setState({ notes: [...newNotes, ...state.notes] });
  }
  if (openedIds.length) saveExternalPaths();
  return openedIds;
}

/** Stops tracking an external note without deleting the source file. */
export async function closeExternalNote(id: string): Promise<void> {
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note || !isExternalNote(note) || state.busyNoteIds.has(id)) return;
  setNoteBusy(id, true);
  try {
    if (!(await flushUntilIdle(id))) return;
    const current = state.notes.find((candidate) => candidate.id === id);
    if (!current?.externalPath) return;
    setState({ notes: state.notes.filter((candidate) => candidate.id !== id) });
    diskSnapshots.delete(id);
    clearNoteConflict(id);
    forgetExternalPath(current.externalPath);
    saveExternalPaths();
  } finally {
    setNoteBusy(id, false);
  }
}

/** Copies an external file into the selected vault type, preserving the source. */
export async function copyExternalNoteToVault(
  id: string,
  typePath: string[],
): Promise<Note | null> {
  if (!backend || !isSafeTypePath(typePath) || state.busyNoteIds.has(id)) {
    return null;
  }
  const initial = state.notes.find((candidate) => candidate.id === id);
  if (!initial?.externalPath) return null;
  setNoteBusy(id, true);
  try {
    if (!(await flushUntilIdle(id))) return null;
    const source = state.notes.find((candidate) => candidate.id === id);
    if (!source?.externalPath) return null;
    const existedKeys = existingTypeKeys();
    try {
      const copiedId = crypto.randomUUID();
      const createdAt = new Date().toISOString();
      const content = setZerusState(source.content, { id: copiedId });
      const path = await writeUniquePathOnDisk(
        typeKey(typePath),
        fileStem(source.externalPath),
        content,
      );
      const copied: Note = {
        id: copiedId,
        path,
        content,
        pinned: false,
        archived: false,
        createdAt,
        updatedAt: createdAt,
      };
      diskSnapshots.set(copied.id, content);
      if (state.isNotePaginationEnabled) {
        mobileNoteEntries.push({
          path,
          createdAt: copied.createdAt,
          updatedAt: copied.updatedAt,
        });
        sortMobileEntries();
      }
      const summary = state.isNotePaginationEnabled
        ? summarizeMobileEntries(mobileNoteEntries)
        : { totalNoteCount: state.totalNoteCount + 1 };
      setState({ notes: [copied, ...state.notes], ...summary });
      suggestIconsForNewType(typePath, existedKeys);
      return copied;
    } catch (error) {
      reportError("copy external note to vault", error);
      return null;
    }
  } finally {
    setNoteBusy(id, false);
  }
}

/** Moves an external file into the selected vault type and removes the source. */
export async function moveExternalNoteToVault(
  id: string,
  typePath: string[],
): Promise<boolean> {
  if (!backend || !isSafeTypePath(typePath) || state.busyNoteIds.has(id)) {
    return false;
  }
  const initial = state.notes.find((candidate) => candidate.id === id);
  if (!initial?.externalPath) return false;
  setNoteBusy(id, true);
  try {
    if (!(await flushUntilIdle(id))) return false;
    const note = state.notes.find((candidate) => candidate.id === id);
    if (!note?.externalPath) return false;
    const existedKeys = existingTypeKeys();
    let target: string | null = null;
    try {
      target = await writeUniquePathOnDisk(
        typeKey(typePath),
        fileStem(note.externalPath),
        note.content,
        id,
      );
      try {
        await removeFsFile(note.externalPath);
      } catch (error) {
        await backend.removeFile(target).catch(() => {});
        throw error;
      }
      updateNote(id, { path: target, externalPath: undefined });
      diskSnapshots.set(id, note.content);
      forgetExternalPath(note.externalPath);
      saveExternalPaths();
      suggestIconsForNewType(typePath, existedKeys);
      return true;
    } catch (error) {
      reportError("move external note to vault", error);
      return false;
    }
  } finally {
    setNoteBusy(id, false);
  }
}

export async function revealNoteInDesktop(id: string): Promise<void> {
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note) return;
  const path = noteAbsolutePath(note, state.location);
  if (!path || !isTauri()) return;
  try {
    await invoke("reveal_in_file_manager", { path });
  } catch (error) {
    reportError("reveal note in desktop", error);
  }
}

// ---- file hubs --------------------------------------------------------------

export interface FileHubStatus {
  resolved: ResolvedFileHub;
  exists: boolean;
  size: number | null;
  modifiedAt: string | null;
}

export type AttachFileResult =
  | { status: "attached"; noteId: string }
  | { status: "duplicate"; noteId: string }
  | { status: "needs-choice"; path: string }
  | { status: "failed" };

function resolvedHub(note: Note): ResolvedFileHub | null {
  const reference = getFileHubReference(note);
  if (!reference) return null;
  if (reference.kind === "vault" && reference.path && backend?.absolutePath) {
    const absolutePath = backend.absolutePath(reference.path);
    if (absolutePath) {
      return {
        reference,
        absolutePath,
        location: null,
        missingMapping: false,
      };
    }
  }
  return resolveFileHubReference(
    reference,
    state.location,
    state.fileLocations,
    getFileLocationMappings(),
    getFileHubMappings(),
  );
}

export function getResolvedFileHub(note: Note): ResolvedFileHub | null {
  return resolvedHub(note);
}

export async function getFileHubStatus(id: string): Promise<FileHubStatus | null> {
  const note = state.notes.find((candidate) => candidate.id === id);
  const resolved = note ? resolvedHub(note) : null;
  if (!resolved) return null;
  if (!resolved.absolutePath) {
    return { resolved, exists: false, size: null, modifiedAt: null };
  }
  try {
    const info = await stat(resolved.absolutePath);
    return {
      resolved,
      exists: info.isFile,
      size: info.size,
      modifiedAt: info.mtime?.toISOString() ?? null,
    };
  } catch {
    return { resolved, exists: false, size: null, modifiedAt: null };
  }
}

export async function chooseDocumentFile(): Promise<string | null> {
  if (!isTauri()) return null;
  if (isIOSRuntime()) {
    return (await pickMobileFiles())[0]?.path ?? null;
  }
  const picked = await openDialog({
    title: "Choose a file",
  });
  return typeof picked === "string" ? picked : null;
}

export async function chooseAttachmentFiles(): Promise<string[]> {
  if (!isTauri()) return [];
  if (isIOSRuntime()) return (await pickMobileFiles()).map((file) => file.path);
  const picked = await openDialog({
    multiple: true,
    title: "Attach files to note",
  });
  if (!picked) return [];
  return typeof picked === "string" ? [picked] : picked;
}

/** Creates a note for a document selected from the Files section. */
export async function createFileNote(
  typePath: string[],
): Promise<Note | null> {
  const picked = await chooseDocumentFile();
  if (!picked) return null;
  return createUnmanagedFileHubNote(typePath, picked);
}

/** Creates an app-managed web link outside the vault's note/type hierarchy. */
export async function createLinkNote(
  rawUrl: string,
): Promise<Note | null> {
  const url = normalizeExternalUrl(rawUrl);
  if (!url) return null;
  const existing = state.notes.find(
    (note) => getLinkHubReference(note)?.url === url,
  );
  if (existing) return existing;

  const id = crypto.randomUUID();
  const title = linkDisplayName(url) || "Link";
  const path = `${SAVED_LINKS_DIR}/${id}.md`;
  const content = setZerusState(
    setLinkHubReference(withLinkMarkdown(`# ${title}\n`, url), { id, url }),
    { id },
  );
  const createdAt = new Date().toISOString();
  const note: Note = {
    id,
    path,
    content,
    pinned: false,
    archived: false,
    createdAt,
    updatedAt: createdAt,
  };
  if (!backend) return null;
  try {
    await backend.writeNew(path, content);
    const paths = state.notes
      .filter(isSavedLinkNote)
      .map((candidate) => candidate.path);
    await saveSavedLinkPaths([...paths, path]);
    diskSnapshots.set(id, content);
    setState({ notes: [note, ...state.notes] });
    return note;
  } catch (error) {
    await backend.removeFile(path).catch(() => {});
    reportError("create link", error);
    return null;
  }
}

/** Converts an app-managed saved link into an ordinary typed Markdown note. */
export async function moveSavedLinkToVault(
  id: string,
  typePath: string[],
): Promise<boolean> {
  if (!backend || !isSafeTypePath(typePath) || state.busyNoteIds.has(id)) {
    return false;
  }
  const initial = state.notes.find((note) => note.id === id);
  if (!initial || !isSavedLinkNote(initial)) return false;
  setNoteBusy(id, true);
  try {
    if (!(await flushUntilIdle(id))) return false;
    const note = state.notes.find((candidate) => candidate.id === id);
    if (!note || !isSavedLinkNote(note)) return false;
    const existedKeys = existingTypeKeys();
    const content = removeLinkHubReference(note.content);
    const target = uniquePath(typeKey(typePath), sanitizeFileStem(noteTitle(note)), id);
    await backend.write(target, content);
    const managedSavedLink = note.path.startsWith(`${SAVED_LINKS_DIR}/`);
    const previousSavedLinkPaths = state.notes
      .filter(isSavedLinkNote)
      .map((candidate) => candidate.path);
    const nextSavedLinkPaths = previousSavedLinkPaths.filter(
      (path) => path !== note.path,
    );
    if (managedSavedLink) await saveSavedLinkPaths(nextSavedLinkPaths);
    if (target !== note.path) {
      try {
        await backend.removeFile(note.path);
      } catch (error) {
        if (managedSavedLink) {
          await saveSavedLinkPaths(previousSavedLinkPaths).catch(() => {});
        }
        await backend.removeFile(target).catch(() => {});
        throw error;
      }
    }
    updateNote(id, { path: target, content });
    diskSnapshots.set(id, content);
    saveNoteDisplayState();
    await suggestIconsForNewType(typePath, existedKeys);
    return true;
  } catch (error) {
    reportError("move link to vault", error);
    return false;
  } finally {
    setNoteBusy(id, false);
  }
}

async function findHubForAbsolutePath(
  absolutePath: string,
  exceptId?: string,
): Promise<Note | null> {
  const canonical = normalizeFsPath(await canonicalizeFsPath(absolutePath));
  for (const note of state.notes) {
    if (note.id === exceptId) continue;
    const candidate = resolvedHub(note)?.absolutePath;
    if (!candidate) continue;
    if (normalizeFsPath(await canonicalizeFsPath(candidate)) === canonical) return note;
  }
  return null;
}

/**
 * Creates the note and its unmanaged file-hub metadata in one disk write.
 * This prevents a focus-triggered vault scan from observing a plain note
 * between creation and attachment.
 */
async function createUnmanagedFileHubNote(
  typePath: string[],
  selectedPath: string,
): Promise<Note | null> {
  const canonical = await canonicalizeFsPath(selectedPath);
  const existing = await findHubForAbsolutePath(canonical);
  if (existing) return existing;

  const id = crypto.randomUUID();
  const name = fileNameFromPath(canonical);
  const vaultPath = state.location
    ? pathInsideRoot(state.location, canonical)
    : null;
  const locationMatch = mostSpecificLocation(
    canonical,
    state.fileLocations,
    getFileLocationMappings(),
  );
  const reference: FileHubReference = vaultPath
    ? { id, name, kind: "vault", path: vaultPath, managed: false }
    : locationMatch
      ? {
          id,
          name,
          kind: "location",
          locationId: locationMatch.location.id,
          path: locationMatch.path,
          managed: false,
        }
      : { id, name, kind: "local", managed: false };
  const stem = name.replace(/\.[^.]+$/, "") || "Document";
  const note = await createNote(
    typePath,
    setFileHubReference(`# ${stem}\n\n`, reference),
  );
  if (!note) return null;
  if (reference.kind === "local") setFileHubMapping(id, canonical);
  return note;
}

async function copyDocumentIntoVault(note: Note, source: string): Promise<string> {
  if (!state.location) throw new Error("The vault is unavailable");
  const dir = note.path.split("/").slice(0, -1).join("/");
  return invoke<string>("copy_file_into_vault", {
    source,
    root: state.location,
    relativeDirectory: dir,
    fileName: fileNameFromPath(source),
  });
}

export async function attachFileToNote(
  id: string,
  selectedPath: string,
  mode: "auto" | "local" | "copy" = "auto",
): Promise<AttachFileResult> {
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note || isExternalNote(note) || isTrashed(note) || !isTauri()) {
    return { status: "failed" };
  }
  const canonical = await canonicalizeFsPath(selectedPath);
  const duplicate = await findHubForAbsolutePath(canonical, id);
  if (duplicate) return { status: "duplicate", noteId: duplicate.id };

  const idValue = getFileHubReference(note)?.id ?? crypto.randomUUID();
  const name = fileNameFromPath(canonical);
  let reference: FileHubReference | null = null;
  const vaultPath = state.location ? pathInsideRoot(state.location, canonical) : null;
  const locationMatch = mostSpecificLocation(
    canonical,
    state.fileLocations,
    getFileLocationMappings(),
  );
  try {
    if (mode === "copy") {
      reference = {
        id: idValue,
        name,
        kind: "vault",
        path: await copyDocumentIntoVault(note, canonical),
        managed: true,
      };
    } else if (vaultPath && mode === "auto") {
      reference = { id: idValue, name, kind: "vault", path: vaultPath, managed: false };
    } else if (locationMatch && mode === "auto") {
      reference = {
        id: idValue,
        name,
        kind: "location",
        locationId: locationMatch.location.id,
        path: locationMatch.path,
        managed: false,
      };
    } else if (mode === "local") {
      reference = { id: idValue, name, kind: "local", managed: false };
      setFileHubMapping(idValue, canonical);
    } else {
      return { status: "needs-choice", path: canonical };
    }
    setFileHubMapping(idValue, null);
    if (reference.kind === "local") setFileHubMapping(idValue, canonical);
    updateNoteContent(id, setFileHubReference(note.content, reference));
    return { status: "attached", noteId: id };
  } catch (error) {
    reportError("attach document", error);
    return { status: "failed" };
  }
}

export function detachFileHub(id: string) {
  const note = state.notes.find((candidate) => candidate.id === id);
  const reference = note ? getFileHubReference(note) : null;
  if (!note || !reference) return;
  setFileHubMapping(reference.id, null);
  updateNoteContent(id, removeFileHubReference(note.content));
}

export async function locateFileHub(id: string): Promise<boolean> {
  const note = state.notes.find((candidate) => candidate.id === id);
  const reference = note ? getFileHubReference(note) : null;
  if (!note || !reference) return false;
  const picked = await chooseDocumentFile();
  if (!picked) return false;
  const canonical = await canonicalizeFsPath(picked);
  if (reference.kind === "location" && reference.locationId) {
    const mappedRoot = getFileLocationMappings()[reference.locationId];
    const mappedRelative = mappedRoot ? pathInsideRoot(mappedRoot, canonical) : null;
    if (mappedRelative) {
      updateNoteContent(
        id,
        setFileHubReference(note.content, {
          ...reference,
          name: fileNameFromPath(canonical),
          path: mappedRelative,
        }),
      );
      setFileHubMapping(reference.id, null);
      return true;
    }
    const suffix = `/${reference.path ?? ""}`;
    const normalized = normalizeFsPath(canonical);
    if (reference.path && normalized.endsWith(suffix)) {
      setFileLocationMapping(
        reference.locationId,
        canonical.slice(0, canonical.length - suffix.length),
      );
      setFileHubMapping(reference.id, null);
      return true;
    }
  }
  if (reference.kind === "vault" && state.location) {
    const relative = pathInsideRoot(state.location, canonical);
    if (relative) {
      updateNoteContent(
        id,
        setFileHubReference(note.content, {
          ...reference,
          name: fileNameFromPath(canonical),
          path: relative,
        }),
      );
      return true;
    }
  }
  setFileHubMapping(reference.id, canonical);
  return true;
}

export async function openFileHub(
  id: string,
  mode: "preview" | "refresh" = "preview",
): Promise<void> {
  const note = state.notes.find((candidate) => candidate.id === id);
  const path = note ? resolvedHub(note)?.absolutePath : null;
  if (!path) return;
  try {
    if (isIOSRuntime()) await openMobileFile(path, mode);
    else await openPath(path);
  } catch (error) {
    reportError("open document", error);
  }
}

export async function revealFileHub(id: string): Promise<void> {
  const note = state.notes.find((candidate) => candidate.id === id);
  const path = note ? resolvedHub(note)?.absolutePath : null;
  if (!path) return;
  try {
    await invoke("reveal_in_file_manager", { path });
  } catch (error) {
    reportError("reveal document", error);
  }
}

export async function readFileHubBytes(
  id: string,
  maximumBytes?: number,
): Promise<Uint8Array> {
  const note = state.notes.find((candidate) => candidate.id === id);
  const path = note ? resolvedHub(note)?.absolutePath : null;
  if (!path) throw new Error("The file location is not configured on this device.");
  if (maximumBytes !== undefined) {
    const info = await stat(path);
    if (info.size > maximumBytes) {
      throw new Error(
        `This HTML file is too large to preview safely (${Math.ceil(info.size / 1024 / 1024)} MB). The limit is ${Math.floor(maximumBytes / 1024 / 1024)} MB.`,
      );
    }
  }
  return readFile(path);
}

function saveFileLocations(locations: FileLocationDefinition[]) {
  setState({ fileLocations: locations });
  if (!backend) return;
  backend
    .write(FILE_LOCATIONS_PATH, serializeFileLocations(locations))
    .catch((error) => reportError("save file locations", error));
}

export async function addFileLocation(name: string): Promise<boolean> {
  if (!isTauri()) return false;
  const root = isIOSRuntime()
    ? (await pickMobileFileLocationFolder())?.path ?? null
    : await openDialog({ directory: true, title: `Choose the ${name} folder` });
  if (typeof root !== "string" || !root) return false;
  const location = { id: crypto.randomUUID(), name: name.trim() };
  if (!location.name) return false;
  saveFileLocations([...state.fileLocations, location]);
  setFileLocationMapping(location.id, await canonicalizeFsPath(root));
  return true;
}

export function renameFileLocation(id: string, name: string) {
  const trimmed = name.trim();
  if (!trimmed) return;
  saveFileLocations(
    state.fileLocations.map((location) =>
      location.id === id ? { ...location, name: trimmed } : location,
    ),
  );
}

export async function mapFileLocation(id: string): Promise<boolean> {
  const location = state.fileLocations.find((candidate) => candidate.id === id);
  if (!location || !isTauri()) return false;
  const root = isIOSRuntime()
    ? (await pickMobileFileLocationFolder())?.path ?? null
    : await openDialog({ directory: true, title: `Locate ${location.name}` });
  if (typeof root !== "string" || !root) return false;
  setFileLocationMapping(id, await canonicalizeFsPath(root));
  return true;
}

export function fileLocationUsages(id: string): Note[] {
  return state.notes.filter((note) => getFileHubReference(note)?.locationId === id);
}

export function removeFileLocation(id: string): boolean {
  if (fileLocationUsages(id).length) return false;
  saveFileLocations(state.fileLocations.filter((location) => location.id !== id));
  setFileLocationMapping(id, null);
  return true;
}

// ---- note attachments -------------------------------------------------------

export type NoteAttachmentMode = "copy" | "external";

function attachmentAbsolutePath(attachment: NoteAttachment): string | null {
  if (attachment.kind === "vault" && attachment.path) {
    return backend?.absolutePath?.(attachment.path) ?? null;
  }
  return getFileHubMappings()[attachment.id] ?? null;
}

async function copyAttachmentIntoVault(
  note: Note,
  source: string,
): Promise<string> {
  if (!state.location) throw new Error("The vault is unavailable");
  const directory = `.zerus/attachments/${note.id}`;
  await backend?.mkDir(directory);
  return invoke<string>("copy_file_into_vault", {
    source,
    root: state.location,
    relativeDirectory: directory,
    fileName: fileNameFromPath(source),
  });
}

/** Adds files to a note and returns the references to insert into its body. */
export async function addNoteAttachments(
  noteId: string,
  selectedPaths: string[],
  mode: NoteAttachmentMode,
): Promise<NoteAttachment[]> {
  const initial = state.notes.find((candidate) => candidate.id === noteId);
  if (!initial || isExternalNote(initial) || isTrashed(initial) || !isTauri()) {
    return [];
  }

  const added: NoteAttachment[] = [];
  try {
    for (const selectedPath of selectedPaths) {
      const canonical = await canonicalizeFsPath(selectedPath);
      const current = state.notes.find((candidate) => candidate.id === noteId);
      if (!current) break;
      const existing = getNoteAttachments(current).find((attachment) => {
        const path = attachmentAbsolutePath(attachment);
        const originalPath = getFileHubMappings()[attachment.id];
        return [path, originalPath].some(
          (candidate) =>
            candidate &&
            normalizeFsPath(candidate) === normalizeFsPath(canonical),
        );
      });
      if (existing) {
        added.push(existing);
        continue;
      }

      const id = crypto.randomUUID();
      // Preserve the source mapping even for vault copies so switching back to
      // an external link can restore the original without deleting anything.
      setFileHubMapping(id, canonical);
      const attachment: NoteAttachment =
        mode === "copy"
          ? {
              id,
              name: fileNameFromPath(canonical),
              kind: "vault",
              path: await copyAttachmentIntoVault(current, canonical),
              managed: true,
            }
          : {
              id,
              name: fileNameFromPath(canonical),
              kind: "external",
              managed: false,
            };
      const latest = state.notes.find((candidate) => candidate.id === noteId);
      if (!latest) break;
      updateNoteContent(
        noteId,
        setNoteAttachments(latest.content, [
          ...getNoteAttachments(latest),
          attachment,
        ]),
      );
      added.push(attachment);
    }
  } catch (error) {
    reportError("attach file", error);
  }
  return added;
}

export async function convertNoteAttachment(
  noteId: string,
  attachmentId: string,
  mode: NoteAttachmentMode,
): Promise<boolean> {
  const note = state.notes.find((candidate) => candidate.id === noteId);
  if (!note) return false;
  const attachments = getNoteAttachments(note);
  const index = attachments.findIndex((attachment) => attachment.id === attachmentId);
  if (index < 0) return false;
  const current = attachments[index];
  if (
    (mode === "copy" && current.kind === "vault") ||
    (mode === "external" && current.kind === "external")
  ) {
    return true;
  }

  try {
    let next: NoteAttachment;
    if (mode === "copy") {
      const source = attachmentAbsolutePath(current);
      if (!source) throw new Error("The external file is not available on this device.");
      next = {
        ...current,
        kind: "vault",
        path: await copyAttachmentIntoVault(note, source),
        managed: true,
      };
    } else {
      const mappedSource = getFileHubMappings()[current.id];
      const vaultSource = attachmentAbsolutePath(current);
      const source = mappedSource ?? vaultSource;
      if (!source) throw new Error("The attached file is not available on this device.");
      setFileHubMapping(current.id, source);
      next = { ...current, kind: "external", path: undefined, managed: false };
    }
    const latest = state.notes.find((candidate) => candidate.id === noteId);
    if (!latest) return false;
    const latestAttachments = getNoteAttachments(latest);
    const latestIndex = latestAttachments.findIndex(
      (attachment) => attachment.id === attachmentId,
    );
    if (latestIndex < 0) return false;
    latestAttachments[latestIndex] = next;
    updateNoteContent(noteId, setNoteAttachments(latest.content, latestAttachments));
    return true;
  } catch (error) {
    reportError("change attachment location", error);
    return false;
  }
}

export async function openNoteAttachment(
  noteId: string,
  attachmentId: string,
): Promise<void> {
  const note = state.notes.find((candidate) => candidate.id === noteId);
  const attachment = note
    ? getNoteAttachments(note).find((candidate) => candidate.id === attachmentId)
    : null;
  const path = attachment ? attachmentAbsolutePath(attachment) : null;
  if (!path) return;
  try {
    await invoke("open_file_in_default_app", { path });
  } catch (error) {
    reportError("open attachment", error);
  }
}

export async function revealNoteAttachment(
  noteId: string,
  attachmentId: string,
): Promise<void> {
  const note = state.notes.find((candidate) => candidate.id === noteId);
  const attachment = note
    ? getNoteAttachments(note).find((candidate) => candidate.id === attachmentId)
    : null;
  const path = attachment ? attachmentAbsolutePath(attachment) : null;
  if (!path) return;
  try {
    await invoke("reveal_in_file_manager", { path });
  } catch (error) {
    reportError("reveal attachment", error);
  }
}

// ---- images ------------------------------------------------------------------

const IMAGE_DIR = "assets";

const EXT_BY_MIME: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/gif": "gif",
  "image/webp": "webp",
  "image/svg+xml": "svg",
  "image/bmp": "bmp",
};

const MIME_BY_EXT: Record<string, string> = {
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
  svg: "image/svg+xml",
  bmp: "image/bmp",
};

const imageUrlCache = new ImageUrlCache();
const serializeImageMutation = createImageMutationQueue();

function isTrashedImage(value: unknown): value is TrashedImage {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<TrashedImage>;
  return (
    typeof candidate.id === "string" &&
    typeof candidate.name === "string" &&
    typeof candidate.originalPath === "string" &&
    typeof candidate.trashPath === "string" &&
    typeof candidate.deletedAt === "string"
  );
}

async function loadTrashedImages(
  source: VaultBackend,
): Promise<TrashedImage[]> {
  try {
    const parsed = JSON.parse(
      await source.readText(TRASHED_IMAGES_INDEX_PATH),
    ) as unknown;
    return Array.isArray(parsed) ? parsed.filter(isTrashedImage) : [];
  } catch {
    return [];
  }
}

async function persistTrashedImages(
  images = state.trashedImages,
  targetBackend = backend,
) {
  if (!targetBackend) return;
  await targetBackend.write(
    TRASHED_IMAGES_INDEX_PATH,
    JSON.stringify(images, null, 2),
  );
}

function imageFileName(path: string): string {
  const encoded = path.split("/").pop() || "image";
  try {
    return decodeURIComponent(encoded);
  } catch {
    return encoded;
  }
}

function imageMimeType(path: string): string {
  const ext = path.split(".").pop()?.toLowerCase() ?? "";
  return MIME_BY_EXT[ext] ?? "image/png";
}

function clearImageUrlCache() {
  imageUrlCache.clear();
}

function invalidateImageUrl(path: string) {
  imageUrlCache.invalidate(path);
}

/**
 * Resolves a vault-relative image path to a displayable URL (a blob URL backed
 * by the vault file). Remote URLs pass through untouched.
 */
export function getImageUrl(path: string): Promise<string | null> {
  if (isRemoteUrl(path)) return Promise.resolve(path);
  return imageUrlCache.get(path, async () => {
      if (!backend) return null;
      try {
        const bytes = await backend.readBinary(decodeURI(path));
        const ext = path.split(".").pop()?.toLowerCase() ?? "";
        const type = MIME_BY_EXT[ext] ?? "application/octet-stream";
        return URL.createObjectURL(new Blob([bytes as BlobPart], { type }));
      } catch {
        return null;
      }
    });
}

/** Opens an embedded image in the platform's default app. */
export async function openImageInDefaultApp(path: string): Promise<boolean> {
  try {
    if (isRemoteUrl(path)) {
      await openExternalUrl(path);
      return true;
    }
    const absolute = backend?.absolutePath?.(decodeURI(path));
    if (absolute) {
      await openPath(absolute);
      return true;
    }
    const url = await getImageUrl(path);
    if (!url) return false;
    window.open(url, "_blank", "noopener,noreferrer");
    return true;
  } catch (error) {
    reportError("open image", error);
    return false;
  }
}

/** Copies the actual image payload rather than its Markdown source. */
export async function copyImageToClipboard(path: string): Promise<boolean> {
  try {
    const url = await getImageUrl(path);
    if (!url || !navigator.clipboard?.write || typeof ClipboardItem === "undefined") {
      return false;
    }
    const response = await fetch(url);
    const source = await response.blob();
    const type = source.type.startsWith("image/")
      ? source.type
      : imageMimeType(path);
    const blob = source.type === type ? source : new Blob([source], { type });
    await navigator.clipboard.write([new ClipboardItem({ [type]: blob })]);
    return true;
  } catch (error) {
    reportError("copy image", error);
    return false;
  }
}

export type TrashImageResult =
  | { kind: "external" | "shared" }
  | { kind: "trashed"; image: TrashedImage };

async function imageIsShared(
  targetBackend: VaultBackend,
  noteId: string,
  path: string,
): Promise<boolean> {
  if (loadedNotesShareImage(state.notes, noteId, path)) return true;
  if (
    targetBackend.kind !== "mobile" ||
    !targetBackend.listNoteEntries ||
    !targetBackend.loadFiles
  ) {
    return false;
  }
  const entries = await targetBackend.listNoteEntries();
  const loadedPaths = new Set(
    state.notes
      .filter((note) => !isExternalNote(note))
      .map((note) => note.path),
  );
  return unloadedNotesReferenceImage(
    targetBackend,
    entries,
    loadedPaths,
    path,
    MOBILE_NOTE_PAGE_SIZE,
  );
}

/** Moves an unshared vault image into recoverable Zerus Trash. */
export function trashImageForNote(
  noteId: string,
  path: string,
  markdown?: string,
): Promise<TrashImageResult> {
  return serializeImageMutation(() =>
    performTrashImageForNote(noteId, path, markdown),
  );
}

async function performTrashImageForNote(
  noteId: string,
  path: string,
  markdown?: string,
): Promise<TrashImageResult> {
  const targetBackend = backend;
  if (!targetBackend || isRemoteUrl(path)) return { kind: "external" };
  if (await imageIsShared(targetBackend, noteId, path)) {
    return { kind: "shared" };
  }
  if (backend !== targetBackend) throw new Error("Vault changed while removing image.");
  const originalPath = decodeURI(path);
  if (!(await targetBackend.exists(originalPath))) return { kind: "external" };

  const name = imageFileName(path);
  const dot = name.lastIndexOf(".");
  const stem = dot > 0 ? name.slice(0, dot) : name;
  const extension = dot > 0 ? name.slice(dot) : "";
  let trashPath = `${TRASH_DIR}/assets/${name}`;
  for (
    let suffix = 2;
    await targetBackend.exists(trashPath);
    suffix += 1
  ) {
    trashPath = `${TRASH_DIR}/assets/${stem}-${suffix}${extension}`;
  }
  if (backend !== targetBackend) throw new Error("Vault changed while removing image.");
  const image: TrashedImage = {
    id: crypto.randomUUID(),
    name,
    originalPath: path,
    trashPath,
    deletedAt: new Date().toISOString(),
    noteId,
    markdown,
  };
  const previousImages = state.trashedImages;
  const trashedImages = [image, ...previousImages];
  await moveImageWithRollback(
    targetBackend,
    originalPath,
    trashPath,
    () => persistTrashedImages(trashedImages, targetBackend),
  );
  if (backend !== targetBackend) {
    await moveImageWithRollback(
      targetBackend,
      trashPath,
      originalPath,
      () => persistTrashedImages(previousImages, targetBackend),
    );
    throw new Error("Vault changed while removing image.");
  }
  invalidateImageUrl(path);
  setState({ trashedImages });
  return { kind: "trashed", image };
}

/** Restores a recoverable image to its original vault path. */
export function restoreTrashedImage(
  id: string,
  options: { reattach?: boolean } = {},
): Promise<boolean> {
  return serializeImageMutation(() => performRestoreTrashedImage(id, options));
}

async function performRestoreTrashedImage(
  id: string,
  options: { reattach?: boolean },
): Promise<boolean> {
  const targetBackend = backend;
  if (!targetBackend) return false;
  const image = state.trashedImages.find((candidate) => candidate.id === id);
  const originalPath = image ? decodeURI(image.originalPath) : "";
  if (!image || (await targetBackend.exists(originalPath))) {
    return false;
  }
  try {
    const previousImages = state.trashedImages;
    const trashedImages = state.trashedImages.filter(
      (candidate) => candidate.id !== id,
    );
    await moveImageWithRollback(
      targetBackend,
      image.trashPath,
      originalPath,
      () => persistTrashedImages(trashedImages, targetBackend),
    );
    if (backend !== targetBackend) {
      await moveImageWithRollback(
        targetBackend,
        originalPath,
        image.trashPath,
        () => persistTrashedImages(previousImages, targetBackend),
      );
      return false;
    }
    invalidateImageUrl(image.originalPath);
    invalidateImageUrl(image.trashPath);
    setState({ trashedImages });
    if (options.reattach !== false && image.noteId && image.markdown) {
      const note = state.notes.find((candidate) => candidate.id === image.noteId);
      if (note && imageReferenceCount(note.content, image.originalPath) === 0) {
        const body = noteBody(note.content);
        const separator = body.length === 0 || body.endsWith("\n\n")
          ? ""
          : body.endsWith("\n")
            ? "\n"
            : "\n\n";
        updateNoteContent(
          note.id,
          withBody(note.content, `${body}${separator}${image.markdown}`),
        );
      }
    }
    return true;
  } catch (error) {
    reportError("restore image", error);
    return false;
  }
}

export function deleteTrashedImageForever(id: string): Promise<boolean> {
  return serializeImageMutation(() => performDeleteTrashedImageForever(id));
}

async function performDeleteTrashedImageForever(
  id: string,
): Promise<boolean> {
  const targetBackend = backend;
  if (!targetBackend) return false;
  const image = state.trashedImages.find((candidate) => candidate.id === id);
  if (!image) return false;
  try {
    if (await targetBackend.exists(image.trashPath)) {
      await targetBackend.removeFile(image.trashPath);
    }
    const trashedImages = state.trashedImages.filter(
      (candidate) => candidate.id !== id,
    );
    await persistTrashedImages(trashedImages, targetBackend);
    if (backend !== targetBackend) return false;
    invalidateImageUrl(image.trashPath);
    setState({ trashedImages });
    return true;
  } catch (error) {
    reportError("delete image", error);
    return false;
  }
}

/** Permanently removes a newly saved image that never made it into a note. */
export function discardUnsavedImage(path: string): Promise<void> {
  return serializeImageMutation(() => performDiscardUnsavedImage(path));
}

async function performDiscardUnsavedImage(path: string): Promise<void> {
  try {
    const targetBackend = backend;
    if (!targetBackend || isRemoteUrl(path)) return;
    if (await imageIsShared(targetBackend, "", path)) return;
    if (backend !== targetBackend) return;
    const decodedPath = decodeURI(path);
    if (await targetBackend.exists(decodedPath)) {
      await targetBackend.removeFile(decodedPath);
    }
    invalidateImageUrl(path);
  } catch (error) {
    reportError("discard unsaved image", error);
  }
}

/** Reads a vault-relative image for a provider request. */
export async function readVaultImage(path: string): Promise<Uint8Array | null> {
  if (!backend || isRemoteUrl(path)) return null;
  try {
    return await backend.readBinary(decodeURI(path));
  } catch {
    return null;
  }
}

/**
 * Saves pasted/dropped image bytes into the vault's assets folder and returns
 * the vault-relative path to reference from markdown, or null on failure.
 */
export async function savePastedImage(
  bytes: Uint8Array,
  mime: string,
): Promise<string | null> {
  if (!backend) return null;
  const ext = EXT_BY_MIME[mime] ?? "png";
  const stamp = new Date()
    .toISOString()
    .replace(/[-:]/g, "")
    .replace("T", "-")
    .slice(0, 15);
  let path = "";
  for (let n = 0; ; n++) {
    path = `${IMAGE_DIR}/pasted-${stamp}${n === 0 ? "" : `-${n}`}.${ext}`;
    if (!(await backend.exists(path))) break;
  }
  try {
    await backend.writeBinary(path, bytes);
  } catch (error) {
    reportError("save image", error);
    return null;
  }
  return path;
}

// ---- note properties & per-type definitions ---------------------------------

function saveSchemas(schemas: PropertySchemas) {
  setState({ schemas });
  if (!backend) return;
  backend
    .write(SCHEMAS_PATH, JSON.stringify(schemas, null, 2))
    .catch((error) => reportError("save property definitions", error));
}

function notesOfType(ownerKey: string): Note[] {
  return notesOfTypeKey(state.notes, ownerKey);
}

function schemaOwnerKey(typeKeyOrPath: string): string {
  return typeKeyOrPath
    .split("/")
    .map((segment) => segment.trim())
    .filter(Boolean)
    .join("/");
}

export function addTypeProperty(typeKeyOrPath: string, def: PropertyDef) {
  if (isReservedZerusProperty(def.name)) return;
  const ownerKey = schemaOwnerKey(typeKeyOrPath);
  const defs = state.schemas[ownerKey] ?? [];
  if (defs.some((d) => d.name.toLowerCase() === def.name.toLowerCase())) return;
  saveSchemas({ ...state.schemas, [ownerKey]: [...defs, def] });
}

/** Edits a property definition; a rename migrates the key in every note of the type. */
export function updateTypeProperty(
  typeKeyOrPath: string,
  oldName: string,
  def: PropertyDef,
) {
  if (isReservedZerusProperty(def.name)) return;
  const ownerKey = schemaOwnerKey(typeKeyOrPath);
  const defs = state.schemas[ownerKey] ?? [];
  const idx = defs.findIndex(
    (d) => d.name.toLowerCase() === oldName.toLowerCase(),
  );
  if (idx < 0) return;
  const collides = defs.some(
    (d, i) => i !== idx && d.name.toLowerCase() === def.name.toLowerCase(),
  );
  if (collides) return;
  const affectedNotes = notesOfType(ownerKey).filter(
    (note) =>
      propertyDefinitionOwner(
        noteTypePath(note),
        state.schemas,
        oldName,
      ) === ownerKey,
  );
  const next = defs.slice();
  next[idx] = def;
  saveSchemas({ ...state.schemas, [ownerKey]: next });
  if (def.name !== oldName || (def.type === "list" && !def.listMultiple)) {
    for (const note of affectedNotes) {
      let migrated = note.content;
      if (def.type === "list" && !def.listMultiple) {
        const values = getNoteProperties(migrated);
        const existingKey = Object.keys(values).find(
          (key) => key.toLowerCase() === oldName.toLowerCase(),
        );
        if (existingKey) {
          migrated = setContentProperty(
            migrated,
            existingKey,
            listPropertyValue(listSelections(values[existingKey]), false),
          );
        }
      }
      if (def.name !== oldName) {
        migrated = renameContentProperty(migrated, oldName, def.name);
      }
      if (migrated !== note.content) updateNoteContent(note.id, migrated);
    }
  }
}

/** Deletes a property from the type and strips its value from the type's notes. */
export function removeTypeProperty(typeKeyOrPath: string, name: string) {
  const ownerKey = schemaOwnerKey(typeKeyOrPath);
  const defs = state.schemas[ownerKey] ?? [];
  const next = defs.filter((d) => d.name.toLowerCase() !== name.toLowerCase());
  if (next.length === defs.length) return;
  const affectedNotes = notesOfType(ownerKey).filter(
    (note) =>
      propertyDefinitionOwner(noteTypePath(note), state.schemas, name) ===
      ownerKey,
  );
  const schemas = { ...state.schemas };
  if (next.length) schemas[ownerKey] = next;
  else delete schemas[ownerKey];
  saveSchemas(schemas);
  for (const note of affectedNotes) {
    if (propertyDefinitionOwner(noteTypePath(note), schemas, name) !== null) {
      continue;
    }
    const stripped = setContentProperty(note.content, name, null);
    if (stripped !== note.content) updateNoteContent(note.id, stripped);
  }
}

/** Sets (or with `null`, clears) one property value in a note's frontmatter. */
export function setNoteProperty(
  id: string,
  name: string,
  value: PropertyValue | null,
) {
  if (isReservedZerusProperty(name)) return;
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note) return;
  const next = setContentProperty(note.content, name, value);
  if (next !== note.content) updateNoteContent(id, next);
}

/** Replaces the note body from the editor, preserving frontmatter properties. */
export function updateNoteBody(id: string, body: string) {
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note) return;
  const next = withBody(note.content, body);
  if (next !== note.content) updateNoteContent(id, next);
}

// ---- per-type saved views ---------------------------------------------------

function saveTypeViews(typeViews: TypeViewConfigs) {
  setState({ typeViews });
  const targetBackend = backend;
  if (!targetBackend) return;
  typeViewsWriteInFlight = typeViewsWriteInFlight
    .catch(() => undefined)
    .then(async () => {
      if (backend !== targetBackend) return;
      await targetBackend.write(
        TYPE_VIEWS_PATH,
        JSON.stringify(state.typeViews, null, 2),
      );
    })
    .catch((error) => reportError("save type views", error));
}

/** Auto-saves one folder-backed type's active view and configuration. */
export function updateTypeView(
  typeKeyOrPath: string,
  patch: Partial<TypeViewConfig>,
) {
  const ownerKey = schemaOwnerKey(typeKeyOrPath);
  if (!ownerKey) return;
  const current = state.typeViews[ownerKey];
  const next = normalizeTypeViewConfig({ ...current, ...patch });
  saveTypeViews({ ...state.typeViews, [ownerKey]: next });
}

// ---- type icons ---------------------------------------------------------------

function saveTypeIcons(typeIcons: TypeIcons) {
  setState({ typeIcons });
  if (!backend) return;
  backend
    .write(TYPE_ICONS_PATH, JSON.stringify(typeIcons, null, 2))
    .catch((error) => reportError("save type icons", error));
}

/** Sets (or with `null`, resets to the default folder) a type's icon. */
export function setTypeIcon(typePath: string[], icon: string | null) {
  const key = typeKey(typePath);
  if (!key) return;
  const typeIcons = { ...state.typeIcons };
  if (icon) typeIcons[key] = icon;
  else delete typeIcons[key];
  saveTypeIcons(typeIcons);
}

/**
 * Guesses icons for type levels that didn't exist before (e.g. creating
 * "work/recipes" suggests for both "work" and "work/recipes" if both are new).
 * Never touches types that already existed or already have an icon.
 */
async function suggestIconsForNewType(
  typePath: string[],
  existedKeys: Set<string>,
) {
  const suggestions: Array<[string, string]> = [];
  for (let depth = 1; depth <= typePath.length; depth++) {
    const key = typeKey(typePath.slice(0, depth));
    if (existedKeys.has(key) || state.typeIcons[key]) continue;
    const suggested = await suggestIconForType(typePath[depth - 1]);
    if (suggested) suggestions.push([key, suggested]);
  }
  if (!suggestions.length) return;
  const typeIcons = { ...state.typeIcons };
  for (const [key, icon] of suggestions) {
    if (!typeIcons[key]) typeIcons[key] = icon;
  }
  saveTypeIcons(typeIcons);
}

function existingTypeKeys(): Set<string> {
  return new Set(
    getAllTypePaths(state.notes, state.extraTypes).map((path) => typeKey(path)),
  );
}

// ---- type operations ---------------------------------------------------------

/**
 * Creates a type (a folder) without putting any note in it — empty types are
 * fine and show up in the sidebar with a count of 0.
 */
export async function createType(typePath: string[]): Promise<boolean> {
  if (!backend || !typePath.length) return false;
  const key = typeKey(typePath);
  const existedKeys = existingTypeKeys();
  try {
    await backend.mkDir(key);
  } catch (error) {
    reportError("create type", error);
    return false;
  }
  if (!state.extraTypes.some((path) => typeKey(path) === key)) {
    setState({ extraTypes: [...state.extraTypes, typePath] });
  }
  await suggestIconsForNewType(typePath, existedKeys);
  return true;
}

/**
 * Deletes a type (and its sub-types): every note in it is moved to Trash
 * first — recoverable via restore — then the now-empty folder is removed.
 */
export async function deleteType(typePath: string[]): Promise<boolean> {
  if (!backend || !typePath.length) return false;
  const key = typeKey(typePath);
  await flushAll();
  for (const note of notesOfType(key)) {
    await trashNote(note.id);
  }
  try {
    await backend.removeDir(key);
  } catch (error) {
    reportError("delete type", error);
    return false;
  }
  const schemas = { ...state.schemas };
  let schemasChanged = false;
  for (const schemaKey of Object.keys(schemas)) {
    if (schemaKey === key || schemaKey.startsWith(`${key}/`)) {
      delete schemas[schemaKey];
      schemasChanged = true;
    }
  }
  if (schemasChanged) saveSchemas(schemas);
  const typeIcons = { ...state.typeIcons };
  let iconsChanged = false;
  for (const iconKey of Object.keys(typeIcons)) {
    if (iconKey === key || iconKey.startsWith(`${key}/`)) {
      delete typeIcons[iconKey];
      iconsChanged = true;
    }
  }
  if (iconsChanged) saveTypeIcons(typeIcons);
  const typeViews = { ...state.typeViews };
  let viewsChanged = false;
  for (const viewKey of Object.keys(typeViews)) {
    if (viewKey === key || viewKey.startsWith(`${key}/`)) {
      delete typeViews[viewKey];
      viewsChanged = true;
    }
  }
  if (viewsChanged) saveTypeViews(typeViews);
  setState({
    extraTypes: state.extraTypes.filter((path) => {
      const otherKey = typeKey(path);
      return otherKey !== key && !otherKey.startsWith(`${key}/`);
    }),
  });
  return true;
}

/**
 * Renames (and/or moves) a type: renames its folder on disk, then updates
 * every note path, sub-type, property schema, and relation reference under
 * the old key so nothing is left pointing at the stale path.
 */
export async function renameType(
  oldPath: string[],
  newPath: string[],
): Promise<boolean> {
  if (!backend || !oldPath.length || !newPath.length) return false;
  const oldKey = typeKey(oldPath);
  const newKey = typeKey(newPath);
  if (oldKey === newKey) return true;
  const collides = getAllTypePaths(state.notes, state.extraTypes).some(
    (path) => typeKey(path) === newKey,
  );
  if (collides) {
    reportError("rename type", `a type named "${newKey}" already exists`);
    return false;
  }
  await flushAll();
  try {
    await backend.renameDir(oldKey, newKey);
  } catch (error) {
    reportError("rename type", error);
    return false;
  }

  const oldPrefix = `${oldKey}/`;
  const newPrefix = `${newKey}/`;
  const remapKey = (key: string): string =>
    key === oldKey ? newKey : newPrefix + key.slice(oldPrefix.length);

  const notes = state.notes.map((note) =>
    note.path.startsWith(oldPrefix)
      ? { ...note, path: newPrefix + note.path.slice(oldPrefix.length) }
      : note,
  );

  const extraTypes = state.extraTypes.map((path) => {
    const key = typeKey(path);
    if (key !== oldKey && !key.startsWith(oldPrefix)) return path;
    return remapKey(key).split("/");
  });

  const schemas: PropertySchemas = {};
  let schemasChanged = false;
  for (const [key, defs] of Object.entries(state.schemas)) {
    const migrated = defs.map((def) => {
      if (
        !def.relationTypeKey ||
        (def.relationTypeKey !== oldKey &&
          !def.relationTypeKey.startsWith(oldPrefix))
      ) {
        return def;
      }
      schemasChanged = true;
      return { ...def, relationTypeKey: remapKey(def.relationTypeKey) };
    });
    if (key === oldKey || key.startsWith(oldPrefix)) {
      schemas[remapKey(key)] = migrated;
      schemasChanged = true;
    } else {
      schemas[key] = migrated;
    }
  }

  const typeIcons: TypeIcons = {};
  let iconsChanged = false;
  for (const [key, icon] of Object.entries(state.typeIcons)) {
    if (key === oldKey || key.startsWith(oldPrefix)) {
      typeIcons[remapKey(key)] = icon;
      iconsChanged = true;
    } else {
      typeIcons[key] = icon;
    }
  }

  const typeViews: TypeViewConfigs = {};
  let viewsChanged = false;
  for (const [key, config] of Object.entries(state.typeViews)) {
    if (key === oldKey || key.startsWith(oldPrefix)) {
      typeViews[remapKey(key)] = config;
      viewsChanged = true;
    } else {
      typeViews[key] = config;
    }
  }

  setState({ notes, extraTypes });
  saveNoteDisplayState();
  if (schemasChanged) saveSchemas(schemas);
  if (iconsChanged) saveTypeIcons(typeIcons);
  if (viewsChanged) saveTypeViews(typeViews);
  return true;
}

// ---- note operations -------------------------------------------------------

export async function createNote(
  typePath: string[] = DEFAULT_TYPE,
  content = "",
): Promise<Note | null> {
  if (!backend) return null;
  const dir = typeKey(typePath.length ? typePath : DEFAULT_TYPE);
  const stem = sanitizeFileStem(
    content ? noteTitle({ content, path: "" } as Note) : "Untitled",
  );
  const path = uniquePath(dir, stem);
  const id = crypto.randomUUID();
  const persistedContent = setZerusState(content, { id });
  const createdAt = new Date().toISOString();
  const note: Note = {
    id,
    path,
    content: persistedContent,
    pinned: false,
    archived: false,
    createdAt,
    updatedAt: createdAt,
  };
  try {
    await backend.write(path, persistedContent);
    diskSnapshots.set(note.id, persistedContent);
    if (state.isNotePaginationEnabled) {
      mobileNoteEntries.push({
        path,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
      });
      sortMobileEntries();
    }
    const summary = state.isNotePaginationEnabled
      ? summarizeMobileEntries(mobileNoteEntries)
      : { totalNoteCount: state.totalNoteCount + 1 };
    setState({ notes: [note, ...state.notes], ...summary });
  } catch (error) {
    reportError("create note", error);
    return null;
  }
  return note;
}

async function uniqueManagedDocumentPath(
  dir: string,
  name: string,
  currentPath: string,
): Promise<string> {
  if (!backend) throw new Error("The vault is unavailable");
  const dot = name.lastIndexOf(".");
  const stem = dot > 0 ? name.slice(0, dot) : name;
  const extension = dot > 0 ? name.slice(dot) : "";
  const prefix = dir ? `${dir}/` : "";
  for (let index = 0; ; index++) {
    const candidate = `${prefix}${stem}${index === 0 ? "" : ` ${index + 1}`}${extension}`;
    if (candidate === currentPath || !(await backend.exists(candidate))) return candidate;
  }
}

async function moveNoteWithManagedDocument(note: Note, target: string) {
  if (!backend) throw new Error("The vault is unavailable");
  const reference = getFileHubReference(note);
  if (
    !reference?.managed ||
    reference.kind !== "vault" ||
    !reference.path ||
    !(await backend.exists(reference.path))
  ) {
    await backend.move(note.path, target);
    updateNote(note.id, { path: target });
    return;
  }
  const targetDir = target.split("/").slice(0, -1).join("/");
  const documentTarget = await uniqueManagedDocumentPath(
    targetDir,
    fileNameFromPath(reference.path),
    reference.path,
  );
  if (documentTarget === reference.path) {
    await backend.move(note.path, target);
    updateNote(note.id, { path: target });
    return;
  }
  await backend.move(note.path, target);
  try {
    await backend.move(reference.path, documentTarget);
    const content = setFileHubReference(note.content, {
      ...reference,
      path: documentTarget,
    });
    await backend.write(target, content);
    diskSnapshots.set(note.id, content);
    updateNote(note.id, { path: target, content });
  } catch (error) {
    await backend.move(target, note.path).catch(() => {});
    if (await backend.exists(documentTarget)) {
      await backend.move(documentTarget, reference.path).catch(() => {});
    }
    throw error;
  }
}

export async function setNoteType(id: string, typePath: string[]) {
  if (!backend) return;
  await flushAll();
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note || isExternalNote(note) || isTrashed(note) || !typePath.length)
    return;
  if (typeKey(noteTypePath(note)) === typeKey(typePath)) return;
  // the move may create the type — capture what existed before to only
  // suggest icons for genuinely new type levels
  const existedKeys = existingTypeKeys();
  const target = uniquePath(typeKey(typePath), fileStem(note.path), id);
  try {
    await moveNoteWithManagedDocument(note, target);
    saveNoteDisplayState();
    await suggestIconsForNewType(typePath, existedKeys);
  } catch (error) {
    reportError("move note", error);
  }
}

export function toggleNotePinned(id: string) {
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note || isExternalNote(note)) return;
  const pinned = !note.pinned;
  updateNoteContent(id, setZerusState(note.content, { pinned }));
  updateNote(id, { pinned });
  savePinnedPaths();
}

export function toggleNoteArchived(id: string) {
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note || isExternalNote(note) || isTrashed(note)) return;
  const archived = !note.archived;
  const pinned = archived ? false : note.pinned;
  updateNoteContent(
    id,
    setZerusState(note.content, { archived, pinned }),
  );
  updateNote(id, { archived, pinned });
  saveNoteDisplayState();
}

export async function trashNote(id: string) {
  if (!backend) return;
  await flushAll();
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note || isExternalNote(note) || isTrashed(note)) return;
  const dir = [TRASH_DIR, ...noteTypePath(note)].join("/");
  const target = uniquePath(dir, fileStem(note.path), id);
  try {
    await moveNoteWithManagedDocument(note, target);
    updateNote(id, { pinned: false, archived: false });
    saveNoteDisplayState();
  } catch (error) {
    reportError("trash note", error);
  }
}

export async function restoreNote(id: string) {
  if (!backend) return;
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note || !isTrashed(note)) return;
  const logical = logicalPath(note);
  const dir = logical.split("/").slice(0, -1).join("/");
  const target = uniquePath(dir, fileStem(logical), id);
  try {
    await moveNoteWithManagedDocument(note, target);
  } catch (error) {
    reportError("restore note", error);
  }
}

export async function deleteNoteForever(id: string) {
  if (!backend) return;
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note || isExternalNote(note)) return;
  try {
    const reference = getFileHubReference(note);
    if (reference?.managed && reference.kind === "vault" && reference.path) {
      await backend.removeFile(reference.path);
    }
    await backend.removeFile(note.path);
    await clearStoredNoteHistory(backend, id).catch((error) =>
      reportError("delete note history", error),
    );
    diskSnapshots.delete(id);
    clearNoteConflict(id);
    removeMobileEntry(note.path);
    const summary = state.isNotePaginationEnabled
      ? summarizeMobileEntries(mobileNoteEntries)
      : {
          totalNoteCount: state.notes.filter(
            (candidate) =>
              candidate.id !== id &&
              !isExternalNote(candidate) &&
              !isTrashed(candidate),
          ).length,
        };
    setState({
      notes: state.notes.filter((candidate) => candidate.id !== id),
      ...summary,
    });
  } catch (error) {
    reportError("delete note", error);
  }
}

export function emptyTrash(): Promise<void> {
  return serializeImageMutation(performEmptyTrash);
}

async function performEmptyTrash() {
  const targetBackend = backend;
  if (!targetBackend) return;
  const trashed = state.notes.filter((note) => isTrashed(note));
  const trashedImages = [...state.trashedImages];
  for (const note of trashed) {
    try {
      const reference = getFileHubReference(note);
      if (reference?.managed && reference.kind === "vault" && reference.path) {
        await targetBackend.removeFile(reference.path);
      }
      await targetBackend.removeFile(note.path);
      await clearStoredNoteHistory(targetBackend, note.id).catch((error) =>
        reportError("delete note history", error),
      );
    } catch (error) {
      reportError("empty trash", error);
      return;
    }
  }
  for (const image of trashedImages) {
    try {
      if (await targetBackend.exists(image.trashPath)) {
        await targetBackend.removeFile(image.trashPath);
      }
    } catch (error) {
      reportError("empty image trash", error);
      return;
    }
  }
  await persistTrashedImages([], targetBackend);
  if (backend !== targetBackend) return;
  for (const image of trashedImages) {
    invalidateImageUrl(image.trashPath);
    invalidateImageUrl(image.originalPath);
  }
  setState({
    notes: state.notes.filter((note) => !isTrashed(note)),
    trashedImages: [],
  });
  for (const note of trashed) {
    diskSnapshots.delete(note.id);
    clearNoteConflict(note.id);
  }
}
