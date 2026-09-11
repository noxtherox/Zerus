import { getNoteProperties, noteBody, setContentProperty, withBody } from "@/lib/frontmatter";
import { effectiveProperties, type PropertySchemas } from "@/lib/properties";
import { findNoteByTitle, noteReference, noteTypePath, type Note } from "@/lib/note-utils";
import { mapWikilinks, parseNoteReference } from "@/lib/wikilinks";

/** Bind existing links once; unresolved and ambiguous legacy targets stay readable. */
export function stabilizeNoteLinks(note: Note, notes: Note[], schemas: PropertySchemas): string {
  const bind = (reference: string) => {
    const parsed = parseNoteReference(reference);
    if (parsed.id !== null) {
      // An early stable-reference patch wrote some ID-only values. Repair those
      // with a readable fallback once the target is available, while preserving
      // intentional labels already stored on newer references.
      const target = findNoteByTitle(reference, notes);
      return target && parsed.label === parsed.target
        ? noteReference(target)
        : reference;
    }
    const target = findNoteByTitle(reference, notes);
    return target ? noteReference(target, parsed.label) : reference;
  };
  const body = noteBody(note.content);
  const nextBody = mapWikilinks(body, (reference, original) => {
    const bound = bind(reference);
    return bound === reference ? original : `[[${bound}]]`;
  });
  let content = body === nextBody ? note.content : withBody(note.content, nextBody);
  const properties = getNoteProperties(content);
  for (const def of effectiveProperties(noteTypePath(note), schemas)) {
    if (def.type !== "relation") continue;
    const value = properties[def.name];
    const next = Array.isArray(value) ? value.map(bind) : typeof value === "string" ? bind(value) : value;
    if (next !== undefined && JSON.stringify(next) !== JSON.stringify(value)) {
      content = setContentProperty(content, def.name, next);
    }
  }
  return content;
}
