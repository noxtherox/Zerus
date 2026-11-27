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
import { Input } from "@/components/ui/input";
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
  type NotePropertyCondition,
  type NotePropertyDateFilter,
  type NotePropertyDateOperator,
  type NotePropertyFilter,
  type NotePropertyNumberOperator,
  type NotePropertyRelativeDate,
  type NoteSort,
  PROPERTY_NUMBER_OPERATORS,
  PROPERTY_RELATIVE_DATES,
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
  mobile?: boolean;
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
  mobile = false,
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
            : inferredPropertyType(property.values),
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
      <Popover open={open} onOpenChange={setOpen} modal={mobile}>
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
          className={cn("max-h-[70vh] w-[min(20rem,calc(100vw-2rem))] overflow-y-auto p-0", mobile && "mobile-filter-sheet", contentClassName)}
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
            {mobile ? <div className="grid grid-cols-2 gap-2" role="group" aria-label="Sort by">
              {SORT_OPTIONS.map((option) => <button key={option.value} type="button" aria-pressed={filters.sort === option.value} onClick={() => onChange({ ...filters, sort: option.value })} className={cn("rounded-xl border px-3 py-2 text-left text-sm", filters.sort === option.value ? "border-zerus-accent bg-zerus-accent/15 text-zerus-accent" : "border-border bg-background")}>{option.label}</button>)}
            </div> : <Select
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
            </Select>}
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
                    : selected.condition
                      ? propertyConditionLabel(selected.condition)
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
                              checked={selectedValueKeys === null && !selected?.condition}
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
                          <PropertyConditionOptions
                            propertyName={property.name}
                            propertyType={property.type}
                            selected={selected}
                            filters={filters}
                            remainingProperties={remainingProperties}
                            onChange={onChange}
                          />
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
                                    checked={checked && !selected?.condition}
                                    onCheckedChange={() => {
                                      const current = selected?.condition ? [] : selectedValueKeys ?? [];
                                      const valueKeys = checked && !selected?.condition
                                        ? current.filter(
                                            (key) => key !== value.value,
                                          )
                                        : [...current, value.value];
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
          {mobile && <div className="sticky bottom-0 border-t bg-popover p-3"><Button className="h-11 w-full" onClick={() => setOpen(false)}>Show notes</Button></div>}
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

const RELATIVE_DATE_LABELS: Record<NotePropertyRelativeDate, string> = {
  "before-today": "Before today",
  today: "Today",
  tomorrow: "Tomorrow",
  yesterday: "Yesterday",
  "next-7-days": "Next 7 days",
  "last-7-days": "Last 7 days",
  "this-week": "This week",
  "this-month": "This month",
  "next-30-days": "Next 30 days",
  "last-30-days": "Last 30 days",
  "after-today": "After today",
};

const NUMBER_OPERATOR_LABELS: Record<NotePropertyNumberOperator, string> = {
  eq: "=",
  neq: "≠",
  gt: ">",
  gte: "≥",
  lt: "<",
  lte: "≤",
  between: "Between",
};

function inferredPropertyType(values: Map<string, string>): PropertyType | undefined {
  const keys = [...values.keys()];
  if (keys.length === 0) return undefined;
  if ([...values.values()].every((value) => /^\d{4}-\d{2}-\d{2}$/.test(value))) return "date";
  if (keys.every((key) => key.startsWith("number:"))) return "number";
  if (keys.every((key) => key.startsWith("boolean:"))) return "checkbox";
  return undefined;
}

function propertyConditionLabel(condition: NotePropertyCondition): string {
  switch (condition.kind) {
    case "empty":
      return "Is empty";
    case "not-empty":
      return "Is not empty";
    case "checked":
      return "Is checked";
    case "unchecked":
      return "Is unchecked";
    case "relative-date":
      return RELATIVE_DATE_LABELS[condition.range];
    case "number":
      return condition.operator === "between"
        ? `${condition.value} – ${condition.endValue ?? condition.value}`
        : `${NUMBER_OPERATOR_LABELS[condition.operator]} ${condition.value}`;
  }
}

function PropertyConditionOptions({
  propertyName,
  propertyType,
  selected,
  filters,
  remainingProperties,
  onChange,
}: {
  propertyName: string;
  propertyType?: PropertyType;
  selected?: NotePropertyFilter;
  filters: NoteListFilterState;
  remainingProperties: NotePropertyFilter[];
  onChange: (filters: NoteListFilterState) => void;
}) {
  const current = selected?.condition;
  const setCondition = (condition: NotePropertyCondition) =>
    onChange({
      ...filters,
      properties: [
        ...remainingProperties,
        { name: propertyName, valueKeys: null, condition },
      ],
    });
  const kinds: Array<"empty" | "not-empty" | "checked" | "unchecked"> = [
    "empty",
    "not-empty",
    ...(propertyType === "checkbox" ? (["checked", "unchecked"] as const) : []),
  ];
  const number = current?.kind === "number" ? current : null;
  const [operator, setOperator] = useState<NotePropertyNumberOperator>(number?.operator ?? "eq");
  const [value, setValue] = useState(number ? String(number.value) : "");
  const [endValue, setEndValue] = useState(
    number?.endValue !== undefined ? String(number.endValue) : "",
  );
  const commitNumber = (
    nextOperator: NotePropertyNumberOperator,
    nextValue: string,
    nextEnd: string,
  ) => {
    const parsed = parseFilterNumber(nextValue);
    const parsedEnd = parseFilterNumber(nextEnd);
    if (parsed === null || (nextOperator === "between" && parsedEnd === null)) return;
    setCondition(
      nextOperator === "between"
        ? { kind: "number", operator: nextOperator, value: parsed, endValue: parsedEnd! }
        : { kind: "number", operator: nextOperator, value: parsed },
    );
  };
  return (
    <>
      {kinds.map((kind) => (
        <label
          key={kind}
          className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-sm hover:bg-muted"
        >
          <Checkbox
            checked={current?.kind === kind}
            onCheckedChange={() =>
              current?.kind === kind
                ? onChange({ ...filters, properties: remainingProperties })
                : setCondition({ kind })
            }
          />
          <span>{propertyConditionLabel({ kind })}</span>
        </label>
      ))}
      {propertyType === "number" && (
        <div className="space-y-1.5 px-2 py-1.5">
          <div className="text-xs text-muted-foreground">Compare number</div>
          <div className="flex items-center gap-1.5">
            <Select
              value={operator}
              onValueChange={(next) => {
                const nextOperator = next as NotePropertyNumberOperator;
                setOperator(nextOperator);
                commitNumber(nextOperator, value, endValue || value);
              }}
            >
              <SelectTrigger className="h-8 w-20 px-2 text-xs" aria-label={`${propertyName} comparison`}>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {PROPERTY_NUMBER_OPERATORS.map((option) => (
                  <SelectItem key={option} value={option}>
                    {NUMBER_OPERATOR_LABELS[option]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Input
              inputMode="decimal"
              className="h-8 min-w-0 flex-1 px-2 text-xs"
              aria-label={`${propertyName} value`}
              value={value}
              onChange={(event) => {
                setValue(event.target.value);
                commitNumber(operator, event.target.value, endValue);
              }}
            />
            {operator === "between" && (
              <Input
                inputMode="decimal"
                className="h-8 min-w-0 flex-1 px-2 text-xs"
                aria-label={`${propertyName} end value`}
                value={endValue}
                onChange={(event) => {
                  setEndValue(event.target.value);
                  commitNumber(operator, value, event.target.value);
                }}
              />
            )}
          </div>
        </div>
      )}
    </>
  );
}

function parseFilterNumber(value: string): number | null {
  const trimmed = value.trim();
  if (!/^-?(\d+\.?\d*|\.\d+)$/.test(trimmed)) return null;
  const parsed = Number(trimmed);
  return Number.isFinite(parsed) ? parsed : null;
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

  const setRelative = (range: NotePropertyRelativeDate) =>
    onChange({
      ...filters,
      properties: [
        ...remainingProperties,
        { name: propertyName, valueKeys: null, condition: { kind: "relative-date", range } },
      ],
    });
  const relative =
    selected?.condition?.kind === "relative-date" ? selected.condition.range : null;

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
        <div className="grid grid-cols-2 gap-1.5" role="group" aria-label="Relative dates">
          {PROPERTY_RELATIVE_DATES.map((range) => (
            <Button
              key={range}
              type="button"
              variant="outline"
              size="sm"
              aria-pressed={relative === range}
              className={cn(
                "h-8 justify-start px-2 text-[11px] font-normal",
                relative === range && "border-zerus-accent/60 bg-zerus-accent/10 text-zerus-accent",
              )}
              onClick={() => setRelative(range)}
            >
              {RELATIVE_DATE_LABELS[range]}
            </Button>
          ))}
        </div>
        <p className="text-[10px] text-muted-foreground">
          Relative ranges follow today’s date each time the view opens.
        </p>
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
          <PropertyConditionOptions
            propertyName={propertyName}
            propertyType="date"
            selected={selected}
            filters={filters}
            remainingProperties={remainingProperties}
            onChange={onChange}
          />
          {!condition && !selected?.condition && (
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
  if (property.condition) {
    return `${property.name}: ${propertyConditionLabel(property.condition)}`;
  }
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
