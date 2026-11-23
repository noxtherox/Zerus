import type { PhrasingContent, Root } from "mdast";
import { fromMarkdown } from "mdast-util-from-markdown";
import { toMarkdown } from "mdast-util-to-markdown";
import { describe, expect, it } from "vitest";

// Regression coverage for patches/mdast-util-to-markdown@2.1.2.patch.
// Upstream encodes characters next to bold/italic runs one UTF-16 unit at a
// time, which split emoji surrogate pairs and saved them to disk as "��".
const text = (value: string): PhrasingContent => ({ type: "text", value });
const strong = (value: string): PhrasingContent => ({ type: "strong", children: [text(value)] });
const emphasis = (value: string): PhrasingContent => ({ type: "emphasis", children: [text(value)] });

function roundTrip(children: PhrasingContent[]) {
  const tree: Root = { type: "root", children: [{ type: "paragraph", children }] };
  const markdown = toMarkdown(tree);
  // Writing to disk goes through UTF-8, which turns lone surrogates into U+FFFD.
  const onDisk = new TextDecoder().decode(new TextEncoder().encode(markdown));
  return { markdown: onDisk, tree: fromMarkdown(onDisk) };
}

describe("emoji next to emphasis", () => {
  const cases: Array<[string, PhrasingContent[]]> = [
    ["bold with trailing space before an emoji", [strong("Não "), text("🦠🦠- DAI")]],
    ["bold ending in punctuation before an emoji", [strong("Risco:"), text("🚩 sinal")]],
    ["emoji before bold starting with a space", [text("🔺"), strong(" Risco")]],
    ["italic ending in punctuation before an emoji", [emphasis("nota."), text("💊")]],
    ["emoji with a variation selector", [strong("Alerta:"), text("❤️ ok")]],
  ];

  it.each(cases)("preserves emoji for %s", (_name, children) => {
    const { markdown, tree } = roundTrip(children);
    expect(markdown).not.toContain("�");
    expect(tree.children[0]).toMatchObject({ type: "paragraph", children });
  });
});
