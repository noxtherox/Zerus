import { EditorSelection, EditorState } from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { describe, expect, it } from "vitest";
import {
  livePreviewExtension,
  externalLinkAt,
  listItemIndentEm,
  moveCursorPastClosingMarkup,
} from "./live-preview";

function createState(doc: string) {
  return EditorState.create({
    doc,
    extensions: [
      markdown({ base: markdownLanguage, extensions: GFM }),
      livePreviewExtension(),
    ],
  });
}

describe("live preview cursor placement", () => {
  it.each([
    ["**bold**", 6, 8],
    ["*italic*", 7, 8],
    ["~~struck~~", 8, 10],
    ["`code`", 5, 6],
    ["[label](https://example.com)", 6, 28],
    ["***both***", 7, 10],
    ["[**label**](url)", 8, 16],
  ])(
    "moves a cursor before the closing syntax in %s past the construct",
    (doc, cursor, expected) => {
      const state = createState(doc);
      const selection = EditorSelection.single(cursor);

      expect(moveCursorPastClosingMarkup(state, selection).main.head).toBe(
        expected,
      );
    },
  );

  it("does not change a text selection ending at the closing marker", () => {
    const state = createState("**bold**");
    const selection = EditorSelection.create([EditorSelection.range(2, 6)]);

    expect(moveCursorPastClosingMarkup(state, selection)).toBe(selection);
  });

  it("does not move a cursor within ordinary text", () => {
    const state = createState("plain text");
    const selection = EditorSelection.single(5);

    expect(moveCursorPastClosingMarkup(state, selection)).toBe(selection);
  });

  it("applies the correction to editor selection transactions", () => {
    const state = createState("**bold**");
    const transaction = state.update({ selection: { anchor: 6 } });

    expect(transaction.state.selection.main.head).toBe(8);
  });
});

describe("external links", () => {
  it.each([
    ["Read [standards](weldnote.com) today", 8, "https://weldnote.com/"],
    ["Visit https://example.com/docs today", 12, "https://example.com/docs"],
    ["Visit weldnote.com today", 10, "https://weldnote.com/"],
  ])("finds a link in %s", (doc, pos, expected) => {
    expect(externalLinkAt(createState(doc), pos)?.url).toBe(expected);
  });

  it("does not treat an image destination as a clickable text link", () => {
    expect(
      externalLinkAt(createState("![logo](https://example.com/logo.png)"), 3),
    ).toBeNull();
  });

  it("does not auto-link a bare domain used as the note title", () => {
    const state = createState("# start.gg\n\nhttps://www.start.gg/");

    expect(externalLinkAt(state, 5)).toBeNull();
    expect(externalLinkAt(state, 20)?.url).toBe("https://www.start.gg/");
  });
});

describe("list item indentation", () => {
  it("aligns wrapped nested bullet text with the first line", () => {
    expect(listItemIndentEm(4, "-", false)).toBe(1.8);
  });

  it("preserves marker-specific spacing", () => {
    expect(listItemIndentEm(0, "-", false)).toBe(0.8);
    expect(listItemIndentEm(0, "10.", false)).toBeCloseTo(1.65);
    expect(listItemIndentEm(0, "-", true)).toBe(1.35);
  });
});
