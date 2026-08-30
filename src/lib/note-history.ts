import { isRemoteUrl } from "@/lib/note-utils";
import { getNoteProperties, setContentProperty } from "@/lib/frontmatter";
import {
  ZERUS_METADATA_KEYS,
  isReservedZerusProperty,
  readZerusMetadata,
  stripZerusMetadata,
} from "@/lib/zerus-metadata";
import type { VaultBackend } from "@/lib/vault/backend";

export const HISTORY_CHECKPOINT_INTERVAL = 3;
export const DEFAULT_HISTORY_CHECKPOINT_LIMIT = 10;

const HISTORY_ROOT = ".zerus/history";
const HISTORY_NOTES_ROOT = `${HISTORY_ROOT}/notes`;
const HISTORY_BLOBS_ROOT = `${HISTORY_ROOT}/blobs`;
const HISTORY_SETTINGS_PATH = ".zerus/history-settings.json";
const MARKDOWN_IMAGE = /!\[([^\]]*)\]\(([^()\s]+)\)/g;

export interface HistorySettings {
  enabled: boolean;
  /** Null means unlimited. */
  checkpointLimit: number | null;
}

export type HistorySource = "desktop" | "mobile" | "browser" | "external" | "restore";

export interface HistoryDelta {
  start: number;
  removed: string;
  inserted: string;
}

export interface HistoryImage {
  path: string;
  hash: string | null;
  extension: string;
}

export interface StoredHistoryEntry {
  schema: 1;
  id: string;
  noteId: string;
  timestamp: string;
  source: HistorySource;
  originId: string;
  parentId: string | null;
  depth: number;
  kind: "checkpoint" | "delta";
  baseHash: string | null;
  resultHash: string;
  content?: string;
  delta?: HistoryDelta;
  images: HistoryImage[];
  kept: boolean;
  label: string | null;
}

export interface NoteHistoryVersion {
  id: string;
  timestamp: string;
  source: HistorySource;
  originId: string;
  parentId: string | null;
  alternateBranch: boolean;
  checkpoint: boolean;
  kept: boolean;
  label: string | null;
  content: string;
  images: HistoryImage[];
  addedLines: number;
  removedLines: number;
  incomplete: boolean;
}

export const DEFAULT_HISTORY_SETTINGS: HistorySettings = {
  enabled: true,
  checkpointLimit: DEFAULT_HISTORY_CHECKPOINT_LIMIT,
};

function safeSettings(value: unknown): HistorySettings {
  if (!value || typeof value !== "object") return DEFAULT_HISTORY_SETTINGS;
  const record = value as Record<string, unknown>;
  const rawLimit = record.checkpointLimit;
  const checkpointLimit = rawLimit === null
    ? null
    : typeof rawLimit === "number" && Number.isInteger(rawLimit)
      ? Math.max(1, Math.min(100, rawLimit))
      : DEFAULT_HISTORY_CHECKPOINT_LIMIT;
  return {
    enabled: record.enabled !== false,
    checkpointLimit,
  };
}

export async function loadHistorySettings(
  backend: VaultBackend,
): Promise<HistorySettings> {
  try {
    return safeSettings(JSON.parse(await backend.readText(HISTORY_SETTINGS_PATH)));
  } catch {
    return DEFAULT_HISTORY_SETTINGS;
  }
}

export async function saveHistorySettings(
  backend: VaultBackend,
  settings: HistorySettings,
): Promise<HistorySettings> {
  const next = safeSettings(settings);
  await backend.write(HISTORY_SETTINGS_PATH, JSON.stringify(next, null, 2));
  if (next.enabled && next.checkpointLimit !== null) {
    await pruneAllHistory(backend, next.checkpointLimit);
  }
  return next;
}

export function historyRelevantContent(content: string): string {
  return stripZerusMetadata(content);
}

export function preserveCurrentZerusMetadata(
  historical: string,
  current: string,
): string {
  const metadata = readZerusMetadata(current);
  let next = stripZerusMetadata(historical);
  for (const [key, value] of Object.entries(getNoteProperties(current))) {
    if (isReservedZerusProperty(key)) next = setContentProperty(next, key, value);
  }
  // These fields may be absent from older notes, so normalize their current
  // semantic state rather than reviving historical values.
  next = setContentProperty(next, ZERUS_METADATA_KEYS.id, metadata.id);
  next = setContentProperty(next, ZERUS_METADATA_KEYS.pinned, metadata.pinned ? true : null);
  next = setContentProperty(next, ZERUS_METADATA_KEYS.archived, metadata.archived ? true : null);
  return next;
}

export function createHistoryDelta(before: string, after: string): HistoryDelta {
  let start = 0;
  const maxPrefix = Math.min(before.length, after.length);
  while (start < maxPrefix && before[start] === after[start]) start += 1;

  let beforeEnd = before.length;
  let afterEnd = after.length;
  while (
    beforeEnd > start &&
    afterEnd > start &&
    before[beforeEnd - 1] === after[afterEnd - 1]
  ) {
    beforeEnd -= 1;
    afterEnd -= 1;
  }
  return {
    start,
    removed: before.slice(start, beforeEnd),
    inserted: after.slice(start, afterEnd),
  };
}

export function applyHistoryDelta(content: string, delta: HistoryDelta): string {
  if (content.slice(delta.start, delta.start + delta.removed.length) !== delta.removed) {
    throw new Error("History delta does not match its parent content");
  }
  return `${content.slice(0, delta.start)}${delta.inserted}${content.slice(delta.start + delta.removed.length)}`;
}

async function sha256Bytes(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes as BufferSource);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function sha256Text(content: string): Promise<string> {
  return sha256Bytes(new TextEncoder().encode(content));
}

function historyEntryPath(noteId: string, entryId: string): string {
  return `${HISTORY_NOTES_ROOT}/${noteId}/${entryId}.json`;
}

function blobPath(hash: string, _extension: string): string {
  return `${HISTORY_BLOBS_ROOT}/${hash}`;
}

function imageExtension(path: string): string {
  const clean = decodeURI(path).split(/[?#]/, 1)[0];
  const match = clean.match(/\.([a-z0-9]+)$/i);
  return match?.[1]?.toLowerCase() ?? "bin";
}

function vaultImagePaths(content: string): string[] {
  const paths = new Set<string>();
  for (const match of content.matchAll(MARKDOWN_IMAGE)) {
    const path = match[2];
    if (
      isRemoteUrl(path) ||
      path.startsWith("/") ||
      /^[a-z]:[\\/]/i.test(path) ||
      decodeURI(path).split(/[\\/]/).some((part) => part === "..")
    ) {
      continue;
    }
    paths.add(path);
  }
  return [...paths];
}

async function snapshotImages(
  backend: VaultBackend,
  content: string,
): Promise<HistoryImage[]> {
  return Promise.all(vaultImagePaths(content).map(async (path) => {
    const extension = imageExtension(path);
    try {
      const bytes = await backend.readBinary(decodeURI(path));
      const hash = await sha256Bytes(bytes);
      const target = blobPath(hash, extension);
      if (!(await backend.exists(target))) await backend.writeBinary(target, bytes);
      return { path, hash, extension };
    } catch {
      return { path, hash: null, extension };
    }
  }));
}

async function readStoredEntries(
  backend: VaultBackend,
  noteId: string,
): Promise<Array<{ path: string; entry: StoredHistoryEntry }>> {
  const prefix = `${HISTORY_NOTES_ROOT}/${noteId}`;
  const paths = (await backend.listFiles(prefix)).filter((path) => path.endsWith(".json"));
  const entries = await Promise.all(paths.map(async (path) => {
    try {
      const entry = JSON.parse(await backend.readText(path)) as StoredHistoryEntry;
      if (entry.schema !== 1 || entry.noteId !== noteId || !entry.id) return null;
      return { path, entry };
    } catch {
      return null;
    }
  }));
  return entries.filter((value): value is { path: string; entry: StoredHistoryEntry } => value !== null);
}

async function reconstructEntries(
  backend: VaultBackend,
  noteId: string,
): Promise<{ stored: Array<{ path: string; entry: StoredHistoryEntry }>; contents: Map<string, string> }> {
  const stored = await readStoredEntries(backend, noteId);
  const byId = new Map(stored.map(({ entry }) => [entry.id, entry]));
  const contents = new Map<string, string>();
  const resolving = new Set<string>();
  const resolve = async (entry: StoredHistoryEntry): Promise<string> => {
    const cached = contents.get(entry.id);
    if (cached !== undefined) return cached;
    if (resolving.has(entry.id)) throw new Error("Circular history parent chain");
    resolving.add(entry.id);
    let content: string;
    if (entry.kind === "checkpoint") {
      content = entry.content ?? "";
    } else {
      const parent = entry.parentId ? byId.get(entry.parentId) : null;
      if (!parent || !entry.delta) throw new Error("Incomplete history parent chain");
      const parentContent = await resolve(parent);
      if (entry.baseHash && await sha256Text(parentContent) !== entry.baseHash) {
        throw new Error("History parent hash mismatch");
      }
      content = applyHistoryDelta(parentContent, entry.delta);
    }
    if (await sha256Text(content) !== entry.resultHash) {
      throw new Error("History content hash mismatch");
    }
    resolving.delete(entry.id);
    contents.set(entry.id, content);
    return content;
  };
  for (const { entry } of stored) {
    try { await resolve(entry); } catch { /* surfaced as incomplete in the UI */ }
  }
  return { stored, contents };
}

function lineChangeCount(before: string, after: string): { addedLines: number; removedLines: number } {
  const beforeLines = before.split("\n");
  const afterLines = after.split("\n");
  const beforeCounts = new Map<string, number>();
  for (const line of beforeLines) beforeCounts.set(line, (beforeCounts.get(line) ?? 0) + 1);
  let addedLines = 0;
  for (const line of afterLines) {
    const count = beforeCounts.get(line) ?? 0;
    if (count > 0) beforeCounts.set(line, count - 1);
    else addedLines += 1;
  }
  const removedLines = [...beforeCounts.values()].reduce((sum, count) => sum + count, 0);
  return { addedLines, removedLines };
}

export async function listNoteHistory(
  backend: VaultBackend,
  noteId: string,
): Promise<NoteHistoryVersion[]> {
  const { stored, contents } = await reconstructEntries(backend, noteId);
  const childIds = new Set(stored.map(({ entry }) => entry.parentId).filter(Boolean));
  const tips = stored
    .map(({ entry }) => entry)
    .filter((entry) => !childIds.has(entry.id))
    .sort((a, b) => b.timestamp.localeCompare(a.timestamp));
  const primaryTip = tips[0]?.id ?? null;
  const primaryAncestors = new Set<string>();
  const byId = new Map(stored.map(({ entry }) => [entry.id, entry]));
  for (let cursor = primaryTip ? byId.get(primaryTip) : undefined; cursor; cursor = cursor.parentId ? byId.get(cursor.parentId) : undefined) {
    primaryAncestors.add(cursor.id);
  }
  return stored
    .map(({ entry }) => {
      const content = contents.get(entry.id);
      const parentContent = entry.parentId ? contents.get(entry.parentId) ?? "" : "";
      const counts = content === undefined
        ? { addedLines: 0, removedLines: 0 }
        : lineChangeCount(parentContent, content);
      return {
        id: entry.id,
        timestamp: entry.timestamp,
        source: entry.source,
        originId: entry.originId,
        parentId: entry.parentId,
        alternateBranch: primaryTip !== null && !primaryAncestors.has(entry.id),
        checkpoint: entry.kind === "checkpoint",
        kept: entry.kept,
        label: entry.label,
        content: content ?? "",
        images: entry.images,
        ...counts,
        incomplete: content === undefined || entry.images.some((image) => image.hash === null),
      } satisfies NoteHistoryVersion;
    })
    .sort((a, b) => b.timestamp.localeCompare(a.timestamp));
}

export async function recordNoteHistory(
  backend: VaultBackend,
  options: {
    noteId: string;
    before: string;
    after: string;
    source: HistorySource;
    originId: string;
    timestamp?: string;
    settings: HistorySettings;
  },
): Promise<void> {
  if (!options.settings.enabled) return;
  if (historyRelevantContent(options.before) === historyRelevantContent(options.after)) return;
  const timestamp = options.timestamp ?? new Date().toISOString();
  const { stored, contents } = await reconstructEntries(backend, options.noteId);
  const beforeHash = await sha256Text(options.before);
  const afterHash = await sha256Text(options.after);
  const matchingParents = stored
    .map(({ entry }) => entry)
    .filter((entry) => entry.resultHash === beforeHash && contents.has(entry.id))
    .sort((a, b) => b.timestamp.localeCompare(a.timestamp));

  let parent = matchingParents[0] ?? null;
  if (!parent) {
    const baselineId = crypto.randomUUID();
    const baseline: StoredHistoryEntry = {
      schema: 1,
      id: baselineId,
      noteId: options.noteId,
      timestamp,
      source: options.source === "external" ? "external" : options.source,
      originId: options.originId,
      parentId: null,
      depth: 0,
      kind: "checkpoint",
      baseHash: null,
      resultHash: beforeHash,
      content: options.before,
      images: await snapshotImages(backend, options.before),
      kept: false,
      label: "History started",
    };
    await backend.write(historyEntryPath(options.noteId, baselineId), JSON.stringify(baseline, null, 2));
    parent = baseline;
  }

  const depth = parent.depth + 1;
  const checkpoint = depth % HISTORY_CHECKPOINT_INTERVAL === 0;
  const id = crypto.randomUUID();
  const entry: StoredHistoryEntry = {
    schema: 1,
    id,
    noteId: options.noteId,
    timestamp: new Date(Math.max(Date.parse(timestamp), Date.parse(parent.timestamp) + 1)).toISOString(),
    source: options.source,
    originId: options.originId,
    parentId: parent.id,
    depth,
    kind: checkpoint ? "checkpoint" : "delta",
    baseHash: checkpoint ? null : beforeHash,
    resultHash: afterHash,
    ...(checkpoint
      ? { content: options.after }
      : { delta: createHistoryDelta(options.before, options.after) }),
    images: await snapshotImages(backend, options.after),
    kept: false,
    label: null,
  };
  await backend.write(historyEntryPath(options.noteId, id), JSON.stringify(entry, null, 2));
  if (options.settings.checkpointLimit !== null) {
    await pruneNoteHistory(backend, options.noteId, options.settings.checkpointLimit);
  }
}

export async function updateHistoryVersion(
  backend: VaultBackend,
  noteId: string,
  versionId: string,
  patch: { kept?: boolean; label?: string | null },
): Promise<void> {
  const stored = await readStoredEntries(backend, noteId);
  const target = stored.find(({ entry }) => entry.id === versionId);
  if (!target) throw new Error("Version not found");
  const entry = {
    ...target.entry,
    ...(patch.kept === undefined ? {} : { kept: patch.kept }),
    ...(patch.label === undefined ? {} : { label: patch.label?.trim() || null }),
  };
  await backend.write(target.path, JSON.stringify(entry, null, 2));
}

async function promoteKeptEntry(
  backend: VaultBackend,
  storedPath: string,
  entry: StoredHistoryEntry,
  content: string,
): Promise<void> {
  const promoted: StoredHistoryEntry = {
    ...entry,
    parentId: null,
    depth: 0,
    kind: "checkpoint",
    baseHash: null,
    content,
    delta: undefined,
  };
  await backend.write(storedPath, JSON.stringify(promoted, null, 2));
}

export async function pruneNoteHistory(
  backend: VaultBackend,
  noteId: string,
  checkpointLimit: number,
): Promise<void> {
  const { stored, contents } = await reconstructEntries(backend, noteId);
  const checkpoints = stored
    .filter(({ entry }) => entry.kind === "checkpoint" && !entry.kept)
    .sort((a, b) => b.entry.timestamp.localeCompare(a.entry.timestamp));
  if (checkpoints.length <= checkpointLimit) return;
  const retainedCheckpointIds = new Set(checkpoints.slice(0, checkpointLimit).map(({ entry }) => entry.id));
  const byId = new Map(stored.map((item) => [item.entry.id, item]));
  const keepIds = new Set<string>();
  for (const item of stored) {
    let nearestCheckpoint: StoredHistoryEntry | null = null;
    for (let cursor: typeof item | undefined = item; cursor; cursor = cursor.entry.parentId ? byId.get(cursor.entry.parentId) : undefined) {
      if (cursor.entry.kind === "checkpoint") {
        nearestCheckpoint = cursor.entry;
        break;
      }
    }
    if (nearestCheckpoint && retainedCheckpointIds.has(nearestCheckpoint.id)) {
      keepIds.add(item.entry.id);
    }
    if (item.entry.kept) {
      for (let cursor: typeof item | undefined = item; cursor; cursor = cursor.entry.parentId ? byId.get(cursor.entry.parentId) : undefined) {
        keepIds.add(cursor.entry.id);
        if (cursor.entry.kind === "checkpoint") break;
      }
    }
  }
  for (const item of stored) {
    if (keepIds.has(item.entry.id)) continue;
    if (item.entry.kept && contents.has(item.entry.id)) {
      await promoteKeptEntry(backend, item.path, item.entry, contents.get(item.entry.id)!);
      continue;
    }
    await backend.removeFile(item.path);
  }
  await garbageCollectHistoryBlobs(backend);
}

async function noteIdsWithHistory(backend: VaultBackend): Promise<string[]> {
  const paths = await backend.listFiles(HISTORY_NOTES_ROOT);
  return [...new Set(paths.map((path) => path.slice(`${HISTORY_NOTES_ROOT}/`.length).split("/")[0]).filter(Boolean))];
}

export async function pruneAllHistory(backend: VaultBackend, checkpointLimit: number): Promise<void> {
  for (const noteId of await noteIdsWithHistory(backend)) {
    await pruneNoteHistory(backend, noteId, checkpointLimit);
  }
}

export async function clearNoteHistory(backend: VaultBackend, noteId: string): Promise<void> {
  await backend.removeDir(`${HISTORY_NOTES_ROOT}/${noteId}`);
  await garbageCollectHistoryBlobs(backend);
}

export async function clearAllHistory(backend: VaultBackend): Promise<void> {
  await backend.removeDir(HISTORY_ROOT);
}

async function garbageCollectHistoryBlobs(backend: VaultBackend): Promise<void> {
  const used = new Set<string>();
  for (const noteId of await noteIdsWithHistory(backend)) {
    for (const { entry } of await readStoredEntries(backend, noteId)) {
      for (const image of entry.images) {
        if (image.hash) used.add(blobPath(image.hash, image.extension));
      }
    }
  }
  for (const path of await backend.listFiles(HISTORY_BLOBS_ROOT)) {
    if (!used.has(path)) await backend.removeFile(path);
  }
}

function replaceImagePath(content: string, from: string, to: string): string {
  return content.replace(MARKDOWN_IMAGE, (full, alt: string, path: string) =>
    path === from ? `![${alt}](${to})` : full,
  );
}

export async function materializeHistoryImages(
  backend: VaultBackend,
  version: NoteHistoryVersion,
): Promise<string> {
  let content = version.content;
  for (const image of version.images) {
    if (!image.hash) throw new Error(`Historical image is unavailable: ${image.path}`);
    let currentMatches = false;
    try {
      const current = await backend.readBinary(decodeURI(image.path));
      currentMatches = await sha256Bytes(current) === image.hash;
    } catch {
      currentMatches = false;
    }
    if (currentMatches) continue;
    const bytes = await backend.readBinary(blobPath(image.hash, image.extension));
    const stamp = version.timestamp
      .split("-").join("")
      .split(":").join("")
      .split(".").join("")
      .split("T").join("")
      .split("Z").join("")
      .slice(0, 14);
    const base = `assets/restored-${stamp}-${image.hash.slice(0, 8)}`;
    let target = `${base}.${image.extension}`;
    for (let index = 2; await backend.exists(target); index += 1) {
      target = `${base}-${index}.${image.extension}`;
    }
    await backend.writeBinary(target, bytes);
    content = replaceImagePath(content, image.path, target);
  }
  return content;
}
