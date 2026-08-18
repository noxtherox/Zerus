import {
  type Note,
  isArchived,
  isExternalNote,
  isSavedLinkNote,
  isTrashed,
  noteMatchesSearch,
  noteTypePath,
  typeKey,
} from "@/lib/note-utils";
import { getNoteProperties, type PropertyValue } from "@/lib/frontmatter";
import { fileExtension, getFileHubReference } from "@/lib/file-hubs";
import { getLinkHubReference } from "@/lib/link-hubs";

export type NoteFilter =
  | { kind: "all" }
  | { kind: "external" }
  | { kind: "files" }
  | { kind: "links" }
  | { kind: "type"; path: string[]; includeSubtypes?: boolean }
  | { kind: "trash" };

export type NoteDateFilter = "today" | "last-7-days" | "last-30-days";

export interface NotePropertyFilter {
  name: string;
  /** null means the property only needs to be present. */
  valueKey: string | null;
}

export interface NoteListFilters {
  date: NoteDateFilter | null;
  showArchived: boolean;
  typeKeys: string[];
  fileExtensions: string[];
  properties: NotePropertyFilter[];
}

export const EMPTY_NOTE_LIST_FILTERS: NoteListFilters = {
  date: null,
  showArchived: false,
  typeKeys: [],
  fileExtensions: [],
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
  return filter.valueKey === null
    ? true
    : notePropertyValueKeys(entry[1]).includes(filter.valueKey);
}

function startOfLocalDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
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
        if (
          !listFilters.properties.every((item) =>
            propertyMatches(properties, item),
          )
        ) {
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
    .sort((a, b) => {
      if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.localeCompare(a.updatedAt);
    });
}
