import {
  createContext,
  useContext,
  useState,
  type ReactElement,
  type ReactNode,
} from "react";
import {
  Archive,
  ArchiveRestore,
  Copy,
  FilePlus2,
  FolderSearch,
  Pin,
  SlidersHorizontal,
  Trash2,
  Undo2,
  X,
} from "@/lib/icons";
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
import { buttonVariants } from "@/components/ui/button-variants";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";
import { fileManagerName } from "@/lib/desktop-platform";
import { getFileHubReference } from "@/lib/file-hubs";
import { handleMiddleMouseDown } from "@/lib/middle-click";
import {
  isArchived,
  isExternalNote,
  noteTitle,
  type Note,
} from "@/lib/note-utils";
import {
  closeExternalNote,
  deleteNoteForever,
  duplicateNote,
  restoreNote,
  revealNoteInDesktop,
  toggleNoteArchived,
  toggleNotePinned,
  trashNote,
} from "@/store/notes-store";
import type { BulkMutationRequest } from "./BulkActionsToolbar";

type Confirmation = { note: Note; action: "trash" | "delete" | "close" };

interface NoteMenuActions {
  selectedIds: ReadonlySet<string>;
  disabled?: boolean;
  inTrash?: boolean;
  onOpenNote: (id: string) => void;
  onOpenNoteInNewTab: (id: string) => void;
  onBulkRequest: (request: BulkMutationRequest) => void;
  onInteraction: () => void;
  confirm: (confirmation: Confirmation) => void;
}

const NoteMenuContext = createContext<NoteMenuActions | null>(null);

export function NoteContextMenuProvider({
  children,
  ...actions
}: Omit<NoteMenuActions, "confirm"> & { children: ReactNode }) {
  const [confirmation, setConfirmation] = useState<Confirmation | null>(null);
  const target = confirmation?.note;
  const action = confirmation?.action;
  const label =
    action === "delete"
      ? "Delete forever"
      : action === "close"
        ? "Close note"
        : "Move to trash";
  const title =
    action === "delete"
      ? `Delete “${target ? noteTitle(target) : "this note"}” forever?`
      : action === "close"
        ? `Close “${target ? noteTitle(target) : "this note"}”?`
        : `Move “${target ? noteTitle(target) : "this note"}” to trash?`;

  return (
    <NoteMenuContext.Provider value={{ ...actions, confirm: setConfirmation }}>
      {children}
      <AlertDialog
        open={confirmation !== null}
        onOpenChange={(open) => !open && setConfirmation(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle className="line-clamp-3" title={title}>
              {title}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {action === "close" ? (
                "Zerus will stop tracking this external note. The file will be saved and left in its current location."
              ) : action === "delete" ? (
                <>
                  This cannot be undone.
                  {target && getFileHubReference(target)?.managed
                    ? ` The managed file “${getFileHubReference(target)?.name}” will also be permanently deleted.`
                    : ""}
                </>
              ) : (
                "You can restore this note later from Trash."
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className={
                action !== "close"
                  ? buttonVariants({ variant: "destructive" })
                  : undefined
              }
              onClick={() => {
                if (!confirmation) return;
                const { note, action: confirmedAction } = confirmation;
                if (confirmedAction === "close")
                  void closeExternalNote(note.id);
                else if (confirmedAction === "delete")
                  void deleteNoteForever(note.id);
                else void trashNote(note.id);
              }}
            >
              {label}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </NoteMenuContext.Provider>
  );
}

export function NoteContextMenu({
  note,
  children,
}: {
  note: Note;
  children: ReactElement;
}) {
  const actions = useContext(NoteMenuContext);
  if (!actions)
    throw new Error("NoteContextMenu requires NoteContextMenuProvider");
  const {
    selectedIds,
    disabled,
    inTrash,
    onOpenNote,
    onOpenNoteInNewTab,
    onBulkRequest,
    onInteraction,
    confirm,
  } = actions;
  const external = isExternalNote(note);
  const archived = isArchived(note);
  const targetIds = selectedIds.has(note.id) ? [...selectedIds] : [note.id];
  const bulk = targetIds.length > 1;
  const request = (patch: Omit<BulkMutationRequest, "id" | "noteIds">) =>
    onBulkRequest({ id: Date.now(), noteIds: targetIds, ...patch });

  return (
    <ContextMenu
      onOpenChange={(open) => {
        if (open) onInteraction();
      }}
    >
      <ContextMenuTrigger
        asChild
        className="touch-manipulation"
        disabled={disabled}
        onMouseDown={(event) => {
          if (
            disabled ||
            (event.target as HTMLElement).closest(
              "input, select, textarea, [contenteditable=true], [data-note-selection]",
            )
          )
            return;
          handleMiddleMouseDown(event, () => {
            onInteraction();
            onOpenNoteInNewTab(note.id);
          });
        }}
      >
        {children}
      </ContextMenuTrigger>
      <ContextMenuContent>
        <ContextMenuItem onSelect={() => onOpenNoteInNewTab(note.id)}>
          <FilePlus2 size={14} className="mr-2" /> Open in new tab
        </ContextMenuItem>
        <ContextMenuSeparator />
        <ContextMenuItem onSelect={() => void revealNoteInDesktop(note.id)}>
          <FolderSearch size={14} className="mr-2" /> Reveal in{" "}
          {fileManagerName}
        </ContextMenuItem>
        {external ? (
          <ContextMenuItem onSelect={() => confirm({ note, action: "close" })}>
            <X size={14} className="mr-2" /> Close note
          </ContextMenuItem>
        ) : inTrash ? (
          <>
            <ContextMenuItem onSelect={() => void restoreNote(note.id)}>
              <Undo2 size={14} className="mr-2" /> Restore
            </ContextMenuItem>
            <ContextMenuItem
              className="text-destructive"
              onSelect={() => confirm({ note, action: "delete" })}
            >
              <Trash2 size={14} className="mr-2" /> Delete forever
            </ContextMenuItem>
          </>
        ) : (
          <>
            {!bulk && (
              <ContextMenuItem
                onSelect={() =>
                  void duplicateNote(note.id).then((copy) => {
                    if (copy) onOpenNote(copy.id);
                  })
                }
              >
                <Copy size={14} className="mr-2" /> Duplicate note
              </ContextMenuItem>
            )}
            {bulk ? (
              <>
                <ContextMenuItem
                  onSelect={() => request({ mutation: { archived: true } })}
                >
                  <Archive size={14} className="mr-2" /> Archive{" "}
                  {targetIds.length} notes
                </ContextMenuItem>
                <ContextMenuItem
                  onSelect={() => request({ mutation: { archived: false } })}
                >
                  <ArchiveRestore size={14} className="mr-2" /> Unarchive{" "}
                  {targetIds.length} notes
                </ContextMenuItem>
                <ContextMenuItem
                  onSelect={() => request({ mutation: { pinned: true } })}
                >
                  <Pin size={14} className="mr-2" /> Pin {targetIds.length}{" "}
                  notes
                </ContextMenuItem>
                <ContextMenuItem
                  onSelect={() => request({ mutation: { pinned: false } })}
                >
                  <Pin size={14} className="mr-2" /> Unpin {targetIds.length}{" "}
                  notes
                </ContextMenuItem>
              </>
            ) : (
              <>
                <ContextMenuItem onSelect={() => toggleNoteArchived(note.id)}>
                  {archived ? (
                    <ArchiveRestore size={14} className="mr-2" />
                  ) : (
                    <Archive size={14} className="mr-2" />
                  )}
                  {archived ? "Unarchive" : "Archive"}
                </ContextMenuItem>
                <ContextMenuItem onSelect={() => toggleNotePinned(note.id)}>
                  <Pin size={14} className="mr-2" />{" "}
                  {note.pinned ? "Unpin" : "Pin"}
                </ContextMenuItem>
              </>
            )}
            <ContextMenuItem onSelect={() => request({ openProperties: true })}>
              <SlidersHorizontal size={14} className="mr-2" /> Edit properties…
            </ContextMenuItem>
            {!bulk && (
              <ContextMenuItem
                className="text-destructive"
                onSelect={() => confirm({ note, action: "trash" })}
              >
                <Trash2 size={14} className="mr-2" /> Move to trash
              </ContextMenuItem>
            )}
          </>
        )}
      </ContextMenuContent>
    </ContextMenu>
  );
}
