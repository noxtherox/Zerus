import {
  EMPTY_NOTE_LIST_FILTERS,
  type NoteDateFilter,
  type NoteListFilters,
  type NotePropertyDateFilter,
  type NotePropertyDateOperator,
  type NotePropertyMatch,
  type NotePropertyFilter,
  type NoteSort,
} from "@/lib/filters";
import type { PropertyValue } from "@/lib/frontmatter";

export const NOTE_VIEW_MODES = [
  "gallery",
  "board",
  "table",
  "calendar",
  "list",
] as const;

export type NoteViewMode = (typeof NOTE_VIEW_MODES)[number];

export interface TypeViewConfig {
  mode: NoteViewMode;
  /** Properties rendered as pills on cards and list rows. */
  visibleProperties: string[];
  /** Frontmatter property used to group Gallery cards or Board columns. */
  groupBy: string | null;
  /** User-defined Kanban column order, keyed by the grouped property name. */
  boardColumnOrder: Record<string, string[]>;
  /** Frontmatter date property used by Calendar. */
  dateProperty: string | null;
  filters: NoteListFilters;
}

export type TypeViewConfigs = Record<string, TypeViewConfig>;

export interface SavedTypeView {
  id: string;
  name: string;
  config: TypeViewConfig;
}

export type SavedTypeViews = Record<string, SavedTypeView[]>;

export function defaultTypeViewConfig(): TypeViewConfig {
  return {
    mode: "list",
    visibleProperties: [],
    groupBy: null,
    boardColumnOrder: {},
    dateProperty: null,
    filters: {
      ...EMPTY_NOTE_LIST_FILTERS,
      typeKeys: [],
      fileExtensions: [],
      properties: [],
    },
  };
}

function isViewMode(value: unknown): value is NoteViewMode {
  return NOTE_VIEW_MODES.includes(value as NoteViewMode);
}

function isDateFilter(value: unknown): value is NoteDateFilter {
  return value === "today" || value === "last-7-days" || value === "last-30-days";
}

function isNoteSort(value: unknown): value is NoteSort {
  return (
    value === "updated-desc" ||
    value === "updated-asc" ||
    value === "created-desc" ||
    value === "created-asc" ||
    value === "title-asc" ||
    value === "title-desc"
  );
}

function normalizePropertyFilters(value: unknown): NotePropertyFilter[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    if (!entry || typeof entry !== "object") return [];
    const candidate = entry as Partial<NotePropertyFilter> & {
      valueKey?: unknown;
    };
    if (typeof candidate.name !== "string" || !candidate.name.trim()) return [];
    const date = normalizePropertyDateFilter(candidate.date);
    const legacyValueKey = candidate.valueKey;
    const valueKeys = Array.isArray(candidate.valueKeys)
      ? [...new Set(candidate.valueKeys.filter((item): item is string => typeof item === "string"))]
      : typeof legacyValueKey === "string"
        ? [legacyValueKey]
        : null;
    if (Array.isArray(valueKeys) && valueKeys.length === 0 && !date) return [];
    return [{ name: candidate.name.trim(), valueKeys, ...(date ? { date } : {}) }];
  });
}

const PROPERTY_DATE_OPERATORS: NotePropertyDateOperator[] = [
  "on",
  "before",
  "after",
  "on-or-before",
  "on-or-after",
  "between",
];

function normalizePropertyDateFilter(value: unknown): NotePropertyDateFilter | undefined {
  if (!value || typeof value !== "object") return undefined;
  const candidate = value as Partial<NotePropertyDateFilter>;
  if (
    !PROPERTY_DATE_OPERATORS.includes(candidate.operator as NotePropertyDateOperator) ||
    typeof candidate.date !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(candidate.date)
  ) {
    return undefined;
  }
  if (candidate.operator === "between") {
    if (typeof candidate.endDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(candidate.endDate)) {
      return undefined;
    }
    return { operator: candidate.operator, date: candidate.date, endDate: candidate.endDate };
  }
  return { operator: candidate.operator, date: candidate.date };
}

function isPropertyMatch(value: unknown): value is NotePropertyMatch {
  return value === "all" || value === "any";
}

function normalizeBoardColumnOrder(value: unknown): Record<string, string[]> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const orders: Record<string, string[]> = {};
  for (const [propertyName, order] of Object.entries(value)) {
    const key = propertyName.trim().toLowerCase();
    if (!key || !Array.isArray(order)) continue;
    orders[key] = [...new Set(order.filter((item): item is string => typeof item === "string"))];
  }
  return orders;
}

function normalizeVisibleProperties(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  return value.flatMap((item) => {
    if (typeof item !== "string" || !item.trim()) return [];
    const name = item.trim();
    const key = name.toLowerCase();
    if (seen.has(key)) return [];
    seen.add(key);
    return [name];
  });
}

export function boardColumnOrderKey(propertyName: string): string {
  return propertyName.trim().toLowerCase();
}

/** Keeps saved columns in place while appending newly discovered values. */
export function reconcileBoardColumnOrder(
  availableColumns: string[],
  savedOrder: string[] | undefined,
): string[] {
  const available = [...new Set(availableColumns)];
  const availableSet = new Set(available);
  const ordered = (savedOrder ?? []).filter(
    (column, index, values) => availableSet.has(column) && values.indexOf(column) === index,
  );
  const orderedSet = new Set(ordered);
  return [...ordered, ...available.filter((column) => !orderedSet.has(column))];
}

/**
 * Labels used when grouping notes by a frontmatter value. Multi-value
 * properties (including relations) put the note in one group per value.
 */
export function propertyGroupLabels(
  value: PropertyValue | undefined,
): string[] {
  if (value === undefined || value === "") return ["No value"];
  if (Array.isArray(value)) {
    const labels = [...new Set(value.filter((item) => item !== ""))];
    return labels.length ? labels : ["No value"];
  }
  if (typeof value === "boolean") return [value ? "Checked" : "Unchecked"];
  return [String(value)];
}

export function normalizeTypeViewConfig(value: unknown): TypeViewConfig {
  const fallback = defaultTypeViewConfig();
  if (!value || typeof value !== "object") return fallback;
  const candidate = value as Partial<TypeViewConfig>;
  const filters =
    candidate.filters && typeof candidate.filters === "object"
      ? candidate.filters
      : fallback.filters;
  return {
    mode: isViewMode(candidate.mode) ? candidate.mode : fallback.mode,
    visibleProperties: normalizeVisibleProperties(candidate.visibleProperties),
    groupBy:
      typeof candidate.groupBy === "string" && candidate.groupBy.trim()
        ? candidate.groupBy.trim()
        : null,
    boardColumnOrder: normalizeBoardColumnOrder(candidate.boardColumnOrder),
    dateProperty:
      typeof candidate.dateProperty === "string" && candidate.dateProperty.trim()
        ? candidate.dateProperty.trim()
        : null,
    filters: {
      sort: isNoteSort(filters.sort) ? filters.sort : fallback.filters.sort,
      date: isDateFilter(filters.date) ? filters.date : null,
      showArchived: filters.showArchived === true,
      typeKeys: [],
      fileExtensions: [],
      propertyMatch: isPropertyMatch(filters.propertyMatch)
        ? filters.propertyMatch
        : "all",
      properties: normalizePropertyFilters(filters.properties),
    },
  };
}

export function normalizeTypeViewConfigs(value: unknown): TypeViewConfigs {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const configs: TypeViewConfigs = {};
  for (const [key, config] of Object.entries(value)) {
    const normalizedKey = key
      .split("/")
      .map((segment) => segment.trim())
      .filter(Boolean)
      .join("/");
    if (!normalizedKey) continue;
    configs[normalizedKey] = normalizeTypeViewConfig(config);
  }
  return configs;
}

export function normalizeSavedTypeViews(value: unknown): SavedTypeViews {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const savedViews: SavedTypeViews = {};
  for (const [key, entries] of Object.entries(value)) {
    const normalizedKey = key
      .split("/")
      .map((segment) => segment.trim())
      .filter(Boolean)
      .join("/");
    if (!normalizedKey || !Array.isArray(entries)) continue;
    const seenIds = new Set<string>();
    const normalized = entries.flatMap((entry) => {
      if (!entry || typeof entry !== "object") return [];
      const candidate = entry as Partial<SavedTypeView>;
      const id = typeof candidate.id === "string" ? candidate.id.trim() : "";
      const name = typeof candidate.name === "string" ? candidate.name.trim() : "";
      if (!id || !name || seenIds.has(id)) return [];
      seenIds.add(id);
      return [{ id, name, config: normalizeTypeViewConfig(candidate.config) }];
    });
    if (normalized.length) savedViews[normalizedKey] = normalized;
  }
  return savedViews;
}

export function sameTypeViewConfig(
  left: TypeViewConfig,
  right: TypeViewConfig,
): boolean {
  return JSON.stringify(normalizeTypeViewConfig(left)) === JSON.stringify(normalizeTypeViewConfig(right));
}

export function typeViewConfigFor(
  configs: TypeViewConfigs,
  typeKey: string,
): TypeViewConfig {
  return configs[typeKey] ?? defaultTypeViewConfig();
}
