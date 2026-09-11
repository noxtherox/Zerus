import type { DriveVaultSelection } from "@/lib/google-drive";
import { GoogleDrivePicker } from "./GoogleDrivePicker";
import { DateFormatSetting } from "@/components/notes/DateFormatSetting";
import { parseNoteReference } from "@/lib/wikilinks";
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type PointerEvent as ReactPointerEvent, type ReactNode, type TouchEvent as ReactTouchEvent } from "react";
import {
  Archive,
  ArchiveRestore,
  ArrowLeft,
  ArrowDown,
  ArrowUp,
  Check,
  ChevronRight,
  Cloud,
  Copy,
  Download,
  ExternalLink,
  File,
  FilePlus2,
  FileText,
  Folder,
  FolderCog,
  FolderOpen,
  FolderSearch,
  History,
  ImagePlus,
  Loader2,
  Link2,
  Link2Off,
  MapPin,
  Menu,
  MoreHorizontal,
  Pencil,
  Pin,
  Plus,
  RefreshCw,
  Search,
  Settings,
  Smile,
  Sparkles,
  Smartphone,
  FolderPlus,
  Trash2,
  Undo2,
  X,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { buttonVariants } from "@/components/ui/button-variants";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
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
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogDescription,
  DialogTitle,
} from "@/components/ui/dialog";
import { MarkdownEditor } from "@/components/editor/MdxMarkdownEditor";
import {
  PropertiesSection,
  RelationsSection,
} from "@/components/notes/PropertiesSection";
import { IconPickerDialog } from "@/components/notes/IconPickerDialog";
import { NoteExportDialog } from "@/components/notes/NoteExportDialog";
import { TypeIcon } from "@/components/notes/TypeIcon";
import { TypeCreationDialog } from "@/components/notes/TypeCreationDialog";
import { VersionHistoryPanel } from "@/components/notes/VersionHistoryPanel";
import { PersistentAIChat } from "@/components/mobile/AIChat";
import { MobileThemeSettings } from "@/components/mobile/MobileThemeSettings";
import type { ChatScope } from "@/lib/mobile-chat-history";
import { cn } from "@/lib/utils";
import { noteBody } from "@/lib/frontmatter";
import {
  DEFAULT_TYPE,
  MAX_TYPE_DEPTH,
  buildTypeTree,
  buildTypeTreeFromCounts,
  findNoteByTitle,
  firstNoteImagePath,
  isArchived,
  isExternalNote,
  isTrashed,
  noteSnippet,
  noteTitle,
  noteTypePath,
  parseTypePath,
  reorderTypeTree,
  typeKey,
  type Note,
  type TypeNode,
} from "@/lib/note-utils";
import { noteCreationType } from "@/lib/note-creation";
import { getFileHubReference } from "@/lib/file-hubs";
import { filterNotes, type NoteFilter } from "@/lib/filters";
import {
  getBacklinksGroupedByType,
  getOutgoingRelationTitles,
} from "@/lib/links";
import type { PropertySchemas } from "@/lib/properties";
import {
  loadDefaultNoteType,
  loadNoteTypeOrder,
  saveDefaultNoteType,
  saveNoteTypeOrder,
} from "@/lib/note-preferences";
import {
  horizontalSwipeDirection,
  noteHeaderCollapseProgress,
  shouldDismissBottomSheet,
} from "@/lib/mobile-gestures";
import {
  readMobileNavigationEntry,
  withMobileNavigationEntry,
  type MobileNavigationEntry,
} from "@/lib/mobile-navigation";
import {
  createFileNote,
  clearVaultVersionHistory,
  createNote,
  createMobileVaultAtLocation,
  createMobileVaultOnDevice,
  initStore,
  loadAllNotes,
  loadMoreNotes,
  locateMobileVault,
  openGoogleDriveVault,
  prepareGoogleDriveConnection,
  reloadVault,
  resolveNoteConflict,
  openExternalNotes,
  openFileHub,
  createType,
  deleteType,
  detachFileHub,
  emptyTrash,
  deleteTrashedImageForever,
  getFileHubStatus,
  getNotes,
  attachFileToNote,
  chooseDocumentFile,
  locateFileHub,
  addFileLocation,
  fileLocationUsages,
  getFileLocationMappings,
  mapFileLocation,
  removeFileLocation,
  renameFileLocation,
  renameType,
  restoreNote,
  restoreTrashedImage,
  openImageInDefaultApp,
  savePastedImage,
  setNoteType,
  setTypeIcon,
  toggleNoteArchived,
  toggleNotePinned,
  trashNote,
  updateNoteBody,
  updateVersionHistorySettings,
  useVault,
  getImageUrl,
} from "@/store/notes-store";

interface MobileNote {
  id: string;
  title: string;
  preview: string;
  imagePath: string | null;
  body: string;
  type: string;
  kind: "note" | "external" | "file";
  icon: string | null;
  fileName?: string;
  updated: string;
  pinned?: boolean;
}

function editorBody(note: Note): string {
  const lines = noteBody(note.content).split("\n");
  const titleIndex = lines.findIndex((line) => line.trim().length > 0);
  if (titleIndex < 0) return "";
  return lines
    .slice(titleIndex + 1)
    .join("\n")
    .replace(/^\s*\n/, "");
}

function formatUpdated(updatedAt: string): string {
  const elapsed = Date.now() - new Date(updatedAt).getTime();
  if (!Number.isFinite(elapsed) || elapsed < 60_000) return "Now";
  if (elapsed < 60 * 60_000) return `${Math.floor(elapsed / 60_000)} min`;
  if (elapsed < 24 * 60 * 60_000) return `${Math.floor(elapsed / (60 * 60_000))} hr`;
  if (elapsed < 48 * 60 * 60_000) return "Yesterday";
  return new Intl.DateTimeFormat(undefined, { day: "numeric", month: "short" }).format(new Date(updatedAt));
}

function presentNote(note: Note, typeIcons: Record<string, string> = {}): MobileNote {
  const file = getFileHubReference(note);
  const typePath = noteTypePath(note);
  const typeKey = typePath.join("/");
  const configuredIcon = typeIcons[typeKey] ?? typeIcons[typePath[0] ?? ""];
  const type = isExternalNote(note)
    ? "External Note"
    : typePath.join(" / ") || "Inbox";
  return {
    id: note.id,
    title: noteTitle(note),
    preview: file?.name ?? (noteSnippet(note) || "Empty note"),
    imagePath: firstNoteImagePath(note),
    body: editorBody(note),
    type,
    kind: file ? "file" : isExternalNote(note) ? "external" : "note",
    icon: configuredIcon ?? null,
    fileName: file?.name,
    updated: formatUpdated(note.updatedAt),
    pinned: note.pinned,
  };
}

function StatusBar() {
  return (
    <div className="flex h-11 shrink-0 items-end justify-between px-6 pb-2 text-[12px] font-semibold text-[#20201e] dark:text-[#f5f3ef]">
      <span>9:41</span>
      <div className="flex items-center gap-1.5" aria-label="Phone status">
        <span className="flex items-end gap-[2px]" aria-hidden="true">
          <span className="h-1 w-[3px] rounded-full bg-current" />
          <span className="h-1.5 w-[3px] rounded-full bg-current" />
          <span className="h-2 w-[3px] rounded-full bg-current" />
          <span className="h-2.5 w-[3px] rounded-full bg-current" />
        </span>
        <span className="text-[10px]" aria-hidden="true">⌁</span>
        <span className="h-[10px] w-[19px] rounded-[3px] border border-current p-[1px]" aria-hidden="true">
          <span className="block h-full w-[12px] rounded-[1px] bg-current" />
        </span>
      </div>
    </div>
  );
}

interface NoteCardProps {
  note: MobileNote;
  onOpen: (note: MobileNote) => void;
}

function NoteCardImage({ path }: { path: string }) {
  const [url, setUrl] = useState<string | null | undefined>();

  useEffect(() => {
    let active = true;
    setUrl(undefined);
    void getImageUrl(path).then((resolved) => {
      if (active) setUrl(resolved);
    });
    return () => {
      active = false;
    };
  }, [path]);

  if (url === null) return null;
  return (
    <span className="h-[76px] w-[76px] shrink-0 overflow-hidden rounded-[12px] bg-white/[0.06]" aria-hidden="true">
      {url && (
        <img
          src={url}
          alt=""
          className="h-full w-full object-cover"
          onError={() => setUrl(null)}
        />
      )}
    </span>
  );
}

function NoteCard({ note, onOpen }: NoteCardProps) {
  const icon = note.icon ? (
    <TypeIcon icon={note.icon} size={18} />
  ) : note.kind === "external" ? (
    <ExternalLink className="h-[18px] w-[18px]" />
  ) : note.kind === "file" ? (
    <File className="h-[18px] w-[18px]" />
  ) : (
    <FileText className="h-[18px] w-[18px]" />
  );
  return (
    <button
      type="button"
      onClick={() => onOpen(note)}
      className="group w-full border-b border-zerus-text/[0.065] px-1 py-4 text-left transition last:border-b-0 active:bg-zerus-text/[0.035]"
    >
      <div className="flex items-start gap-3">
        <span className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-[11px] bg-zerus-text/[0.07] text-zerus-accent" aria-hidden="true">{icon}</span>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <h3 className="truncate text-[16px] font-semibold tracking-[-0.015em] text-[#f2efea]">{note.title}</h3>
            {note.pinned && <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-[#d84b40]" title="Pinned" />}
          </div>
          <p className="mt-1 line-clamp-2 text-[13px] leading-[1.4] text-[#9b9893]">{note.preview}</p>
          <div className="mt-2 flex items-center gap-2 text-[11px] font-medium text-[#74716d]">
            <span className="flex items-center gap-1 text-zerus-accent"><Folder className="h-3 w-3" />{note.type}</span><span>·</span><span>{note.updated}</span>
          </div>
        </div>
        {note.imagePath && <NoteCardImage path={note.imagePath} />}
      </div>
    </button>
  );
}

interface BottomSearchProps {
  query: string;
  onQueryChange: (query: string) => void;
  onCreate?: () => void;
  onChat: () => void;
  createLabel?: string;
}

function BottomSearch({ query, onQueryChange, onCreate, onChat, createLabel = "Create a new note" }: BottomSearchProps) {
  return (
    <div className="mobile-bottom-search pointer-events-none absolute inset-x-0 bottom-0 z-30 flex items-center gap-2.5 bg-gradient-to-t from-zerus-editor via-zerus-editor/95 to-transparent px-5 pb-7 pt-8">
      <label className="pointer-events-auto relative min-w-0 flex-1">
        <span className="sr-only">Search notes</span>
        <Search className="absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-[#f2f2f7]" strokeWidth={2.1} />
        <Input
          value={query}
          onChange={(event) => onQueryChange(event.target.value)}
          placeholder="Search"
          className="h-[52px] rounded-[26px] border border-zerus-text/[0.10] bg-zerus-surface/95 pl-12 pr-10 text-[17px] text-zerus-text shadow-[0_8px_28px_rgba(0,0,0,0.24)] backdrop-blur-xl placeholder:text-zerus-text/50 focus-visible:ring-1 focus-visible:ring-zerus-accent/70"
        />
        {query && (
          <button type="button" onClick={() => onQueryChange("")} className="absolute right-3.5 top-1/2 -translate-y-1/2 rounded-full bg-white/15 p-1 text-[#c8c8ce]" aria-label="Clear search">
            <X className="h-3 w-3" />
          </button>
        )}
      </label>
      <button type="button" onClick={onChat} className="pointer-events-auto flex h-[52px] w-[52px] shrink-0 items-center justify-center rounded-full bg-zerus-surface text-zerus-accent shadow-[0_8px_24px_rgba(0,0,0,0.22)] transition active:scale-95" aria-label="Open voice chat">
        <Sparkles className="h-6 w-6" />
      </button>
      {onCreate && <button type="button" onClick={onCreate} className="pointer-events-auto flex h-[52px] w-[52px] shrink-0 items-center justify-center rounded-full bg-zerus-accent text-white shadow-[0_8px_24px_rgba(0,0,0,0.22)] transition active:scale-95" aria-label={createLabel}>
        <Plus className="h-7 w-7" strokeWidth={2} />
      </button>}
    </div>
  );
}

interface LibraryDrawerProps {
  counts: { all: number; external: number; files: number; trash: number };
  typeTree: TypeNode[];
  typeIcons: Record<string, string>;
  onClose: () => void;
  onSelect: (scope: NoteFilter) => void;
  onCreateType: () => void;
  onOpenTypeActions: (target: TypeActionTarget) => void;
}

interface TypeActionTarget {
  node: TypeNode;
  canMoveUp: boolean;
  canMoveDown: boolean;
  previousKey: string | null;
  nextKey: string | null;
}

function flattenTypes(nodes: TypeNode[], depth = 0): Array<TypeActionTarget & { depth: number }> {
  return nodes.flatMap((node, index) => [
    {
      node,
      depth,
      canMoveUp: index > 0,
      canMoveDown: index < nodes.length - 1,
      previousKey: index > 0 ? typeKey(nodes[index - 1].path) : null,
      nextKey: index < nodes.length - 1 ? typeKey(nodes[index + 1].path) : null,
    },
    ...flattenTypes(node.children, depth + 1),
  ]);
}

function flattenTypeKeys(nodes: TypeNode[]): string[] {
  return nodes.flatMap((node) => [
    typeKey(node.path),
    ...flattenTypeKeys(node.children),
  ]);
}

function LibraryDrawer({ counts, typeTree, typeIcons, onClose, onSelect, onCreateType, onOpenTypeActions }: LibraryDrawerProps) {
  const [swipeOffset, setSwipeOffset] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [isClosing, setIsClosing] = useState(false);
  const touchStart = useRef<{ x: number; y: number; startedAt: number; axis: "horizontal" | "vertical" | null } | null>(null);
  const suppressClick = useRef(false);
  const drawerRef = useRef<HTMLDivElement | null>(null);
  const closeTimer = useRef<number | null>(null);
  const closeFrame = useRef<number | null>(null);

  const updateHeaderProgress = useCallback((scrollTop: number) => {
    drawerRef.current?.style.setProperty(
      "--mobile-library-header-progress",
      `${noteHeaderCollapseProgress(scrollTop, 56)}`,
    );
  }, []);

  useEffect(() => () => {
    if (closeTimer.current !== null) window.clearTimeout(closeTimer.current);
    if (closeFrame.current !== null) window.cancelAnimationFrame(closeFrame.current);
  }, []);

  const finishClose = () => {
    if (closeTimer.current !== null) {
      window.clearTimeout(closeTimer.current);
      closeTimer.current = null;
    }
    onClose();
  };

  const closeWithAnimation = () => {
    if (isClosing) return;
    touchStart.current = null;
    setIsDragging(false);
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      onClose();
      return;
    }
    setIsClosing(true);
    const drawerWidth = drawerRef.current?.getBoundingClientRect().width || window.innerWidth;
    // First remove the entrance animation while preserving the drawer's current
    // transform. Applying both changes in one render skips the transition in
    // some WebKit/Chromium configurations.
    closeFrame.current = window.requestAnimationFrame(() => {
      closeFrame.current = window.requestAnimationFrame(() => {
        closeFrame.current = null;
        setSwipeOffset(-drawerWidth);
        // transitionend keeps the drawer mounted through the last painted frame.
        // The timeout only covers transitions interrupted by the browser.
        closeTimer.current = window.setTimeout(finishClose, 420);
      });
    });
  };

  const handleTouchStart = (event: ReactTouchEvent<HTMLDivElement>) => {
    const touch = event.touches[0];
    if (!touch || isClosing) return;
    touchStart.current = { x: touch.clientX, y: touch.clientY, startedAt: performance.now(), axis: null };
    suppressClick.current = false;
  };

  const handleTouchMove = (event: ReactTouchEvent<HTMLDivElement>) => {
    const start = touchStart.current;
    const touch = event.touches[0];
    if (!start || !touch || isClosing) return;
    const deltaX = touch.clientX - start.x;
    const deltaY = touch.clientY - start.y;
    if (!start.axis && Math.max(Math.abs(deltaX), Math.abs(deltaY)) >= 8) {
      start.axis = Math.abs(deltaX) > Math.abs(deltaY) ? "horizontal" : "vertical";
      if (start.axis === "horizontal") setIsDragging(true);
    }
    if (start.axis !== "horizontal") return;
    event.preventDefault();
    const nextOffset = Math.min(0, deltaX);
    if (nextOffset < -8) suppressClick.current = true;
    setSwipeOffset(nextOffset);
  };

  const handleTouchEnd = (event: ReactTouchEvent<HTMLDivElement>, cancelled = false) => {
    const start = touchStart.current;
    const touch = event.changedTouches[0];
    touchStart.current = null;
    if (!start || !touch || start.axis !== "horizontal") return;
    const deltaX = touch.clientX - start.x;
    const velocity = deltaX / Math.max(performance.now() - start.startedAt, 1);
    const drawerWidth = drawerRef.current?.getBoundingClientRect().width || window.innerWidth;
    const closeDistance = Math.min(drawerWidth * 0.22, 96);
    if (!cancelled && (deltaX <= -closeDistance || (deltaX <= -24 && velocity <= -0.5))) {
      closeWithAnimation();
      return;
    }
    setIsDragging(false);
    setSwipeOffset(0);
  };

  const scopeRow = (
    label: string,
    count: number,
    icon: ReactNode,
    scope: NoteFilter,
    iconClass = "bg-zerus-accent",
  ) => (
    <button type="button" onClick={() => onSelect(scope)} className="flex min-h-[62px] w-full items-center gap-3 rounded-[13px] border-b border-zerus-sidebar-fg/[0.08] px-4 py-3 text-left last:border-b-0 active:bg-zerus-sidebar-fg/[0.05]">
      <span className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-[11px] text-white", iconClass)}>{icon}</span>
      <span className="flex-1 text-[16px] font-medium">{label}</span>
      <span className="text-sm text-zerus-sidebar-fg/55">{count}</span><ChevronRight className="h-4 w-4 text-zerus-sidebar-fg/35" />
    </button>
  );
  return (
    <div
      ref={drawerRef}
      className={cn("mobile-library-drawer absolute inset-0 z-40 flex min-h-0 flex-col bg-zerus-sidebar text-zerus-sidebar-fg shadow-[10px_0_28px_rgba(0,0,0,0.28)]", !isClosing && "mobile-library-enter", isDragging && "mobile-library-dragging")}
      role="dialog"
      aria-modal="true"
      aria-label="Zerus navigation"
      style={{
        "--mobile-library-header-progress": "0",
        transform: `translate3d(${swipeOffset}px, 0, 0)`,
      } as CSSProperties}
      onTouchStart={handleTouchStart}
      onTouchMove={handleTouchMove}
      onTouchEnd={(event) => handleTouchEnd(event)}
      onTouchCancel={(event) => handleTouchEnd(event, true)}
      onTransitionEnd={(event) => {
        if (isClosing && event.target === event.currentTarget && event.propertyName === "transform") finishClose();
      }}
      onClickCapture={(event) => {
        if (!suppressClick.current) return;
        suppressClick.current = false;
        event.preventDefault();
        event.stopPropagation();
      }}
    >
      <header className="mobile-library-header absolute inset-x-0 top-0 z-10 overflow-hidden border-b border-zerus-sidebar-fg/[0.06] bg-zerus-sidebar">
        <h2 className="mobile-library-title-expanded absolute bottom-4 left-5 text-[30px] font-bold tracking-[-0.04em]">Zerus</h2>
        <h2 aria-hidden="true" className="mobile-library-title-compact pointer-events-none absolute inset-x-16 bottom-0 top-[env(safe-area-inset-top)] flex items-center justify-center truncate text-[18px] font-semibold tracking-[-0.025em]">Zerus</h2>
        <Button variant="ghost" size="icon" onClick={closeWithAnimation} className="mobile-library-close absolute bottom-4 right-5 h-10 w-10 rounded-full bg-zerus-sidebar-fg/[0.08] text-zerus-sidebar-fg hover:bg-zerus-sidebar-fg/[0.12]" aria-label="Close Zerus navigation"><X className="h-5 w-5" /></Button>
      </header>
      <div onScroll={(event) => updateHeaderProgress(event.currentTarget.scrollTop)} className="mobile-library-scroll min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pb-[calc(env(safe-area-inset-bottom)+2rem)] touch-pan-y" style={{ WebkitOverflowScrolling: "touch", touchAction: "pan-y" }}>
        <div className="rounded-[18px] bg-zerus-surface p-1">
          {scopeRow("All Notes", counts.all, <FileText className="h-[18px] w-[18px]" />, { kind: "all" })}
          {scopeRow("External Notes", counts.external, <ExternalLink className="h-[18px] w-[18px]" />, { kind: "external" })}
          {scopeRow("Files", counts.files, <File className="h-[18px] w-[18px]" />, { kind: "files" })}
        </div>
        <div className="mb-2 mt-7 flex items-center justify-between px-1">
          <p className="text-[13px] font-semibold text-zerus-sidebar-fg/55">Types</p>
          <button type="button" onClick={onCreateType} className="flex h-8 w-8 items-center justify-center rounded-full bg-zerus-sidebar-fg/[0.07] text-zerus-sidebar-fg active:bg-zerus-sidebar-fg/[0.12]" aria-label="Add type"><Plus className="h-4 w-4" /></button>
        </div>
        {typeTree.length > 0 ? <div className="rounded-[18px] bg-zerus-surface p-1">
          {flattenTypes(typeTree).map((target) => (
            <div key={typeKey(target.node.path)} className="flex min-h-[62px] items-center border-b border-zerus-sidebar-fg/[0.08] last:border-b-0" style={{ paddingLeft: `${12 + target.depth * 18}px` }}>
              <button type="button" onClick={() => onSelect({ kind: "type", path: target.node.path })} className="flex min-w-0 flex-1 items-center gap-3 self-stretch rounded-[13px] text-left active:bg-zerus-sidebar-fg/[0.05]">
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[11px] bg-zerus-accent text-white"><TypeIcon icon={typeIcons[typeKey(target.node.path)]} size={20} /></span>
                <span className="min-w-0 flex-1 truncate text-[16px] font-medium">{target.node.name}</span>
              </button>
              <button type="button" onClick={() => onOpenTypeActions(target)} className="mr-1 flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-zerus-sidebar-fg/55 active:bg-zerus-sidebar-fg/[0.08]" aria-label={`Actions for ${target.node.name}`}><MoreHorizontal className="h-5 w-5" /></button>
            </div>
          ))}
        </div> : <p className="rounded-[14px] bg-zerus-surface px-4 py-4 text-sm text-zerus-sidebar-fg/55">No note types yet.</p>}
        <div className="mt-7 rounded-[18px] bg-zerus-surface p-1">
          {scopeRow("Recently Deleted", counts.trash, <Trash2 className="h-[18px] w-[18px]" />, { kind: "trash" }, "bg-zerus-sidebar-fg/35")}
        </div>
      </div>
    </div>
  );
}

interface TypeActionSheetProps {
  target: TypeActionTarget;
  onClose: () => void;
  onMoveUp: () => void;
  onMoveDown: () => void;
  onChangeIcon: () => void;
  onAddSubtype: () => void;
  onRename: () => void;
  onDelete: () => void;
}

function TypeActionSheet({ target, onClose, onMoveUp, onMoveDown, onChangeIcon, onAddSubtype, onRename, onDelete }: TypeActionSheetProps) {
  const action = (
    label: string,
    icon: ReactNode,
    run: () => void,
    disabled = false,
    destructive = false,
  ) => (
    <button type="button" disabled={disabled} onClick={() => { onClose(); run(); }} className={cn("flex min-h-[54px] w-full items-center gap-3 border-b border-white/[0.08] px-4 text-left text-[16px] last:border-b-0 active:bg-white/[0.05] disabled:opacity-35", destructive && "text-[#ff6961]")}>
      <span className="flex h-8 w-8 items-center justify-center">{icon}</span><span>{label}</span>
    </button>
  );
  return (
    <div className="absolute inset-0 z-[70] flex items-end bg-black/55" role="dialog" aria-modal="true" aria-label={`Actions for ${target.node.name}`} onClick={onClose}>
      <section className="w-full rounded-t-[26px] bg-[#242426] px-4 pb-[calc(env(safe-area-inset-bottom)+1rem)] pt-3 shadow-2xl" onClick={(event) => event.stopPropagation()}>
        <div className="mx-auto h-1 w-10 rounded-full bg-white/20" />
        <h3 className="px-2 pb-3 pt-4 text-center text-[15px] font-semibold text-[#a6a6ab]">{target.node.name}</h3>
        <div className="overflow-hidden rounded-[16px] bg-[#2c2c2e]">
          {action("Move up", <ArrowUp className="h-5 w-5" />, onMoveUp, !target.canMoveUp)}
          {action("Move down", <ArrowDown className="h-5 w-5" />, onMoveDown, !target.canMoveDown)}
          {action("Change icon", <Smile className="h-5 w-5" />, onChangeIcon)}
          {action("Add subtype", <FolderPlus className="h-5 w-5" />, onAddSubtype, target.node.path.length >= MAX_TYPE_DEPTH)}
          {action("Rename type", <Pencil className="h-5 w-5" />, onRename)}
          {action("Delete type", <Trash2 className="h-5 w-5" />, onDelete, false, true)}
        </div>
        <button type="button" onClick={onClose} className="mt-3 h-[52px] w-full rounded-[16px] bg-[#2c2c2e] text-[16px] font-semibold active:bg-[#363638]">Cancel</button>
      </section>
    </div>
  );
}

interface NoteActionSheetProps {
  note: Note;
  fileExists: boolean | null;
  onClose: () => void;
  onShowProperties: () => void;
  onOpenFile: () => void;
  onRefreshFile: () => void;
  onCopyFileIntoVault: () => void;
  onLocateFile: () => void;
  onReplaceFile: () => void;
  onDetachFile: () => void;
  onMoveToTrash: () => void;
  onFind: () => void;
  onInsertImage: () => void;
  onMoveType: () => void;
  onChat: () => void;
  onShowHistory: () => void;
  onExport: () => void;
}

function NoteActionSheet({ note, fileExists, onClose, onShowProperties, onOpenFile, onRefreshFile, onCopyFileIntoVault, onLocateFile, onReplaceFile, onDetachFile, onMoveToTrash, onFind, onInsertImage, onMoveType, onChat, onShowHistory, onExport }: NoteActionSheetProps) {
  const archived = isArchived(note);
  const trashed = isTrashed(note);
  const external = isExternalNote(note);
  const file = getFileHubReference(note);
  const sheetRef = useRef<HTMLElement | null>(null);
  const dragStart = useRef<{ pointerId: number; y: number; startedAt: number } | null>(null);
  const closeTimer = useRef<number | null>(null);
  const [dragOffset, setDragOffset] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [isClosing, setIsClosing] = useState(false);

  useEffect(() => () => {
    if (closeTimer.current !== null) window.clearTimeout(closeTimer.current);
  }, []);

  const finishClose = () => {
    if (closeTimer.current !== null) {
      window.clearTimeout(closeTimer.current);
      closeTimer.current = null;
    }
    onClose();
  };

  const dismissWithDrag = () => {
    setIsDragging(false);
    setIsClosing(true);
    setDragOffset(sheetRef.current?.clientHeight ?? window.innerHeight);
    closeTimer.current = window.setTimeout(finishClose, 320);
  };

  const handleDragStart = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (!event.isPrimary || isClosing) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    dragStart.current = { pointerId: event.pointerId, y: event.clientY, startedAt: performance.now() };
    setIsDragging(true);
  };

  const handleDragMove = (event: ReactPointerEvent<HTMLDivElement>) => {
    const start = dragStart.current;
    if (!start || start.pointerId !== event.pointerId) return;
    setDragOffset(Math.max(0, event.clientY - start.y));
  };

  const handleDragEnd = (event: ReactPointerEvent<HTMLDivElement>) => {
    const start = dragStart.current;
    if (!start || start.pointerId !== event.pointerId) return;
    const distance = Math.max(0, event.clientY - start.y);
    const duration = performance.now() - start.startedAt;
    const sheetHeight = sheetRef.current?.clientHeight ?? window.innerHeight;
    dragStart.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
    if (shouldDismissBottomSheet(distance, duration, sheetHeight)) {
      dismissWithDrag();
      return;
    }
    setIsDragging(false);
    setDragOffset(0);
  };

  const handleDragCancel = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (dragStart.current?.pointerId !== event.pointerId) return;
    dragStart.current = null;
    setIsDragging(false);
    setDragOffset(0);
  };
  const action = (
    label: string,
    icon: ReactNode,
    run: () => void,
    destructive = false,
    disabled = false,
  ) => (
    <button
      type="button"
      disabled={disabled}
      onClick={() => { onClose(); run(); }}
      className={cn(
        "flex min-h-[56px] w-full items-center gap-3 border-b border-white/[0.08] px-4 text-left text-[16px] last:border-b-0 active:bg-white/[0.05]",
        destructive && "text-[#ff6961]",
        disabled && "opacity-40",
      )}
    >
      <span className="flex h-8 w-8 items-center justify-center">{icon}</span>
      <span>{label}</span>
    </button>
  );

  return (
    <div
      className="absolute inset-0 z-[70] flex items-end bg-black/55"
      role="dialog"
      aria-modal="true"
      aria-label="Note actions"
      onClick={onClose}
      onTouchStart={(event) => event.stopPropagation()}
      onTouchMove={(event) => event.stopPropagation()}
      onTouchEnd={(event) => event.stopPropagation()}
    >
      <section
        ref={sheetRef}
        className="max-h-full min-h-0 w-full touch-pan-y overflow-y-auto overscroll-contain rounded-t-[26px] bg-[#242426] px-4 pb-[calc(env(safe-area-inset-bottom)+1rem)] pt-3 shadow-2xl [-webkit-overflow-scrolling:touch]"
        style={{
          transform: `translate3d(0, ${dragOffset}px, 0)`,
          transition: isDragging ? "none" : "transform 280ms cubic-bezier(0.32, 0.72, 0, 1)",
        }}
        onClick={(event) => event.stopPropagation()}
        onTransitionEnd={(event) => {
          if (isClosing && event.target === event.currentTarget && event.propertyName === "transform") finishClose();
        }}
      >
        <div
          className="touch-none select-none pb-3"
          data-note-actions-drag-handle
          onPointerDown={handleDragStart}
          onPointerMove={handleDragMove}
          onPointerUp={handleDragEnd}
          onPointerCancel={handleDragCancel}
        >
          <div className="mx-auto h-1 w-10 rounded-full bg-white/20" />
          <h3 className="truncate px-2 pt-4 text-center text-[15px] font-semibold text-[#a6a6ab]">{noteTitle(note)}</h3>
        </div>
        <div className="overflow-hidden rounded-[16px] bg-[#2c2c2e]">
          {action("Properties", <Link2 className="h-5 w-5" />, onShowProperties)}
          {action("Chat about this note", <Sparkles className="h-5 w-5" />, onChat)}
          {action("Find in note", <Search className="h-5 w-5" />, onFind)}
          {!external && action("Version history", <History className="h-5 w-5" />, onShowHistory)}
          {!trashed && action("Export", <Download className="h-5 w-5" />, onExport)}
          {!external && !trashed && action("Insert image", <ImagePlus className="h-5 w-5" />, onInsertImage)}
          {!external && !trashed && action("Move to folder", <FolderCog className="h-5 w-5" />, onMoveType)}
          {!file && !external && !trashed && action("Attach file to note", <FilePlus2 className="h-5 w-5" />, onReplaceFile)}
        </div>
        {file && !trashed && (
          <>
            <p className="px-2 pb-2 pt-4 text-[12px] font-semibold uppercase tracking-[0.08em] text-[#7f7f85]">File actions</p>
            <div className="overflow-hidden rounded-[16px] bg-[#2c2c2e]">
              {action(`Preview ${file.name}`, <ExternalLink className="h-5 w-5" />, onOpenFile)}
              {action("Refresh file access", <RefreshCw className="h-5 w-5" />, onRefreshFile)}
              {fileExists === false && action("Locate file", <MapPin className="h-5 w-5" />, onLocateFile)}
              {!file.managed && file.kind !== "vault" && fileExists === true
                && action("Copy into Vault", <Copy className="h-5 w-5" />, onCopyFileIntoVault)}
              {action("Replace linked file", <RefreshCw className="h-5 w-5" />, onReplaceFile)}
              {action("Detach file from note", <Link2Off className="h-5 w-5" />, onDetachFile, true)}
            </div>
          </>
        )}
        {!external && (
          <div className="mt-3 overflow-hidden rounded-[16px] bg-[#2c2c2e]">
            {!trashed && action(archived ? "Unarchive" : "Archive", archived ? <ArchiveRestore className="h-5 w-5" /> : <Archive className="h-5 w-5" />, () => toggleNoteArchived(note.id))}
            {!trashed && action(note.pinned ? "Unpin" : "Pin", <Pin className={cn("h-5 w-5", note.pinned && "fill-current")} />, () => toggleNotePinned(note.id))}
            {trashed
              ? action("Restore", <Undo2 className="h-5 w-5" />, () => { void restoreNote(note.id); })
              : action("Move to trash", <Trash2 className="h-5 w-5" />, onMoveToTrash, true)}
          </div>
        )}
        <button type="button" onClick={onClose} className="mt-3 h-[52px] w-full rounded-[16px] bg-[#2c2c2e] text-[16px] font-semibold active:bg-[#363638]">Cancel</button>
      </section>
    </div>
  );
}

interface NoteViewProps {
  note: Note;
  allNotes: Note[];
  schemas: PropertySchemas;
  typeTree: TypeNode[];
  onBack: () => void;
  onBodyChange: (body: string) => void;
  onRename: (title: string, body: string) => void;
  onOpenNote: (id: string) => void;
  onOpenFile: (id: string, mode?: "preview" | "refresh") => void;
  onChat: (scope: ChatScope) => void;
}

function NoteView({
  note,
  allNotes,
  schemas,
  typeTree,
  onBack,
  onBodyChange,
  onRename,
  onOpenNote,
  onOpenFile,
  onChat,
}: NoteViewProps) {
  const presentedNote = presentNote(note);
  const archived = isArchived(note);
  const trashed = isTrashed(note);
  const file = getFileHubReference(note);
  const hasFile = file !== null;
  const [draft, setDraft] = useState(presentedNote.body);
  const [titleDraft, setTitleDraft] = useState(presentedNote.title);
  const [editingTitle, setEditingTitle] = useState(false);
  const [titleRegionHeight, setTitleRegionHeight] = useState(0);
  const [propertiesOpen, setPropertiesOpen] = useState(false);
  const [actionsOpen, setActionsOpen] = useState(false);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [exportOpen, setExportOpen] = useState(false);
  const [trashConfirmOpen, setTrashConfirmOpen] = useState(false);
  const [detachConfirmOpen, setDetachConfirmOpen] = useState(false);
  const [pendingAttachPath, setPendingAttachPath] = useState<string | null>(null);
  useEffect(() => {
    setDraft(presentedNote.body);
    setTitleDraft(presentedNote.title);
  }, [presentedNote.body, presentedNote.title]);
  const [moveTypeOpen, setMoveTypeOpen] = useState(false);
  const [findRequest, setFindRequest] = useState(0);
  const [insertTextRequest, setInsertTextRequest] = useState<{ id: number; text: string } | null>(null);
  const [fileExists, setFileExists] = useState<boolean | null>(null);
  const [dragX, setDragX] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [isSettling, setIsSettling] = useState(false);
  const touchStart = useRef<{ x: number; y: number; axis: "horizontal" | "vertical" | null } | null>(null);
  const settleTimer = useRef<number | null>(null);
  const pendingSettle = useRef<(() => void) | null>(null);
  const notePageRef = useRef<HTMLDivElement | null>(null);
  const titleRegionRef = useRef<HTMLDivElement | null>(null);
  const imageInputRef = useRef<HTMLInputElement | null>(null);

  const commitTitle = () => {
    const next = titleDraft.replace(/[\r\n]+/g, " ").trim();
    setEditingTitle(false);
    if (!next) {
      setTitleDraft(presentedNote.title);
      return;
    }
    if (next !== presentedNote.title) onRename(next, draft);
  };

  const insertImage = async (file?: File) => {
    if (!file || !file.type.startsWith("image/")) return;
    const path = await savePastedImage(new Uint8Array(await file.arrayBuffer()), file.type);
    if (!path) return;
    const markdown = `![${file.name.replace(/\.[^.]+$/, "") || "image"}](${path})`;
    setInsertTextRequest({ id: Date.now(), text: markdown });
  };

  useEffect(() => () => {
    if (settleTimer.current !== null) window.clearTimeout(settleTimer.current);
    pendingSettle.current = null;
  }, []);

  useLayoutEffect(() => {
    const region = titleRegionRef.current;
    if (!region) return;
    const measure = () => setTitleRegionHeight(region.scrollHeight);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(region);
    return () => observer.disconnect();
  }, [editingTitle, note.id, presentedNote.title]);

  const updateHeaderProgress = useCallback((scrollTop: number) => {
    const page = notePageRef.current;
    if (!page) return;
    const offset = Math.max(0, scrollTop);
    const progress = noteHeaderCollapseProgress(offset);
    const expandedOpacity = Math.max(0, 1 - progress * 1.6);
    const compactOpacity = Math.max(0, (progress - 0.2) / 0.8);

    // These values deliberately follow the scroll event directly. Interpolating
    // toward them makes the title lag behind the user's finger on iOS.
    const titleHeight = titleRegionRef.current?.offsetHeight ?? 0;
    page.style.setProperty("--mobile-note-title-offset", `${Math.min(offset, titleHeight)}px`);
    page.style.setProperty("--mobile-note-expanded-opacity", `${expandedOpacity}`);
    page.style.setProperty("--mobile-note-expanded-y", `${-6 * progress}px`);
    page.style.setProperty("--mobile-note-compact-opacity", `${compactOpacity}`);
    page.style.setProperty("--mobile-note-compact-y", `${(1 - compactOpacity) * 6}px`);
    page.style.setProperty("--mobile-note-header-bg-opacity", `${compactOpacity * 0.9}`);
    page.style.setProperty("--mobile-note-header-border-opacity", `${compactOpacity * 0.07}`);
    page.style.setProperty("--mobile-note-button-bg-opacity", `${(1 - progress) * 0.08}`);
  }, []);

  useEffect(() => {
    updateHeaderProgress(0);
  }, [note.id, updateHeaderProgress]);

  useEffect(() => {
    let cancelled = false;
    if (!hasFile) {
      setFileExists(null);
      return;
    }
    void getFileHubStatus(note.id).then((status) => {
      if (!cancelled) setFileExists(status?.exists ?? false);
    });
    return () => { cancelled = true; };
  }, [hasFile, note.id]);

  const replaceLinkedFile = async () => {
    const path = await chooseDocumentFile();
    if (!path) return;
    const result = await attachFileToNote(note.id, path, "auto");
    if (result.status === "duplicate") {
      onOpenNote(result.noteId);
    } else if (result.status === "needs-choice") {
      setPendingAttachPath(result.path);
    } else if (result.status === "attached") {
      setFileExists(true);
    }
  };

  const copyFileIntoVault = async () => {
    const status = await getFileHubStatus(note.id);
    const path = status?.resolved.absolutePath;
    if (!path || !status.exists) return;
    const result = await attachFileToNote(note.id, path, "copy");
    if (result.status === "attached") setFileExists(true);
  };

  const finishSettle = () => {
    const complete = pendingSettle.current;
    if (!complete) return;
    pendingSettle.current = null;
    if (settleTimer.current !== null) {
      window.clearTimeout(settleTimer.current);
      settleTimer.current = null;
    }
    setIsSettling(false);
    setDragX(0);
    complete();
  };

  const pageWidth = () => notePageRef.current?.getBoundingClientRect().width || window.innerWidth;

  const settle = (target: number, complete: () => void) => {
    setIsDragging(false);
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setDragX(0);
      complete();
      return;
    }
    pendingSettle.current = complete;
    setIsSettling(true);
    setDragX(target);
    // transitionend is authoritative. This is only a safety net for interrupted
    // browser transitions (for example when the tab is backgrounded mid-swipe).
    settleTimer.current = window.setTimeout(() => {
      finishSettle();
    }, 420);
  };

  const handleTouchStart = (event: ReactTouchEvent<HTMLDivElement>) => {
    if (isSettling) return;
    if (
      event.target instanceof Element &&
      event.target.closest(
        "input, textarea, select, button, [contenteditable]",
      )
    ) {
      touchStart.current = null;
      return;
    }
    const touch = event.touches[0];
    if (!touch) return;
    touchStart.current = { x: touch.clientX, y: touch.clientY, axis: null };
  };

  const handleTouchMove = (event: ReactTouchEvent<HTMLDivElement>) => {
    const start = touchStart.current;
    const touch = event.touches[0];
    if (!start || !touch) return;
    const deltaX = touch.clientX - start.x;
    const deltaY = touch.clientY - start.y;
    if (!start.axis && Math.max(Math.abs(deltaX), Math.abs(deltaY)) >= 8) {
      start.axis = Math.abs(deltaX) > Math.abs(deltaY) ? "horizontal" : "vertical";
      if (start.axis === "horizontal") setIsDragging(true);
    }
    if (start.axis !== "horizontal") return;
    event.preventDefault();
    setDragX(propertiesOpen && deltaX < 0 ? deltaX * 0.12 : deltaX);
  };

  const handleTouchEnd = (event: ReactTouchEvent<HTMLDivElement>) => {
    const start = touchStart.current;
    const touch = event.changedTouches[0];
    touchStart.current = null;
    if (!start || !touch || start.axis !== "horizontal") {
      setIsDragging(false);
      setDragX(0);
      return;
    }
    const direction = horizontalSwipeDirection(start, { x: touch.clientX, y: touch.clientY });
    if (direction === "right" && propertiesOpen) {
      settle(pageWidth(), () => setPropertiesOpen(false));
    } else if (direction === "right") {
      settle(pageWidth(), onBack);
    } else if (direction === "left" && !propertiesOpen) {
      setPropertiesOpen(true);
      setIsDragging(false);
      setIsSettling(true);
      requestAnimationFrame(() => {
        setDragX(0);
        settleTimer.current = window.setTimeout(() => setIsSettling(false), 340);
      });
    } else {
      setIsDragging(false);
      setDragX(0);
    }
  };

  const propertiesVisible = propertiesOpen || (isDragging && dragX < 0);
  const transition = isDragging ? "none" : "transform 340ms cubic-bezier(0.32, 0.72, 0, 1)";
  const [showArchivedBacklinks, setShowArchivedBacklinks] = useState(false);
  const backlinkGroups = useMemo(
    () => getBacklinksGroupedByType(note, allNotes, schemas, showArchivedBacklinks),
    [allNotes, note, schemas, showArchivedBacklinks],
  );
  const backlinkTotal = [...backlinkGroups.values()].reduce((total, group) => total + group.length, 0);
  const relationTotal = getOutgoingRelationTitles(
    note.content,
    noteTypePath(note),
    schemas,
  ).length;
  const linkableNotes = () => getNotes().filter(
    (candidate) =>
      !isExternalNote(candidate) &&
      !isTrashed(candidate) &&
      candidate.id !== note.id,
  );
  const followNoteLink = async (title: string) => {
    await loadAllNotes();
    const existing = findNoteByTitle(title, getNotes());
    if (existing) {
      onOpenNote(existing.id);
      return;
    }
    const reference = parseNoteReference(title);
    if (reference.id !== null) return;
    const created = await createNote(noteTypePath(note), `# ${reference.target}\n\n`);
    if (created) onOpenNote(created.id);
  };

  return (
    <div
      ref={notePageRef}
      className="mobile-note-page-enter relative flex min-h-0 flex-1 flex-col overflow-hidden"
      style={{
        "--mobile-note-title-height": `${titleRegionHeight}px`,
        "--mobile-note-title-offset": "0px",
        "--mobile-note-expanded-opacity": "1",
        "--mobile-note-expanded-y": "0px",
        "--mobile-note-compact-opacity": "0",
        "--mobile-note-compact-y": "6px",
        "--mobile-note-header-bg-opacity": "0",
        "--mobile-note-header-border-opacity": "0",
        "--mobile-note-button-bg-opacity": "0.08",
      } as CSSProperties}
      onTouchStart={handleTouchStart}
      onTouchMove={handleTouchMove}
      onTouchEnd={handleTouchEnd}
      onTouchCancel={() => { touchStart.current = null; setIsDragging(false); setDragX(0); }}
    >
      <div
        className="relative z-10 flex min-h-0 flex-1 flex-col bg-[#1c1d1e] shadow-[-10px_0_28px_rgba(0,0,0,0.28)]"
        style={{ transform: `translate3d(${propertiesOpen ? 0 : Math.max(0, dragX)}px, 0, 0)`, transition }}
        onTransitionEnd={(event) => {
          if (event.target === event.currentTarget && event.propertyName === "transform") finishSettle();
        }}
      >
      <header
        className="relative z-20 grid h-[60px] shrink-0 grid-cols-[44px_1fr_44px] items-center border-b px-4 pb-3 pt-1 backdrop-blur-xl"
        style={{
          backgroundColor: "rgb(28 29 30 / var(--mobile-note-header-bg-opacity))",
          borderBottomColor: "rgb(255 255 255 / var(--mobile-note-header-border-opacity))",
        }}
      >
        <Button
          variant="ghost"
          size="icon"
          className="h-11 w-11 touch-manipulation rounded-full text-[#f5f3ef] hover:bg-white/[0.12]"
          style={{ backgroundColor: "rgb(255 255 255 / var(--mobile-note-button-bg-opacity))" }}
          onClick={() => settle(pageWidth(), onBack)}
          aria-label="Back to notes"
        >
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div className="relative flex h-11 min-w-0 items-center justify-center justify-self-stretch">
          <span
            className="absolute inset-0 flex min-w-0 items-center justify-center gap-1.5 overflow-hidden text-[14px] font-medium leading-none text-zerus-accent"
            style={{
              opacity: "var(--mobile-note-expanded-opacity)",
              transform: "translate3d(0, var(--mobile-note-expanded-y), 0)",
            }}
          >
            <TypeIcon icon={presentedNote.icon ?? undefined} size={16} className="shrink-0" />
            <span className="truncate">{presentedNote.type}</span>
          </span>
          <span
            className="absolute inset-0 flex min-w-0 flex-col items-center justify-center gap-0.5 overflow-hidden px-2 text-center"
            style={{
              opacity: "var(--mobile-note-compact-opacity)",
              transform: "translate3d(0, var(--mobile-note-compact-y), 0)",
            }}
          >
            <span className="order-1 max-w-full truncate text-[10px] font-medium leading-none text-zerus-accent">
              {presentedNote.type}
            </span>
            <span className="order-2 max-w-full truncate text-[14px] font-medium leading-tight tracking-[-0.015em] text-[#f5f3ef]">
              {presentedNote.title}
            </span>
          </span>
        </div>
        <Button
          variant="ghost"
          size="icon"
          className="h-11 w-11 touch-manipulation rounded-full text-[#f5f3ef] hover:bg-white/[0.12]"
          style={{ backgroundColor: "rgb(255 255 255 / var(--mobile-note-button-bg-opacity))" }}
          onClick={() => setActionsOpen(true)}
          aria-label="Note actions"
        >
          <MoreHorizontal className="h-[20px] w-[20px]" />
        </Button>
      </header>
      {trashed && (
        <div
          className="mx-4 flex shrink-0 items-center gap-3 rounded-[14px] border border-[#df5149]/25 bg-[#df5149]/10 px-3 py-2.5"
          role="status"
        >
          <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#df5149]/15 text-[#ef6b62]">
            <Trash2 className="h-4 w-4" />
          </span>
          <span className="min-w-0 flex-1 text-sm font-medium text-[#c9c5bf]">
            This note is in Recently Deleted.
          </span>
          <Button
            type="button"
            size="sm"
            onClick={() => void restoreNote(note.id)}
            className="h-8 shrink-0 rounded-full bg-[#df5149] px-3 text-xs font-semibold text-white hover:bg-[#c94740]"
          >
            Restore
          </Button>
        </div>
      )}
      {archived && !trashed && (
        <div
          className="mx-4 flex shrink-0 items-center gap-3 rounded-[14px] border border-[#df5149]/25 bg-[#df5149]/10 px-3 py-2.5"
          role="status"
        >
          <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[#df5149]/15 text-[#ef6b62]">
            <Archive className="h-4 w-4" />
          </span>
          <span className="min-w-0 flex-1 text-sm font-medium text-[#c9c5bf]">
            This note is archived.
          </span>
          <Button
            type="button"
            size="sm"
            onClick={() => toggleNoteArchived(note.id)}
            className="h-8 shrink-0 rounded-full bg-[#df5149] px-3 text-xs font-semibold text-white hover:bg-[#c94740]"
          >
            Unarchive
          </Button>
        </div>
      )}
      <main
        className="mobile-note-body flex min-h-0 flex-1 flex-col overflow-hidden px-6 pt-2"
      >
        <div
          data-mobile-note-title-region
          className="shrink-0 overflow-hidden"
          style={{
            height: "max(0px, calc(var(--mobile-note-title-height) - var(--mobile-note-title-offset)))",
            willChange: "height",
          }}
        >
          <div
            ref={titleRegionRef}
            className="pb-2 pt-3"
            style={{
              transform: "translate3d(0, calc(-1 * var(--mobile-note-title-offset)), 0)",
              willChange: "transform",
            }}
          >
            {editingTitle ? (
              <Input
                autoFocus
                value={titleDraft}
                onChange={(event) => setTitleDraft(event.target.value)}
                onBlur={commitTitle}
                onKeyDown={(event) => {
                  if (event.key === "Enter") event.currentTarget.blur();
                  if (event.key === "Escape") {
                    setTitleDraft(presentedNote.title);
                    setEditingTitle(false);
                  }
                }}
                className="h-auto border-0 bg-transparent px-0 text-[27px] font-bold leading-[1.06] tracking-[-0.045em] text-[#f5f3ef] shadow-none focus-visible:ring-0"
                aria-label="Note title"
              />
            ) : (
              <button type="button" onClick={() => setEditingTitle(true)} className="text-left">
                <h1 className="text-[27px] font-bold leading-[1.06] tracking-[-0.045em] text-[#24221f] dark:text-[#f5f3ef]">{presentedNote.title}</h1>
              </button>
            )}
          {file && <button type="button" onClick={() => onOpenFile(note.id, "preview")} className="mt-5 flex w-full min-w-0 select-none items-center gap-3 rounded-[14px] bg-[#292a2b] px-4 py-3.5 text-left active:bg-[#333436]">
            <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[11px] bg-[#df5149] text-white"><File className="h-5 w-5" /></span>
            <span className="min-w-0 flex-1"><span className="block truncate text-sm font-semibold">{file.name}</span><span className="mt-0.5 block text-xs text-[#8e8e93]">Preview file</span></span>
            <ExternalLink className="h-4 w-4 shrink-0 text-[#77777d]" />
          </button>}
          </div>
        </div>
        <div className="mobile-note-editor -mx-6 min-h-0 flex-1 overflow-hidden">
          <MarkdownEditor
            noteId={note.id}
            initialContent={draft}
            getLinkableTitles={() => linkableNotes().map((candidate) => noteTitle(candidate))}
            isTitleResolved={(title) => !!findNoteByTitle(title, getNotes())}
            onChange={(body) => {
              setDraft(body);
              onBodyChange(body);
            }}
            onFollowLink={(title) => void followNoteLink(title)}
            autoFocus={false}
            placeholderText="Start writing…"
            firstLineIsTitle={false}
            followLinksOnClick
            findRequest={findRequest}
            insertTextRequest={insertTextRequest}
            onScrollTopChange={updateHeaderProgress}
          />
        </div>
      </main>
      </div>
      {propertiesVisible && (
        <div
          className="mobile-properties-panel absolute inset-0 z-40 flex flex-col bg-[#1c1d1e]"
          role="dialog"
          aria-modal="true"
          aria-label="Note properties"
          inert={!propertiesOpen && !isDragging}
          style={{
            transform: propertiesOpen
              ? `translate3d(${Math.max(0, dragX)}px, 0, 0)`
              : `translate3d(calc(100% + ${dragX}px), 0, 0)`,
            transition,
            touchAction: "pan-y",
          }}
          onTransitionEnd={(event) => {
            if (event.target === event.currentTarget && event.propertyName === "transform") finishSettle();
          }}
        >
          <header className="flex h-12 shrink-0 items-center justify-end border-b border-white/[0.07] px-3">
            <Button variant="ghost" size="icon" className="h-9 w-9 rounded-full bg-white/[0.08] text-[#f5f3ef] hover:bg-white/[0.12]" onClick={() => settle(pageWidth(), () => setPropertiesOpen(false))} aria-label="Close properties"><X className="h-5 w-5" /></Button>
          </header>
          <div className="min-h-0 flex-1 overflow-y-auto">
            <PropertiesSection
              note={note}
              allNotes={allNotes}
              onOpenNote={(id) => {
                setPropertiesOpen(false);
                onOpenNote(id);
              }}
              expanded
            />
            <section className="border-t border-white/[0.07] px-4 py-4">
              <div className="mb-3 flex items-center gap-2">
                <h2 className="min-w-0 flex-1 text-xs font-semibold uppercase tracking-[0.08em] text-[#9b9893]">
                  Relations & backlinks
                  {backlinkTotal + relationTotal
                    ? ` · ${backlinkTotal + relationTotal}`
                    : ""}
                </h2>
                <label className="flex items-center gap-2 text-xs text-[#9b9893]">
                  <input
                    type="checkbox"
                    checked={showArchivedBacklinks}
                    onChange={(event) => setShowArchivedBacklinks(event.target.checked)}
                    className="accent-[#df5149]"
                  />
                  Archived
                </label>
              </div>
              <RelationsSection
                note={note}
                allNotes={allNotes}
                onOpenNote={(id) => {
                  setPropertiesOpen(false);
                  onOpenNote(id);
                }}
                expanded
                showArchived={showArchivedBacklinks}
              />
              {backlinkTotal === 0 && relationTotal === 0 ? (
                <p className="text-sm text-[#77777d]">No notes link here yet.</p>
              ) : backlinkTotal > 0 ? (
                <div className={cn("space-y-4", relationTotal > 0 && "mt-4")}>
                  {[...backlinkGroups.entries()].map(([type, notes]) => (
                    <div key={type}>
                      <p className="mb-1.5 text-xs font-semibold text-[#ef6b62]">{type ? type.split("/").join(" / ") : "Inbox"}</p>
                      <div className="overflow-hidden rounded-[14px] bg-[#292a2b]">
                        {notes.map((backlink) => (
                          <button
                            key={backlink.id}
                            type="button"
                            onClick={() => { setPropertiesOpen(false); onOpenNote(backlink.id); }}
                            className="block min-h-12 w-full border-b border-white/[0.07] px-3 py-2 text-left text-sm font-medium last:border-0"
                          >
                            <span className="flex items-center gap-2">
                              <ArrowLeft
                                className="h-3.5 w-3.5 shrink-0 text-[#ef6b62]"
                                aria-label="Backlink"
                              />
                              <span className="truncate">
                                {noteTitle(backlink)}
                              </span>
                            </span>
                          </button>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              ) : null}
            </section>
          </div>
        </div>
      )}
      {historyOpen && <VersionHistoryPanel note={note} mobile onClose={() => setHistoryOpen(false)} />}
      {actionsOpen && (
        <NoteActionSheet
          note={note}
          fileExists={fileExists}
          onClose={() => setActionsOpen(false)}
          onShowProperties={() => setPropertiesOpen(true)}
          onOpenFile={() => onOpenFile(note.id)}
          onRefreshFile={() => onOpenFile(note.id, "refresh")}
          onCopyFileIntoVault={() => { void copyFileIntoVault(); }}
          onLocateFile={() => { void locateFileHub(note.id).then((located) => { if (located) setFileExists(true); }); }}
          onReplaceFile={() => { void replaceLinkedFile(); }}
          onDetachFile={() => setDetachConfirmOpen(true)}
          onMoveToTrash={() => setTrashConfirmOpen(true)}
          onFind={() => setFindRequest((value) => value + 1)}
          onInsertImage={() => imageInputRef.current?.click()}
          onMoveType={() => setMoveTypeOpen(true)}
          onChat={() => onChat({ kind: "note", noteId: note.id, title: noteTitle(note) })}
          onShowHistory={() => setHistoryOpen(true)}
          onExport={() => setExportOpen(true)}
        />
      )}
      <NoteExportDialog
        note={note}
        open={exportOpen}
        onOpenChange={setExportOpen}
      />
      <input
        ref={imageInputRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={(event) => {
          void insertImage(event.target.files?.[0]);
          event.currentTarget.value = "";
        }}
      />
      <Dialog open={moveTypeOpen} onOpenChange={setMoveTypeOpen}>
        <DialogContent className="max-h-[75dvh] overflow-y-auto">
          <DialogHeader><DialogTitle>Move to folder</DialogTitle></DialogHeader>
          <div className="space-y-1">
            {flattenTypes(typeTree).map(({ node, depth }) => (
              <Button
                key={typeKey(node.path)}
                type="button"
                variant="ghost"
                className="w-full justify-start"
                style={{ paddingLeft: `${12 + depth * 18}px` }}
                disabled={typeKey(node.path) === typeKey(noteTypePath(note))}
                onClick={() => {
                  setMoveTypeOpen(false);
                  void setNoteType(note.id, node.path);
                }}
              >
                <Folder className="mr-2 h-4 w-4 text-[#df5149]" />
                {node.name}
              </Button>
            ))}
          </div>
        </DialogContent>
      </Dialog>
      <AlertDialog open={detachConfirmOpen} onOpenChange={setDetachConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Detach “{file?.name ?? "this file"}” from this note?</AlertDialogTitle>
            <AlertDialogDescription>This removes the file link and preview from the note. The file itself will not be deleted or moved.</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => detachFileHub(note.id)}>Detach file</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <Dialog open={pendingAttachPath !== null} onOpenChange={(open) => { if (!open) setPendingAttachPath(null); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>How should this file be attached?</DialogTitle>
          </DialogHeader>
          <p className="break-all text-sm text-muted-foreground">{pendingAttachPath}</p>
          <p className="text-sm text-muted-foreground">A local link stays on this device. A vault copy is portable and will move and trash together with this note.</p>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => {
                if (pendingAttachPath) {
                  void attachFileToNote(note.id, pendingAttachPath, "local").then((result) => {
                    if (result.status === "attached") setFileExists(true);
                    if (result.status === "duplicate") onOpenNote(result.noteId);
                  });
                }
                setPendingAttachPath(null);
              }}
            >
              Link Locally
            </Button>
            <Button
              onClick={() => {
                if (pendingAttachPath) {
                  void attachFileToNote(note.id, pendingAttachPath, "copy").then((result) => {
                    if (result.status === "attached") setFileExists(true);
                    if (result.status === "duplicate") onOpenNote(result.noteId);
                  });
                }
                setPendingAttachPath(null);
              }}
            >
              Copy into Vault
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      <AlertDialog open={trashConfirmOpen} onOpenChange={setTrashConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Move this note to trash?</AlertDialogTitle>
            <AlertDialogDescription>You can restore it later from Recently Deleted.</AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className={buttonVariants({ variant: "destructive" })}
              onClick={() => { void trashNote(note.id).then(onBack); }}
            >
              Move to trash
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

interface ComposerProps {
  onClose: () => void;
  onSave: (title: string, body: string) => Promise<boolean>;
  typePath: string[];
  typeIcon?: string;
  allNotes: Note[];
  isNativeApp: boolean;
}

function Composer({ onClose, onSave, typePath, typeIcon, allNotes, isNativeApp }: ComposerProps) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [bodyFocusRequest, setBodyFocusRequest] = useState(0);
  const [actionsOpen, setActionsOpen] = useState(false);
  const [isClosing, setIsClosing] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const closeTimer = useRef<number | null>(null);
  const typeLabel = typePath.join(" / ");
  const hasDraft = Boolean(title.trim() || body.trim());

  useEffect(() => () => {
    if (closeTimer.current !== null) window.clearTimeout(closeTimer.current);
  }, []);

  const finishClose = () => {
    if (closeTimer.current !== null) {
      window.clearTimeout(closeTimer.current);
      closeTimer.current = null;
    }
    onClose();
  };

  const closeWithSwipe = () => {
    if (isClosing) return;
    setActionsOpen(false);
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      onClose();
      return;
    }
    setIsClosing(true);
    closeTimer.current = window.setTimeout(finishClose, 420);
  };

  const saveAndClose = async () => {
    const nextTitle = title.trim();
    if (!nextTitle || isSaving || isClosing) return;
    setIsSaving(true);
    try {
      const saved = await onSave(nextTitle, body);
      if (saved) closeWithSwipe();
      else setIsSaving(false);
    } catch {
      setIsSaving(false);
    }
  };

  return (
    <div
      className={cn(
        "absolute inset-x-0 bottom-0 z-40 flex flex-col overflow-hidden bg-zerus-editor text-zerus-text",
        isClosing ? "mobile-composer-sheet-exit" : "mobile-composer-sheet-enter",
        isNativeApp ? "top-[var(--mobile-safe-area-top,0px)]" : "top-11",
      )}
      role="dialog"
      aria-modal="true"
      aria-label="New note"
      onAnimationEnd={(event) => {
        if (isClosing && event.animationName === "mobile-composer-sheet-exit") finishClose();
      }}
    >
      <header className="relative grid h-[60px] shrink-0 grid-cols-[44px_1fr_auto] items-center gap-2 px-4 pb-3 pt-1">
        <Button
          variant="ghost"
          size="icon"
          className="h-11 w-11 touch-manipulation rounded-full bg-zerus-text/[0.08] text-zerus-text hover:bg-zerus-text/[0.12]"
          onClick={closeWithSwipe}
          aria-label="Close composer"
        >
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div className="pointer-events-none absolute left-1/2 flex max-w-[36%] -translate-x-1/2 items-center justify-center gap-1.5 overflow-hidden text-[14px] font-medium leading-none text-zerus-accent">
          <TypeIcon icon={typeIcon} size={16} className="shrink-0" />
          <span className="truncate capitalize">{typeLabel}</span>
        </div>
        <div className="col-start-3 flex items-center justify-self-end gap-2">
          <div className="flex h-10 w-10 items-center overflow-hidden rounded-full bg-zerus-text/[0.08]">
            <Button
              variant="ghost"
              size="icon"
              className="h-10 w-10 shrink-0 rounded-full text-zerus-text hover:bg-zerus-text/[0.08]"
              onClick={() => setActionsOpen(true)}
              aria-label="More note actions"
            >
              <MoreHorizontal className="h-[20px] w-[20px]" />
            </Button>
          </div>
          <Button
            variant="ghost"
            size="icon"
            className="h-10 w-10 shrink-0 rounded-full bg-zerus-accent text-white shadow-[0_4px_14px_rgb(var(--zerus-accent)/0.26)] hover:bg-zerus-accent/90 disabled:bg-zerus-text/[0.08] disabled:text-zerus-text/30 disabled:opacity-100"
            disabled={!title.trim() || isSaving || isClosing}
            onClick={() => void saveAndClose()}
            aria-label="Save note"
          >
            {isSaving ? <Loader2 className="h-5 w-5 animate-spin" /> : <Check className="h-[21px] w-[21px]" strokeWidth={2.6} />}
          </Button>
        </div>
      </header>
      <main className="mobile-note-body flex min-h-0 flex-1 flex-col overflow-hidden px-6 pt-2">
        <div className="shrink-0 pb-2 pt-3">
          <Input
            value={title}
            onChange={(event) => setTitle(event.target.value)}
            onKeyDown={(event) => {
              if (event.key !== "Enter") return;
              event.preventDefault();
              setBodyFocusRequest((request) => request + 1);
            }}
            autoFocus
            aria-label="Note title"
            className="h-auto border-0 bg-transparent px-0 text-[27px] font-bold leading-[1.06] tracking-[-0.045em] text-zerus-text shadow-none ring-offset-0 placeholder:text-zerus-text focus-visible:border-transparent focus-visible:ring-0 focus-visible:ring-offset-0 md:text-[27px]"
          />
        </div>
        <div className="mobile-note-editor -mx-6 min-h-0 flex-1 overflow-hidden">
          <MarkdownEditor
            noteId="mobile-new-note"
            initialContent={body}
            getLinkableTitles={() => allNotes
              .filter((note) => !isExternalNote(note) && !isTrashed(note))
              .map((note) => noteTitle(note))}
            isTitleResolved={(linkTitle) => !!findNoteByTitle(linkTitle, allNotes)}
            onChange={setBody}
            onFollowLink={() => undefined}
            autoFocus={false}
            focusRequest={bodyFocusRequest}
            placeholderText=""
            firstLineIsTitle={false}
          />
        </div>
      </main>
      {actionsOpen && (
        <div className="absolute inset-0 z-[70] flex items-end bg-black/55" role="dialog" aria-modal="true" aria-label="New note actions" onClick={() => setActionsOpen(false)}>
          <section className="w-full rounded-t-[26px] bg-zerus-editor px-4 pb-[calc(env(safe-area-inset-bottom)+1rem)] pt-3 text-zerus-text shadow-2xl" onClick={(event) => event.stopPropagation()}>
            <div className="mx-auto h-1 w-10 rounded-full bg-zerus-text/20" />
            <h3 className="px-2 pb-3 pt-4 text-center text-[15px] font-semibold text-zerus-text/60">New note</h3>
            <div className="overflow-hidden rounded-[16px] bg-zerus-surface">
              <button
                type="button"
                disabled={!hasDraft}
                onClick={() => { setTitle(""); setBody(""); setActionsOpen(false); }}
                className="flex min-h-[56px] w-full items-center gap-3 border-b border-zerus-text/[0.08] px-4 text-left text-[16px] active:bg-zerus-text/[0.05] disabled:opacity-35"
              >
                <span className="flex h-8 w-8 items-center justify-center"><X className="h-5 w-5" /></span>
                <span>Clear draft</span>
              </button>
              <button type="button" onClick={closeWithSwipe} className="flex min-h-[56px] w-full items-center gap-3 px-4 text-left text-[16px] text-destructive active:bg-zerus-text/[0.05]">
                <span className="flex h-8 w-8 items-center justify-center"><Trash2 className="h-5 w-5" /></span>
                <span>Discard note</span>
              </button>
            </div>
            <button type="button" onClick={() => setActionsOpen(false)} className="mt-3 h-[52px] w-full rounded-[16px] bg-zerus-surface text-[16px] font-semibold active:bg-zerus-text/[0.08]">Cancel</button>
          </section>
        </div>
      )}
    </div>
  );
}

interface MobileSettingsProps {
  location: string | null;
  defaultNoteType: string[];
  typeTree: TypeNode[];
  onDefaultNoteTypeChange: (typePath: string[]) => void;
  onClose: () => void;
  onChangeVault: () => void;
}

type MobileSettingsPage =
  | "root"
  | "general"
  | "appearance"
  | "vault"
  | "locations"
  | "history";

const MOBILE_SETTINGS_TITLES: Record<MobileSettingsPage, string> = {
  root: "Settings",
  general: "General",
  appearance: "Appearance",
  vault: "Vault",
  locations: "File Locations",
  history: "Version History",
};

function MobileSettings({
  location,
  defaultNoteType,
  typeTree,
  onDefaultNoteTypeChange,
  onClose,
  onChangeVault,
}: MobileSettingsProps) {
  const { fileLocations, historyError, historySettings } = useVault();
  const locationMappings = getFileLocationMappings();
  const [locationDraft, setLocationDraft] = useState("");
  const [busyLocation, setBusyLocation] = useState<string | null>(null);
  const [locationMessage, setLocationMessage] = useState<string | null>(null);
  const [clearHistoryOpen, setClearHistoryOpen] = useState(false);
  const [page, setPage] = useState<MobileSettingsPage>("root");
  const defaultTypeOptions = [...new Set([
    typeKey(DEFAULT_TYPE),
    ...flattenTypeKeys(typeTree),
    typeKey(defaultNoteType),
  ])];
  const mapLocation = async (id: string) => {
    setBusyLocation(id);
    setLocationMessage(null);
    try {
      const mapped = await mapFileLocation(id);
      if (!mapped) setLocationMessage("No folder was selected.");
    } catch (error) {
      setLocationMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setBusyLocation(null);
    }
  };

  const addLocation = async () => {
    const name = locationDraft.trim();
    if (!name) return;
    setBusyLocation("new");
    setLocationMessage(null);
    try {
      const added = await addFileLocation(name);
      if (added) setLocationDraft("");
      else setLocationMessage("No folder was selected.");
    } catch (error) {
      setLocationMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setBusyLocation(null);
    }
  };

  return (
    <div className="absolute inset-0 z-50 flex min-h-0 items-end bg-black/45 backdrop-blur-[2px]" role="dialog" aria-modal="true" aria-label="Mobile settings">
      <section className="flex h-[92%] max-h-[92dvh] min-h-0 w-full flex-col overflow-hidden rounded-t-[28px] border-t border-zerus-text/[0.06] bg-zerus-editor text-zerus-text shadow-2xl">
        <header className="grid shrink-0 grid-cols-[minmax(72px,auto)_1fr_minmax(72px,auto)] items-center border-b border-zerus-text/[0.06] bg-zerus-editor px-4 pb-3 pt-4">
          <div className="flex justify-start">
            {page !== "root" && (
              <Button
                type="button"
                variant="ghost"
                onClick={() => setPage("root")}
                className="h-10 gap-1 rounded-full px-2 text-sm font-semibold text-zerus-accent hover:bg-zerus-accent/10 hover:text-zerus-accent"
                aria-label="Back to settings"
              >
                <ArrowLeft className="h-5 w-5" />
                Settings
              </Button>
            )}
          </div>
          <div className="min-w-0 text-center">
            <h2 className="truncate text-[18px] font-bold tracking-[-0.025em]">{MOBILE_SETTINGS_TITLES[page]}</h2>
            {page === "root" && <p className="mt-0.5 text-xs text-zerus-text/55">Markdown vault</p>}
          </div>
          <div className="flex justify-end">
          <Button
            type="button"
            variant="ghost"
            onClick={onClose}
            className="h-10 rounded-full bg-zerus-accent/12 px-4 text-sm font-semibold text-zerus-accent hover:bg-zerus-accent/18 hover:text-zerus-accent"
            aria-label="Close settings"
          >
            Done
          </Button>
          </div>
        </header>

        <div className="min-h-0 flex-1 touch-pan-y overflow-y-auto overscroll-contain px-5 pb-[calc(env(safe-area-inset-bottom)+1.25rem)] [-webkit-overflow-scrolling:touch]">
        {page === "root" && (
          <div className="space-y-5 pt-5">
            <div className="overflow-hidden rounded-[16px] bg-zerus-surface">
              {([
                { page: "general", label: "General", description: "Dates and new-note defaults", icon: <Settings className="h-5 w-5" /> },
                { page: "appearance", label: "Appearance", description: "Theme and colour palette", icon: <Sparkles className="h-5 w-5" /> },
              ] as const).map((item) => (
                <button
                  type="button"
                  key={item.page}
                  onClick={() => setPage(item.page)}
                  className="flex min-h-[64px] w-full items-center gap-3 border-b border-zerus-text/[0.08] px-4 text-left last:border-b-0 active:bg-zerus-text/[0.05]"
                >
                  <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[10px] bg-zerus-accent text-white">{item.icon}</span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-[16px] font-semibold">{item.label}</span>
                    <span className="mt-0.5 block truncate text-xs text-zerus-text/50">{item.description}</span>
                  </span>
                  <ChevronRight className="h-5 w-5 shrink-0 text-zerus-text/30" />
                </button>
              ))}
            </div>
            <div className="overflow-hidden rounded-[16px] bg-zerus-surface">
              {([
                { page: "vault", label: "Vault", description: location ?? "Your Markdown vault", icon: <Folder className="h-5 w-5" /> },
                { page: "locations", label: "File Locations", description: "Map synced folders on this device", icon: <FolderCog className="h-5 w-5" /> },
                { page: "history", label: "Version History", description: historySettings.enabled ? "Automatic history is on" : "Automatic history is off", icon: <History className="h-5 w-5" /> },
              ] as const).map((item) => (
                <button
                  type="button"
                  key={item.page}
                  onClick={() => setPage(item.page)}
                  className="flex min-h-[64px] w-full items-center gap-3 border-b border-zerus-text/[0.08] px-4 text-left last:border-b-0 active:bg-zerus-text/[0.05]"
                >
                  <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[10px] bg-zerus-text/[0.08] text-zerus-accent">{item.icon}</span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-[16px] font-semibold">{item.label}</span>
                    <span className="mt-0.5 block truncate text-xs text-zerus-text/50">{item.description}</span>
                  </span>
                  <ChevronRight className="h-5 w-5 shrink-0 text-zerus-text/30" />
                </button>
              ))}
            </div>
          </div>
        )}

        {page === "general" && <div className="pt-5"><DateFormatSetting />
          <p className="mb-2 mt-6 text-xs font-semibold uppercase tracking-[0.08em] text-zerus-text/45">New notes</p>
          <div className="rounded-[16px] bg-zerus-surface p-4">
            <label htmlFor="mobile-default-note-type" className="block text-[15px] font-semibold">Default type</label>
            <p id="mobile-default-note-type-description" className="mb-3 mt-1 text-xs leading-4 text-zerus-text/55">
              Used when creating notes from All Notes. Inside a type, new notes use that type. Saved for this vault on this device.
            </p>
            <select
              id="mobile-default-note-type"
              aria-describedby="mobile-default-note-type-description"
              value={typeKey(defaultNoteType)}
              onChange={(event) => onDefaultNoteTypeChange(parseTypePath(event.target.value))}
              className="min-h-11 w-full min-w-0 rounded-[11px] border border-zerus-text/[0.08] bg-zerus-editor px-3 text-base text-zerus-text"
            >
              {defaultTypeOptions.map((key) => (
                <option key={key} value={key}>
                  {key === typeKey(DEFAULT_TYPE) ? "Inbox" : parseTypePath(key).join(" / ")}
                </option>
              ))}
            </select>
          </div>
        </div>}

        {page === "appearance" && <MobileThemeSettings />}

        {page === "vault" && <>
        <p className="mb-2 mt-6 text-xs font-semibold uppercase tracking-[0.08em] text-zerus-text/45">Current vault</p>
        <div className="rounded-[16px] bg-zerus-surface px-4 py-4">
          <div className="flex items-center gap-3">
            <span className="flex h-10 w-10 items-center justify-center rounded-[11px] bg-zerus-accent text-white"><Folder className="h-5 w-5" /></span>
            <span className="min-w-0 flex-1"><span className="block text-[15px] font-semibold">{location ?? "Zerus"}</span><span className="mt-0.5 block text-xs text-zerus-text/55">Your Markdown vault</span></span>
          </div>
          {location?.startsWith("Google Drive ·") && <Button type="button" variant="ghost" onClick={() => void reloadVault()} className="mt-3 w-full">Save and refresh Google Drive</Button>}
          <Button type="button" variant="ghost" onClick={onChangeVault} className="mt-4 h-10 w-full rounded-[12px] bg-zerus-text/[0.07] text-sm font-semibold text-zerus-accent hover:bg-zerus-text/[0.1] hover:text-zerus-accent">Change vault</Button>
        </div>
        </>}

        {page === "locations" && <>
          <p className="mb-2 mt-6 text-xs font-semibold uppercase tracking-[0.08em] text-zerus-text/45">File locations</p>
          <div className="rounded-[16px] bg-zerus-surface p-3">
          <p className="px-1 pb-3 text-xs leading-4 text-zerus-text/55">
            Map each synced location to its folder on this device. Use a provider that supports folder access, such as iCloud Drive. Google Drive vaults connect separately; Drive file-location mappings are not supported.
          </p>
          <div className="space-y-2">
            {fileLocations.map((fileLocation) => {
              const mapped = locationMappings[fileLocation.id];
              const usages = fileLocationUsages(fileLocation.id);
              const busy = busyLocation === fileLocation.id;
              return (
                <div key={fileLocation.id} className="rounded-[13px] bg-zerus-text/[0.06] p-3">
                  <div className="flex items-center gap-2">
                    <FolderCog className="h-5 w-5 shrink-0 text-zerus-accent" />
                    <Input
                      defaultValue={fileLocation.name}
                      aria-label="File location name"
                      className="h-9 min-w-0 flex-1 border-zerus-text/[0.08] bg-transparent text-sm"
                      onBlur={(event) => renameFileLocation(fileLocation.id, event.target.value)}
                    />
                    <Button
                      type="button"
                      variant="ghost"
                      disabled={busyLocation !== null}
                      onClick={() => void mapLocation(fileLocation.id)}
                      className="h-9 shrink-0 rounded-[10px] bg-zerus-text/[0.08] px-3 text-xs font-semibold text-zerus-accent hover:bg-zerus-text/[0.12] hover:text-zerus-accent"
                    >
                      {busy ? <Loader2 className="mr-1 h-3.5 w-3.5 animate-spin" /> : <MapPin className="mr-1 h-3.5 w-3.5" />}
                      {mapped ? "Remap" : "Map"}
                    </Button>
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon"
                      disabled={usages.length > 0 || busyLocation !== null}
                      onClick={() => removeFileLocation(fileLocation.id)}
                      className="h-9 w-9 shrink-0 rounded-[10px] text-[#ff6961] disabled:text-[#66666b]"
                      aria-label={`Remove ${fileLocation.name}`}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                  <p className="mt-1 truncate pl-7 text-[11px] text-zerus-text/45">
                    {mapped ?? "Not configured on this device"}
                    {usages.length > 0 && ` · ${usages.length} file${usages.length === 1 ? "" : "s"}`}
                  </p>
                </div>
              );
            })}
          </div>
          <div className="mt-3 flex gap-2">
            <Input
              value={locationDraft}
              onChange={(event) => setLocationDraft(event.target.value)}
              placeholder="Company OneDrive"
              className="h-10 min-w-0 flex-1 border-zerus-text/[0.08] bg-zerus-text/[0.04] text-sm"
            />
            <Button
              type="button"
              disabled={!locationDraft.trim() || busyLocation !== null}
              onClick={() => void addLocation()}
              className="h-10 shrink-0 rounded-[11px] bg-zerus-accent px-3 text-xs font-semibold text-white"
            >
              {busyLocation === "new" ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <FolderOpen className="mr-1 h-4 w-4" />}
              Add
            </Button>
          </div>
          {locationMessage && <p className="mt-3 rounded-[11px] bg-zerus-accent/10 px-3 py-2 text-xs text-zerus-accent">{locationMessage}</p>}
          </div>
        </>}

        {page === "history" && <>
          <p className="mb-2 mt-6 text-xs font-semibold uppercase tracking-[0.08em] text-zerus-text/45">Version history</p>
          <div className="space-y-4 rounded-[16px] bg-zerus-surface p-4">
          <div className="flex items-center justify-between gap-3">
            <span><span className="block text-[15px] font-semibold">Record history</span><span className="mt-0.5 block text-xs text-zerus-text/55">Autosaves after 5 seconds idle</span></span>
            <Switch checked={historySettings.enabled} onCheckedChange={(enabled) => void updateVersionHistorySettings({ ...historySettings, enabled })} />
          </div>
          <div className="flex items-center gap-3 border-t border-zerus-text/[0.08] pt-4">
            <span className="min-w-0 flex-1"><span className="block text-[15px] font-semibold">Retained checkpoints</span><span className="mt-0.5 block text-xs text-zerus-text/55">3 autosaves per checkpoint</span></span>
            {historySettings.checkpointLimit === null ? <Button variant="ghost" className="h-10 rounded-[11px] bg-zerus-text/[0.07] px-3 text-xs" onClick={() => void updateVersionHistorySettings({ ...historySettings, checkpointLimit: 10 })}>Unlimited</Button> : <Input key={historySettings.checkpointLimit} type="number" min={1} max={100} defaultValue={historySettings.checkpointLimit} className="h-10 w-20 border-zerus-text/[0.08] bg-zerus-text/[0.04] text-center" onBlur={(event) => void updateVersionHistorySettings({ ...historySettings, checkpointLimit: Math.max(1, Math.min(100, Number(event.target.value) || 1)) })} />}
          </div>
          <button type="button" className="text-left text-xs font-semibold text-zerus-accent" onClick={() => void updateVersionHistorySettings({ ...historySettings, checkpointLimit: historySettings.checkpointLimit === null ? 10 : null })}>{historySettings.checkpointLimit === null ? "Use a fixed limit" : "Keep unlimited checkpoints"}</button>
          <button type="button" className="block border-t border-zerus-text/[0.08] pt-4 text-left text-sm font-semibold text-[#ff6961]" onClick={() => setClearHistoryOpen(true)}>Clear all version history</button>
          {historyError && <p className="rounded-[11px] bg-zerus-accent/10 px-3 py-2 text-xs text-zerus-accent">{historyError}</p>}
          </div>
        </>}
        </div>
      </section>
      <AlertDialog open={clearHistoryOpen} onOpenChange={setClearHistoryOpen}><AlertDialogContent><AlertDialogHeader><AlertDialogTitle>Clear all version history?</AlertDialogTitle><AlertDialogDescription>This permanently deletes automatic and kept versions for every note in this vault. Current notes and live images are not changed.</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel>Cancel</AlertDialogCancel><AlertDialogAction className="bg-destructive text-destructive-foreground" onClick={() => void clearVaultVersionHistory().then(() => setClearHistoryOpen(false))}>Clear all history</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
    </div>
  );
}

interface VaultSetupProps {
  nativeAvailable: boolean;
  error: string | null;
  onClose?: () => void;
  onLocate: () => Promise<boolean>;
  onDrive: (selection: DriveVaultSelection) => Promise<boolean>;
  onCreateAtLocation: () => Promise<boolean>;
  onCreateOnDevice: () => Promise<boolean>;
}

function VaultSetup({
  nativeAvailable,
  error,
  onClose,
  onLocate,
  onDrive,
  onCreateAtLocation,
  onCreateOnDevice,
}: VaultSetupProps) {
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [driveOpen, setDriveOpen] = useState(false);

  const run = async (label: string, action: () => Promise<boolean>) => {
    setBusyAction(label);
    try {
      await action();
    } finally {
      setBusyAction(null);
    }
  };

  const actionRow = (
    label: string,
    description: string,
    icon: ReactNode,
    action: () => Promise<boolean>,
  ) => (
    <button type="button" disabled={busyAction !== null || !nativeAvailable} onClick={() => void run(label, action)} className="flex w-full items-center gap-3 border-b border-white/[0.08] px-4 py-4 text-left last:border-0 disabled:opacity-50">
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[11px] bg-[#343536] text-[#f5f3ef]">{icon}</span>
      <span className="min-w-0 flex-1"><span className="block text-[15px] font-semibold">{label}</span><span className="mt-0.5 block text-xs leading-4 text-[#8e8e93]">{description}</span></span>
      {busyAction === label ? <Loader2 className="h-5 w-5 animate-spin text-[#ef6b62]" /> : <ChevronRight className="h-5 w-5 text-[#66666b]" />}
    </button>
  );

  if (driveOpen) return <GoogleDrivePicker onClose={() => setDriveOpen(false)} onChoose={async (selection) => {
    const opened = await onDrive(selection);
    if (opened) onClose?.();
    return opened;
  }} />;

  return (
    <main className="absolute inset-0 z-50 flex flex-col overflow-y-auto bg-[#1c1d1e] px-5 pb-[calc(env(safe-area-inset-bottom)+1.5rem)] pt-4">
      {onClose && <Button variant="ghost" size="icon" onClick={onClose} disabled={busyAction !== null} className="ml-auto h-10 w-10 rounded-full bg-white/[0.08]" aria-label="Close vault setup"><X className="h-5 w-5" /></Button>}
      <div className={cn("mx-auto flex w-full max-w-sm flex-1 flex-col justify-center", onClose ? "pb-4" : "pb-10")}>
        <span className="flex h-14 w-14 items-center justify-center rounded-[17px] bg-[#df5149] text-white shadow-[0_10px_30px_rgba(223,81,73,0.24)]"><Folder className="h-7 w-7" /></span>
        <h1 className="mt-6 text-[32px] font-bold leading-[1.05] tracking-[-0.045em]">Find your Zerus</h1>
        <p className="mt-3 text-[15px] leading-6 text-[#9a9691]">Open an existing vault, or create one if Zerus cannot find it.</p>

        <Button disabled={busyAction !== null || !nativeAvailable} onClick={() => void run("Locate existing vault", onLocate)} className="mt-7 h-[52px] rounded-[15px] bg-[#df5149] text-[15px] font-semibold text-white hover:bg-[#e15d54]">
          {busyAction === "Locate existing vault" ? <Loader2 className="mr-2 h-5 w-5 animate-spin" /> : <FolderSearch className="mr-2 h-5 w-5" />}
          Locate existing vault
        </Button>
        <p className="mt-2 text-center text-xs leading-4 text-[#77777d]">Use iCloud Drive or another provider that supports folder access.</p>
        <div className="mt-4 overflow-hidden rounded-[17px] bg-[#292a2b]">
          {actionRow("Google Drive", "Connect your account and choose a vault folder", <Cloud className="h-5 w-5" />, async () => {
            if (!(await prepareGoogleDriveConnection())) return false;
            setDriveOpen(true);
            return false;
          })}
        </div>

        <div className="my-6 flex items-center gap-3"><span className="h-px flex-1 bg-white/[0.08]" /><span className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[#66666b]">Create a vault</span><span className="h-px flex-1 bg-white/[0.08]" /></div>
        <div className="overflow-hidden rounded-[17px] bg-[#292a2b]">
          {actionRow("Choose a location", "Create a Zerus folder wherever you choose", <Folder className="h-5 w-5" />, onCreateAtLocation)}
          {actionRow("On this iPhone", "Let Zerus choose a private local folder", <Smartphone className="h-5 w-5" />, onCreateOnDevice)}
          {actionRow("iCloud Drive", "Choose where to create the vault in iCloud Drive", <Cloud className="h-5 w-5" />, onCreateAtLocation)}
        </div>
        {error && <p className="mt-4 rounded-[13px] bg-[#df5149]/10 px-4 py-3 text-sm leading-5 text-[#ef847d]">{error}</p>}
        {!nativeAvailable && <p className="mt-4 text-center text-xs text-[#77777d]">Vault selection is available in the iOS app.</p>}
      </div>
    </main>
  );
}

export function MobileZerus() {
  const isNativeApp = "__TAURI_INTERNALS__" in window;
  const vault = useVault();
  const [selectedNoteId, setSelectedNoteId] = useState<string | null>(null);
  const [composerOpen, setComposerOpen] = useState(false);
  const [libraryOpen, setLibraryOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [chatOpen, setChatOpen] = useState(false);
  const [chatHistoryOpen, setChatHistoryOpen] = useState(false);
  const [chatScope, setChatScope] = useState<ChatScope>({ kind: "vault" });
  const [noteOrigin, setNoteOrigin] = useState<"notes" | "chat">("notes");
  const [notesPreparationError, setNotesPreparationError] = useState<string | null>(null);
  const [emptyTrashConfirmOpen, setEmptyTrashConfirmOpen] = useState(false);
  const [deleteImageTargetId, setDeleteImageTargetId] = useState<string | null>(null);
  const [vaultSetupOpen, setVaultSetupOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [scope, setScope] = useState<NoteFilter>({ kind: "all" });
  const [typeOrder, setTypeOrder] = useState<string[]>(() => loadNoteTypeOrder(null));
  const [defaultNoteType, setDefaultNoteTypeState] = useState<string[]>(() => loadDefaultNoteType(null));
  const [typeActionTarget, setTypeActionTarget] = useState<TypeActionTarget | null>(null);
  const [typeDraft, setTypeDraft] = useState<string | null>(null);
  const [typeParentPath, setTypeParentPath] = useState<string[]>([]);
  const [renameTarget, setRenameTarget] = useState<TypeNode | null>(null);
  const [renameDraft, setRenameDraft] = useState("");
  const [iconTarget, setIconTarget] = useState<TypeNode | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<TypeNode | null>(null);
  const notesSwipeStart = useRef<{ x: number; y: number; axis: "horizontal" | "vertical" | null } | null>(null);

  useLayoutEffect(() => {
    if (!isNativeApp) return;

    const safeAreaProbe = document.createElement("div");
    safeAreaProbe.style.cssText = [
      "position:fixed",
      "visibility:hidden",
      "pointer-events:none",
      "padding-top:env(safe-area-inset-top)",
    ].join(";");
    document.body.appendChild(safeAreaProbe);

    const safeAreaTop = getComputedStyle(safeAreaProbe).paddingTop;
    safeAreaProbe.remove();
    document.documentElement.style.setProperty(
      "--mobile-safe-area-top",
      safeAreaTop,
    );

    return () => {
      document.documentElement.style.removeProperty("--mobile-safe-area-top");
    };
  }, [isNativeApp]);

  useEffect(() => {
    document.documentElement.classList.add("mobile-zerus-page");
    return () => document.documentElement.classList.remove("mobile-zerus-page");
  }, []);

  useEffect(() => {
    initStore();
  }, []);

  useEffect(() => {
    if (readMobileNavigationEntry(window.history.state)) return;
    window.history.replaceState(
      withMobileNavigationEntry(window.history.state, { view: "notes" }),
      "",
    );
  }, []);

  useEffect(() => {
    const restoreNavigation = (entry: MobileNavigationEntry | null) => {
      if (!entry || entry.view === "notes") {
        setSelectedNoteId(null);
        setChatOpen(false);
        setChatHistoryOpen(false);
        return;
      }
      if (entry.view === "chat" || entry.view === "chat-history") {
        setSelectedNoteId(null);
        setChatOpen(true);
        setChatHistoryOpen(entry.view === "chat-history");
        return;
      }
      setNoteOrigin(entry.origin);
      setSelectedNoteId(entry.noteId);
      setChatOpen(entry.origin === "chat");
      setChatHistoryOpen(false);
    };
    const onPopState = (event: PopStateEvent) => restoreNavigation(readMobileNavigationEntry(event.state));
    window.addEventListener("popstate", onPopState);
    return () => window.removeEventListener("popstate", onPopState);
  }, []);

  useEffect(() => {
    if (query.trim() && vault.hasMoreNotes) void loadAllNotes();
  }, [query, vault.hasMoreNotes]);

  useEffect(() => {
    setTypeOrder(loadNoteTypeOrder(vault.location));
    setDefaultNoteTypeState(loadDefaultNoteType(vault.location));
  }, [vault.location]);

  const selectedSourceNote = vault.notes.find((note) => note.id === selectedNoteId) ?? null;
  const selectedNote = selectedSourceNote
    ? presentNote(selectedSourceNote, vault.typeIcons)
    : null;
  const typeTree = useMemo(() => {
    if (vault.isNotePaginationEnabled) {
      return buildTypeTreeFromCounts(vault.typeNoteCounts, vault.extraTypes);
    }
    return buildTypeTree(vault.notes, vault.extraTypes, typeOrder);
  }, [typeOrder, vault.extraTypes, vault.isNotePaginationEnabled, vault.notes, vault.typeNoteCounts]);
  const creationType = useMemo(
    () => noteCreationType(scope, defaultNoteType),
    [defaultNoteType, scope],
  );
  const scopeTitle = scope.kind === "all"
    ? "All Notes"
    : scope.kind === "external"
      ? "External Notes"
      : scope.kind === "files"
        ? "Files"
        : scope.kind === "links"
          ? "Links"
        : scope.kind === "tasks"
          ? "Tasks"
        : scope.kind === "trash"
          ? "Recently Deleted"
          : scope.path.join(" / ");
  const filteredNotes = useMemo(() => {
    return filterNotes(vault.notes, scope, query).map((note) =>
      presentNote(note, vault.typeIcons),
    );
  }, [query, scope, vault.notes, vault.typeIcons]);
  const libraryCounts = useMemo(() => ({
    all: vault.isNotePaginationEnabled ? vault.totalNoteCount : filterNotes(vault.notes, { kind: "all" }, "").length,
    external: filterNotes(vault.notes, { kind: "external" }, "").length,
    files: filterNotes(vault.notes, { kind: "files" }, "").length,
    trash: filterNotes(vault.notes, { kind: "trash" }, "").length + vault.trashedImages.length,
  }), [vault.isNotePaginationEnabled, vault.notes, vault.totalNoteCount, vault.trashedImages.length]);

  const pushNavigation = (entry: MobileNavigationEntry) => {
    window.history.pushState(withMobileNavigationEntry(window.history.state, entry), "");
  };

  const openNote = (noteId: string, origin: "notes" | "chat" = "notes") => {
    setNoteOrigin(origin);
    setSelectedNoteId(noteId);
    pushNavigation({ view: "note", noteId, origin });
  };

  const prepareAllNotes = async () => {
    setNotesPreparationError(null);
    try {
      await loadAllNotes();
    } catch (error) {
      setNotesPreparationError(String(error));
    }
  };

  const openChat = (nextScope: ChatScope = { kind: "vault" }) => {
    setChatScope(nextScope);
    setSelectedNoteId(null);
    setChatOpen(true);
    setChatHistoryOpen(false);
    pushNavigation({ view: "chat" });
    if (vault.hasMoreNotes) void prepareAllNotes();
  };

  const handleNotesTouchStart = (event: ReactTouchEvent<HTMLDivElement>) => {
    const touch = event.touches[0];
    if (!touch || libraryOpen) return;
    notesSwipeStart.current = { x: touch.clientX, y: touch.clientY, axis: null };
  };

  const handleNotesTouchMove = (event: ReactTouchEvent<HTMLDivElement>) => {
    const start = notesSwipeStart.current;
    const touch = event.touches[0];
    if (!start || !touch) return;
    const deltaX = touch.clientX - start.x;
    const deltaY = touch.clientY - start.y;
    if (!start.axis && Math.max(Math.abs(deltaX), Math.abs(deltaY)) >= 8) {
      start.axis = Math.abs(deltaX) > Math.abs(deltaY) ? "horizontal" : "vertical";
    }
    if (start.axis === "horizontal" && deltaX > 0) event.preventDefault();
  };

  const handleNotesTouchEnd = (event: ReactTouchEvent<HTMLDivElement>) => {
    const start = notesSwipeStart.current;
    const touch = event.changedTouches[0];
    notesSwipeStart.current = null;
    if (!start || !touch || start.axis !== "horizontal") return;
    if (horizontalSwipeDirection(start, { x: touch.clientX, y: touch.clientY }) === "right") {
      setLibraryOpen(true);
    }
  };

  const saveQuickNote = async (title: string, body: string) => {
    const content = `# ${title}\n\n${body.trim()}`;
    const note = await createNote(creationType, content);
    return Boolean(note);
  };

  const pinnedNotes = filteredNotes.filter((note) => note.pinned);
  const recentNotes = filteredNotes.filter((note) => !note.pinned);

  const resetNavigation = () => {
    setSelectedNoteId(null);
    setQuery("");
    setScope({ kind: "all" });
    setLibraryOpen(false);
  };

  const selectScope = (nextScope: NoteFilter) => {
    setScope(nextScope);
    setSelectedNoteId(null);
    setQuery("");
    setLibraryOpen(false);
  };

  const updateTypeOrder = (nextOrder: string[]) => {
    setTypeOrder(nextOrder);
    saveNoteTypeOrder(vault.location, nextOrder);
  };

  const updateDefaultNoteType = (nextType: string[]) => {
    setDefaultNoteTypeState(nextType);
    saveDefaultNoteType(vault.location, nextType);
  };

  const startTypeCreation = (parentPath: string[] = []) => {
    setTypeParentPath(parentPath);
    setTypeDraft("");
  };

  const closeTypeCreation = () => {
    setTypeDraft(null);
    setTypeParentPath([]);
  };

  const submitNewType = async (name: string) => {
    const path = [...typeParentPath, name].slice(0, MAX_TYPE_DEPTH);
    closeTypeCreation();
    if (!path.length) return;
    const existingKeys = new Set(flattenTypeKeys(typeTree));
    const created = await createType(path);
    if (!created) return;
    const newKeys: string[] = [];
    for (let depth = 1; depth <= path.length; depth += 1) {
      const key = typeKey(path.slice(0, depth));
      if (!existingKeys.has(key)) newKeys.push(key);
    }
    if (newKeys.length) {
      const currentKeys = new Set(typeOrder);
      const baseline = [
        ...typeOrder,
        ...flattenTypeKeys(typeTree).filter((key) => !currentKeys.has(key)),
      ].filter((key) => !newKeys.includes(key));
      updateTypeOrder([...baseline, ...newKeys]);
    }
    setScope({ kind: "type", path });
  };

  const moveType = (target: TypeActionTarget, direction: "up" | "down") => {
    const siblingKey = direction === "up" ? target.previousKey : target.nextKey;
    if (!siblingKey) return;
    const nextOrder = reorderTypeTree(
      typeTree,
      typeKey(target.node.path),
      siblingKey,
      direction === "up" ? "before" : "after",
    );
    if (nextOrder) updateTypeOrder(nextOrder);
  };

  const startRename = (node: TypeNode) => {
    setRenameTarget(node);
    setRenameDraft(typeKey(node.path));
  };

  const submitRename = async () => {
    if (!renameTarget) return;
    const oldPath = renameTarget.path;
    const newPath = parseTypePath(renameDraft);
    if (!newPath.length || typeKey(newPath) === typeKey(oldPath)) {
      setRenameTarget(null);
      return;
    }
    const renamed = await renameType(oldPath, newPath);
    if (!renamed) return;
    setRenameTarget(null);
    const oldKey = typeKey(oldPath);
    const oldPrefix = `${oldKey}/`;
    const newKey = typeKey(newPath);
    updateTypeOrder(typeOrder.map((key) =>
      key === oldKey
        ? newKey
        : key.startsWith(oldPrefix)
          ? `${newKey}/${key.slice(oldPrefix.length)}`
          : key,
    ));
    const defaultKey = typeKey(defaultNoteType);
    if (defaultKey === oldKey || defaultKey.startsWith(`${oldKey}/`)) {
      updateDefaultNoteType([...newPath, ...defaultNoteType.slice(oldPath.length)]);
    }
    if (scope.kind === "type") {
      const activeKey = typeKey(scope.path);
      if (activeKey === oldKey || activeKey.startsWith(`${oldKey}/`)) {
        setScope({ kind: "type", path: [...newPath, ...scope.path.slice(oldPath.length)] });
      }
    }
  };

  const confirmDeleteType = async () => {
    if (!deleteTarget) return;
    const target = deleteTarget;
    const key = typeKey(target.path);
    setDeleteTarget(null);
    const deleted = await deleteType(target.path);
    if (!deleted) return;
    updateTypeOrder(typeOrder.filter((type) => type !== key && !type.startsWith(`${key}/`)));
    const defaultKey = typeKey(defaultNoteType);
    if (defaultKey === key || defaultKey.startsWith(`${key}/`)) {
      updateDefaultNoteType(DEFAULT_TYPE);
    }
    const activeKey = scope.kind === "type" ? typeKey(scope.path) : null;
    if (activeKey && (activeKey === key || activeKey.startsWith(`${key}/`))) {
      setScope({ kind: "all" });
    }
  };

  const createForScope = async () => {
    if (scope.kind === "external") {
      const ids = await openExternalNotes();
      if (ids[0]) openNote(ids[0]);
      return;
    }
    if (scope.kind === "files") {
      const note = await createFileNote(creationType);
      if (note) openNote(note.id);
      return;
    }
    setComposerOpen(true);
  };

  const runVaultAction = async (action: () => Promise<boolean>) => {
    const changed = await action();
    if (changed) {
      resetNavigation();
      setVaultSetupOpen(false);
    }
    return changed;
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-zerus-sidebar p-0 sm:p-8">
      <section className={cn("mobile-zerus-themed relative flex h-[100dvh] w-full max-w-[393px] flex-col overflow-hidden bg-zerus-editor text-zerus-text sm:h-[852px] sm:rounded-[42px] sm:border-[7px] sm:border-zerus-sidebar sm:shadow-[0_28px_70px_rgba(0,0,0,0.35)]", isNativeApp && "mobile-native-shell")} aria-label="Zerus mobile app">
        {!isNativeApp && <StatusBar />}
        {vault.status === "pick-vault" || (vault.status === "error" && vaultSetupOpen) ? (
          <VaultSetup
            nativeAvailable={isNativeApp}
            error={vault.error}
            onLocate={() => runVaultAction(locateMobileVault)} onDrive={(selection) => runVaultAction(() => openGoogleDriveVault(selection))}
            onCreateAtLocation={() => runVaultAction(createMobileVaultAtLocation)}
            onCreateOnDevice={() => runVaultAction(createMobileVaultOnDevice)}
          />
        ) : vault.status !== "ready" ? (
          <main className="flex min-h-0 flex-1 flex-col items-center justify-center px-8 text-center">
            {vault.status === "error" ? (
              <>
                <h1 className="text-xl font-semibold">Couldn’t open your notes</h1>
                <p className="mt-2 text-sm text-[#8e8e93]">{vault.error ?? "The mobile vault is unavailable."}</p>
                <Button className="mt-5" onClick={() => void reloadVault()}>Retry opening vault</Button>
                <Button variant="ghost" className="mt-2" onClick={() => setVaultSetupOpen(true)}>Choose another vault</Button>
              </>
            ) : (
              <>
                <Loader2 className="h-6 w-6 animate-spin text-[#df5149]" aria-hidden="true" />
                <p className="mt-3 text-sm text-[#8e8e93]">Opening your notes…</p>
              </>
            )}
          </main>
        ) : (
          <div className="relative min-h-0 flex-1 overflow-hidden">
            <div
              className="h-full overflow-y-auto pb-28"
              onTouchStart={handleNotesTouchStart}
              onTouchMove={handleNotesTouchMove}
              onTouchEnd={handleNotesTouchEnd}
              onTouchCancel={() => { notesSwipeStart.current = null; }}
            >
            <header className="sticky top-0 z-20 grid grid-cols-[44px_1fr_auto] items-center border-b border-zerus-text/[0.07] bg-zerus-editor/90 px-4 pb-3 pt-1 backdrop-blur-xl">
              <Button variant="ghost" size="icon" onClick={() => setLibraryOpen(true)} className="h-11 w-11 rounded-full bg-zerus-surface text-zerus-text hover:bg-zerus-text/10" aria-label="Open Zerus navigation"><Menu className="h-[21px] w-[21px]" /></Button>
              <div className="min-w-0 text-center"><h1 className="truncate text-[19px] font-semibold tracking-[-0.02em]">{scopeTitle}</h1><p className="mt-0.5 text-[14px] text-zerus-text/55">{scope.kind === "trash" ? libraryCounts.trash : filteredNotes.length} {scope.kind === "trash" ? (libraryCounts.trash === 1 ? "Item" : "Items") : scope.kind === "files" ? (filteredNotes.length === 1 ? "File" : "Files") : (filteredNotes.length === 1 ? "Note" : "Notes")}</p></div>
              {scope.kind === "trash" && libraryCounts.trash > 0 ? (
                <Button variant="ghost" onClick={() => setEmptyTrashConfirmOpen(true)} className="h-11 rounded-full px-3 text-[14px] font-semibold text-[#ff6961] hover:bg-[#363638] hover:text-[#ff6961]">Empty</Button>
              ) : (
                <Button variant="ghost" size="icon" onClick={() => setSettingsOpen(true)} className="h-11 w-11 rounded-full bg-zerus-surface text-zerus-text hover:bg-zerus-text/10" aria-label="Settings"><Settings className="h-[20px] w-[20px]" /></Button>
              )}
            </header>
            <main className="px-4 pb-8 pt-6">
              {query ? (
                <section><h2 className="mb-3 px-1 text-[24px] font-bold tracking-[-0.035em]">Search Results</h2>{filteredNotes.length > 0 ? <div className="overflow-hidden rounded-[18px] bg-[#222324] px-3">{filteredNotes.map((note) => <NoteCard key={note.id} note={note} onOpen={(openedNote) => openNote(openedNote.id)} />)}</div> : <div className="rounded-[18px] bg-[#222324] px-5 py-12 text-center"><Search className="mx-auto h-7 w-7 text-[#65625f]" /><p className="mt-3 text-[16px] font-semibold">No notes found</p><p className="mt-1 text-sm text-[#8e8a85]">Try a different search.</p></div>}</section>
              ) : (
                <div className="space-y-7">
                  {scope.kind === "trash" && vault.trashedImages.length > 0 && (
                    <section>
                      <h2 className="mb-3 px-1 text-[24px] font-bold tracking-[-0.035em]">Deleted Images</h2>
                      <div className="overflow-hidden rounded-[18px] bg-[#222324] px-3">
                        {vault.trashedImages.map((image) => (
                          <div key={image.id} className="flex items-center gap-3 border-b border-white/[0.065] px-1 py-3 last:border-b-0">
                            <button type="button" className="flex min-w-0 flex-1 items-center gap-3 text-left" onClick={() => void openImageInDefaultApp(image.trashPath)}>
                              <NoteCardImage path={image.trashPath} />
                              <span className="min-w-0 flex-1">
                                <span className="block truncate text-[15px] font-semibold">{image.name}</span>
                                <span className="mt-0.5 block text-xs text-[#8e8e93]">Image · Recently deleted</span>
                              </span>
                            </button>
                            <Button type="button" variant="ghost" size="icon" className="h-11 w-11 rounded-full bg-white/[0.07] text-[#ef6b62]" aria-label={`Restore ${image.name}`} onClick={() => void restoreTrashedImage(image.id)}><Undo2 className="h-5 w-5" /></Button>
                            <Button type="button" variant="ghost" size="icon" className="h-11 w-11 rounded-full text-[#ff6961]" aria-label={`Delete ${image.name} forever`} onClick={() => setDeleteImageTargetId(image.id)}><Trash2 className="h-5 w-5" /></Button>
                          </div>
                        ))}
                      </div>
                    </section>
                  )}
                  {pinnedNotes.length > 0 && <section><h2 className="mb-3 px-1 text-[24px] font-bold tracking-[-0.035em]">Pinned</h2><div className="overflow-hidden rounded-[18px] bg-[#222324] px-3">{pinnedNotes.map((note) => <NoteCard key={note.id} note={note} onOpen={(openedNote) => openNote(openedNote.id)} />)}</div></section>}
                  {recentNotes.length > 0 && <section><h2 className="mb-3 px-1 text-[24px] font-bold tracking-[-0.035em]">{scope.kind === "files" ? "Linked Files" : scope.kind === "external" ? "External Notes" : scope.kind === "trash" ? "Deleted Notes" : "Previous 30 Days"}</h2><div className="overflow-hidden rounded-[18px] bg-[#222324] px-3">{recentNotes.map((note) => <NoteCard key={note.id} note={note} onOpen={(openedNote) => openNote(openedNote.id)} />)}</div></section>}
                  {filteredNotes.length === 0 && (scope.kind !== "trash" || vault.trashedImages.length === 0) && <section className="rounded-[18px] bg-[#222324] px-5 py-12 text-center">
                    {scope.kind === "files" ? <FilePlus2 className="mx-auto h-7 w-7 text-[#65625f]" /> : scope.kind === "external" ? <ExternalLink className="mx-auto h-7 w-7 text-[#65625f]" /> : <FileText className="mx-auto h-7 w-7 text-[#65625f]" />}
                    <p className="mt-3 text-[16px] font-semibold">{scope.kind === "files" ? "No linked files" : scope.kind === "external" ? "No external notes" : "No notes here"}</p>
                    <p className="mt-1 text-sm text-[#8e8a85]">{scope.kind === "files" ? "Add any file and Zerus will keep its linked note in your vault." : scope.kind === "external" ? "Open a Markdown file without moving it into your vault." : "This section is empty."}</p>
                  </section>}
                  {vault.hasMoreNotes && <Button type="button" variant="ghost" disabled={vault.isLoadingMoreNotes} onClick={() => void loadMoreNotes()} className="mx-auto flex rounded-full bg-white/[0.06] px-5 text-sm text-[#aaa6a0] hover:bg-white/[0.1]">{vault.isLoadingMoreNotes ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}Load more notes</Button>}
                </div>
              )}
              </main>
            </div>
            {selectedNote && selectedSourceNote && (
              <div className="absolute inset-0 z-40 flex min-h-0 overflow-hidden">
                <NoteView
                  key={selectedSourceNote.id}
                  note={selectedSourceNote}
                  allNotes={vault.notes}
                  schemas={vault.schemas}
                  typeTree={typeTree}
                  onBack={() => window.history.back()}
                  onBodyChange={(body) =>
                    updateNoteBody(selectedNote.id, `# ${selectedNote.title}\n\n${body}`)
                  }
                  onRename={(title, body) =>
                    updateNoteBody(selectedNote.id, `# ${title}\n\n${body}`)
                  }
                  onOpenNote={(id) => openNote(id, noteOrigin)}
                  onOpenFile={(id, mode) => void openFileHub(id, mode)}
                  onChat={(nextScope) => openChat(nextScope)}
                />
              </div>
            )}
          </div>
        )}
        {vault.status === "ready" && !chatOpen && <BottomSearch query={query} onQueryChange={setQuery} onChat={() => openChat(
          scope.kind === "type"
            ? { kind: "type", path: scope.path }
            : scope.kind === "external" || scope.kind === "files" || scope.kind === "links"
              ? { kind: scope.kind }
              : { kind: "vault" },
        )} onCreate={scope.kind === "trash" ? undefined : () => void createForScope()} createLabel={scope.kind === "external" ? "Open an external note" : scope.kind === "files" ? "Add a linked file" : "Create a new note"} />}
        {libraryOpen && <LibraryDrawer counts={libraryCounts} typeTree={typeTree} typeIcons={vault.typeIcons} onClose={() => setLibraryOpen(false)} onSelect={selectScope} onCreateType={() => startTypeCreation()} onOpenTypeActions={setTypeActionTarget} />}
        {libraryOpen && typeActionTarget && (
          <TypeActionSheet
            target={typeActionTarget}
            onClose={() => setTypeActionTarget(null)}
            onMoveUp={() => moveType(typeActionTarget, "up")}
            onMoveDown={() => moveType(typeActionTarget, "down")}
            onChangeIcon={() => setIconTarget(typeActionTarget.node)}
            onAddSubtype={() => startTypeCreation(typeActionTarget.node.path)}
            onRename={() => startRename(typeActionTarget.node)}
            onDelete={() => setDeleteTarget(typeActionTarget.node)}
          />
        )}
        <TypeCreationDialog
          open={typeDraft !== null}
          parentPath={typeParentPath}
          draft={typeDraft ?? ""}
          onDraftChange={setTypeDraft}
          onOpenChange={(open) => { if (!open) closeTypeCreation(); }}
          onSubmit={(name) => void submitNewType(name)}
        />
        <IconPickerDialog
          open={iconTarget !== null}
          typeName={iconTarget?.name ?? ""}
          value={iconTarget ? vault.typeIcons[typeKey(iconTarget.path)] : undefined}
          onOpenChange={(open) => { if (!open) setIconTarget(null); }}
          onPick={(icon) => { if (iconTarget) setTypeIcon(iconTarget.path, icon); }}
        />
        <Dialog open={renameTarget !== null} onOpenChange={(open) => { if (!open) setRenameTarget(null); }}>
          <DialogContent>
            <DialogHeader><DialogTitle>Rename type "{renameTarget?.name}"</DialogTitle></DialogHeader>
            <form onSubmit={(event) => { event.preventDefault(); void submitRename(); }}>
              <Input autoFocus value={renameDraft} onChange={(event) => setRenameDraft(event.target.value)} placeholder="type (e.g. work/projects)" />
              <DialogFooter className="mt-4">
                <Button type="button" variant="outline" onClick={() => setRenameTarget(null)}>Cancel</Button>
                <Button type="submit">Rename</Button>
              </DialogFooter>
            </form>
          </DialogContent>
        </Dialog>
        <AlertDialog open={deleteTarget !== null} onOpenChange={(open) => { if (!open) setDeleteTarget(null); }}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Delete type "{deleteTarget?.name}"?</AlertDialogTitle>
              <AlertDialogDescription>
                {deleteTarget && deleteTarget.count > 0
                  ? `${deleteTarget.count} note${deleteTarget.count === 1 ? "" : "s"} in this type will be moved to Trash.`
                  : "This type has no notes."}
                {deleteTarget && deleteTarget.children.length > 0 && <> Its sub-types will be deleted too.</>}
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction className={buttonVariants({ variant: "destructive" })} onClick={() => void confirmDeleteType()}>Delete</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
        <AlertDialog open={emptyTrashConfirmOpen} onOpenChange={setEmptyTrashConfirmOpen}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Empty trash?</AlertDialogTitle>
              <AlertDialogDescription>
                {libraryCounts.trash} deleted {libraryCounts.trash === 1 ? "item" : "items"} will be permanently removed. This can’t be undone.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction className={buttonVariants({ variant: "destructive" })} onClick={() => void emptyTrash()}>Empty trash</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
        <AlertDialog open={deleteImageTargetId !== null} onOpenChange={(open) => !open && setDeleteImageTargetId(null)}>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Delete this image forever?</AlertDialogTitle>
              <AlertDialogDescription>This can’t be undone.</AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction className={buttonVariants({ variant: "destructive" })} onClick={() => { if (deleteImageTargetId) void deleteTrashedImageForever(deleteImageTargetId); }}>Delete forever</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
        <PersistentAIChat
          notes={vault.notes}
          notesReady={!vault.hasMoreNotes}
          notesPreparationError={notesPreparationError}
          onRetryNotesPreparation={() => void prepareAllNotes()}
          visible={chatOpen && !selectedNote}
          historyVisible={chatHistoryOpen}
          onClose={() => window.history.back()}
          onOpenHistory={() => {
            setChatHistoryOpen(true);
            pushNavigation({ view: "chat-history" });
          }}
          onCloseHistory={() => window.history.back()}
          onOpenNote={(noteId) => openNote(noteId, "chat")}
          scope={chatScope}
        />
        {settingsOpen && <MobileSettings location={vault.location} defaultNoteType={defaultNoteType} typeTree={typeTree} onDefaultNoteTypeChange={updateDefaultNoteType} onClose={() => setSettingsOpen(false)} onChangeVault={() => { setSettingsOpen(false); setVaultSetupOpen(true); }} />}
        {vault.status === "ready" && vaultSetupOpen && <VaultSetup nativeAvailable={isNativeApp} error={vault.error} onClose={() => setVaultSetupOpen(false)} onLocate={() => runVaultAction(locateMobileVault)} onDrive={(selection) => runVaultAction(() => openGoogleDriveVault(selection))} onCreateAtLocation={() => runVaultAction(createMobileVaultAtLocation)} onCreateOnDevice={() => runVaultAction(createMobileVaultOnDevice)} />}
        {vault.status === "ready" && vault.location?.startsWith("Google Drive ·") && Object.values(vault.conflicts)[0] && <DriveConflictReview conflict={Object.values(vault.conflicts)[0]} />}
        {composerOpen && (
          <Composer
            onClose={() => setComposerOpen(false)}
            onSave={saveQuickNote}
            typePath={creationType}
            typeIcon={vault.typeIcons[typeKey(creationType)]}
            allNotes={vault.notes}
            isNativeApp={isNativeApp}
          />
        )}
        {!isNativeApp && <div className="pointer-events-none absolute bottom-1.5 left-1/2 z-50 h-1 w-32 -translate-x-1/2 rounded-full bg-[#f5f3ef]" />}
      </section>
      <div className="pointer-events-none fixed bottom-5 right-6 hidden items-center gap-2 rounded-full bg-[#232323]/90 px-3 py-2 text-xs font-medium text-[#aaa6a0] shadow-sm backdrop-blur sm:flex"><FileText className="h-3.5 w-3.5" />Interactive iOS prototype</div>
    </div>
  );
}

function DriveConflictReview({ conflict }: { conflict: { noteId: string; currentContent: string; diskContent: string | null; diskPath: string } }) {
  const [busy, setBusy] = useState(false);
  const [review, setReview] = useState(false);
  const resolve = async (choice: "disk" | "current") => {
    setBusy(true);
    try { if (await resolveNoteConflict(conflict.noteId, choice)) setReview(false); }
    finally { setBusy(false); }
  };
  return <>
    <button type="button" onClick={() => setReview(true)} className="absolute inset-x-4 bottom-24 z-50 rounded-xl bg-[#59352f] p-3 text-sm text-white">A note changed in Google Drive. Review both versions.</button>
    <Dialog open={review} onOpenChange={setReview}>
      <DialogContent className="max-h-[85dvh] overflow-y-auto">
        <DialogHeader><DialogTitle>Review Google Drive changes</DialogTitle><DialogDescription>{conflict.diskPath}</DialogDescription></DialogHeader>
        <label className="text-sm">Your edit<textarea readOnly value={conflict.currentContent} className="mt-2 h-36 w-full rounded border bg-background p-2 text-xs" /></label>
        <label className="text-sm">Google Drive version<textarea readOnly value={conflict.diskContent ?? "This note is no longer in the vault."} className="mt-2 h-36 w-full rounded border bg-background p-2 text-xs" /></label>
        <p className="text-xs text-muted-foreground">Choosing a version replaces the other in Zerus. Copy any text you want to keep first.</p>
        <Button disabled={busy} onClick={() => void resolve("current")}>Save my version to Drive</Button>
        <Button disabled={busy} variant="outline" onClick={() => void resolve("disk")}>Use Google Drive version</Button>
      </DialogContent>
    </Dialog>
  </>;
}
