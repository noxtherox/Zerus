import {
  EMPTY_NOTE_LIST_FILTERS,
  type NoteDateFilter,
  type NoteListFilters,
  type NotePropertyFilter,
} from "@/lib/filters";

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
  /** Frontmatter property used to group Gallery cards or Board columns. */
  groupBy: string | null;
  /** User-defined Kanban column order, keyed by the grouped property name. */
  boardColumnOrder: Record<string, string[]>;
  /** Frontmatter date property used by Calendar. */
  dateProperty: string | null;
  filters: NoteListFilters;
}

export type TypeViewConfigs = Record<string, TypeViewConfig>;

export function defaultTypeViewConfig(): TypeViewConfig {
  return {
    mode: "list",
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

function normalizePropertyFilters(value: unknown): NotePropertyFilter[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    if (!entry || typeof entry !== "object") return [];
    const candidate = entry as Partial<NotePropertyFilter>;
    if (typeof candidate.name !== "string" || !candidate.name.trim()) return [];
    if (candidate.valueKey !== null && typeof candidate.valueKey !== "string") return [];
    return [{ name: candidate.name.trim(), valueKey: candidate.valueKey ?? null }];
  });
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
      date: isDateFilter(filters.date) ? filters.date : null,
      showArchived: filters.showArchived === true,
      typeKeys: [],
      fileExtensions: [],
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

export function typeViewConfigFor(
  configs: TypeViewConfigs,
  typeKey: string,
): TypeViewConfig {
  return configs[typeKey] ?? defaultTypeViewConfig();
}
