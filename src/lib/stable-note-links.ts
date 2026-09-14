import { getNoteProperties, noteBody, setContentProperty, withBody } from "@/lib/frontmatter";
import { effectiveProperties, type PropertySchemas } from "@/lib/properties";
import { findNoteByTitle, noteReference, noteTypePath, type Note } from "@/lib/note-utils";
import { mapWikilinks, parseNoteReference } from "@/lib/wikilinks";

// Recheck bindings against the current catalogue, but only parse Markdown again
// when the source, relation definitions, or a resolved binding actually changes.
const stabilizationCache = new WeakMap<Note, {
  content: string;
  relationKey: string;
  bindings: Map<string, string>;
  result: string;
}>();

/** Bind existing links once; unresolved and ambiguous legacy targets stay readable. */
export function stabilizeNoteLinks(
  note: Note,
  notes: Note[],
  schemas: PropertySchemas,
  resolve = (reference: string) => findNoteByTitle(reference, notes),
): string {
  const bind = (reference: string) => {
    const parsed = parseNoteReference(reference);
    if (parsed.id !== null) {
      // An early stable-reference patch wrote some ID-only values. Repair those
      // with a readable fallback once the target is available, while preserving
      // intentional labels already stored on newer references.
      if (parsed.label !== parsed.target) return reference;
      const target = resolve(reference);
      return target && parsed.label === parsed.target
        ? noteReference(target)
        : reference;
    }
    const target = resolve(reference);
    return target ? noteReference(target, parsed.label) : reference;
  };
  const relations = effectiveProperties(noteTypePath(note), schemas)
    .filter((def) => def.type === "relation");
  const relationKey = JSON.stringify(relations.map((def) => def.name));
  const cached = stabilizationCache.get(note);
  if (cached?.content === note.content && cached.relationKey === relationKey &&
      [...cached.bindings].every(([reference, bound]) => bind(reference) === bound)) {
    return cached.result;
  }
  const bindings = new Map<string, string>();
  const cachedBind = (reference: string) => {
    const bound = bindings.get(reference) ?? bind(reference);
    bindings.set(reference, bound);
    return bound;
  };
  const body = noteBody(note.content);
  const nextBody = mapWikilinks(body, (reference, original) => {
    const bound = cachedBind(reference);
    return bound === reference ? original : `[[${bound}]]`;
  });
  let content = body === nextBody ? note.content : withBody(note.content, nextBody);
  const properties = getNoteProperties(content);
  for (const def of relations) {
    const value = properties[def.name];
    const next = Array.isArray(value) ? value.map(cachedBind) : typeof value === "string" ? cachedBind(value) : value;
    if (next !== undefined && JSON.stringify(next) !== JSON.stringify(value)) {
      content = setContentProperty(content, def.name, next);
    }
  }
  stabilizationCache.set(note, { content: note.content, relationKey, bindings, result: content });
  return content;
}
