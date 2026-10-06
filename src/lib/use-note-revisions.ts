import { useCallback, useEffect, useRef, useState } from "react";
import { isExternalNote, type Note } from "@/lib/note-utils";
import { getNoteProperties } from "@/lib/frontmatter";
import { getNoteRevisions, updateNoteRevision, useVaultSelector } from "@/store/notes-store";
import { revisionContent, REVISION_TRANSACTION_KEY, type NoteRevisions, type RevisionAction } from "@/lib/note-revisions";

export function useNoteRevisions(note: Note | null) {
  const [document, setDocument] = useState<NoteRevisions | null>(null);
  const [selection, setSelection] = useState<{ noteId: string; revisionId: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [workingContext, setWorkingContext] = useState<string | null>(null);
  const [retryVersion, setRetryVersion] = useState(0);
  const version = useVaultSelector((vault) => vault.revisionVersion);
  const location = useVaultSelector((vault) => vault.location);
  const storeBusy = useVaultSelector((vault) => !!note && vault.busyNoteIds.has(note.id));
  const id = note && !isExternalNote(note) ? note.id : null;
  const context = `${location ?? ""}:${id ?? ""}`;
  const activeContext = useRef(context);
  activeContext.current = context;
  const working = workingContext === context;
  const commit = note ? getNoteProperties(note.content)[REVISION_TRANSACTION_KEY] : undefined;
  useEffect(() => {
    let cancelled = false;
    setDocument(null);
    setError(null);
    if (id) void getNoteRevisions(id).then((value) => {
      if (!cancelled) setDocument(value);
    }).catch((cause) => { if (!cancelled) setError(String(cause)); });
    return () => { cancelled = true; };
  }, [id, version, location, commit, retryVersion]);
  useEffect(() => {
    const onFocus = () => setRetryVersion((value) => value + 1);
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, []);
  const data = document?.noteId === id ? document : null;
  const selected = data?.revisions.find((r) =>
    r.id === (selection?.noteId === id ? selection.revisionId : data.currentId),
  ) ?? data?.revisions.find((r) => r.id === data.currentId) ?? null;
  const historical = !!selected && selected.id !== data?.currentId;
  const select = useCallback((revisionId: string) => {
    if (id) setSelection({ noteId: id, revisionId });
  }, [id]);
  const run = async (action: RevisionAction) => {
    if (!id || working) return;
    setWorkingContext(context);
    setError(null);
    try {
      await updateNoteRevision(id, action);
      const next = await getNoteRevisions(id);
      if (activeContext.current !== context) return;
      setDocument(next);
      setSelection(null);
    } catch (cause) {
      if (activeContext.current === context) setError(cause instanceof Error ? cause.message : String(cause));
    } finally { setWorkingContext((value) => value === context ? null : value); }
  };
  return {
    data, selected, historical, select, run, error,
    retry: () => setRetryVersion((value) => value + 1),
    busy: working || storeBusy,
    previewNote: note && selected && historical
      ? { ...note, content: revisionContent(selected, note) } : null,
  };
}

export type NoteRevisionController = ReturnType<typeof useNoteRevisions>;
