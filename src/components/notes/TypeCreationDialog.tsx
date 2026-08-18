import { ChevronRight, Folder } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { parseTypePath } from "@/lib/note-utils";

interface TypeCreationDialogProps {
  open: boolean;
  parentPath: string[];
  draft: string;
  onDraftChange: (draft: string) => void;
  onOpenChange: (open: boolean) => void;
  onSubmit: (name: string) => void;
}

export function TypeCreationDialog({
  open,
  parentPath,
  draft,
  onDraftChange,
  onOpenChange,
  onSubmit,
}: TypeCreationDialogProps) {
  const parsedName = parseTypePath(draft);
  const containsPathSeparator = draft.includes("/");
  const canSubmit = parsedName.length === 1 && !containsPathSeparator;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>
            {parentPath.length > 0 ? "Add subtype" : "Add type"}
          </DialogTitle>
        </DialogHeader>
        <form
          className="space-y-4"
          onSubmit={(event) => {
            event.preventDefault();
            if (canSubmit) onSubmit(parsedName[0]);
          }}
        >
          {parentPath.length > 0 && (
            <div className="space-y-2">
              <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Parent types
              </p>
              <div className="flex flex-wrap items-center gap-1.5 rounded-md border bg-muted/35 px-3 py-2.5 text-sm">
                {parentPath.map((segment, index) => (
                  <span key={`${segment}-${index}`} className="contents">
                    {index > 0 && (
                      <ChevronRight
                        className="h-3.5 w-3.5 shrink-0 text-muted-foreground"
                        aria-hidden="true"
                      />
                    )}
                    <span className="flex min-w-0 items-center gap-1.5 font-medium">
                      <Folder
                        className="h-4 w-4 shrink-0 text-muted-foreground"
                        aria-hidden="true"
                      />
                      <span className="truncate">{segment}</span>
                    </span>
                  </span>
                ))}
              </div>
            </div>
          )}
          <div className="space-y-2">
            <Label htmlFor="new-type-name">Name</Label>
            <Input
              id="new-type-name"
              autoFocus
              value={draft}
              onChange={(event) => onDraftChange(event.target.value)}
              placeholder={parentPath.length > 0 ? "Subtype name" : "Type name"}
              aria-describedby={
                containsPathSeparator ? "new-type-name-error" : undefined
              }
            />
            {containsPathSeparator && (
              <p id="new-type-name-error" className="text-xs text-destructive">
                Enter one name without a slash.
              </p>
            )}
          </div>
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={!canSubmit}>
              Add
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
