import { EditorSelection, EditorState } from "@codemirror/state";
import { SearchQuery } from "@codemirror/search";
import { describe, expect, it } from "vitest";
import {
  editorSearchText,
  literalMatchRanges,
  searchMatchSummary,
} from "./find-in-note";

describe("Clean-mode search source", () => {
  it("maps visible literal Markdown to its escaped source", () => {
    expect(editorSearchText("**literal**", true)).toBe(
      "\\*\\*literal\\*\\*",
    );
    expect(editorSearchText("[label](url)", true)).toBe("\\[label](url)");
  });

  it("leaves prose and Markdown-aware queries unchanged", () => {
    expect(editorSearchText("ordinary text", true)).toBe("ordinary text");
    expect(editorSearchText("**source**", false)).toBe("**source**");
  });
});

describe("find in rendered table text", () => {
  it("finds every case-insensitive literal match", () => {
    expect(literalMatchRanges("Alpha beta ALPHA", "alpha")).toEqual([
      { from: 0, to: 5 },
      { from: 11, to: 16 },
    ]);
  });

  it("does not produce ranges for an empty query", () => {
    expect(literalMatchRanges("table text", "")).toEqual([]);
  });
});

describe("find match summary", () => {
  const query = new SearchQuery({ search: "alpha" });

  it("shows the total while no match is selected", () => {
    const state = EditorState.create({ doc: "alpha beta alpha" });

    expect(searchMatchSummary(state, query)).toEqual({
      current: null,
      total: 2,
      label: "2 matches",
    });
  });

  it("shows the current position after navigating to a match", () => {
    const state = EditorState.create({
      doc: "alpha beta alpha",
      selection: EditorSelection.single(11, 16),
    });

    expect(searchMatchSummary(state, query)).toEqual({
      current: 2,
      total: 2,
      label: "2 of 2",
    });
  });

  it("shows zero for an empty query", () => {
    const state = EditorState.create({ doc: "alpha" });

    expect(searchMatchSummary(state, new SearchQuery({ search: "" }))).toEqual({
      current: null,
      total: 0,
      label: "0 matches",
    });
  });
});
