import { useEffect, useState } from "react";
import { Link2 } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { normalizeExternalUrl } from "@/lib/external-links";

interface LinkDialogProps {
  open: boolean;
  initialLabel: string;
  onOpenChange: (open: boolean) => void;
  onInsert: (label: string, url: string) => void;
}

export function LinkDialog({
  open,
  initialLabel,
  onOpenChange,
  onInsert,
}: LinkDialogProps) {
  const [label, setLabel] = useState("");
  const [url, setUrl] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setLabel(initialLabel);
      setUrl("");
      setError(null);
    }
  }, [initialLabel, open]);

  const submit = () => {
    const cleanLabel = label.trim();
    const normalizedUrl = normalizeExternalUrl(url);
    if (!cleanLabel) return;
    if (!normalizedUrl) {
      setError("Enter a valid http or https web address.");
      return;
    }
    onInsert(cleanLabel, normalizedUrl);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-sm border-border bg-background p-5 shadow-2xl">
        <DialogHeader>
          <div className="mb-1 flex h-9 w-9 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <Link2 className="h-4 w-4" />
          </div>
          <DialogTitle>Insert link</DialogTitle>
          <DialogDescription>
            Choose the text readers will see and where the link should go.
          </DialogDescription>
        </DialogHeader>

        <form
          className="space-y-4 py-1"
          onSubmit={(event) => {
            event.preventDefault();
            submit();
          }}
        >
          <div className="space-y-2">
            <Label htmlFor="editor-link-label" className="text-xs font-medium text-muted-foreground">
              Text to display
            </Label>
            <Input
              id="editor-link-label"
              value={label}
              placeholder="Link text"
              autoFocus={!initialLabel}
              onChange={(event) => setLabel(event.target.value)}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="editor-link-url" className="text-xs font-medium text-muted-foreground">
              Web address
            </Label>
            <Input
              id="editor-link-url"
              value={url}
              inputMode="url"
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              placeholder="https://example.com"
              autoFocus={!!initialLabel}
              aria-invalid={!!error}
              aria-describedby={error ? "editor-link-url-error" : undefined}
              onChange={(event) => {
                setUrl(event.target.value);
                setError(null);
              }}
            />
            {error && (
              <p id="editor-link-url-error" className="text-xs text-destructive" role="alert">
                {error}
              </p>
            )}
          </div>

          <DialogFooter>
            <Button type="button" variant="ghost" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={!label.trim() || !url.trim()}>
              Insert link
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
