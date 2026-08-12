import { useEffect, useState } from "react";
import {
  Archive,
  ArchiveRestore,
  AlertTriangle,
  ArrowLeft,
  ArrowRight,
  Copy,
  Ellipsis,
  FileUp,
  FolderSearch,
  Link2,
  Link2Off,
  Loader2,
  MapPin,
  Maximize,
  Minimize,
  Pin,
  RefreshCw,
  Search,
  SquareTerminal,
  Sparkles,
  Trash2,
  Undo2,
  X,
} from "@/lib/icons";
import { Button, buttonVariants } from "@/components/ui/button";
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
import { MarkdownEditor } from "@/components/editor/MarkdownEditor";
import { FileHubPanel } from "./FileHubPanel";
import {
  ResizableHandle,
  ResizablePanel,
  ResizablePanelGroup,
} from "@/components/ui/resizable";
import { ZerusLogo } from "@/components/ZerusLogo";
import { TypePicker } from "./TypePicker";
import { BacklinksPanel } from "./BacklinksPanel";
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
import type { PropertySchemas } from "@/lib/properties";
import type { TypeIcons } from "@/lib/type-icons";
import {
  type NoteConflict,
  closeExternalNote,
  attachFileToNote,
  chooseDocumentFile,
  createNote,
  detachFileHub,
  getNotes,
  getFileHubStatus,
  locateFileHub,
  restoreNote,
  resolveNoteConflict,
  revealNoteInDesktop,
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

interface EditorPaneProps {
  note: Note | null;
  allNotes: Note[];
  /** Types that exist without notes — offered by the type picker too. */
  extraTypes: string[][];
  schemas: PropertySchemas;
  /** Custom icon per type key, shown in the type picker. */
  typeIcons: TypeIcons;
  vaultLocation: string | null;
  onOpenNote: (id: string) => void;
  onMoveExternalToVault: (id: string, typePath: string[]) => void;
  isBusy: boolean;
  isLoading: boolean;
  isRefreshing: boolean;
  isFocusMode: boolean;
  onToggleFocusMode: () => void;
  isDesktop: boolean;
  terminalOpen: boolean;
  onToggleTerminal: () => void;
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
  terminalOpen: boolean;
  onToggleTerminal: () => void;
  isFocusMode: boolean;
  onToggleFocusMode: () => void;
}

function EditorContextControls({
  isDesktop,
  aiOpen,
  onToggleAi,
  terminalOpen,
  onToggleTerminal,
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
            aiOpen && "bg-muted text-grim-accent",
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
      {isDesktop && (
        <Button
          variant="ghost"
          size="icon"
          className={cn(
            "h-7 w-7 shrink-0",
            terminalOpen && "bg-muted text-grim-accent",
          )}
          title={
            terminalOpen
              ? `Hide terminal (${primaryModifierLabel}J)`
              : `Open terminal (${primaryModifierLabel}J)`
          }
          aria-label={terminalOpen ? "Hide terminal" : "Open terminal"}
          aria-pressed={terminalOpen}
          onClick={onToggleTerminal}
        >
          <SquareTerminal size={15} />
        </Button>
      )}
      <Button
        variant="ghost"
        size="icon"
        className={cn(
          "h-7 w-7 shrink-0",
          isFocusMode && "bg-muted text-grim-accent",
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

type ExpandedFileHubSection = "pdf" | "markdown";

export function EditorPane({
  note,
  allNotes,
  extraTypes,
  schemas,
  typeIcons,
  vaultLocation,
  onOpenNote,
  onMoveExternalToVault,
  isBusy,
  isLoading,
  isRefreshing,
  isFocusMode,
  onToggleFocusMode,
  isDesktop,
  terminalOpen,
  onToggleTerminal,
  aiOpen,
  onToggleAi,
  conflict,
  canNavigateBack,
  canNavigateForward,
  onNavigateBack,
  onNavigateForward,
}: EditorPaneProps) {
  const [showBacklinks, setShowBacklinks] = useState(false);
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
  const [fileHubExists, setFileHubExists] = useState<boolean | null>(null);
  const [expandedFileHubSection, setExpandedFileHubSection] = useState<{
    noteId: string;
    section: ExpandedFileHubSection;
  } | null>(null);

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

  if (!note) {
    return (
      <div className="flex h-full flex-col bg-grim-editor">
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
            terminalOpen={terminalOpen}
            onToggleTerminal={onToggleTerminal}
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

  if (isLoading) {
    return (
      <div className="flex h-full flex-col bg-grim-editor">
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
            terminalOpen={terminalOpen}
            onToggleTerminal={onToggleTerminal}
            isFocusMode={isFocusMode}
            onToggleFocusMode={onToggleFocusMode}
          />
        </div>
        <div className="flex min-h-0 flex-1 items-center justify-center">
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" />
            Loading note…
          </div>
        </div>
      </div>
    );
  }

  const external = isExternalNote(note);
  const absolutePath = noteAbsolutePath(note, vaultLocation);
  const backlinkCount = external
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

  const fileHub = getFileHubReference(note);
  const linkedFileType = fileHub
    ? fileExtension(fileHub.name).toUpperCase() || "FILE"
    : "FILE";
  const pdfHub = fileHub ? fileExtension(fileHub.name) === "pdf" : false;
  const expandedSection =
    expandedFileHubSection?.noteId === note.id
      ? expandedFileHubSection.section
      : null;
  const toggleExpandedSection = (section: ExpandedFileHubSection) => {
    setExpandedFileHubSection((current) =>
      current?.noteId === note.id && current.section === section
        ? null
        : { noteId: note.id, section },
    );
  };
  const editorContent = (
    <div className="flex min-h-0 flex-1">
      <div
        className={cn(
          "min-w-0 flex-1",
          showBacklinks && expandBacklinks && "hidden",
        )}
      >
        <MarkdownEditor
          noteId={note.id}
          initialContent={noteBody(note.content)}
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
            pdfHub ? () => toggleExpandedSection("markdown") : undefined
          }
          findRequest={findRequest}
        />
      </div>
      {!external && showBacklinks && (
        <BacklinksPanel
          note={note}
          allNotes={allNotes}
          schemas={schemas}
          onOpenNote={onOpenNote}
          expanded={expandBacklinks}
          onToggleExpanded={() => setExpandBacklinks((open) => !open)}
        />
      )}
    </div>
  );

  return (
    <div className="flex h-full flex-col bg-grim-editor">
      <div
        className={cn(
          "flex items-center gap-2 border-b border-border/60 px-4 py-2",
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
            <TypePicker
              value={[]}
              existingTypePaths={getAllTypePaths(allNotes, extraTypes)}
              typeIcons={typeIcons}
              label="Move to vault…"
              title="Move this file into the vault and assign its type"
              onChange={(typePath) => onMoveExternalToVault(note.id, typePath)}
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
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  onSelect={() => void revealNoteInDesktop(note.id)}
                >
                  <FolderSearch className="mr-2" size={14} />
                  Reveal in {fileManagerName}
                </DropdownMenuItem>
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
                {!fileHub && !isTrashed(note) && (
                  <DropdownMenuItem onSelect={() => void startFileHubAttach()}>
                    <FileUp className="mr-2" size={14} />
                    Attach file to note
                  </DropdownMenuItem>
                )}
                <DropdownMenuSeparator />
                {isTrashed(note) ? (
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
                      {isArchived(note) ? (
                        <ArchiveRestore className="mr-2" size={14} />
                      ) : (
                        <Archive className="mr-2" size={14} />
                      )}
                      {isArchived(note) ? "Unarchive" : "Archive"}
                    </DropdownMenuItem>
                    <DropdownMenuItem
                      onSelect={() => toggleNotePinned(note.id)}
                    >
                      <Pin
                        className={cn(
                          "mr-2",
                          note.pinned && "text-grim-accent",
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
                showBacklinks && "bg-muted text-grim-accent",
              )}
              title="properties and backlinks"
              onClick={() => setShowBacklinks((open) => !open)}
            >
              <Link2 size={15} />
              {backlinkCount > 0 && (
                <span className="absolute -right-0.5 -top-0.5 flex h-3.5 min-w-3.5 items-center justify-center rounded-full bg-grim-accent px-0.5 text-[9px] font-semibold leading-none text-white tabular-nums">
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
          terminalOpen={terminalOpen}
          onToggleTerminal={onToggleTerminal}
          isFocusMode={isFocusMode}
          onToggleFocusMode={onToggleFocusMode}
        />
      </div>
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
        pdfHub ? (
          <ResizablePanelGroup direction="vertical" className="min-h-0 flex-1">
            <ResizablePanel
              defaultSize={58}
              minSize={20}
              collapsible
              collapsedSize={8}
              className={expandedSection === "markdown" ? "hidden" : undefined}
            >
              <FileHubPanel
                note={note}
                showPdf
                isPdfFullHeight={expandedSection === "pdf"}
                onTogglePdfFullHeight={() => toggleExpandedSection("pdf")}
              />
            </ResizablePanel>
            <ResizableHandle
              withHandle
              className={expandedSection ? "hidden" : undefined}
            />
            <ResizablePanel
              defaultSize={42}
              minSize={20}
              className={expandedSection === "pdf" ? "hidden" : undefined}
            >
              {editorContent}
            </ResizablePanel>
          </ResizablePanelGroup>
        ) : (
          <div className="flex min-h-0 flex-1 flex-col">
            <div className="shrink-0">
              <FileHubPanel note={note} showPdf={false} />
            </div>
            {editorContent}
          </div>
        )
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
