import { useState } from "react";
import { createNote, getNotes, updateNoteBody } from "@/store/notes-store";
import { noteBody } from "@/lib/frontmatter";
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
}: {
  text: string;
  note?: Note | null;
  changes?: AiNoteChange[];
  onRegenerate?: () => void;
  disabled?: boolean;
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
              void action(() => {
                const latest = getNotes().find(
                  (candidate) => candidate.id === note.id,
                );
                if (!latest)
                  throw new Error("This note is no longer available.");
                const before = noteBody(latest.content);
                const after = `${before.trimEnd()}\n\n${text}`;
                updateNoteBody(latest.id, after);
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
        {allChanges.length > 0 && (
          <button
            className={button}
            disabled={busy || disabled || undone}
            onClick={() =>
              void action(() => {
                const originals = planAiUndo(
                  allChanges,
                  new Map(
                    getNotes().map((note) => [note.id, noteBody(note.content)]),
                  ),
                );
                for (const [id, before] of originals)
                  updateNoteBody(id, before);
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
              <p>Before</p>
              <pre className="max-h-48 overflow-auto whitespace-pre-wrap rounded bg-red-500/10 p-2">
                {change.before || "Empty note"}
              </pre>
              <p>After</p>
              <pre className="max-h-48 overflow-auto whitespace-pre-wrap rounded bg-emerald-500/10 p-2">
                {change.after}
              </pre>
            </div>
          ))}
        </details>
      )}
    </div>
  );
}
