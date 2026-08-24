import { EditorState } from "@codemirror/state";
import type { EditorView } from "@codemirror/view";
import { describe, expect, it } from "vitest";
import { imageEditIsCurrent } from "./image-edit-guard";

function view(doc: string): EditorView {
  return { state: EditorState.create({ doc }) } as EditorView;
}

describe("imageEditIsCurrent", () => {
  const markdown = "![chart](assets/chart.png)";

  it("accepts the unchanged editor and source range", () => {
    const expected = view(markdown);
    expect(
      imageEditIsCurrent(
        expected,
        expected,
        { from: 0, to: markdown.length },
        markdown,
      ),
    ).toBe(true);
  });

  it("rejects a switched editor or source changed during an await", () => {
    const expected = view(markdown);
    expect(
      imageEditIsCurrent(
        view(markdown),
        expected,
        { from: 0, to: markdown.length },
        markdown,
      ),
    ).toBe(false);
    const edited = view("edited");
    expect(
      imageEditIsCurrent(
        edited,
        edited,
        { from: 0, to: markdown.length },
        markdown,
      ),
    ).toBe(false);
  });
});
