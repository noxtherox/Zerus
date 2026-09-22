import { useMemo, useState } from "react";
import {
  Archive,
  ArrowUpDown,
  CalendarDays,
  ChevronDown,
  FileType,
  Filter,
  Eye,
  EyeOff,
  Tag,
  X,
} from "@/lib/icons";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { DateInput } from "@/components/ui/date-input";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { Switch } from "@/components/ui/switch";
import { getNoteProperties } from "@/lib/frontmatter";
import {
  FILE_HUB_PROPERTY_KEYS,
  fileExtension,
  getFileHubReference,
} from "@/lib/file-hubs";
import {
  EMPTY_NOTE_LIST_FILTERS,
  type NoteDateFilter,
  type NoteListFilters as NoteListFilterState,
  type NotePropertyDateFilter,
  type NotePropertyDateOperator,
  type NotePropertyFilter,
  type NoteSort,
  propertyFilterValueKeys,
  propertyValueKey,
  propertyValueLabel,
} from "@/lib/filters";
import { formatDate, useDateFormat } from "@/lib/date-format";
import { noteReferenceLabel, type Note, noteTypePath, typeKey } from "@/lib/note-utils";
import {
  effectivePropertyDefinitions,
  type PropertySchemas,
  type PropertyType,
} from "@/lib/properties";
import { cn } from "@/lib/utils";
import { isReservedZerusProperty } from "@/lib/zerus-metadata";

const DATE_OPTIONS: { value: NoteDateFilter; label: string }[] = [
  { value: "today", label: "Today" },
  { value: "last-7-days", label: "Last 7 days" },
  { value: "last-30-days", label: "Last 30 days" },
];

const SORT_OPTIONS: { value: NoteSort; label: string }[] = [
  { value: "updated-desc", label: "Recently updated" },
  { value: "updated-asc", label: "Least recently updated" },
  { value: "created-desc", label: "Newest" },
  { value: "created-asc", label: "Oldest" },
  { value: "title-asc", label: "Title: A–Z" },
  { value: "title-desc", label: "Title: Z–A" },
];

interface NoteListFiltersProps {
  notes: Note[];
  schemas: PropertySchemas;
  showTypes: boolean;
  showFileTypes: boolean;
  showArchivedToggle: boolean;
  filters: NoteListFilterState;
  visibleProperties?: string[];
  triggerClassName?: string;
  contentClassName?: string;
  defaultSort?: NoteSort;
  showActivePills?: boolean;
  onChange: (filters: NoteListFilterState) => void;
  onVisiblePropertiesChange?: (properties: string[]) => void;
}

export function NoteListFilters({
  notes,
  schemas,
  showTypes,
  showFileTypes,
  showArchivedToggle,
  filters,
  visibleProperties = [],
  triggerClassName,
  contentClassName,
  defaultSort = EMPTY_NOTE_LIST_FILTERS.sort,
  showActivePills = true,
  onChange,
  onVisiblePropertiesChange,
}: NoteListFiltersProps) {
  const dateFormat = useDateFormat();
  const [open, setOpen] = useState(false);
  const typeOptions = useMemo(() => {
    if (!open) return [];
    const values = new Map<string, string>();
    for (const note of notes) {
      const key = typeKey(noteTypePath(note));
      values.set(key, key ? key.split("/").join(" / ") : "Unfiled");
    }
    return [...values]
      .map(([value, label]) => ({ value, label }))
      .sort((a, b) => a.label.localeCompare(b.label));
  }, [notes, open]);

  const propertyOptions = useMemo(() => {
    if (!open) return [];
    const properties = new Map<
      string,
      { name: string; values: Map<string, string>; types: Set<PropertyType> }
    >();
    for (const note of notes) {
      const definitions = effectivePropertyDefinitions(noteTypePath(note), schemas);
      for (const [name, rawValue] of Object.entries(
        getNoteProperties(note.content),
      )) {
        const normalizedName = name.toLowerCase();
        if (
          FILE_HUB_PROPERTY_KEYS.has(normalizedName) ||
          isReservedZerusProperty(normalizedName)
        ) {
          continue;
        }
        const property = properties.get(normalizedName) ?? {
          name,
          values: new Map<string, string>(),
          types: new Set<PropertyType>(),
        };
        const definition = definitions.find(
          ({ def }) => def.name.toLowerCase() === normalizedName,
        );
        if (definition) property.types.add(definition.def.type);
        const values = Array.isArray(rawValue) ? rawValue : [rawValue];
        for (const value of values) {
          const key = propertyValueKey(value);
          const rawLabel = String(value);
          property.values.set(
            key,
            rawLabel.startsWith("zerus:")
              ? noteReferenceLabel(rawLabel, notes)
              : rawLabel || "Empty",
          );
        }
        properties.set(normalizedName, property);
      }
    }
    return [...properties.values()]
      .map((property) => ({
        name: property.name,
        type:
          property.types.size === 1
            ? [...property.types][0]
            : [...property.values.values()].every((value) =>
                /^\d{4}-\d{2}-\d{2}$/.test(value),
              )
              ? "date" as const
              : undefined,
        values: [...property.values].map(([value, label]) => ({
          value,
          label,
        })),
      }))
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [notes, open, schemas]);

  const fileTypeOptions = useMemo(() => {
    if (!open) return [];
    const extensions = new Set<string>();
    for (const note of notes) {
      const fileHub = getFileHubReference(note);
      if (fileHub) extensions.add(fileExtension(fileHub.name));
    }
    return [...extensions]
      .filter(Boolean)
      .sort()
      .map((value) => ({ value, label: value.toUpperCase() }));
  }, [notes, open]);

  const activeCount =
    (filters.sort !== defaultSort ? 1 : 0) +
    (filters.date ? 1 : 0) +
    (filters.showArchived ? 1 : 0) +
    filters.typeKeys.length +
    filters.fileExtensions.length +
    filters.properties.length;

  return (
    <>
      <Popover open={open} onOpenChange={setOpen}>
        <PopoverTrigger asChild>
          <Button
            variant={activeCount ? "secondary" : "outline"}
            size="sm"
            className={cn(
              "relative h-8 w-[132px] shrink-0 justify-center gap-1.5 px-2.5",
              triggerClassName,
            )}
            title="Sort and filter notes"
            aria-label="Sort and filter notes"
          >
            <Filter size={14} />
            <span className="text-xs">Sort &amp; filter</span>
            <ChevronDown size={13} className="text-muted-foreground" />
            {activeCount > 0 && (
              <span className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-zerus-accent px-1 text-[9px] font-semibold text-white">
                {activeCount}
              </span>
            )}
          </Button>
        </PopoverTrigger>
        <PopoverContent
          align="end"
          className={cn("max-h-[70vh] w-[min(20rem,calc(100vw-2rem))] overflow-y-auto p-0", contentClassName)}
        >
          <div className="flex items-center justify-between px-3 py-2.5">
            <span className="text-sm font-semibold">Sort &amp; filter</span>
            {activeCount > 0 && (
              <Button
                variant="ghost"
                size="sm"
                className="h-7 px-2 text-xs"
                onClick={() => onChange({ ...EMPTY_NOTE_LIST_FILTERS, sort: defaultSort })}
              >
                Clear all
              </Button>
            )}
          </div>
          <Separator />
          <section className="space-y-2 p-3">
            <div className="flex items-center gap-2 text-xs font-medium text-muted-foreground">
              <ArrowUpDown size={13} /> Sort by
            </div>
            <Select
              value={filters.sort}
              onValueChange={(sort) =>
                onChange({ ...filters, sort: sort as NoteSort })
              }
            >
              <SelectTrigger className="h-8 px-2 text-xs">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {SORT_OPTIONS.map((option) => (
                  <SelectItem key={option.value} value={option.value}>
                    {option.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </section>
          <Separator />
          {showArchivedToggle && (
            <>
              <section className="p-3">
                <label className="flex cursor-pointer items-center gap-2 text-sm">
                  <Archive size={13} className="text-muted-foreground" />
                  <span className="flex-1">Show archived notes</span>
                  <Switch
                    checked={filters.showArchived}
                    onCheckedChange={(checked) =>
                      onChange({ ...filters, showArchived: checked })
                    }
                    aria-label="Show archived notes"
                  />
                </label>
              </section>
              <Separator />
            </>
          )}
          <section className="space-y-2 p-3">
            <div className="flex items-center gap-2 text-xs font-medium text-muted-foreground">
              <CalendarDays size={13} /> Updated date
            </div>
            <div className="grid grid-cols-3 gap-1.5">
              {DATE_OPTIONS.map((option) => (
                <Button
                  key={option.value}
                  variant={
                    filters.date === option.value ? "secondary" : "outline"
                  }
                  size="sm"
                  className="h-8 px-1 text-[11px]"
                  aria-pressed={filters.date === option.value}
                  onClick={() =>
                    onChange({
                      ...filters,
                      date:
                        filters.date === option.value ? null : option.value,
                    })
                  }
                >
                  {option.label}
                </Button>
              ))}
            </div>
          </section>
          {showTypes && typeOptions.length > 0 && (
            <>
              <Separator />
              <section className="space-y-2 p-3">
                <div className="flex items-center gap-2 text-xs font-medium text-muted-foreground">
                  <Tag size={13} /> Types
                </div>
                <div className="max-h-36 space-y-1 overflow-y-auto pr-1">
                  {typeOptions.map((option) => {
                    const checked = filters.typeKeys.includes(option.value);
                    return (
                      <label
                        key={option.value || "unfiled"}
                        className="flex cursor-pointer items-center gap-2 rounded px-1 py-1 text-sm hover:bg-muted/60"
                      >
                        <Checkbox
                          checked={checked}
                          onCheckedChange={(next) =>
                            onChange({
                              ...filters,
                              typeKeys: next
                                ? [...filters.typeKeys, option.value]
                                : filters.typeKeys.filter(
                                    (key) => key !== option.value,
                                  ),
                            })
                          }
                        />
                        <span className="truncate">{option.label}</span>
                      </label>
                    );
                  })}
                </div>
              </section>
            </>
          )}
          {showFileTypes && fileTypeOptions.length > 0 && (
            <>
              <Separator />
              <section className="space-y-2 p-3">
                <div className="flex items-center gap-2 text-xs font-medium text-muted-foreground">
                  <FileType size={13} /> File types
                </div>
                <div className="grid grid-cols-2 gap-1">
                  {fileTypeOptions.map((option) => (
                    <label
                      key={option.value}
                      className="flex cursor-pointer items-center gap-2 rounded px-1 py-1 text-sm hover:bg-muted/60"
                    >
                      <Checkbox
                        checked={filters.fileExtensions.includes(option.value)}
                        onCheckedChange={(next) =>
                          onChange({
                            ...filters,
                            fileExtensions: next
                              ? [...filters.fileExtensions, option.value]
                              : filters.fileExtensions.filter(
                                  (value) => value !== option.value,
                                ),
                          })
                        }
                      />
                      <span>{option.label}</span>
                    </label>
                  ))}
                </div>
              </section>
            </>
          )}
          {propertyOptions.length > 0 && (
            <>
              <Separator />
              <section className="space-y-2 p-3">
                <div className="flex items-center justify-between gap-3">
                  <div className="text-xs font-medium text-muted-foreground">
                    Properties
                  </div>
                  <div
                    className="flex items-center gap-0.5 rounded-md border border-border bg-muted/30 p-0.5"
                    role="group"
                    aria-label="Match property filters"
                  >
                    {(["all", "any"] as const).map((mode) => (
                      <button
                        key={mode}
                        type="button"
                        className={cn(
                          "rounded px-2 py-1 text-[10px] font-medium capitalize text-muted-foreground transition-colors",
                          filters.propertyMatch === mode &&
                            "bg-background text-foreground shadow-sm",
                        )}
                        aria-pressed={filters.propertyMatch === mode}
                        title={
                          mode === "all"
                            ? "Notes must match every filtered property"
                            : "Notes may match any filtered property"
                        }
                        onClick={() =>
                          onChange({ ...filters, propertyMatch: mode })
                        }
                      >
                        {mode}
                      </button>
                    ))}
                  </div>
                </div>
                {propertyOptions.map((property) => {
                  const selected = filters.properties.find(
                    (item) =>
                      item.name.toLowerCase() === property.name.toLowerCase(),
                  );
                  const selectedValueKeys = selected
                    ? propertyFilterValueKeys(selected)
                    : [];
                  const isVisible = visibleProperties.some(
                    (name) => name.toLowerCase() === property.name.toLowerCase(),
                  );
                  const remainingProperties = filters.properties.filter(
                    (item) =>
                      item.name.toLowerCase() !== property.name.toLowerCase(),
                  );
                  const selectionLabel = !selected
                    ? "Don’t filter"
                    : selected.date
                      ? datePropertyFilterLabel(selected.date, dateFormat)
                    : selectedValueKeys === null
                      ? "Has property"
                      : selectedValueKeys.length === 1
                        ? property.values.find(
                            (value) => value.value === selectedValueKeys[0],
                          )?.label ?? propertyValueLabel(selectedValueKeys[0])
                        : `${selectedValueKeys.length} selected`;
                  return (
                    <div
                      key={property.name}
                      className={cn("grid items-center gap-1.5", onVisiblePropertiesChange ? "grid-cols-[minmax(0,1fr)_28px_minmax(0,1.35fr)]" : "grid-cols-[minmax(0,1fr)_minmax(0,1.35fr)]")}
                    >
                      <span className="truncate text-xs" title={property.name}>
                        {property.name}
                      </span>
                      {onVisiblePropertiesChange && <button
                        type="button"
                        className={cn(
                          "flex h-7 w-7 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                          isVisible && "bg-zerus-accent/10 text-zerus-accent",
                        )}
                        title={isVisible ? `Hide ${property.name} on notes` : `Show ${property.name} on notes`}
                        aria-label={isVisible ? `Hide ${property.name} property` : `Show ${property.name} property`}
                        aria-pressed={isVisible}
                        onClick={() => {
                          if (!onVisiblePropertiesChange) return;
                          onVisiblePropertiesChange(
                            isVisible
                              ? visibleProperties.filter(
                                  (name) => name.toLowerCase() !== property.name.toLowerCase(),
                                )
                              : [...visibleProperties, property.name],
                          );
                        }}
                      >
                        {isVisible ? <Eye size={15} /> : <EyeOff size={15} />}
                      </button>}
                      {property.type === "date" ? (
                        <DatePropertyFilterControl
                          propertyName={property.name}
                          selected={selected}
                          filters={filters}
                          remainingProperties={remainingProperties}
                          label={selectionLabel}
                          onChange={onChange}
                        />
                      ) : (
                      <Popover>
                        <PopoverTrigger asChild>
                          <Button
                            variant="outline"
                            role="combobox"
                            className="h-8 min-w-0 justify-between gap-1 px-2 text-xs font-normal"
                            aria-label={`Filter ${property.name}: ${selectionLabel}`}
                          >
                            <span className="truncate">{selectionLabel}</span>
                            <ChevronDown
                              size={12}
                              className="shrink-0 text-muted-foreground"
                            />
                          </Button>
                        </PopoverTrigger>
                        <PopoverContent
                          align="end"
                          sideOffset={4}
                          className="w-56 p-1"
                        >
                          <label
                            className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-sm hover:bg-muted"
                          >
                            <Checkbox
                              checked={!selected}
                              onCheckedChange={() =>
                                onChange({
                                  ...filters,
                                  properties: remainingProperties,
                                })
                              }
                            />
                            <span>Don’t filter</span>
                          </label>
                          <label
                            className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-sm hover:bg-muted"
                          >
                            <Checkbox
                              checked={selectedValueKeys === null}
                              onCheckedChange={() =>
                                onChange({
                                  ...filters,
                                  properties: [
                                    ...remainingProperties,
                                    { name: property.name, valueKeys: null },
                                  ],
                                })
                              }
                            />
                            <span>Has property</span>
                          </label>
                          <Separator className="my-1" />
                          <div className="max-h-56 overflow-y-auto">
                            {property.values.map((value) => {
                              const checked = (selectedValueKeys ?? []).includes(
                                value.value,
                              );
                              return (
                                <label
                                  key={value.value}
                                  className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-sm hover:bg-muted"
                                >
                                  <Checkbox
                                    checked={checked}
                                    onCheckedChange={() => {
                                      const valueKeys = checked
                                        ? (selectedValueKeys ?? []).filter(
                                            (key) => key !== value.value,
                                          )
                                        : [
                                            ...(selectedValueKeys ?? []),
                                            value.value,
                                          ];
                                      onChange({
                                        ...filters,
                                        properties:
                                          valueKeys.length === 0
                                            ? remainingProperties
                                            : [
                                                ...remainingProperties,
                                                {
                                                  name: property.name,
                                                  valueKeys,
                                                },
                                              ],
                                      });
                                    }}
                                  />
                                  <span className="truncate">{value.label}</span>
                                </label>
                              );
                            })}
                          </div>
                        </PopoverContent>
                      </Popover>
                      )}
                    </div>
                  );
                })}
              </section>
            </>
          )}
        </PopoverContent>
      </Popover>

      {showActivePills && (
        <NoteListFilterPills
          filters={filters}
          propertyOptions={propertyOptions}
          onChange={onChange}
          className="col-span-2 pt-0.5"
        />
      )}
    </>
  );
}

const PROPERTY_DATE_OPERATOR_OPTIONS: Array<{
  value: NotePropertyDateOperator;
  label: string;
}> = [
  { value: "on", label: "Is on" },
  { value: "before", label: "Is before" },
  { value: "after", label: "Is after" },
  { value: "on-or-before", label: "Is on or before" },
  { value: "on-or-after", label: "Is on or after" },
  { value: "between", label: "Is between" },
];

function localDateKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function offsetDate(date: Date, days: number): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days);
}

function datePropertyFilterLabel(
  filter: NotePropertyDateFilter,
  format: ReturnType<typeof useDateFormat>,
): string {
  const date = formatDate(filter.date, format);
  const operator = PROPERTY_DATE_OPERATOR_OPTIONS.find(
    (option) => option.value === filter.operator,
  )?.label ?? filter.operator;
  if (filter.operator === "between" && filter.endDate) {
    return `${date} – ${formatDate(filter.endDate, format)}`;
  }
  return `${operator.replace(/^Is /, "")} ${date}`;
}

function DatePropertyFilterControl({
  propertyName,
  selected,
  filters,
  remainingProperties,
  label,
  onChange,
}: {
  propertyName: string;
  selected?: NotePropertyFilter;
  filters: NoteListFilterState;
  remainingProperties: NotePropertyFilter[];
  label: string;
  onChange: (filters: NoteListFilterState) => void;
}) {
  const today = new Date();
  const todayKey = localDateKey(today);
  const condition = selected?.date;
  const current: NotePropertyDateFilter = condition ?? {
    operator: "on",
    date: todayKey,
  };
  const setCondition = (date: NotePropertyDateFilter) =>
    onChange({
      ...filters,
      properties: [
        ...remainingProperties,
        { name: propertyName, valueKeys: null, date },
      ],
    });
  const clear = () =>
    onChange({ ...filters, properties: remainingProperties });

  const presets: Array<{
    label: string;
    value: NotePropertyDateFilter;
  }> = [
    { label: "Today", value: { operator: "on", date: todayKey } },
    {
      label: "Tomorrow",
      value: { operator: "on", date: localDateKey(offsetDate(today, 1)) },
    },
    {
      label: "Next 7 days",
      value: {
        operator: "between",
        date: todayKey,
        endDate: localDateKey(offsetDate(today, 6)),
      },
    },
    {
      label: "This month",
      value: {
        operator: "between",
        date: localDateKey(new Date(today.getFullYear(), today.getMonth(), 1)),
        endDate: localDateKey(new Date(today.getFullYear(), today.getMonth() + 1, 0)),
      },
    },
    { label: "Past due", value: { operator: "before", date: todayKey } },
  ];

  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          role="combobox"
          className="h-8 min-w-0 justify-between gap-1 px-2 text-xs font-normal"
          aria-label={`Filter ${propertyName}: ${label}`}
        >
          <span className="truncate">{label}</span>
          <ChevronDown size={12} className="shrink-0 text-muted-foreground" />
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" sideOffset={4} className="w-72 space-y-3 p-3">
        <div className="flex items-center justify-between gap-3">
          <span className="truncate text-xs font-semibold">{propertyName}</span>
          <Button variant="ghost" size="sm" className="h-7 px-2 text-xs" onClick={clear}>
            Clear
          </Button>
        </div>
        <div className="grid grid-cols-2 gap-1.5">
          {presets.map((preset) => (
            <Button
              key={preset.label}
              type="button"
              variant="outline"
              size="sm"
              className={cn(
                "h-8 justify-start px-2 text-[11px] font-normal",
                JSON.stringify(condition) === JSON.stringify(preset.value) && "border-zerus-accent/60 bg-zerus-accent/10 text-zerus-accent",
              )}
              onClick={() => setCondition(preset.value)}
            >
              {preset.label}
            </Button>
          ))}
        </div>
        <Separator />
        <div className="space-y-2">
          <Select
            value={current.operator}
            onValueChange={(operator) => {
              const nextOperator = operator as NotePropertyDateOperator;
              setCondition({
                operator: nextOperator,
                date: current.date,
                ...(nextOperator === "between"
                  ? { endDate: current.endDate ?? current.date }
                  : {}),
              });
            }}
          >
            <SelectTrigger className="h-8 px-2 text-xs">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {PROPERTY_DATE_OPERATOR_OPTIONS.map((option) => (
                <SelectItem key={option.value} value={option.value}>
                  {option.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <div className={cn("grid gap-2", current.operator === "between" && "grid-cols-2")}>
            <DateInput
              aria-label={current.operator === "between" ? `${propertyName} from` : propertyName}
              className="h-8 text-xs"
              value={current.date}
              onValueChange={(date) => date ? setCondition({ ...current, date }) : clear()}
            />
            {current.operator === "between" && (
              <DateInput
                aria-label={`${propertyName} to`}
                className="h-8 text-xs"
                value={current.endDate ?? current.date}
                onValueChange={(endDate) =>
                  endDate ? setCondition({ ...current, endDate }) : clear()
                }
              />
            )}
          </div>
          {!condition && (
            <button
              type="button"
              className="text-xs text-muted-foreground hover:text-foreground"
              onClick={() =>
                onChange({
                  ...filters,
                  properties: [
                    ...remainingProperties,
                    { name: propertyName, valueKeys: null },
                  ],
                })
              }
            >
              Only require this property to have a date
            </button>
          )}
        </div>
      </PopoverContent>
    </Popover>
  );
}

interface NoteListFilterPillsProps {
  filters: NoteListFilterState;
  propertyOptions?: Array<{
    name: string;
    values: Array<{ value: string; label: string }>;
  }>;
  className?: string;
  onChange: (filters: NoteListFilterState) => void;
}

export function NoteListFilterPills({
  filters,
  propertyOptions = [],
  className,
  onChange,
}: NoteListFilterPillsProps) {
  const dateFormat = useDateFormat();
  const activeCount =
    (filters.date ? 1 : 0) +
    (filters.showArchived ? 1 : 0) +
    filters.typeKeys.length +
    filters.fileExtensions.length +
    filters.properties.length;

  if (activeCount === 0) return null;

  return (
    <div className={cn("flex min-w-0 flex-wrap gap-1", className)}>
      {filters.showArchived && (
        <FilterPill
          label="Archived shown"
          onRemove={() => onChange({ ...filters, showArchived: false })}
        />
      )}
      {filters.date && (
        <FilterPill
          label={`Updated: ${DATE_OPTIONS.find((option) => option.value === filters.date)?.label ?? filters.date}`}
          onRemove={() => onChange({ ...filters, date: null })}
        />
      )}
      {filters.typeKeys.map((key) => (
        <FilterPill
          key={key || "unfiled"}
          label={`Type: ${key ? key.split("/").join(" / ") : "Unfiled"}`}
          onRemove={() =>
            onChange({
              ...filters,
              typeKeys: filters.typeKeys.filter((value) => value !== key),
            })
          }
        />
      ))}
      {filters.fileExtensions.map((extension) => (
        <FilterPill
          key={extension}
          label={`File: ${extension.toUpperCase()}`}
          onRemove={() =>
            onChange({
              ...filters,
              fileExtensions: filters.fileExtensions.filter((value) => value !== extension),
            })
          }
        />
      ))}
      {filters.properties.map((property) => (
        <FilterPill
          key={property.name}
          label={propertyFilterLabel(property, propertyOptions, dateFormat)}
          onRemove={() =>
            onChange({
              ...filters,
              properties: filters.properties.filter(
                (item) => item.name !== property.name,
              ),
            })
          }
        />
      ))}
    </div>
  );
}

function propertyFilterLabel(
  property: NoteListFilterState["properties"][number],
  propertyOptions: NoteListFilterPillsProps["propertyOptions"],
  dateFormat: ReturnType<typeof useDateFormat>,
): string {
  if (property.date) {
    return `${property.name}: ${datePropertyFilterLabel(property.date, dateFormat)}`;
  }
  const valueKeys = propertyFilterValueKeys(property);
  if (valueKeys === null) return `Has ${property.name}`;
  const options = propertyOptions?.find(
    (option) => option.name.toLowerCase() === property.name.toLowerCase(),
  );
  const labels = valueKeys.map(
    (valueKey) =>
      options?.values.find((value) => value.value === valueKey)?.label ??
      propertyValueLabel(valueKey),
  );
  if (labels.length <= 2) return `${property.name}: ${labels.join(" or ")}`;
  return `${property.name}: ${labels[0]} +${labels.length - 1}`;
}

function FilterPill({
  label,
  onRemove,
}: {
  label: string;
  onRemove: () => void;
}) {
  return (
    <Badge
      variant="secondary"
      className={cn(
        "h-6 max-w-full gap-1 rounded-full pl-2 pr-1 font-normal",
      )}
    >
      <span className="truncate">{label}</span>
      <button
        type="button"
        onClick={onRemove}
        className="rounded-full p-0.5 hover:bg-foreground/10"
        aria-label={`Remove ${label} filter`}
      >
        <X size={11} />
      </button>
    </Badge>
  );
}
