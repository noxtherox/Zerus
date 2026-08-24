import { EditorSelection, EditorState, type Transaction } from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { history, redo, undo, undoDepth } from "@codemirror/commands";
import { describe, expect, it, vi } from "vitest";
import {
  continueOrExitMarkdown,
  deleteBeforeEscapedMarkdownSymbolBackward,
  deleteEscapedMarkdownSymbolBackward,
  deleteEscapedMarkdownSymbolForward,
  deleteImageBackward,
  deleteInlineTagMarkerBackward,
  exitEmptyFencedCodeBlock,
  literalMarkdownSymbolTyping,
  markdownEditingMechanics,
  typedMarkdownEscapePositions,
} from "./editing-mechanics";

function pressEnter(doc: string): { handled: boolean; state: EditorState } {
  let state = EditorState.create({
    doc,
    selection: { anchor: doc.length },
    extensions: [
      markdown({ base: markdownLanguage, extensions: GFM }),
    ],
  });
  const handled = continueOrExitMarkdown({
    state,
    dispatch: (transaction: Transaction) => {
      state = transaction.state;
    },
  });
  return { handled, state };
}

function pressBackspace(doc: string, cursor = doc.length) {
  let state = EditorState.create({
    doc,
    selection: { anchor: cursor },
    extensions: [markdown({ base: markdownLanguage, extensions: GFM })],
  });
  const handled = exitEmptyFencedCodeBlock({
    state,
    dispatch: (transaction: Transaction) => {
      state = transaction.state;
    },
  });
  return { handled, state };
}

function deleteInlineTagMarker(doc: string, cursor: number) {
  let state = EditorState.create({
    doc,
    selection: { anchor: cursor },
    extensions: [markdown({ base: markdownLanguage, extensions: GFM })],
  });
  const handled = deleteInlineTagMarkerBackward({
    state,
    dispatch: (transaction: Transaction) => {
      state = transaction.state;
    },
  });
  return { handled, state };
}

function deleteEscapedSymbol(doc: string, cursor = doc.length) {
  let state = EditorState.create({
    doc,
    selection: { anchor: cursor },
  });
  const handled = deleteEscapedMarkdownSymbolBackward({
    state,
    dispatch: (transaction: Transaction) => {
      state = transaction.state;
    },
  });
  return { handled, state };
}

function runDeleteCommand(
  command: typeof deleteEscapedMarkdownSymbolBackward,
  doc: string,
  cursor: number,
) {
  let state = EditorState.create({ doc, selection: { anchor: cursor } });
  const handled = command({
    state,
    dispatch: (transaction: Transaction) => {
      state = transaction.state;
    },
  });
  return { handled, state };
}

function deleteImage(doc: string, cursor: number) {
  let state = EditorState.create({
    doc,
    selection: { anchor: cursor },
    extensions: [markdown({ base: markdownLanguage, extensions: GFM })],
  });
  const handled = deleteImageBackward({
    state,
    dispatch: (transaction: Transaction) => {
      state = transaction.state;
    },
  });
  return { handled, state };
}

describe("Markdown Enter behavior", () => {
  it.each([
    ["- item", "- item\n- "],
    ["1. item", "1. item\n2. "],
    ["- [ ] task", "- [ ] task\n- [ ] "],
    ["- [x] done", "- [x] done\n- [ ] "],
    ["> quote", "> quote\n> "],
  ])("continues a non-empty structure in %s", (doc, expected) => {
    const result = pressEnter(doc);
    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe(expected);
  });

  it.each([
    ["- ", ""],
    ["- one\n- ", "- one\n"],
    ["1. ", ""],
    ["1. one\n2. ", "1. one\n"],
    ["- [ ] ", ""],
    ["- [ ] one\n- [ ] ", "- [ ] one\n"],
    ["> ", ""],
    ["> quote\n> ", "> quote\n"],
    ["> > ", "> "],
  ])("exits an empty structure in %s", (doc, expected) => {
    const result = pressEnter(doc);
    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe(expected);
  });

  it("leaves ordinary text to the default Enter command", () => {
    expect(pressEnter("plain text").handled).toBe(false);
  });

  it.each([
    ["```", "```\n\n```", 4],
    ["```ts", "```ts\n\n```", 6],
    ["  ~~~js", "  ~~~js\n  \n  ~~~", 10],
  ])("confirms and closes the code fence in %s", (doc, expected, cursor) => {
    const result = pressEnter(doc);
    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe(expected);
    expect(result.state.selection.main.head).toBe(cursor);
  });

  it("does not treat an existing closing fence as a new opening", () => {
    expect(pressEnter("```\ncode\n```").handled).toBe(false);
  });

  it("returns an empty auto-closed code block to its literal fence", () => {
    const result = pressBackspace("```ts\n\n```", 6);
    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe("```ts");
    expect(result.state.selection.main.head).toBe(5);
  });

  it("does not exit a code block that contains text", () => {
    expect(pressBackspace("```\ncode\n```", 8).handled).toBe(false);
  });

  it("undoes and redoes code-fence confirmation as one action", () => {
    let state = EditorState.create({
      doc: "```",
      selection: { anchor: 3 },
      extensions: [
        markdown({ base: markdownLanguage, extensions: GFM }),
        history(),
      ],
    });
    const target = {
      get state() {
        return state;
      },
      dispatch(transaction: Transaction) {
        state = transaction.state;
      },
    };

    expect(continueOrExitMarkdown(target)).toBe(true);
    expect(undoDepth(state)).toBe(1);
    expect(undo(target)).toBe(true);
    expect(state.doc.toString()).toBe("```");
    expect(redo(target)).toBe(true);
    expect(state.doc.toString()).toBe("```\n\n```");
  });

  it("undoes exiting an empty code area without losing its source", () => {
    let state = EditorState.create({
      doc: "```\n\n```",
      selection: { anchor: 4 },
      extensions: [
        markdown({ base: markdownLanguage, extensions: GFM }),
        history(),
      ],
    });
    const target = {
      get state() {
        return state;
      },
      dispatch(transaction: Transaction) {
        state = transaction.state;
      },
    };

    expect(exitEmptyFencedCodeBlock(target)).toBe(true);
    expect(state.doc.toString()).toBe("```");
    expect(undo(target)).toBe(true);
    expect(state.doc.toString()).toBe("```\n\n```");
  });
});

describe("Markdown Backspace boundaries", () => {
  it.each([
    ["\\#", ""],
    ["\\*", ""],
    ["\\_", ""],
    ["\\[", ""],
    ["before \\#", "before "],
    ["\\\\", ""],
  ])("deletes an escaped visible symbol atomically in %s", (doc, expected) => {
    const result = deleteEscapedSymbol(doc);

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe(expected);
    expect(result.state.selection.main.head).toBe(expected.length);
  });

  it("deletes only one visible backslash from a repeated run", () => {
    const result = deleteEscapedSymbol("\\\\\\\\");

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe("\\\\");
    expect(result.state.selection.main.head).toBe(2);
  });

  it.each(["#", "plain", "\\a"])(
    "leaves unescaped or non-Markdown text alone in %s",
    (doc) => {
      expect(deleteEscapedSymbol(doc).handled).toBe(false);
    },
  );

  it("deletes the preceding visible letter from after a hidden escape", () => {
    const result = runDeleteCommand(
      deleteBeforeEscapedMarkdownSymbolBackward,
      "Hello\\*",
      6,
    );

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe("Hell\\*");
    expect(result.state.selection.main.head).toBe(4);
  });

  it("deletes the complete preceding escaped symbol at a shared boundary", () => {
    const result = runDeleteCommand(
      deleteBeforeEscapedMarkdownSymbolBackward,
      "\\*\\*",
      3,
    );

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe("\\*");
    expect(result.state.selection.main.head).toBe(0);
  });

  it.each([5, 6])(
    "forward-deletes an escaped symbol from source boundary %i",
    (cursor) => {
      const result = runDeleteCommand(
        deleteEscapedMarkdownSymbolForward,
        "Hello\\*",
        cursor,
      );

      expect(result.handled).toBe(true);
      expect(result.state.doc.toString()).toBe("Hello");
      expect(result.state.selection.main.head).toBe(5);
    },
  );

  it("removes escape residue when native Backspace deletes only the former heading marker", () => {
    const doc = "\\#**Hello**";
    const state = EditorState.create({
      doc,
      selection: { anchor: 2 },
      extensions: [markdownEditingMechanics],
    });

    const transaction = state.update({
      changes: { from: 1, to: 2 },
      selection: { anchor: 1 },
      userEvent: "delete.backward",
    });

    expect(transaction.state.doc.toString()).toBe("**Hello**");
    expect(transaction.state.selection.main.head).toBe(0);
  });

  it("preserves a real backslash pair when deleting a following raw hash", () => {
    const state = EditorState.create({
      doc: "\\\\#**Hello**",
      selection: { anchor: 3 },
      extensions: [markdownEditingMechanics],
    });
    const transaction = state.update({
      changes: { from: 2, to: 3 },
      selection: { anchor: 2 },
      userEvent: "delete.backward",
    });

    expect(transaction.state.doc.toString()).toBe("\\\\**Hello**");
  });

  it("deletes a standalone image from its visual after-image caret", () => {
    const image = "![dashboard](assets/dashboard.png)";
    const result = deleteImage(`${image}\nFollowing text`, image.length);

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe("\nFollowing text");
    expect(result.state.selection.main.head).toBe(0);
  });

  it("deletes a standalone image from the caret immediately below it", () => {
    const image = "![dashboard](assets/dashboard.png)";
    const result = deleteImage(`${image}\n\n- first item`, image.length + 1);

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe("\n- first item");
    expect(result.state.selection.main.head).toBe(0);
  });

  it("deletes an image without merging the following text into its line", () => {
    const image = "![](assets/photo.png)";
    const result = deleteImage(`${image}\nFollowing text`, image.length + 1);

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe("Following text");
    expect(result.state.selection.main.head).toBe(0);
  });

  it.each([
    ["Before\n![](assets/photo.png)\n\nAfter", "Before\n\nAfter"],
    ["Before\n![](assets/photo.png)\nAfter", "Before\nAfter"],
  ])("preserves text before and after an image in %s", (doc, expected) => {
    const cursor = doc.indexOf("\n", doc.indexOf("![](")) + 1;
    const result = deleteImage(doc, cursor);

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe(expected);
    expect(result.state.selection.main.head).toBe("Before\n".length);
  });

  it("leaves other Backspace boundaries alone", () => {
    const image = "![](assets/photo.png)";
    expect(deleteImage(`${image}\nFollowing text`, image.length + 2).handled).toBe(false);

    for (const doc of [
      "Caption ![](assets/photo.png)\nFollowing text",
      "Plain text\nFollowing text",
    ]) {
      expect(deleteImage(doc, doc.indexOf("\n") + 1).handled).toBe(false);
    }
  });

  it("deletes the inline-tag marker after a heading loses its space", () => {
    const result = deleteInlineTagMarker("#Hello", 1);

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe("Hello");
    expect(result.state.selection.main.head).toBe(0);
  });

  it("deletes a former heading marker without changing bold text", () => {
    const result = deleteInlineTagMarker("#**Hello**", 1);

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe("**Hello**");
    expect(result.state.selection.main.head).toBe(0);
  });

  it("deletes an escaped former heading marker without consuming bold syntax", () => {
    const result = deleteInlineTagMarker("\\#**Hello**", 2);

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe("**Hello**");
    expect(result.state.selection.main.head).toBe(0);
  });

  it("deletes a lone visible escaped heading marker atomically", () => {
    const result = deleteInlineTagMarker("\\#", 2);

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe("");
    expect(result.state.selection.main.head).toBe(0);
  });

  it("preserves a real backslash pair before a former heading marker", () => {
    const result = deleteInlineTagMarker("\\\\#**Hello**", 3);

    expect(result.handled).toBe(true);
    expect(result.state.doc.toString()).toBe("\\\\**Hello**");
    expect(result.state.selection.main.head).toBe(2);
  });

  it.each([2, 3, 4])(
    "removes an escaped heading when its visual caret resolves to source position %i",
    (cursor) => {
      const result = deleteInlineTagMarker("\\#**Hello**", cursor);

      expect(result.handled).toBe(true);
      expect(result.state.doc.toString()).toBe("**Hello**");
      expect(result.state.selection.main.head).toBe(0);
    },
  );

  it.each([
    ["before#Hello", 7],
    ["# Hello", 1],
    ["#-not-a-tag", 1],
    ["#Hello", 2],
  ])("leaves unrelated Backspace positions alone in %s", (doc, cursor) => {
    expect(deleteInlineTagMarker(doc, cursor).handled).toBe(false);
  });
});

describe("literal Markdown symbol typing", () => {
  const typeLiterally = (text: string) => {
    const state = EditorState.create({
      extensions: [literalMarkdownSymbolTyping(() => false)],
    });
    return state.update({
      changes: { from: 0, insert: text },
      selection: { anchor: text.length },
      userEvent: "input.type",
    }).state;
  };

  it.each([
    ["# heading", "\\# heading"],
    ["**bold**", "\\*\\*bold\\*\\*"],
    ["_italic_", "\\_italic\\_"],
    ["- item", "\\- item"],
    ["+ item", "\\+ item"],
    ["1. item", "1\\. item"],
    ["> quote", "\\> quote"],
    ["---", "--\\-"],
    ["Title\n---", "Title\n\\---"],
    ["Title\n===", "Title\n\\==="],
    ["`code`", "\\`code\\`"],
    ["~~strikethrough~~", "\\~\\~strikethrough\\~\\~"],
    ["[link](url)", "\\[link](url)"],
    ["![image](path)", "\\!\\[image](path)"],
    ["| table |", "\\| table \\|"],
    ["cell|cell", "cell\\|cell"],
    ["<https://example.com>", "\\<https://example.com>"],
    ["#tag", "#tag"],
    ["[[Note]]", "[[Note]]"],
  ])("keeps Markdown syntax literal in %s", (typed, expected) => {
    expect(typeLiterally(typed).doc.toString()).toBe(expected);
  });

  it.each([
    "https://example.com/a-b_(draft)",
    "Version 1.2 (draft).",
    "192.168.1.1",
    "report-final.md",
  ])("preserves ordinary URL and prose punctuation in %s", (typed) => {
    expect(typeLiterally(typed).doc.toString()).toBe(typed);
  });

  it("supports multiple typed selections in the same transaction", () => {
    const state = EditorState.create({
      doc: "left right",
      selection: EditorSelection.create([
        EditorSelection.cursor(4),
        EditorSelection.cursor(10),
      ]),
      extensions: [literalMarkdownSymbolTyping(() => false)],
    });
    const transaction = state.update({
      changes: [
        { from: 0, insert: "*" },
        { from: 5, insert: "*" },
      ],
      userEvent: "input.type",
    });

    expect(transaction.state.doc.toString()).toBe("\\*left \\*right");
  });

  it.each([
    ["#tag", "#tag"],
    ["[[Note]]", "[[Note]]"],
  ])("keeps Zerus navigation syntax active in %s", (typed, expected) => {
    let state = EditorState.create({
      extensions: [literalMarkdownSymbolTyping(() => false)],
    });
    for (const character of typed) {
      state = state.update({
        changes: { from: state.doc.length, insert: character },
        selection: { anchor: state.doc.length + 1 },
        userEvent: "input.type",
      }).state;
    }
    expect(state.doc.toString()).toBe(expected);
  });

  it("undoes the typed symbol and its protective escape together", () => {
    let state = EditorState.create({
      extensions: [
        history(),
        literalMarkdownSymbolTyping(() => false),
      ],
    });
    state = state.update({
      changes: { from: 0, insert: "*" },
      userEvent: "input.type",
    }).state;
    const target = {
      get state() {
        return state;
      },
      dispatch(transaction: Transaction) {
        state = transaction.state;
      },
    };

    expect(state.doc.toString()).toBe("\\*");
    expect(undo(target)).toBe(true);
    expect(state.doc.toString()).toBe("");
  });

  it("leaves typed symbols and pasted Markdown alone when enabled or pasted", () => {
    const enabled = EditorState.create({
      extensions: [literalMarkdownSymbolTyping(() => true)],
    }).update({
      changes: { from: 0, insert: "*" },
      userEvent: "input.type",
    }).state;
    const literalState = EditorState.create({
      extensions: [literalMarkdownSymbolTyping(() => false)],
    });
    const pasted = literalState.update({
      changes: { from: 0, insert: "*" },
      userEvent: "input.paste",
    }).state;

    expect(enabled.doc.toString()).toBe("*");
    expect(pasted.doc.toString()).toBe("*");
  });

  it("reports contextual escape positions without escaping URL punctuation", () => {
    const document = EditorState.create({
      doc: "- item https://example.com",
    }).doc;

    expect(typedMarkdownEscapePositions(document, 0, document.length)).toEqual([
      0,
    ]);
  });
});
