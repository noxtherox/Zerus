import { noteUnifiedDiff } from "@/lib/ai-diff";
import { useState } from "react";
import {
  createNote,
  getNotes,
  writeAgentNoteContent,
  getVaultBackend,
} from "@/store/notes-store";
import { noteBody, withBody } from "@/lib/frontmatter";
import { noteTitle, noteTypePath, type Note } from "@/lib/note-utils";
import type { AiNoteChange } from "@/lib/ai-conversations";
import { planAiUndo } from "@/lib/ai-chat-experience";
import { showError, showSuccess } from "@/utils/toast";

export function ChatAnswerActions({
  text,
  note,
  changes = [],
  onRegenerate,
  disabled = false,
  compact = false,
}: {
  text: string;
  note?: Note | null;
  changes?: AiNoteChange[];
  onRegenerate?: () => void;
  disabled?: boolean;
  compact?: boolean;
}) {
  const [localChanges, setLocalChanges] = useState<AiNoteChange[]>([]);
  const [undone, setUndone] = useState(false);
  const [busy, setBusy] = useState(false);
  const allChanges = [...changes, ...localChanges];
  const action = async (work: () => Promise<void> | void) => {
    if (busy) return;
    setBusy(true);
    try {
      await work();
    } catch (error) {
      showError(String(error));
    } finally {
      setBusy(false);
    }
  };
  const button =
    "rounded px-2 py-2 text-xs hover:bg-muted/50 focus-visible:outline focus-visible:outline-2 disabled:opacity-40";
  return (
    <div className="mt-3 border-t border-current/15 pt-1">
      <div className="flex flex-wrap items-center gap-1">
        {!compact && <>
        <button
          className={button}
          disabled={busy}
          onClick={() =>
            void action(async () => {
              await navigator.clipboard.writeText(text);
              showSuccess("Copied answer");
            })
          }
        >
          Copy
        </button>
        <button
          className={button}
          disabled={busy || disabled}
          onClick={() =>
            void action(async () => {
              const created = await createNote(
                note ? noteTypePath(note) : ["inbox"],
                text.startsWith("# ") ? text : `# Chat answer\n\n${text}`,
              );
              if (!created) throw new Error("The answer could not be saved.");
              showSuccess("Answer saved as a note");
            })
          }
        >
          Save as note
        </button>
        {note && (
          <button
            title={`Append to ${noteTitle(note)}`}
            className={button}
            disabled={busy || disabled || localChanges.length > 0}
            onClick={() =>
              void action(async () => {
                const latest = getNotes().find(
                  (candidate) => candidate.id === note.id,
                );
                if (!latest)
                  throw new Error("This note is no longer available.");
                const before = noteBody(latest.content);
                const after = `${before.trimEnd()}\n\n${text}`;
                if (
                  !(await writeAgentNoteContent(
                    latest.id,
                    latest.content,
                    withBody(latest.content, after),
                  ))
                )
                  throw new Error("The append could not be saved.");
                const saved = getNotes().find((note) => note.id === latest.id);
                if (
                  !saved ||
                  (await getVaultBackend()?.readText(saved.path)) !==
                    saved.content
                )
                  throw new Error("The append could not be verified.");
                setLocalChanges([
                  {
                    noteId: latest.id,
                    title: noteTitle(latest),
                    before,
                    after,
                  },
                ]);
                setUndone(false);
                showSuccess("Answer appended to note");
              })
            }
          >
            Append to note
          </button>
        )}
        {onRegenerate && (
          <button
            className={button}
            disabled={busy || disabled}
            onClick={onRegenerate}
          >
            Regenerate
          </button>
        )}
        </>}
        {allChanges.length > 0 && (
          <button
            className={button}
            disabled={busy || disabled || undone}
            onClick={() =>
              void action(async () => {
                const originals = planAiUndo(
                  allChanges,
                  new Map(
                    getNotes().map((note) => [note.id, noteBody(note.content)]),
                  ),
                );
                for (const [id, before] of originals) {
                  const current = getNotes().find((note) => note.id === id);
                  if (
                    !current ||
                    !(await writeAgentNoteContent(
                      id,
                      current.content,
                      withBody(current.content, before),
                    ))
                  )
                    throw new Error("Undo could not be saved.");
                }
                setUndone(true);
                showSuccess("Changes undone");
              })
            }
          >
            {undone ? "Undone" : "Undo changes"}
          </button>
        )}
      </div>
      {allChanges.length > 0 && (
        <details className="px-2 py-1 text-xs">
          <summary className="cursor-pointer">View changes</summary>
          {allChanges.map((change, index) => (
            <div key={index} className="mt-3 space-y-2">
              <p className="font-medium">{change.title}</p>
              <pre className="max-h-64 overflow-auto whitespace-pre-wrap rounded bg-muted/50 p-2">
                {noteUnifiedDiff(change.before, change.after, change.title)}
              </pre>
            </div>
          ))}
        </details>
      )}
    </div>
  );
}
