import { notesInAiScope, type AiKnowledgeScope } from "./ai-context";
import {
  getNotes,
  getVaultBackend,
  getPropertySchemas,
  loadAllNotes,
  noteBulkBlockReason,
  writeAgentNoteContent,
  createNote,
  moveAgentNote,
  restoreAgentNote,
} from "@/store/notes-store";
import { loadChatConversations } from "./mobile-chat-history";
import { type NotesAgentPort } from "./ai-harness";
import type { VaultBackend } from "./vault/backend";
import { noteTypePath, typeKey } from "./note-utils";

export function notesAgentPort(
  backend: VaultBackend,
  chatId: string,
  ownerId: string,
  scopeStillActive: () => boolean = () => true,
  scopeKey?: string,
): NotesAgentPort {
  const scope = scopeKey
    ? (JSON.parse(scopeKey) as
        | AiKnowledgeScope
        | { kind: "note"; noteId: string })
    : null;
  const scopedIds = () =>
    scope
      ? new Set(
          (scope.kind === "note"
            ? getNotes().filter((note) => note.id === scope.noteId)
            : notesInAiScope(getNotes(), scope)
          ).map((note) => note.id),
        )
      : new Set<string>();
  const permitsType = (path: string[]) =>
    scope?.kind === "vault" ||
    (scope?.kind === "type" &&
      (typeKey(path) === typeKey(scope.path) ||
        (scope.includeSubtypes !== false &&
          typeKey(path).startsWith(`${typeKey(scope.path)}/`))));
  const find = (id: string) => {
    const note = getNotes().find((item) => item.id === id);
    if (!note) throw new Error("Note is unavailable");
    return note;
  };
  return {
    backend,
    scopeKey,
    permitsRead: (note) => scopedIds().has(note.id),
    permitsWrite: (note) =>
      permitsType(
        noteTypePath({ ...note, path: note.path.replace(/^\.trash\//, "") }),
      ) ||
      (scope?.kind === "selection"
        ? scope.noteIds.includes(note.id)
        : scope?.kind === "note"
          ? scope.noteId === note.id
          : scopedIds().has(note.id)),
    permitsCreate: permitsType,
    notes: getNotes,
    schemas: getPropertySchemas,
    hydrate: async () => {
      if (!(await loadAllNotes()))
        throw new Error(
          "Notes could not be loaded completely. Try again after vault loading finishes.",
        );
    },
    writable: async () => {
      if (getVaultBackend() !== backend || !scopeStillActive()) return false;
      const chat = (await loadChatConversations(backend)).find(
        (item) => item.id === chatId,
      );
      return Boolean(
        chat &&
          chat.owner.id === ownerId &&
          !chat.archivedAt &&
          !chat.deletedAt,
      );
    },
    write: async (note, content) => {
      const blocked = noteBulkBlockReason(note.id);
      if (blocked) throw new Error(blocked);
      if (!(await writeAgentNoteContent(note.id, note.content, content)))
        throw new Error(
          "The note could not be saved. It may have a conflict or the vault may be busy.",
        );
      return find(note.id);
    },
    create: async (id, typePath, content) => {
      const note = await createNote(typePath, content, id);
      if (!note) throw new Error("The note could not be created.");
      return note;
    },
    organize: async (note, args, path) => {
      await moveAgentNote(note.id, note.content, path, args);
      return find(note.id);
    },
    restore: async (snapshot, current) => {
      await restoreAgentNote(current.id, current.content, snapshot);
      const note = find(current.id);
      if (
        snapshot &&
        (note.content !== snapshot.content || note.path !== snapshot.path)
      )
        throw new Error("Undo could not restore the approved snapshot.");
      if ((await backend.readText(note.path)) !== note.content)
        throw new Error("Undo was not durably saved.");
      return note;
    },
  };
}
