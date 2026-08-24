import { describe, expect, it } from "vitest";
import {
  firstNoteImage,
  getOutgoingLinkTitles,
  noteMatchesSearch,
  noteSnippet,
  noteTitle,
  type Note,
} from "./note-utils";

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

describe("escaped Markdown in derived note text", () => {
  it("keeps a literal heading marker in the title without its storage escape", () => {
    expect(noteTitle(note("\\# Literal title\n\nBody"))).toBe(
      "# Literal title",
    );
  });

  it("keeps literal punctuation in snippets while removing real formatting", () => {
    expect(
      noteSnippet(
        note("# Title\n\n\\*\\*literal\\*\\* and **formatted**"),
      ),
    ).toBe("**literal** and formatted");
  });

  it("matches visible literal text without requiring source escapes", () => {
    expect(
      noteMatchesSearch(note("# Title\n\n\\*\\*literal\\*\\*"), "**literal**"),
    ).toBe(true);
  });

  it("keeps wikilinks created by the older escaped typing behavior active", () => {
    expect(getOutgoingLinkTitles("Open \\[\\[Project Atlas]]")).toEqual([
      "Project Atlas",
    ]);
  });
});
