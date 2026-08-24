import { describe, expect, it } from "vitest";
import { EditorState, Transaction } from "@codemirror/state";
import {
  history,
  isolateHistory,
  redo,
  undo,
  undoDepth,
} from "@codemirror/commands";
import type { EditorView } from "@codemirror/view";
import {
  applyPasteChoice,
  escapeMarkdownPlainText,
  joinEditorHistoryEvent,
  looksLikeMarkdown,
  pasteHistoryStart,
  pasteHistoryTracking,
  pasteChoices,
  type PasteChoiceSession,
} from "./paste-options";

describe("paste option detection", () => {
  it.each([
    "# Heading",
    "- list item",
    "1. ordered item",
    "> quoted text",
    "- [ ] task",
    "**bold**",
    "*italic*",
    "_also italic_",
    "~~deleted~~",
    "Use `code` here",
    "[Zerus](https://example.com)",
    "```ts\nconst answer = 42;\n```",
    "| Name | Status |\n| --- | --- |\n| Zerus | Ready |",
  ])("recognizes meaningful Markdown in %s", (value) => {
    expect(looksLikeMarkdown(value)).toBe(true);
  });

  it.each([
    "A normal sentence.",
    "https://example.com/docs",
    "Price: 10 * 4",
    "#hashtag",
    "1.5 is a decimal",
    "Use [brackets] normally",
  ])("does not offer Markdown interpretation for %s", (value) => {
    expect(looksLikeMarkdown(value)).toBe(false);
  });

  it("keeps Markdown-looking plain text literal by default", () => {
    const result = pasteChoices({ plainText: "# Heading" });

    expect(result.defaultText).toBe("\\# Heading");
    expect(result.choices.map(({ mode }) => mode)).toEqual([
      "source",
      "markdown",
    ]);
    expect(result.choices[1].text).toBe("# Heading");
  });

  it("suppresses the menu when plain text has no meaningful interpretation", () => {
    expect(pasteChoices({ plainText: "A normal sentence." })).toEqual({
      defaultText: "A normal sentence.",
      choices: [],
    });
  });

  it("preserves Markdown copied within Zerus by default", () => {
    const result = pasteChoices({
      plainText: "bold",
      html: "<strong>bold</strong>",
      internalMarkdown: "**bold**",
    });

    expect(result.defaultText).toBe("**bold**");
    expect(result.choices.map(({ mode }) => mode)).toEqual([
      "source",
      "plain",
    ]);
    expect(result.choices[1].text).toBe("bold");
  });

  it("does not show options for internally copied unformatted text", () => {
    expect(
      pasteChoices({
        plainText: "A normal sentence.",
        html: "<p>A normal sentence.</p>",
        internalMarkdown: "A normal sentence.",
      }),
    ).toEqual({
      defaultText: "A normal sentence.",
      choices: [],
    });
  });
});

describe("literal Markdown escaping", () => {
  it.each([
    ["# Heading", "\\# Heading"],
    ["- item", "\\- item"],
    ["12. item", "12\\. item"],
    ["> quotation", "\\> quotation"],
    ["**bold**", "\\*\\*bold\\*\\*"],
    ["Use `code`", "Use \\`code\\`"],
    ["~~deleted~~", "\\~\\~deleted\\~\\~"],
    ["[label](https://example.com)", "\\[label](https://example.com)"],
    ["<strong>text</strong>", "\\<strong>text\\</strong>"],
  ])("escapes %s without changing its visible text", (source, expected) => {
    expect(escapeMarkdownPlainText(source)).toBe(expected);
  });
});

function historyHarness() {
  let state = EditorState.create({
    extensions: [
      pasteHistoryTracking,
      history({ joinToEvent: joinEditorHistoryEvent }),
    ],
  });
  const view = {
    get state() {
      return state;
    },
    dispatch(spec: Transaction | Parameters<EditorState["update"]>[number]) {
      state = spec instanceof Transaction ? spec.state : state.update(spec).state;
    },
  } as unknown as EditorView;
  return { view, state: () => state };
}

function insertPendingPaste(view: EditorView, text: string) {
  view.dispatch({
    changes: { from: 0, insert: text },
    selection: { anchor: text.length },
    effects: pasteHistoryStart.of(null),
    annotations: isolateHistory.of("before"),
    userEvent: "input.paste",
  });
}

describe("paste history", () => {
  const choices = pasteChoices({ plainText: "# Heading" }).choices;
  const source = choices.find((choice) => choice.mode === "source")!;
  const markdown = choices.find((choice) => choice.mode === "markdown")!;

  const session = (): PasteChoiceSession => ({
    from: 0,
    to: source.text.length,
    choices,
    selectedMode: "source",
    anchor: { left: 0, bottom: 0 },
  });

  it("undoes a paste and its selected interpretation in one step", () => {
    const harness = historyHarness();
    insertPendingPaste(harness.view, source.text);
    applyPasteChoice(harness.view, session(), markdown);

    expect(undoDepth(harness.state())).toBe(1);
    expect(undo(harness.view)).toBe(true);
    expect(harness.state().doc.toString()).toBe("");
    expect(redo(harness.view)).toBe(true);
    expect(harness.state().doc.toString()).toBe(markdown.text);
  });

  it("keeps repeated interpretation changes in the same history event", () => {
    const harness = historyHarness();
    insertPendingPaste(harness.view, source.text);
    const interpreted = applyPasteChoice(harness.view, session(), markdown);
    applyPasteChoice(harness.view, interpreted, source);

    expect(undoDepth(harness.state())).toBe(1);
    undo(harness.view);
    expect(harness.state().doc.toString()).toBe("");
    redo(harness.view);
    expect(harness.state().doc.toString()).toBe(source.text);
  });

  it("keeps typing after the default paste as a separate undo step", () => {
    const harness = historyHarness();
    insertPendingPaste(harness.view, source.text);
    harness.view.dispatch({
      changes: { from: source.text.length, insert: "!" },
      userEvent: "input.type",
    });

    expect(undoDepth(harness.state())).toBe(2);
    undo(harness.view);
    expect(harness.state().doc.toString()).toBe(source.text);
    undo(harness.view);
    expect(harness.state().doc.toString()).toBe("");
  });

  it("keeps typing after an interpreted paste as a separate undo step", () => {
    const harness = historyHarness();
    insertPendingPaste(harness.view, source.text);
    applyPasteChoice(harness.view, session(), markdown);
    harness.view.dispatch({
      changes: { from: markdown.text.length, insert: "!" },
      userEvent: "input.type",
    });

    expect(undoDepth(harness.state())).toBe(2);
    undo(harness.view);
    expect(harness.state().doc.toString()).toBe(markdown.text);
    undo(harness.view);
    expect(harness.state().doc.toString()).toBe("");
  });
});
