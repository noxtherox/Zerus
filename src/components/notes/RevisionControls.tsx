import { useState } from "react";
import { ChevronDown, Plus, Trash2, Undo2 } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";
import { isExternalNote, isTrashed, type Note } from "@/lib/note-utils";
import { trashNote } from "@/store/notes-store";
import type { NoteRevisionController } from "@/lib/use-note-revisions";

export function RevisionControls({ note, controller, disabled = false, onSelectRevision, hideHeading = false }: {
  note: Note; controller: NoteRevisionController; disabled?: boolean; onSelectRevision?: () => void; hideHeading?: boolean;
}) {
  const [deleteOpen, setDeleteOpen] = useState(false);
  const { data, selected, historical, busy, error, select, run } = controller;
  if (isExternalNote(note)) return null;
  const active = data?.revisions.filter((r) => !r.deletedAt).sort((a, b) => b.number - a.number) ?? [];
  const deleted = data?.revisions.filter((r) => r.deletedAt) ?? [];
  const blocked = disabled || busy || isTrashed(note);
  const last = active.length === 1;
  const selectRevision = (id: string) => {
    select(id);
    onSelectRevision?.();
  };
  return <section className={hideHeading ? "space-y-3 px-4 pb-4" : "shrink-0 space-y-3 border-b border-border/60 px-4 py-4"} aria-label={hideHeading ? undefined : "Revisions"} data-note-revisions>
    {!hideHeading && <h2 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Revisions</h2>}
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm" className="h-9 w-full justify-between gap-2 text-xs" disabled={!data || busy} aria-label="Select revision">
          <span>{selected ? `Revision ${selected.number}` : error ? "Revisions unavailable" : "Loading revisions…"}</span>
          <span className="ml-auto text-muted-foreground">{selected?.deletedAt ? "In Trash" : historical ? "Read-only" : selected ? "Current" : ""}</span>
          <ChevronDown size={13} className="shrink-0" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" className="max-h-80 w-72 overflow-y-auto">
        <DropdownMenuLabel>Revisions</DropdownMenuLabel>
        {active.map((revision) => <DropdownMenuItem key={revision.id} onSelect={() => selectRevision(revision.id)} className="flex flex-col items-start gap-0.5 py-2">
          <span>Revision {revision.number}{revision.id === data?.currentId ? " · Current" : ""}</span>
          <span className="text-xs text-muted-foreground">{new Date(revision.createdAt).toLocaleString()}</span>
        </DropdownMenuItem>)}
        {deleted.length > 0 && <>
          <DropdownMenuSeparator /><DropdownMenuLabel>In Trash</DropdownMenuLabel>
          {deleted.map((revision) => <DropdownMenuItem key={revision.id} onSelect={() => selectRevision(revision.id)}>
            Revision {revision.number} · Deleted
          </DropdownMenuItem>)}
        </>}
      </DropdownMenuContent>
    </DropdownMenu>
    {selected && <p className="text-xs text-muted-foreground">{new Date(selected.createdAt).toLocaleString()}{selected.deletedAt ? " · Read-only" : ""}</p>}
    <div className="flex flex-wrap items-center justify-between gap-2">
    <Button variant="ghost" size="sm" className="h-8 gap-1 text-xs" disabled={blocked || !data} onClick={() => void run({ kind: "create" })}>
      <Plus size={14} /> New revision
    </Button>
    {historical && !selected?.deletedAt && <Button variant="outline" size="sm" className="order-last h-8 w-full text-xs" disabled={blocked} onClick={() => selected && void run({ kind: "promote", revisionId: selected.id })}>Make current</Button>}
    {selected?.deletedAt
      ? <Button variant="outline" size="sm" className="h-8 gap-1 text-xs" disabled={blocked} onClick={() => void run({ kind: "restore", revisionId: selected.id })}><Undo2 size={14} /> Restore revision</Button>
      : <Button variant="ghost" size="icon" className="h-8 w-8 text-muted-foreground" aria-label="Delete revision" title="Delete revision" disabled={blocked || !selected} onClick={() => setDeleteOpen(true)}><Trash2 size={14} /></Button>}
    </div>
    {busy && <span className="text-xs text-muted-foreground" role="status">Saving revision…</span>}
    {error && <div className="flex w-full items-center gap-2"><p role="alert" className="text-xs text-destructive">{error}</p><Button variant="outline" size="sm" disabled={busy} onClick={controller.retry}>Retry</Button></div>}
    <AlertDialog open={deleteOpen} onOpenChange={setDeleteOpen}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{last ? "Move the whole note to Trash?" : `Delete revision ${selected?.number}?`}</AlertDialogTitle>
          <AlertDialogDescription>{last
            ? "This is the note’s only remaining revision. The whole note and all its revisions will move to Trash, where you can restore them together."
            : historical ? "This revision and its files will move to Trash. You can restore it until Trash is emptied."
              : "This revision and its files will move to Trash. The most recent remaining revision will become current."}</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter><AlertDialogCancel>Cancel</AlertDialogCancel><AlertDialogAction disabled={blocked} onClick={() => {
          if (last) void trashNote(note.id);
          else if (selected) void run({ kind: "trash", revisionId: selected.id });
        }}>{last ? "Move note to Trash" : "Delete revision"}</AlertDialogAction></AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  </section>;
}
