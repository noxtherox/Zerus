import { useState, type ReactNode } from "react";
import { Copy, ExternalLink, Link2, Maximize, Minimize, Pencil } from "@/lib/icons";
import { ResizableHandle, ResizablePanel, ResizablePanelGroup } from "@/components/ui/resizable";
import { loadLinkPreview, saveLinkPreview } from "@/lib/link-preview";
import { Button } from "@/components/ui/button";
import { getLinkHubReference } from "@/lib/link-hubs";
import { normalizeExternalUrl, openExternalUrl } from "@/lib/external-links";
import { noteTitle, type Note } from "@/lib/note-utils";
import { updateSavedLinkUrl } from "@/store/notes-store";
import { showError, showSuccess } from "@/utils/toast";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";

export function LinkHubPanel({ note, children }: { note: Note; children: ReactNode }) {
  const reference = getLinkHubReference(note);
  const [renderPage, setRenderPage] = useState(() => reference ? loadLinkPreview(reference.id, reference.url) : false);
  const [expanded, setExpanded] = useState(false);
  const [reload, setReload] = useState(0);
  const [editing, setEditing] = useState(false);
  const [urlDraft, setUrlDraft] = useState(reference?.url ?? "");
  const [urlError, setUrlError] = useState<string | null>(null);
  if (!reference) return <>{children}</>;

  const togglePreview = () => {
    const next = !renderPage;
    setRenderPage(next);
    setExpanded(false);
    saveLinkPreview(reference.id, reference.url, next);
  };

  const copyLink = async () => {
    try {
      await navigator.clipboard.writeText(reference.url);
      showSuccess("Link copied");
    } catch {
      showError("Couldn't copy the link");
    }
  };

  const saveLink = () => {
    const url = normalizeExternalUrl(urlDraft);
    if (!url) {
      setUrlError("Enter a valid http or https URL.");
      return;
    }
    if (!updateSavedLinkUrl(note.id, url)) {
      setUrlError("That URL is already saved.");
      return;
    }
    setEditing(false);
    showSuccess("Link updated");
  };

  return (
    <div className="flex min-h-0 flex-1 flex-col">
    <div className="shrink-0 border-b border-border/60 bg-background/70 p-3">
      <div className="flex flex-wrap items-start gap-3">
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
        <div className="flex shrink-0 flex-wrap gap-1">
          <Button
            variant="outline"
            size="sm"
            className="h-8 gap-1.5 text-xs"
            onClick={() => {
              setUrlDraft(reference.url);
              setUrlError(null);
              setEditing(true);
            }}
          >
            <Pencil size={13} /> Edit Link
          </Button>
          <Button
            variant="outline"
            size="sm"
            className="h-8 text-xs"
            aria-pressed={renderPage}
            onClick={togglePreview}
          >
            {renderPage ? "Hide page" : "Render page"}
          </Button>
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
    <ResizablePanelGroup direction="vertical" className="min-h-0 flex-1">
      <ResizablePanel defaultSize={58} minSize={20} className={!renderPage ? "hidden" : undefined}>
        {renderPage && (
          <div className="flex h-full min-h-0 flex-col">
            <div className="flex shrink-0 flex-wrap items-center gap-2 border-b px-3 py-1.5">
              <p className="min-w-0 flex-1 text-xs text-muted-foreground">
                Live page · Some sites block previews or require a browser. Use Open Link if the page is blank.
              </p>
              <Button variant="ghost" size="sm" className="h-7 text-xs" onClick={() => setReload((value) => value + 1)}>
                Reload
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7"
                title={expanded ? "Restore page and notes split" : "Expand page to full height"}
                aria-label={expanded ? "Restore page and notes split" : "Expand page to full height"}
                aria-pressed={expanded}
                onClick={() => setExpanded((value) => !value)}
              >
                {expanded ? <Minimize size={14} /> : <Maximize size={14} />}
              </Button>
            </div>
            <iframe
              key={`${reference.url}:${reload}`}
              title={`Web page preview: ${noteTitle(note)}`}
              src={reference.url}
              sandbox="allow-scripts"
              referrerPolicy="no-referrer"
              allow="camera 'none'; microphone 'none'; geolocation 'none'; clipboard-read 'none'; clipboard-write 'none'"
              className="min-h-0 w-full flex-1 border-0 bg-white"
            />
          </div>
        )}
      </ResizablePanel>
      <ResizableHandle withHandle className={!renderPage || expanded ? "hidden" : undefined} />
      <ResizablePanel defaultSize={42} minSize={20} className={renderPage && expanded ? "hidden" : undefined}>
        <div className="flex h-full min-h-0 flex-col">{children}</div>
      </ResizablePanel>
    </ResizablePanelGroup>
    <Dialog open={editing} onOpenChange={setEditing}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Edit link</DialogTitle>
          <DialogDescription>
            Change the web address used by this saved link.
          </DialogDescription>
        </DialogHeader>
        <form
          className="space-y-2"
          onSubmit={(event) => {
            event.preventDefault();
            saveLink();
          }}
        >
          <Input
            autoFocus
            inputMode="url"
            value={urlDraft}
            onChange={(event) => {
              setUrlDraft(event.target.value);
              setUrlError(null);
            }}
            aria-invalid={!!urlError}
          />
          {urlError && <p className="text-xs text-destructive">{urlError}</p>}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setEditing(false)}>
              Cancel
            </Button>
            <Button type="submit" disabled={!urlDraft.trim()}>
              Save link
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
    </div>
  );
}
