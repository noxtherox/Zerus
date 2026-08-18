import { Copy, ExternalLink, Link2 } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import { getLinkHubReference } from "@/lib/link-hubs";
import { openExternalUrl } from "@/lib/external-links";
import { noteTitle, type Note } from "@/lib/note-utils";
import { showError, showSuccess } from "@/utils/toast";

export function LinkHubPanel({ note }: { note: Note }) {
  const reference = getLinkHubReference(note);
  if (!reference) return null;

  const copyLink = async () => {
    try {
      await navigator.clipboard.writeText(reference.url);
      showSuccess("Link copied");
    } catch {
      showError("Couldn't copy the link");
    }
  };

  return (
    <div className="shrink-0 border-b border-border/60 bg-background/70 p-3">
      <div className="flex items-start gap-3">
        <div className="mt-0.5 rounded-md bg-muted p-2 text-zerus-accent">
          <Link2 size={20} />
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold">
            {noteTitle(note)}
          </p>
          <p
            className="mt-0.5 truncate text-xs text-muted-foreground"
            title={reference.url}
          >
            {reference.url}
          </p>
        </div>
        <div className="flex shrink-0 gap-1">
          <Button
            variant="outline"
            size="sm"
            className="h-8 gap-1.5 text-xs"
            onClick={() => void copyLink()}
          >
            <Copy size={13} /> Copy Link
          </Button>
          <Button
            size="sm"
            className="h-8 gap-1.5 text-xs"
            onClick={() => void openExternalUrl(reference.url)}
          >
            <ExternalLink size={13} /> Open Link
          </Button>
        </div>
      </div>
    </div>
  );
}
