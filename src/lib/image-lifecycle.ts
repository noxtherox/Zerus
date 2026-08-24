import { IMAGE_MD_REGEX } from "./note-utils";
import type {
  VaultBackend,
  VaultFileEntry,
} from "./vault/backend";

interface NoteContent {
  id: string;
  content: string;
}

/** Prevents two image filesystem/index mutations from clobbering each other. */
export function createImageMutationQueue() {
  let tail: Promise<void> = Promise.resolve();
  return function run<T>(operation: () => Promise<T>): Promise<T> {
    const result = tail.then(operation, operation);
    tail = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  };
}

export function imageReferenceCount(content: string, path: string): number {
  const regex = new RegExp(IMAGE_MD_REGEX.source, "g");
  let count = 0;
  for (const match of content.matchAll(regex)) {
    if (match[2] === path) count += 1;
  }
  return count;
}

export function loadedNotesShareImage(
  notes: readonly NoteContent[],
  noteId: string,
  path: string,
): boolean {
  return notes.some((note) =>
    note.id === noteId
      ? imageReferenceCount(note.content, path) > 1
      : imageReferenceCount(note.content, path) > 0,
  );
}

/**
 * Checks notes omitted by a paginated backend. Trash entries are deliberately
 * included: restoring one must not reveal that its image was deleted.
 */
export async function unloadedNotesReferenceImage(
  source: Pick<VaultBackend, "loadFiles">,
  entries: readonly VaultFileEntry[],
  loadedPaths: ReadonlySet<string>,
  path: string,
  batchSize = 30,
): Promise<boolean> {
  if (!source.loadFiles) return false;
  const unloadedPaths = entries
    .map((entry) => entry.path)
    .filter((entryPath) => !loadedPaths.has(entryPath));

  for (let offset = 0; offset < unloadedPaths.length; offset += batchSize) {
    const files = await source.loadFiles(
      unloadedPaths.slice(offset, offset + batchSize),
    );
    if (files.some((file) => imageReferenceCount(file.content, path) > 0)) {
      return true;
    }
  }
  return false;
}

/**
 * Commits a filesystem move and its metadata update as one logical operation.
 * A failed metadata write moves the file back before surfacing the error.
 */
export async function moveImageWithRollback(
  source: Pick<VaultBackend, "move">,
  from: string,
  to: string,
  commit: () => Promise<void>,
): Promise<void> {
  await source.move(from, to);
  try {
    await commit();
  } catch (commitError) {
    try {
      await source.move(to, from);
    } catch (rollbackError) {
      throw Object.assign(
        new Error(
          "Image metadata failed and the file move could not be rolled back.",
        ),
        { commitError, rollbackError },
      );
    }
    throw commitError;
  }
}
