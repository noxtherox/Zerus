import { useEffect, useState } from "react";
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
import { normalizeExternalUrl } from "@/lib/external-links";

export function AddLinkDialog({
  open,
  onOpenChange,
  onAdd,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onAdd: (url: string) => Promise<void>;
}) {
  const [value, setValue] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!open) {
      setValue("");
      setError(null);
      setSubmitting(false);
    }
  }, [open]);

  const submit = async () => {
    const url = normalizeExternalUrl(value);
    if (!url) {
      setError("Enter a valid http or https URL.");
      return;
    }
    setSubmitting(true);
    await onAdd(url);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add link</DialogTitle>
          <DialogDescription>
            Add a web address to Links. You can use a full URL or a domain.
          </DialogDescription>
        </DialogHeader>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            void submit();
          }}
          className="space-y-2"
        >
          <Input
            autoFocus
            inputMode="url"
            placeholder="https://example.com"
            value={value}
            onChange={(event) => {
              setValue(event.target.value);
              setError(null);
            }}
            aria-invalid={!!error}
          />
          {error && <p className="text-xs text-destructive">{error}</p>}
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={!value.trim() || submitting}>
              Add link
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
