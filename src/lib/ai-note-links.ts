import { mapWikilinks, parseNoteReference } from "@/lib/wikilinks";

const NOTE_LINK_PREFIX = "zerus-note:";

/** Turn the notes agent's stable citations into links, leaving code examples literal. */
export function prepareAiNoteLinks(markdown: string): string {
  return mapWikilinks(markdown, (reference, original) => {
    const { id, label } = parseNoteReference(reference);
    if (!id) return original;
    const text = label.replace(/[\\[\]*_`<>]/g, "\\$&");
    return `[${text}](${NOTE_LINK_PREFIX}${encodeURIComponent(id)})`;
  });
}

export function noteIdFromAiHref(href: string | undefined): string | null {
  if (!href?.toLowerCase().startsWith(NOTE_LINK_PREFIX)) return null;
  try {
    const noteId = decodeURIComponent(href.slice(NOTE_LINK_PREFIX.length)).trim();
    return noteId || null;
  } catch {
    return null;
  }
}
