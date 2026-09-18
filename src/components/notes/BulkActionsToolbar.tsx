import { useEffect, useMemo, useRef, useState } from "react";
import {
  Archive,
  ArchiveRestore,
  CheckSquare,
  ChevronDown,
  History,
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
import { noteTitle, noteTypePath, type Note } from "@/lib/note-utils";
import { cn } from "@/lib/utils";
import { ListValueEditor } from "@/components/notes/PropertiesSection";

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
  externalRequest?: BulkMutationRequest | null;
  onExternalRequestHandled?: () => void;
  className?: string;
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
    left.relationMultiple === right.relationMultiple;
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
    if (matches.some((match) => !match || !sameDefinition(candidate, match))) return [];
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

function propertyStateLabel(notes: Note[], name: string): string {
  const values = notes.map((note) => propertyValue(note, name));
  const serialized = values.map((value) => JSON.stringify(value));
  if (serialized.some((value) => value !== serialized[0])) return "Mixed";
  const value = values[0];
  if (value === undefined || value === "") return "Empty";
  return Array.isArray(value) ? value.join(", ") : String(value);
}

function valueForDefinition(definition: PropertyDef, raw: string): PropertyValue {
  if (definition.type === "checkbox") return raw === "true";
  if (definition.type === "number") return Number(raw);
  if ((definition.type === "list" && definition.listMultiple) ||
      (definition.type === "relation" && definition.relationMultiple)) {
    return raw.split(",").map((value) => value.trim()).filter(Boolean);
  }
  return raw;
}

function PropertyChangeComposer({
  notes,
  properties,
  changes,
  onChanges,
}: {
  notes: Note[];
  properties: PropertyDef[];
  changes: BulkPropertyChange[];
  onChanges: (changes: BulkPropertyChange[]) => void;
}) {
  const [propertyName, setPropertyName] = useState(properties[0]?.name ?? "");
  const definition = properties.find((property) => property.name === propertyName);
  const supportsListOperations = definition && (
    (definition.type === "list" && definition.listMultiple) ||
    (definition.type === "relation" && definition.relationMultiple)
  );
  const [operation, setOperation] = useState<BulkPropertyOperation>("set");
  const [rawValue, setRawValue] = useState("");
  const [selectedListValues, setSelectedListValues] = useState<string[]>([]);

  const addChange = () => {
    if (!definition) return;
    const value = definition.type === "list"
      ? definition.listMultiple
        ? selectedListValues
        : selectedListValues[0] ?? ""
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
    setSelectedListValues([]);
  };

  if (!properties.length) {
    return <p className="rounded-md border border-dashed p-4 text-sm text-muted-foreground">The selected note types do not share any compatible properties.</p>;
  }

  return (
    <div className="space-y-4">
      <div className="grid gap-3 rounded-md border border-border/70 p-3 sm:grid-cols-[1fr_130px]">
        <Select value={propertyName} onValueChange={(value) => {
          setPropertyName(value);
          setOperation("set");
          setRawValue("");
          setSelectedListValues([]);
        }}>
          <SelectTrigger><SelectValue /></SelectTrigger>
          <SelectContent>
            {properties.map((property) => (
              <SelectItem key={property.name} value={property.name}>
                {property.name} · {propertyStateLabel(notes, property.name)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select value={operation} onValueChange={(value) => {
          setOperation(value as BulkPropertyOperation);
          setRawValue("");
          setSelectedListValues([]);
        }}>
          <SelectTrigger><SelectValue /></SelectTrigger>
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
              value={selectedListValues}
              onCommit={(value) => {
                if (Array.isArray(value)) setSelectedListValues(value);
                else setSelectedListValues(value === null ? [] : [String(value)]);
              }}
              emptyPickerLabel="Select options"
              selectedPickerLabel="Add another"
              searchPlaceholder="Search available options…"
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
            placeholder={supportsListOperations ? "Comma-separated values" : "New value"}
          />
        ) : null}
        <Button
          type="button"
          variant="secondary"
          className="sm:col-span-2"
          disabled={operation !== "clear" && definition?.type === "list" && selectedListValues.length === 0}
          onClick={addChange}
        >
          Add change
        </Button>
      </div>
      {changes.length > 0 && (
        <div className="space-y-2">
          {changes.map((change) => (
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
  externalRequest,
  onExternalRequestHandled,
  className,
}: BulkActionsToolbarProps) {
  const selectedNotes = useMemo(
    () => notes.filter((note) => selectedIds.has(note.id)),
    [notes, selectedIds],
  );
  const properties = useMemo(
    () => commonProperties(selectedNotes, schemas),
    [schemas, selectedNotes],
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
      <div className={cn("sticky top-0 z-20 flex min-h-11 items-center gap-1.5 border-b border-zerus-accent/20 bg-zerus-surface/95 px-3 py-1.5 shadow-sm backdrop-blur", className)}>
        <strong className="min-w-0 flex-1 truncate text-xs">{selectedIds.size} selected</strong>
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
              setPropertyChanges([]);
              setPropertyDialogOpen(true);
            }}>
              <SlidersHorizontal size={14} className="mr-2" /> Properties
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
        <DialogContent className="max-h-[85vh] max-w-xl overflow-y-auto">
          <DialogHeader>
            <DialogTitle>Edit properties for {selectedIds.size} notes</DialogTitle>
            <DialogDescription>Only compatible properties shared by every selected note are available. Clear keeps the key with an explicit empty value.</DialogDescription>
          </DialogHeader>
          <PropertyChangeComposer notes={selectedNotes} properties={properties} changes={propertyChanges} onChanges={setPropertyChanges} />
          <DialogFooter>
            <Button variant="ghost" onClick={() => setPropertyDialogOpen(false)}>Cancel</Button>
            <Button disabled={!propertyChanges.length} onClick={() => {
              setPropertyDialogOpen(false);
              prepare({ properties: propertyChanges });
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
