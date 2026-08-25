import { describe, expect, it } from "vitest";
import { prepareMarkdownForMdxEditor } from "./mdx-compat";

describe("MDX Markdown compatibility", () => {
  it.each([
    ["K+ <1", "K+ \\<1"],
    ["SpO2 <90%", "SpO2 \\<90%"],
    ["x <= 1", "x \\<= 1"],
    ["a <½", "a \\<½"],
    ["5 << 6", "5 \\<< 6"],
  ])("shields literal comparison text in %s", (source, expected) => {
    expect(prepareMarkdownForMdxEditor(source)).toBe(expected);
  });

  it.each([
    "x < 1",
    "<u>underlined</u>",
    "already \\<1",
    "inline `<1` code",
    "```txt\n<1\n```",
    "~~~txt\n<1\n~~~",
  ])("leaves compatible or verbatim Markdown unchanged: %s", (source) => {
    expect(prepareMarkdownForMdxEditor(source)).toBe(source);
  });

  it("is idempotent", () => {
    const once = prepareMarkdownForMdxEditor("K+ <1 and SpO2 <90%");
    expect(prepareMarkdownForMdxEditor(once)).toBe(once);
  });

  it("resumes shielding after a fenced code block", () => {
    expect(prepareMarkdownForMdxEditor("```txt\n<1\n```\nK+ <1")).toBe(
      "```txt\n<1\n```\nK+ \\<1",
    );
  });

  it.each([
    ["First<br>Second", "First<br />Second"],
    ["First<BR >Second", "First<br />Second"],
    ["| First<br>Second | Other |", "| First<br />Second | Other |"],
  ])("makes HTML break tags MDX-compatible: %s", (source, expected) => {
    expect(prepareMarkdownForMdxEditor(source)).toBe(expected);
  });

  it.each([
    "First<br />Second",
    "inline `<br>` code",
    "```html\n<br>\n```",
  ])("does not rewrite compatible or verbatim break tags: %s", (source) => {
    expect(prepareMarkdownForMdxEditor(source)).toBe(source);
  });
});
