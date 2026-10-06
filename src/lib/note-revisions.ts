import { fromMarkdown } from "mdast-util-from-markdown";
import { getNoteProperties, noteBody, setContentProperty, withBody } from "@/lib/frontmatter";
import { ATTACHMENTS_PROPERTY, getNoteAttachments, setNoteAttachments } from "@/lib/note-attachments";
import { FILE_HUB_KEYS, getFileHubReference, normalizeRelativeFilePath, setFileHubReference } from "@/lib/file-hubs";
import { isExternalNote, isTrashed, type Note } from "@/lib/note-utils";
import type { VaultBackend } from "@/lib/vault/backend";

const ROOT = ".zerus/revisions";
export const REVISION_TRANSACTION_KEY = "zerus-revision-transaction";
const FILE_KEYS = [...Object.values(FILE_HUB_KEYS), ATTACHMENTS_PROPERTY];

export interface NoteRevision {
  id: string;
  number: number;
  createdAt: string;
  /** Frozen content. The current revision always reads from the live Markdown note. */
  content: string;
  deletedAt?: string;
}

export interface NoteRevisions {
  schema: 1;
  noteId: string;
  currentId: string;
  nextNumber: number;
  commitToken?: string;
  revisions: NoteRevision[];
  /** Managed originals superseded by revision copies; collect only after explicit Trash emptying. */
  ownedFiles?: string[];
}

export type RevisionAction =
  | { kind: "create" }
  | { kind: "promote" | "trash" | "restore"; revisionId: string };

function noteRoot(id: string): string {
  if (!/^[a-zA-Z0-9_-]+$/.test(id)) throw new Error("Invalid note identity for revisions.");
  return `${ROOT}/notes/${id}`;
}

function indexPath(id: string): string { return `${noteRoot(id)}/index.json`; }
function pendingPath(id: string): string { return `${noteRoot(id)}/pending.json`; }

function initialRevisions(note: Note): NoteRevisions {
  return {
    schema: 1, noteId: note.id, currentId: "initial", nextNumber: 2,
    revisions: [{ id: "initial", number: 1, createdAt: note.createdAt ?? note.updatedAt, content: note.content }],
  };
}

function parseRevisions(text: string, noteId: string): NoteRevisions {
  const value = JSON.parse(text) as NoteRevisions;
  if (value.schema !== 1 || value.noteId !== noteId || !Array.isArray(value.revisions) ||
      !Number.isInteger(value.nextNumber) || value.nextNumber < 2 ||
      !value.revisions.every((r) => typeof r.id === "string" && Number.isInteger(r.number) &&
        r.number > 0 && typeof r.content === "string" && typeof r.createdAt === "string" &&
        Number.isFinite(Date.parse(r.createdAt))) ||
      new Set(value.revisions.map((r) => r.id)).size !== value.revisions.length ||
      new Set(value.revisions.map((r) => r.number)).size !== value.revisions.length ||
      value.revisions.some((r) => r.number >= value.nextNumber) ||
      (value.ownedFiles !== undefined && (!Array.isArray(value.ownedFiles) ||
        !value.ownedFiles.every((path) => typeof path === "string" && normalizeRelativeFilePath(path)))) ||
      !value.revisions.some((r) => r.id === value.currentId && !r.deletedAt)) {
    throw new Error("This note's revision data is incomplete. Restore its revision folder before making changes.");
  }
  return value;
}

interface PendingRevision {
  token: string;
  before: string;
  after: string;
  previous: NoteRevisions;
  next: NoteRevisions;
}

/** Finish or roll back an interrupted two-file commit, without guessing over an external edit. */
async function recoverPending(backend: VaultBackend, note: Note): Promise<void> {
  if (!(await backend.exists(pendingPath(note.id)))) return;
  const pending = JSON.parse(await backend.readText(pendingPath(note.id))) as PendingRevision;
  const disk = await backend.readText(note.path);
  if (getNoteProperties(disk)[REVISION_TRANSACTION_KEY] === pending.token) {
    parseRevisions(JSON.stringify(pending.next), note.id);
    await backend.write(indexPath(note.id), JSON.stringify(pending.next));
  } else if (disk === pending.before) {
    parseRevisions(JSON.stringify(pending.previous), note.id);
    await backend.write(indexPath(note.id), JSON.stringify(pending.previous));
  } else {
    throw new Error("A revision change was interrupted and the note changed elsewhere. Your saved revision data has been retained; resolve the note before continuing.");
  }
  await backend.removeFile(pendingPath(note.id));
}

export async function readNoteRevisions(backend: VaultBackend, note: Note): Promise<NoteRevisions> {
  if (isExternalNote(note)) throw new Error("Bring this note into the vault to use revisions.");
  await recoverPending(backend, note);
  const path = indexPath(note.id);
  const token = getNoteProperties(note.content)[REVISION_TRANSACTION_KEY];
  if (!(await backend.exists(path))) {
    if (token) throw new Error("This note's revision folder has not arrived. Sync or restore .zerus/revisions before changing revisions.");
    return initialRevisions(note);
  }
  const document = parseRevisions(await backend.readText(path), note.id);
  if (document.commitToken && document.commitToken !== token) {
    throw new Error("The note and its revisions are still syncing. Wait for both to finish, then retry.");
  }
  return document;
}

/** Note-level properties and the first body line (the title) always come from today's note. */
export function revisionContent(revision: NoteRevision, note: Note): string {
  let body = noteBody(revision.content);
  const title = noteBody(note.content).match(/^\s*\S[^\r\n]*/)?.[0].trim();
  if (title) body = /^\s*\S[^\r\n]*/.test(body)
    ? body.replace(/^\s*\S[^\r\n]*/, () => title)
    : `${title}\n\n${body}`;
  let content = withBody(note.content, body);
  const properties = getNoteProperties(revision.content);
  for (const key of FILE_KEYS) content = setContentProperty(content, key, properties[key] ?? null);
  return content;
}

interface PositionedLink {
  type: string;
  url?: string;
  children?: PositionedLink[];
  position?: { start: { offset?: number }; end: { offset?: number } };
}

/** Local Markdown files are links to other notes, not owned attachments. */
function localAssetPath(value: string): string | null {
  if (/^(?:file:|[a-z]:[\\/]|\/(?!\/))/i.test(value)) {
    throw new Error("Copy external file links into the vault before creating a revision.");
  }
  if (/^(?:[a-z][a-z0-9+.-]*:|#|\/\/)/i.test(value)) return null;
  const pathname = value.split(/[?#]/)[0];
  let path: string;
  try { path = decodeURIComponent(pathname); } catch { return null; }
  if (/\.(?:md|markdown)$/i.test(path)) return null;
  const normalized = normalizeRelativeFilePath(path);
  if (!normalized) throw new Error(`Use a vault-relative file link before creating a revision: ${value}`);
  return normalized;
}

function markdownAssets(body: string): Array<{ path: string; url: string; start: number; end: number }> {
  const result: ReturnType<typeof markdownAssets> = [];
  const visit = (node: PositionedLink) => {
    if (["image", "link", "definition"].includes(node.type) && node.url) {
      const path = localAssetPath(node.url);
      const start = node.position?.start.offset;
      const end = node.position?.end.offset;
      if (path && start !== undefined && end !== undefined) result.push({ path, url: node.url, start, end });
    }
    node.children?.forEach(visit);
  };
  visit(fromMarkdown(body) as PositionedLink);
  return result;
}

export function revisionFiles(content: string): Array<{ path: string; name: string }> {
  const hub = getFileHubReference(content);
  const files = [
    ...(hub?.kind === "vault" && hub.path ? [{ path: hub.path, name: hub.name }] : []),
    ...getNoteAttachments(content).flatMap((a) => a.path ? [{ path: a.path, name: a.name }] : []),
    ...markdownAssets(noteBody(content)).map((a) => ({ path: a.path, name: a.path.split("/").pop()! })),
  ];
  return files.filter((file, index) => files.findIndex((other) => other.path === file.path) === index);
}

/** Snapshot every vault-owned document, attachment, inline image, and ordinary file link. */
async function copyRevisionFiles(backend: VaultBackend, noteId: string, content: string, staged: string[]): Promise<string> {
  const hub = getFileHubReference(content);
  const attachments = getNoteAttachments(content);
  if (hub && hub.kind !== "vault" || attachments.some((a) => a.kind !== "vault")) {
    throw new Error("Copy linked external files into the vault before creating a revision.");
  }
  const directory = `${noteRoot(noteId)}/files/${crypto.randomUUID()}`;
  const copied = new Map<string, string>();
  const copy = async (source: string): Promise<string> => {
    const path = normalizeRelativeFilePath(source);
    if (!path) throw new Error(`Cannot preserve file outside the vault: ${source}`);
    const existing = copied.get(path);
    if (existing) return existing;
    let bytes: Uint8Array;
    try { bytes = await backend.readBinary(path); }
    catch { throw new Error(`Cannot preserve “${path}”. Restore the missing file before creating this revision.`); }
    const name = path.split("/").pop()!.replace(/^(?:\d+-)+/, "").replace(/[^a-zA-Z0-9._-]/g, "_");
    const destination = `${directory}/${copied.size}-${name}`;
    staged.push(destination);
    await backend.writeBinary(destination, bytes);
    copied.set(path, destination);
    return destination;
  };
  let next = content;
  if (hub?.path) next = setFileHubReference(next, { ...hub, path: await copy(hub.path), managed: false });
  const savedAttachments = [];
  for (const attachment of attachments) {
    savedAttachments.push({ ...attachment, path: await copy(attachment.path!), managed: false });
  }
  next = setNoteAttachments(next, savedAttachments);
  let body = noteBody(next);
  for (const reference of markdownAssets(body).reverse()) {
    const destination = await copy(reference.path);
    const suffix = reference.url.slice(reference.url.split(/[?#]/)[0].length);
    const source = body.slice(reference.start, reference.end);
    // The parser supplies decoded destinations; also handle escaped spaces/parentheses.
    const escaped = reference.url.replace(/[() ]/g, (character) => `\\${character}`);
    const at = source.lastIndexOf(reference.url);
    const original = at >= 0 ? reference.url : escaped;
    const offset = at >= 0 ? at : source.lastIndexOf(escaped);
    if (offset < 0) throw new Error(`Cannot preserve file link: ${reference.url}`);
    body = body.slice(0, reference.start + offset) + destination + suffix +
      body.slice(reference.start + offset + original.length);
  }
  return withBody(next, body);
}

/** The note and manifest share a recoverable commit. File copies finish before either changes. */
export async function changeNoteRevision(
  backend: VaultBackend, note: Note, action: RevisionAction,
): Promise<{ content: string; revisions: NoteRevisions }> {
  const staged: string[] = [];
  try { return await commitNoteRevision(backend, note, action, staged); }
  catch (error) {
    // Failed copies must not consume all remaining browser/cloud storage. A
    // pending or acknowledged commit still owns its files and must keep them.
    if (staged.length) {
      try {
        if (!(await backend.exists(pendingPath(note.id))) && await backend.readText(note.path) === note.content) {
          for (const path of staged) {
            if (await backend.exists(path)) await backend.removeFile(path);
          }
        }
      } catch { /* A later explicit Trash cleanup can collect orphaned copies. */ }
    }
    throw error;
  }
}

async function commitNoteRevision(
  backend: VaultBackend, note: Note, action: RevisionAction, staged: string[],
): Promise<{ content: string; revisions: NoteRevisions }> {
  if (isTrashed(note)) throw new Error("Restore this note from Trash before changing its revisions.");
  const previous = await readNoteRevisions(backend, note);
  const baseline = await backend.exists(indexPath(note.id)) ? await backend.readText(indexPath(note.id)) : null;
  const next: NoteRevisions = structuredClone(previous);
  const ownedHub = getFileHubReference(note.content);
  next.ownedFiles = [...new Set([
    ...(previous.ownedFiles ?? []),
    ...(ownedHub?.managed && ownedHub.kind === "vault" && ownedHub.path ? [ownedHub.path] : []),
    ...getNoteAttachments(note).flatMap((a) => a.managed && a.kind === "vault" && a.path ? [a.path] : []),
  ])];
  const current = next.revisions.find((r) => r.id === next.currentId)!;
  const target = "revisionId" in action ? next.revisions.find((r) => r.id === action.revisionId) : current;
  if (!target) throw new Error("This revision is no longer available.");
  let content = note.content;
  if (action.kind === "create" || action.kind === "promote") {
    if (target.deletedAt) throw new Error("Restore this revision from Trash first.");
    current.content = await copyRevisionFiles(backend, note.id, note.content, staged);
    const source = action.kind === "create" ? current : target;
    content = await copyRevisionFiles(backend, note.id, revisionContent(source, note), staged);
    const revision: NoteRevision = {
      id: crypto.randomUUID(), number: next.nextNumber++, createdAt: new Date().toISOString(), content,
    };
    next.revisions.push(revision);
    next.currentId = revision.id;
  } else if (action.kind === "trash") {
    if (target.deletedAt) throw new Error("This revision is already in Trash.");
    const remaining = next.revisions.filter((r) => !r.deletedAt && r.id !== target.id);
    if (!remaining.length) throw new Error("Deleting the only revision requires moving the whole note to Trash.");
    if (target.id === next.currentId) {
      target.content = await copyRevisionFiles(backend, note.id, note.content, staged);
      const latest = remaining.sort((a, b) => b.number - a.number)[0];
      content = await copyRevisionFiles(backend, note.id, revisionContent(latest, note), staged);
      next.currentId = latest.id;
    }
    target.deletedAt = new Date().toISOString();
  } else {
    if (!target.deletedAt) throw new Error("This revision is not in Trash.");
    delete target.deletedAt;
  }
  const token = crypto.randomUUID();
  next.commitToken = token;
  content = setContentProperty(content, REVISION_TRANSACTION_KEY, token);
  const disk = await backend.readText(note.path);
  const latestIndex = await backend.exists(indexPath(note.id)) ? await backend.readText(indexPath(note.id)) : null;
  if (disk !== note.content || latestIndex !== baseline) {
    throw new Error("This note or its revisions changed elsewhere. Refresh it before trying again.");
  }
  const pending: PendingRevision = { token, before: note.content, after: content, previous, next };
  await backend.writeNew(pendingPath(note.id), JSON.stringify(pending));
  try {
    await backend.write(note.path, content);
    await backend.write(indexPath(note.id), JSON.stringify(next));
    await backend.removeFile(pendingPath(note.id));
  } catch (error) {
    // Recover according to the actual disk result, including writes whose acknowledgement failed.
    await recoverPending(backend, note);
    if (getNoteProperties(await backend.readText(note.path))[REVISION_TRANSACTION_KEY] !== token) throw error;
  }
  return { content, revisions: next };
}

export interface TrashedNoteRevision {
  noteId: string;
  revision: NoteRevision;
}

export async function listTrashedRevisions(backend: VaultBackend): Promise<TrashedNoteRevision[]> {
  const result: TrashedNoteRevision[] = [];
  for (const path of await backend.listFiles(`${ROOT}/notes`)) {
    const match = path.match(/\/notes\/([^/]+)\/index\.json$/);
    if (!match) continue;
    const document = parseRevisions(await backend.readText(path), match[1]);
    for (const revision of document.revisions) {
      if (revision.deletedAt) result.push({ noteId: document.noteId, revision });
    }
  }
  return result.sort((a, b) => b.revision.deletedAt!.localeCompare(a.revision.deletedAt!));
}

/** Remove metadata first; collect only files no surviving note or revision refers to. */
export async function purgeRevisionTrash(backend: VaultBackend, deletedNoteIds: ReadonlySet<string>, emptyAll = true): Promise<void> {
  const paths = await backend.listFiles(`${ROOT}/notes`);
  const candidates = new Set(paths.filter((p) => p.includes("/files/")));
  const retained: string[] = (await backend.loadAll()).map((file) => file.content);
  for (const path of await backend.listFiles(".zerus/links")) {
    if (path.endsWith(".md")) retained.push(await backend.readText(path));
  }
  for (const path of paths.filter((p) => p.endsWith("/pending.json"))) {
    const noteId = path.match(/\/notes\/([^/]+)\/pending\.json$/)?.[1];
    if (noteId && deletedNoteIds.has(noteId)) {
      await backend.removeFile(path);
      continue;
    }
    // Do not collect assets belonging to a commit awaiting recovery.
    retained.push(await backend.readText(path));
  }
  for (const path of paths) {
    const match = path.match(/\/notes\/([^/]+)\/index\.json$/);
    if (!match) continue;
    const document = parseRevisions(await backend.readText(path), match[1]);
    for (const file of document.ownedFiles ?? []) candidates.add(file);
    if (deletedNoteIds.has(match[1])) {
      await backend.removeFile(path);
      continue;
    }
    if (emptyAll) {
      document.revisions = document.revisions.filter((r) => !r.deletedAt);
      await backend.write(path, JSON.stringify(document));
    }
    retained.push(...document.revisions.filter((r) => r.id !== document.currentId).map((r) => r.content));
  }
  for (const path of candidates) {
    if (!retained.some((content) => content.includes(path) || content.includes(encodeURI(path))) && await backend.exists(path)) {
      await backend.removeFile(path);
    }
  }
}
