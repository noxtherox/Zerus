import { useState } from "react";
import {
  ArrowLeftRight,
  ArrowRight,
  Calendar,
  CheckSquare,
  ExternalLink,
  Hash,
  Link,
  List,
  Loader2,
  Pencil,
  Plus,
  SlidersHorizontal,
  Type as TypeIcon,
  X,
} from "@/lib/icons";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { type PropertyValue, getNoteProperties } from "@/lib/frontmatter";
import {
  PROPERTY_TYPES,
  type PropertyDef,
  type PropertySchemas,
  type PropertyType,
  effectivePropertyDefinitions,
  inferPropertyType,
  listOptionToCreate,
  listPickerLabel,
  listPropertyValue,
  listSelections,
  normalizeListOptions,
  sanitizePropertyName,
  schemaKeyFor,
} from "@/lib/properties";
import {
  type Note,
  findNoteByTitle,
  getAllTypePaths,
  isExternalNote,
  isTrashed,
  noteTitle,
  noteTypePath,
  notesOfTypeKey,
  parseTypePath,
  typeKey,
} from "@/lib/note-utils";
import {
  addTypeProperty,
  createNote,
  removeTypeProperty,
  setNoteProperty,
  updateTypeProperty,
  useVault,
} from "@/store/notes-store";
import { cn } from "@/lib/utils";
import { FILE_HUB_PROPERTY_KEYS } from "@/lib/file-hubs";
import { isReservedZerusProperty } from "@/lib/zerus-metadata";
import { hasRelationTo } from "@/lib/links";
import {
  normalizeExternalUrl,
  openExternalUrl,
} from "@/lib/external-links";

const TYPE_ICONS: Record<PropertyType, typeof TypeIcon> = {
  text: TypeIcon,
  url: ExternalLink,
  number: Hash,
  date: Calendar,
  checkbox: CheckSquare,
  list: List,
  relation: Link,
};

const PROPERTY_DEFINITION_TYPES = PROPERTY_TYPES.map(
  ({ value }) => value,
).filter((type) => type !== "relation");

// ---- value editors -----------------------------------------------------------

interface ValueEditorProps {
  def: PropertyDef;
  value: PropertyValue | undefined;
  allNotes: Note[];
  currentNote: Note;
  schemas: PropertySchemas;
  onOpenNote: (id: string) => void;
  onCommit: (value: PropertyValue | null) => void;
}

const inputClass =
  "h-6 rounded border-transparent bg-transparent px-1.5 text-xs shadow-none hover:bg-muted/60 focus-visible:bg-white focus-visible:ring-1";

const wrapEditorClass =
  "w-full resize-none overflow-hidden whitespace-pre-wrap break-words rounded px-1.5 py-1 text-xs leading-4";

interface WrapTextareaProps {
  value: string;
  placeholder?: string;
  onChange: (text: string) => void;
  onBlur?: () => void;
}

// Single-line look, but grows and wraps when the value is long. The invisible
// replica sizes the grid cell; the textarea stretches to match it.
function WrapTextarea({
  value,
  placeholder,
  onChange,
  onBlur,
}: WrapTextareaProps) {
  return (
    <div className="grid">
      <span
        aria-hidden
        className={`${wrapEditorClass} invisible [grid-area:1/1]`}
      >
        {value || placeholder}{" "}
      </span>
      <textarea
        rows={1}
        value={value}
        placeholder={placeholder}
        className={`${wrapEditorClass} [grid-area:1/1] bg-transparent outline-none placeholder:text-muted-foreground hover:bg-muted/60 focus-visible:bg-white focus-visible:ring-1 focus-visible:ring-ring`}
        onChange={(e) => onChange(e.target.value.replace(/\n/g, " "))}
        onKeyDown={(e) => {
          if (e.key === "Enter") {
            e.preventDefault();
            e.currentTarget.blur();
          }
        }}
        onBlur={onBlur}
      />
    </div>
  );
}

export function ListValueEditor({
  def,
  value,
  onCommit,
  onCreateOption,
  onDeleteOption,
  emptyPickerLabel = "Select",
  selectedPickerLabel = "Add",
  searchPlaceholder = "Search options…",
}: {
  def: PropertyDef;
  value: PropertyValue | undefined;
  onCommit: (value: PropertyValue | null) => void;
  onCreateOption?: (option: string) => void;
  onDeleteOption?: (option: string) => void;
  emptyPickerLabel?: string;
  selectedPickerLabel?: string;
  searchPlaceholder?: string;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const selected = listSelections(value);
  const selectedKeys = new Set(selected.map((item) => item.toLowerCase()));
  const options = normalizeListOptions(def.listOptions ?? []);
  const available = onDeleteOption
    ? options
    : options.filter((option) => !selectedKeys.has(option.toLowerCase()));
  const multiple = def.listMultiple === true;
  const optionToCreate = onCreateOption
    ? listOptionToCreate(query, options)
    : null;

  const remove = (option: string) => {
    const next = selected.filter(
      (item) => item.toLowerCase() !== option.toLowerCase(),
    );
    onCommit(listPropertyValue(next, multiple));
  };

  const pick = (option: string) => {
    const next = multiple ? [...selected, option] : [option];
    onCommit(listPropertyValue(next, multiple));
    setOpen(false);
    setQuery("");
  };

  const createAndPick = () => {
    if (!optionToCreate || !onCreateOption) return;
    onCreateOption(optionToCreate);
    pick(optionToCreate);
  };

  const showPicker = multiple || selected.length === 0 || Boolean(onDeleteOption);

  return (
    <div className="flex min-h-6 flex-wrap items-center gap-1 px-0.5 py-0.5">
      {selected.map((option) => (
        <span
          key={option.toLowerCase()}
          className="inline-flex max-w-full items-center gap-1 rounded-full border border-primary/25 bg-primary/10 px-1.5 py-0.5 text-xs text-foreground"
        >
          <span className="truncate">{option}</span>
          <button
            type="button"
            className="shrink-0 opacity-60 hover:opacity-100"
            title={`Remove ${option}`}
            aria-label={`Remove ${option}`}
            onClick={() => remove(option)}
          >
            <X size={10} />
          </button>
        </span>
      ))}
      {showPicker && (
        <Popover
          open={open}
          onOpenChange={(nextOpen) => {
            setOpen(nextOpen);
            if (!nextOpen) setQuery("");
          }}
        >
          <PopoverTrigger asChild>
            <button
              type="button"
              className="flex h-5 items-center gap-0.5 rounded-full px-1.5 text-[11px] text-muted-foreground hover:bg-muted/60 hover:text-foreground"
            >
              <Plus size={10} />
              {selected.length && onDeleteOption
                ? selectedPickerLabel
                : listPickerLabel(selected.length, options.length, emptyPickerLabel)}
            </button>
          </PopoverTrigger>
          <PopoverContent className="w-56 p-0" align="start">
            <Command>
              <CommandInput
                value={query}
                onValueChange={setQuery}
                placeholder={searchPlaceholder}
              />
              <CommandList>
                <CommandEmpty>
                  {onCreateOption
                    ? "Type a new option to create it."
                    : options.length
                      ? "No matching options."
                      : "No options configured."}
                </CommandEmpty>
                <CommandGroup>
                  {optionToCreate && (
                    <CommandItem
                      value={`create ${optionToCreate}`}
                      onSelect={createAndPick}
                    >
                      <Plus size={13} className="mr-1.5" />
                      Create “{optionToCreate}”
                    </CommandItem>
                  )}
                  {available.map((option) => (
                    <CommandItem
                      key={option.toLowerCase()}
                      value={option}
                      onSelect={() => pick(option)}
                    >
                      <span className="min-w-0 flex-1 truncate">{option}</span>
                      {onDeleteOption && (
                        <button
                          type="button"
                          className="ml-2 shrink-0 rounded p-1 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
                          aria-label={`Delete ${option} option`}
                          onPointerDown={(event) => {
                            event.preventDefault();
                            event.stopPropagation();
                          }}
                          onClick={(event) => {
                            event.preventDefault();
                            event.stopPropagation();
                            setOpen(false);
                            setQuery("");
                            onDeleteOption(option);
                          }}
                        >
                          <X size={12} />
                        </button>
                      )}
                    </CommandItem>
                  ))}
                </CommandGroup>
              </CommandList>
            </Command>
          </PopoverContent>
        </Popover>
      )}
    </div>
  );
}

function UrlValueEditor({
  value,
  onCommit,
}: {
  value: PropertyValue | undefined;
  onCommit: (value: PropertyValue | null) => void;
}) {
  const [editing, setEditing] = useState(false);
  const text = value === undefined ? "" : String(value);
  const normalized = normalizeExternalUrl(text);

  if (!editing && normalized) {
    return (
      <div className="flex min-h-6 min-w-0 items-center gap-1 px-1.5 text-xs">
        <button
          type="button"
          className="flex min-w-0 items-center gap-1 text-left text-zerus-link hover:underline"
          title={`Open ${normalized}`}
          onClick={() => void openExternalUrl(normalized)}
        >
          <span className="truncate">{text}</span>
          <ExternalLink size={11} className="shrink-0" />
        </button>
        <button
          type="button"
          className="ml-auto shrink-0 rounded p-0.5 text-muted-foreground opacity-70 hover:bg-muted hover:text-foreground hover:opacity-100"
          aria-label={`Edit URL ${text}`}
          title="Edit URL"
          onClick={() => setEditing(true)}
        >
          <Pencil size={11} />
        </button>
      </div>
    );
  }

  return (
    <Input
      type="url"
      autoFocus={editing}
      key={text}
      defaultValue={text}
      placeholder="https://example.com"
      className={inputClass}
      onKeyDown={(event) => {
        if (event.key === "Enter") event.currentTarget.blur();
      }}
      onBlur={(event) => {
        onCommit(event.target.value.trim() || null);
        setEditing(false);
      }}
    />
  );
}

function RelationChip({
  title,
  note,
  reciprocal,
  expanded,
  onOpenNote,
  onRemove,
}: {
  title: string;
  note: Note | undefined;
  reciprocal: boolean;
  expanded?: boolean;
  onOpenNote: (id: string) => void;
  onRemove: () => void;
}) {
  return (
    <span
      className={cn(
        "flex min-h-10 min-w-0 items-center gap-2 rounded-md border px-3 py-2 text-sm",
        note
          ? "border-border/50 bg-zerus-editor text-zerus-link transition-colors hover:border-zerus-accent/40 hover:bg-zerus-accent/5"
          : "border-dashed border-muted-foreground/40 bg-zerus-editor text-muted-foreground",
        expanded && "h-full",
      )}
    >
      {reciprocal ? (
        <ArrowLeftRight
          size={13}
          className="shrink-0 opacity-80"
          aria-label="Bidirectional relation"
          title="Bidirectional relation"
        />
      ) : (
        <ArrowRight
          size={13}
          className="shrink-0 opacity-80"
          aria-label="Outgoing relation"
        />
      )}
      {note ? (
        <button
          type="button"
          className="min-w-0 flex-1 truncate text-left font-medium"
          title={`Open "${title}"`}
          onClick={() => onOpenNote(note.id)}
        >
          {title}
        </button>
      ) : (
        <span
          className="min-w-0 flex-1 truncate italic"
          title="No note matches this title"
        >
          {title}
        </span>
      )}
      <button
        type="button"
        className="shrink-0 rounded p-0.5 opacity-60 hover:bg-muted hover:opacity-100"
        title="Remove"
        onClick={onRemove}
      >
        <X size={10} />
      </button>
    </span>
  );
}

function RelationValueEditor({
  def,
  value,
  allNotes,
  currentNote,
  schemas,
  onOpenNote,
  onCommit,
  expanded,
}: {
  def: PropertyDef;
  value: PropertyValue | undefined;
  allNotes: Note[];
  currentNote: Note;
  schemas: PropertySchemas;
  onOpenNote: (id: string) => void;
  onCommit: (value: PropertyValue | null) => void;
  expanded?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [creating, setCreating] = useState(false);

  const titles = Array.isArray(value)
    ? value
    : value === undefined || value === null || value === ""
      ? []
      : [String(value)];
  const selectedLower = new Set(titles.map((title) => title.toLowerCase()));

  const relatedNotes = (
    def.relationTypeKey
      ? notesOfTypeKey(allNotes, def.relationTypeKey)
      : allNotes.filter((note) => !isExternalNote(note) && !isTrashed(note))
  ).filter((note) => note.id !== currentNote.id);
  const candidates = relatedNotes.filter(
    (note) => !selectedLower.has(noteTitle(note).toLowerCase()),
  );

  const pick = (note: Note) => {
    const title = noteTitle(note);
    onCommit(def.relationMultiple ? [...titles, title] : title);
    setQuery("");
    setOpen(false);
  };

  const relatedTypePath = def.relationTypeKey
    ? parseTypePath(def.relationTypeKey)
    : noteTypePath(currentNote);
  const relatedTypeLabel =
    relatedTypePath.at(-1) ?? (def.name || "current type");
  const createTitle = query.trim() || "Untitled";
  const normalizedCreateTitle = query.trim().toLocaleLowerCase();
  const hasExactTitleMatch =
    selectedLower.has(normalizedCreateTitle) ||
    relatedNotes.some(
      (note) =>
        noteTitle(note).trim().toLocaleLowerCase() === normalizedCreateTitle,
    );
  const showCreateAction =
    normalizedCreateTitle.length >= 2 && !hasExactTitleMatch;

  const createRelatedNote = async () => {
    if (creating) return;
    setCreating(true);
    try {
      const created = await createNote(
        relatedTypePath,
        `# ${createTitle}\n\n`,
      );
      if (!created) return;

      // Linking from the current note makes it appear automatically in the
      // new note's Backlinks panel without duplicating relation metadata.
      pick(created);
      onOpenNote(created.id);
    } finally {
      setCreating(false);
    }
  };

  const remove = (title: string) => {
    const next = titles.filter((t) => t.toLowerCase() !== title.toLowerCase());
    onCommit(next.length ? next : null);
  };

  const showAdd = def.relationMultiple || titles.length === 0;

  return (
    <div className="relative space-y-1.5">
      {showAdd && (
        <Popover open={open} onOpenChange={setOpen}>
          <Tooltip>
            <TooltipTrigger asChild>
              <PopoverTrigger asChild>
                <button
                  type="button"
                  className="absolute right-0 -top-7 flex h-6 w-6 items-center justify-center rounded text-muted-foreground hover:bg-muted/60 hover:text-foreground"
                  aria-label={`Add a link to ${def.name}`}
                >
                  <Plus size={13} />
                </button>
              </PopoverTrigger>
            </TooltipTrigger>
            <TooltipContent side="left">
              Add a link to {def.name}
            </TooltipContent>
          </Tooltip>
          <PopoverContent className="w-64 p-0" align="end">
            <Command>
              <CommandInput
                placeholder={
                  def.relationTypeKey
                    ? `Search "${def.relationTypeKey}"…`
                    : "Search notes…"
                }
                value={query}
                onValueChange={setQuery}
              />
              <CommandList>
                <CommandEmpty>No matching notes.</CommandEmpty>
                <CommandGroup>
                  {candidates.slice(0, 100).map((note) => (
                    <CommandItem
                      key={note.id}
                      value={noteTitle(note)}
                      onSelect={() => pick(note)}
                    >
                      {noteTitle(note)}
                    </CommandItem>
                  ))}
                </CommandGroup>
              </CommandList>
              {showCreateAction && (
                <div className="border-t p-1">
                  <button
                    type="button"
                    disabled={creating}
                    onMouseDown={(event) => event.preventDefault()}
                    onClick={() => void createRelatedNote()}
                    className="flex w-full items-center rounded-sm px-2 py-1.5 text-left text-sm hover:bg-accent hover:text-accent-foreground disabled:pointer-events-none disabled:opacity-50"
                  >
                    {creating ? (
                      <Loader2 size={14} className="mr-2 animate-spin" />
                    ) : (
                      <Plus size={14} className="mr-2" />
                    )}
                    <span className="truncate">
                      Create “{createTitle}” in {relatedTypeLabel}
                    </span>
                  </button>
                </div>
              )}
            </Command>
          </PopoverContent>
        </Popover>
      )}
      <div
        className={cn(
          expanded
            ? "grid grid-cols-1 gap-2 md:grid-cols-2 xl:grid-cols-3"
            : "space-y-1",
        )}
      >
        {titles.map((title) => {
          const linkedNote = findNoteByTitle(title, allNotes);
          return (
            <RelationChip
              key={title}
              title={title}
              note={linkedNote}
              reciprocal={
                linkedNote
                  ? hasRelationTo(linkedNote, currentNote, schemas)
                  : false
              }
              expanded={expanded}
              onOpenNote={onOpenNote}
              onRemove={() => remove(title)}
            />
          );
        })}
      </div>
      {titles.length === 0 && (
        <p className="py-1 text-xs text-muted-foreground">
          No {def.name} linked
        </p>
      )}
    </div>
  );
}

function ValueEditor({
  def,
  value,
  allNotes,
  currentNote,
  schemas,
  onOpenNote,
  onCommit,
}: ValueEditorProps) {
  const type = def.type;
  if (type === "relation") {
    return (
      <RelationValueEditor
        def={def}
        value={value}
        allNotes={allNotes}
        currentNote={currentNote}
        schemas={schemas}
        onOpenNote={onOpenNote}
        onCommit={onCommit}
        expanded={false}
      />
    );
  }
  if (type === "checkbox") {
    return (
      <Checkbox
        className="ml-1.5 mt-1"
        checked={value === true}
        onCheckedChange={(checked) => onCommit(checked === true)}
      />
    );
  }
  if (type === "date") {
    return (
      <Input
        type="date"
        className={inputClass}
        value={typeof value === "string" ? value : ""}
        onChange={(e) => onCommit(e.target.value || null)}
      />
    );
  }
  if (type === "number") {
    const text = typeof value === "number" ? String(value) : "";
    return (
      <Input
        type="number"
        key={text}
        defaultValue={text}
        placeholder="Empty"
        className={inputClass}
        onKeyDown={(e) => e.key === "Enter" && e.currentTarget.blur()}
        onBlur={(e) => {
          const parsed = parseFloat(e.target.value);
          onCommit(Number.isFinite(parsed) ? parsed : null);
        }}
      />
    );
  }
  if (type === "list") {
    return <ListValueEditor def={def} value={value} onCommit={onCommit} />;
  }
  if (type === "url") {
    return <UrlValueEditor value={value} onCommit={onCommit} />;
  }
  return (
    <WrapTextarea
      placeholder="Empty"
      value={value === undefined ? "" : String(value)}
      onChange={(text) => onCommit(text || null)}
    />
  );
}

// ---- add / edit definition form ------------------------------------------------

interface DefFormProps {
  initial?: PropertyDef;
  submitLabel: string;
  existingTypePaths: string[][];
  allowedTypes?: PropertyType[];
  onSubmit: (def: PropertyDef) => void;
  onDelete?: () => void;
}

export function ListOptionsField({
  options,
  onChange,
}: {
  options: string[];
  onChange: (options: string[]) => void;
}) {
  const [draft, setDraft] = useState("");

  const addDraft = () => {
    const next = normalizeListOptions([...options, draft]);
    if (next.length === options.length) return;
    onChange(next);
    setDraft("");
  };

  return (
    <div className="space-y-1.5">
      <span className="text-xs text-muted-foreground">Options</span>
      <div className="flex gap-1">
        <Input
          value={draft}
          placeholder="Add an option"
          className="h-7 min-w-0 text-xs"
          onChange={(event) => setDraft(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              addDraft();
            }
          }}
        />
        <Button
          type="button"
          size="icon"
          variant="outline"
          className="h-7 w-7 shrink-0"
          aria-label="Add list option"
          disabled={!draft.trim()}
          onClick={addDraft}
        >
          <Plus size={13} />
        </Button>
      </div>
      {options.length > 0 && (
        <div className="flex flex-wrap gap-1">
          {options.map((option) => (
            <span
              key={option.toLowerCase()}
              className="inline-flex max-w-full items-center gap-1 rounded-full border bg-muted/50 px-1.5 py-0.5 text-[11px]"
            >
              <span className="truncate">{option}</span>
              <button
                type="button"
                className="shrink-0 opacity-60 hover:opacity-100"
                aria-label={`Delete ${option} option`}
                onClick={() =>
                  onChange(options.filter((candidate) => candidate !== option))
                }
              >
                <X size={10} />
              </button>
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

function DefForm({
  initial,
  submitLabel,
  existingTypePaths,
  allowedTypes,
  onSubmit,
  onDelete,
}: DefFormProps) {
  const availableTypes = PROPERTY_TYPES.filter(
    (option) => !allowedTypes || allowedTypes.includes(option.value),
  );
  const [name, setName] = useState(initial?.name ?? "");
  const [type, setType] = useState<PropertyType>(
    initial?.type ?? availableTypes[0]?.value ?? "text",
  );
  const [relationTypeKey, setRelationTypeKey] = useState(
    initial?.relationTypeKey ?? "",
  );
  const [relationMultiple, setRelationMultiple] = useState(
    initial?.relationMultiple ?? false,
  );
  const [listOptions, setListOptions] = useState(
    normalizeListOptions(initial?.listOptions ?? []),
  );
  const [listMultiple, setListMultiple] = useState(
    initial?.listMultiple ?? false,
  );
  const clean = sanitizePropertyName(name);
  const canSubmit = Boolean(
    clean &&
      !isReservedZerusProperty(clean) &&
      (type !== "list" || listOptions.length > 0),
  );

  return (
    <form
      className="space-y-2"
      onSubmit={(e) => {
        e.preventDefault();
        if (!canSubmit) return;
        onSubmit(
          type === "relation"
            ? {
                name: clean,
                type,
                relationTypeKey: relationTypeKey || undefined,
                relationMultiple,
              }
            : type === "list"
              ? { name: clean, type, listOptions, listMultiple }
              : { name: clean, type },
        );
      }}
    >
      <Input
        autoFocus
        value={name}
        placeholder="Property name"
        className="h-7 text-xs"
        onChange={(e) => setName(e.target.value)}
      />
      {availableTypes.length > 1 && (
        <select
          value={type}
          onChange={(e) => setType(e.target.value as PropertyType)}
          className="h-7 w-full rounded-md border border-input bg-background px-2 text-xs text-foreground"
        >
          {availableTypes.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      )}
      {type === "relation" && (
        <>
          <select
            value={relationTypeKey}
            onChange={(e) => setRelationTypeKey(e.target.value)}
            className="h-7 w-full rounded-md border border-input bg-background px-2 text-xs text-foreground"
          >
            <option value="">Any type</option>
            {existingTypePaths.map((path) => {
              const key = typeKey(path);
              return (
                <option key={key} value={key}>
                  {"  ".repeat(path.length - 1)}
                  {path[path.length - 1]}
                </option>
              );
            })}
          </select>
          <label className="flex items-center gap-1.5 px-0.5 text-xs text-muted-foreground">
            <Checkbox
              checked={relationMultiple}
              onCheckedChange={(checked) =>
                setRelationMultiple(checked === true)
              }
            />
            Allow multiple notes
          </label>
        </>
      )}
      {type === "list" && (
        <>
          <ListOptionsField options={listOptions} onChange={setListOptions} />
          <label className="flex items-center justify-between gap-3 px-0.5 text-xs text-muted-foreground">
            <span>Allow multiple options</span>
            <Switch
              checked={listMultiple}
              onCheckedChange={setListMultiple}
              aria-label="Allow multiple list options"
            />
          </label>
          {listOptions.length === 0 && (
            <p className="text-[11px] text-muted-foreground">
              Add at least one option to continue.
            </p>
          )}
        </>
      )}
      <div className="flex items-center gap-2">
        <Button
          type="submit"
          size="sm"
          className="h-7 text-xs"
          disabled={!canSubmit}
        >
          {submitLabel}
        </Button>
        {onDelete && (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="h-7 text-xs text-destructive hover:text-destructive"
            onClick={onDelete}
          >
            Delete
          </Button>
        )}
      </div>
    </form>
  );
}

// ---- the section ----------------------------------------------------------------

interface PropertiesSectionProps {
  note: Note;
  allNotes: Note[];
  onOpenNote: (id: string) => void;
  expanded?: boolean;
}

export function PropertiesSection({
  note,
  allNotes,
  onOpenNote,
  expanded,
}: PropertiesSectionProps) {
  const nameColumnClass = expanded ? "w-48" : "w-28";
  const { schemas, extraTypes } = useVault();
  const [addOpen, setAddOpen] = useState(false);
  const [addOwnerKey, setAddOwnerKey] = useState("");
  const [editing, setEditing] = useState<string | null>(null);

  const typePath = noteTypePath(note);
  const ownKey = typeKey(typePath);
  const currentKey = schemaKeyFor(typePath);
  const currentLabel = currentKey || "unfiled";
  const availableOwnerKeys = typePath.length
    ? typePath.map((_, index) => typePath.slice(0, index + 1).join("/"))
    : [""];
  const selectedAddOwnerKey = availableOwnerKeys.includes(addOwnerKey)
    ? addOwnerKey
    : currentKey;
  const selectedAddOwnerLabel = selectedAddOwnerKey || "unfiled";
  const effectiveEntries = effectivePropertyDefinitions(
    typePath,
    schemas,
  ).filter(({ def }) => !isReservedZerusProperty(def.name));
  const effective = effectiveEntries.map(({ def }) => def);
  const propertyEntries = effectiveEntries.filter(
    ({ def }) => def.type !== "relation",
  );
  const values = getNoteProperties(note.content);
  const existingTypePaths = getAllTypePaths(allNotes, extraTypes);

  // frontmatter keys not covered by the type's definitions (ad-hoc properties)
  const covered = new Set(effective.map((def) => def.name.toLowerCase()));
  const extras = Object.entries(values).filter(
    ([key]) =>
      !covered.has(key.toLowerCase()) &&
      !FILE_HUB_PROPERTY_KEYS.has(key.toLowerCase()) &&
      !isReservedZerusProperty(key),
  );

  const valueFor = (name: string): PropertyValue | undefined => {
    const match = Object.keys(values).find(
      (key) => key.toLowerCase() === name.toLowerCase(),
    );
    return match === undefined ? undefined : values[match];
  };

  return (
    <div className="border-b border-border/60">
      <div className="flex items-center gap-1.5 border-b border-border/60 px-4 py-3 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
        <SlidersHorizontal size={13} />
        Properties
        <span className="normal-case font-normal tracking-normal">
          · {ownKey || "unfiled"}
        </span>
      </div>
      <div className="space-y-0.5 px-3 py-2.5">
        {propertyEntries.length === 0 && extras.length === 0 && (
          <p className="px-1 pb-1 text-xs text-muted-foreground">
            Properties added here apply to every{" "}
            <span className="font-medium">{currentLabel}</span> note, including
            sub-types.
          </p>
        )}
        {propertyEntries.map(({ def, ownerKey }) => {
          const Icon = TYPE_ICONS[def.type];
          const ownerLabel = ownerKey || "unfiled";
          return (
            <div
              key={`${ownerKey}:${def.name}`}
              className="flex items-start gap-1"
            >
              <Popover
                open={editing === `def:${def.name}`}
                onOpenChange={(open) =>
                  setEditing(open ? `def:${def.name}` : null)
                }
              >
                <PopoverTrigger asChild>
                  <button
                    className={`flex ${nameColumnClass} shrink-0 items-center gap-1.5 rounded px-1 py-1 text-left text-xs text-muted-foreground hover:bg-muted/60 hover:text-foreground`}
                    title={`Defined on "${ownerLabel}" — applies to it and all its sub-types`}
                  >
                    <Icon size={12} className="shrink-0 opacity-70" />
                    <span className="truncate">{def.name}</span>
                  </button>
                </PopoverTrigger>
                <PopoverContent className="w-56 p-3" align="start">
                  <p className="mb-2 text-xs text-muted-foreground">
                    Edits apply to all{" "}
                    <span className="font-medium">{ownerLabel}</span> notes.
                  </p>
                  <DefForm
                    initial={def}
                    submitLabel="Save"
                    existingTypePaths={existingTypePaths}
                    allowedTypes={PROPERTY_DEFINITION_TYPES}
                    onSubmit={(next) => {
                      updateTypeProperty(ownerKey, def.name, next);
                      setEditing(null);
                    }}
                    onDelete={() => {
                      removeTypeProperty(ownerKey, def.name);
                      setEditing(null);
                    }}
                  />
                </PopoverContent>
              </Popover>
              <div className="min-w-0 flex-1">
                <ValueEditor
                  def={def}
                  value={valueFor(def.name)}
                  allNotes={allNotes}
                  currentNote={note}
                  schemas={schemas}
                  onOpenNote={onOpenNote}
                  onCommit={(value) =>
                    setNoteProperty(note.id, def.name, value)
                  }
                />
              </div>
            </div>
          );
        })}
        {extras.map(([key, value]) => {
          const inferredType = inferPropertyType(value);
          const Icon = TYPE_ICONS[inferredType];
          return (
            <div key={key} className="flex items-start gap-1">
              <Popover
                open={editing === `extra:${key}`}
                onOpenChange={(open) =>
                  setEditing(open ? `extra:${key}` : null)
                }
              >
                <PopoverTrigger asChild>
                  <button
                    className={`flex ${nameColumnClass} shrink-0 items-center gap-1.5 rounded px-1 py-1 text-left text-xs italic text-muted-foreground hover:bg-muted/60 hover:text-foreground`}
                    title="Only on this note — not part of the type"
                  >
                    <Icon size={12} className="shrink-0 opacity-70" />
                    <span className="truncate">{key}</span>
                  </button>
                </PopoverTrigger>
                <PopoverContent className="w-56 space-y-1.5 p-3" align="start">
                  <p className="text-xs text-muted-foreground">
                    Only on this note.
                  </p>
                  <Button
                    size="sm"
                    variant="outline"
                    className="h-7 w-full justify-start text-xs"
                    onClick={() => {
                      const name = sanitizePropertyName(key);
                      if (name) {
                        addTypeProperty(
                          currentKey,
                          inferredType === "list"
                            ? {
                                name,
                                type: inferredType,
                                listOptions: listSelections(value),
                                listMultiple:
                                  Array.isArray(value) && value.length > 1,
                              }
                            : { name, type: inferredType },
                        );
                      }
                      setEditing(null);
                    }}
                  >
                    <Plus size={12} className="mr-1.5" />
                    Add to “{currentLabel}”
                  </Button>
                  <Button
                    size="sm"
                    variant="ghost"
                    className="h-7 w-full justify-start text-xs text-destructive hover:text-destructive"
                    onClick={() => {
                      setNoteProperty(note.id, key, null);
                      setEditing(null);
                    }}
                  >
                    Remove from note
                  </Button>
                </PopoverContent>
              </Popover>
              <div className="min-w-0 flex-1">
                <ValueEditor
                  def={{ name: key, type: inferredType }}
                  value={value}
                  allNotes={allNotes}
                  currentNote={note}
                  schemas={schemas}
                  onOpenNote={onOpenNote}
                  onCommit={(next) => setNoteProperty(note.id, key, next)}
                />
              </div>
            </div>
          );
        })}
        <Popover
          open={addOpen}
          onOpenChange={(open) => {
            setAddOpen(open);
            if (open) setAddOwnerKey(currentKey);
          }}
        >
          <PopoverTrigger asChild>
            <Button
              variant="ghost"
              size="sm"
              className="h-6 gap-1 px-1 text-xs text-muted-foreground hover:text-foreground"
            >
              <Plus size={12} />
              Add property
            </Button>
          </PopoverTrigger>
          <PopoverContent className="w-56 p-3" align="start">
            <p className="mb-2 text-xs text-muted-foreground">
              Added to every{" "}
              <span className="font-medium">{selectedAddOwnerLabel}</span> note,
              including sub-types.
            </p>
            {availableOwnerKeys.length > 1 && (
              <label className="mb-2 block text-xs text-muted-foreground">
                Apply to
                <select
                  value={selectedAddOwnerKey}
                  onChange={(event) => setAddOwnerKey(event.target.value)}
                  className="mt-1 h-7 w-full rounded-md border border-input bg-background px-2 text-xs text-foreground"
                >
                  {[...availableOwnerKeys].reverse().map((ownerKey) => (
                    <option key={ownerKey} value={ownerKey}>
                      {ownerKey}
                    </option>
                  ))}
                </select>
              </label>
            )}
            <DefForm
              submitLabel="Add"
              existingTypePaths={existingTypePaths}
              allowedTypes={PROPERTY_DEFINITION_TYPES}
              onSubmit={(def) => {
                addTypeProperty(selectedAddOwnerKey, def);
                setAddOpen(false);
              }}
            />
          </PopoverContent>
        </Popover>
      </div>
    </div>
  );
}

export function RelationsSection({
  note,
  allNotes,
  onOpenNote,
  expanded,
}: PropertiesSectionProps) {
  const { schemas, extraTypes } = useVault();
  const [addOpen, setAddOpen] = useState(false);
  const [addOwnerKey, setAddOwnerKey] = useState("");
  const [editing, setEditing] = useState<string | null>(null);

  const typePath = noteTypePath(note);
  const currentKey = schemaKeyFor(typePath);
  const availableOwnerKeys = typePath.length
    ? typePath.map((_, index) => typePath.slice(0, index + 1).join("/"))
    : [""];
  const selectedAddOwnerKey = availableOwnerKeys.includes(addOwnerKey)
    ? addOwnerKey
    : currentKey;
  const selectedAddOwnerLabel = selectedAddOwnerKey || "unfiled";
  const relationEntries = effectivePropertyDefinitions(typePath, schemas).filter(
    ({ def }) => def.type === "relation" && !isReservedZerusProperty(def.name),
  );
  const values = getNoteProperties(note.content);
  const existingTypePaths = getAllTypePaths(allNotes, extraTypes);
  const valueFor = (name: string): PropertyValue | undefined => {
    const match = Object.keys(values).find(
      (key) => key.toLowerCase() === name.toLowerCase(),
    );
    return match === undefined ? undefined : values[match];
  };

  return (
    <div className="space-y-4">
        {relationEntries.map(({ def, ownerKey }) => {
          const ownerLabel = ownerKey || "unfiled";
          const rawValue = valueFor(def.name);
          const relationCount = Array.isArray(rawValue)
            ? rawValue.length
            : rawValue == null || rawValue === ""
              ? 0
              : 1;
          return (
            <div key={`${ownerKey}:${def.name}`}>
              <Popover
                open={editing === `def:${def.name}`}
                onOpenChange={(open) =>
                  setEditing(open ? `def:${def.name}` : null)
                }
              >
                <PopoverTrigger asChild>
                  <button
                    className="mb-1.5 flex items-center gap-1 rounded text-left text-xs font-medium text-zerus-accent hover:underline"
                    title={`Defined on "${ownerLabel}" — applies to it and all its sub-types`}
                  >
                    <ArrowRight size={12} className="shrink-0" />
                    <span className="truncate">{def.name}</span>
                    {relationCount > 0 && (
                      <span className="text-muted-foreground">
                        · {relationCount}
                      </span>
                    )}
                  </button>
                </PopoverTrigger>
                <PopoverContent className="w-56 p-3" align="start">
                  <p className="mb-2 text-xs text-muted-foreground">
                    Edits apply to all{" "}
                    <span className="font-medium">{ownerLabel}</span> notes.
                  </p>
                  <DefForm
                    initial={def}
                    submitLabel="Save"
                    existingTypePaths={existingTypePaths}
                    allowedTypes={["relation"]}
                    onSubmit={(next) => {
                      updateTypeProperty(ownerKey, def.name, next);
                      setEditing(null);
                    }}
                    onDelete={() => {
                      removeTypeProperty(ownerKey, def.name);
                      setEditing(null);
                    }}
                  />
                </PopoverContent>
              </Popover>
              <RelationValueEditor
                def={def}
                value={rawValue}
                allNotes={allNotes}
                currentNote={note}
                schemas={schemas}
                onOpenNote={onOpenNote}
                onCommit={(value) => setNoteProperty(note.id, def.name, value)}
                expanded={expanded}
              />
            </div>
          );
        })}
        <Popover
          open={addOpen}
          onOpenChange={(open) => {
            setAddOpen(open);
            if (open) setAddOwnerKey(currentKey);
          }}
        >
          <PopoverTrigger asChild>
            <Button
              variant="ghost"
              size="sm"
              className="h-6 gap-1 px-1 text-xs text-muted-foreground hover:text-foreground"
            >
              <Plus size={12} />
              Add relation
            </Button>
          </PopoverTrigger>
          <PopoverContent className="w-56 p-3" align="start">
            <p className="mb-2 text-xs text-muted-foreground">
              Added to every{" "}
              <span className="font-medium">{selectedAddOwnerLabel}</span> note,
              including sub-types.
            </p>
            {availableOwnerKeys.length > 1 && (
              <label className="mb-2 block text-xs text-muted-foreground">
                Apply to
                <select
                  value={selectedAddOwnerKey}
                  onChange={(event) => setAddOwnerKey(event.target.value)}
                  className="mt-1 h-7 w-full rounded-md border border-input bg-background px-2 text-xs text-foreground"
                >
                  {[...availableOwnerKeys].reverse().map((ownerKey) => (
                    <option key={ownerKey} value={ownerKey}>
                      {ownerKey || "unfiled"}
                    </option>
                  ))}
                </select>
              </label>
            )}
            <DefForm
              submitLabel="Add"
              existingTypePaths={existingTypePaths}
              allowedTypes={["relation"]}
              onSubmit={(def) => {
                addTypeProperty(selectedAddOwnerKey, def);
                setAddOpen(false);
              }}
            />
          </PopoverContent>
        </Popover>
    </div>
  );
}
