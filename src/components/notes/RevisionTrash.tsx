import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Undo2 } from "@/lib/icons";
import { isTrashed, noteTitle } from "@/lib/note-utils";
import { loadAllNotes, updateNoteRevision, useVault } from "@/store/notes-store";

export function RevisionTrash() {
  const vault = useVault();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const deleted = vault.trashedRevisions.filter((entry) => {
    const note = vault.notes.find((note) => note.id === entry.noteId);
    return !note || !isTrashed(note);
  });
  if (!deleted.length) return null;
  return <section aria-label="Deleted revisions" className="border-b border-border/60">
    <p className="px-4 py-2 text-xs font-semibold text-muted-foreground">Deleted revisions</p>
    {deleted.map(({ noteId, revision }) => {
      const note = vault.notes.find((note) => note.id === noteId);
      return <div key={`${noteId}:${revision.id}`} className="flex items-center gap-2 border-t border-border/40 px-4 py-3">
        <div className="min-w-0 flex-1"><p className="truncate text-sm font-medium">{note ? noteTitle(note) : "Note"} · Revision {revision.number}</p>
          <p className="text-xs text-muted-foreground">{new Date(revision.createdAt).toLocaleString()}</p></div>
        <Button variant="ghost" size="sm" className="gap-1" disabled={busy} aria-label={`Restore revision ${revision.number}`} onClick={() => {
          setBusy(true); setError(null);
          void (async () => {
            if (!note && !(await loadAllNotes())) throw new Error("Load the note before restoring its revision.");
            await updateNoteRevision(noteId, { kind: "restore", revisionId: revision.id });
          })().catch((cause) => setError(String(cause))).finally(() => setBusy(false));
        }}><Undo2 size={14} /> Restore</Button>
      </div>;
    })}
    {error && <p role="alert" className="px-4 py-2 text-xs text-destructive">{error}</p>}
  </section>;
}
