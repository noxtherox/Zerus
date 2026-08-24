import { describe, expect, it } from "vitest";
import {
  decodeMarkdownEscapes,
  interpretMarkdownSource,
  markdownEscapeUnits,
  transformPreservingMarkdownEscapes,
} from "./markdown-escapes";

describe("Markdown escape parity", () => {
  it.each([
    ["\\*", "*", [0]],
    ["\\\\", "\\", [0]],
    ["\\\\\\*", "\\*", [0, 2]],
    ["\\\\\\\\", "\\\\", [0, 2]],
    ["\\a", "\\a", []],
  ])("decodes %s without losing visible slashes", (source, visible, hidden) => {
    expect(decodeMarkdownEscapes(source)).toBe(visible);
    expect(markdownEscapeUnits(source).map((unit) => unit.escapeFrom)).toEqual(
      hidden,
    );
  });

  it("removes only protective source escapes when interpreting a selection", () => {
    expect(interpretMarkdownSource("\\*\\*bold\\*\\* and \\\\ path")).toBe(
      "**bold** and \\ path",
    );
  });

  it("shields literal delimiters from formatting cleanup", () => {
    expect(
      transformPreservingMarkdownEscapes(
        "\\*\\*literal\\*\\* and **formatted**",
        (value) => value.replace(/\*\*([^*]+)\*\*/g, "$1"),
      ),
    ).toBe("**literal** and formatted");
  });
});
