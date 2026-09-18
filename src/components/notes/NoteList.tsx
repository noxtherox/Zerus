import { useEffect, useMemo, useRef, useState } from "react";
import { format, isToday, isYesterday } from "date-fns";
import {
  Archive,
  Copy,
  ArchiveRestore,
  CheckSquare,
  FolderSearch,
  FileText,
  ImageIcon,
  FilePlus2,
  Link2,
  Pin,
  Plus,
  Search,
  SlidersHorizontal,
  Trash2,
  Undo2,
  X,
} from "@/lib/icons";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { buttonVariants } from "@/components/ui/button-variants";
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
  noteListTitle,
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
  duplicateNote,
  deleteTrashedImageForever,
  deleteNoteForever,
  emptyTrash,
  restoreNote,
  restoreTrashedImage,
  openImageInDefaultApp,
  revealNoteInDesktop,
  trashNote,
  type TrashedImage,
} from "@/store/notes-store";
import { NoteListFilters } from "./NoteListFilters";
import { TypeViewSwitcher } from "./TypeViewWorkspace";
import { PropertyPills } from "./PropertyPills";
import type { SavedTypeView, TypeViewConfig } from "@/lib/note-views";
import type { PropertySchemas } from "@/lib/properties";
import { fileExtension, getFileHubReference } from "@/lib/file-hubs";
import { getLinkHubReference } from "@/lib/link-hubs";
import { AddLinkDialog } from "./AddLinkDialog";
import {
  fileManagerName,
  primaryModifierLabel,
} from "@/lib/desktop-platform";
import { handleMiddleMouseDown } from "@/lib/middle-click";
import { useBulkSelection } from "@/lib/use-bulk-selection";
import {
  BulkActionsToolbar,
  type BulkMutationRequest,
} from "./BulkActionsToolbar";

const INITIAL_NOTE_COUNT = 40;
const NOTE_LOAD_INCREMENT = 30;

function formatNoteDate(iso: string): string {
  const date = new Date(iso);
  if (isToday(date)) return format(date, "HH:mm");
  if (isYesterday(date)) return "Yesterday";
  return format(date, "d MMM yyyy");
}

interface NoteListProps {
  notes: Note[];
  trashedImages: TrashedImage[];
  filterOptions: Note[];
  filter: NoteFilter;
  listFilters: NoteListFilterState;
  selectedNoteId: string | null;
  search: string;
  isRefreshing: boolean;
  onSearchChange: (value: string) => void;
  onListFiltersChange: (filters: NoteListFilterState) => void;
  visibleProperties: string[];
  onVisiblePropertiesChange: (properties: string[]) => void;
  onSelectNote: (id: string) => void;
  onOpenNoteInNewTab: (id: string) => void;
  onCreateNote: () => void;
  onCreateFile: () => void;
  onCreateLink: (url: string) => Promise<void>;
  onOpenExternalNotes: () => void;
  viewConfig?: TypeViewConfig;
  savedViews: SavedTypeView[];
  onViewModeChange?: (mode: TypeViewConfig["mode"]) => void;
  onApplySavedView: (view: SavedTypeView) => void;
  onSaveView: (name: string) => void;
  hideSubtypeNotes: boolean;
  onHideSubtypeNotesChange: (hidden: boolean) => void;
  schemas: PropertySchemas;
  vaultLocation: string | null;
}

export function NoteList({
  notes,
  trashedImages,
  filterOptions,
  filter,
  listFilters,
  selectedNoteId,
  search,
  isRefreshing,
  onSearchChange,
  onListFiltersChange,
  visibleProperties,
  onVisiblePropertiesChange,
  onSelectNote,
  onOpenNoteInNewTab,
  onCreateNote,
  onCreateFile,
  onCreateLink,
  onOpenExternalNotes,
  viewConfig,
  savedViews,
  onViewModeChange,
  onApplySavedView,
  onSaveView,
  hideSubtypeNotes,
  onHideSubtypeNotesChange,
  schemas,
  vaultLocation,
}: NoteListProps) {
  const [trashTarget, setTrashTarget] = useState<Note | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<Note | null>(null);
  const [deleteImageTarget, setDeleteImageTarget] = useState<TrashedImage | null>(null);
  const [closeExternalTarget, setCloseExternalTarget] = useState<Note | null>(
    null,
  );
  const [visibleNoteCount, setVisibleNoteCount] = useState(INITIAL_NOTE_COUNT);
  const [addLinkOpen, setAddLinkOpen] = useState(false);
  const [bulkRequest, setBulkRequest] = useState<BulkMutationRequest | null>(null);
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
  const noteIds = useMemo(() => notes.map((note) => note.id), [notes]);
  const bulkSelection = useBulkSelection(
    noteIds,
    `${filterKey}:${listFilterKey}:${search}`,
  );
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
    <div
      className="flex h-full flex-col bg-zerus-surface"
      onKeyDown={bulkSelection.handleCollectionKeyDown}
    >
      <div
        className={cn(
          "flex items-center gap-2 border-b border-border/60 px-3 py-2.5",
          isRefreshing && "pointer-events-none opacity-70",
        )}
      >
        <span className="flex-1 truncate text-sm font-semibold">{heading}</span>
        {filter.kind === "type" && viewConfig && onViewModeChange && (
          <TypeViewSwitcher
            typeName={heading}
            config={viewConfig}
            savedViews={savedViews}
            hideSubtypeNotes={hideSubtypeNotes}
            onChange={onViewModeChange}
            onApplySavedView={onApplySavedView}
            onSaveView={onSaveView}
            onHideSubtypeNotesChange={onHideSubtypeNotesChange}
          />
        )}
        {!inTrash && notes.length > 0 && (
          <Button
            variant="ghost"
            size="sm"
            className={cn(
              "h-7 gap-1 px-2 text-xs",
              bulkSelection.selectMode && "border border-zerus-accent/60 bg-zerus-accent/20 text-zerus-accent ring-1 ring-inset ring-zerus-accent/25 hover:bg-zerus-accent/25 hover:text-zerus-accent",
            )}
            aria-pressed={bulkSelection.selectMode}
            onClick={() => bulkSelection.setSelectMode(!bulkSelection.selectMode)}
          >
            <CheckSquare size={14} /> Select
          </Button>
        )}
        {inTrash ? (
          notes.length + trashedImages.length > 0 && (
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
      {!inTrash && (bulkSelection.selectMode || bulkSelection.selectedIds.size > 0) && (
        <BulkActionsToolbar
          notes={notes}
          selectedIds={bulkSelection.selectedIds}
          schemas={schemas}
          vaultLocation={vaultLocation}
          onClear={bulkSelection.clearSelection}
          onSelectAll={bulkSelection.selectAll}
          onRemoveSelected={bulkSelection.removeSelected}
          externalRequest={bulkRequest}
          onExternalRequestHandled={() => setBulkRequest(null)}
        />
      )}
      <div
        className={cn(
          "grid grid-cols-1 gap-2 px-3 py-2",
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
          schemas={schemas}
          showTypes={filter.kind === "all"}
          showFileTypes={inFiles}
          showArchivedToggle={!inTrash && !inExternal}
          filters={listFilters}
          visibleProperties={visibleProperties}
          triggerClassName="w-full justify-between"
          onChange={onListFiltersChange}
          onVisiblePropertiesChange={onVisiblePropertiesChange}
        />
      </div>
      <div ref={scrollContainerRef} className="flex-1 overflow-y-auto">
        {notes.length === 0 && (!inTrash || trashedImages.length === 0) && (
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
        {inTrash && trashedImages.map((image) => (
          <ContextMenu key={image.id}>
            <ContextMenuTrigger asChild>
              <button
                type="button"
                onClick={() => void openImageInDefaultApp(image.trashPath)}
                className="block w-full border-b border-border/40 px-4 py-3 text-left transition-colors hover:bg-zerus-text/[0.03]"
              >
                <div className="flex items-center gap-1.5">
                  <ImageIcon size={13} className="shrink-0 text-zerus-accent" />
                  <span className="truncate text-sm font-medium">{image.name}</span>
                </div>
                <p className="mt-0.5 truncate text-xs text-muted-foreground">
                  Deleted image
                </p>
                <div className="mt-1.5 flex items-center gap-2">
                  <Badge variant="secondary" className="h-4 rounded px-1.5 text-[10px] font-normal">
                    IMAGE
                  </Badge>
                  <span className="text-[11px] text-muted-foreground">
                    {formatNoteDate(image.deletedAt)}
                  </span>
                </div>
              </button>
            </ContextMenuTrigger>
            <ContextMenuContent>
              <ContextMenuItem onClick={() => void restoreTrashedImage(image.id)}>
                <Undo2 size={14} className="mr-2" /> Restore
              </ContextMenuItem>
              <ContextMenuItem
                className="text-destructive"
                onClick={() => setDeleteImageTarget(image)}
              >
                <Trash2 size={14} className="mr-2" /> Delete forever
              </ContextMenuItem>
            </ContextMenuContent>
          </ContextMenu>
        ))}
        {visibleNotes.map((note) => {
          const noteName = noteListTitle(note);
          const external = isExternalNote(note);
          const archived = isArchived(note);
          const fileHub = getFileHubReference(note);
          const linkHub = getLinkHubReference(note);
          const snippet = inFiles && fileHub
            ? fileHub.name
            : inLinks && linkHub
              ? linkHub.url
              : noteSnippet(note);
          const type = typeKey(noteTypePath(note));
          const bulkTargetIds = bulkSelection.selectedIds.has(note.id)
            ? [...bulkSelection.selectedIds]
            : [note.id];
          return (
            <ContextMenu key={note.id}>
              <ContextMenuTrigger asChild disabled={isRefreshing}>
                <button
                  onClick={(event) => {
                    if (!inTrash && bulkSelection.handleModifiedClick(event, note.id)) return;
                    bulkSelection.clearSelection();
                    onSelectNote(note.id);
                  }}
                  onMouseDown={(event) =>
                    handleMiddleMouseDown(event, () =>
                      onOpenNoteInNewTab(note.id),
                    )
                  }
                  className={cn(
                    "block w-full border-b border-border/40 px-4 py-3 text-left transition-colors",
                    bulkSelection.selectedIds.has(note.id)
                      ? "bg-zerus-accent/15 ring-1 ring-inset ring-zerus-accent/35"
                      : note.id === selectedNoteId
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
                      {noteName}
                    </span>
                  </div>
                  {snippet && (
                    <p className="mt-0.5 truncate text-xs text-muted-foreground">
                      {snippet}
                    </p>
                  )}
                  <PropertyPills note={note} visibleProperties={visibleProperties} className="mt-1.5" />
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
                    {bulkSelection.selectedIds.size <= 1 && (
                      <ContextMenuItem onClick={() => void duplicateNote(note.id).then((copy) => {
                        if (copy) onSelectNote(copy.id);
                      })}>
                        <Copy size={14} className="mr-2" /> Duplicate note
                      </ContextMenuItem>
                    )}
                    {bulkSelection.selectedIds.size > 1 ? (
                      <>
                        <ContextMenuItem onClick={() => setBulkRequest({ id: Date.now(), noteIds: bulkTargetIds, mutation: { archived: true } })}>
                          <Archive size={14} className="mr-2" /> Archive {bulkTargetIds.length} notes
                        </ContextMenuItem>
                        <ContextMenuItem onClick={() => setBulkRequest({ id: Date.now(), noteIds: bulkTargetIds, mutation: { archived: false } })}>
                          <ArchiveRestore size={14} className="mr-2" /> Unarchive {bulkTargetIds.length} notes
                        </ContextMenuItem>
                        <ContextMenuItem onClick={() => setBulkRequest({ id: Date.now(), noteIds: bulkTargetIds, mutation: { pinned: true } })}>
                          <Pin size={14} className="mr-2" /> Pin {bulkTargetIds.length} notes
                        </ContextMenuItem>
                        <ContextMenuItem onClick={() => setBulkRequest({ id: Date.now(), noteIds: bulkTargetIds, mutation: { pinned: false } })}>
                          <Pin size={14} className="mr-2" /> Unpin {bulkTargetIds.length} notes
                        </ContextMenuItem>
                      </>
                    ) : (
                      <>
                        <ContextMenuItem onClick={() => setBulkRequest({ id: Date.now(), noteIds: bulkTargetIds, mutation: { archived: !archived } })}>
                          {archived ? <ArchiveRestore size={14} className="mr-2" /> : <Archive size={14} className="mr-2" />}
                          {archived ? "Unarchive" : "Archive"}
                        </ContextMenuItem>
                        <ContextMenuItem onClick={() => setBulkRequest({ id: Date.now(), noteIds: bulkTargetIds, mutation: { pinned: !note.pinned } })}>
                          <Pin size={14} className="mr-2" /> {note.pinned ? "Unpin" : "Pin"}
                        </ContextMenuItem>
                      </>
                    )}
                    <ContextMenuItem onClick={() => setBulkRequest({ id: Date.now(), noteIds: bulkTargetIds, openProperties: true })}>
                      <SlidersHorizontal size={14} className="mr-2" /> Edit properties…
                    </ContextMenuItem>
                    {bulkSelection.selectedIds.size <= 1 && (
                      <ContextMenuItem
                        className="text-destructive"
                        onClick={() => setTrashTarget(note)}
                      >
                        <Trash2 size={14} className="mr-2" /> Move to trash
                      </ContextMenuItem>
                    )}
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
        open={deleteImageTarget !== null}
        onOpenChange={(open) => !open && setDeleteImageTarget(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Delete “{deleteImageTarget?.name ?? "this image"}” forever?
            </AlertDialogTitle>
            <AlertDialogDescription>This cannot be undone.</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className={buttonVariants({ variant: "destructive" })}
              onClick={() => {
                if (deleteImageTarget) void deleteTrashedImageForever(deleteImageTarget.id);
              }}
            >
              Delete forever
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
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
            <AlertDialogTitle
              className="line-clamp-3"
              title={closeExternalTarget ? noteTitle(closeExternalTarget) : "this note"}
            >
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
