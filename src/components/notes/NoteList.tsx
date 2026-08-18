import { useEffect, useMemo, useRef, useState } from "react";
import { format, isToday, isYesterday } from "date-fns";
import {
  Archive,
  ArchiveRestore,
  FolderSearch,
  FileText,
  FilePlus2,
  Link2,
  Pin,
  Plus,
  Search,
  Trash2,
  Undo2,
  X,
} from "@/lib/icons";
import { Input } from "@/components/ui/input";
import { Button, buttonVariants } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";
import { cn } from "@/lib/utils";
import {
  type Note,
  isArchived,
  isExternalNote,
  noteSnippet,
  noteTitle,
  noteTypePath,
  typeKey,
} from "@/lib/note-utils";
import type { NoteFilter } from "@/lib/filters";
import type { NoteListFilters as NoteListFilterState } from "@/lib/filters";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import {
  closeExternalNote,
  deleteNoteForever,
  emptyTrash,
  restoreNote,
  revealNoteInDesktop,
  toggleNotePinned,
  toggleNoteArchived,
  trashNote,
} from "@/store/notes-store";
import { NoteListFilters } from "./NoteListFilters";
import { TypeViewSwitcher } from "./TypeViewWorkspace";
import type { NoteViewMode } from "@/lib/note-views";
import { fileExtension, getFileHubReference } from "@/lib/file-hubs";
import { getLinkHubReference } from "@/lib/link-hubs";
import { AddLinkDialog } from "./AddLinkDialog";
import {
  fileManagerName,
  primaryModifierLabel,
} from "@/lib/desktop-platform";

const INITIAL_NOTE_COUNT = 100;
const NOTE_LOAD_INCREMENT = 50;

function formatNoteDate(iso: string): string {
  const date = new Date(iso);
  if (isToday(date)) return format(date, "HH:mm");
  if (isYesterday(date)) return "Yesterday";
  return format(date, "d MMM yyyy");
}

interface NoteListProps {
  notes: Note[];
  filterOptions: Note[];
  filter: NoteFilter;
  listFilters: NoteListFilterState;
  selectedNoteId: string | null;
  search: string;
  isRefreshing: boolean;
  onSearchChange: (value: string) => void;
  onListFiltersChange: (filters: NoteListFilterState) => void;
  onSelectNote: (id: string) => void;
  onOpenNoteInNewTab: (id: string) => void;
  onCreateNote: () => void;
  onCreateFile: () => void;
  onCreateLink: (url: string) => Promise<void>;
  onOpenExternalNotes: () => void;
  viewMode?: NoteViewMode;
  onViewModeChange?: (mode: NoteViewMode) => void;
}

export function NoteList({
  notes,
  filterOptions,
  filter,
  listFilters,
  selectedNoteId,
  search,
  isRefreshing,
  onSearchChange,
  onListFiltersChange,
  onSelectNote,
  onOpenNoteInNewTab,
  onCreateNote,
  onCreateFile,
  onCreateLink,
  onOpenExternalNotes,
  viewMode,
  onViewModeChange,
}: NoteListProps) {
  const [trashTarget, setTrashTarget] = useState<Note | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<Note | null>(null);
  const [closeExternalTarget, setCloseExternalTarget] = useState<Note | null>(
    null,
  );
  const [visibleNoteCount, setVisibleNoteCount] = useState(INITIAL_NOTE_COUNT);
  const [addLinkOpen, setAddLinkOpen] = useState(false);
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const loadMoreRef = useRef<HTMLDivElement>(null);
  const inTrash = filter.kind === "trash";
  const inExternal = filter.kind === "external";
  const inFiles = filter.kind === "files";
  const inLinks = filter.kind === "links";
  const filterKey =
    filter.kind === "type" ? `type:${filter.path.join("/")}` : filter.kind;
  const listFilterKey = JSON.stringify(listFilters);
  const visibleNotes = useMemo(
    () => notes.slice(0, visibleNoteCount),
    [notes, visibleNoteCount],
  );
  const hasMoreNotes = visibleNoteCount < notes.length;
  const heading =
    filter.kind === "type"
      ? filter.path.join(" / ")
      : filter.kind === "all"
        ? "All Notes"
        : filter.kind === "external"
          ? "External Notes"
          : filter.kind === "files"
            ? "Files"
            : filter.kind === "links"
              ? "Links"
              : "Trash";

  useEffect(() => {
    setVisibleNoteCount(INITIAL_NOTE_COUNT);
    scrollContainerRef.current?.scrollTo({ top: 0 });
  }, [filterKey, listFilterKey, search]);

  useEffect(() => {
    const root = scrollContainerRef.current;
    const target = loadMoreRef.current;
    if (!root || !target || !hasMoreNotes) return;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        setVisibleNoteCount((count) =>
          Math.min(count + NOTE_LOAD_INCREMENT, notes.length),
        );
      },
      { root },
    );

    observer.observe(target);
    return () => observer.disconnect();
  }, [hasMoreNotes, notes.length]);

  return (
    <div className="flex h-full flex-col bg-zerus-surface">
      <div
        className={cn(
          "flex items-center gap-2 border-b border-border/60 px-3 py-2.5",
          isRefreshing && "pointer-events-none opacity-70",
        )}
      >
        <span className="flex-1 truncate text-sm font-semibold">{heading}</span>
        {filter.kind === "type" && viewMode && onViewModeChange && (
          <TypeViewSwitcher
            typeName={heading}
            mode={viewMode}
            onChange={onViewModeChange}
          />
        )}
        {inTrash ? (
          notes.length > 0 && (
            <Button
              variant="ghost"
              size="sm"
              className="h-7 text-xs text-destructive hover:text-destructive"
              onClick={() => void emptyTrash()}
            >
              Empty trash
            </Button>
          )
        ) : (
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7"
            title={undefined}
            onClick={() => {
              if (inFiles) onCreateFile();
              else if (inLinks) setAddLinkOpen(true);
              else if (inExternal) onOpenExternalNotes();
              else onCreateNote();
            }}
          >
            <Tooltip>
              <TooltipTrigger asChild>
                <span className="flex items-center">
                  {inFiles ? (
                    <FilePlus2 size={16} />
                  ) : inLinks ? (
                    <Link2 size={16} />
                  ) : (
                    <Plus size={16} />
                  )}
                </span>
              </TooltipTrigger>
              <TooltipContent>
                {inFiles
                  ? "Add a file to Files"
                  : inLinks
                    ? "Add a URL to Links"
                  : inExternal
                    ? "Open markdown file(s)"
                    : `New note (${primaryModifierLabel}N)`}
              </TooltipContent>
            </Tooltip>
          </Button>
        )}
      </div>
      <div
        className={cn(
          "grid grid-cols-[minmax(0,1fr)_auto] gap-2 px-3 py-2",
          isRefreshing && "pointer-events-none opacity-70",
        )}
      >
        <div className="relative min-w-0">
          <Search
            size={14}
            className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground"
          />
          <Input
            value={search}
            onChange={(event) => onSearchChange(event.target.value)}
            placeholder={
              inFiles ? "Search files…" : inLinks ? "Search links…" : "Search notes…"
            }
            className="h-8 bg-zerus-editor pl-8 text-sm"
          />
        </div>
        <NoteListFilters
          notes={filterOptions}
          showTypes={filter.kind === "all"}
          showFileTypes={inFiles}
          showArchivedToggle={!inTrash && !inExternal}
          filters={listFilters}
          onChange={onListFiltersChange}
        />
      </div>
      <div ref={scrollContainerRef} className="flex-1 overflow-y-auto">
        {notes.length === 0 && (
          <p className="px-4 py-8 text-center text-sm text-muted-foreground">
            {search ||
            listFilters.date ||
            listFilters.showArchived ||
            listFilters.typeKeys.length ||
            listFilters.fileExtensions.length ||
            listFilters.properties.length
              ? "No notes match these filters."
              : inTrash
              ? "Trash is empty."
              : inExternal
                ? "Open markdown files from anywhere on your computer."
                : inFiles
                  ? "Files attached to notes will appear here."
                  : inLinks
                    ? "URLs added to Links will appear here."
                : "No notes here yet."}
          </p>
        )}
        {visibleNotes.map((note) => {
          const noteName = noteTitle(note);
          const external = isExternalNote(note);
          const archived = isArchived(note);
          const fileHub = getFileHubReference(note);
          const linkHub = getLinkHubReference(note);
          const title = inFiles && fileHub ? fileHub.name : noteName;
          const snippet = inFiles
            ? noteName
            : inLinks && linkHub
              ? linkHub.url
              : noteSnippet(note);
          const type = typeKey(noteTypePath(note));
          return (
            <ContextMenu key={note.id}>
              <ContextMenuTrigger asChild disabled={isRefreshing}>
                <button
                  onClick={() => onSelectNote(note.id)}
                  onAuxClick={(event) => {
                    if (event.button !== 1) return;
                    event.preventDefault();
                    onOpenNoteInNewTab(note.id);
                  }}
                  className={cn(
                    "block w-full border-b border-border/40 px-4 py-3 text-left transition-colors",
                    note.id === selectedNoteId
                      ? "bg-zerus-accent/10"
                      : "hover:bg-zerus-text/[0.03]",
                  )}
                >
                  <div className="flex items-center gap-1.5">
                    {fileHub && (
                      <FileText size={12} className="shrink-0 text-zerus-accent" />
                    )}
                    {linkHub && (
                      <Link2 size={12} className="shrink-0 text-zerus-accent" />
                    )}
                    {note.pinned && (
                      <Pin size={12} className="shrink-0 text-zerus-accent" />
                    )}
                    {archived && (
                      <Archive
                        size={12}
                        className="shrink-0 text-muted-foreground"
                      />
                    )}
                    <span className="truncate text-sm font-medium">
                      {title}
                    </span>
                  </div>
                  {snippet && (
                    <p className="mt-0.5 truncate text-xs text-muted-foreground">
                      {snippet}
                    </p>
                  )}
                  <div className="mt-1.5 flex items-center gap-2">
                    <Badge
                      variant="secondary"
                      className="h-4 max-w-[60%] rounded px-1.5 text-[10px] font-normal"
                    >
                      <span className="truncate">
                        {fileHub
                          ? `${fileExtension(fileHub.name).toUpperCase()} · ${type || "unfiled"}`
                          : linkHub
                            ? "LINK"
                          : external
                            ? "external"
                            : type || "unfiled"}
                      </span>
                    </Badge>
                    <span className="text-[11px] text-muted-foreground">
                      {formatNoteDate(note.updatedAt)}
                    </span>
                  </div>
                </button>
              </ContextMenuTrigger>
              <ContextMenuContent>
                <ContextMenuItem onClick={() => onOpenNoteInNewTab(note.id)}>
                  <FilePlus2 size={14} className="mr-2" /> Open in new tab
                </ContextMenuItem>
                <ContextMenuSeparator />
                <ContextMenuItem
                  onClick={() => void revealNoteInDesktop(note.id)}
                >
                  <FolderSearch size={14} className="mr-2" /> Reveal in{" "}
                  {fileManagerName}
                </ContextMenuItem>
                {external ? (
                  <>
                    <ContextMenuItem
                      onClick={() => setCloseExternalTarget(note)}
                    >
                      <X size={14} className="mr-2" /> Close note
                    </ContextMenuItem>
                  </>
                ) : inTrash ? (
                  <>
                    <ContextMenuItem onClick={() => void restoreNote(note.id)}>
                      <Undo2 size={14} className="mr-2" /> Restore
                    </ContextMenuItem>
                    <ContextMenuItem
                      className="text-destructive"
                      onClick={() => setDeleteTarget(note)}
                    >
                      <Trash2 size={14} className="mr-2" /> Delete forever
                    </ContextMenuItem>
                  </>
                ) : (
                  <>
                    <ContextMenuItem onClick={() => toggleNoteArchived(note.id)}>
                      {archived ? (
                        <ArchiveRestore size={14} className="mr-2" />
                      ) : (
                        <Archive size={14} className="mr-2" />
                      )}
                      {archived ? "Unarchive" : "Archive"}
                    </ContextMenuItem>
                    <ContextMenuItem onClick={() => toggleNotePinned(note.id)}>
                      <Pin size={14} className="mr-2" />
                      {note.pinned ? "Unpin" : "Pin"}
                    </ContextMenuItem>
                    <ContextMenuItem
                      className="text-destructive"
                      onClick={() => setTrashTarget(note)}
                    >
                      <Trash2 size={14} className="mr-2" /> Move to trash
                    </ContextMenuItem>
                  </>
                )}
              </ContextMenuContent>
            </ContextMenu>
          );
        })}
        {hasMoreNotes && (
          <div
            ref={loadMoreRef}
            className="flex h-12 items-center justify-center text-xs text-muted-foreground"
            aria-live="polite"
          >
            Showing {visibleNotes.length} of {notes.length} notes
          </div>
        )}
      </div>
      <AlertDialog
        open={trashTarget !== null}
        onOpenChange={(open) => {
          if (!open) setTrashTarget(null);
        }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Move “{trashTarget ? noteTitle(trashTarget) : "this note"}” to
              trash?
            </AlertDialogTitle>
            <AlertDialogDescription>
              You can restore this note later from Trash.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className={buttonVariants({ variant: "destructive" })}
              onClick={() => {
                if (trashTarget) void trashNote(trashTarget.id);
              }}
            >
              Move to trash
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <AlertDialog
        open={closeExternalTarget !== null}
        onOpenChange={(open) => !open && setCloseExternalTarget(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Close “{closeExternalTarget
                ? noteTitle(closeExternalTarget)
                : "this note"}”?
            </AlertDialogTitle>
            <AlertDialogDescription>
              Zerus will stop tracking this external note. The file will be
              saved and left in its current location.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                if (closeExternalTarget) {
                  void closeExternalNote(closeExternalTarget.id);
                }
              }}
            >
              Close note
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <AlertDialog
        open={deleteTarget !== null}
        onOpenChange={(open) => !open && setDeleteTarget(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Delete “{deleteTarget ? noteTitle(deleteTarget) : "this note"}” forever?
            </AlertDialogTitle>
            <AlertDialogDescription>
              This cannot be undone.
              {deleteTarget && getFileHubReference(deleteTarget)?.managed
                ? ` The managed file “${getFileHubReference(deleteTarget)?.name}” will also be permanently deleted.`
                : ""}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className={buttonVariants({ variant: "destructive" })}
              onClick={() => {
                if (deleteTarget) void deleteNoteForever(deleteTarget.id);
              }}
            >
              Delete forever
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <AddLinkDialog
        open={addLinkOpen}
        onOpenChange={setAddLinkOpen}
        onAdd={onCreateLink}
      />
    </div>
  );
}
