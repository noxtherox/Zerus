import { EditorState } from "@codemirror/state";
import { describe, expect, it } from "vitest";
import { shouldFollowWikilink, titleLineFrom } from "./markdown-extensions";

describe("note title line", () => {
  it("uses the first line for a normal note", () => {
    const state = EditorState.create({ doc: "My title\nBody" });

    expect(titleLineFrom(state)).toBe(0);
  });

  it("matches the first non-empty line used by noteTitle", () => {
    const state = EditorState.create({ doc: "  \n\n# My title\nBody" });

    expect(titleLineFrom(state)).toBe(4);
  });

  it("keeps an empty note ready for title-sized typing", () => {
    const state = EditorState.create({ doc: "" });

    expect(titleLineFrom(state)).toBe(0);
  });
});

describe("wikilink activation", () => {
  it("uses a normal tap when mobile link activation is enabled", () => {
    expect(
      shouldFollowWikilink({ button: 0, metaKey: false, ctrlKey: false }, true),
    ).toBe(true);
  });

  it("keeps modifier-click behavior on desktop", () => {
    expect(
      shouldFollowWikilink({ button: 0, metaKey: false, ctrlKey: false }),
    ).toBe(false);
    expect(
      shouldFollowWikilink({ button: 0, metaKey: true, ctrlKey: false }),
    ).toBe(true);
  });

  it("does not follow a link from a secondary click", () => {
    expect(
      shouldFollowWikilink({ button: 2, metaKey: true, ctrlKey: false }, true),
    ).toBe(false);
  });
});
