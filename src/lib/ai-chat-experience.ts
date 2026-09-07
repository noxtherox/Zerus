import type { StoredAiMessage } from "./ai-conversations";

export const CHAT_HISTORY_BUDGET = 24_000;
/** Keep complete recent turns; never silently truncate the current question. */
export function budgetChatHistory(
  messages: StoredAiMessage[],
  budget = CHAT_HISTORY_BUDGET,
) {
  const lastUser = messages.map((message) => message.role).lastIndexOf("user");
  if (lastUser < 0) return { messages: [], omitted: messages.length };
  let start = lastUser;
  let size = messages
    .slice(start)
    .reduce((sum, message) => sum + message.content.length, 0);
  if (size > budget)
    throw new Error(
      "This message is too long. Split it into smaller questions.",
    );
  for (let index = lastUser - 1; index >= 0; index--) {
    size += messages[index].content.length;
    if (size > budget) break;
    if (messages[index].role === "user") start = index;
  }
  return { messages: messages.slice(start), omitted: start };
}

/** Hide the native tool/edit protocol, including partially streamed opening tags. */
export function visibleChatStream(text: string): string {
  const protocol = text.search(
    /<(?:zerus_tool|zerus[-_]action|zerus_actions|note_action|note_get|note_list|search|note_append|note_set_body)/i,
  );
  const visible = protocol >= 0 ? text.slice(0, protocol) : text;
  return visible
    .replace(/\n?```(?:json)?\s*$/i, "")
    .replace(/<[^>]*$/, "")
    .replace(/\[[^\]]*\]\([^)]*$/, "")
    .trimEnd();
}

export function chatActivityLabel(name: string): string {
  return (
    {
      search: "Searching your notes",
      note_get: "Reading a note",
      note_list: "Finding notes",
      note_append: "Adding to your note",
      note_set_body: "Updating your note",
    }[name] ?? "Working with your notes"
  );
}

export function latestUserIndex(
  messages: StoredAiMessage[],
  before = messages.length,
) {
  return messages
    .slice(0, before)
    .map((message) => message.role)
    .lastIndexOf("user");
}

export function planAiUndo(
  changes: import("./ai-conversations").AiNoteChange[],
  currentBodies: Map<string, string>,
) {
  const latest = new Map<string, import("./ai-conversations").AiNoteChange>();
  const originals = new Map<string, string>();
  for (const change of changes) {
    latest.set(change.noteId, change);
    if (!originals.has(change.noteId))
      originals.set(change.noteId, change.before);
  }
  for (const change of latest.values()) {
    if (currentBodies.get(change.noteId) !== change.after)
      throw new Error(
        "The note changed after this edit. Review the saved changes before restoring it.",
      );
  }
  return originals;
}
