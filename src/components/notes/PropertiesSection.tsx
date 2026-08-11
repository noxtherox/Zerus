import { useState } from "react";
import {
  ArrowLeftRight,
  Calendar,
  CheckSquare,
  ExternalLink,
  Hash,
  Link,
  List,
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
import { type PropertyValue, getNoteProperties } from "@/lib/frontmatter";
import {
  PROPERTY_TYPES,
  type PropertyDef,
  type PropertySchemas,
  type PropertyType,
  effectivePropertyDefinitions,
  inferPropertyType,
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
  typeKey,
} from "@/lib/note-utils";
import {
  addTypeProperty,
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

function ListValueEditor({
  def,
  value,
  onCommit,
}: {
  def: PropertyDef;
  value: PropertyValue | undefined;
  onCommit: (value: PropertyValue | null) => void;
}) {
  const [open, setOpen] = useState(false);
  const selected = listSelections(value);
  const selectedKeys = new Set(selected.map((item) => item.toLowerCase()));
  const options = normalizeListOptions(def.listOptions ?? []);
  const available = options.filter(
    (option) => !selectedKeys.has(option.toLowerCase()),
  );
  const multiple = def.listMultiple === true;

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
  };

  const showPicker = multiple || selected.length === 0;

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
        <Popover open={open} onOpenChange={setOpen}>
          <PopoverTrigger asChild>
            <button
              type="button"
              className="flex h-5 items-center gap-0.5 rounded-full px-1.5 text-[11px] text-muted-foreground hover:bg-muted/60 hover:text-foreground"
            >
              <Plus size={10} />
              {selected.length ? "Add" : "Select"}
            </button>
          </PopoverTrigger>
          <PopoverContent className="w-56 p-0" align="start">
            <Command>
              <CommandInput placeholder="Search options…" />
              <CommandList>
                <CommandEmpty>
                  {options.length
                    ? "No matching options."
                    : "No options configured."}
                </CommandEmpty>
                <CommandGroup>
                  {available.map((option) => (
                    <CommandItem
                      key={option.toLowerCase()}
                      value={option}
                      onSelect={() => pick(option)}
                    >
                      {option}
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
          className="flex min-w-0 items-center gap-1 text-left text-grim-link hover:underline"
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
  onOpenNote,
  onRemove,
}: {
  title: string;
  note: Note | undefined;
  reciprocal: boolean;
  onOpenNote: (id: string) => void;
  onRemove: () => void;
}) {
  return (
    <span
      className={cn(
        "inline-flex max-w-full items-center gap-1 rounded-full border px-1.5 py-0.5 text-xs",
        note
          ? "border-grim-link/30 text-grim-link hover:bg-grim-link/10"
          : "border-dashed border-muted-foreground/40 text-muted-foreground",
      )}
    >
      {note ? (
        <button
          type="button"
          className="truncate"
          title={`Open "${title}"`}
          onClick={() => onOpenNote(note.id)}
        >
          {title}
        </button>
      ) : (
        <span className="truncate italic" title="No note matches this title">
          {title}
        </span>
      )}
      {reciprocal && (
        <ArrowLeftRight
          size={10}
          className="shrink-0 opacity-70"
          aria-label="Linked both ways"
          title="Linked both ways"
        />
      )}
      <button
        type="button"
        className="shrink-0 opacity-60 hover:opacity-100"
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
}: {
  def: PropertyDef;
  value: PropertyValue | undefined;
  allNotes: Note[];
  currentNote: Note;
  schemas: PropertySchemas;
  onOpenNote: (id: string) => void;
  onCommit: (value: PropertyValue | null) => void;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");

  const titles = Array.isArray(value)
    ? value
    : value === undefined || value === null || value === ""
      ? []
      : [String(value)];
  const selectedLower = new Set(titles.map((title) => title.toLowerCase()));

  const candidates = (
    def.relationTypeKey
      ? notesOfTypeKey(allNotes, def.relationTypeKey)
      : allNotes.filter((note) => !isExternalNote(note) && !isTrashed(note))
  ).filter(
    (note) =>
      note.id !== currentNote.id &&
      !selectedLower.has(noteTitle(note).toLowerCase()),
  );

  const pick = (note: Note) => {
    const title = noteTitle(note);
    onCommit(def.relationMultiple ? [...titles, title] : title);
    setQuery("");
    setOpen(false);
  };

  const remove = (title: string) => {
    const next = titles.filter((t) => t.toLowerCase() !== title.toLowerCase());
    onCommit(next.length ? next : null);
  };

  const showAdd = def.relationMultiple || titles.length === 0;

  return (
    <div className="flex flex-wrap items-center gap-1 px-0.5 py-0.5">
      {titles.map((title) => {
        const linkedNote = findNoteByTitle(title, allNotes);
        return (
          <RelationChip
            key={title}
            title={title}
            note={linkedNote}
            reciprocal={
              linkedNote ? hasRelationTo(linkedNote, currentNote, schemas) : false
            }
            onOpenNote={onOpenNote}
            onRemove={() => remove(title)}
          />
        );
      })}
      {showAdd && (
        <Popover open={open} onOpenChange={setOpen}>
          <PopoverTrigger asChild>
            <button
              type="button"
              className="flex h-5 items-center gap-0.5 rounded-full px-1.5 text-[11px] text-muted-foreground hover:bg-muted/60 hover:text-foreground"
            >
              <Plus size={10} />
              Link
            </button>
          </PopoverTrigger>
          <PopoverContent className="w-64 p-0" align="start">
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
            </Command>
          </PopoverContent>
        </Popover>
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
  onSubmit: (def: PropertyDef) => void;
  onDelete?: () => void;
}

function ListOptionsField({
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
  onSubmit,
  onDelete,
}: DefFormProps) {
  const [name, setName] = useState(initial?.name ?? "");
  const [type, setType] = useState<PropertyType>(initial?.type ?? "text");
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
      <select
        value={type}
        onChange={(e) => setType(e.target.value as PropertyType)}
        className="h-7 w-full rounded-md border border-input bg-background px-2 text-xs text-foreground"
      >
        {PROPERTY_TYPES.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
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
        {effective.length === 0 && extras.length === 0 && (
          <p className="px-1 pb-1 text-xs text-muted-foreground">
            Properties added here apply to every{" "}
            <span className="font-medium">{currentLabel}</span> note, including
            sub-types.
          </p>
        )}
        {effectiveEntries.map(({ def, ownerKey }) => {
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
