import { useState } from "react";
import { ExternalLink, Link2, Pencil } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { openExternalUrl } from "@/lib/external-links";
import { updateSavedLinkUrl } from "@/store/notes-store";

export function MobileSavedLink({ noteId, url }: { noteId: string; url: string }) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(url);
  const [error, setError] = useState<string | null>(null);
  return <>
    <div className="mt-4 flex items-center gap-1 rounded-xl bg-zerus-accent/10 text-zerus-accent">
      <button type="button" onClick={() => void openExternalUrl(url)} className="flex min-h-12 min-w-0 flex-1 items-center gap-3 px-4 py-3 text-left text-sm" aria-label={`Open saved link: ${url}`}>
        <Link2 className="h-5 w-5 shrink-0" /><span className="min-w-0 flex-1 truncate">{url}</span><ExternalLink className="h-4 w-4 shrink-0" />
      </button>
      <Button variant="ghost" size="icon" className="h-11 w-11 shrink-0" aria-label="Edit saved link URL" onClick={() => { setDraft(url); setError(null); setEditing(true); }}><Pencil className="h-4 w-4" /></Button>
    </div>
    <Dialog open={editing} onOpenChange={setEditing}>
      <DialogContent>
        <DialogHeader><DialogTitle>Edit link</DialogTitle><DialogDescription>Update the web address. Your title and notes stay with this link.</DialogDescription></DialogHeader>
        <form className="space-y-4" onSubmit={event => {
          event.preventDefault();
          if (updateSavedLinkUrl(noteId, draft)) setEditing(false);
          else setError("Use a valid http or https address that is not already saved in Links.");
        }}>
          <Input autoFocus aria-label="Web address" aria-invalid={!!error} aria-describedby={error ? "mobile-link-error" : undefined} inputMode="url" autoCapitalize="none" autoCorrect="off" value={draft} onChange={event => { setDraft(event.target.value); setError(null); }} className="min-h-11 text-base" />
          {error && <p id="mobile-link-error" role="alert" className="text-sm text-destructive">{error}</p>}
          <DialogFooter><Button type="button" variant="outline" onClick={() => setEditing(false)}>Cancel</Button><Button type="submit" disabled={!draft.trim()}>Save link</Button></DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  </>;
}
