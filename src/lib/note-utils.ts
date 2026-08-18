import { getNoteProperties, noteBody } from "@/lib/frontmatter";

export const TRASH_DIR = ".trash";
export const MAX_TYPE_DEPTH = 3;
export const DEFAULT_TYPE: string[] = ["inbox"];

/**
 * A note is a markdown file inside the vault. `path` is its vault-relative
 * path (forward slashes); the folders it sits in are its type hierarchy:
 * type / sub-type / sub-sub-type. Trashed notes keep their original relative
 * path under `.trash/`.
 */
export interface Note {
  id: string; // stable for the session; the path may change on rename/move
  path: string;
  /** Absolute source path when the note is open outside the vault. */
  externalPath?: string;
  content: string;
  pinned: boolean;
  /** Zerus-only visibility state; archived notes remain in place on disk. */
  archived?: boolean;
  updatedAt: string;
}

export const WIKILINK_REGEX = /\[\[([^[\]]+)\]\]/g;

/**
 * Markdown image: `![alt](path)`. An optional `|width` suffix in the alt text
 * (`![screenshot|320](assets/foo.png)`) sets the preview width in pixels —
 * the same convention Obsidian uses.
 */
export const IMAGE_MD_REGEX = /!\[([^\]]*)\]\(([^()\s]+)\)/g;

export function isExternalNote(note: Note): boolean {
  return !!note.externalPath;
}

/** A saved web link is app-managed until it is explicitly moved into a type. */
export function isSavedLinkNote(note: Note): boolean {
  const properties = getNoteProperties(note.content);
  return (
    typeof properties["zerus-link-id"] === "string" &&
    typeof properties["zerus-link-url"] === "string"
  );
}

/** Normalizes separators and Windows casing for reliable path comparisons. */
export function normalizeFsPath(path: string): string {
  const withSlashes = path.replace(/\\/g, "/");
  const isUnc = withSlashes.startsWith("//");
  let normalized = withSlashes.replace(/\/{2,}/g, "/").replace(/\/$/, "");
  if (isUnc) normalized = `/${normalized}`;
  const looksWindows =
    isUnc || /^[a-z]:\//i.test(normalized) || path.includes("\\");
  return looksWindows ? normalized.toLowerCase() : normalized;
}

/** Absolute filesystem path when available (desktop only). */
export function noteAbsolutePath(
  note: Note,
  vaultLocation: string | null,
): string | null {
  if (note.externalPath) return note.externalPath;
  if (!vaultLocation) return null;
  return `${vaultLocation.replace(/[\\/]$/, "")}/${note.path}`;
}

/** Absolute folder containing a note, when local filesystem access exists. */
export function noteContainingFolder(
  note: Note,
  vaultLocation: string | null,
): string | null {
  const absolutePath = noteAbsolutePath(note, vaultLocation);
  if (!absolutePath) return null;
  const normalized = absolutePath.replace(/\\/g, "/");
  const separator = normalized.lastIndexOf("/");
  if (separator < 0) return null;
  const folder = normalized.slice(0, separator);
  if (/^[a-z]:$/i.test(folder)) return `${folder}/`;
  return folder || "/";
}

export function isRemoteUrl(path: string): boolean {
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(path);
}

/** Splits `alt|320` into the plain alt text and the width, if present. */
export function parseImageAlt(alt: string): {
  alt: string;
  width: number | null;
} {
  const match = alt.match(/^(.*?)\|(\d+)$/);
  if (!match) return { alt, width: null };
  return { alt: match[1], width: parseInt(match[2], 10) };
}

export function formatImageMarkdown(
  alt: string,
  width: number | null,
  path: string,
): string {
  return `![${width ? `${alt}|${width}` : alt}](${path})`;
}

/** The first Markdown image in the note body, for compact note previews. */
export function firstNoteImage(content: string): {
  path: string;
  alt: string;
} | null {
  for (const match of noteBody(content).matchAll(IMAGE_MD_REGEX)) {
    return { path: match[2], alt: parseImageAlt(match[1]).alt };
  }
  return null;
}

export function isTrashed(note: Note): boolean {
  return !isExternalNote(note) && note.path.startsWith(`${TRASH_DIR}/`);
}

export function isArchived(note: Note): boolean {
  return !isExternalNote(note) && note.archived === true;
}

/** Vault-relative path ignoring the .trash prefix. */
export function logicalPath(note: Note): string {
  return isTrashed(note) ? note.path.slice(TRASH_DIR.length + 1) : note.path;
}

/** Folder segments of the note, clamped to the max type depth. */
export function noteTypePath(note: Note): string[] {
  if (isExternalNote(note)) return [];
  const segments = logicalPath(note).split("/");
  return segments.slice(0, -1).slice(0, MAX_TYPE_DEPTH);
}

export function typeKey(typePath: string[]): string {
  return typePath.join("/");
}

/** Non-trashed notes of the given type, including its sub-types. */
export function notesOfTypeKey(notes: Note[], ownerKey: string): Note[] {
  return notes.filter((note) => {
    if (isExternalNote(note) || isSavedLinkNote(note) || isTrashed(note))
      return false;
    const key = typeKey(noteTypePath(note));
    return key === ownerKey || key.startsWith(`${ownerKey}/`);
  });
}

export function fileStem(path: string): string {
  const name = path.split(/[\\/]/).pop() ?? "";
  return name.replace(/\.md$/i, "");
}

/** Title = first non-empty body line (frontmatter excluded), else the filename. */
export function noteTitle(note: Note): string {
  const firstLine = noteBody(note.content)
    .split("\n")
    .map((line) => line.trim())
    .find((line) => line.length > 0);
  if (!firstLine) return fileStem(note.path) || "Untitled";
  return firstLine.replace(/^#{1,6}\s+/, "").trim() || "Untitled";
}

export function noteSnippet(note: Note): string {
  const lines = noteBody(note.content)
    .split("\n")
    .map((line) => line.trim());
  const firstIdx = lines.findIndex((line) => line.length > 0);
  const rest = lines
    .slice(firstIdx + 1)
    .filter((line) => line.length > 0)
    .join(" ")
    .replace(IMAGE_MD_REGEX, "")
    .replace(WIKILINK_REGEX, "$1")
    .replace(/[#*_`>]/g, "")
    .trim();
  return rest.slice(0, 120);
}

/** First image embedded in the note body, used by note-card previews. */
export function firstNoteImagePath(note: Note): string | null {
  const match = new RegExp(IMAGE_MD_REGEX).exec(noteBody(note.content));
  return match?.[2] ?? null;
}

export function getOutgoingLinkTitles(content: string): string[] {
  const titles: string[] = [];
  for (const match of noteBody(content).matchAll(WIKILINK_REGEX)) {
    titles.push(match[1].trim());
  }
  return titles;
}

export function findNoteByTitle(
  title: string,
  notes: Note[],
): Note | undefined {
  const needle = title.trim().toLowerCase();
  return notes.find(
    (note) =>
      !isExternalNote(note) &&
      !isSavedLinkNote(note) &&
      !isTrashed(note) &&
      noteTitle(note).toLowerCase() === needle,
  );
}

export interface TypeNode {
  name: string;
  path: string[];
  count: number; // notes in this type and all sub-types
  children: TypeNode[];
}

/**
 * Builds the type tree (max 3 levels) from non-trashed notes, plus
 * `extraTypePaths` — types that exist as folders but hold no notes yet.
 */
export function buildTypeTree(
  notes: Note[],
  extraTypePaths: string[][] = [],
  typeOrder: string[] = [],
): TypeNode[] {
  const roots: TypeNode[] = [];
  const ensureChild = (list: TypeNode[], name: string, path: string[]) => {
    let node = list.find((child) => child.name === name);
    if (!node) {
      node = { name, path, count: 0, children: [] };
      list.push(node);
      list.sort((a, b) => a.name.localeCompare(b.name));
    }
    return node;
  };
  const addPath = (typePath: string[], countDelta: number) => {
    let level = roots;
    for (let depth = 0; depth < typePath.length; depth++) {
      const node = ensureChild(
        level,
        typePath[depth],
        typePath.slice(0, depth + 1),
      );
      node.count += countDelta;
      level = node.children;
    }
  };
  for (const typePath of extraTypePaths) {
    addPath(typePath.slice(0, MAX_TYPE_DEPTH), 0);
  }
  for (const note of notes) {
    if (isExternalNote(note) || isSavedLinkNote(note) || isTrashed(note))
      continue;
    addPath(noteTypePath(note), 1);
  }
  if (typeOrder.length) {
    const positions = new Map(typeOrder.map((key, index) => [key, index]));
    const sortLevel = (nodes: TypeNode[]) => {
      nodes.sort((a, b) => {
        const aPosition = positions.get(typeKey(a.path));
        const bPosition = positions.get(typeKey(b.path));
        if (aPosition !== undefined && bPosition !== undefined) {
          return aPosition - bPosition;
        }
        if (aPosition !== undefined) return -1;
        if (bPosition !== undefined) return 1;
        return a.name.localeCompare(b.name);
      });
      nodes.forEach((node) => sortLevel(node.children));
    };
    sortLevel(roots);
  }
  return roots;
}

/** Builds a type tree from direct per-type counts without loaded note bodies. */
export function buildTypeTreeFromCounts(
  directCounts: Readonly<Record<string, number>>,
  extraTypePaths: string[][] = [],
): TypeNode[] {
  const roots: TypeNode[] = [];
  const ensureChild = (list: TypeNode[], name: string, path: string[]) => {
    let node = list.find((child) => child.name === name);
    if (!node) {
      node = { name, path, count: 0, children: [] };
      list.push(node);
      list.sort((a, b) => a.name.localeCompare(b.name));
    }
    return node;
  };
  const addPath = (typePath: string[], count: number) => {
    let level = roots;
    for (let depth = 0; depth < typePath.length; depth++) {
      const node = ensureChild(level, typePath[depth], typePath.slice(0, depth + 1));
      node.count += count;
      level = node.children;
    }
  };
  extraTypePaths.forEach((path) => addPath(path.slice(0, MAX_TYPE_DEPTH), 0));
  Object.entries(directCounts).forEach(([key, count]) => {
    if (key && count > 0) addPath(key.split("/").slice(0, MAX_TYPE_DEPTH), count);
  });
  return roots;
}

/** Returns a stable type order after moving one type before or after a sibling. */
export function reorderTypeTree(
  nodes: TypeNode[],
  sourceKey: string,
  targetKey: string,
  placement: "before" | "after",
): string[] | null {
  let moved = false;
  const visit = (level: TypeNode[]): TypeNode[] => {
    const sourceIndex = level.findIndex((node) => typeKey(node.path) === sourceKey);
    const targetIndex = level.findIndex((node) => typeKey(node.path) === targetKey);
    let ordered = level;
    if (sourceIndex >= 0 && targetIndex >= 0 && sourceIndex !== targetIndex) {
      ordered = [...level];
      const [source] = ordered.splice(sourceIndex, 1);
      const adjustedTarget = ordered.findIndex(
        (node) => typeKey(node.path) === targetKey,
      );
      ordered.splice(adjustedTarget + (placement === "after" ? 1 : 0), 0, source);
      moved = true;
    }
    return ordered.map((node) => ({ ...node, children: visit(node.children) }));
  };
  const reordered = visit(nodes);
  if (!moved) return null;
  const flatten = (level: TypeNode[]): string[] =>
    level.flatMap((node) => [typeKey(node.path), ...flatten(node.children)]);
  return flatten(reordered);
}

/** All distinct type paths in use, including intermediate levels. */
export function getAllTypePaths(
  notes: Note[],
  extraTypePaths: string[][] = [],
): string[][] {
  const seen = new Map<string, string[]>();
  const add = (typePath: string[]) => {
    const clamped = typePath.slice(0, MAX_TYPE_DEPTH);
    for (let depth = 1; depth <= clamped.length; depth++) {
      const prefix = clamped.slice(0, depth);
      seen.set(typeKey(prefix), prefix);
    }
  };
  for (const typePath of extraTypePaths) add(typePath);
  for (const note of notes) {
    if (!isExternalNote(note) && !isSavedLinkNote(note) && !isTrashed(note))
      add(noteTypePath(note));
  }
  return [...seen.values()].sort((a, b) =>
    typeKey(a).localeCompare(typeKey(b)),
  );
}

/** Normalizes user input like " Work / Sub Type " into a valid type path. */
export function parseTypePath(input: string): string[] {
  return input
    .split("/")
    .map((segment) =>
      segment
        .trim()
        .replace(/[\\:*?"<>|#[\]]/g, "")
        .replace(/\s+/g, " ")
        .trim(),
    )
    .filter(
      (segment) =>
        segment.length > 0 &&
        segment !== "." &&
        segment !== ".." &&
        segment.toLowerCase() !== TRASH_DIR,
    )
    .slice(0, MAX_TYPE_DEPTH);
}

/** A safe filename (without extension) derived from a note title. */
export function sanitizeFileStem(title: string): string {
  const stem = title
    .replace(/[/\\:*?"<>|#[\]]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\.+$/, "")
    .slice(0, 120)
    .trim();
  return stem || "Untitled";
}

export function noteMatchesSearch(note: Note, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  return (
    note.content.toLowerCase().includes(q) ||
    String(getNoteProperties(note.content)["zerus-file-name"] ?? "")
      .toLowerCase()
      .includes(q) ||
    note.externalPath?.toLowerCase().includes(q) ||
    typeKey(noteTypePath(note)).toLowerCase().includes(q) ||
    fileStem(note.path).toLowerCase().includes(q)
  );
}
