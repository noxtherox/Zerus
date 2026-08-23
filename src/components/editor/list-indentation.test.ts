import { indentLess, indentMore } from "@codemirror/commands";
import { EditorSelection, EditorState, type Transaction } from "@codemirror/state";
import { describe, expect, it } from "vitest";
import { markdownListIndentation } from "./list-indentation";

function runIndentCommand(
  doc: string,
  selection: { readonly anchor: number; readonly head: number },
  command: typeof indentMore,
): EditorState {
  let state = EditorState.create({
    doc,
    selection,
    extensions: [markdownListIndentation],
  });

  command({
    state,
    dispatch: (transaction: Transaction) => {
      state = transaction.state;
    },
  });

  return state;
}

describe("Markdown list indentation", () => {
  it("indents a bullet by one stable four-space nesting level", () => {
    const state = runIndentCommand(
      "- parent\n- child",
      EditorSelection.cursor(12),
      indentMore,
    );

    expect(state.doc.toString()).toBe("- parent\n    - child");
  });

  it("moves selected list items together", () => {
    const state = runIndentCommand(
      "- one\n- two\n- three",
      EditorSelection.range(0, 11),
      indentMore,
    );

    expect(state.doc.toString()).toBe("    - one\n    - two\n- three");
  });

  it("outdents exactly one nesting level", () => {
    const state = runIndentCommand(
      "- parent\n        - child",
      EditorSelection.cursor(20),
      indentLess,
    );

    expect(state.doc.toString()).toBe("- parent\n    - child");
  });
});
