import {
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
  type TouchEvent as ReactTouchEvent,
} from "react";
import {
  ArrowLeft,
  ArrowDown,
  ArrowUp,
  ChevronRight,
  Cloud,
  ExternalLink,
  File,
  FilePlus2,
  FileText,
  Folder,
  FolderSearch,
  Loader2,
  Link2,
  Menu,
  MoreHorizontal,
  Pencil,
  Plus,
  Search,
  Settings,
  Smile,
  Smartphone,
  FolderPlus,
  Trash2,
  X,
} from "@/lib/icons";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
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
  DialogTitle,
} from "@/components/ui/dialog";
import { MarkdownEditor } from "@/components/editor/MarkdownEditor";
import { PropertiesSection } from "@/components/notes/PropertiesSection";
import { AddLinkDialog } from "@/components/notes/AddLinkDialog";
import { IconPickerDialog } from "@/components/notes/IconPickerDialog";
import { TypeIcon } from "@/components/notes/TypeIcon";
import { TypeCreationDialog } from "@/components/notes/TypeCreationDialog";
import { cn } from "@/lib/utils";
import { noteBody } from "@/lib/frontmatter";
import {
  DEFAULT_TYPE,
  MAX_TYPE_DEPTH,
  buildTypeTree,
  isExternalNote,
  noteSnippet,
  noteTitle,
  noteTypePath,
  parseTypePath,
  reorderTypeTree,
  typeKey,
  type Note,
  type TypeNode,
} from "@/lib/note-utils";
import { getFileHubReference } from "@/lib/file-hubs";
import { getLinkHubReference } from "@/lib/link-hubs";
import { openExternalUrl } from "@/lib/external-links";
import { filterNotes, type NoteFilter } from "@/lib/filters";
import {
  loadDefaultNoteType,
  loadNoteTypeOrder,
  saveDefaultNoteType,
  saveNoteTypeOrder,
} from "@/lib/note-preferences";
import { isTypeIconValue } from "@/lib/type-icons";
import { mobileNoteSwipeAction } from "./mobile-gestures";
import {
  createFileNote,
  createLinkNote,
  createNote,
  createMobileVaultAtLocation,
  createMobileVaultOnDevice,
  initStore,
  locateMobileVault,
  openExternalNotes,
  openFileHub,
  createType,
  deleteType,
  emptyTrash,
  renameType,
  setTypeIcon,
  updateNoteBody,
  useVault,
} from "@/store/notes-store";

interface MobileNote {
  id: string;
  title: string;
  preview: string;
  body: string;
  type: string;
  kind: "note" | "external" | "file" | "link";
  icon: string | null;
  fileName?: string;
  url?: string;
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
  const link = getLinkHubReference(note);
  const typePath = noteTypePath(note);
  const typeKey = typePath.join("/");
  const configuredIcon = typeIcons[typeKey] ?? typeIcons[typePath[0] ?? ""];
  const type = isExternalNote(note)
    ? "External Note"
    : typePath.join(" / ") || "Inbox";
  return {
    id: note.id,
    title: noteTitle(note),
    preview: file?.name ?? link?.url ?? (noteSnippet(note) || "Empty note"),
    body: editorBody(note),
    type,
    kind: file
      ? "file"
      : link
        ? "link"
        : isExternalNote(note)
          ? "external"
          : "note",
    icon: configuredIcon && isTypeIconValue(configuredIcon) ? configuredIcon : null,
    fileName: file?.name,
    url: link?.url,
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

function NoteCard({ note, onOpen }: NoteCardProps) {
  const icon = note.icon ? (
    <TypeIcon icon={note.icon} size={18} />
  ) : note.kind === "external" ? (
    <ExternalLink className="h-[18px] w-[18px]" />
  ) : note.kind === "file" ? (
    <File className="h-[18px] w-[18px]" />
  ) : note.kind === "link" ? (
    <Link2 className="h-[18px] w-[18px]" />
  ) : (
    <FileText className="h-[18px] w-[18px]" />
  );
  return (
    <button
      type="button"
      onClick={() => onOpen(note)}
      className="group w-full border-b border-white/[0.065] px-1 py-4 text-left transition last:border-b-0 active:bg-white/[0.035]"
    >
      <div className="flex items-start gap-3">
        <span className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-[11px] bg-white/[0.07] text-[#ef6b62]" aria-hidden="true">{icon}</span>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <h3 className="truncate text-[16px] font-semibold tracking-[-0.015em] text-[#f2efea]">{note.title}</h3>
            {note.pinned && <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-[#d84b40]" title="Pinned" />}
          </div>
          <p className="mt-1 line-clamp-2 text-[13px] leading-[1.4] text-[#9b9893]">{note.preview}</p>
          <div className="mt-2 flex items-center gap-2 text-[11px] font-medium text-[#74716d]">
            <span className="flex items-center gap-1 text-[#ef6b62]"><Folder className="h-3 w-3" />{note.type}</span><span>·</span><span>{note.updated}</span>
          </div>
        </div>
      </div>
    </button>
  );
}

interface BottomSearchProps {
  query: string;
  onQueryChange: (query: string) => void;
  onCreate?: () => void;
  createLabel?: string;
}

function BottomSearch({ query, onQueryChange, onCreate, createLabel = "Create a new note" }: BottomSearchProps) {
  return (
    <div className="mobile-bottom-search pointer-events-none absolute inset-x-0 bottom-0 z-30 flex items-center gap-2.5 bg-gradient-to-t from-[#1c1d1e] via-[#1c1d1e]/95 to-transparent px-5 pb-7 pt-8">
      <label className="pointer-events-auto relative min-w-0 flex-1">
        <span className="sr-only">Search notes</span>
        <Search className="absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-[#f2f2f7]" strokeWidth={2.1} />
        <Input
          value={query}
          onChange={(event) => onQueryChange(event.target.value)}
          placeholder="Search"
          className="h-[52px] rounded-[26px] border border-white/[0.10] bg-[#292a2b]/95 pl-12 pr-10 text-[17px] text-white shadow-[0_8px_28px_rgba(0,0,0,0.36)] backdrop-blur-xl placeholder:text-[#9b9893] focus-visible:ring-1 focus-visible:ring-[#d84b40]/70"
        />
        {query && (
          <button type="button" onClick={() => onQueryChange("")} className="absolute right-3.5 top-1/2 -translate-y-1/2 rounded-full bg-white/15 p-1 text-[#c8c8ce]" aria-label="Clear search">
            <X className="h-3 w-3" />
          </button>
        )}
      </label>
      {onCreate && <button type="button" onClick={onCreate} className="pointer-events-auto flex h-[52px] w-[52px] shrink-0 items-center justify-center rounded-full bg-[#df5149] text-white shadow-[0_8px_24px_rgba(223,81,73,0.34)] transition active:scale-95" aria-label={createLabel}>
        <Plus className="h-7 w-7" strokeWidth={2} />
      </button>}
    </div>
  );
}

interface LibraryDrawerProps {
  counts: { all: number; external: number; files: number; links: number; trash: number };
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
  const touchStart = useRef<{
    x: number;
    y: number;
    startedAt: number;
    axis: "horizontal" | "vertical" | null;
  } | null>(null);
  const suppressClick = useRef(false);

  useEffect(() => {
    if (!isClosing) return;
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const timer = window.setTimeout(onClose, reduceMotion ? 0 : 260);
    return () => window.clearTimeout(timer);
  }, [isClosing, onClose]);

  const closeWithAnimation = () => {
    touchStart.current = null;
    setIsDragging(false);
    setIsClosing(true);
    setSwipeOffset(-window.innerWidth);
  };

  const handleTouchStart = (event: ReactTouchEvent<HTMLDivElement>) => {
    const touch = event.touches[0];
    if (!touch || isClosing) return;
    touchStart.current = {
      x: touch.clientX,
      y: touch.clientY,
      startedAt: performance.now(),
      axis: null,
    };
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
    const elapsed = Math.max(performance.now() - start.startedAt, 1);
    const velocity = deltaX / elapsed;
    const closeDistance = Math.min(window.innerWidth * 0.22, 96);
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
    iconClass = "bg-[#df5149]",
  ) => (
    <button type="button" onClick={() => onSelect(scope)} className="flex min-h-[62px] w-full items-center gap-3 rounded-[13px] border-b border-white/[0.08] px-4 py-3 text-left last:border-b-0 active:bg-white/[0.05]">
      <span className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-[11px] text-white", iconClass)}>{icon}</span>
      <span className="flex-1 text-[16px] font-medium">{label}</span>
      <span className="text-sm text-[#98989f]">{count}</span><ChevronRight className="h-4 w-4 text-[#636366]" />
    </button>
  );
  return (
    <div
      className={cn("mobile-library-enter mobile-library-drawer absolute inset-0 z-40 flex min-h-0 flex-col bg-[#1c1c1e]", isDragging && "mobile-library-dragging")}
      role="dialog"
      aria-modal="true"
      aria-label="Zerus navigation"
      style={swipeOffset !== 0 || isClosing ? { transform: `translate3d(${swipeOffset}px, 0, 0)` } : undefined}
      onTouchStart={handleTouchStart}
      onTouchMove={handleTouchMove}
      onTouchEnd={(event) => handleTouchEnd(event)}
      onTouchCancel={(event) => handleTouchEnd(event, true)}
      onClickCapture={(event) => {
        if (!suppressClick.current) return;
        suppressClick.current = false;
        event.preventDefault();
        event.stopPropagation();
      }}
    >
      <header className="z-10 flex shrink-0 items-center justify-between border-b border-white/[0.06] bg-[#1c1c1e]/95 px-5 pb-4 pt-[max(2.75rem,env(safe-area-inset-top))] backdrop-blur-xl">
        <h2 className="text-[30px] font-bold tracking-[-0.04em]">Zerus</h2>
        <Button variant="ghost" size="icon" onClick={closeWithAnimation} className="h-10 w-10 rounded-full bg-white/[0.08] text-[#f5f5f7] hover:bg-white/[0.12]" aria-label="Close Zerus navigation"><X className="h-5 w-5" /></Button>
      </header>
      <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pb-[calc(env(safe-area-inset-bottom)+2rem)] pt-5 touch-pan-y" style={{ WebkitOverflowScrolling: "touch", touchAction: "pan-y" }}>
        <div className="rounded-[18px] bg-[#2c2c2e] p-1">
          {scopeRow("All Notes", counts.all, <FileText className="h-[18px] w-[18px]" />, { kind: "all" })}
          {scopeRow("External Notes", counts.external, <ExternalLink className="h-[18px] w-[18px]" />, { kind: "external" })}
          {scopeRow("Files", counts.files, <File className="h-[18px] w-[18px]" />, { kind: "files" })}
          {scopeRow("Links", counts.links, <Link2 className="h-[18px] w-[18px]" />, { kind: "links" })}
        </div>
        <div className="mb-2 mt-7 flex items-center justify-between px-1">
          <p className="text-[13px] font-semibold text-[#98989f]">Types</p>
          <button type="button" onClick={onCreateType} className="flex h-8 w-8 items-center justify-center rounded-full bg-white/[0.07] text-[#d4d4d8] active:bg-white/[0.12]" aria-label="Add type"><Plus className="h-4 w-4" /></button>
        </div>
        {typeTree.length > 0 ? <div className="rounded-[18px] bg-[#2c2c2e] p-1">
          {flattenTypes(typeTree).map((target) => (
            <div key={typeKey(target.node.path)} className="flex min-h-[62px] items-center border-b border-white/[0.08] last:border-b-0" style={{ paddingLeft: `${12 + target.depth * 18}px` }}>
              <button type="button" onClick={() => onSelect({ kind: "type", path: target.node.path })} className="flex min-w-0 flex-1 items-center gap-3 self-stretch rounded-[13px] text-left active:bg-white/[0.05]">
                <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[11px] bg-[#df5149] text-white"><TypeIcon icon={typeIcons[typeKey(target.node.path)]} size={20} /></span>
                <span className="min-w-0 flex-1 truncate text-[16px] font-medium">{target.node.name}</span>
              </button>
              <button type="button" onClick={() => onOpenTypeActions(target)} className="mr-1 flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-[#8e8e93] active:bg-white/[0.08]" aria-label={`Actions for ${target.node.name}`}><MoreHorizontal className="h-5 w-5" /></button>
            </div>
          ))}
        </div> : <p className="rounded-[14px] bg-[#2c2c2e] px-4 py-4 text-sm text-[#98989f]">No note types yet.</p>}
        <div className="mt-7 rounded-[18px] bg-[#2c2c2e] p-1">
          {scopeRow("Recently Deleted", counts.trash, <Trash2 className="h-[18px] w-[18px]" />, { kind: "trash" }, "bg-[#636366]")}
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

interface NoteViewProps {
  note: Note;
  allNotes: Note[];
  onBack: () => void;
  onBodyChange: (body: string) => void;
  onOpenNote: (id: string) => void;
  onOpenFile: (id: string) => void;
}

function NoteView({
  note,
  allNotes,
  onBack,
  onBodyChange,
  onOpenNote,
  onOpenFile,
}: NoteViewProps) {
  const presentedNote = presentNote(note);
  const file = getFileHubReference(note);
  const link = getLinkHubReference(note);
  const [draft, setDraft] = useState(presentedNote.body);
  const [propertiesOpen, setPropertiesOpen] = useState(false);
  const [dragX, setDragX] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const [isClosingNote, setIsClosingNote] = useState(false);
  const touchStart = useRef<{ x: number; y: number } | null>(null);
  const touchIntent = useRef<"pending" | "horizontal" | "vertical">("pending");
  const closeTimer = useRef<number | null>(null);

  useEffect(() => () => {
    if (closeTimer.current !== null) window.clearTimeout(closeTimer.current);
  }, []);

  const closeNote = () => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      onBack();
      return;
    }
    setIsClosingNote(true);
    closeTimer.current = window.setTimeout(onBack, 240);
  };

  const handleTouchStart = (event: ReactTouchEvent) => {
    const touch = event.touches[0];
    if (!touch) return;
    touchStart.current = { x: touch.clientX, y: touch.clientY };
    touchIntent.current = "pending";
    setIsDragging(false);
  };

  const handleTouchMove = (event: ReactTouchEvent) => {
    const start = touchStart.current;
    const touch = event.touches[0];
    if (!start || !touch || touchIntent.current === "vertical") return;

    const deltaX = touch.clientX - start.x;
    const deltaY = touch.clientY - start.y;
    if (touchIntent.current === "pending") {
      if (Math.hypot(deltaX, deltaY) < 7) return;
      touchIntent.current = Math.abs(deltaX) > Math.abs(deltaY) * 1.15
        ? "horizontal"
        : "vertical";
      if (touchIntent.current === "vertical") return;
      setIsDragging(true);
    }

    setDragX(propertiesOpen && deltaX < 0 ? deltaX * 0.12 : deltaX);
  };

  const handleTouchEnd = (event: ReactTouchEvent) => {
    const start = touchStart.current;
    const touch = event.changedTouches[0];
    const intent = touchIntent.current;
    touchStart.current = null;
    touchIntent.current = "pending";
    setIsDragging(false);
    if (!start || !touch || intent !== "horizontal") {
      setDragX(0);
      return;
    }

    const action = mobileNoteSwipeAction(
      start,
      { x: touch.clientX, y: touch.clientY },
      propertiesOpen,
    );
    if (action === "open-properties") setPropertiesOpen(true);
    if (action === "close-properties") setPropertiesOpen(false);
    if (action === "back") closeNote();
    setDragX(0);
  };

  const noteDrag = isClosingNote
    ? "100vw"
    : !propertiesOpen && dragX > 0
      ? `${dragX}px`
      : !propertiesOpen && dragX < 0
        ? `${Math.max(-24, dragX * 0.08)}px`
        : "0px";
  const propertiesDrag = propertiesOpen
    ? `${Math.max(0, dragX)}px`
    : `calc(100% + ${Math.min(0, dragX)}px)`;
  const transition = isDragging
    ? "none"
    : "transform 240ms cubic-bezier(0.22, 1, 0.36, 1)";

  return (
    <div
      className="mobile-note-page-enter relative flex min-h-0 flex-1 flex-col bg-[#1c1d1e]"
      onTouchStart={handleTouchStart}
      onTouchMove={handleTouchMove}
      onTouchEnd={handleTouchEnd}
      onTouchCancel={() => {
        touchStart.current = null;
        touchIntent.current = "pending";
        setIsDragging(false);
        setDragX(0);
      }}
      style={{
        transform: `translate3d(${noteDrag}, 0, 0)`,
        transition,
        touchAction: "pan-y",
        willChange: "transform",
      }}
    >
      <header className="relative z-20 grid h-[60px] shrink-0 grid-cols-[44px_1fr_44px] items-center px-4 pb-3 pt-1">
        <Button variant="ghost" size="icon" className="h-11 w-11 touch-manipulation rounded-full bg-[#f0efed] hover:bg-[#e9e7e3] dark:bg-white/[0.08] dark:text-[#f5f3ef] dark:hover:bg-white/[0.12]" onClick={closeNote} aria-label="Back to notes"><ArrowLeft className="h-5 w-5" /></Button>
        <span className="flex min-w-0 max-w-full items-center justify-center gap-1.5 justify-self-center text-[14px] font-medium leading-none text-[#99958f] dark:text-[#8b8883]">
          <TypeIcon icon={presentedNote.icon ?? undefined} size={16} className="shrink-0" />
          <span className="truncate">{presentedNote.type}</span>
        </span>
        <Button variant="ghost" size="icon" className="h-11 w-11 touch-manipulation rounded-full bg-[#f0efed] hover:bg-[#e9e7e3] dark:bg-white/[0.08] dark:text-[#f5f3ef] dark:hover:bg-white/[0.12]" onClick={() => setPropertiesOpen(true)} aria-label="View properties"><Link2 className="h-[18px] w-[18px]" /></Button>
      </header>
      <main className="flex min-h-0 flex-1 flex-col overflow-hidden px-6 pt-5">
        <div className="mb-4 flex items-center gap-2 text-xs font-medium text-[#77736f]"><span className="flex items-center gap-1 text-[#df5149]">{presentedNote.kind === "external" ? <ExternalLink className="h-3.5 w-3.5" /> : presentedNote.kind === "file" ? <File className="h-3.5 w-3.5" /> : presentedNote.kind === "link" ? <Link2 className="h-3.5 w-3.5" /> : <Folder className="h-3.5 w-3.5" />}{presentedNote.type}</span><span>·</span><span>Edited {presentedNote.updated} ago</span></div>
        <h1 className="text-[36px] font-bold leading-[1.06] tracking-[-0.045em] text-[#24221f] dark:text-[#f5f3ef]">{presentedNote.title}</h1>
        {file && <button type="button" onClick={() => onOpenFile(note.id)} className="mt-5 flex items-center gap-3 rounded-[14px] bg-[#292a2b] px-4 py-3.5 text-left active:bg-[#333436]">
          <span className="flex h-10 w-10 items-center justify-center rounded-[11px] bg-[#df5149] text-white"><File className="h-5 w-5" /></span>
          <span className="min-w-0 flex-1"><span className="block truncate text-sm font-semibold">{file.name}</span><span className="mt-0.5 block text-xs text-[#8e8e93]">Open with an app on this device</span></span>
          <ExternalLink className="h-4 w-4 text-[#77777d]" />
        </button>}
        {link && <button type="button" onClick={() => void openExternalUrl(link.url)} className="mt-5 flex items-center gap-3 rounded-[14px] bg-[#292a2b] px-4 py-3.5 text-left active:bg-[#333436]">
          <span className="flex h-10 w-10 items-center justify-center rounded-[11px] bg-[#df5149] text-white"><Link2 className="h-5 w-5" /></span>
          <span className="min-w-0 flex-1"><span className="block truncate text-sm font-semibold">{link.url}</span><span className="mt-0.5 block text-xs text-[#8e8e93]">Open in your browser</span></span>
          <ExternalLink className="h-4 w-4 text-[#77777d]" />
        </button>}
        <div className="mobile-note-editor -mx-6 mt-2 min-h-0 flex-1 overflow-hidden [&_[role=toolbar]]:hidden [&_.cm-content]:!px-6 [&_.cm-content]:!pb-28 [&_.cm-content]:!pt-3 [&_.cm-scroller]:overscroll-contain">
          <MarkdownEditor
            noteId={`mobile-${presentedNote.id}`}
            initialContent={draft}
            getLinkableTitles={() => []}
            isTitleResolved={() => false}
            onChange={(body) => {
              setDraft(body);
              onBodyChange(body);
            }}
            onFollowLink={() => undefined}
            autoFocus={false}
            placeholderText="Start writing…"
            firstLineIsTitle={false}
          />
        </div>
      </main>
      <div
          className={cn(
            "absolute inset-0 z-40 flex flex-col bg-[#1c1d1e] shadow-[-18px_0_42px_rgba(0,0,0,0.3)]",
            !propertiesOpen && !isDragging && "pointer-events-none",
          )}
          role="dialog"
          aria-modal="true"
          aria-label="Note properties"
          aria-hidden={!propertiesOpen}
          inert={!propertiesOpen && !isDragging}
          style={{
            transform: `translate3d(${propertiesDrag}, 0, 0)`,
            transition,
            touchAction: "pan-y",
            willChange: "transform",
          }}
        >
          <header className="flex h-12 shrink-0 items-center justify-end border-b border-white/[0.07] px-3">
            <Button variant="ghost" size="icon" className="h-9 w-9 rounded-full bg-white/[0.08] text-[#f5f3ef] hover:bg-white/[0.12]" onClick={() => setPropertiesOpen(false)} aria-label="Close properties"><X className="h-5 w-5" /></Button>
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
          </div>
        </div>
    </div>
  );
}

interface ComposerProps {
  onClose: () => void;
  onSave: (title: string, body: string) => void;
  typePath: string[];
}

function Composer({ onClose, onSave, typePath }: ComposerProps) {
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");

  return (
    <div className="mobile-composer-backdrop-enter absolute inset-0 z-40 flex items-end bg-black/20 backdrop-blur-[2px]" role="dialog" aria-modal="true" aria-label="New note">
      <div className="mobile-composer-sheet-enter flex h-[82%] w-full flex-col rounded-t-[28px] bg-[#fffefa] shadow-2xl dark:bg-[#1c1d1e]">
        <div className="mx-auto mt-2.5 h-1 w-10 rounded-full bg-[#d7d3cd] dark:bg-white/20" />
        <header className="flex items-center justify-between px-4 py-3">
          <Button variant="ghost" size="icon" className="rounded-full dark:text-[#f5f3ef]" onClick={onClose} aria-label="Close composer"><X className="h-5 w-5" /></Button>
          <span className="text-sm font-semibold tracking-[-0.01em]">New note</span>
          <Button variant="ghost" className="h-9 px-3 text-sm font-semibold text-[#d84b40] hover:text-[#d84b40]" disabled={!title.trim()} onClick={() => onSave(title.trim(), body)}>Save</Button>
        </header>
        <div className="min-h-0 flex-1 overflow-y-auto px-6 pt-3">
          <Input value={title} onChange={(event) => setTitle(event.target.value)} autoFocus placeholder="Note title" className="h-auto border-0 bg-transparent px-0 text-[36px] font-bold leading-[1.06] tracking-[-0.045em] shadow-none ring-offset-0 placeholder:text-[#c1bdb7] focus-visible:border-transparent focus-visible:ring-0 focus-visible:ring-offset-0 dark:text-[#f5f3ef] dark:placeholder:text-[#5e5b57] md:text-[36px]" />
          <div className="mobile-note-editor -mx-6 mb-5 mt-3 h-[320px] overflow-hidden [&_[role=toolbar]]:hidden [&_.cm-content]:!px-6 [&_.cm-content]:!pb-20 [&_.cm-content]:!pt-3 [&_.cm-scroller]:overscroll-contain">
            <MarkdownEditor
              noteId="mobile-new-note"
              initialContent={body}
              getLinkableTitles={() => []}
              isTitleResolved={() => false}
              onChange={setBody}
              onFollowLink={() => undefined}
              autoFocus={false}
              placeholderText="Start writing…"
              firstLineIsTitle={false}
            />
          </div>
        </div>
        <div className="flex items-center gap-2 border-t border-black/[0.06] px-5 pb-7 pt-3 text-xs text-[#77736d] dark:border-white/[0.06] dark:text-[#aaa6a0]"><Folder className="h-4 w-4 text-[#df5149]" /><span>Note Type: {typePath.join(" / ")}</span></div>
      </div>
    </div>
  );
}

interface MobileSettingsProps {
  location: string | null;
  onClose: () => void;
  onChangeVault: () => void;
}

function MobileSettings({
  location,
  onClose,
  onChangeVault,
}: MobileSettingsProps) {
  return (
    <div className="absolute inset-0 z-50 flex items-end bg-black/45 backdrop-blur-[2px]" role="dialog" aria-modal="true" aria-label="Mobile settings">
      <section className="w-full rounded-t-[28px] bg-[#1c1d1e] px-5 pb-[calc(env(safe-area-inset-bottom)+1.25rem)] pt-3 shadow-2xl">
        <div className="mx-auto h-1 w-10 rounded-full bg-white/20" />
        <header className="flex items-center justify-between py-4">
          <div>
            <h2 className="text-[22px] font-bold tracking-[-0.03em]">Settings</h2>
            <p className="mt-0.5 text-xs text-[#8e8e93]">Markdown vault</p>
          </div>
          <Button variant="ghost" size="icon" onClick={onClose} className="h-9 w-9 rounded-full bg-white/[0.08]" aria-label="Close settings"><X className="h-5 w-5" /></Button>
        </header>

        <p className="mb-2 text-xs font-semibold uppercase tracking-[0.08em] text-[#77777d]">Current vault</p>
        <div className="rounded-[16px] bg-[#292a2b] px-4 py-4">
          <div className="flex items-center gap-3">
            <span className="flex h-10 w-10 items-center justify-center rounded-[11px] bg-[#df5149] text-white"><Folder className="h-5 w-5" /></span>
            <span className="min-w-0 flex-1"><span className="block text-[15px] font-semibold">{location ?? "Zerus"}</span><span className="mt-0.5 block text-xs text-[#8e8e93]">Your Markdown vault</span></span>
          </div>
          <Button type="button" variant="ghost" onClick={onChangeVault} className="mt-4 h-10 w-full rounded-[12px] bg-white/[0.07] text-sm font-semibold text-[#ef6b62] hover:bg-white/[0.1] hover:text-[#ef6b62]">Change vault</Button>
        </div>
      </section>
    </div>
  );
}

interface VaultSetupProps {
  nativeAvailable: boolean;
  error: string | null;
  onClose?: () => void;
  onLocate: () => Promise<boolean>;
  onCreateAtLocation: () => Promise<boolean>;
  onCreateOnDevice: () => Promise<boolean>;
}

function VaultSetup({
  nativeAvailable,
  error,
  onClose,
  onLocate,
  onCreateAtLocation,
  onCreateOnDevice,
}: VaultSetupProps) {
  const [busyAction, setBusyAction] = useState<string | null>(null);

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
        <p className="mt-2 text-center text-xs leading-4 text-[#77777d]">Select the vault itself or a folder containing “Zerus.”</p>

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
  const [addLinkOpen, setAddLinkOpen] = useState(false);
  const [libraryOpen, setLibraryOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [emptyTrashConfirmOpen, setEmptyTrashConfirmOpen] = useState(false);
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
    setTypeOrder(loadNoteTypeOrder(vault.location));
    setDefaultNoteTypeState(loadDefaultNoteType(vault.location));
  }, [vault.location]);

  const selectedSourceNote = vault.notes.find((note) => note.id === selectedNoteId) ?? null;
  const selectedNote = selectedSourceNote
    ? presentNote(selectedSourceNote, vault.typeIcons)
    : null;
  const typeTree = useMemo(
    () => buildTypeTree(vault.notes, vault.extraTypes, typeOrder),
    [typeOrder, vault.extraTypes, vault.notes],
  );
  const creationType = useMemo(
    () => scope.kind === "type" ? scope.path : defaultNoteType,
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
        : scope.kind === "trash"
          ? "Recently Deleted"
          : scope.path.join(" / ");
  const filteredNotes = useMemo(() => {
    return filterNotes(vault.notes, scope, query).map((note) =>
      presentNote(note, vault.typeIcons),
    );
  }, [query, scope, vault.notes, vault.typeIcons]);
  const libraryCounts = useMemo(() => ({
    all: filterNotes(vault.notes, { kind: "all" }, "").length,
    external: filterNotes(vault.notes, { kind: "external" }, "").length,
    files: filterNotes(vault.notes, { kind: "files" }, "").length,
    links: filterNotes(vault.notes, { kind: "links" }, "").length,
    trash: filterNotes(vault.notes, { kind: "trash" }, "").length,
  }), [vault.notes]);

  const saveQuickNote = async (title: string, body: string) => {
    const content = `# ${title}\n\n${body.trim()}`;
    const note = await createNote(creationType, content);
    if (!note) return;
    setComposerOpen(false);
    setSelectedNoteId(note.id);
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
      if (ids[0]) setSelectedNoteId(ids[0]);
      return;
    }
    if (scope.kind === "files") {
      const note = await createFileNote(creationType);
      if (note) setSelectedNoteId(note.id);
      return;
    }
    if (scope.kind === "links") {
      setAddLinkOpen(true);
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
    <div className="dark flex min-h-screen items-center justify-center bg-[#0d0d0d] p-0 sm:p-8">
      <section className={cn("mobile-zerus-dark relative flex h-[100dvh] w-full max-w-[393px] flex-col overflow-hidden bg-[#1c1d1e] text-[#f5f3ef] sm:h-[852px] sm:rounded-[42px] sm:border-[7px] sm:border-[#080808] sm:shadow-[0_28px_70px_rgba(0,0,0,0.6)]", isNativeApp && "mobile-native-shell")} aria-label="Zerus iOS prototype">
        {!isNativeApp && <StatusBar />}
        {vault.status === "pick-vault" ? (
          <VaultSetup
            nativeAvailable={isNativeApp}
            error={vault.error}
            onLocate={() => runVaultAction(locateMobileVault)}
            onCreateAtLocation={() => runVaultAction(createMobileVaultAtLocation)}
            onCreateOnDevice={() => runVaultAction(createMobileVaultOnDevice)}
          />
        ) : vault.status !== "ready" ? (
          <main className="flex min-h-0 flex-1 flex-col items-center justify-center px-8 text-center">
            {vault.status === "error" ? (
              <>
                <h1 className="text-xl font-semibold">Couldn’t open your notes</h1>
                <p className="mt-2 text-sm text-[#8e8e93]">{vault.error ?? "The mobile vault is unavailable."}</p>
              </>
            ) : (
              <>
                <Loader2 className="h-6 w-6 animate-spin text-[#df5149]" aria-hidden="true" />
                <p className="mt-3 text-sm text-[#8e8e93]">Opening your notes…</p>
              </>
            )}
          </main>
        ) : selectedNote && selectedSourceNote ? (
          <NoteView
            key={selectedSourceNote.id}
            note={selectedSourceNote}
            allNotes={vault.notes}
            onBack={() => setSelectedNoteId(null)}
            onBodyChange={(body) =>
              updateNoteBody(selectedNote.id, `# ${selectedNote.title}\n\n${body}`)
            }
            onOpenNote={setSelectedNoteId}
            onOpenFile={(id) => void openFileHub(id)}
          />
        ) : (
          <div className="min-h-0 flex-1 overflow-y-auto pb-28">
            <header className="sticky top-0 z-20 grid grid-cols-[44px_1fr_auto] items-center border-b border-white/[0.07] bg-[#1c1d1e]/90 px-4 pb-3 pt-1 backdrop-blur-xl">
              <Button variant="ghost" size="icon" onClick={() => setLibraryOpen(true)} className="h-11 w-11 rounded-full bg-[#2c2c2e] text-[#f5f5f7] hover:bg-[#363638]" aria-label="Open Zerus navigation"><Menu className="h-[21px] w-[21px]" /></Button>
              <div className="min-w-0 text-center"><h1 className="truncate text-[19px] font-semibold tracking-[-0.02em]">{scopeTitle}</h1><p className="mt-0.5 text-[14px] text-[#8e8e93]">{filteredNotes.length} {scope.kind === "files" ? (filteredNotes.length === 1 ? "File" : "Files") : scope.kind === "links" ? (filteredNotes.length === 1 ? "Link" : "Links") : (filteredNotes.length === 1 ? "Note" : "Notes")}</p></div>
              {scope.kind === "trash" && libraryCounts.trash > 0 ? (
                <Button variant="ghost" onClick={() => setEmptyTrashConfirmOpen(true)} className="h-11 rounded-full px-3 text-[14px] font-semibold text-[#ff6961] hover:bg-[#363638] hover:text-[#ff6961]">Empty</Button>
              ) : (
                <Button variant="ghost" size="icon" onClick={() => setSettingsOpen(true)} className="h-11 w-11 rounded-full bg-[#2c2c2e] text-[#f5f5f7] hover:bg-[#363638]" aria-label="Settings"><Settings className="h-[20px] w-[20px]" /></Button>
              )}
            </header>
            <main className="px-4 pb-8 pt-6">
              {query ? (
                <section><h2 className="mb-3 px-1 text-[24px] font-bold tracking-[-0.035em]">Search Results</h2>{filteredNotes.length > 0 ? <div className="overflow-hidden rounded-[18px] bg-[#222324] px-3">{filteredNotes.map((note) => <NoteCard key={note.id} note={note} onOpen={(openedNote) => setSelectedNoteId(openedNote.id)} />)}</div> : <div className="rounded-[18px] bg-[#222324] px-5 py-12 text-center"><Search className="mx-auto h-7 w-7 text-[#65625f]" /><p className="mt-3 text-[16px] font-semibold">No notes found</p><p className="mt-1 text-sm text-[#8e8a85]">Try a different search.</p></div>}</section>
              ) : (
                <div className="space-y-7">
                  {pinnedNotes.length > 0 && <section><h2 className="mb-3 px-1 text-[24px] font-bold tracking-[-0.035em]">Pinned</h2><div className="overflow-hidden rounded-[18px] bg-[#222324] px-3">{pinnedNotes.map((note) => <NoteCard key={note.id} note={note} onOpen={(openedNote) => setSelectedNoteId(openedNote.id)} />)}</div></section>}
                  {recentNotes.length > 0 && <section><h2 className="mb-3 px-1 text-[24px] font-bold tracking-[-0.035em]">{scope.kind === "files" ? "Linked Files" : scope.kind === "links" ? "Saved Links" : scope.kind === "external" ? "External Notes" : scope.kind === "trash" ? "Deleted Notes" : "Previous 30 Days"}</h2><div className="overflow-hidden rounded-[18px] bg-[#222324] px-3">{recentNotes.map((note) => <NoteCard key={note.id} note={note} onOpen={(openedNote) => setSelectedNoteId(openedNote.id)} />)}</div></section>}
                  {filteredNotes.length === 0 && <section className="rounded-[18px] bg-[#222324] px-5 py-12 text-center">
                    {scope.kind === "files" ? <FilePlus2 className="mx-auto h-7 w-7 text-[#65625f]" /> : scope.kind === "links" ? <Link2 className="mx-auto h-7 w-7 text-[#65625f]" /> : scope.kind === "external" ? <ExternalLink className="mx-auto h-7 w-7 text-[#65625f]" /> : <FileText className="mx-auto h-7 w-7 text-[#65625f]" />}
                    <p className="mt-3 text-[16px] font-semibold">{scope.kind === "files" ? "No linked files" : scope.kind === "links" ? "No saved links" : scope.kind === "external" ? "No external notes" : "No notes here"}</p>
                    <p className="mt-1 text-sm text-[#8e8a85]">{scope.kind === "files" ? "Add any file and Zerus will keep its linked note in your vault." : scope.kind === "links" ? "Add a URL and Zerus will keep its linked note in your vault." : scope.kind === "external" ? "Open a Markdown file without moving it into your vault." : "This section is empty."}</p>
                  </section>}
                </div>
              )}
            </main>
          </div>
        )}
        {vault.status === "ready" && !selectedNote && <BottomSearch query={query} onQueryChange={setQuery} onCreate={scope.kind === "trash" ? undefined : () => void createForScope()} createLabel={scope.kind === "external" ? "Open an external note" : scope.kind === "files" ? "Add a linked file" : scope.kind === "links" ? "Add a link" : "Create a new note"} />}
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
                {libraryCounts.trash} deleted {libraryCounts.trash === 1 ? "note" : "notes"} will be permanently removed. This can’t be undone.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction className={buttonVariants({ variant: "destructive" })} onClick={() => void emptyTrash()}>Empty trash</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
        {settingsOpen && <MobileSettings location={vault.location} onClose={() => setSettingsOpen(false)} onChangeVault={() => { setSettingsOpen(false); setVaultSetupOpen(true); }} />}
        {vault.status === "ready" && vaultSetupOpen && <VaultSetup nativeAvailable={isNativeApp} error={vault.error} onClose={() => setVaultSetupOpen(false)} onLocate={() => runVaultAction(locateMobileVault)} onCreateAtLocation={() => runVaultAction(createMobileVaultAtLocation)} onCreateOnDevice={() => runVaultAction(createMobileVaultOnDevice)} />}
        {composerOpen && <Composer onClose={() => setComposerOpen(false)} onSave={saveQuickNote} typePath={creationType} />}
        <AddLinkDialog
          open={addLinkOpen}
          onOpenChange={setAddLinkOpen}
          onAdd={async (url) => {
            const note = await createLinkNote(creationType, url);
            if (note) setSelectedNoteId(note.id);
          }}
        />
        {!isNativeApp && <div className="pointer-events-none absolute bottom-1.5 left-1/2 z-50 h-1 w-32 -translate-x-1/2 rounded-full bg-[#f5f3ef]" />}
      </section>
      <div className="pointer-events-none fixed bottom-5 right-6 hidden items-center gap-2 rounded-full bg-[#232323]/90 px-3 py-2 text-xs font-medium text-[#aaa6a0] shadow-sm backdrop-blur sm:flex"><FileText className="h-3.5 w-3.5" />Interactive iOS prototype</div>
    </div>
  );
}
