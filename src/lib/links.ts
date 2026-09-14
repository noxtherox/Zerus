import { getNoteProperties } from "@/lib/frontmatter";
import { effectiveProperties, type PropertySchemas } from "@/lib/properties";
import {
  type Note,
  getOutgoingLinkTitles,
  createNoteResolver,
  isArchived,
  isExternalNote,
  isTrashed,
  noteReferenceMatches,
  noteTypePath,
  notesOfTypeKey,
  typeKey,
} from "@/lib/note-utils";

/** Notes eligible to be added from a relation-property picker. */
export function getRelationPickerNotes(
  notes: Note[],
  currentNoteId: string,
  relationTypeKey?: string,
  includeArchived = false,
): Note[] {
  const relatedNotes = relationTypeKey
    ? notesOfTypeKey(notes, relationTypeKey)
    : notes.filter((note) => !isExternalNote(note) && !isTrashed(note));

  return relatedNotes.filter(
    (note) =>
      note.id !== currentNoteId && (includeArchived || !isArchived(note)),
  );
}

/** Titles referenced by this note's relation properties. */
export function getOutgoingRelationTitles(
  content: string,
  typePath: string[],
  schemas: PropertySchemas,
): string[] {
  const props = getNoteProperties(content);
  const titles: string[] = [];
  for (const def of effectiveProperties(typePath, schemas)) {
    if (def.type !== "relation") continue;
    const value = props[def.name];
    if (value == null) continue;
    for (const title of Array.isArray(value) ? value : [value]) {
      if (typeof title === "string" && title.trim()) titles.push(title.trim());
    }
  }
  return titles;
}

/** Whether `source` points to `target` through any relation property. */
export function hasRelationTo(
  source: Note,
  target: Note,
  schemas: PropertySchemas,
): boolean {
  return getOutgoingRelationTitles(
    source.content,
    noteTypePath(source),
    schemas,
  ).some((title) => noteReferenceMatches(title, target));
}

/** All titles this note links to: body wikilinks plus relation properties. */
export function getOutgoingTitles(
  note: Note,
  schemas: PropertySchemas,
): string[] {
  return [
    ...getOutgoingLinkTitles(note.content),
    ...getOutgoingRelationTitles(note.content, noteTypePath(note), schemas),
  ];
}

// Store updates replace edited Note objects; unchanged notes retain their identity.
// Weak keys release parsed links when a note or vault is replaced.
const bodyLinkCache = new WeakMap<Note, { content: string; links: string[] }>();
function cachedBodyLinks(note: Note): string[] {
  const cached = bodyLinkCache.get(note);
  if (cached?.content === note.content) return cached.links;
  const links = getOutgoingLinkTitles(note.content);
  bodyLinkCache.set(note, { content: note.content, links });
  return links;
}

/**
 * Notes that link to `target` — via body wikilinks or relation properties —
 * grouped by each linking note's type path.
 */
export function getBacklinksGroupedByType(
  target: Note,
  notes: Note[],
  schemas: PropertySchemas,
  includeArchived = false,
): Map<string, Note[]> {
  const groups = new Map<string, Note[]>();
  const resolve = createNoteResolver(notes);
  for (const note of notes) {
    if (
      isExternalNote(note) ||
      isTrashed(note) ||
      (!includeArchived && isArchived(note)) ||
      note.id === target.id
    )
      continue;
    const bodyLinksToTarget = cachedBodyLinks(note).some(
      (title) => resolve(title)?.id === target.id,
    );
    const relationLinksToTarget = getOutgoingRelationTitles(
      note.content,
      noteTypePath(note),
      schemas,
    ).some((title) => resolve(title)?.id === target.id);
    const reciprocalRelation =
      relationLinksToTarget &&
      hasRelationTo(target, note, schemas);
    // A reciprocal relation is already shown in Properties. Keep body mentions,
    // since they provide separate context even when the two notes are related.
    if (!bodyLinksToTarget && (!relationLinksToTarget || reciprocalRelation))
      continue;
    const key = typeKey(noteTypePath(note));
    const group = groups.get(key) ?? [];
    group.push(note);
    groups.set(key, group);
  }
  for (const group of groups.values()) {
    group.sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  }
  return new Map([...groups.entries()].sort(([a], [b]) => a.localeCompare(b)));
}
