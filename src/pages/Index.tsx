import {
  lazy,
  Suspense,
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
import { EditorPane } from "@/components/notes/EditorPane";
import { GrimoireLogo } from "@/components/GrimoireLogo";
import {
  chooseVaultFolder,
  copyExternalNoteToVault,
  createFileNote,
  createNote,
  initStore,
  moveExternalNoteToVault,
  onDesktopNotesOpened,
  openExternalNotes,
  prioritizeNoteLoad,
  refreshVaultFromDisk,
  useVault,
} from "@/store/notes-store";
import {
  EMPTY_NOTE_LIST_FILTERS,
  filterNotes,
  type NoteFilter,
  type NoteListFilters,
} from "@/lib/filters";
import { DEFAULT_TYPE } from "@/lib/note-utils";
import {
  loadDefaultNoteType,
  loadHideSubtypeNotes,
  loadNoteTypeOrder,
  saveDefaultNoteType,
  saveHideSubtypeNotes,
  saveNoteTypeOrder,
} from "@/lib/note-preferences";
import { cn } from "@/lib/utils";
import { showError } from "@/utils/toast";
import { AutoUpdater } from "@/lib/auto-updater";

const TerminalPanel = lazy(() =>
  import("@/components/terminal/TerminalPanel").then((module) => ({
    default: module.TerminalPanel,
  })),
);

const SIDEBAR_DEFAULT_SIZE = 15;
const NOTE_LIST_DEFAULT_SIZE = 18;
const EDITOR_DEFAULT_SIZE = 67;
const DEFAULT_PANEL_LAYOUT = [
  SIDEBAR_DEFAULT_SIZE,
  NOTE_LIST_DEFAULT_SIZE,
  EDITOR_DEFAULT_SIZE,
];

const Index = () => {
  const vault = useVault();
  const [filter, setFilter] = useState<NoteFilter>({ kind: "all" });
  const [search, setSearch] = useState("");
  const [listFilters, setListFilters] =
    useState<NoteListFilters>(EMPTY_NOTE_LIST_FILTERS);
  const [selectedNoteId, setSelectedNoteId] = useState<string | null>(null);
  const [isFocusMode, setIsFocusMode] = useState(false);
  const [terminalOpen, setTerminalOpen] = useState(false);
  const [terminalLoaded, setTerminalLoaded] = useState(false);
  const [defaultNoteType, setDefaultNoteType] = useState<string[]>(DEFAULT_TYPE);
  const [typeOrder, setTypeOrder] = useState<string[]>([]);
  const [hideSubtypeNotes, setHideSubtypeNotes] = useState(false);
  const panelGroupRef = useRef<ImperativePanelGroupHandle>(null);
  const sidebarPanelRef = useRef<ImperativePanelHandle>(null);
  const [isSidebarCollapsed, setIsSidebarCollapsed] = useState(false);
  const expandedPanelLayoutRef = useRef([...DEFAULT_PANEL_LAYOUT]);
  const previousPanelLayoutRef = useRef([...DEFAULT_PANEL_LAYOUT]);

  useEffect(() => {
    const stopListening = onDesktopNotesOpened(
      (ids, firstNoteIsExternal, firstNoteIsFileHub) => {
        setFilter(
          firstNoteIsFileHub
            ? { kind: "files" }
            : firstNoteIsExternal
              ? { kind: "external" }
              : { kind: "all" },
        );
        setListFilters(EMPTY_NOTE_LIST_FILTERS);
        setSearch("");
        setSelectedNoteId(ids[0]);
      },
    );
    initStore();
    return stopListening;
  }, []);

  useEffect(() => {
    const refresh = () => void refreshVaultFromDisk();
    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", refresh);
    return () => {
      window.removeEventListener("focus", refresh);
      document.removeEventListener("visibilitychange", refresh);
    };
  }, []);

  const { notes } = vault;
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

  const handleFilterChange = (nextFilter: NoteFilter) => {
    setFilter(nextFilter);
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

  const handleTerminalOpenChange = useCallback((open: boolean) => {
    if (open) setTerminalLoaded(true);
    setTerminalOpen(open);
  }, []);

  const handleToggleTerminal = useCallback(() => {
    handleTerminalOpenChange(!terminalOpen);
  }, [handleTerminalOpenChange, terminalOpen]);

  const handleCreateNote = async () => {
    if (vault.isRefreshing) return;
    const typePath =
      filter.kind === "type"
        ? filter.path
        : filter.kind === "all"
          ? defaultNoteType
          : DEFAULT_TYPE;
    const note = await createNote(typePath);
    if (!note) return;
    if (
      filter.kind === "trash" ||
      filter.kind === "external" ||
      filter.kind === "files"
    ) {
      setFilter({ kind: "all" });
    }
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    setSelectedNoteId(note.id);
  };

  const handleCreateFile = async () => {
    if (vault.isRefreshing) return;
    const note = await createFileNote(defaultNoteType);
    if (!note) return;
    setFilter({ kind: "files" });
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    setSelectedNoteId(note.id);
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

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (
        !(event.metaKey || event.ctrlKey) ||
        event.shiftKey ||
        event.altKey ||
        event.key.toLowerCase() !== "j"
      ) {
        return;
      }
      event.preventDefault();
      if (vault.isRefreshing) return;
      if (!vault.isDesktop) return;
      if (!selectedNote) {
        showError("Select a note to open its terminal.");
        return;
      }
      handleToggleTerminal();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [handleToggleTerminal, selectedNote, vault.isDesktop, vault.isRefreshing]);

  const handleOpenNote = (id: string) => {
    setFilter({ kind: "all" });
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    setSelectedNoteId(id);
    void prioritizeNoteLoad(id);
  };

  const handleSelectNote = (id: string) => {
    setSelectedNoteId(id);
    void prioritizeNoteLoad(id);
  };

  const handleOpenExternalNotes = async () => {
    const ids = await openExternalNotes();
    if (!ids.length) return;
    setFilter({ kind: "external" });
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    setSelectedNoteId(ids[0]);
  };

  const handleMoveExternalToVault = async (id: string, typePath: string[]) => {
    const moved = await moveExternalNoteToVault(id, typePath);
    if (!moved) return;
    setFilter({ kind: "type", path: typePath });
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    setSelectedNoteId(id);
  };

  const handleCopyExternalToVault = async (id: string, typePath: string[]) => {
    const copied = await copyExternalNoteToVault(id, typePath);
    if (!copied) return;
    setFilter({ kind: "type", path: typePath });
    setListFilters(EMPTY_NOTE_LIST_FILTERS);
    setSearch("");
    setSelectedNoteId(copied.id);
  };

  const handleToggleFocusMode = () => {
    const panelGroup = panelGroupRef.current;
    if (!panelGroup) return;

    if (!isFocusMode) {
      previousPanelLayoutRef.current = panelGroup.getLayout();
    }
    setIsFocusMode((focused) => !focused);
  };

  useEffect(() => {
    const panelGroup = panelGroupRef.current;
    if (!panelGroup) return;
    panelGroup.setLayout(
      isFocusMode ? [0, 0, 100] : previousPanelLayoutRef.current,
    );
  }, [isFocusMode]);

  useEffect(() => {
    if (!isSidebarCollapsed || isFocusMode) return;

    const panelGroup = panelGroupRef.current;
    if (!panelGroup) return;

    const noteListSize = expandedPanelLayoutRef.current[1];
    panelGroup.setLayout([0, noteListSize, 100 - noteListSize]);
  }, [isFocusMode, isSidebarCollapsed]);

  const handlePanelLayout = (layout: number[]) => {
    if (!isFocusMode && layout[0] > 0) {
      expandedPanelLayoutRef.current = layout;
    }
  };

  const handleRestoreSidebar = () => {
    panelGroupRef.current?.setLayout(expandedPanelLayoutRef.current);
  };

  if (vault.status === "pick-vault" || vault.status === "error") {
    return (
      <div className="flex h-screen w-screen items-center justify-center bg-grim-surface">
        <div className="max-w-sm text-center">
          <GrimoireLogo
            alt="Grimoire"
            className="mx-auto h-20 w-20 rounded-xl"
          />
          <h1 className="mt-4 text-xl font-semibold">Grimoire</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Your notes are plain markdown files in a folder — folders are types.
            Point Grimoire at a folder to open your vault.
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
      <div className="flex h-screen w-screen items-center justify-center bg-grim-surface">
        <Loader2 className="animate-spin text-muted-foreground" />
      </div>
    );
  }

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
              onCollapse={() => sidebarPanelRef.current?.collapse()}
            />
          </div>
        </ResizablePanel>
        <ResizableHandle
          className={isFocusMode ? "hidden" : "w-px bg-transparent"}
        />
        <ResizablePanel
          defaultSize={NOTE_LIST_DEFAULT_SIZE}
          minSize={isFocusMode ? 0 : 18}
          maxSize={40}
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
            onCreateNote={() => void handleCreateNote()}
            onCreateFile={() => void handleCreateFile()}
            onOpenExternalNotes={() => void handleOpenExternalNotes()}
          />
        </ResizablePanel>
        <ResizableHandle
          className={isFocusMode ? "hidden" : "w-px bg-border/60"}
        />
        <ResizablePanel defaultSize={EDITOR_DEFAULT_SIZE} minSize={30}>
          <div className="flex h-full min-w-0">
            <div className="min-w-0 flex-1">
              <EditorPane
                note={selectedNote}
                allNotes={notes}
                extraTypes={vault.extraTypes}
                schemas={vault.schemas}
                typeIcons={vault.typeIcons}
                vaultLocation={vault.location}
                isBusy={
                  selectedNote ? vault.busyNoteIds.has(selectedNote.id) : false
                }
                isLoading={
                  selectedNote
                    ? vault.loadingNoteIds.has(selectedNote.id)
                    : false
                }
                isRefreshing={vault.isRefreshing}
                onOpenNote={handleOpenNote}
                onCopyExternalToVault={(id, typePath) =>
                  void handleCopyExternalToVault(id, typePath)
                }
                onMoveExternalToVault={(id, typePath) =>
                  void handleMoveExternalToVault(id, typePath)
                }
                isFocusMode={isFocusMode}
                onToggleFocusMode={handleToggleFocusMode}
                isDesktop={vault.isDesktop}
                terminalOpen={terminalOpen}
                onToggleTerminal={handleToggleTerminal}
                conflict={
                  selectedNote
                    ? (vault.conflicts[selectedNote.id] ?? null)
                    : null
                }
              />
            </div>
            {vault.isDesktop && terminalLoaded && (
              <Suspense fallback={null}>
                <TerminalPanel
                  open={terminalOpen}
                  note={selectedNote}
                  vaultLocation={vault.location}
                  onOpenChange={handleTerminalOpenChange}
                />
              </Suspense>
            )}
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
