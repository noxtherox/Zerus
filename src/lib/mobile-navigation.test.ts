import { describe, expect, it } from "vitest";
import {
  readMobileNavigationEntry,
  withMobileNavigationEntry,
} from "./mobile-navigation";

describe("mobile navigation history state", () => {
  it("round-trips notes, chat, chat history, and origin-aware note entries", () => {
    expect(readMobileNavigationEntry(withMobileNavigationEntry({}, { view: "notes" }))).toEqual({ view: "notes" });
    expect(readMobileNavigationEntry(withMobileNavigationEntry({}, { view: "chat" }))).toEqual({ view: "chat" });
    expect(readMobileNavigationEntry(withMobileNavigationEntry({}, { view: "chat-history" }))).toEqual({ view: "chat-history" });
    expect(readMobileNavigationEntry(withMobileNavigationEntry({}, {
      view: "note",
      noteId: "Ideas/example.md",
      origin: "chat",
    }))).toEqual({ view: "note", noteId: "Ideas/example.md", origin: "chat" });
  });

  it("preserves router state and rejects malformed entries", () => {
    const state = withMobileNavigationEntry({ idx: 3, key: "router-key" }, { view: "chat" });
    expect(state).toMatchObject({ idx: 3, key: "router-key" });
    expect(readMobileNavigationEntry({ zerusMobileNavigation: { view: "note", noteId: "", origin: "chat" } })).toBeNull();
    expect(readMobileNavigationEntry({ zerusMobileNavigation: { view: "note", noteId: "note", origin: "somewhere" } })).toBeNull();
  });

  it("returns from a linked note to the tasks workspace", () => {
    expect(readMobileNavigationEntry(withMobileNavigationEntry({}, { view: "tasks" }))).toEqual({ view: "tasks" });
    const linkedNote = { view: "note", noteId: "project", origin: "tasks" } as const;
    expect(readMobileNavigationEntry(withMobileNavigationEntry({}, linkedNote))).toEqual(linkedNote);
    const task = { view: "tasks", taskId: "task-1" } as const;
    expect(readMobileNavigationEntry(withMobileNavigationEntry({}, task))).toEqual(task);
    expect(readMobileNavigationEntry({ zerusMobileNavigation: { view: "tasks", taskId: 42 } })).toBeNull();
  });
});
