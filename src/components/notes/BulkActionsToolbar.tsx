import { useEffect, useMemo, useRef, useState } from "react";
import {
  Archive,
  ArchiveRestore,
  CheckSquare,
  ChevronDown,
  FolderInput,
  History,
  Link,
  Loader2,
  Pin,
  RotateCcw,
  SlidersHorizontal,
  Undo2,
  X,
} from "@/lib/icons";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  executeBulkAction,
  mutationSummary,
  previewBulkAction,
  transitionBulkAction,
  useBulkActionHistory,
  type BulkActionProgress,
  type BulkActionPreview,
  type BulkActionResult,
  type BulkNoteMutation,
  type BulkPropertyChange,
  type BulkPropertyOperation,
} from "@/lib/bulk-note-actions";
import { getNoteProperties, type PropertyValue } from "@/lib/frontmatter";
import {
  effectiveProperties,
  normalizeListOptions,
  type PropertyDef,
  type PropertySchemas,
} from "@/lib/properties";
import { noteReferenceLabel, noteTitle, noteTypePath, type Note } from "@/lib/note-utils";
import { cn } from "@/lib/utils";
import { useVaultSelector } from "@/store/notes-store";
import { ListValueEditor, RelationValueEditor } from "@/components/notes/PropertiesSection";

export interface BulkMutationRequest {
  id: number;
  noteIds: string[];
  mutation?: BulkNoteMutation;
  openProperties?: boolean;
}

interface BulkActionsToolbarProps {
  notes: Note[];
  selectedIds: ReadonlySet<string>;
  schemas: PropertySchemas;
  vaultLocation: string | null;
  onClear: () => void;
  onSelectAll: () => void;
  onRemoveSelected: (ids: Iterable<string>) => void;
  onMoveNotes?: (ids: string[]) => void;
  externalRequest?: BulkMutationRequest | null;
  onExternalRequestHandled?: () => void;
  className?: string;
  presentation?: "standalone" | "inline";
}

interface PendingAction {
  noteIds: string[];
  mutation: BulkNoteMutation;
  preview: BulkActionPreview;
  titles: Record<string, string>;
}

function noteTitleSnapshot(noteIds: string[], notes: Note[]): Record<string, string> {
  const titles = new Map(notes.map((note) => [note.id, noteTitle(note)]));
  return Object.fromEntries(noteIds.map((id) => [id, titles.get(id) ?? "Missing note"]));
}

function sameDefinition(left: PropertyDef, right: PropertyDef): boolean {
  return left.type === right.type &&
    left.listMultiple === right.listMultiple &&
    left.relationMultiple === right.relationMultiple &&
    (left.type !== "relation" || left.relationTypeKey === right.relationTypeKey);
}

function commonProperties(notes: Note[], schemas: PropertySchemas): PropertyDef[] {
  if (!notes.length) return [];
  const first = effectiveProperties(noteTypePath(notes[0]), schemas).filter(
    (property) => !property.relationHidden,
  );
  return first.flatMap((candidate) => {
    const matches = notes.slice(1).map((note) =>
      effectiveProperties(noteTypePath(note), schemas).find(
        (property) => property.name.toLowerCase() === candidate.name.toLowerCase(),
      ),
    );
    if (matches.some((match) => !match || match.relationHidden || !sameDefinition(candidate, match))) return [];
    if (candidate.type !== "list") return [candidate];

    const definitions = [candidate, ...matches] as PropertyDef[];
    const listOptions = normalizeListOptions(candidate.listOptions ?? []).filter((option) =>
      definitions.slice(1).every((definition) =>
        normalizeListOptions(definition.listOptions ?? []).some(
          (available) => available.toLowerCase() === option.toLowerCase(),
        ),
      ),
    );
    return [{ ...candidate, listOptions }];
  });
}

function propertyValue(note: Note, name: string): PropertyValue | undefined {
  const properties = getNoteProperties(note.content);
  const key = Object.keys(properties).find(
    (candidate) => candidate.toLowerCase() === name.toLowerCase(),
  );
  return key ? properties[key] : undefined;
}

function propertyStateLabel(notes: Note[], definition: PropertyDef, allNotes: Note[]): string {
  const { name } = definition;
  const values = notes.map((note) => propertyValue(note, name));
  const serialized = values.map((value) => JSON.stringify(value));
  if (serialized.some((value) => value !== serialized[0])) return "Mixed";
  const value = values[0];
  if (value === undefined || value === "" || (Array.isArray(value) && !value.length)) return "Empty";
  if (definition.type === "relation") {
    return (Array.isArray(value) ? value : [String(value)]).map((reference) => noteReferenceLabel(reference, allNotes)).join(", ");
  }
  return Array.isArray(value) ? value.join(", ") : String(value);
}

function valueForDefinition(definition: PropertyDef, raw: string): PropertyValue {
  if (definition.type === "checkbox") return raw === "true";
  if (definition.type === "number") return Number(raw);
  return raw;
}

function PropertyChangeComposer({
  notes,
  allNotes,
  properties,
  kind,
  changes,
  onChanges,
}: {
  notes: Note[];
  allNotes: Note[];
  properties: PropertyDef[];
  kind: "property" | "relation";
  changes: BulkPropertyChange[];
  onChanges: (changes: BulkPropertyChange[]) => void;
}) {
  const isRelations = kind === "relation";
  const sectionChanges = changes.filter((change) =>
    properties.some((property) => property.name.toLowerCase() === change.name.toLowerCase()),
  );
  const [propertyName, setPropertyName] = useState(properties[0]?.name ?? "");
  const definition = properties.find((property) => property.name === propertyName);
  const supportsListOperations = definition && (
    (definition.type === "list" && definition.listMultiple) ||
    (definition.type === "relation" && definition.relationMultiple)
  );
  const [operation, setOperation] = useState<BulkPropertyOperation>("set");
  const [rawValue, setRawValue] = useState("");
  const [selectedValues, setSelectedValues] = useState<string[]>([]);

  const excludedNoteIds = useMemo(() => new Set(notes.map((note) => note.id)), [notes]);
  const usesPicker = definition?.type === "list" || definition?.type === "relation";

  const addChange = () => {
    if (!definition) return;
    const value = usesPicker
      ? (definition.type === "list" ? definition.listMultiple : definition.relationMultiple)
        ? selectedValues
        : selectedValues[0] ?? ""
      : valueForDefinition(definition, rawValue);
    const change: BulkPropertyChange = {
      name: definition.name,
      operation,
      ...(operation === "clear" ? {} : { value }),
    };
    onChanges([
      ...changes.filter((candidate) => candidate.name.toLowerCase() !== definition.name.toLowerCase()),
      change,
    ]);
    setRawValue("");
    setSelectedValues([]);
  };

  if (!properties.length) {
    return <p className="rounded-md border border-dashed p-4 text-sm text-muted-foreground">{isRelations ? "The selected notes do not share any editable relations." : "The selected notes do not share any editable properties."}</p>;
  }

  return (
    <div className="space-y-4">
      <div className="grid gap-2 rounded-md border border-border/70 p-3 sm:grid-cols-[1fr_130px]">
        <Select value={propertyName} onValueChange={(value) => {
          setPropertyName(value);
          setOperation("set");
          setRawValue("");
          setSelectedValues([]);
        }}>
          <SelectTrigger aria-label={isRelations ? "Relation" : "Property"}><SelectValue placeholder={isRelations ? "Choose a relation" : "Choose a property"} /></SelectTrigger>
          <SelectContent>
            {properties.map((property) => (
              <SelectItem key={property.name} value={property.name}>
                {property.name} · {propertyStateLabel(notes, property, allNotes)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select value={operation} onValueChange={(value) => {
          setOperation(value as BulkPropertyOperation);
          setRawValue("");
          setSelectedValues([]);
        }}>
          <SelectTrigger aria-label={isRelations ? "Relation operation" : "Property operation"}><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="set">Set</SelectItem>
            <SelectItem value="clear">Clear</SelectItem>
            {supportsListOperations && <SelectItem value="add">Add</SelectItem>}
            {supportsListOperations && <SelectItem value="remove">Remove</SelectItem>}
          </SelectContent>
        </Select>
        {operation !== "clear" && definition?.type === "list" ? (
          <div className="min-h-10 rounded-md border border-input bg-background px-2 py-1.5 sm:col-span-2">
            <ListValueEditor
              def={definition}
              value={selectedValues}
              onCommit={(value) => {
                if (Array.isArray(value)) setSelectedValues(value);
                else setSelectedValues(value === null ? [] : [String(value)]);
              }}
              emptyPickerLabel="Select options"
              selectedPickerLabel="Add another"
              searchPlaceholder="Search available options…"
            />
          </div>
        ) : operation !== "clear" && definition?.type === "relation" && notes[0] ? (
          <div className="min-h-10 rounded-md border border-input bg-background px-2 py-1.5 sm:col-span-2">
            <RelationValueEditor
              key={`${definition.name}:${operation}`}
              def={definition}
              value={selectedValues}
              allNotes={allNotes}
              currentNote={notes[0]}
              excludedNoteIds={operation === "remove" ? undefined : excludedNoteIds}
              inlinePicker
              showArchived={operation === "remove"}
              onCommit={(value) => setSelectedValues(Array.isArray(value) ? value : value == null || value === "" ? [] : [String(value)])}
            />
          </div>
        ) : operation !== "clear" && definition?.type === "checkbox" ? (
          <Select value={rawValue || "false"} onValueChange={setRawValue}>
            <SelectTrigger className="sm:col-span-2"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="true">Checked</SelectItem>
              <SelectItem value="false">Unchecked</SelectItem>
            </SelectContent>
          </Select>
        ) : operation !== "clear" ? (
          <Input
            className="sm:col-span-2"
            type={definition?.type === "number" ? "number" : definition?.type === "date" ? "date" : "text"}
            value={rawValue}
            onChange={(event) => setRawValue(event.target.value)}
            placeholder="New value"
          />
        ) : null}
        <Button
          type="button"
          variant="secondary"
          className="sm:col-span-2"
          disabled={operation !== "clear" && usesPicker && selectedValues.length === 0}
          onClick={addChange}
        >
          {isRelations ? "Add relation change" : "Add property change"}
        </Button>
      </div>
      {sectionChanges.length > 0 && (
        <div className="space-y-2">
          {sectionChanges.map((change) => (
            <div key={change.name} className="flex items-center gap-2 rounded-md bg-muted/60 px-3 py-2 text-sm">
              <span className="min-w-0 flex-1 truncate">{mutationSummary({ properties: [change] })[0]}</span>
              <Button type="button" variant="ghost" size="icon" className="h-7 w-7" aria-label={`Remove ${change.name} change`} onClick={() => onChanges(changes.filter((candidate) => candidate !== change))}>
                <X size={14} />
              </Button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export function BulkActionsToolbar({
  notes,
  selectedIds,
  schemas,
  vaultLocation,
  onClear,
  onSelectAll,
  onRemoveSelected,
  onMoveNotes,
  externalRequest,
  onExternalRequestHandled,
  className,
  presentation = "standalone",
}: BulkActionsToolbarProps) {
  const allNotes = useVaultSelector((state) => state.notes);
  const [propertyNoteIds, setPropertyNoteIds] = useState<string[]>([]);
  const propertyNotes = useMemo(
    () => notes.filter((note) => propertyNoteIds.includes(note.id)),
    [notes, propertyNoteIds],
  );
  const properties = useMemo(
    () => commonProperties(propertyNotes, schemas),
    [schemas, propertyNotes],
  );
  const history = useBulkActionHistory(vaultLocation);
  const [propertyDialogOpen, setPropertyDialogOpen] = useState(false);
  const [propertyChanges, setPropertyChanges] = useState<BulkPropertyChange[]>([]);
  const [pending, setPending] = useState<PendingAction | null>(null);
  const [progress, setProgress] = useState<BulkActionProgress | null>(null);
  const [lastResult, setLastResult] = useState<BulkActionResult | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const abortRef = useRef<AbortController | null>(null);
  const consumedRequest = useRef<number | null>(null);

  useEffect(() => {
    if (externalRequest && consumedRequest.current !== externalRequest.id) {
      consumedRequest.current = externalRequest.id;
      if (externalRequest.openProperties) {
        setPropertyNoteIds(externalRequest.noteIds);
        setPropertyChanges([]);
        setPropertyDialogOpen(true);
      } else if (externalRequest.mutation) {
        setPending({
          noteIds: externalRequest.noteIds,
          mutation: externalRequest.mutation,
          preview: previewBulkAction(externalRequest.noteIds, externalRequest.mutation),
          titles: noteTitleSnapshot(externalRequest.noteIds, notes),
        });
      }
      onExternalRequestHandled?.();
    }
  }, [externalRequest, notes, onExternalRequestHandled]);

  const prepare = (mutation: BulkNoteMutation, noteIds = [...selectedIds]) => {
    setLastResult(null);
    setPending({
      noteIds,
      mutation,
      preview: previewBulkAction(noteIds, mutation),
      titles: noteTitleSnapshot(noteIds, notes),
    });
  };
  const preview = pending?.preview ?? null;

  const apply = async () => {
    if (!pending || !vaultLocation) return;
    const controller = new AbortController();
    abortRef.current = controller;
    setProgress({ completed: 0, total: pending.noteIds.length, currentTitle: "" });
    const result = await executeBulkAction({
      location: vaultLocation,
      noteIds: pending.noteIds,
      mutation: pending.mutation,
      signal: controller.signal,
      onProgress: setProgress,
    });
    abortRef.current = null;
    setProgress(null);
    setLastResult(result);
    onRemoveSelected(result.successfulIds);
  };

  const closeConfirmation = () => {
    if (progress) return;
    setPending(null);
    setLastResult(null);
  };

  return (
    <>
      <div
        className={cn(
          "flex items-center gap-1.5",
          presentation === "standalone"
            ? "sticky top-0 z-20 min-h-11 border-b border-zerus-accent/20 bg-zerus-surface/95 px-3 py-1.5 shadow-sm backdrop-blur"
            : "min-w-0 shrink-0",
          className,
        )}
      >
        <strong className={cn("min-w-0 truncate text-xs", presentation === "standalone" && "flex-1")}>
          {selectedIds.size} selected
        </strong>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="outline"
              size="sm"
              className="h-7 shrink-0 gap-1 border-zerus-accent/35 bg-zerus-accent/10 px-2.5 text-xs text-zerus-accent hover:bg-zerus-accent/15 hover:text-zerus-accent"
            >
              Actions <ChevronDown size={13} />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-48">
            {selectedIds.size < notes.length && (
              <>
                <DropdownMenuItem onSelect={onSelectAll}>
                  <CheckSquare size={14} className="mr-2" /> Select all {notes.length}
                </DropdownMenuItem>
                <DropdownMenuSeparator />
              </>
            )}
            {onMoveNotes && (
              <DropdownMenuItem disabled={!selectedIds.size} onSelect={() => onMoveNotes([...selectedIds])}>
                <FolderInput size={14} className="mr-2" /> Move to folder…
              </DropdownMenuItem>
            )}
            <DropdownMenuItem disabled={!selectedIds.size} onSelect={() => prepare({ archived: true })}>
              <Archive size={14} className="mr-2" /> Archive
            </DropdownMenuItem>
            <DropdownMenuItem disabled={!selectedIds.size} onSelect={() => prepare({ archived: false })}>
              <ArchiveRestore size={14} className="mr-2" /> Unarchive
            </DropdownMenuItem>
            <DropdownMenuItem disabled={!selectedIds.size} onSelect={() => prepare({ pinned: true })}>
              <Pin size={14} className="mr-2" /> Pin
            </DropdownMenuItem>
            <DropdownMenuItem disabled={!selectedIds.size} onSelect={() => prepare({ pinned: false })}>
              <Pin size={14} className="mr-2 rotate-45" /> Unpin
            </DropdownMenuItem>
            <DropdownMenuItem disabled={!selectedIds.size} onSelect={() => {
              setPropertyNoteIds([...selectedIds]);
              setPropertyChanges([]);
              setPropertyDialogOpen(true);
            }}>
              <SlidersHorizontal size={14} className="mr-2" /> Properties and relations
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={() => setHistoryOpen(true)}>
              <History size={14} className="mr-2" /> Recent actions
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
        <Button variant="ghost" size="icon" className="h-7 w-7" aria-label="Clear selection" title="Clear selection" onClick={onClear}><X size={15} /></Button>
      </div>

      <Dialog open={propertyDialogOpen} onOpenChange={setPropertyDialogOpen}>
        <DialogContent className="flex max-h-[85vh] max-w-2xl flex-col overflow-hidden">
          <DialogHeader>
            <DialogTitle>Edit {propertyNoteIds.length} {propertyNoteIds.length === 1 ? "note" : "notes"}</DialogTitle>
            <DialogDescription>Only compatible properties and relations shared by every selected note are available.</DialogDescription>
          </DialogHeader>
          <div className="min-h-0 space-y-4 overflow-y-auto pr-1">
            <section aria-label="Properties" className="space-y-2">
              <h3 className="flex items-center gap-2 text-sm font-semibold">
                <SlidersHorizontal size={15} className="text-muted-foreground" aria-hidden="true" />
                Properties
              </h3>
              <PropertyChangeComposer
                kind="property"
                notes={propertyNotes}
                allNotes={allNotes}
                properties={properties.filter((property) => property.type !== "relation")}
                changes={propertyChanges}
                onChanges={setPropertyChanges}
              />
            </section>
            <section aria-label="Relations" className="space-y-2 border-t border-border/70 pt-4">
              <h3 className="flex items-center gap-2 text-sm font-semibold">
                <Link size={15} className="text-muted-foreground" aria-hidden="true" />
                Relations
              </h3>
              <PropertyChangeComposer
                kind="relation"
                notes={propertyNotes}
                allNotes={allNotes}
                properties={properties.filter((property) => property.type === "relation")}
                changes={propertyChanges}
                onChanges={setPropertyChanges}
              />
            </section>
          </div>
          <DialogFooter className="shrink-0">
            <Button variant="ghost" onClick={() => setPropertyDialogOpen(false)}>Cancel</Button>
            <Button disabled={!propertyChanges.length} onClick={() => {
              setPropertyDialogOpen(false);
              prepare({ properties: propertyChanges }, propertyNoteIds);
            }}>Review changes</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={pending !== null} onOpenChange={(open) => !open && closeConfirmation()}>
        <DialogContent className="max-h-[85vh] max-w-lg overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Confirm bulk action</DialogTitle>
            <DialogDescription>
              {preview?.eligibleIds.length ?? 0} notes will change
              {(preview?.skipped.length ?? 0) > 0 ? `; ${preview?.skipped.length} will be skipped` : ""}.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3 text-sm">
            <ul className="space-y-1 rounded-md bg-muted/60 p-3">
              {(pending ? mutationSummary(pending.mutation) : []).map((line) => <li key={line}>{line}</li>)}
            </ul>
            <details>
              <summary className="cursor-pointer text-xs font-medium text-muted-foreground">Show affected note titles</summary>
              <ul className="mt-2 max-h-44 space-y-1 overflow-y-auto rounded-md border p-2 text-xs">
                {(pending?.noteIds ?? []).map((id) => (
                  <li key={id} className="truncate">{pending?.titles[id] ?? "Missing note"}</li>
                ))}
              </ul>
            </details>
            {(preview?.skipped.length ?? 0) > 0 && (
              <details>
                <summary className="cursor-pointer text-xs font-medium text-amber-700">{preview?.skipped.length} skipped before applying</summary>
                <ul className="mt-2 space-y-1 text-xs text-muted-foreground">
                  {preview?.skipped.map((item) => <li key={item.noteId}>{item.title}: {item.reason}</li>)}
                </ul>
              </details>
            )}
            {progress && (
              <div className="rounded-md border p-3" aria-live="polite">
                <div className="mb-2 flex items-center gap-2"><Loader2 size={15} className="animate-spin" /> {progress.completed} of {progress.total}</div>
                <div className="h-1.5 overflow-hidden rounded-full bg-muted"><div className="h-full bg-zerus-accent transition-all" style={{ width: `${progress.total ? progress.completed / progress.total * 100 : 0}%` }} /></div>
                {progress.currentTitle && <p className="mt-2 truncate text-xs text-muted-foreground">{progress.currentTitle}</p>}
              </div>
            )}
            {lastResult && (
              <div className="rounded-md border p-3 text-xs">
                <strong>{lastResult.successfulIds.length} changed</strong>
                {lastResult.failed.length > 0 && <span>; {lastResult.failed.length} failed</span>}
                {lastResult.skipped.length > 0 && <span>; {lastResult.skipped.length} skipped</span>}
                {lastResult.cancelled && <span>; cancelled</span>}
              </div>
            )}
          </div>
          <DialogFooter>
            {progress ? (
              <Button variant="secondary" onClick={() => abortRef.current?.abort()}>Cancel remaining</Button>
            ) : lastResult ? (
              <>
                {lastResult.failed.length > 0 && pending && (
                  <Button variant="secondary" onClick={() => {
                    setLastResult(null);
                    const noteIds = lastResult.failed.map((item) => item.noteId);
                    setPending({
                      ...pending,
                      noteIds,
                      preview: previewBulkAction(noteIds, pending.mutation),
                    });
                  }}>Retry failed</Button>
                )}
                <Button onClick={closeConfirmation}>Done</Button>
              </>
            ) : (
              <>
                <Button variant="ghost" onClick={closeConfirmation}>Cancel</Button>
                <Button disabled={!preview?.eligibleIds.length || !vaultLocation} onClick={() => void apply()}>Apply to {preview?.eligibleIds.length ?? 0} notes</Button>
              </>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={historyOpen} onOpenChange={setHistoryOpen}>
        <DialogContent className="max-h-[85vh] max-w-xl overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Recent bulk actions</DialogTitle>
            <DialogDescription>The latest 10 actions are kept on this device for 90 days.</DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            {!history.length && <p className="py-6 text-center text-sm text-muted-foreground">No bulk actions yet.</p>}
            {history.map((record) => (
              <div key={record.id} className="rounded-md border border-border/70 p-3">
                <div className="flex items-start gap-3">
                  <div className="min-w-0 flex-1">
                    <strong className="block text-sm">{record.label}</strong>
                    <span className="text-xs text-muted-foreground">{new Date(record.createdAt).toLocaleString()} · {record.entries.length} notes · {record.status}</span>
                    <p className="mt-1 truncate text-xs">{record.summary.join("; ")}</p>
                  </div>
                  {(record.status === "applied" || record.status === "partially-undone") ? (
                    <Button size="sm" variant="secondary" className="h-8 gap-1" disabled={!vaultLocation} onClick={() => vaultLocation && void transitionBulkAction(vaultLocation, record.id, "undo")}><Undo2 size={14} /> Undo</Button>
                  ) : (
                    <Button size="sm" variant="secondary" className="h-8 gap-1" disabled={!vaultLocation} onClick={() => vaultLocation && void transitionBulkAction(vaultLocation, record.id, "redo")}><RotateCcw size={14} /> Redo</Button>
                  )}
                </div>
              </div>
            ))}
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
