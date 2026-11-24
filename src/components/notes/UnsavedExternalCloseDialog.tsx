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
import { noteTitle } from "@/lib/note-utils";
import {
  cancelUnsavedExternalClose,
  closeExternalNote,
  useVaultSelector,
} from "@/store/notes-store";

/**
 * Shown when closing an external note could not save it first (for example,
 * a Markdown file on a read-only disk image). Lets the user close without
 * saving instead of leaving the note stuck open.
 */
export function UnsavedExternalCloseDialog() {
  const id = useVaultSelector((vault) => vault.unsavedExternalCloseId);
  const note = useVaultSelector((vault) =>
    id ? vault.notes.find((candidate) => candidate.id === id) : undefined,
  );
  const title = note ? noteTitle(note) : "this note";

  return (
    <AlertDialog
      open={Boolean(id && note)}
      onOpenChange={(open) => !open && cancelUnsavedExternalClose()}
    >
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle className="line-clamp-3" title={title}>
            Close “{title}” without saving?
          </AlertDialogTitle>
          <AlertDialogDescription>
            Zerus couldn’t save this note to its file, which may be on a
            read-only location. Closing now discards changes that weren’t
            saved. The original file stays where it is.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Keep open</AlertDialogCancel>
          <AlertDialogAction
            className={buttonVariants({ variant: "destructive" })}
            onClick={() => {
              if (id) void closeExternalNote(id, { discardUnsaved: true });
            }}
          >
            Close without saving
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
