import { EditorState, type TransactionSpec } from "@codemirror/state";
import type { EditorView } from "@codemirror/view";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { describe, expect, it, vi } from "vitest";
import {
  interpretSelectionAsMarkdown,
  setHeadingLevel,
  toggleInlineMarkup,
  toggleLinePrefix,
} from "./editor-commands";

function editor(doc: string, from: number, to = from) {
  let state = EditorState.create({
    doc,
    selection: { anchor: from, head: to },
    extensions: [markdown({ base: markdownLanguage, extensions: GFM })],
  });
  const focus = vi.fn();
  const view = {
    get state() {
      return state;
    },
    dispatch(spec: TransactionSpec) {
      state = state.update(spec).state;
    },
    focus,
  } as unknown as EditorView;
  return { view, focus, doc: () => state.doc.toString() };
}

describe("editor formatting commands", () => {
  it("adds and removes inline markup", () => {
    const target = editor("bold", 0, 4);
    toggleInlineMarkup(target.view, "**", "bold text");
    expect(target.doc()).toBe("**bold**");
    toggleInlineMarkup(target.view, "**", "bold text");
    expect(target.doc()).toBe("bold");
  });

  it("toggles a prefix across selected lines", () => {
    const target = editor("one\ntwo", 0, 7);
    toggleLinePrefix(target.view, "- ", /^[-*+]\s/);
    expect(target.doc()).toBe("- one\n- two");
    toggleLinePrefix(target.view, "- ", /^[-*+]\s/);
    expect(target.doc()).toBe("one\ntwo");
  });

  it("replaces an existing heading level and toggles the selected level", () => {
    const target = editor("## Heading", 0, 10);
    setHeadingLevel(target.view, 3);
    expect(target.doc()).toBe("### Heading");
    setHeadingLevel(target.view, 3);
    expect(target.doc()).toBe("Heading");
  });

  it("interprets selected literal Markdown without touching other text", () => {
    const source = "before \\*\\*bold\\*\\* after";
    const target = editor(source, 7, source.length - 6);

    expect(interpretSelectionAsMarkdown(target.view)).toBe(true);
    expect(target.doc()).toBe("before **bold** after");
  });

  it("requires selected text before interpreting Markdown", () => {
    const target = editor("\\*literal\\*", 3);
    expect(interpretSelectionAsMarkdown(target.view)).toBe(false);
    expect(target.doc()).toBe("\\*literal\\*");
  });
});
