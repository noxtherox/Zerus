import {
  type Note,
  isArchived,
  isExternalNote,
  isManagedSavedLinkNote,
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

export type NotePropertyNumberOperator =
  | "eq"
  | "neq"
  | "gt"
  | "gte"
  | "lt"
  | "lte"
  | "between";

/** Resolved against the viewer's local day; weeks start on Monday everywhere. */
export type NotePropertyRelativeDate =
  | "before-today"
  | "today"
  | "tomorrow"
  | "yesterday"
  | "next-7-days"
  | "last-7-days"
  | "this-week"
  | "this-month"
  | "next-30-days"
  | "last-30-days"
  | "after-today";

export type NotePropertyCondition =
  | { kind: "empty" }
  | { kind: "not-empty" }
  | { kind: "checked" }
  | { kind: "unchecked" }
  | {
      kind: "number";
      operator: NotePropertyNumberOperator;
      value: number;
      endValue?: number;
    }
  | { kind: "relative-date"; range: NotePropertyRelativeDate };

export const PROPERTY_NUMBER_OPERATORS: NotePropertyNumberOperator[] = [
  "eq",
  "neq",
  "gt",
  "gte",
  "lt",
  "lte",
  "between",
];

export const PROPERTY_RELATIVE_DATES: NotePropertyRelativeDate[] = [
  "before-today",
  "today",
  "tomorrow",
  "yesterday",
  "next-7-days",
  "last-7-days",
  "this-week",
  "this-month",
  "next-30-days",
  "last-30-days",
  "after-today",
];

export interface NotePropertyFilter {
  name: string;
  /** null means the property only needs to be present. */
  valueKeys: string[] | null;
  /** Date properties use comparisons instead of enumerating stored values. */
  date?: NotePropertyDateFilter;
  /**
   * Takes precedence over valueKeys and date. Stored with `valueKeys: null`,
   * so clients that predate conditions still read a presence filter.
   */
  condition?: NotePropertyCondition;
}

/** Returns a valid condition, or undefined for unknown or incomplete input. */
export function normalizePropertyCondition(
  value: unknown,
): NotePropertyCondition | undefined {
  if (!value || typeof value !== "object") return undefined;
  const candidate = value as Record<string, unknown>;
  switch (candidate.kind) {
    case "empty":
    case "not-empty":
    case "checked":
    case "unchecked":
      return { kind: candidate.kind };
    case "number": {
      const operator = candidate.operator as NotePropertyNumberOperator;
      if (!PROPERTY_NUMBER_OPERATORS.includes(operator)) return undefined;
      if (typeof candidate.value !== "number" || !Number.isFinite(candidate.value)) {
        return undefined;
      }
      if (operator !== "between") {
        return { kind: "number", operator, value: candidate.value };
      }
      if (typeof candidate.endValue !== "number" || !Number.isFinite(candidate.endValue)) {
        return undefined;
      }
      return {
        kind: "number",
        operator,
        value: candidate.value,
        endValue: candidate.endValue,
      };
    }
    case "relative-date": {
      const range = candidate.range as NotePropertyRelativeDate;
      return PROPERTY_RELATIVE_DATES.includes(range)
        ? { kind: "relative-date", range }
        : undefined;
    }
    default:
      return undefined;
  }
}

function localDateKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

/** Inclusive yyyy-mm-dd bounds for a relative range; null leaves a side open. */
export function relativeDateBounds(
  range: NotePropertyRelativeDate,
  now: Date,
): [string | null, string | null] {
  const y = now.getFullYear();
  const m = now.getMonth();
  const d = now.getDate();
  const day = (offset: number) => localDateKey(new Date(y, m, d + offset));
  switch (range) {
    case "before-today":
      return [null, day(-1)];
    case "today":
      return [day(0), day(0)];
    case "tomorrow":
      return [day(1), day(1)];
    case "yesterday":
      return [day(-1), day(-1)];
    case "next-7-days":
      return [day(0), day(6)];
    case "last-7-days":
      return [day(-6), day(0)];
    case "next-30-days":
      return [day(0), day(29)];
    case "last-30-days":
      return [day(-29), day(0)];
    case "after-today":
      return [day(1), null];
    case "this-week": {
      const sinceMonday = (now.getDay() + 6) % 7;
      return [day(-sinceMonday), day(6 - sinceMonday)];
    }
    case "this-month":
      return [
        localDateKey(new Date(y, m, 1)),
        localDateKey(new Date(y, m + 1, 0)),
      ];
  }
}

/** Blank strings, empty lists and a missing property all count as empty. */
function isEmptyPropertyValue(value: PropertyValue | undefined): boolean {
  if (value === undefined) return true;
  if (typeof value === "string") return value.trim() === "";
  if (Array.isArray(value)) return value.every((item) => item.trim() === "");
  return false;
}

function conditionMatches(
  value: PropertyValue | undefined,
  condition: NotePropertyCondition,
  now: Date,
): boolean {
  switch (condition.kind) {
    case "empty":
      return isEmptyPropertyValue(value);
    case "not-empty":
      return !isEmptyPropertyValue(value);
    case "checked":
      return value === true;
    case "unchecked":
      return value === false || isEmptyPropertyValue(value);
    case "number": {
      if (typeof value !== "number" || !Number.isFinite(value)) return false;
      const target = condition.value;
      switch (condition.operator) {
        case "eq":
          return value === target;
        case "neq":
          return value !== target;
        case "gt":
          return value > target;
        case "gte":
          return value >= target;
        case "lt":
          return value < target;
        case "lte":
          return value <= target;
        case "between": {
          const end = condition.endValue ?? target;
          return value >= Math.min(target, end) && value <= Math.max(target, end);
        }
      }
      return false;
    }
    case "relative-date": {
      if (value === undefined) return false;
      const [start, end] = relativeDateBounds(condition.range, now);
      return (Array.isArray(value) ? value : [value]).some(
        (candidate) =>
          typeof candidate === "string" &&
          /^\d{4}-\d{2}-\d{2}$/.test(candidate) &&
          (start === null || candidate >= start) &&
          (end === null || candidate <= end),
      );
    }
  }
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
  now: Date,
): boolean {
  const entry = Object.entries(properties).find(
    ([name]) => name.toLowerCase() === filter.name.toLowerCase(),
  );
  if (filter.condition) return conditionMatches(entry?.[1], filter.condition, now);
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
    if (isManagedSavedLinkNote(note)) return false;
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
          propertyMatches(properties, item, now),
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
