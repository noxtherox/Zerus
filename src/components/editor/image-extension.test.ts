import { EditorState } from "@codemirror/state";
import { describe, expect, it } from "vitest";
import {
  caretAfterEditorImage,
  hasBlankLineAfterEditorImage,
  shouldOpenEditorImage,
} from "./image-extension";

describe("image activation", () => {
  it("opens on a double click", () => {
    expect(
      shouldOpenEditorImage({ button: 0, metaKey: false, ctrlKey: false, detail: 2 }),
    ).toBe(true);
  });

  it("opens on a modifier click", () => {
    expect(
      shouldOpenEditorImage({ button: 0, metaKey: true, ctrlKey: false, detail: 1 }),
    ).toBe(true);
    expect(
      shouldOpenEditorImage({ button: 0, metaKey: false, ctrlKey: true, detail: 1 }),
    ).toBe(true);
  });

  it("keeps a normal click for the image popover", () => {
    expect(
      shouldOpenEditorImage({ button: 0, metaKey: false, ctrlKey: false, detail: 1 }),
    ).toBe(false);
  });
});

describe("image caret placement", () => {
  it.each([
    ["Before\n![](assets/image.png)\n\nAfter", 7, 28, 29],
    ["Before\n![](assets/image.png)\nAfter", 7, 28, 29],
    ["Before\n![](assets/image.png)", 7, 28, 28],
  ])(
    "places the caret on the real line after the image in %s",
    (doc, imageFrom, imageTo, expected) => {
      const state = EditorState.create({ doc });
      expect(doc.slice(imageFrom, imageTo)).toBe("![](assets/image.png)");
      expect(caretAfterEditorImage(state, imageTo)).toBe(expected);
    },
  );

  it("extends the image interaction boundary only across a real blank line", () => {
    const image = "![](assets/image.png)";
    const withBlankLine = EditorState.create({
      doc: `Before\n${image}\n\nAfter`,
    });
    const withImmediateText = EditorState.create({
      doc: `Before\n${image}\nAfter`,
    });

    expect(hasBlankLineAfterEditorImage(withBlankLine, 7 + image.length)).toBe(
      true,
    );
    expect(
      hasBlankLineAfterEditorImage(withImmediateText, 7 + image.length),
    ).toBe(false);
  });
});
