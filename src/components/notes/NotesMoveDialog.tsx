import { useState } from "react";
import { Loader2 } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { getAllTypePaths, isExternalNote, noteTitle, type Note } from "@/lib/note-utils";
import type { TypeIcons } from "@/lib/type-icons";
import { moveNotesToType, type NotesMoveResult } from "@/store/notes-store";
import { TypePicker } from "./TypePicker";

export interface NotesMoveRequest {
  noteIds: string[];
  openNoteId?: string;
  typePath?: string[];
}

export function NotesMoveDialog({ request, notes, extraTypes, typeIcons, onClose, onMoved }: {
  request: NotesMoveRequest;
  notes: Note[];
  extraTypes: string[][];
  typeIcons: TypeIcons;
  onClose: () => void;
  onMoved: (ids: string[]) => void;
}) {
  const [scope, setScope] = useState<"open" | "selected">(request.openNoteId ? "open" : "selected");
  const [typePath, setTypePath] = useState(request.typePath ?? []);
  const [progress, setProgress] = useState<{ completed: number; total: number } | null>(null);
  const [result, setResult] = useState<NotesMoveResult | null>(null);
  const ids = scope === "open" && request.openNoteId ? [request.openNoteId] : request.noteIds;
  const idSet = new Set(ids);
  const affected = notes.filter((note) => idSet.has(note.id));
  const externalCount = affected.filter(isExternalNote).length;
  const openNote = notes.find((note) => note.id === request.openNoteId);
  const issues = result ? [...result.failed, ...result.skipped] : [];
  const moving = progress !== null;

  const move = async () => {
    setProgress({ completed: 0, total: ids.length });
    try {
      const outcome = await moveNotesToType(ids, typePath, (completed, total) => setProgress({ completed, total }));
      onMoved(outcome.movedIds);
      if (!outcome.failed.length && !outcome.skipped.length) onClose();
      else setResult(outcome);
    } finally {
      setProgress(null);
    }
  };

  return (
    <Dialog open onOpenChange={(open) => { if (!open && !moving) onClose(); }}>
      <DialogContent className="max-h-[85vh] max-w-lg overflow-y-auto text-foreground" onEscapeKeyDown={(event) => { if (moving) event.preventDefault(); }} onPointerDownOutside={(event) => { if (moving) event.preventDefault(); }}>
        <DialogHeader>
          <DialogTitle>{result ? "Move results" : "Move to folder"}</DialogTitle>
          <DialogDescription>
            {result
              ? `${result.movedIds.length} ${result.movedIds.length === 1 ? "note moved" : "notes moved"}. ${issues.length} ${issues.length === 1 ? "note was" : "notes were"} left in place.`
              : request.openNoteId ? "Move only the open note or all selected notes." : `Choose a destination for ${ids.length === 1 ? "this note" : `all ${ids.length} selected notes`}.`}
          </DialogDescription>
        </DialogHeader>
        {!result && (
          <div className="space-y-4">
            {request.openNoteId && (
              <fieldset className="space-y-2" disabled={moving}>
                <legend className="mb-2 text-sm font-medium">Notes to move</legend>
                <label className="flex cursor-pointer items-start gap-3 rounded-md border p-3 text-sm">
                  <input type="radio" name="move-scope" value="open" checked={scope === "open"} onChange={() => setScope("open")} className="mt-1 accent-zerus-accent" />
                  <span className="min-w-0"><span className="block font-medium">Only the open note</span><span className="block break-words text-xs text-muted-foreground">{openNote ? noteTitle(openNote) : "Missing note"}</span></span>
                </label>
                <label className="flex cursor-pointer items-center gap-3 rounded-md border p-3 text-sm">
                  <input type="radio" name="move-scope" value="selected" checked={scope === "selected"} onChange={() => setScope("selected")} className="accent-zerus-accent" />
                  <span>All selected notes ({request.noteIds.length})</span>
                </label>
              </fieldset>
            )}
            <div className="space-y-2">
              <p className="text-sm font-medium">Destination folder</p>
              <TypePicker value={typePath} existingTypePaths={getAllTypePaths(notes, extraTypes)} typeIcons={typeIcons} label={typePath.length ? undefined : "Choose folder…"} onChange={setTypePath} disabled={moving} />
            </div>
            <div className="space-y-2 rounded-md bg-muted/60 p-3 text-xs text-muted-foreground">
              <p>Managed files move with their notes. Attachments stay accessible, and external file connections keep pointing to their original files.</p>
              {externalCount > 0 && <p>{externalCount === 1 ? "The external Markdown file moves" : `${externalCount} external Markdown files move`} into the vault. Local images are copied into the vault; their originals are kept so other notes can still use them.</p>}
            </div>
            <details className="text-xs text-muted-foreground">
              <summary className="cursor-pointer">Show {ids.length} {ids.length === 1 ? "note" : "notes"}</summary>
              <ul className="mt-2 max-h-36 space-y-1 overflow-y-auto">{affected.map((note) => <li key={note.id} className="break-words">{noteTitle(note)}</li>)}</ul>
            </details>
          </div>
        )}
        {result && <ul className="space-y-2 text-sm">{issues.map((issue) => <li key={issue.noteId}><span className="font-medium">{issue.title}</span><span className="block text-xs text-muted-foreground">{issue.reason}</span></li>)}</ul>}
        {progress && <p role="status" className="flex items-center gap-2 text-sm"><Loader2 size={15} className="animate-spin" />Moving {progress.completed} of {progress.total}…</p>}
        <DialogFooter>
          <Button variant="outline" disabled={moving} onClick={onClose}>{result ? "Done" : "Cancel"}</Button>
          {!result && <Button disabled={moving || !typePath.length || !ids.length} onClick={() => void move()}>Move {ids.length === 1 ? "note" : `${ids.length} notes`}</Button>}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
