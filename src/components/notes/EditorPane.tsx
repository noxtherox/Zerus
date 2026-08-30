import { useCallback, useEffect, useRef, useState } from "react";
import {
  Archive,
  ArchiveRestore,
  AlertTriangle,
  ArrowLeft,
  ArrowRight,
  Copy,
  Download,
  Ellipsis,
  FileSearch,
  FileUp,
  FolderSearch,
  History,
  Link2,
  Link2Off,
  Loader2,
  MapPin,
  Maximize,
  Minimize,
  Pin,
  RefreshCw,
  Search,
  Sparkles,
  Trash2,
  Undo2,
  X,
} from "@/lib/icons";
import { Button, buttonVariants } from "@/components/ui/button";
import {
  ToggleGroup,
  ToggleGroupItem,
} from "@/components/ui/toggle-group";
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
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { MarkdownEditor } from "@/components/editor/MdxMarkdownEditor";
import { FileHubPanel, type FileHubPreviewType } from "./FileHubPanel";
import { HtmlPreviewDialog } from "./HtmlPreviewDialog";
import { NoteExportDialog } from "./NoteExportDialog";
import { LinkHubPanel } from "./LinkHubPanel";
import {
  ResizableHandle,
  ResizablePanel,
  ResizablePanelGroup,
} from "@/components/ui/resizable";
import { ZerusLogo } from "@/components/ZerusLogo";
import { TypePicker } from "./TypePicker";
import { BacklinksPanel } from "./BacklinksPanel";
import { VersionHistoryPanel } from "./VersionHistoryPanel";
import { getBacklinksGroupedByType } from "@/lib/links";
import {
  type Note,
  findNoteByTitle,
  getAllTypePaths,
  isArchived,
  isExternalNote,
  isTrashed,
  noteAbsolutePath,
  noteTitle,
  noteTypePath,
} from "@/lib/note-utils";
import { noteBody } from "@/lib/frontmatter";
import { fileExtension, getFileHubReference } from "@/lib/file-hubs";
import { getLinkHubReference, withLinkMarkdown } from "@/lib/link-hubs";
import {
  formatAttachmentMarkdown,
  getNoteAttachments,
  isImageAttachmentPath,
} from "@/lib/note-attachments";
import type { PropertySchemas } from "@/lib/properties";
import type { TypeIcons } from "@/lib/type-icons";
import type { Task } from "@/lib/tasks";
import {
  type NoteConflict,
  closeExternalNote,
  attachFileToNote,
  addNoteAttachments,
  chooseDocumentFile,
  chooseAttachmentFiles,
  convertNoteAttachment,
  createNote,
  detachFileHub,
  getNotes,
  getFileHubStatus,
  locateFileHub,
  openNoteAttachment,
  readFileHubBytes,
  restoreNote,
  resolveNoteConflict,
  revealNoteInDesktop,
  revealNoteAttachment,
  setNoteType,
  toggleNotePinned,
  toggleNoteArchived,
  trashNote,
  updateNoteBody,
} from "@/store/notes-store";
import { cn } from "@/lib/utils";
import {
  fileManagerName,
  primaryModifierLabel,
} from "@/lib/desktop-platform";
import {
  loadFileHubExpandedSection,
  loadHtmlPreviewPreference,
  loadHtmlPreviewMode,
  loadPropertiesPanelKeepOpen,
  saveFileHubExpandedSection,
  saveHtmlPreviewMode,
  savePropertiesPanelKeepOpen,
  type FileHubExpandedSection,
  type HtmlPreviewMode,
} from "@/lib/note-preferences";
import {
  analyzeHtmlPreview,
  htmlPreviewFingerprint,
  htmlPreviewNeedsPermission,
  MAX_HTML_PREVIEW_BYTES,
  type HtmlPreviewAnalysis,
} from "@/lib/html-preview";

interface EditorPaneProps {
  note: Note | null;
  allNotes: Note[];
  tasks: Task[];
  /** Types that exist without notes — offered by the type picker too. */
  extraTypes: string[][];
  schemas: PropertySchemas;
  /** Custom icon per type key, shown in the type picker. */
  typeIcons: TypeIcons;
  vaultLocation: string | null;
  onOpenNote: (id: string) => void;
  onOpenTask: (id: string) => void;
  onCopyExternalToVault: (id: string, typePath: string[]) => void;
  onMoveExternalToVault: (id: string, typePath: string[]) => void;
  onMoveSavedLinkToVault: (id: string, typePath: string[]) => void;
  isBusy: boolean;
  isLoading: boolean;
  isRefreshing: boolean;
  isFocusMode: boolean;
  onToggleFocusMode: () => void;
  isDesktop: boolean;
  aiOpen: boolean;
  onToggleAi: () => void;
  conflict: NoteConflict | null;
  canNavigateBack: boolean;
  canNavigateForward: boolean;
  onNavigateBack: () => void;
  onNavigateForward: () => void;
}

interface NavigationControlsProps {
  canNavigateBack: boolean;
  canNavigateForward: boolean;
  onNavigateBack: () => void;
  onNavigateForward: () => void;
}

function NavigationControls({
  canNavigateBack,
  canNavigateForward,
  onNavigateBack,
  onNavigateForward,
}: NavigationControlsProps) {
  return (
    <div className="flex shrink-0 items-center gap-0.5" aria-label="Navigation history">
      <Button
        variant="ghost"
        size="icon"
        className="h-7 w-7"
        title="Go back"
        aria-label="Go back"
        disabled={!canNavigateBack}
        onClick={onNavigateBack}
      >
        <ArrowLeft size={15} />
      </Button>
      <Button
        variant="ghost"
        size="icon"
        className="h-7 w-7"
        title="Go forward"
        aria-label="Go forward"
        disabled={!canNavigateForward}
        onClick={onNavigateForward}
      >
        <ArrowRight size={15} />
      </Button>
    </div>
  );
}

interface EditorContextControlsProps {
  isDesktop: boolean;
  aiOpen: boolean;
  onToggleAi: () => void;
  isFocusMode: boolean;
  onToggleFocusMode: () => void;
}

function EditorContextControls({
  isDesktop,
  aiOpen,
  onToggleAi,
  isFocusMode,
  onToggleFocusMode,
}: EditorContextControlsProps) {
  return (
    <>
      {isDesktop && (
        <Button
          variant="ghost"
          size="sm"
          className={cn(
            "h-7 shrink-0 gap-1 px-2 text-xs",
            aiOpen && "bg-muted text-zerus-accent",
          )}
          title={aiOpen ? "Hide AI chat" : "Open AI chat"}
          aria-label={aiOpen ? "Hide AI chat" : "Open AI chat"}
          aria-pressed={aiOpen}
          onClick={onToggleAi}
        >
          <Sparkles size={15} />
          AI
        </Button>
      )}
      <Button
        variant="ghost"
        size="icon"
        className={cn(
          "h-7 w-7 shrink-0",
          isFocusMode && "bg-muted text-zerus-accent",
        )}
        title={isFocusMode ? "Collapse note" : "Expand note"}
        aria-label={isFocusMode ? "Collapse note" : "Expand note"}
        aria-pressed={isFocusMode}
        onClick={onToggleFocusMode}
      >
        {isFocusMode ? <Minimize size={15} /> : <Maximize size={15} />}
      </Button>
    </>
  );
}

type ExternalImportMode = "copy" | "move";

export function EditorPane({
  note,
  allNotes,
  tasks,
  extraTypes,
  schemas,
  typeIcons,
  vaultLocation,
  onOpenNote,
  onOpenTask,
  onCopyExternalToVault,
  onMoveExternalToVault,
  onMoveSavedLinkToVault,
  isBusy,
  isLoading,
  isRefreshing,
  isFocusMode,
  onToggleFocusMode,
  isDesktop,
  aiOpen,
  onToggleAi,
  conflict,
  canNavigateBack,
  canNavigateForward,
  onNavigateBack,
  onNavigateForward,
}: EditorPaneProps) {
  const [showBacklinks, setShowBacklinks] = useState(false);
  const [keepPropertiesOpen, setKeepPropertiesOpen] = useState(
    loadPropertiesPanelKeepOpen,
  );
  const [historyOpen, setHistoryOpen] = useState(false);
  const [externalImportMode, setExternalImportMode] =
    useState<ExternalImportMode>("copy");
  const [expandBacklinks, setExpandBacklinks] = useState(false);
  const [pathOpen, setPathOpen] = useState(false);
  const [closeExternalConfirmOpen, setCloseExternalConfirmOpen] =
    useState(false);
  const [trashConfirmOpen, setTrashConfirmOpen] = useState(false);
  const [findRequest, setFindRequest] = useState(0);
  const [conflictReviewOpen, setConflictReviewOpen] = useState(false);
  const [overwriteDiskConfirmOpen, setOverwriteDiskConfirmOpen] =
    useState(false);
  const [detachConfirmOpen, setDetachConfirmOpen] = useState(false);
  const [pendingAttachPath, setPendingAttachPath] = useState<string | null>(null);
  const [pendingNoteAttachments, setPendingNoteAttachments] = useState<{
    paths: string[];
    at?: number;
  } | null>(null);
  const [attachmentInsertRequest, setAttachmentInsertRequest] = useState<{
    id: number;
    text: string;
    at?: number;
  } | null>(null);
  const [fileHubExists, setFileHubExists] = useState<boolean | null>(null);
  const [expandedFileHubSection, setExpandedFileHubSection] = useState<{
    fileHubId: string;
    section: FileHubExpandedSection | null;
  } | null>(null);
  const [htmlPreviewState, setHtmlPreviewState] = useState<{
    fileHubId: string;
    mode: HtmlPreviewMode | null;
    analysis: HtmlPreviewAnalysis | null;
    fingerprint: string | null;
    error: string | null;
    approvalExpired: boolean;
  } | null>(null);
  const [htmlPreviewDialogOpen, setHtmlPreviewDialogOpen] = useState(false);
  const [exportDialogOpen, setExportDialogOpen] = useState(false);
  const activeFileHub = note ? getFileHubReference(note) : null;
  const activeFileHubId = activeFileHub?.id ?? null;
  const activeFileHubName = activeFileHub?.name ?? null;
  const activeNoteId = note?.id ?? null;
  const previousNoteIdRef = useRef(activeNoteId);
  const activeFileExtension = activeFileHub ? fileExtension(activeFileHub.name) : "";
  const activeFileIsHtml = ["html", "htm"].includes(activeFileExtension);
  const [editorReadyNoteId, setEditorReadyNoteId] = useState<string | null>(null);

  useEffect(() => {
    if (
      previousNoteIdRef.current !== activeNoteId &&
      !keepPropertiesOpen
    ) {
      setShowBacklinks(false);
    }
    previousNoteIdRef.current = activeNoteId;
  }, [activeNoteId, keepPropertiesOpen]);

  useEffect(() => {
    if (!activeNoteId || isLoading) {
      setEditorReadyNoteId(null);
      return;
    }

    // Let the loading state paint before mounting MDXEditor. Parsing a large
    // document is synchronous, so mounting it in the selection render would
    // otherwise make the app appear frozen with no visual feedback.
    const frame = window.requestAnimationFrame(() => {
      setEditorReadyNoteId(activeNoteId);
    });
    return () => window.cancelAnimationFrame(frame);
  }, [activeNoteId, isLoading]);

  useEffect(() => {
    setExternalImportMode("copy");
    setHistoryOpen(false);
    setPendingNoteAttachments(null);
    setAttachmentInsertRequest(null);
  }, [note?.id]);

  useEffect(() => {
    let cancelled = false;
    const refreshFileHubStatus = async () => {
      if (!note || !getFileHubReference(note)) {
        setFileHubExists(null);
        return;
      }
      const status = await getFileHubStatus(note.id);
      if (!cancelled) setFileHubExists(status?.exists ?? false);
    };
    void refreshFileHubStatus();
    const onFocus = () => void refreshFileHubStatus();
    window.addEventListener("focus", onFocus);
    return () => {
      cancelled = true;
      window.removeEventListener("focus", onFocus);
    };
  }, [note]);

  useEffect(() => {
    let cancelled = false;
    if (!activeNoteId || !activeFileHubId || !activeFileIsHtml) {
      setHtmlPreviewState(null);
      setHtmlPreviewDialogOpen(false);
      return;
    }

    const savedPreference = loadHtmlPreviewPreference(activeFileHubId);
    const savedMode = savedPreference?.mode ?? null;
    setHtmlPreviewState({
      fileHubId: activeFileHubId,
      mode: savedMode,
      analysis: null,
      fingerprint: savedPreference?.fingerprint ?? null,
      error: null,
      approvalExpired: false,
    });
    void readFileHubBytes(activeNoteId, MAX_HTML_PREVIEW_BYTES)
      .then(async (bytes) => {
        if (cancelled) return;
        const analysis = analyzeHtmlPreview(new TextDecoder("utf-8").decode(bytes));
        const fingerprint = await htmlPreviewFingerprint(bytes);
        if (cancelled) return;
        let mode = savedMode;
        if (
          mode === "full" &&
          savedPreference?.fingerprint !== fingerprint
        ) {
          mode = null;
        }
        if (!mode && !htmlPreviewNeedsPermission(analysis)) {
          mode = "safe";
          saveHtmlPreviewMode(activeFileHubId, mode);
        }
        setHtmlPreviewState({
          fileHubId: activeFileHubId,
          mode,
          analysis,
          fingerprint,
          error: null,
          approvalExpired:
            mode === null &&
            savedMode === "full" &&
            savedPreference?.fingerprint !== fingerprint,
        });
        if (!mode && htmlPreviewNeedsPermission(analysis)) {
          setHtmlPreviewDialogOpen(true);
        }
      })
      .catch((cause) => {
        if (cancelled) return;
        setHtmlPreviewState({
          fileHubId: activeFileHubId,
          mode: null,
          analysis: null,
          fingerprint: null,
          error: cause instanceof Error ? cause.message : String(cause),
          approvalExpired: false,
        });
        setHtmlPreviewDialogOpen(true);
      });
    return () => {
      cancelled = true;
    };
  }, [activeFileHubId, activeFileHubName, activeFileIsHtml, activeNoteId]);

  const expireHtmlFullPreview = useCallback((
    analysis: HtmlPreviewAnalysis,
    fingerprint: string,
  ) => {
    if (!activeFileHubId) return;
    setHtmlPreviewState({
      fileHubId: activeFileHubId,
      mode: null,
      analysis,
      fingerprint,
      error: null,
      approvalExpired: true,
    });
    setHtmlPreviewDialogOpen(true);
  }, [activeFileHubId]);

  if (!note) {
    return (
      <div className="flex h-full flex-col bg-zerus-editor">
        <div className="flex items-center gap-2 border-b border-border/60 px-4 py-2">
          <NavigationControls
            canNavigateBack={canNavigateBack}
            canNavigateForward={canNavigateForward}
            onNavigateBack={onNavigateBack}
            onNavigateForward={onNavigateForward}
          />
          <div className="flex-1" />
          <EditorContextControls
            isDesktop={isDesktop}
            aiOpen={aiOpen}
            onToggleAi={onToggleAi}
            isFocusMode={isFocusMode}
            onToggleFocusMode={onToggleFocusMode}
          />
        </div>
        <div className="flex min-h-0 flex-1 items-center justify-center">
          <div className="text-center text-muted-foreground">
            <ZerusLogo
              alt="Zerus"
              className="mx-auto h-16 w-16 rounded-xl"
            />
            <p className="mt-3 text-sm">
              Select a note, or press {primaryModifierLabel}N to create one.
            </p>
          </div>
        </div>
      </div>
    );
  }

  if (isLoading || editorReadyNoteId !== activeNoteId) {
    return (
      <div className="flex h-full flex-col bg-zerus-editor">
        <div className="flex items-center gap-2 border-b border-border/60 px-4 py-2">
          <NavigationControls
            canNavigateBack={canNavigateBack}
            canNavigateForward={canNavigateForward}
            onNavigateBack={onNavigateBack}
            onNavigateForward={onNavigateForward}
          />
          <div className="flex-1" />
          <EditorContextControls
            isDesktop={isDesktop}
            aiOpen={aiOpen}
            onToggleAi={onToggleAi}
            isFocusMode={isFocusMode}
            onToggleFocusMode={onToggleFocusMode}
          />
        </div>
        <div className="flex min-h-0 flex-1 items-center justify-center">
          <div
            className="flex items-center gap-2 text-sm text-muted-foreground"
            role="status"
            aria-live="polite"
          >
            <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
            Loading note…
          </div>
        </div>
      </div>
    );
  }

  const external = isExternalNote(note);
  const archived = isArchived(note);
  const trashed = isTrashed(note);
  const linkHub = getLinkHubReference(note);
  const absolutePath = noteAbsolutePath(note, vaultLocation);
  const backlinkCount = external || linkHub
    ? 0
    : [...getBacklinksGroupedByType(note, allNotes, schemas).values()].reduce(
        (sum, group) => sum + group.length,
        0,
      );

  const handleFollowLink = async (title: string) => {
    if (isRefreshing) return;
    // Read the freshest notes — the store may be ahead of this render
    const existing = findNoteByTitle(title, getNotes());
    if (existing) {
      onOpenNote(existing.id);
      return;
    }
    const created = await createNote(noteTypePath(note), `# ${title}\n\n`);
    if (created) onOpenNote(created.id);
  };

  const startFileHubAttach = async () => {
    const path = await chooseDocumentFile();
    if (!path) return;
    const result = await attachFileToNote(note.id, path, "auto");
    if (result.status === "duplicate") onOpenNote(result.noteId);
    if (result.status === "needs-choice") setPendingAttachPath(result.path);
  };

  const copyFileHubIntoVault = async () => {
    const status = await getFileHubStatus(note.id);
    const path = status?.resolved.absolutePath;
    if (!path) return;
    await attachFileToNote(note.id, path, "copy");
  };

  const queueNoteAttachments = (paths: string[], at?: number) => {
    const supported = paths.filter((path) => !isImageAttachmentPath(path));
    if (supported.length) setPendingNoteAttachments({ paths: supported, at });
  };

  const requestNoteAttachments = async () => {
    queueNoteAttachments(await chooseAttachmentFiles());
  };

  const confirmNoteAttachments = async (mode: "copy" | "external") => {
    const pending = pendingNoteAttachments;
    if (!pending) return;
    setPendingNoteAttachments(null);
    const added = await addNoteAttachments(note.id, pending.paths, mode);
    if (!added.length) return;
    const text = added.map(formatAttachmentMarkdown).join("\n");
    setAttachmentInsertRequest((current) => ({
      id: (current?.id ?? 0) + 1,
      text,
      ...(pending.at === undefined ? {} : { at: pending.at }),
    }));
    setHistoryOpen(false);
    setShowBacklinks(true);
  };

  const handleAttachmentAction = (
    attachmentId: string,
    action: "open" | "reveal" | "copy" | "external",
  ) => {
    if (action === "open") {
      void openNoteAttachment(note.id, attachmentId);
    } else if (action === "reveal") {
      void revealNoteAttachment(note.id, attachmentId);
    } else {
      void convertNoteAttachment(note.id, attachmentId, action);
    }
  };

  const fileHub = activeFileHub;
  const linkedFileType = fileHub
    ? fileExtension(fileHub.name).toUpperCase() || "FILE"
    : "FILE";
  const extension = activeFileExtension;
  const htmlPreviewMode = fileHub && activeFileIsHtml
    ? htmlPreviewState?.fileHubId === fileHub.id
      ? htmlPreviewState.mode
      : loadHtmlPreviewMode(fileHub.id)
    : null;
  const renderedHtmlPreviewMode =
    htmlPreviewMode === "safe" || htmlPreviewMode === "full"
      ? htmlPreviewMode
      : null;
  const previewType: FileHubPreviewType =
    extension === "pdf" ? "pdf" : renderedHtmlPreviewMode ? "html" : null;
  const expandedSection = fileHub
    ? expandedFileHubSection?.fileHubId === fileHub.id
      ? expandedFileHubSection.section
      : loadFileHubExpandedSection(fileHub.id)
    : null;
  const toggleExpandedSection = (section: FileHubExpandedSection) => {
    if (!fileHub) return;
    const next = expandedSection === section ? null : section;
    saveFileHubExpandedSection(fileHub.id, next);
    setExpandedFileHubSection({ fileHubId: fileHub.id, section: next });
  };
  const chooseHtmlPreviewMode = (mode: HtmlPreviewMode) => {
    if (!fileHub || !activeFileIsHtml) return;
    const current = htmlPreviewState?.fileHubId === fileHub.id
      ? htmlPreviewState
      : null;
    if (mode === "full" && !current?.fingerprint) return;
    saveHtmlPreviewMode(fileHub.id, mode, current?.fingerprint ?? null);
    setHtmlPreviewState((current) => ({
      fileHubId: fileHub.id,
      mode,
      analysis: current?.fileHubId === fileHub.id ? current.analysis : null,
      fingerprint: current?.fileHubId === fileHub.id ? current.fingerprint : null,
      error: null,
      approvalExpired: false,
    }));
    setHtmlPreviewDialogOpen(false);
  };
  const setHtmlPreviewDialogVisibility = (open: boolean) => {
    if (!open && !htmlPreviewMode) {
      chooseHtmlPreviewMode("link");
      return;
    }
    setHtmlPreviewDialogOpen(open);
  };
  const backlinksPanel = !external && !linkHub && showBacklinks ? (
    <BacklinksPanel
      note={note}
      allNotes={allNotes}
      tasks={tasks}
      schemas={schemas}
      onOpenNote={onOpenNote}
      onOpenTask={onOpenTask}
      expanded={expandBacklinks}
      onToggleExpanded={() => setExpandBacklinks((open) => !open)}
      keepOpen={keepPropertiesOpen}
      onKeepOpenChange={(keepOpen) => {
        setKeepPropertiesOpen(keepOpen);
        savePropertiesPanelKeepOpen(keepOpen);
      }}
    />
  ) : null;
  const editorContent = (
    <div className="flex h-full min-h-0 flex-1">
      <div
        className={cn(
          "h-full min-h-0 min-w-0 flex-1",
          showBacklinks && expandBacklinks && "hidden",
        )}
      >
        <MarkdownEditor
          noteId={note.id}
          initialContent={
            linkHub
              ? withLinkMarkdown(noteBody(note.content), linkHub.url)
              : noteBody(note.content)
          }
          getLinkableTitles={() =>
            getNotes()
              .filter(
                (other) =>
                  !isExternalNote(other) &&
                  !isTrashed(other) &&
                  other.id !== note.id,
              )
              .map((other) => noteTitle(other))
          }
          isTitleResolved={(title) => !!findNoteByTitle(title, getNotes())}
          onChange={(body) => updateNoteBody(note.id, body)}
          onFollowLink={(title) => void handleFollowLink(title)}
          readOnly={isBusy}
          isFullHeight={expandedSection === "markdown"}
          onToggleFullHeight={
            previewType ? () => toggleExpandedSection("markdown") : undefined
          }
          findRequest={findRequest}
          insertTextRequest={attachmentInsertRequest}
          attachments={getNoteAttachments(note)}
          onAttachmentAction={handleAttachmentAction}
          onAttachmentDrop={
            !external && !trashed && !linkHub
              ? (paths, at) => queueNoteAttachments(paths, at)
              : undefined
          }
          onRequestAttachments={
            !external && !trashed && !linkHub
              ? () => void requestNoteAttachments()
              : undefined
          }
        />
      </div>
      {!previewType && backlinksPanel}
      {!external && historyOpen && (
        <VersionHistoryPanel note={note} onClose={() => setHistoryOpen(false)} />
      )}
    </div>
  );

  return (
    <div className="flex h-full flex-col bg-zerus-editor">
      <div
        className={cn(
          "relative z-20 flex items-center gap-2 border-b border-border/60 bg-zerus-editor px-4 py-2",
          isRefreshing && "pointer-events-none opacity-70",
        )}
      >
        <NavigationControls
          canNavigateBack={canNavigateBack}
          canNavigateForward={canNavigateForward}
          onNavigateBack={onNavigateBack}
          onNavigateForward={onNavigateForward}
        />
        {external ? (
          <>
            <ToggleGroup
              type="single"
              value={externalImportMode}
              onValueChange={(mode: ExternalImportMode) =>
                mode && setExternalImportMode(mode)
              }
              disabled={isBusy}
              aria-label="Choose whether to copy or move the external note"
              className="gap-0"
            >
              <ToggleGroupItem
                value="copy"
                aria-label="Copy external note"
                className="h-7 rounded-r-none border border-zerus-accent/35 px-2 text-xs data-[state=on]:bg-zerus-accent/10 data-[state=on]:text-zerus-accent"
              >
                Copy
              </ToggleGroupItem>
              <ToggleGroupItem
                value="move"
                aria-label="Move external note"
                className="h-7 rounded-l-none border border-l-0 border-zerus-accent/35 px-2 text-xs data-[state=on]:bg-zerus-accent/10 data-[state=on]:text-zerus-accent"
              >
                Move
              </ToggleGroupItem>
            </ToggleGroup>
            <TypePicker
              value={[]}
              existingTypePaths={getAllTypePaths(allNotes, extraTypes)}
              typeIcons={typeIcons}
              label="Choose type…"
              title={`${externalImportMode === "copy" ? "Copy" : "Move"} this file into the vault and assign its type`}
              onChange={(typePath) =>
                externalImportMode === "copy"
                  ? onCopyExternalToVault(note.id, typePath)
                  : onMoveExternalToVault(note.id, typePath)
              }
              disabled={isBusy}
            />
            <div
              className="min-w-0 flex-1 truncate text-xs text-muted-foreground"
              title={absolutePath ?? undefined}
            >
              {absolutePath}
            </div>
            <Button
              variant="ghost"
              size="sm"
              className="h-7 gap-1.5 text-xs"
              title="View note path"
              onClick={() => setPathOpen(true)}
            >
              <MapPin size={14} /> Path
            </Button>
            <Button
              variant="ghost"
              size="sm"
              className="h-7 gap-1.5 text-xs"
              title={`Reveal in ${fileManagerName}`}
              onClick={() => void revealNoteInDesktop(note.id)}
            >
              <FolderSearch size={14} /> Reveal
            </Button>
            <Button
              variant="ghost"
              size="sm"
              className="h-7 gap-1.5 text-xs"
              title="Close note without deleting the file"
              onClick={() => setCloseExternalConfirmOpen(true)}
              disabled={isBusy}
            >
              <X size={14} /> Close
            </Button>
          </>
        ) : linkHub ? (
          <>
            <TypePicker
              value={[]}
              existingTypePaths={getAllTypePaths(allNotes, extraTypes)}
              typeIcons={typeIcons}
              label="Move to vault…"
              title="Convert this saved link into a vault note and assign its type"
              onChange={(typePath) =>
                onMoveSavedLinkToVault(note.id, typePath)
              }
              disabled={isBusy}
            />
            <div className="flex-1" />
          </>
        ) : (
          <>
            <TypePicker
              value={noteTypePath(note)}
              existingTypePaths={getAllTypePaths(allNotes, extraTypes)}
              typeIcons={typeIcons}
              onChange={(typePath) => void setNoteType(note.id, typePath)}
            />
            <div className="flex-1" />
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-7 w-7"
                  title="Note actions"
                  aria-label="Note actions"
                >
                  <Ellipsis size={16} />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-48">
                <DropdownMenuItem
                  onSelect={() => setFindRequest((request) => request + 1)}
                >
                  <Search className="mr-2" size={14} />
                  Find in note
                </DropdownMenuItem>
                <DropdownMenuItem
                  onSelect={() => {
                    setShowBacklinks(false);
                    setHistoryOpen(true);
                  }}
                >
                  <History className="mr-2" size={14} />
                  Version history
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  onSelect={() => void revealNoteInDesktop(note.id)}
                >
                  <FolderSearch className="mr-2" size={14} />
                  Reveal in {fileManagerName}
                </DropdownMenuItem>
                {!trashed && (
                  <DropdownMenuItem onSelect={() => setExportDialogOpen(true)}>
                    <Download className="mr-2" size={14} />
                    Export…
                  </DropdownMenuItem>
                )}
                {fileHub && (
                  <>
                    <DropdownMenuSeparator />
                    <DropdownMenuLabel>File type actions</DropdownMenuLabel>
                    {fileHubExists === false && (
                      <DropdownMenuItem
                        onSelect={() => void locateFileHub(note.id)}
                      >
                        <MapPin className="mr-2" size={14} />
                        Locate
                      </DropdownMenuItem>
                    )}
                    {!fileHub.managed && fileHub.kind !== "vault" && fileHubExists && (
                      <DropdownMenuItem
                        onSelect={() => void copyFileHubIntoVault()}
                      >
                        <Copy className="mr-2" size={14} />
                        Copy into Vault
                      </DropdownMenuItem>
                    )}
                    {activeFileIsHtml && (
                      <DropdownMenuItem onSelect={() => setHtmlPreviewDialogOpen(true)}>
                        <FileSearch className="mr-2" size={14} />
                        Change file preview
                      </DropdownMenuItem>
                    )}
                    <DropdownMenuItem onSelect={() => void startFileHubAttach()}>
                      <RefreshCw className="mr-2" size={14} />
                      Replace linked {linkedFileType}
                    </DropdownMenuItem>
                    <DropdownMenuItem onSelect={() => setDetachConfirmOpen(true)}>
                      <Link2Off className="mr-2" size={14} />
                      Detach {linkedFileType} from note
                    </DropdownMenuItem>
                  </>
                )}
                {!fileHub && !trashed && (
                  <DropdownMenuItem onSelect={() => void startFileHubAttach()}>
                    <FileUp className="mr-2" size={14} />
                    Attach file to note
                  </DropdownMenuItem>
                )}
                <DropdownMenuSeparator />
                {trashed ? (
                  <DropdownMenuItem
                    onSelect={() => void restoreNote(note.id)}
                  >
                    <Undo2 className="mr-2" size={14} />
                    Restore
                  </DropdownMenuItem>
                ) : (
                  <>
                    <DropdownMenuItem
                      onSelect={() => toggleNoteArchived(note.id)}
                    >
                      {archived ? (
                        <ArchiveRestore className="mr-2" size={14} />
                      ) : (
                        <Archive className="mr-2" size={14} />
                      )}
                      {archived ? "Unarchive" : "Archive"}
                    </DropdownMenuItem>
                    <DropdownMenuItem
                      onSelect={() => toggleNotePinned(note.id)}
                    >
                      <Pin
                        className={cn(
                          "mr-2",
                          note.pinned && "text-zerus-accent",
                        )}
                        size={14}
                      />
                      {note.pinned ? "Unpin" : "Pin"}
                    </DropdownMenuItem>
                    <DropdownMenuItem
                      className="text-destructive focus:text-destructive"
                      disabled={isBusy}
                      onSelect={() => setTrashConfirmOpen(true)}
                    >
                      <Trash2 className="mr-2" size={14} />
                      Move to trash
                    </DropdownMenuItem>
                  </>
                )}
              </DropdownMenuContent>
            </DropdownMenu>
            <Button
              variant="ghost"
              size="icon"
              className={cn(
                "relative h-7 w-7",
                showBacklinks && "bg-muted text-zerus-accent",
              )}
              title="properties and backlinks"
              onClick={() => {
                setHistoryOpen(false);
                setShowBacklinks((open) => !open);
              }}
            >
              <Link2 size={15} />
              {backlinkCount > 0 && (
                <span className="absolute -right-0.5 -top-0.5 flex h-3.5 min-w-3.5 items-center justify-center rounded-full bg-zerus-accent px-0.5 text-[9px] font-semibold leading-none text-white tabular-nums">
                  {backlinkCount}
                </span>
              )}
            </Button>
          </>
        )}
        <EditorContextControls
          isDesktop={isDesktop}
          aiOpen={aiOpen}
          onToggleAi={onToggleAi}
          isFocusMode={isFocusMode}
          onToggleFocusMode={onToggleFocusMode}
        />
      </div>
      {trashed && (
        <div
          className="flex shrink-0 items-center gap-2 border-b border-amber-500/30 bg-amber-500/10 px-4 py-2 text-xs"
          role="status"
        >
          <Trash2 className="shrink-0 text-amber-600" size={16} />
          <span className="min-w-0 flex-1 font-medium">
            This note is in Trash.
          </span>
          <Button
            variant="outline"
            size="sm"
            className="h-7 shrink-0 gap-1.5 text-xs"
            disabled={isBusy}
            onClick={() => void restoreNote(note.id)}
          >
            <Undo2 size={14} />
            Restore
          </Button>
        </div>
      )}
      {archived && !trashed && (
        <div
          className="flex shrink-0 items-center gap-2 border-b border-zerus-accent/30 bg-zerus-accent/10 px-4 py-2 text-xs"
          role="status"
        >
          <Archive className="shrink-0 text-zerus-accent" size={16} />
          <span className="min-w-0 flex-1 font-medium">
            This note is archived.
          </span>
          <Button
            variant="outline"
            size="sm"
            className="h-7 shrink-0 gap-1.5 text-xs"
            disabled={isBusy}
            onClick={() => toggleNoteArchived(note.id)}
          >
            <ArchiveRestore size={14} />
            Unarchive
          </Button>
        </div>
      )}
      {conflict && (
        <div className="flex shrink-0 items-center gap-2 border-b border-amber-500/30 bg-amber-500/10 px-4 py-2 text-xs">
          <AlertTriangle className="shrink-0 text-amber-600" size={16} />
          <span className="min-w-0 flex-1">
            {conflict.kind === "deleted"
              ? "This note was deleted on disk while you have unsaved changes in Zerus."
              : "This note changed on disk while you have unsaved changes in Zerus."}
          </span>
          <Button
            variant="outline"
            size="sm"
            className="h-7 shrink-0 text-xs"
            onClick={() => setConflictReviewOpen(true)}
          >
            Review both versions
          </Button>
          <Button
            variant="outline"
            size="sm"
            className="h-7 shrink-0 text-xs"
            onClick={() => void resolveNoteConflict(note.id, "disk")}
          >
            Load disk changes
          </Button>
          <Button
            variant="destructive"
            size="sm"
            className="h-7 shrink-0 text-xs"
            onClick={() => setOverwriteDiskConfirmOpen(true)}
          >
            Save current note over disk
          </Button>
        </div>
      )}
      {fileHub ? (
        previewType ? (
          <div className="flex min-h-0 flex-1">
            <ResizablePanelGroup
              direction="vertical"
              className={cn(
                "min-h-0 min-w-0 flex-1",
                showBacklinks && expandBacklinks && "hidden",
              )}
            >
              <ResizablePanel
                defaultSize={58}
                minSize={20}
                collapsible
                collapsedSize={8}
                className={expandedSection === "markdown" ? "hidden" : undefined}
              >
                <FileHubPanel
                  note={note}
                  previewType={previewType}
                  htmlPreviewMode={renderedHtmlPreviewMode ?? "safe"}
                  htmlApprovedFingerprint={
                    htmlPreviewState?.fileHubId === fileHub.id
                      ? htmlPreviewState.fingerprint
                      : loadHtmlPreviewPreference(fileHub.id)?.fingerprint ?? null
                  }
                  onHtmlApprovalExpired={expireHtmlFullPreview}
                  isPreviewFullHeight={expandedSection === "preview"}
                  onTogglePreviewFullHeight={() => toggleExpandedSection("preview")}
                />
              </ResizablePanel>
              <ResizableHandle
                withHandle
                className={expandedSection ? "hidden" : undefined}
              />
              <ResizablePanel
                defaultSize={42}
                minSize={20}
                className={expandedSection === "preview" ? "hidden" : undefined}
              >
                {editorContent}
              </ResizablePanel>
            </ResizablePanelGroup>
            {backlinksPanel}
          </div>
        ) : (
          <div className="flex min-h-0 flex-1 flex-col">
            <div className="shrink-0">
              <FileHubPanel note={note} previewType={null} />
            </div>
            {editorContent}
          </div>
        )
      ) : linkHub ? (
        <div className="flex min-h-0 flex-1 flex-col">
          <LinkHubPanel note={note} />
          {editorContent}
        </div>
      ) : (
        editorContent
      )}
      <Dialog open={external && pathOpen} onOpenChange={setPathOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>External note path</DialogTitle>
          </DialogHeader>
          <code className="select-all break-all rounded-md bg-muted px-3 py-2 text-xs">
            {absolutePath}
          </code>
        </DialogContent>
      </Dialog>
      <AlertDialog
        open={external && closeExternalConfirmOpen}
        onOpenChange={setCloseExternalConfirmOpen}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Close “{noteTitle(note)}”?
            </AlertDialogTitle>
            <AlertDialogDescription>
              Zerus will stop tracking this external note. The file will be
              saved and left in its current location.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => void closeExternalNote(note.id)}>
              Close note
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <AlertDialog open={detachConfirmOpen} onOpenChange={setDetachConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Detach “{fileHub?.name ?? "this file"}” from this note?</AlertDialogTitle>
            <AlertDialogDescription>
              This removes the file link and preview from the note. The file itself will not be deleted or moved.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => detachFileHub(note.id)}>
              Detach file
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      {fileHub && activeFileIsHtml && (
        <HtmlPreviewDialog
          open={htmlPreviewDialogOpen}
          onOpenChange={setHtmlPreviewDialogVisibility}
          fileName={fileHub.name}
          analysis={
            htmlPreviewState?.fileHubId === fileHub.id
              ? htmlPreviewState.analysis
              : null
          }
          currentMode={htmlPreviewMode}
          onChoose={chooseHtmlPreviewMode}
          unavailableReason={
            htmlPreviewState?.fileHubId === fileHub.id
              ? htmlPreviewState.error
              : null
          }
          fullPreviewReady={Boolean(
            htmlPreviewState?.fileHubId === fileHub.id &&
            htmlPreviewState.fingerprint,
          )}
          approvalExpired={Boolean(
            htmlPreviewState?.fileHubId === fileHub.id &&
            htmlPreviewState.approvalExpired,
          )}
        />
      )}
      <NoteExportDialog
        note={note}
        open={exportDialogOpen}
        onOpenChange={setExportDialogOpen}
      />
      <Dialog
        open={pendingAttachPath !== null}
        onOpenChange={(open) => !open && setPendingAttachPath(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>How should this file be attached?</DialogTitle>
          </DialogHeader>
          <p className="break-all text-sm text-muted-foreground">
            {pendingAttachPath}
          </p>
          <p className="text-sm text-muted-foreground">
            A local link stays on this device. A vault copy is portable and
            will move and trash together with this hub.
          </p>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => {
                if (pendingAttachPath) {
                  void attachFileToNote(note.id, pendingAttachPath, "local");
                }
                setPendingAttachPath(null);
              }}
            >
              Link Locally
            </Button>
            <Button
              onClick={() => {
                if (pendingAttachPath) {
                  void attachFileToNote(note.id, pendingAttachPath, "copy");
                }
                setPendingAttachPath(null);
              }}
            >
              Copy into Vault
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      <Dialog
        open={pendingNoteAttachments !== null}
        onOpenChange={(open) => !open && setPendingNoteAttachments(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {pendingNoteAttachments?.paths.length === 1
                ? "How should this attachment be stored?"
                : `How should these ${pendingNoteAttachments?.paths.length ?? 0} attachments be stored?`}
            </DialogTitle>
          </DialogHeader>
          <div className="max-h-36 space-y-1 overflow-y-auto rounded-md bg-muted/60 p-3">
            {pendingNoteAttachments?.paths.map((path) => (
              <p key={path} className="truncate text-xs text-muted-foreground" title={path}>
                {path.split(/[\\/]/).pop()}
              </p>
            ))}
          </div>
          <p className="text-sm text-muted-foreground">
            An external link leaves the file where it is and works on this
            device. A vault copy travels with the vault. The source file is
            never removed.
          </p>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => void confirmNoteAttachments("external")}
            >
              Keep External Link
            </Button>
            <Button onClick={() => void confirmNoteAttachments("copy")}>
              Copy into Vault
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      <Dialog open={conflictReviewOpen} onOpenChange={setConflictReviewOpen}>
        <DialogContent className="h-[85vh] max-w-6xl grid-rows-[auto_minmax(0,1fr)] overflow-hidden">
          <DialogHeader>
            <DialogTitle>Review note changes</DialogTitle>
          </DialogHeader>
          {conflict && (
            <div className="grid min-h-0 grid-cols-2 gap-3 overflow-hidden">
              <div className="flex min-w-0 flex-col overflow-hidden rounded-md border">
                <div className="border-b bg-muted/50 px-3 py-2 text-xs font-semibold">
                  Current note in Zerus
                </div>
                <pre className="min-h-0 flex-1 overflow-y-auto overscroll-contain whitespace-pre-wrap break-words p-3 text-xs">
                  {conflict.currentContent}
                </pre>
              </div>
              <div className="flex min-w-0 flex-col overflow-hidden rounded-md border">
                <div className="border-b bg-muted/50 px-3 py-2 text-xs font-semibold">
                  Changed version on disk
                </div>
                <pre className="min-h-0 flex-1 overflow-y-auto overscroll-contain whitespace-pre-wrap break-words p-3 text-xs">
                  {conflict.diskContent ?? "This file was deleted on disk."}
                </pre>
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
      <AlertDialog
        open={overwriteDiskConfirmOpen}
        onOpenChange={setOverwriteDiskConfirmOpen}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Save the current note over disk?</AlertDialogTitle>
            <AlertDialogDescription>
              This keeps the note currently shown in Zerus and overwrites the
              changed version on disk. The external changes cannot be recovered
              through Zerus.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className={buttonVariants({ variant: "destructive" })}
              onClick={() => void resolveNoteConflict(note.id, "current")}
            >
              Save current note over disk
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <AlertDialog open={trashConfirmOpen} onOpenChange={setTrashConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Move “{noteTitle(note)}” to trash?
            </AlertDialogTitle>
            <AlertDialogDescription>
              You can restore this note later from Trash.
              {fileHub?.managed
                ? ` Its managed file “${fileHub.name}” will move with it.`
                : ""}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className={buttonVariants({ variant: "destructive" })}
              onClick={() => void trashNote(note.id)}
            >
              Move to trash
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
