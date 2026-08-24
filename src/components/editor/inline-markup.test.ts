import { describe, expect, it } from "vitest";
import { EditorState } from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { enclosingInlineMarkup, inlineMarkupEdit } from "./inline-markup";

function markdownState(doc: string): EditorState {
  return EditorState.create({
    doc,
    extensions: [markdown({ base: markdownLanguage, extensions: GFM })],
  });
}

describe("inlineMarkupEdit", () => {
  it.each([
    ["**", "bold"],
    ["*", "italic"],
    ["~~", "strikethrough"],
  ])("keeps a selected line's newline outside %s markup", (marker) => {
    const edit = inlineMarkupEdit("Full line\n", marker, "placeholder");

    expect(edit.insert).toBe(`${marker}Full line${marker}\n`);
    expect(edit.selectionFrom).toBe(marker.length);
    expect(edit.selectionTo).toBe(marker.length + "Full line".length);
  });

  it("keeps a list prefix outside inline markup", () => {
    const edit = inlineMarkupEdit("  - Full list item\n", "**", "bold text");

    expect(edit.insert).toBe("  - **Full list item**\n");
    expect(edit.selectionFrom).toBe(6);
    expect(edit.selectionTo).toBe(20);
  });

  it("removes markup from a fully selected formatted list line", () => {
    const edit = inlineMarkupEdit("- **Full list item**\n", "**", "bold text");

    expect(edit.insert).toBe("- Full list item\n");
    expect(edit.selectionFrom).toBe(2);
    expect(edit.selectionTo).toBe(16);
  });

  it("retains the placeholder behavior for an empty selection", () => {
    expect(inlineMarkupEdit("", "**", "bold text")).toEqual({
      insert: "**bold text**",
      selectionFrom: 2,
      selectionTo: 11,
    });
  });
});

describe("enclosingInlineMarkup", () => {
  it.each([
    ["before **bold text** after", 9, 18, "**", [7, 9, 18, 20]],
    ["before **bold text** after", 13, 13, "**", [7, 9, 18, 20]],
    ["before *italic text* after", 12, 12, "*", [7, 8, 19, 20]],
    ["before ~~strike~~ after", 11, 11, "~~", [7, 9, 15, 17]],
    ["before `code` after", 10, 10, "`", [7, 8, 12, 13]],
  ] as const)(
    "finds %s formatting around the selection",
    (doc, from, to, marker, expected) => {
      const result = enclosingInlineMarkup(markdownState(doc), from, to, marker);
      expect(result).toEqual({
        openingFrom: expected[0],
        openingTo: expected[1],
        closingFrom: expected[2],
        closingTo: expected[3],
      });
    },
  );

  it("distinguishes nested bold and italic formatting", () => {
    const state = markdownState("***both***");

    expect(enclosingInlineMarkup(state, 3, 7, "**")).toEqual({
      openingFrom: 1,
      openingTo: 3,
      closingFrom: 7,
      closingTo: 9,
    });
    expect(enclosingInlineMarkup(state, 3, 7, "*")).toEqual({
      openingFrom: 0,
      openingTo: 1,
      closingFrom: 9,
      closingTo: 10,
    });
  });

  it("does not remove formatting from an unformatted selection", () => {
    expect(enclosingInlineMarkup(markdownState("plain text"), 0, 5, "**"))
      .toBeNull();
  });
});
