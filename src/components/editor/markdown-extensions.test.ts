import { EditorState } from "@codemirror/state";
import { describe, expect, it } from "vitest";
import {
  lineSelectionBetween,
  shouldFollowWikilink,
  titleLineFrom,
} from "./markdown-extensions";

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

describe("line selection", () => {
  it("stops before the following line break", () => {
    const state = EditorState.create({ doc: "First line\nSecond line" });
    const selection = lineSelectionBetween(state, 3);

    expect(selection.from).toBe(0);
    expect(selection.to).toBe("First line".length);
    expect(state.sliceDoc(selection.from, selection.to)).toBe("First line");
  });

  it("can drag across lines without selecting past the final line", () => {
    const state = EditorState.create({ doc: "First\nSecond\nThird" });
    const selection = lineSelectionBetween(state, 2, 9);

    expect(state.sliceDoc(selection.from, selection.to)).toBe("First\nSecond");
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
