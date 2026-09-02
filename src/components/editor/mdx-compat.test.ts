import { describe, expect, it } from "vitest";
import {
  cleanMarkdownFromMdxEditor,
  prepareMarkdownForMdxEditor,
} from "./mdx-compat";

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
    ["Path: {/Users/example}", "Path: \\{/Users/example\\}"],
    ["Template: {name}", "Template: \\{name\\}"],
    ["Empty braces: {}", "Empty braces: \\{\\}"],
    ["Only an opening { brace", "Only an opening \\{ brace"],
  ])("shields literal braces that MDX treats as expressions: %s", (source, expected) => {
    expect(prepareMarkdownForMdxEditor(source)).toBe(expected);
  });

  it.each([
    "already \\{escaped\\}",
    "inline `{name}` code",
    "```txt\n{/Users/example}\n```",
    "~~~txt\n{name}\n~~~",
  ])("leaves escaped or verbatim braces unchanged: %s", (source) => {
    expect(prepareMarkdownForMdxEditor(source)).toBe(source);
  });

  it("shields braces idempotently", () => {
    const once = prepareMarkdownForMdxEditor("Path: {/Users/example}");
    expect(prepareMarkdownForMdxEditor(once)).toBe(once);
  });

  it("removes serialized trailing-space entities outside code", () => {
    expect(
      prepareMarkdownForMdxEditor(
        "First paragraph&#x20;\n\nSecond paragraph &#x20;",
      ),
    ).toBe("First paragraph\n\nSecond paragraph");
  });

  it("keeps trailing-space entities inside inline and fenced code", () => {
    const source = "`value&#x20;`\n\n```txt\nvalue&#x20;\n```";
    expect(prepareMarkdownForMdxEditor(source)).toBe(source);
  });

  it("cleans newly exported trailing-space entities", () => {
    expect(cleanMarkdownFromMdxEditor("Paragraph&#x20;\n\nNext")).toBe(
      "Paragraph\n\nNext",
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
