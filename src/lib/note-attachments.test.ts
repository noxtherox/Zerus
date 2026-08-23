import { describe, expect, it } from "vitest";
import {
  formatAttachmentMarkdown,
  getNoteAttachments,
  isImageAttachmentPath,
  setNoteAttachments,
  type NoteAttachment,
  upsertNoteAttachment,
} from "./note-attachments";
import { noteBody } from "./frontmatter";

const external: NoteAttachment = {
  id: "attachment-1",
  name: "project brief.pdf",
  kind: "external",
  managed: false,
};

describe("note attachments", () => {
  it("stores multiple attachments in frontmatter without changing the body", () => {
    const vault: NoteAttachment = {
      id: "attachment-2",
      name: "research.zip",
      kind: "vault",
      path: "inbox/research.zip",
      managed: true,
    };
    const content = setNoteAttachments("# Plan\n\nText", [external, vault]);

    expect(noteBody(content)).toBe("# Plan\n\nText");
    expect(getNoteAttachments(content)).toEqual([external, vault]);
  });

  it("updates an attachment in place and removes the property when empty", () => {
    const content = setNoteAttachments("# Plan", [external]);
    const converted = upsertNoteAttachment(content, {
      ...external,
      kind: "vault",
      path: "inbox/project brief.pdf",
      managed: true,
    });

    expect(getNoteAttachments(converted)[0]).toMatchObject({
      kind: "vault",
      path: "inbox/project brief.pdf",
    });
    expect(setNoteAttachments(converted, [])).toBe("# Plan");
  });

  it("formats a portable inline attachment link", () => {
    expect(formatAttachmentMarkdown(external)).toBe(
      "[project brief.pdf](zerus-attachment:attachment-1)",
    );
  });

  it("keeps image drops in the existing image flow", () => {
    expect(isImageAttachmentPath("/tmp/photo.HEIC")).toBe(true);
    expect(isImageAttachmentPath("/tmp/archive.zip")).toBe(false);
  });
});
