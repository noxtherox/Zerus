import { getNoteProperties } from "@/lib/frontmatter";
import { effectiveProperties, type PropertySchemas } from "@/lib/properties";
import {
  type Note,
  getOutgoingLinkTitles,
  isArchived,
  isExternalNote,
  isTrashed,
  noteTitle,
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
  const targetTitle = noteTitle(target).toLowerCase();
  return getOutgoingRelationTitles(
    source.content,
    noteTypePath(source),
    schemas,
  ).some((title) => title.toLowerCase() === targetTitle);
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
  const targetTitle = noteTitle(target).toLowerCase();
  const targetRelationTitles = new Set(
    getOutgoingRelationTitles(target.content, noteTypePath(target), schemas).map(
      (title) => title.toLowerCase(),
    ),
  );
  const groups = new Map<string, Note[]>();
  for (const note of notes) {
    if (
      isExternalNote(note) ||
      isTrashed(note) ||
      (!includeArchived && isArchived(note)) ||
      note.id === target.id
    )
      continue;
    const bodyLinksToTarget = getOutgoingLinkTitles(note.content).some(
      (title) => title.toLowerCase() === targetTitle,
    );
    const relationLinksToTarget = getOutgoingRelationTitles(
      note.content,
      noteTypePath(note),
      schemas,
    ).some((title) => title.toLowerCase() === targetTitle);
    const reciprocalRelation =
      relationLinksToTarget &&
      targetRelationTitles.has(noteTitle(note).toLowerCase());
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
