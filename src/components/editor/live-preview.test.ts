import { EditorSelection, EditorState } from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { describe, expect, it } from "vitest";
import {
  livePreviewExtension,
  externalLinkAt,
  listItemIndentEm,
  listItemPrefixOffsetEm,
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
    ["[**label**](https://example.com)", 8, 32],
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

  it("does not treat a Markdown destination without http(s) as a live link", () => {
    const state = createState("[label](example.com)");
    const selection = EditorSelection.single(6);

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
    [
      "Read [standards](https://weldnote.com) today",
      8,
      "https://weldnote.com/",
    ],
    ["Visit https://example.com/docs today", 12, "https://example.com/docs"],
    ["Visit http://example.com/docs today", 12, "http://example.com/docs"],
  ])("finds a link in %s", (doc, pos, expected) => {
    expect(externalLinkAt(createState(doc), pos)?.url).toBe(expected);
  });

  it.each([
    ["Visit weldnote.com today", 10],
    ["Visit www.weldnote.com today", 12],
    ["Read [standards](weldnote.com) today", 8],
  ])("does not infer a link without http(s) in %s", (doc, pos) => {
    expect(externalLinkAt(createState(doc), pos)).toBeNull();
  });

  it.each([
    "![logo](https://example.com/logo.png)",
    "![Apple Notes image](assets/apple-notes/p33/002.jpg)",
  ])("does not treat any part of image Markdown as a link in %s", (doc) => {
    const state = createState(doc);

    for (let pos = 0; pos <= doc.length; pos += 1) {
      expect(externalLinkAt(state, pos)).toBeNull();
    }
  });

  it("does not auto-link a bare domain used as the note title", () => {
    const state = createState("# start.gg\n\nhttps://www.start.gg/");

    expect(externalLinkAt(state, 5)).toBeNull();
    expect(externalLinkAt(state, 20)?.url).toBe("https://www.start.gg/");
  });
});

describe("list item indentation", () => {
  it("gives the first nesting level a clearly visible step", () => {
    expect(listItemIndentEm(4, "-", false)).toBeCloseTo(2.9);
    expect(listItemPrefixOffsetEm(4, "-", false)).toBe(1.8);
  });

  it("keeps later nesting steps even after the larger first step", () => {
    expect(listItemIndentEm(8, "-", false)).toBeCloseTo(3.9);
    expect(listItemIndentEm(12, "-", false)).toBeCloseTo(4.9);
  });

  it("preserves marker-specific spacing", () => {
    expect(listItemIndentEm(0, "-", false)).toBe(0.8);
    expect(listItemIndentEm(0, "10.", false)).toBeCloseTo(1.65);
    expect(listItemIndentEm(0, "-", true)).toBe(1.35);
  });
});
