import { describe, expect, it } from "vitest";
import { firstNoteImage, noteSnippet, type Note } from "./note-utils";

function note(content: string): Note {
  return {
    id: "note-1",
    path: "Documents/Tickets/example.md",
    content,
    pinned: false,
    updatedAt: "2026-08-16T00:00:00.000Z",
  };
}

describe("note image previews", () => {
  it("finds the first body image and strips an Obsidian width from its alt text", () => {
    expect(
      firstNoteImage(`---\ncover: ignored.png\n---\n# Ticket\n\n![Receipt|320](assets/receipt.png)`),
    ).toEqual({ path: "assets/receipt.png", alt: "Receipt" });
  });

  it("omits image markdown from the note snippet", () => {
    expect(
      noteSnippet(note("# Ticket\n\n![](assets/receipt.png)\n\nTravel receipt")),
    ).toBe("Travel receipt");
  });
});
