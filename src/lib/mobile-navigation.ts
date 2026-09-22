export type MobileNavigationEntry =
  | { view: "notes" }
  | { view: "tasks"; taskId?: string }
  | { view: "chat" }
  | { view: "chat-history" }
  | { view: "note"; noteId: string; origin: "notes" | "chat" | "tasks" };

const MOBILE_NAVIGATION_KEY = "zerusMobileNavigation";

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
  if (entry.view === "tasks") {
    if (entry.taskId !== undefined && (typeof entry.taskId !== "string" || !entry.taskId)) return null;
    return entry.taskId ? { view: "tasks", taskId: entry.taskId as string } : { view: "tasks" };
  }
  if (
    entry.view === "note" &&
    typeof entry.noteId === "string" &&
    entry.noteId.length > 0 &&
    (entry.origin === "notes" || entry.origin === "chat" || entry.origin === "tasks")
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
