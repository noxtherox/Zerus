import {
  type Note,
  isArchived,
  isExternalNote,
  isSavedLinkNote,
  isTrashed,
  noteMatchesSearch,
  noteTitle,
  noteTypePath,
  typeKey,
} from "@/lib/note-utils";
import { getNoteProperties, type PropertyValue } from "@/lib/frontmatter";
import { fileExtension, getFileHubReference } from "@/lib/file-hubs";
import { getLinkHubReference } from "@/lib/link-hubs";

export type NoteFilter =
  | { kind: "all" }
  | { kind: "tasks" }
  | { kind: "external" }
  | { kind: "files" }
  | { kind: "links" }
  | { kind: "type"; path: string[]; includeSubtypes?: boolean }
  | { kind: "trash" };

export type NoteDateFilter = "today" | "last-7-days" | "last-30-days";
export type NoteSort =
  | "updated-desc"
  | "updated-asc"
  | "created-desc"
  | "created-asc"
  | "title-asc"
  | "title-desc";

export type NotePropertyDateOperator =
  | "on"
  | "before"
  | "after"
  | "on-or-before"
  | "on-or-after"
  | "between";

export interface NotePropertyDateFilter {
  operator: NotePropertyDateOperator;
  date: string;
  endDate?: string;
}

export interface NotePropertyFilter {
  name: string;
  /** null means the property only needs to be present. */
  valueKeys: string[] | null;
  /** Date properties use comparisons instead of enumerating stored values. */
  date?: NotePropertyDateFilter;
}

interface LegacyNotePropertyFilter {
  name: string;
  valueKey: string | null;
  date?: NotePropertyDateFilter;
}

export type NotePropertyMatch = "all" | "any";

export interface NoteListFilters {
  sort: NoteSort;
  date: NoteDateFilter | null;
  showArchived: boolean;
  typeKeys: string[];
  fileExtensions: string[];
  propertyMatch: NotePropertyMatch;
  properties: NotePropertyFilter[];
}

export const EMPTY_NOTE_LIST_FILTERS: NoteListFilters = {
  sort: "created-desc",
  date: null,
  showArchived: false,
  typeKeys: [],
  fileExtensions: [],
  propertyMatch: "all",
  properties: [],
};

export function propertyValueKey(
  value: Exclude<PropertyValue, string[]>,
): string {
  return `${typeof value}:${String(value)}`;
}

export function propertyValueLabel(valueKey: string): string {
  return valueKey.slice(valueKey.indexOf(":") + 1);
}

/** Keeps live pre-upgrade filters safe across desktop/web hot refreshes. */
export function propertyFilterValueKeys(
  filter: NotePropertyFilter | LegacyNotePropertyFilter,
): string[] | null {
  const candidate = filter as NotePropertyFilter & { valueKey?: unknown };
  if (candidate.valueKeys === null || Array.isArray(candidate.valueKeys)) {
    return candidate.valueKeys;
  }
  if (candidate.valueKey === null) return null;
  return typeof candidate.valueKey === "string" ? [candidate.valueKey] : [];
}

function notePropertyValueKeys(value: PropertyValue): string[] {
  return Array.isArray(value)
    ? value.map((item) => propertyValueKey(item))
    : [propertyValueKey(value)];
}

function propertyMatches(
  properties: Record<string, PropertyValue>,
  filter: NotePropertyFilter,
): boolean {
  const entry = Object.entries(properties).find(
    ([name]) => name.toLowerCase() === filter.name.toLowerCase(),
  );
  if (!entry) return false;
  if (filter.date) {
    const candidates = (Array.isArray(entry[1]) ? entry[1] : [entry[1]])
      .filter((value): value is string =>
        typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value),
      );
    const { operator, date, endDate } = filter.date;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return false;
    return candidates.some((candidate) => {
      if (operator === "on") return candidate === date;
      if (operator === "before") return candidate < date;
      if (operator === "after") return candidate > date;
      if (operator === "on-or-before") return candidate <= date;
      if (operator === "on-or-after") return candidate >= date;
      if (!endDate || !/^\d{4}-\d{2}-\d{2}$/.test(endDate)) return false;
      const [start, end] = date <= endDate ? [date, endDate] : [endDate, date];
      return candidate >= start && candidate <= end;
    });
  }
  const valueKeys = propertyFilterValueKeys(filter);
  return valueKeys === null
    ? true
    : valueKeys.some((valueKey) =>
        notePropertyValueKeys(entry[1]).includes(valueKey),
      );
}

function startOfLocalDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function sortTitle(note: Note, filter: NoteFilter): string {
  if (filter.kind === "files") {
    return getFileHubReference(note)?.name ?? noteTitle(note);
  }
  return noteTitle(note);
}

function compareNotes(a: Note, b: Note, filter: NoteFilter, sort: NoteSort): number {
  if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
  if (sort === "updated-asc") return a.updatedAt.localeCompare(b.updatedAt);
  if (sort === "created-desc") {
    return (b.createdAt ?? b.updatedAt).localeCompare(a.createdAt ?? a.updatedAt);
  }
  if (sort === "created-asc") {
    return (a.createdAt ?? a.updatedAt).localeCompare(b.createdAt ?? b.updatedAt);
  }
  if (sort === "title-asc") {
    return sortTitle(a, filter).localeCompare(sortTitle(b, filter), undefined, {
      sensitivity: "base",
      numeric: true,
    });
  }
  if (sort === "title-desc") {
    return sortTitle(b, filter).localeCompare(sortTitle(a, filter), undefined, {
      sensitivity: "base",
      numeric: true,
    });
  }
  return b.updatedAt.localeCompare(a.updatedAt);
}

function matchesDateFilter(
  iso: string,
  dateFilter: NoteDateFilter,
  now: Date,
): boolean {
  const days =
    dateFilter === "today" ? 1 : dateFilter === "last-7-days" ? 7 : 30;
  const threshold = startOfLocalDay(now);
  threshold.setDate(threshold.getDate() - (days - 1));
  const updatedAt = new Date(iso);
  return !Number.isNaN(updatedAt.getTime()) && updatedAt >= threshold;
}

/** Type filters include notes in sub-types unless explicitly disabled. */
export function filterNotes(
  notes: Note[],
  filter: NoteFilter,
  search: string,
  listFilters: NoteListFilters = EMPTY_NOTE_LIST_FILTERS,
  now = new Date(),
): Note[] {
  const visible = notes.filter((note) => {
    if (filter.kind === "tasks") return false;
    if (filter.kind === "external") return isExternalNote(note);
    if (filter.kind === "trash") return !isExternalNote(note) && isTrashed(note);
    if (isArchived(note) && !listFilters.showArchived) return false;
    if (filter.kind === "files") {
      return (
        !isExternalNote(note) &&
        !isTrashed(note) &&
        getFileHubReference(note) !== null
      );
    }
    if (filter.kind === "links") {
      return (
        !isExternalNote(note) &&
        !isTrashed(note) &&
        getLinkHubReference(note) !== null
      );
    }
    if (isExternalNote(note)) return false;
    if (isSavedLinkNote(note)) return false;
    if (isTrashed(note)) return false;
    if (filter.kind === "type") {
      const prefix = typeKey(filter.path);
      const key = typeKey(noteTypePath(note));
      return (
        key === prefix ||
        (filter.includeSubtypes !== false && key.startsWith(`${prefix}/`))
      );
    }
    return true;
  });
  return visible
    .filter((note) => noteMatchesSearch(note, search))
    .filter((note) => {
      if (
        listFilters.date &&
        !matchesDateFilter(note.updatedAt, listFilters.date, now)
      ) {
        return false;
      }
      if (listFilters.typeKeys.length > 0) {
        const noteType = typeKey(noteTypePath(note));
        if (!listFilters.typeKeys.includes(noteType)) return false;
      }
      if (listFilters.properties.length > 0) {
        const properties = getNoteProperties(note.content);
        const matches = listFilters.properties.map((item) =>
          propertyMatches(properties, item),
        );
        const propertiesMatch =
          listFilters.propertyMatch === "any"
            ? matches.some(Boolean)
            : matches.every(Boolean);
        if (!propertiesMatch) {
          return false;
        }
      }
      if (listFilters.fileExtensions.length > 0) {
        const fileHub = getFileHubReference(note);
        if (
          !fileHub ||
          !listFilters.fileExtensions.includes(fileExtension(fileHub.name))
        ) {
          return false;
        }
      }
      return true;
    })
    .sort((a, b) => compareNotes(a, b, filter, listFilters.sort));
}
