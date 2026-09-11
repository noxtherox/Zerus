import { describe, expect, it } from "vitest";
import { fromMarkdown } from "mdast-util-from-markdown";
import { mdxJsxFromMarkdown } from "mdast-util-mdx-jsx";
import { mdxJsx } from "micromark-extension-mdx-jsx";
import { mdxMd } from "micromark-extension-mdx-md";
import remarkParse from "remark-parse";
import { unified } from "unified";
import { linkMarkdown } from "@/lib/link-hubs";
import {
  cleanMarkdownFromMdxEditor,
  prepareMarkdownForMdxEditor,
} from "./mdx-compat";

describe("MDX Markdown compatibility", () => {
  it.each([
    "https://claude.ai/design/p/0d3f7a78-c165-4509-9597-ec3933dc08d0?via=share&file=Live+View+Prototype.dc.html",
    "https://example.com/path_(one)?q=[two]&other=value",
    "mailto:hello@example.com",
  ])("opens saved autolinks as explicit links without changing their destination: %s", (url) => {
    const prepared = prepareMarkdownForMdxEditor(`# Link\n\n${linkMarkdown(url)}\n`);
    expect(prepared).toContain("](");
    const paragraph = unified().use(remarkParse).parse(prepared).children[1];
    expect(paragraph).toMatchObject({ type: "paragraph", children: [{ type: "link", url }] });
    expect(prepareMarkdownForMdxEditor(prepared)).toBe(prepared);
  });

  it("converts email autolinks and nested links", () => {
    expect(prepareMarkdownForMdxEditor("> <hello@example.com>\n\n- <https://example.com>"))
      .toBe("> [hello@example.com](mailto:hello@example.com)\n\n- [https://example.com](https://example.com)");
  });

  it.each([
    "`<https://example.com>`",
    "```md\n<https://example.com>\n```",
    "~~~md\n<https://example.com>\n~~~",
    "[Example](<https://example.com>)",
    "![Example](<https://example.com/image.png>)",
    "\\<https://example.com>",
  ])("preserves code, explicit destinations, and escaped autolinks: %s", (source) => {
    expect(prepareMarkdownForMdxEditor(source)).toBe(source);
  });

  it.each([
    ["K+ <1", "K+ \\<1"],
    ["SpO2 <90%", "SpO2 \\<90%"],
    ["x <= 1", "x \\<= 1"],
    ["a <½", "a \\<½"],
    ["5 << 6", "5 \\<\\< 6"],
    ["x < 1", "x \\< 1"],
  ])("shields literal comparison text in %s", (source, expected) => {
    expect(prepareMarkdownForMdxEditor(source)).toBe(expected);
  });

  it.each([
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

// Exercise the actual HTML tokenizer used by MDXEditor, not just string output.
function parseInEditor(source: string) {
  return fromMarkdown(source, {
    extensions: [mdxJsx(), mdxMd()],
    mdastExtensions: [mdxJsxFromMarkdown()],
  });
}

const withoutPositions = (node: unknown): unknown => {
  if (Array.isArray(node)) return node.map(withoutPositions);
  if (node && typeof node === "object") return Object.fromEntries(
    Object.entries(node).filter(([key]) => key !== "position")
      .map(([key, value]) => [key, withoutPositions(value)]),
  );
  return node;
};

describe("arbitrary note text in the formatted editor", () => {
  it.each([
    "Flow <10m/s; FC>110; PAS<90; Sat.O2<90%; Fr>30; Síncope=> RISCO⬆️🚨",
    "Flow </s; dose <mg/kg; A <B; A <_value; <; <>; <!; <?",
    "Template {name}, {/Users/example}, } and {{nested}} ❤️ ⚠️ ≤ ≥ ≠ ± →",
    "Unmatched ` then <dose and {name}",
    "Escaped \\` then <dose and {name}",
    "prefix <span>unclosed",
    "<div title=unquoted>Text</div>",
    "Text <u>underlined</u> and </broken",
    "| Test | Value |\n| --- | --- |\n| Oxygen | <90% |\n| Flow | </s |",
  ])("opens without a JSX parsing error: %s", (source) => {
    const prepared = prepareMarkdownForMdxEditor(source);
    expect(() => parseInEditor(prepared)).not.toThrow();
    expect(prepareMarkdownForMdxEditor(prepared)).toBe(prepared);
  });

  it("preserves Markdown meaning across ASCII punctuation and representative Unicode", () => {
    const characters = Array.from({ length: 95 }, (_, i) => String.fromCharCode(i + 32))
      .concat(["é", "½", "≤", "≥", "→", "❤️", "🚨", "⚠️"]);
    for (const character of characters) {
      const source = `Text <${character}suffix and {${character}} end`;
      const tree = parseInEditor(prepareMarkdownForMdxEditor(source));
      expect(withoutPositions(tree), source).toEqual(
        withoutPositions(unified().use(remarkParse).parse(source)),
      );
    }
  });

  it.each([
    "> ```text\n> </s {name}\n> ```",
    "- Example\n\n  ~~~text\n  </s {name}\n  ~~~",
    "``a ` </s {name}``",
    "[Reference](<https://example.com/{name}>)",
    "![Image](<https://example.com/{name}.png>)",
  ])("keeps code and destinations verbatim: %s", (source) => {
    expect(prepareMarkdownForMdxEditor(source)).toBe(source);
    expect(() => parseInEditor(source)).not.toThrow();
  });

  it("converts indented code to fences without changing its contents", () => {
    for (const source of [
      "    </s {name}\n    <dose",
      ">     </s {name}\n>     <dose",
      "- Example\n\n      </s {name}\n      <dose",
    ]) {
      const prepared = prepareMarkdownForMdxEditor(source);
      expect(prepared).toContain("```");
      expect(withoutPositions(parseInEditor(prepared))).toEqual(
        withoutPositions(unified().use(remarkParse).parse(source)),
      );
      expect(prepareMarkdownForMdxEditor(prepared)).toBe(prepared);
    }
  });
});
