import {
  Copy,
  Ellipsis,
  ExternalLink,
  File,
  FolderSearch,
  Paperclip,
} from "@/lib/icons";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import type { Note } from "@/lib/note-utils";
import { getNoteAttachments } from "@/lib/note-attachments";
import {
  convertNoteAttachment,
  openNoteAttachment,
  revealNoteAttachment,
} from "@/store/notes-store";
import { fileManagerName } from "@/lib/desktop-platform";
import { cn } from "@/lib/utils";

interface AttachmentsSectionProps {
  note: Note;
  expanded: boolean;
}

export function AttachmentsSection({ note, expanded }: AttachmentsSectionProps) {
  const attachments = getNoteAttachments(note);
  if (!attachments.length) return null;

  return (
    <section className="border-t border-border/60" aria-labelledby="attachments-heading">
      <div className="flex items-center gap-1.5 border-b border-border/60 px-4 py-3 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
        <Paperclip size={13} />
        <span id="attachments-heading">Attachments</span>
        <span className="rounded-full bg-muted px-1.5 tabular-nums">
          {attachments.length}
        </span>
      </div>
      <ul
        className={cn(
          "p-3",
          expanded ? "grid grid-cols-1 gap-2 md:grid-cols-2 xl:grid-cols-3" : "space-y-1.5",
        )}
      >
        {attachments.map((attachment) => (
          <li
            key={attachment.id}
            className="flex min-w-0 items-center gap-2 rounded-md border border-border/50 bg-zerus-editor px-2 py-1.5"
          >
            <File size={14} className="shrink-0 text-zerus-accent" />
            <button
              type="button"
              className="min-w-0 flex-1 truncate text-left text-xs font-medium hover:text-zerus-link"
              title={`Open ${attachment.name} in the default app`}
              onClick={() => void openNoteAttachment(note.id, attachment.id)}
            >
              {attachment.name}
            </button>
            <span className="shrink-0 text-[9px] uppercase tracking-wide text-muted-foreground">
              {attachment.kind === "vault" ? "Vault" : "External"}
            </span>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-6 w-6 shrink-0"
                  aria-label={`Actions for ${attachment.name}`}
                >
                  <Ellipsis size={14} />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-52">
                <DropdownMenuItem
                  onSelect={() => void openNoteAttachment(note.id, attachment.id)}
                >
                  <ExternalLink className="mr-2" size={14} />
                  Open in default app
                </DropdownMenuItem>
                <DropdownMenuItem
                  onSelect={() => void revealNoteAttachment(note.id, attachment.id)}
                >
                  <FolderSearch className="mr-2" size={14} />
                  Reveal in {fileManagerName}
                </DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  onSelect={() =>
                    void convertNoteAttachment(
                      note.id,
                      attachment.id,
                      attachment.kind === "vault" ? "external" : "copy",
                    )
                  }
                >
                  {attachment.kind === "vault" ? (
                    <ExternalLink className="mr-2" size={14} />
                  ) : (
                    <Copy className="mr-2" size={14} />
                  )}
                  {attachment.kind === "vault"
                    ? "Keep as external link"
                    : "Copy into vault"}
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </li>
        ))}
      </ul>
    </section>
  );
}
