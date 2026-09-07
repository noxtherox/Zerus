import { useState } from "react";
import { noteTitle, isTrashed, type Note } from "@/lib/note-utils";
import { notesInAiScope, type AiKnowledgeScope } from "@/lib/ai-context";

export function ChatContextPicker({
  note,
  notes,
  scope,
  selected,
  onChange,
  disabled,
}: {
  note: Note | null;
  notes: Note[];
  scope: AiKnowledgeScope;
  selected: string[] | null;
  onChange: (ids: string[] | null) => void;
  disabled: boolean;
}) {
  const [query, setQuery] = useState("");
  const ids =
    selected ?? notesInAiScope(notes, scope).map((candidate) => candidate.id);
  return (
    <details className="border-b border-border/60 px-3 py-2 text-xs">
      <summary className="cursor-pointer text-muted-foreground">
        Context ·{" "}
        {selected === null
          ? "Active folder / scope"
          : `${ids.length} selected notes`}
      </summary>
      <div className="mt-2 flex flex-wrap gap-2">
        <button
          disabled={disabled}
          className="rounded-full border px-2 py-1"
          aria-pressed={selected === null}
          onClick={() => onChange(null)}
        >
          Active scope
        </button>
        {note && (
          <button
            disabled={disabled}
            className="max-w-full truncate rounded-full border px-2 py-1"
            aria-pressed={ids.length === 1 && ids[0] === note.id}
            onClick={() => onChange([note.id])}
          >
            Only {noteTitle(note)}
          </button>
        )}
        <button
          disabled={disabled}
          className="rounded-full border px-2 py-1"
          onClick={() => onChange([])}
        >
          Clear selection
        </button>
      </div>
      <input
        aria-label="Find notes to include"
        placeholder="Find additional notes…"
        className="mt-2 w-full rounded border bg-background p-2"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
      />
      <div className="mt-2 max-h-40 overflow-y-auto">
        {notes
          .filter(
            (candidate) =>
              !isTrashed(candidate) &&
              `${noteTitle(candidate)} ${candidate.path}`
                .toLowerCase()
                .includes(query.toLowerCase()),
          )
          .slice(0, 100)
          .map((candidate) => (
            <label key={candidate.id} className="flex items-start gap-2 py-1.5">
              <input
                type="checkbox"
                disabled={disabled}
                checked={ids.includes(candidate.id)}
                onChange={(event) =>
                  onChange(
                    event.target.checked
                      ? [...ids, candidate.id]
                      : ids.filter((id) => id !== candidate.id),
                  )
                }
              />
              <span className="min-w-0">
                <span className="block truncate">{noteTitle(candidate)}</span>
                <span className="block truncate text-muted-foreground">
                  {candidate.path}
                </span>
              </span>
            </label>
          ))}
      </div>
      <p className="mt-2 text-muted-foreground">
        Selected context is sent to your configured AI provider. Retrieved
        excerpts appear with each answer.
      </p>
    </details>
  );
}
