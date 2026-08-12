export type MobileNavigationEntry =
  | { view: "notes" }
  | { view: "chat" }
  | { view: "chat-history" }
  | { view: "note"; noteId: string; origin: "notes" | "chat" };

const MOBILE_NAVIGATION_KEY = "grimoireMobileNavigation";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

export function readMobileNavigationEntry(state: unknown): MobileNavigationEntry | null {
  if (!isRecord(state)) return null;
  const entry = state[MOBILE_NAVIGATION_KEY];
  if (!isRecord(entry)) return null;

  if (entry.view === "notes" || entry.view === "chat" || entry.view === "chat-history") {
    return { view: entry.view };
  }
  if (
    entry.view === "note" &&
    typeof entry.noteId === "string" &&
    entry.noteId.length > 0 &&
    (entry.origin === "notes" || entry.origin === "chat")
  ) {
    return { view: "note", noteId: entry.noteId, origin: entry.origin };
  }
  return null;
}

export function withMobileNavigationEntry(
  state: unknown,
  entry: MobileNavigationEntry,
): Record<string, unknown> {
  return {
    ...(isRecord(state) ? state : {}),
    [MOBILE_NAVIGATION_KEY]: entry,
  };
}
