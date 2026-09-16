import { describe, expect, it } from "vitest";
import {
  INITIAL_NOTE_TABS_STATE,
  activeWorkspaceTab,
  closeNoteTab,
  openNoteInActiveTab,
  openGlobalInNewTab,
  replaceActiveTabNote,
  openNoteInNewTab,
  openTypeInActiveTab,
  openTypeInNewTab,
  toggleNoteTabPinned,
  updateActiveTypeTab,
} from "./note-tabs";

const allNotes = { kind: "all" } as const;

describe("workspace tabs", () => {
  it("stays hidden until a workspace is explicitly opened in a new tab", () => {
    expect(
      openNoteInActiveTab(INITIAL_NOTE_TABS_STATE, "note-a", allNotes),
    ).toEqual(INITIAL_NOTE_TABS_STATE);

    const state = openNoteInNewTab(
      INITIAL_NOTE_TABS_STATE,
      { kind: "note", noteId: "note-a", filter: allNotes },
      "note-b",
      allNotes,
    );
    expect(state.enabled).toBe(true);
    expect(
      state.tabs.map((tab) => (tab.kind === "note" ? tab.noteId : null)),
    ).toEqual(["note-a", "note-b"]);
  });

  it("reuses an unpinned note tab for ordinary note navigation", () => {
    let state = openNoteInNewTab(
      INITIAL_NOTE_TABS_STATE,
      { kind: "note", noteId: "note-a", filter: allNotes },
      "note-b",
      allNotes,
    );
    state = openNoteInActiveTab(state, "note-c", allNotes);
    expect(
      state.tabs.map((tab) => (tab.kind === "note" ? tab.noteId : null)),
    ).toEqual(["note-a", "note-c"]);
  });

  it("opens a type beside a pinned tab and deduplicates it", () => {
    let state = openNoteInNewTab(
      INITIAL_NOTE_TABS_STATE,
      null,
      "note-a",
      allNotes,
    );
    state = toggleNoteTabPinned(state, state.activeTabId!);
    state = openTypeInActiveTab(state, ["work", "projects"]);
    const typeTabId = state.activeTabId;
    state = openTypeInNewTab(state, null, ["work", "projects"]);

    expect(state.tabs).toHaveLength(2);
    expect(state.activeTabId).toBe(typeTabId);
    expect(activeWorkspaceTab(state)).toMatchObject({
      kind: "type",
      typePath: ["work", "projects"],
    });
  });

  it("remembers drill-in state inside a type tab", () => {
    let state = openTypeInNewTab(
      INITIAL_NOTE_TABS_STATE,
      null,
      ["work", "projects"],
    );
    state = updateActiveTypeTab(state, {
      selectedNoteId: "note-a",
      editorOpen: true,
    });
    expect(activeWorkspaceTab(state)).toMatchObject({
      kind: "type",
      selectedNoteId: "note-a",
      editorOpen: true,
    });
  });

  it("preserves the current global view when opening a type", () => {
    const state = openTypeInNewTab(
      INITIAL_NOTE_TABS_STATE,
      { kind: "global", filter: allNotes, selectedNoteId: null },
      ["work"],
    );
    expect(state.tabs).toHaveLength(2);
    expect(state.tabs[0]).toMatchObject({ kind: "global", filter: allNotes });
    expect(activeWorkspaceTab(state)).toMatchObject({ kind: "type", typePath: ["work"] });
  });

  it.each(["all", "tasks", "external", "files", "links", "trash"] as const)(
    "opens and restores the %s global view without replacing a pinned type",
    (kind) => {
      let state = openTypeInNewTab(INITIAL_NOTE_TABS_STATE, null, ["work"]);
      state = toggleNoteTabPinned(state, state.activeTabId!);
      state = openGlobalInNewTab(state, null, { kind });
      const globalId = state.activeTabId!;
      state = replaceActiveTabNote(state, "note-a");
      state = openTypeInNewTab(state, null, ["work"]);
      state = openGlobalInNewTab(state, null, { kind });
      expect(state.tabs).toHaveLength(2);
      expect(state.activeTabId).toBe(globalId);
      expect(activeWorkspaceTab(state)).toMatchObject({
        kind: "global", filter: { kind }, selectedNoteId: "note-a",
      });
      state = closeNoteTab(state, globalId);
      expect(activeWorkspaceTab(state)).toMatchObject({ kind: "type", pinned: true });
    },
  );

  it("selects an adjacent workspace when the active tab closes", () => {
    let state = openNoteInNewTab(
      INITIAL_NOTE_TABS_STATE,
      { kind: "note", noteId: "note-a", filter: allNotes },
      "note-b",
      allNotes,
    );
    const activeId = state.activeTabId!;
    state = closeNoteTab(state, activeId);
    expect(state.tabs).toHaveLength(1);
    expect(state.tabs[0].id).toBe(state.activeTabId);
  });
});
