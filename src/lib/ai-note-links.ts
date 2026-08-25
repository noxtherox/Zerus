const NOTE_LINK_PREFIX = "zerus-note:";

export function noteIdFromAiHref(href: string | undefined): string | null {
  if (!href?.toLowerCase().startsWith(NOTE_LINK_PREFIX)) return null;
  try {
    const noteId = decodeURIComponent(href.slice(NOTE_LINK_PREFIX.length)).trim();
    return noteId || null;
  } catch {
    return null;
  }
}
