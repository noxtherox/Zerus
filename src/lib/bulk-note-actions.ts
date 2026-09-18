import { useSyncExternalStore } from "react";
import {
  flushNoteWrites,
  getNotes,
  noteBulkBlockReason,
  setNoteArchived,
  setNotePinned,
  setNoteProperty,
} from "@/store/notes-store";
import { getNoteProperties, type PropertyValue } from "@/lib/frontmatter";
import { isArchived, noteTitle, type Note } from "@/lib/note-utils";
import { normalizeListOptions } from "@/lib/properties";

export type BulkPropertyOperation = "set" | "clear" | "add" | "remove";

export interface BulkPropertyChange {
  name: string;
  operation: BulkPropertyOperation;
  value?: PropertyValue;
}

export interface BulkNoteMutation {
  archived?: boolean;
  pinned?: boolean;
  properties?: BulkPropertyChange[];
}

interface ArchivedDelta {
  kind: "archived";
  before: boolean;
  after: boolean;
}

interface PinnedDelta {
  kind: "pinned";
  before: boolean;
  after: boolean;
}

interface PropertyDelta {
  kind: "property";
  name: string;
  operation: BulkPropertyOperation;
  beforeExists: boolean;
  before?: PropertyValue;
  afterExists: boolean;
  after?: PropertyValue;
  values?: string[];
}

export type BulkFieldDelta = ArchivedDelta | PinnedDelta | PropertyDelta;

export interface BulkHistoryEntry {
  noteId: string;
  title: string;
  fields: BulkFieldDelta[];
}

export interface BulkSkippedNote {
  noteId: string;
  title: string;
  reason: string;
}

export interface BulkActionRecord {
  id: string;
  createdAt: string;
  label: string;
  summary: string[];
  status: "applied" | "undone" | "partially-undone" | "partially-redone";
  entries: BulkHistoryEntry[];
  skipped: BulkSkippedNote[];
  failed: BulkSkippedNote[];
}

export interface BulkActionPreview {
  eligibleIds: string[];
  skipped: BulkSkippedNote[];
}

export interface BulkActionProgress {
  completed: number;
  total: number;
  currentTitle: string;
}

export interface BulkActionResult {
  record: BulkActionRecord | null;
  successfulIds: string[];
  skipped: BulkSkippedNote[];
  failed: BulkSkippedNote[];
  cancelled: boolean;
}

const HISTORY_LIMIT = 10;
const HISTORY_MAX_AGE_MS = 90 * 24 * 60 * 60 * 1_000;
const EMPTY_HISTORY: BulkActionRecord[] = [];
const historyCache = new Map<string, BulkActionRecord[]>();
const listeners = new Set<() => void>();

function historyKey(location: string): string {
  return `zerus.bulkHistory.v1.${encodeURIComponent(location)}`;
}

function pruneHistory(records: BulkActionRecord[]): BulkActionRecord[] {
  const cutoff = Date.now() - HISTORY_MAX_AGE_MS;
  return records
    .filter((record) => Date.parse(record.createdAt) >= cutoff)
    .slice(0, HISTORY_LIMIT);
}

function readHistory(location: string): BulkActionRecord[] {
  const cached = historyCache.get(location);
  if (cached) return cached;
  let records: BulkActionRecord[] = [];
  try {
    const parsed = JSON.parse(localStorage.getItem(historyKey(location)) ?? "[]") as unknown;
    if (Array.isArray(parsed)) records = pruneHistory(parsed as BulkActionRecord[]);
  } catch {
    records = [];
  }
  historyCache.set(location, records);
  return records;
}

function writeHistory(location: string, records: BulkActionRecord[]) {
  const next = pruneHistory(records);
  historyCache.set(location, next);
  try {
    localStorage.setItem(historyKey(location), JSON.stringify(next));
  } catch {
    // The action still succeeds when browser persistence is unavailable.
  }
  listeners.forEach((listener) => listener());
}

export function useBulkActionHistory(location: string | null): BulkActionRecord[] {
  return useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    () => (location ? readHistory(location) : EMPTY_HISTORY),
    () => EMPTY_HISTORY,
  );
}

function propertyEntry(note: Note, name: string): { exists: boolean; value?: PropertyValue } {
  const properties = getNoteProperties(note.content);
  const key = Object.keys(properties).find(
    (candidate) => candidate.toLowerCase() === name.toLowerCase(),
  );
  return key ? { exists: true, value: properties[key] } : { exists: false };
}

function equalValue(left: PropertyValue | undefined, right: PropertyValue | undefined): boolean {
  if (Array.isArray(left) || Array.isArray(right)) {
    return Array.isArray(left) && Array.isArray(right) &&
      left.length === right.length && left.every((value, index) => value === right[index]);
  }
  return left === right;
}

function stringValues(value: PropertyValue | undefined): string[] {
  if (Array.isArray(value)) return normalizeListOptions(value);
  if (value === undefined || value === "") return [];
  return [String(value)];
}

function nextPropertyValue(
  current: PropertyValue | undefined,
  change: BulkPropertyChange,
): { value: PropertyValue; values?: string[] } {
  if (change.operation === "clear") return { value: "" };
  if (change.operation === "set") return { value: change.value ?? "" };
  const requested = stringValues(change.value);
  const existing = stringValues(current);
  if (change.operation === "add") {
    const existingKeys = new Set(existing.map((value) => value.toLowerCase()));
    const added = requested.filter((value) => !existingKeys.has(value.toLowerCase()));
    return { value: normalizeListOptions([...existing, ...added]), values: added };
  }
  const removedKeys = new Set(requested.map((value) => value.toLowerCase()));
  const removed = existing.filter((value) => removedKeys.has(value.toLowerCase()));
  return {
    value: existing.filter((value) => !removedKeys.has(value.toLowerCase())),
    values: removed,
  };
}

function buildDeltas(note: Note, mutation: BulkNoteMutation): BulkFieldDelta[] {
  const fields: BulkFieldDelta[] = [];
  if (mutation.archived !== undefined && isArchived(note) !== mutation.archived) {
    fields.push({ kind: "archived", before: isArchived(note), after: mutation.archived });
  }
  if (mutation.pinned !== undefined && note.pinned !== mutation.pinned) {
    fields.push({ kind: "pinned", before: note.pinned, after: mutation.pinned });
  }
  for (const change of mutation.properties ?? []) {
    const before = propertyEntry(note, change.name);
    const next = nextPropertyValue(before.value, change);
    if (before.exists && equalValue(before.value, next.value)) continue;
    fields.push({
      kind: "property",
      name: change.name,
      operation: change.operation,
      beforeExists: before.exists,
      before: before.value,
      afterExists: true,
      after: next.value,
      values: next.values,
    });
  }
  return fields;
}

function noChangeReason(mutation: BulkNoteMutation): string {
  if (mutation.archived !== undefined) return mutation.archived ? "Already archived" : "Already active";
  if (mutation.pinned !== undefined) return mutation.pinned ? "Already pinned" : "Already unpinned";
  return "No property values would change";
}

export function previewBulkAction(
  noteIds: Iterable<string>,
  mutation: BulkNoteMutation,
): BulkActionPreview {
  const notes = new Map(getNotes().map((note) => [note.id, note]));
  const eligibleIds: string[] = [];
  const skipped: BulkSkippedNote[] = [];
  for (const noteId of noteIds) {
    const note = notes.get(noteId);
    const reason = noteBulkBlockReason(noteId);
    if (!note || reason) {
      skipped.push({ noteId, title: note ? noteTitle(note) : "Missing note", reason: reason ?? "Missing note" });
      continue;
    }
    if (!buildDeltas(note, mutation).length) {
      skipped.push({ noteId, title: noteTitle(note), reason: noChangeReason(mutation) });
      continue;
    }
    eligibleIds.push(noteId);
  }
  return { eligibleIds, skipped };
}

function applyFields(noteId: string, fields: BulkFieldDelta[]) {
  for (const field of fields) {
    if (field.kind === "archived") setNoteArchived(noteId, field.after);
    else if (field.kind === "pinned") setNotePinned(noteId, field.after);
    else setNoteProperty(noteId, field.name, field.afterExists ? field.after ?? "" : null);
  }
}

function actionLabel(mutation: BulkNoteMutation): string {
  if (mutation.archived !== undefined) return mutation.archived ? "Archive notes" : "Unarchive notes";
  if (mutation.pinned !== undefined) return mutation.pinned ? "Pin notes" : "Unpin notes";
  return "Update properties";
}

export function mutationSummary(mutation: BulkNoteMutation): string[] {
  if (mutation.archived !== undefined) return [mutation.archived ? "Archive" : "Unarchive"];
  if (mutation.pinned !== undefined) return [mutation.pinned ? "Pin" : "Unpin"];
  return (mutation.properties ?? []).map((change) => {
    const value = Array.isArray(change.value) ? change.value.join(", ") : String(change.value ?? "");
    if (change.operation === "clear") return `Clear ${change.name}`;
    return `${change.operation[0].toUpperCase()}${change.operation.slice(1)} ${change.name}${value ? `: ${value}` : ""}`;
  });
}

export async function executeBulkAction(options: {
  location: string;
  noteIds: string[];
  mutation: BulkNoteMutation;
  signal?: AbortSignal;
  onProgress?: (progress: BulkActionProgress) => void;
}): Promise<BulkActionResult> {
  const { location, noteIds, mutation, signal, onProgress } = options;
  const successfulIds: string[] = [];
  const entries: BulkHistoryEntry[] = [];
  const skipped: BulkSkippedNote[] = [];
  const failed: BulkSkippedNote[] = [];
  let completed = 0;

  for (const noteId of noteIds) {
    if (signal?.aborted) break;
    const note = getNotes().find((candidate) => candidate.id === noteId);
    const reason = noteBulkBlockReason(noteId);
    if (!note || reason) {
      skipped.push({ noteId, title: note ? noteTitle(note) : "Missing note", reason: reason ?? "Missing note" });
      completed += 1;
      onProgress?.({ completed, total: noteIds.length, currentTitle: note ? noteTitle(note) : "Missing note" });
      continue;
    }
    const fields = buildDeltas(note, mutation);
    if (!fields.length) {
      skipped.push({ noteId, title: noteTitle(note), reason: noChangeReason(mutation) });
      completed += 1;
      onProgress?.({ completed, total: noteIds.length, currentTitle: noteTitle(note) });
      continue;
    }
    applyFields(noteId, fields);
    const saved = await flushNoteWrites(noteId);
    if (saved) {
      entries.push({ noteId, title: noteTitle(note), fields });
      successfulIds.push(noteId);
    } else {
      failed.push({ noteId, title: noteTitle(note), reason: noteBulkBlockReason(noteId) ?? "Could not save note" });
    }
    completed += 1;
    onProgress?.({ completed, total: noteIds.length, currentTitle: noteTitle(note) });
  }

  const record: BulkActionRecord | null = entries.length
    ? {
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString(),
        label: actionLabel(mutation),
        summary: mutationSummary(mutation),
        status: "applied",
        entries,
        skipped,
        failed,
      }
    : null;
  if (record) writeHistory(location, [record, ...readHistory(location)]);
  return { record, successfulIds, skipped, failed, cancelled: Boolean(signal?.aborted) };
}

function currentField(note: Note, field: BulkFieldDelta): { exists: boolean; value?: PropertyValue | boolean } {
  if (field.kind === "archived") return { exists: true, value: isArchived(note) };
  if (field.kind === "pinned") return { exists: true, value: note.pinned };
  return propertyEntry(note, field.name);
}

function applyHistoryField(
  noteId: string,
  field: BulkFieldDelta,
  direction: "undo" | "redo",
): boolean {
  const note = getNotes().find((candidate) => candidate.id === noteId);
  if (!note) return false;
  if (field.kind === "archived") {
    const expected = direction === "undo" ? field.after : field.before;
    const target = direction === "undo" ? field.before : field.after;
    if (isArchived(note) === target) return true;
    if (isArchived(note) !== expected) return false;
    setNoteArchived(noteId, target);
    return true;
  }
  if (field.kind === "pinned") {
    const expected = direction === "undo" ? field.after : field.before;
    const target = direction === "undo" ? field.before : field.after;
    if (note.pinned === target) return true;
    if (note.pinned !== expected) return false;
    setNotePinned(noteId, target);
    return true;
  }

  const current = currentField(note, field);
  if ((field.operation === "add" || field.operation === "remove") && field.values?.length) {
    const values = stringValues(current.value as PropertyValue | undefined);
    const keys = new Set(field.values.map((value) => value.toLowerCase()));
    const shouldAdd = (field.operation === "add") === (direction === "redo");
    const next = shouldAdd
      ? normalizeListOptions([...values, ...field.values.filter((value) => !values.some((existing) => existing.toLowerCase() === value.toLowerCase()))])
      : values.filter((value) => !keys.has(value.toLowerCase()));
    setNoteProperty(noteId, field.name, next);
    return true;
  }

  const expectedExists = direction === "undo" ? field.afterExists : field.beforeExists;
  const expected = direction === "undo" ? field.after : field.before;
  const targetExists = direction === "undo" ? field.beforeExists : field.afterExists;
  const target = direction === "undo" ? field.before : field.after;
  if (current.exists === targetExists && equalValue(current.value as PropertyValue | undefined, target)) return true;
  if (current.exists !== expectedExists || !equalValue(current.value as PropertyValue | undefined, expected)) return false;
  setNoteProperty(noteId, field.name, targetExists ? target ?? "" : null);
  return true;
}

export async function transitionBulkAction(
  location: string,
  recordId: string,
  direction: "undo" | "redo",
): Promise<{ changedIds: string[]; conflicts: BulkSkippedNote[] }> {
  const records = readHistory(location);
  const record = records.find((candidate) => candidate.id === recordId);
  if (!record) return { changedIds: [], conflicts: [] };
  const changedIds: string[] = [];
  const conflicts: BulkSkippedNote[] = [];
  for (const entry of record.entries) {
    const note = getNotes().find((candidate) => candidate.id === entry.noteId);
    const reason = noteBulkBlockReason(entry.noteId);
    if (!note || reason) {
      conflicts.push({ noteId: entry.noteId, title: note ? noteTitle(note) : entry.title, reason: reason ?? "Missing note" });
      continue;
    }
    let safe = true;
    for (const field of entry.fields) {
      if (!applyHistoryField(entry.noteId, field, direction)) safe = false;
    }
    const saved = await flushNoteWrites(entry.noteId);
    if (saved) changedIds.push(entry.noteId);
    if (!safe || !saved) {
      conflicts.push({ noteId: entry.noteId, title: entry.title, reason: "A changed value could not be safely overwritten" });
    }
  }
  const status = direction === "undo"
    ? conflicts.length ? "partially-undone" : "undone"
    : conflicts.length ? "partially-redone" : "applied";
  writeHistory(
    location,
    records.map((candidate) => candidate.id === recordId ? { ...candidate, status } : candidate),
  );
  return { changedIds, conflicts };
}
