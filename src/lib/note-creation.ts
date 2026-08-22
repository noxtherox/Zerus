import type { NoteFilter } from "@/lib/filters";

/**
 * Uses the active type when one is selected; every type-neutral section uses
 * the user's configured default.
 */
export function noteCreationType(
  filter: NoteFilter,
  defaultNoteType: string[],
): string[] {
  return filter.kind === "type" ? filter.path : defaultNoteType;
}
