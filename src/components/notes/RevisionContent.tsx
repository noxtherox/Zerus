import { lazy, Suspense, useCallback, useState } from "react";
import { MarkdownEditor } from "@/components/editor/MdxMarkdownEditor";
import { Button } from "@/components/ui/button";
import { Download } from "@/lib/icons";
import { noteBody } from "@/lib/frontmatter";
import { fileExtension, getFileHubReference } from "@/lib/file-hubs";
import { getNoteAttachments } from "@/lib/note-attachments";
import { findNoteByTitle, noteTitle, type Note } from "@/lib/note-utils";
import { revisionFiles } from "@/lib/note-revisions";
import { exportRevisionFile, getNotes, readRevisionFile } from "@/store/notes-store";

const PdfViewer = lazy(() => import("./PdfViewer").then((module) => ({ default: module.PdfViewer })));
const HtmlViewer = lazy(() => import("./HtmlViewer").then((module) => ({ default: module.HtmlViewer })));

/** Read-only body in the normal note area; exports are copies, never editable snapshot paths. */
export function RevisionContent({ note, revisionId, onOpenNote, mobile = false }: {
  note: Note; revisionId: string; onOpenNote: (id: string) => void; mobile?: boolean;
}) {
  const [error, setError] = useState<string | null>(null);
  const file = getFileHubReference(note);
  const files = revisionFiles(note.content);
  const extension = file ? fileExtension(file.name) : "";
  const path = file?.path;
  const loadBytes = useCallback(async () => {
    if (!path) throw new Error("This revision's file is missing.");
    return readRevisionFile(path);
  }, [path]);
  const download = (path: string, name: string) => {
    setError(null);
    void exportRevisionFile(path, name).catch((cause) => setError(String(cause)));
  };
  return <div className="flex min-h-0 flex-1 flex-col" data-revision-preview onContextMenuCapture={(event) => {
    // Editor image menus can open files in external editors. Frozen files only leave as copies.
    event.preventDefault(); event.stopPropagation();
  }} onClickCapture={(event) => {
    const anchor = (event.target as HTMLElement).closest("a");
    const href = anchor?.getAttribute("href");
    const linked = files.find((candidate) => href === candidate.path || href?.startsWith(`${candidate.path}#`));
    if (linked) { event.preventDefault(); event.stopPropagation(); download(linked.path, linked.name); }
  }}>
    {files.length > 0 && <div className="max-h-32 shrink-0 overflow-y-auto border-b border-border/60 px-4 py-2">
      {files.map((asset) => <Button key={asset.path} variant="ghost" size="sm" className="mr-2 max-w-full gap-2 text-xs" onClick={() => download(asset.path, asset.name)}>
        <Download size={14} className="shrink-0" /><span className="truncate">{asset.name}</span>
      </Button>)}
    </div>}
    {error && <p role="alert" className="px-4 py-2 text-xs text-destructive">{error}</p>}
    {path && ["pdf", "html", "htm"].includes(extension) && <div className="h-[40%] min-h-40 shrink-0 border-b border-border/60">
      <Suspense fallback={<p className="p-4 text-sm text-muted-foreground">Loading file preview…</p>}>
        {extension === "pdf" ? <PdfViewer loadBytes={loadBytes} version={revisionId} />
          : <HtmlViewer loadBytes={loadBytes} version={revisionId} mode="safe" />}
      </Suspense>
    </div>}
    <div className="min-h-0 flex-1">
      <MarkdownEditor
        noteId={`${note.id}:revision:${revisionId}`}
        initialContent={noteBody(note.content)}
        getLinkableTitles={() => getNotes().map(noteTitle)}
        isTitleResolved={(title) => !!findNoteByTitle(title, getNotes())}
        onChange={() => {}}
        onFollowLink={(title) => { const target = findNoteByTitle(title, getNotes()); if (target) onOpenNote(target.id); }}
        readOnly autoFocus={false} followLinksOnClick={mobile}
        attachments={getNoteAttachments(note)}
        onAttachmentAction={(id, action) => {
          if (action !== "open") return;
          const attachment = getNoteAttachments(note).find((candidate) => candidate.id === id);
          if (attachment?.path) download(attachment.path, attachment.name);
        }}
      />
    </div>
  </div>;
}
