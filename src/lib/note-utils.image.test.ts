import { describe, expect, it } from "vitest";
import {
  firstNoteImagePath,
  noteSnippet,
  type Note,
} from "./note-utils";

function note(content: string): Note {
  return {
    id: "note-1",
    path: "inbox/example.md",
    content,
    pinned: false,
    updatedAt: "2026-08-16T12:00:00.000Z",
  };
}

describe("note image previews", () => {
  it("returns the first image in the note body", () => {
    expect(
      firstNoteImagePath(
        note("# Trip\n\n![Cover|640](assets/cover.jpg)\n\n![](assets/map.png)"),
      ),
    ).toBe("assets/cover.jpg");
  });

  it("ignores image-like frontmatter values", () => {
    expect(
      firstNoteImagePath(
        note("---\ncover: '![](assets/frontmatter.jpg)'\n---\n# No body image"),
      ),
    ).toBeNull();
  });

  it("does not expose image markdown in the text snippet", () => {
    expect(
      noteSnippet(
        note("# Trip\n\n![](assets/cover.jpg)\n\nNotes from the coast."),
      ),
    ).toBe("Notes from the coast.");
  });
});
