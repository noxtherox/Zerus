import { chatContentRevision } from "@/lib/mobile-chat-history";
import { noteBody } from "@/lib/frontmatter";
import { DEFAULT_TYPE, isExternalNote, isTrashed, noteTitle, type Note } from "@/lib/note-utils";

const ACTION_BLOCK = /<zerus-action>\s*([\s\S]*?)\s*<\/zerus-action>/gi;

export type MobileAIAction =
  | { action: "create_note"; title: string; body: string; type?: string[] }
  | { action: "set_note_body"; noteId: string; revision: string; body: string }
  | { action: "append_note"; noteId: string; revision: string; text: string }
  | { action: "replace_note_text"; noteId: string; revision: string; oldText: string; newText: string };

export interface ParsedMobileAIActions {
  actions: MobileAIAction[];
  visibleText: string;
  malformed: boolean;
}

export interface MobileAIActionResult {
  changedNoteIds: string[];
  message: string;
}

function nonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function parseAction(value: unknown): MobileAIAction | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Record<string, unknown>;
  if (candidate.action === "create_note") {
    const title = nonEmptyString(candidate.title);
    if (!title || typeof candidate.body !== "string") return null;
    const type = candidate.type === undefined
      ? undefined
      : Array.isArray(candidate.type) && candidate.type.length <= 3 && candidate.type.every((part) => {
        const segment = nonEmptyString(part);
        return Boolean(segment) && !/[\\/]/.test(segment!) && segment !== "." && segment !== "..";
      })
        ? candidate.type.map((part) => String(part).trim()).slice(0, 3)
        : null;
    if (type === null) return null;
    return { action: "create_note", title, body: candidate.body, type };
  }
  if (candidate.action === "set_note_body") {
    const noteId = nonEmptyString(candidate.noteId);
    const revision = nonEmptyString(candidate.revision);
    if (!noteId || !revision || typeof candidate.body !== "string") return null;
    return { action: "set_note_body", noteId, revision, body: candidate.body };
  }
  if (candidate.action === "append_note") {
    const noteId = nonEmptyString(candidate.noteId);
    const revision = nonEmptyString(candidate.revision);
    const text = nonEmptyString(candidate.text);
    if (!noteId || !revision || !text) return null;
    return { action: "append_note", noteId, revision, text };
  }
  if (candidate.action === "replace_note_text") {
    const noteId = nonEmptyString(candidate.noteId);
    const revision = nonEmptyString(candidate.revision);
    const oldText = nonEmptyString(candidate.oldText);
    if (!noteId || !revision || !oldText || typeof candidate.newText !== "string") return null;
    return { action: "replace_note_text", noteId, revision, oldText, newText: candidate.newText };
  }
  return null;
}

/** Extracts the deliberately narrow mutation protocol from otherwise normal prose. */
export function parseMobileAIActions(raw: string): ParsedMobileAIActions {
  const actions: MobileAIAction[] = [];
  let malformed = false;
  for (const match of raw.matchAll(ACTION_BLOCK)) {
    try {
      const action = parseAction(JSON.parse(match[1]));
      if (action) actions.push(action);
      else malformed = true;
    } catch {
      malformed = true;
    }
  }
  const visibleText = raw.replace(ACTION_BLOCK, "").trim();
  if (/<\/?zerus-action\b/i.test(visibleText)) malformed = true;
  return { actions, visibleText, malformed };
}

/** A second, deterministic authorization check in addition to the model prompt. */
export function questionRequestsNoteMutation(question: string, referencedTitles: string[] = []): boolean {
  const plain = question.trim().toLowerCase();
  const request = /^(?:(?:please|kindly)\s+|(?:can|could|would|will)\s+you\s+)*(?:create|make|start|write|edit|update|change|rewrite|replace|append|add|insert)\b/;
  const namesReferencedNote = referencedTitles.some((title) =>
    title.trim().length > 1 && plain.includes(title.trim().toLowerCase()));
  return request.test(plain) && (/\b(?:note|entry)\b/.test(plain) || namesReferencedNote);
}

function editableNote(notes: Note[], id: string): Note {
  const note = notes.find((candidate) => candidate.id === id);
  if (!note) throw new Error("The note no longer exists.");
  if (isExternalNote(note) || isTrashed(note) || note.archived) {
    throw new Error(`“${noteTitle(note)}” cannot be edited from chat.`);
  }
  return note;
}

function assertCurrentRevision(note: Note, revision: string) {
  if (chatContentRevision(note.content) !== revision) {
    throw new Error(`“${noteTitle(note)}” changed after the AI read it. Ask it to try again with the latest version.`);
  }
}

function titledBody(title: string, body: string): string {
  const cleanTitle = title.replace(/[\r\n]+/g, " ").trim();
  const cleanBody = body.trim();
  return `# ${cleanTitle}${cleanBody ? `\n\n${cleanBody}\n` : "\n"}`;
}

export async function executeMobileAIActions(
  actions: MobileAIAction[],
  operations: {
    getNotes: () => Note[];
    createNote: (type: string[], content: string) => Promise<Note | null>;
    updateNoteBody: (id: string, body: string) => void;
  },
): Promise<MobileAIActionResult> {
  if (actions.length > 3) throw new Error("The AI requested too many note changes at once.");
  const editedIds = actions
    .filter((action): action is Exclude<MobileAIAction, { action: "create_note" }> => action.action !== "create_note")
    .map((action) => action.noteId);
  if (new Set(editedIds).size !== editedIds.length) {
    throw new Error("The AI requested multiple changes to the same note. Ask it to make one change at a time.");
  }
  for (const action of actions) {
    if (action.action === "create_note") continue;
    const note = editableNote(operations.getNotes(), action.noteId);
    assertCurrentRevision(note, action.revision);
  }

  const changedNoteIds: string[] = [];
  const summaries: string[] = [];
  for (const action of actions) {
    if (action.action === "create_note") {
      const created = await operations.createNote(
        action.type?.length ? action.type : DEFAULT_TYPE,
        titledBody(action.title, action.body),
      );
      if (!created) throw new Error(`Could not create “${action.title}”.`);
      changedNoteIds.push(created.id);
      summaries.push(`Created “${noteTitle(created)}”.`);
      continue;
    }

    const note = editableNote(operations.getNotes(), action.noteId);
    if (action.action === "set_note_body") {
      operations.updateNoteBody(note.id, titledBody(noteTitle(note), action.body));
      summaries.push(`Updated “${noteTitle(note)}”.`);
    } else if (action.action === "append_note") {
      const currentBody = noteBody(note.content).trimEnd();
      operations.updateNoteBody(note.id, `${currentBody}${currentBody ? "\n\n" : ""}${action.text.trim()}\n`);
      summaries.push(`Added to “${noteTitle(note)}”.`);
    } else {
      const currentBody = noteBody(note.content);
      const first = currentBody.indexOf(action.oldText);
      const last = currentBody.lastIndexOf(action.oldText);
      if (first < 0) throw new Error(`The text to change was not found in “${noteTitle(note)}”.`);
      if (first !== last) throw new Error(`The text to change is not unique in “${noteTitle(note)}”.`);
      operations.updateNoteBody(
        note.id,
        `${currentBody.slice(0, first)}${action.newText}${currentBody.slice(first + action.oldText.length)}`,
      );
      summaries.push(`Updated “${noteTitle(note)}”.`);
    }
    changedNoteIds.push(note.id);
  }
  return { changedNoteIds, message: summaries.join(" ") };
}
