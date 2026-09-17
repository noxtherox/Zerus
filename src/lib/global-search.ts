import { WIKILINK_REGEX, parseNoteReference } from "./wikilinks";
import { getNoteProperties, noteBody } from "./frontmatter";
import { getFileHubReference } from "./file-hubs";
import {
  isExternalNote,
  isSavedLinkNote,
  isTrashed,
  noteTitle,
  noteTypePath,
  type Note,
} from "./note-utils";
import type { Task } from "./tasks";
import type { ChatConversation } from "./mobile-chat-history";
import type { ChatDocument } from "./chat-documents";

export type SearchCollection =
  "notes" | "external" | "files" | "links" | "tasks" | "chats";
export interface SearchItem {
  key: string;
  id: string;
  collection: SearchCollection;
  title: string;
  text: string;
  location: string;
  updatedAt: string;
  archived: boolean;
  properties: Record<string, unknown>;
  note?: Note;
  task?: Task;
  chat?: ChatConversation;
}
export interface SearchFilters {
  collection: SearchCollection | "all";
  days: string;
  archived: boolean;
  type: string;
  property: string;
  value: string;
  status: string;
  priority: string;
}
export const EMPTY_SEARCH_FILTERS: SearchFilters = {
  collection: "all",
  days: "",
  archived: false,
  type: "",
  property: "",
  value: "",
  status: "",
  priority: "",
};
export const COLLECTION_LABELS: Record<SearchCollection | "all", string> = {
  all: "Everything",
  notes: "Notes",
  external: "External notes",
  files: "Files",
  links: "Saved links",
  tasks: "Tasks",
  chats: "AI conversations",
};
export interface SearchChatRequest {
  id: string;
  query?: string;
  noteIds?: string[];
  document?: ChatDocument;
  conversation?: ChatConversation;
}
export function searchChatRequest(
  query: string,
  item?: SearchItem,
): SearchChatRequest {
  return {
    id: crypto.randomUUID(),
    query,
    noteIds: item?.note ? [item.id] : [],
    document:
      item && !item.note ? { name: item.title, text: item.text } : undefined,
  };
}
export function buildSearchItems(
  notes: Note[],
  tasks: Task[],
  chats: ChatConversation[],
): SearchItem[] {
  return [
    ...notes
      .filter((note) => !isTrashed(note))
      .map((note): SearchItem => {
        const collection = isExternalNote(note)
          ? "external"
          : getFileHubReference(note)
            ? "files"
            : isSavedLinkNote(note)
              ? "links"
              : "notes";
        return {
          key: `note:${note.id}`,
          id: note.id,
          collection,
          title: noteTitle(note),
          text: note.content,
          location: note.externalPath ?? noteTypePath(note).join(" / "),
          updatedAt: note.updatedAt,
          archived: !!note.archived,
          properties: getNoteProperties(note.content),
          note,
        };
      }),
    ...tasks.map((task): SearchItem => ({
      key: `task:${task.id}`,
      id: task.id,
      collection: "tasks",
      title: task.title,
      text: [
        task.title,
        task.category,
        task.priority,
        task.dueDate,
        task.completed ? "Completed" : "Open",
      ]
        .filter(Boolean)
        .join("\n"),
      location: task.category ?? "Tasks",
      updatedAt: task.updatedAt ?? task.completedAt ?? task.createdAt,
      archived: false,
      properties: {},
      task,
    })),
    ...chats
      .filter((chat) => !chat.deletedAt)
      .map((chat): SearchItem => ({
        key: `chat:${chat.id}`,
        id: chat.id,
        collection: "chats",
        title: chat.title,
        text: chat.messages
          .map((message) => `${message.role}: ${message.text}`)
          .join("\n\n"),
        location: "AI conversations",
        updatedAt: chat.updatedAt,
        archived: !!chat.archivedAt,
        properties: {},
        chat,
      })),
  ];
}
const normalize = (text: string) =>
  text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
// A single insertion, deletion, substitution or adjacent transposition; short words must match exactly.
function nearWord(a: string, b: string): boolean {
  if (a === b) return true;
  if (a.length < 4 || Math.abs(a.length - b.length) > 1) return false;
  let i = 0;
  while (i < a.length && a[i] === b[i]) i++;
  if (a.length === b.length)
    return (
      a.slice(i + 1) === b.slice(i + 1) ||
      (a[i] === b[i + 1] &&
        a[i + 1] === b[i] &&
        a.slice(i + 2) === b.slice(i + 2))
    );
  return a.length > b.length
    ? a.slice(i + 1) === b.slice(i)
    : a.slice(i) === b.slice(i + 1);
}
export function searchScore(item: SearchItem, query: string): number {
  const q = normalize(query.trim());
  if (!q) return 1;
  const title = normalize(item.title);
  if (title === q) return 600;
  if (title.startsWith(q)) return 550;
  if (title.includes(q)) return 500;
  const tokens = q.split(/\s+/);
  if (tokens.every((token) => title.includes(token))) return 450;
  const text = normalize(
    `${item.text}\n${item.location}\n${item.note?.path ?? ""}`,
  );
  if (tokens.every((token) => `${title}\n${text}`.includes(token))) return 300;
  const words = title.split(/[^\p{L}\p{N}]+/u);
  if (
    tokens.every((token) =>
      words.some((word) => word.includes(token) || nearWord(token, word)),
    )
  )
    return 150;
  const allWords = `${title}\n${text}`.split(/[^\p{L}\p{N}]+/u);
  return tokens.every((token) =>
    allWords.some((word) => word.includes(token) || nearWord(token, word)),
  )
    ? 100
    : 0;
}
export function filterSearchItems(
  items: SearchItem[],
  query: string,
  filters: SearchFilters,
  now = Date.now(),
): SearchItem[] {
  return items
    .filter((item) => {
      if (
        filters.collection !== "all" &&
        item.collection !== filters.collection
      )
        return false;
      if (item.archived && !filters.archived) return false;
      if (
        filters.days &&
        !(Date.parse(item.updatedAt) >= now - Number(filters.days) * 86400000)
      )
        return false;
      if (filters.type && item.location !== filters.type) return false;
      if (
        filters.property &&
        (!Object.prototype.hasOwnProperty.call(
          item.properties,
          filters.property,
        ) ||
          (filters.value &&
            ![item.properties[filters.property]]
              .flat()
              .some(
                (value) =>
                  normalize(String(value)) === normalize(filters.value),
              )))
      )
        return false;
      if (
        filters.status &&
        (!item.task || item.task.completed !== (filters.status === "completed"))
      )
        return false;
      if (filters.priority && item.task?.priority !== filters.priority)
        return false;
      return true;
    })
    .map((item) => ({ item, score: searchScore(item, query) }))
    .filter((result) => result.score > 0)
    .sort(
      (a, b) =>
        b.score - a.score ||
        b.item.updatedAt.localeCompare(a.item.updatedAt) ||
        a.item.key.localeCompare(b.item.key),
    )
    .map((result) => result.item);
}
export function searchPreviewText(item: SearchItem): string {
  if (!item.note) return item.text;
  return noteBody(item.text)
    .replace(/^\s*# [^\n]*\n?/, "")
    .replace(
      WIKILINK_REGEX,
      (_, reference: string) => parseNoteReference(reference).label,
    )
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .trim();
}
export function searchExcerpt(item: SearchItem, query: string): string {
  const text = searchPreviewText(item);
  const token = query
    .trim()
    .split(/\s+/)
    .find((word) => normalize(text).includes(normalize(word)));
  const at = token ? normalize(text).indexOf(normalize(token)) : 0;
  const start = Math.max(0, at - 60);
  const excerpt = text
    .slice(start, start + 240)
    .replace(/\s+/g, " ")
    .trim();
  const properties = Object.entries(item.properties).filter(
    ([key, value]) =>
      !key.startsWith("zerus-") &&
      query.trim() &&
      normalize(`${key} ${String(value)}`).includes(normalize(query.trim())),
  );
  return properties.length
    ? properties.map(([key, value]) => `${key}: ${String(value)}`).join(" · ")
    : `${start ? "…" : ""}${excerpt}`;
}

const recentItems = new Map<string, string[]>();
export function recordSearchVisit(vault: string | null, key: string) {
  const scope = vault ?? "browser";
  recentItems.set(
    scope,
    [key, ...(recentItems.get(scope) ?? []).filter((id) => id !== key)].slice(
      0,
      50,
    ),
  );
}
export function recentSearchItems(vault: string | null): string[] {
  return recentItems.get(vault ?? "browser") ?? [];
}
