import { useMemo } from "react";
import { Archive, CalendarDays, FileType, Filter, Tag, X } from "@/lib/icons";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
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
  type NoteDateFilter,
  type NoteListFilters as NoteListFilterState,
  propertyValueKey,
  propertyValueLabel,
} from "@/lib/filters";
import { type Note, noteTypePath, typeKey } from "@/lib/note-utils";
import { cn } from "@/lib/utils";

const DATE_OPTIONS: { value: NoteDateFilter; label: string }[] = [
  { value: "today", label: "Today" },
  { value: "last-7-days", label: "Last 7 days" },
  { value: "last-30-days", label: "Last 30 days" },
];

const NO_PROPERTY_FILTER = "__no_property_filter__";
const HAS_PROPERTY = "__has_property__";

interface NoteListFiltersProps {
  notes: Note[];
  showTypes: boolean;
  showFileTypes: boolean;
  showArchivedToggle: boolean;
  filters: NoteListFilterState;
  onChange: (filters: NoteListFilterState) => void;
}

export function NoteListFilters({
  notes,
  showTypes,
  showFileTypes,
  showArchivedToggle,
  filters,
  onChange,
}: NoteListFiltersProps) {
  const typeOptions = useMemo(() => {
    const values = new Map<string, string>();
    for (const note of notes) {
      const key = typeKey(noteTypePath(note));
      values.set(key, key ? key.split("/").join(" / ") : "Unfiled");
    }
    return [...values]
      .map(([value, label]) => ({ value, label }))
      .sort((a, b) => a.label.localeCompare(b.label));
  }, [notes]);

  const propertyOptions = useMemo(() => {
    const properties = new Map<
      string,
      { name: string; values: Map<string, string> }
    >();
    for (const note of notes) {
      for (const [name, rawValue] of Object.entries(
        getNoteProperties(note.content),
      )) {
        const normalizedName = name.toLowerCase();
        if (FILE_HUB_PROPERTY_KEYS.has(normalizedName)) continue;
        const property = properties.get(normalizedName) ?? {
          name,
          values: new Map<string, string>(),
        };
        const values = Array.isArray(rawValue) ? rawValue : [rawValue];
        for (const value of values) {
          const key = propertyValueKey(value);
          property.values.set(key, String(value) || "Empty");
        }
        properties.set(normalizedName, property);
      }
    }
    return [...properties.values()]
      .map((property) => ({
        ...property,
        values: [...property.values].map(([value, label]) => ({
          value,
          label,
        })),
      }))
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [notes]);

  const fileTypeOptions = useMemo(() => {
    const extensions = new Set<string>();
    for (const note of notes) {
      const fileHub = getFileHubReference(note);
      if (fileHub) extensions.add(fileExtension(fileHub.name));
    }
    return [...extensions]
      .filter(Boolean)
      .sort()
      .map((value) => ({ value, label: value.toUpperCase() }));
  }, [notes]);

  const activeCount =
    (filters.date ? 1 : 0) +
    (filters.showArchived ? 1 : 0) +
    filters.typeKeys.length +
    filters.fileExtensions.length +
    filters.properties.length;

  const removeType = (value: string) =>
    onChange({
      ...filters,
      typeKeys: filters.typeKeys.filter((key) => key !== value),
    });
  const removeProperty = (name: string) =>
    onChange({
      ...filters,
      properties: filters.properties.filter((item) => item.name !== name),
    });

  return (
    <>
      <Popover>
        <PopoverTrigger asChild>
          <Button
            variant={activeCount ? "secondary" : "outline"}
            size="icon"
            className="relative h-8 w-8 shrink-0"
            title="Filter notes"
            aria-label="Filter notes"
          >
            <Filter size={14} />
            {activeCount > 0 && (
              <span className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-grim-accent px-1 text-[9px] font-semibold text-white">
                {activeCount}
              </span>
            )}
          </Button>
        </PopoverTrigger>
        <PopoverContent
          align="end"
          className="max-h-[70vh] w-80 overflow-y-auto p-0"
        >
          <div className="flex items-center justify-between px-3 py-2.5">
            <span className="text-sm font-semibold">Filter notes</span>
            {activeCount > 0 && (
              <Button
                variant="ghost"
                size="sm"
                className="h-7 px-2 text-xs"
                onClick={() =>
                  onChange({
                    date: null,
                    showArchived: false,
                    typeKeys: [],
                    fileExtensions: [],
                    properties: [],
                  })
                }
              >
                Clear all
              </Button>
            )}
          </div>
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
                <div className="text-xs font-medium text-muted-foreground">
                  Properties
                </div>
                {propertyOptions.map((property) => {
                  const selected = filters.properties.find(
                    (item) => item.name === property.name,
                  );
                  return (
                    <div
                      key={property.name}
                      className="grid grid-cols-[minmax(0,1fr)_minmax(0,1.35fr)] items-center gap-2"
                    >
                      <span className="truncate text-xs" title={property.name}>
                        {property.name}
                      </span>
                      <Select
                        value={
                          selected?.valueKey ??
                          (selected ? HAS_PROPERTY : NO_PROPERTY_FILTER)
                        }
                        onValueChange={(value) => {
                          const remaining = filters.properties.filter(
                            (item) => item.name !== property.name,
                          );
                          onChange({
                            ...filters,
                            properties:
                              value === NO_PROPERTY_FILTER
                                ? remaining
                                : [
                                    ...remaining,
                                    {
                                      name: property.name,
                                      valueKey:
                                        value === HAS_PROPERTY ? null : value,
                                    },
                                  ],
                          });
                        }}
                      >
                        <SelectTrigger className="h-8 px-2 text-xs">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value={NO_PROPERTY_FILTER}>
                            Don’t filter
                          </SelectItem>
                          <SelectItem value={HAS_PROPERTY}>
                            Has property
                          </SelectItem>
                          {property.values.map((value) => (
                            <SelectItem key={value.value} value={value.value}>
                              {value.label}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  );
                })}
              </section>
            </>
          )}
        </PopoverContent>
      </Popover>

      {activeCount > 0 && (
        <div className="col-span-2 flex flex-wrap gap-1 pt-0.5">
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
              onRemove={() => removeType(key)}
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
              label={
                property.valueKey === null
                  ? `Has ${property.name}`
                  : `${property.name}: ${propertyValueLabel(property.valueKey)}`
              }
              onRemove={() => removeProperty(property.name)}
            />
          ))}
        </div>
      )}
    </>
  );
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
