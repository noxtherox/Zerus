import { getNoteProperties, setContentProperty } from "@/lib/frontmatter";
import type { Note } from "@/lib/note-utils";

export const ATTACHMENTS_PROPERTY = "zerus-attachments";
export const ATTACHMENT_LINK_REGEX =
  /\[([^\]]+)\]\(zerus-attachment:([a-zA-Z0-9-]+)\)/g;
const IMAGE_FILE_PATTERN =
  /\.(?:apng|avif|bmp|gif|heic|heif|ico|jfif|jpe?g|jxl|png|svg|tiff?|webp)$/i;

export type NoteAttachmentKind = "vault" | "external";

export interface NoteAttachment {
  id: string;
  name: string;
  kind: NoteAttachmentKind;
  /** Vault-relative path. External paths stay in the device-local mapping. */
  path?: string;
  /** True when Zerus made the vault copy. */
  managed: boolean;
}

export function isImageAttachmentPath(path: string): boolean {
  return IMAGE_FILE_PATTERN.test(path);
}

function isAttachment(value: unknown): value is NoteAttachment {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<NoteAttachment>;
  return (
    typeof candidate.id === "string" &&
    !!candidate.id &&
    typeof candidate.name === "string" &&
    !!candidate.name &&
    (candidate.kind === "vault" || candidate.kind === "external") &&
    typeof candidate.managed === "boolean" &&
    (candidate.path === undefined || typeof candidate.path === "string") &&
    (candidate.kind !== "vault" || !!candidate.path)
  );
}

export function getNoteAttachments(
  noteOrContent: Note | string,
): NoteAttachment[] {
  const content =
    typeof noteOrContent === "string" ? noteOrContent : noteOrContent.content;
  const value = getNoteProperties(content)[ATTACHMENTS_PROPERTY];
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const attachments: NoteAttachment[] = [];
  for (const item of value) {
    try {
      const parsed: unknown = JSON.parse(item);
      if (!isAttachment(parsed) || seen.has(parsed.id)) continue;
      seen.add(parsed.id);
      attachments.push(parsed);
    } catch {
      // Ignore malformed entries without disturbing the rest of the note.
    }
  }
  return attachments;
}

export function setNoteAttachments(
  content: string,
  attachments: NoteAttachment[],
): string {
  return setContentProperty(
    content,
    ATTACHMENTS_PROPERTY,
    attachments.length
      ? attachments.map((attachment) => JSON.stringify(attachment))
      : null,
  );
}

export function upsertNoteAttachment(
  content: string,
  attachment: NoteAttachment,
): string {
  const current = getNoteAttachments(content);
  const index = current.findIndex((candidate) => candidate.id === attachment.id);
  const next = [...current];
  if (index < 0) next.push(attachment);
  else next[index] = attachment;
  return setNoteAttachments(content, next);
}

export function formatAttachmentMarkdown(attachment: NoteAttachment): string {
  const label = attachment.name.replace(/[[\]]/g, "");
  return `[${label}](zerus-attachment:${attachment.id})`;
}
