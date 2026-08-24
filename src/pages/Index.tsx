import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { FolderOpen, Loader2 } from "lucide-react";
import type {
  ImperativePanelGroupHandle,
  ImperativePanelHandle,
} from "react-resizable-panels";
import { Button } from "@/components/ui/button";
import {
  ResizableHandle,
  ResizablePanel,
  ResizablePanelGroup,
} from "@/components/ui/resizable";
import { Sidebar } from "@/components/notes/Sidebar";
import { CollapsedSidebar } from "@/components/notes/CollapsedSidebar";
import { NoteList } from "@/components/notes/NoteList";
import { TypeViewWorkspace } from "@/components/notes/TypeViewWorkspace";
import { TasksWorkspace } from "@/components/tasks/TasksWorkspace";
import { NoteTabs } from "@/components/notes/NoteTabs";
import { EditorPane } from "@/components/notes/EditorPane";
import { ZerusLogo } from "@/components/ZerusLogo";
import { AiPanel } from "@/components/ai/AiPanel";
import {
  chooseVaultFolder,
  copyExternalNoteToVault,
  createFileNote,
  createLinkNote,
  createNote,
  initStore,
  moveExternalNoteToVault,
  moveSavedLinkToVault,
  onDesktopNotesOpened,
  openExternalNotes,
  prioritizeNoteLoad,
  refreshVaultFromDisk,
  setNoteProperty,
  updateTypeView,
  useVault,
} from "@/store/notes-store";
import {
  createTask,
  deleteTask,
  deleteTaskCategory,
  loadTasks,
  updateTaskCategoryOptions,
  updateTask,
  useTaskCategoryOptions,
  useTasks,
} from "@/store/tasks-store";
import {
  EMPTY_NOTE_LIST_FILTERS,
  filterNotes,
  type NoteFilter,
  type NoteListFilters,
} from "@/lib/filters";
import { DEFAULT_TYPE, noteContainingFolder, typeKey } from "@/lib/note-utils";
import { noteCreationType } from "@/lib/note-creation";
import { typeViewConfigFor } from "@/lib/note-views";
import {
  loadDefaultNoteType,
  loadHideSubtypeNotes,
  loadNoteTypeOrder,
  saveDefaultNoteType,
  saveHideSubtypeNotes,
  saveNoteTypeOrder,
} from "@/lib/note-preferences";
import { cn } from "@/lib/utils";
import { AutoUpdater } from "@/lib/auto-updater";
import {
  createNavigationHistory,
  goBackInNavigationHistory,
  goForwardInNavigationHistory,
  pushNavigationHistory,
} from "@/lib/navigation-history";
import {
  INITIAL_NOTE_TABS_STATE,
  activeWorkspaceTab,
  activateNoteTab,
  clearActiveTab,
  closeNoteTab,
  openNoteInActiveTab,
  openNoteInNewTab,
  openTypeInActiveTab,
  openTypeInNewTab,
  replaceActiveTabNote,
  toggleNoteTabPinned,
  updateActiveTypeTab,
  type WorkspaceTab,
  type WorkspaceTabSeed,
} from "@/lib/note-tabs";

const SIDEBAR_DEFAULT_SIZE = 15;
const NOTE_LIST_DEFAULT_SIZE = 18;
const EDITOR_DEFAULT_SIZE = 67;
const WORKSPACE_DEFAULT_SIZE = NOTE_LIST_DEFAULT_SIZE + EDITOR_DEFAULT_SIZE;
const NOTE_LIST_WORKSPACE_SIZE =
  (NOTE_LIST_DEFAULT_SIZE / WORKSPACE_DEFAULT_SIZE) * 100;
const EDITOR_WORKSPACE_SIZE = 100 - NOTE_LIST_WORKSPACE_SIZE;
const DEFAULT_PANEL_LAYOUT = [
  SIDEBAR_DEFAULT_SIZE,
  WORKSPACE_DEFAULT_SIZE,
];
const DEFAULT_WORKSPACE_LAYOUT = [
  NOTE_LIST_WORKSPACE_SIZE,
  EDITOR_WORKSPACE_SIZE,
];

interface AppNavigationEntry {
  filter: NoteFilter;
  selectedNoteId: string | null;
}

const INITIAL_NAVIGATION_ENTRY: AppNavigationEntry = {
  filter: { kind: "all" },
  selectedNoteId: null,
};

function navigationEntriesEqual(
  left: AppNavigationEntry,
  right: AppNavigationEntry,
): boolean {
  if (left.selectedNoteId !== right.selectedNoteId) return false;
  if (left.filter.kind !== right.filter.kind) return false;
  if (left.filter.kind !== "type" || right.filter.kind !== "type") return true;
  const leftPath = left.filter.path;
  const rightPath = right.filter.path;
  return (
    left.filter.includeSubtypes === right.filter.includeSubtypes &&
    leftPath.length === rightPath.length &&
    leftPath.every((part, index) => part === rightPath[index])
  );
}

const Index = () => {
  const vault = useVault();
  const tasks = useTasks();
  const taskCategoryOptions = useTaskCategoryOptions();
  const [selectedTaskId, setSelectedTaskId] = useState<string | null>(null);
  const [navigation, setNavigation] = useState(() =>
    createNavigationHistory(INITIAL_NAVIGATION_ENTRY),
  );
  const { filter, selectedNoteId } = navigation.current;
  const [search, setSearch] = useState("");
  const [listFilters, setListFilters] =
    useState<NoteListFilters>(EMPTY_NOTE_LIST_FILTERS);
  const [isFocusMode, setIsFocusMode] = useState(false);
  const [aiOpen, setAiOpen] = useState(false);
  const [defaultNoteType, setDefaultNoteType] = useState<string[]>(DEFAULT_TYPE);
  const [typeOrder, setTypeOrder] = useState<string[]>([]);
  const [hideSubtypeNotes, setHideSubtypeNotes] = useState(false);
  const [expandedEditorOpen, setExpandedEditorOpen] = useState(false);
  const [noteTabs, setNoteTabs] = useState(INITIAL_NOTE_TABS_STATE);
  const panelGroupRef = useRef<ImperativePanelGroupHandle>(null);
  const workspacePanelGroupRef = useRef<ImperativePanelGroupHandle>(null);
  const sidebarPanelRef = useRef<ImperativePanelHandle>(null);
  const [isSidebarCollapsed, setIsSidebarCollapsed] = useState(false);
  const expandedPanelLayoutRef = useRef([...DEFAULT_PANEL_LAYOUT]);
  const workspacePanelLayoutRef = useRef([...DEFAULT_WORKSPACE_LAYOUT]);
  const focusRestoreLayoutRef = useRef([...DEFAULT_PANEL_LAYOUT]);
  const focusRestoreWorkspaceLayoutRef = useRef([
    ...DEFAULT_WORKSPACE_LAYOUT,
  ]);
  const wasFocusModeRef = useRef(false);
  const leavingFocusRef = useRef(false);
  const sidebarCollapsedBeforeFocusRef = useRef(false);
  const previousVaultLocationRef = useRef<string | null>(null);

  useEffect(() => {
    const previous = previousVaultLocationRef.current;
    previousVaultLocationRef.current = vault.location;
    if (!previous || !vault.location || previous === vault.location) return;
    setNavigation(createNavigationHistory(INITIAL_NAVIGATION_ENTRY));
    setNoteTabs(INITIAL_NOTE_TABS_STATE);
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
  }, [vault.location]);

  useEffect(() => {
    void loadTasks(vault.location);
    setSelectedTaskId(null);
  }, [vault.location]);

  useEffect(() => {
    const refresh = () => {
      if (document.visibilityState !== "visible") return;
      void refreshVaultFromDisk();
    };
    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", refresh);
    return () => {
      window.removeEventListener("focus", refresh);
      document.removeEventListener("visibilitychange", refresh);
    };
  }, []);

  const { notes } = vault;
  const navigate = (entry: AppNavigationEntry) => {
    setNavigation((history) =>
      pushNavigationHistory(history, entry, navigationEntriesEqual),
    );
  };

  const navigateBack = () => {
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    setNavigation((history) => {
      const next = goBackInNavigationHistory(history);
      setNoteTabs((tabs) =>
        replaceActiveTabNote(tabs, next.current.selectedNoteId),
      );
      return next;
    });
  };

  const navigateForward = () => {
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    setNavigation((history) => {
      const next = goForwardInNavigationHistory(history);
      setNoteTabs((tabs) =>
        replaceActiveTabNote(tabs, next.current.selectedNoteId),
      );
      return next;
    });
  };

  useEffect(() => {
    const stopListening = onDesktopNotesOpened(
      (ids, firstNoteIsExternal, firstNoteIsFileHub) => {
        const openedFilter: NoteFilter = firstNoteIsFileHub
          ? { kind: "files" }
          : firstNoteIsExternal
            ? { kind: "external" }
            : { kind: "all" };
        setNoteTabs((tabs) =>
          openNoteInActiveTab(tabs, ids[0], openedFilter),
        );
        navigate({
          filter: openedFilter,
          selectedNoteId: ids[0],
        });
        setListFilters(EMPTY_NOTE_LIST_FILTERS);
        setSearch("");
      },
    );
    initStore();
    return stopListening;
  }, []);
  const effectiveFilter = useMemo<NoteFilter>(
    () =>
      filter.kind === "type"
        ? { ...filter, includeSubtypes: !hideSubtypeNotes }
        : filter,
    [filter, hideSubtypeNotes],
  );
  const filterOptions = useMemo(
    () =>
      filterNotes(notes, effectiveFilter, "", {
        ...EMPTY_NOTE_LIST_FILTERS,
        showArchived: listFilters.showArchived,
      }),
    [notes, effectiveFilter, listFilters.showArchived],
  );
  const visibleNotes = useMemo(
    () => filterNotes(notes, effectiveFilter, search, listFilters),
    [notes, effectiveFilter, search, listFilters],
  );
  const activeTypeKey = filter.kind === "type" ? typeKey(filter.path) : null;
  const activeTypeView = activeTypeKey
    ? typeViewConfigFor(vault.typeViews, activeTypeKey)
    : null;
  const structuredTypeViewOpen =
    filter.kind === "type" && activeTypeView?.mode !== "list";

  const currentWorkspaceSeed = (): WorkspaceTabSeed | null => {
    const active = activeWorkspaceTab(noteTabs);
    if (active) {
      return active.kind === "type"
        ? {
            kind: "type",
            typePath: active.typePath,
            selectedNoteId: active.selectedNoteId,
            editorOpen: active.editorOpen,
          }
        : {
            kind: "note",
            noteId: active.noteId,
            filter: active.filter,
          };
    }
    if (filter.kind === "type") {
      return {
        kind: "type",
        typePath: filter.path,
        selectedNoteId,
        editorOpen: expandedEditorOpen,
      };
    }
    return selectedNoteId
      ? { kind: "note", noteId: selectedNoteId, filter }
      : null;
  };

  const showWorkspaceTab = (tab: WorkspaceTab) => {
    if (tab.kind === "type") {
      navigate({
        filter: { kind: "type", path: tab.typePath },
        selectedNoteId: tab.selectedNoteId,
      });
      setExpandedEditorOpen(tab.editorOpen);
      return;
    }
    navigate({ filter: tab.filter, selectedNoteId: tab.noteId });
    const sourceView =
      tab.filter.kind === "type"
        ? typeViewConfigFor(vault.typeViews, typeKey(tab.filter.path))
        : null;
    setExpandedEditorOpen(
      tab.filter.kind === "type" && sourceView?.mode !== "list",
    );
  };

  const handleFilterChange = (nextFilter: NoteFilter) => {
    if (nextFilter.kind === "type" && noteTabs.enabled) {
      const nextTabs = openTypeInActiveTab(noteTabs, nextFilter.path);
      setNoteTabs(nextTabs);
      const nextTab = activeWorkspaceTab(nextTabs);
      if (nextTab) showWorkspaceTab(nextTab);
    } else {
      setNoteTabs((tabs) => clearActiveTab(tabs));
      navigate({ filter: nextFilter, selectedNoteId: null });
      setExpandedEditorOpen(false);
    }
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
  };

  const selectedNote = notes.find((note) => note.id === selectedNoteId) ?? null;

  useEffect(() => {
    setDefaultNoteType(loadDefaultNoteType(vault.location));
    setTypeOrder(loadNoteTypeOrder(vault.location));
    setHideSubtypeNotes(loadHideSubtypeNotes(vault.location));
  }, [vault.location]);

  const handleDefaultNoteTypeChange = (typePath: string[]) => {
    setDefaultNoteType(typePath);
    saveDefaultNoteType(vault.location, typePath);
  };

  const handleTypeOrderChange = (order: string[]) => {
    setTypeOrder(order);
    saveNoteTypeOrder(vault.location, order);
  };

  const handleHideSubtypeNotesChange = (hidden: boolean) => {
    setHideSubtypeNotes(hidden);
    saveHideSubtypeNotes(vault.location, hidden);
  };

  const selectNoteInCurrentWorkspace = (
    id: string,
    editorOpen: boolean,
  ) => {
    const active = activeWorkspaceTab(noteTabs);
    if (active?.kind === "type") {
      setNoteTabs((tabs) =>
        updateActiveTypeTab(tabs, { selectedNoteId: id, editorOpen }),
      );
      return;
    }
    setNoteTabs((tabs) => openNoteInActiveTab(tabs, id, filter));
  };

  const handleCreateNote = async () => {
    if (vault.isRefreshing) return;
    const typePath = noteCreationType(filter, defaultNoteType);
    const note = await createNote(typePath);
    if (!note) return;
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    navigate({
      filter:
        filter.kind === "trash" ||
        filter.kind === "tasks" ||
        filter.kind === "external" ||
        filter.kind === "files" ||
        filter.kind === "links"
          ? { kind: "all" }
          : filter,
      selectedNoteId: note.id,
    });
    selectNoteInCurrentWorkspace(note.id, structuredTypeViewOpen);
    if (structuredTypeViewOpen) setExpandedEditorOpen(true);
  };

  const handleCreateFile = async () => {
    if (vault.isRefreshing) return;
    const note = await createFileNote(defaultNoteType);
    if (!note) return;
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    navigate({ filter: { kind: "files" }, selectedNoteId: note.id });
    setNoteTabs((tabs) =>
      openNoteInActiveTab(tabs, note.id, { kind: "files" }),
    );
  };

  const handleCreateLink = async (url: string) => {
    if (vault.isRefreshing) return;
    const note = await createLinkNote(url);
    if (!note) return;
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    navigate({ filter: { kind: "links" }, selectedNoteId: note.id });
    setNoteTabs((tabs) =>
      openNoteInActiveTab(tabs, note.id, { kind: "links" }),
    );
  };

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (vault.isRefreshing) return;
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "n") {
        event.preventDefault();
        void handleCreateNote();
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, defaultNoteType, vault.isRefreshing]);

  const handleOpenNote = (id: string) => {
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    navigate({ filter: { kind: "all" }, selectedNoteId: id });
    setNoteTabs((tabs) =>
      openNoteInActiveTab(tabs, id, { kind: "all" }),
    );
    void prioritizeNoteLoad(id);
  };

  const handleOpenTask = (id: string) => {
    setNoteTabs((tabs) => clearActiveTab(tabs));
    navigate({ filter: { kind: "tasks" }, selectedNoteId: null });
    setSelectedTaskId(id);
    setExpandedEditorOpen(false);
  };

  const handleSelectNote = (id: string) => {
    navigate({ filter, selectedNoteId: id });
    selectNoteInCurrentWorkspace(id, false);
    void prioritizeNoteLoad(id);
  };

  const handleOpenStructuredNote = (id: string) => {
    navigate({ filter, selectedNoteId: id });
    selectNoteInCurrentWorkspace(id, true);
    void prioritizeNoteLoad(id);
    setExpandedEditorOpen(true);
  };

  const handleTypeViewChange = (
    patch: Parameters<typeof updateTypeView>[1],
  ) => {
    if (!activeTypeKey) return;
    updateTypeView(activeTypeKey, patch);
    if (patch.mode) {
      const active = activeWorkspaceTab(noteTabs);
      const noteTabStaysExpanded =
        active?.kind === "note" && patch.mode !== "list";
      setExpandedEditorOpen(noteTabStaysExpanded);
      if (active?.kind === "type") {
        setNoteTabs((tabs) =>
          updateActiveTypeTab(tabs, { editorOpen: false }),
        );
      }
      setIsFocusMode(false);
    }
  };

  const handleOpenNoteInNewTab = (id: string) => {
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    const nextTabs = openNoteInNewTab(
      noteTabs,
      currentWorkspaceSeed(),
      id,
      filter,
    );
    setNoteTabs(nextTabs);
    navigate({ filter, selectedNoteId: id });
    if (structuredTypeViewOpen) setExpandedEditorOpen(true);
    void prioritizeNoteLoad(id);
  };

  const handleActivateTab = (tabId: string) => {
    const tab = noteTabs.tabs.find((candidate) => candidate.id === tabId);
    if (!tab) return;
    setNoteTabs((tabs) => activateNoteTab(tabs, tabId));
    showWorkspaceTab(tab);
    const noteId =
      tab.kind === "note" ? tab.noteId : tab.selectedNoteId;
    if (noteId) void prioritizeNoteLoad(noteId);
  };

  const handleCloseTab = (tabId: string) => {
    const next = closeNoteTab(noteTabs, tabId);
    setNoteTabs(next);
    if (noteTabs.activeTabId !== tabId) return;
    const nextTab = activeWorkspaceTab(next);
    if (!nextTab) {
      navigate({ filter: { kind: "all" }, selectedNoteId: null });
      setExpandedEditorOpen(false);
      return;
    }
    showWorkspaceTab(nextTab);
    const noteId =
      nextTab.kind === "note" ? nextTab.noteId : nextTab.selectedNoteId;
    if (noteId) void prioritizeNoteLoad(noteId);
  };

  const handleOpenTypeInNewTab = (typePath: string[]) => {
    const nextTabs = openTypeInNewTab(
      noteTabs,
      currentWorkspaceSeed(),
      typePath,
    );
    setNoteTabs(nextTabs);
    const nextTab = activeWorkspaceTab(nextTabs);
    if (nextTab) showWorkspaceTab(nextTab);
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
  };

  const handleCloseExpandedEditor = () => {
    const active = activeWorkspaceTab(noteTabs);
    if (active?.kind === "type") {
      setNoteTabs((tabs) => updateActiveTypeTab(tabs, { editorOpen: false }));
      setExpandedEditorOpen(false);
      return;
    }
    if (active?.kind === "note" && active.filter.kind === "type") {
      const activeTypePath = active.filter.path;
      const sourceTypeTab = noteTabs.tabs.find(
        (tab) =>
          tab.kind === "type" &&
          typeKey(tab.typePath) === typeKey(activeTypePath),
      );
      if (sourceTypeTab) {
        setNoteTabs((tabs) => activateNoteTab(tabs, sourceTypeTab.id));
        showWorkspaceTab(sourceTypeTab);
        return;
      }
      setNoteTabs((tabs) => clearActiveTab(tabs));
    }
    setExpandedEditorOpen(false);
  };
  const handleEditorNavigateBack = () => {
    if (structuredTypeViewOpen && expandedEditorOpen) {
      handleCloseExpandedEditor();
      return;
    }
    navigateBack();
  };
  const handleOpenExternalNotes = async () => {
    const ids = await openExternalNotes();
    if (!ids.length) return;
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    navigate({ filter: { kind: "external" }, selectedNoteId: ids[0] });
    setNoteTabs((tabs) =>
      openNoteInActiveTab(tabs, ids[0], { kind: "external" }),
    );
  };

  const handleMoveExternalToVault = async (id: string, typePath: string[]) => {
    const moved = await moveExternalNoteToVault(id, typePath);
    if (!moved) return;
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    navigate({
      filter: { kind: "type", path: typePath },
      selectedNoteId: id,
    });
  };

  const handleCopyExternalToVault = async (id: string, typePath: string[]) => {
    const copied = await copyExternalNoteToVault(id, typePath);
    if (!copied) return;
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    navigate({
      filter: { kind: "type", path: typePath },
      selectedNoteId: copied.id,
    });
  };

  const handleToggleFocusMode = () => {
    const panelGroup = panelGroupRef.current;
    if (!panelGroup) return;

    if (!isFocusMode) {
      focusRestoreLayoutRef.current = panelGroup.getLayout();
      const workspaceGroup = workspacePanelGroupRef.current;
      if (workspaceGroup) {
        focusRestoreWorkspaceLayoutRef.current = workspaceGroup.getLayout();
      }
      sidebarCollapsedBeforeFocusRef.current = isSidebarCollapsed;
    }
    setIsFocusMode((focused) => !focused);
  };

  useEffect(() => {
    const panelGroup = panelGroupRef.current;
    if (!panelGroup) return;
    const leavingFocus = wasFocusModeRef.current && !isFocusMode;
    leavingFocusRef.current = leavingFocus;
    const focusRestore = focusRestoreLayoutRef.current;
    panelGroup.setLayout(
      isFocusMode
        ? [0, 100]
        : leavingFocus && focusRestore.length === 2
          ? focusRestore
          : expandedPanelLayoutRef.current,
    );
    const workspaceGroup = workspacePanelGroupRef.current;
    if (workspaceGroup && !structuredTypeViewOpen) {
      workspaceGroup.setLayout(
        isFocusMode
          ? [0, 100]
          : leavingFocus && focusRestoreWorkspaceLayoutRef.current.length === 2
            ? focusRestoreWorkspaceLayoutRef.current
            : workspacePanelLayoutRef.current,
      );
    }
    if (leavingFocus) {
      setIsSidebarCollapsed(sidebarCollapsedBeforeFocusRef.current);
      queueMicrotask(() => {
        leavingFocusRef.current = false;
      });
    }
    wasFocusModeRef.current = isFocusMode;
  }, [isFocusMode, structuredTypeViewOpen]);

  useEffect(() => {
    if (!isSidebarCollapsed || isFocusMode || leavingFocusRef.current) return;

    const panelGroup = panelGroupRef.current;
    if (!panelGroup) return;

    panelGroup.setLayout([0, 100]);
  }, [isFocusMode, isSidebarCollapsed, structuredTypeViewOpen]);

  const handlePanelLayout = (layout: number[]) => {
    if (!isFocusMode && layout[0] > 0) {
      expandedPanelLayoutRef.current = layout;
    }
  };

  const handleWorkspacePanelLayout = (layout: number[]) => {
    if (!isFocusMode && layout[0] > 0) workspacePanelLayoutRef.current = layout;
  };

  const handleRestoreSidebar = () => {
    panelGroupRef.current?.setLayout(expandedPanelLayoutRef.current);
  };

  if (vault.status === "pick-vault" || vault.status === "error") {
    return (
      <div className="flex h-screen w-screen items-center justify-center bg-zerus-surface">
        <div className="max-w-sm text-center">
          <ZerusLogo
            alt="Zerus"
            className="mx-auto h-20 w-20 rounded-xl"
          />
          <h1 className="mt-4 text-xl font-semibold">Zerus</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Your notes are plain markdown files in a folder — folders are types.
            Point Zerus at a folder to open your vault.
          </p>
          {vault.status === "error" && (
            <p className="mt-3 rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">
              Couldn't open the vault: {vault.error}
            </p>
          )}
          <Button
            className="mt-5 gap-2"
            onClick={() => void chooseVaultFolder()}
          >
            <FolderOpen size={16} /> Choose vault folder
          </Button>
        </div>
      </div>
    );
  }

  if (vault.status !== "ready") {
    return (
      <div className="flex h-screen w-screen items-center justify-center bg-zerus-surface">
        <Loader2 className="animate-spin text-muted-foreground" />
      </div>
    );
  }

  const editorWorkspace = (
    <div className="flex h-full min-w-0">
      <div className="flex min-w-0 flex-1 flex-col">
        <div className="min-h-0 flex-1">
          <EditorPane
            note={selectedNote}
            allNotes={notes}
            tasks={tasks}
            extraTypes={vault.extraTypes}
            schemas={vault.schemas}
            typeIcons={vault.typeIcons}
            vaultLocation={vault.location}
            isBusy={
              selectedNote ? vault.busyNoteIds.has(selectedNote.id) : false
            }
            isLoading={
              selectedNote ? vault.loadingNoteIds.has(selectedNote.id) : false
            }
            isRefreshing={vault.isRefreshing}
            onOpenNote={handleOpenNote}
            onOpenTask={handleOpenTask}
            onCopyExternalToVault={(id, typePath) =>
              void handleCopyExternalToVault(id, typePath)
            }
            onMoveExternalToVault={(id, typePath) =>
              void handleMoveExternalToVault(id, typePath)
            }
            onMoveSavedLinkToVault={(id, typePath) =>
              void (async () => {
                if (!(await moveSavedLinkToVault(id, typePath))) return;
                setListFilters(EMPTY_NOTE_LIST_FILTERS);
                setSearch("");
                navigate({
                  filter: { kind: "type", path: typePath },
                  selectedNoteId: id,
                });
              })()
            }
            isFocusMode={isFocusMode}
            onToggleFocusMode={handleToggleFocusMode}
            isDesktop={vault.isDesktop}
            aiOpen={aiOpen}
            onToggleAi={() => setAiOpen((current) => !current)}
            conflict={
              selectedNote ? (vault.conflicts[selectedNote.id] ?? null) : null
            }
            canNavigateBack={
              (structuredTypeViewOpen && expandedEditorOpen) ||
              navigation.back.length > 0
            }
            canNavigateForward={navigation.forward.length > 0}
            onNavigateBack={handleEditorNavigateBack}
            onNavigateForward={navigateForward}
          />
        </div>
      </div>
      {vault.isDesktop && (
        <AiPanel
          open={aiOpen}
          note={selectedNote}
          notes={notes}
          targetDirectory={
            selectedNote
              ? noteContainingFolder(selectedNote, vault.location)
              : vault.location
          }
          vaultLocation={vault.location}
          onOpenChange={setAiOpen}
        />
      )}
    </div>
  );

  return (
    <>
      <AutoUpdater />
      <div
        className={cn(
          "relative flex h-screen w-screen overflow-hidden",
          isSidebarCollapsed && !isFocusMode && "pl-12",
        )}
      >
      {isSidebarCollapsed && !isFocusMode && (
        <div
          className={cn(
            "absolute inset-y-0 left-0 w-12",
            vault.isRefreshing && "pointer-events-none",
          )}
        >
          <CollapsedSidebar
            notes={notes}
            extraTypes={vault.extraTypes}
            typeIcons={vault.typeIcons}
            typeOrder={typeOrder}
            filter={filter}
            isDesktop={vault.isDesktop}
            defaultNoteType={defaultNoteType}
            hideSubtypeNotes={hideSubtypeNotes}
            onDefaultNoteTypeChange={handleDefaultNoteTypeChange}
            onHideSubtypeNotesChange={handleHideSubtypeNotesChange}
            onFilterChange={handleFilterChange}
            onRestore={handleRestoreSidebar}
          />
        </div>
      )}
      <div className="min-w-0 flex-1">
        <ResizablePanelGroup
          ref={panelGroupRef}
          direction="horizontal"
          onLayout={handlePanelLayout}
        >
        <ResizablePanel
          id="sidebar"
          order={1}
          ref={sidebarPanelRef}
          defaultSize={SIDEBAR_DEFAULT_SIZE}
          minSize={12}
          maxSize={28}
          collapsible
          collapsedSize={0}
          onCollapse={() => setIsSidebarCollapsed(true)}
          onExpand={() => setIsSidebarCollapsed(false)}
          className={isFocusMode ? "invisible" : undefined}
        >
          <div
            className={cn(
              "h-full",
              vault.isRefreshing && "pointer-events-none",
            )}
          >
            <Sidebar
              notes={notes}
              taskCount={tasks.length}
              extraTypes={vault.extraTypes}
              typeIcons={vault.typeIcons}
              typeOrder={typeOrder}
              filter={filter}
              isDesktop={vault.isDesktop}
              vaultLocation={vault.location}
              defaultNoteType={defaultNoteType}
              hideSubtypeNotes={hideSubtypeNotes}
              onDefaultNoteTypeChange={handleDefaultNoteTypeChange}
              onHideSubtypeNotesChange={handleHideSubtypeNotesChange}
              onTypeOrderChange={handleTypeOrderChange}
              onFilterChange={handleFilterChange}
              onOpenTypeInNewTab={handleOpenTypeInNewTab}
              onCollapse={() => sidebarPanelRef.current?.collapse()}
            />
          </div>
        </ResizablePanel>
        <ResizableHandle
          className={isFocusMode ? "hidden" : "w-px bg-transparent"}
        />
        <ResizablePanel
          id="workspace"
          order={2}
          defaultSize={WORKSPACE_DEFAULT_SIZE}
          minSize={55}
        >
          <div className="flex h-full min-w-0 flex-col">
            {noteTabs.enabled && (
              <NoteTabs
                tabs={noteTabs.tabs}
                activeTabId={noteTabs.activeTabId}
                notes={notes}
                typeIcons={vault.typeIcons}
                onActivate={handleActivateTab}
                onTogglePinned={(tabId) =>
                  setNoteTabs((tabs) => toggleNoteTabPinned(tabs, tabId))
                }
                onClose={handleCloseTab}
              />
            )}
            <div className="min-h-0 min-w-0 flex-1">
              {filter.kind === "tasks" ? (
                <TasksWorkspace
                  tasks={tasks}
                  categoryOptions={taskCategoryOptions}
                  notes={notes}
                  selectedTaskId={selectedTaskId}
                  onSelectedTaskChange={setSelectedTaskId}
                  onCreateTask={createTask}
                  onUpdateTask={updateTask}
                  onDeleteTask={deleteTask}
                  onCategoryOptionsChange={updateTaskCategoryOptions}
                  onDeleteCategory={deleteTaskCategory}
                  onOpenNote={handleOpenNote}
                />
              ) : structuredTypeViewOpen && activeTypeView && filter.kind === "type" ? (
                <TypeViewWorkspace
                  typePath={filter.path}
                  notes={notes}
                  schemas={vault.schemas}
                  config={activeTypeView}
                  isRefreshing={vault.isRefreshing}
                  editorOpen={expandedEditorOpen}
                  hideSubtypeNotes={hideSubtypeNotes}
                  editor={editorWorkspace}
                  onOpenNote={handleOpenStructuredNote}
                  onCreateNote={() => void handleCreateNote()}
                  onConfigChange={handleTypeViewChange}
                  onHideSubtypeNotesChange={handleHideSubtypeNotesChange}
                  onSetProperty={setNoteProperty}
                />
              ) : (
                <ResizablePanelGroup
                  ref={workspacePanelGroupRef}
                  direction="horizontal"
                  onLayout={handleWorkspacePanelLayout}
                >
                  <ResizablePanel
                    id="note-list"
                    order={1}
                    defaultSize={NOTE_LIST_WORKSPACE_SIZE}
                    minSize={isFocusMode ? 0 : NOTE_LIST_WORKSPACE_SIZE}
                    maxSize={48}
                    collapsible={isFocusMode}
                    className={isFocusMode ? "invisible" : undefined}
                  >
                    <NoteList
                      notes={visibleNotes}
                      filterOptions={filterOptions}
                      filter={filter}
                      listFilters={listFilters}
                      selectedNoteId={selectedNoteId}
                      search={search}
                      isRefreshing={vault.isRefreshing}
                      onSearchChange={setSearch}
                      onListFiltersChange={setListFilters}
                      onSelectNote={handleSelectNote}
                      onOpenNoteInNewTab={handleOpenNoteInNewTab}
                      onCreateNote={() => void handleCreateNote()}
                      onCreateFile={() => void handleCreateFile()}
                      onCreateLink={handleCreateLink}
                      onOpenExternalNotes={() => void handleOpenExternalNotes()}
                      viewMode={activeTypeView?.mode}
                      onViewModeChange={(mode) => handleTypeViewChange({ mode })}
                      hideSubtypeNotes={hideSubtypeNotes}
                      onHideSubtypeNotesChange={handleHideSubtypeNotesChange}
                    />
                  </ResizablePanel>
                  <ResizableHandle
                    className={isFocusMode ? "hidden" : "w-px bg-border/60"}
                  />
                  <ResizablePanel
                    id="editor"
                    order={2}
                    defaultSize={EDITOR_WORKSPACE_SIZE}
                    minSize={30}
                  >
                    {editorWorkspace}
                  </ResizablePanel>
                </ResizablePanelGroup>
              )}
            </div>
          </div>
        </ResizablePanel>
        </ResizablePanelGroup>
      </div>
      {vault.isRefreshing && (
        <div className="pointer-events-none absolute right-4 top-4 z-50 flex items-center gap-2 rounded-full border border-border/60 bg-background/90 px-3 py-1.5 text-xs text-muted-foreground shadow-sm backdrop-blur">
          <Loader2 className="h-3.5 w-3.5 animate-spin" />
          Refreshing notes…
        </div>
      )}
      </div>
    </>
  );
};

export default Index;
