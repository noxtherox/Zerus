import { noteBody } from "@/lib/frontmatter";
import { isTrashed, noteTitle, type Note } from "@/lib/note-utils";

export type LinkOption = "note" | "web";
const KEY = "zerus.editor.linkOption";

export function loadLinkOption(): LinkOption {
  try { return localStorage.getItem(KEY) === "web" ? "web" : "note"; }
  catch { return "note"; }
}

export function saveLinkOption(option: LinkOption) {
  try { localStorage.setItem(KEY, option); } catch { /* Storage may be unavailable. */ }
}

export function searchLinkNotes(notes: Note[], query: string): Note[] {
  const terms = query.toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);
  return notes.filter((note) => !isTrashed(note) && !note.externalPath &&
    terms.every((term) => `${noteTitle(note)} ${note.path}`.toLocaleLowerCase().includes(term)))
    .sort((a, b) => noteTitle(a).localeCompare(noteTitle(b)));
}

export function linkedNoteExcerpt(note: Note): string {
  return noteBody(note.content).split("\n").filter((line) => line.trim())
    .filter((line, index) => index !== 0 || line.replace(/^#+\s*/, "").trim() !== noteTitle(note))
    .join(" ").replace(/\[\[([^\]]+)\]\]/g, (_, ref: string) => ref.split("|").pop() ?? ref)
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/[#*_`>]/g, "").replace(/\s+/g, " ").trim().slice(0, 200);
}
