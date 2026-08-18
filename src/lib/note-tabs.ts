import type { NoteFilter } from "./filters";

interface WorkspaceTabBase {
  id: string;
  pinned: boolean;
}

export interface NoteTab extends WorkspaceTabBase {
  kind: "note";
  noteId: string;
  /** The notes workspace the note was opened from. */
  filter: NoteFilter;
}

export interface TypeTab extends WorkspaceTabBase {
  kind: "type";
  typePath: string[];
  selectedNoteId: string | null;
  editorOpen: boolean;
}

export type WorkspaceTab = NoteTab | TypeTab;

export interface NoteTabsState {
  enabled: boolean;
  tabs: WorkspaceTab[];
  activeTabId: string | null;
  nextTabId: number;
}

export type WorkspaceTabSeed =
  | { kind: "note"; noteId: string; filter: NoteFilter }
  | {
      kind: "type";
      typePath: string[];
      selectedNoteId: string | null;
      editorOpen: boolean;
    };

export const INITIAL_NOTE_TABS_STATE: NoteTabsState = {
  enabled: false,
  tabs: [],
  activeTabId: null,
  nextTabId: 1,
};

function appendTab(state: NoteTabsState, seed: WorkspaceTabSeed): NoteTabsState {
  const tab: WorkspaceTab = {
    ...seed,
    id: `workspace-tab-${state.nextTabId}`,
    pinned: false,
  };
  return {
    ...state,
    enabled: true,
    tabs: [...state.tabs, tab],
    activeTabId: tab.id,
    nextTabId: state.nextTabId + 1,
  };
}

function sameType(left: string[], right: string[]) {
  return (
    left.length === right.length &&
    left.every((part, index) => part === right[index])
  );
}

function replaceActiveTab(
  state: NoteTabsState,
  seed: WorkspaceTabSeed,
): NoteTabsState {
  const active = state.tabs.find((tab) => tab.id === state.activeTabId);
  if (!active || active.pinned) return appendTab(state, seed);
  return {
    ...state,
    tabs: state.tabs.map((tab) =>
      tab.id === active.id ? { ...seed, id: tab.id, pinned: false } : tab,
    ),
  };
}

export function activeWorkspaceTab(state: NoteTabsState) {
  return state.tabs.find((tab) => tab.id === state.activeTabId) ?? null;
}

export function openNoteInNewTab(
  state: NoteTabsState,
  current: WorkspaceTabSeed | null,
  noteId: string,
  filter: NoteFilter = { kind: "all" },
): NoteTabsState {
  let next = state;
  if (!next.enabled && current) next = appendTab(next, current);

  const existing = next.tabs.find(
    (tab) => tab.kind === "note" && tab.noteId === noteId,
  );
  if (existing) return { ...next, activeTabId: existing.id };
  return appendTab(next, { kind: "note", noteId, filter });
}

export function openNoteInActiveTab(
  state: NoteTabsState,
  noteId: string,
  filter: NoteFilter = { kind: "all" },
): NoteTabsState {
  if (!state.enabled) return state;

  const existing = state.tabs.find(
    (tab) => tab.kind === "note" && tab.noteId === noteId,
  );
  if (existing) return { ...state, activeTabId: existing.id };

  return replaceActiveTab(state, { kind: "note", noteId, filter });
}

export function openTypeInActiveTab(
  state: NoteTabsState,
  typePath: string[],
): NoteTabsState {
  if (!state.enabled) return state;
  const existing = state.tabs.find(
    (tab) => tab.kind === "type" && sameType(tab.typePath, typePath),
  );
  if (existing) return { ...state, activeTabId: existing.id };
  return replaceActiveTab(state, {
    kind: "type",
    typePath,
    selectedNoteId: null,
    editorOpen: false,
  });
}

export function openTypeInNewTab(
  state: NoteTabsState,
  current: WorkspaceTabSeed | null,
  typePath: string[],
): NoteTabsState {
  let next = state;
  if (!next.enabled && current) next = appendTab(next, current);
  const existing = next.tabs.find(
    (tab) => tab.kind === "type" && sameType(tab.typePath, typePath),
  );
  if (existing) return { ...next, activeTabId: existing.id };
  return appendTab(next, {
    kind: "type",
    typePath,
    selectedNoteId: null,
    editorOpen: false,
  });
}

export function updateActiveTypeTab(
  state: NoteTabsState,
  patch: Partial<Pick<TypeTab, "selectedNoteId" | "editorOpen">>,
): NoteTabsState {
  const active = activeWorkspaceTab(state);
  if (!active || active.kind !== "type") return state;
  return {
    ...state,
    tabs: state.tabs.map((tab) =>
      tab.id === active.id ? { ...tab, ...patch } : tab,
    ),
  };
}

export function replaceActiveTabNote(
  state: NoteTabsState,
  noteId: string | null,
): NoteTabsState {
  if (!state.enabled) return state;
  const active = activeWorkspaceTab(state);
  if (!active) return state;
  if (active.kind === "type") {
    return updateActiveTypeTab(state, { selectedNoteId: noteId });
  }
  if (!noteId) return state;
  return {
    ...state,
    tabs: state.tabs.map((tab) =>
      tab.id === active.id ? { ...tab, noteId } : tab,
    ),
  };
}

export function activateNoteTab(
  state: NoteTabsState,
  tabId: string,
): NoteTabsState {
  return state.tabs.some((tab) => tab.id === tabId)
    ? { ...state, activeTabId: tabId }
    : state;
}

export function clearActiveTab(state: NoteTabsState): NoteTabsState {
  return state.enabled ? { ...state, activeTabId: null } : state;
}

export function toggleNoteTabPinned(
  state: NoteTabsState,
  tabId: string,
): NoteTabsState {
  return {
    ...state,
    tabs: state.tabs.map((tab) =>
      tab.id === tabId ? { ...tab, pinned: !tab.pinned } : tab,
    ),
  };
}

export function closeNoteTab(
  state: NoteTabsState,
  tabId: string,
): NoteTabsState {
  const index = state.tabs.findIndex((tab) => tab.id === tabId);
  if (index < 0) return state;
  const tabs = state.tabs.filter((tab) => tab.id !== tabId);
  if (!tabs.length) return INITIAL_NOTE_TABS_STATE;
  if (state.activeTabId !== tabId) return { ...state, tabs };
  const nextActive = tabs[Math.min(index, tabs.length - 1)];
  return { ...state, tabs, activeTabId: nextActive.id };
}
