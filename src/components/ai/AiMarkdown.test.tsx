import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { noteIdFromAiHref } from "@/lib/ai-note-links";
import { AiMarkdown } from "./AiMarkdown";

describe("AiMarkdown", () => {
  it("renders common and GitHub-flavored Markdown", () => {
    const html = renderToStaticMarkup(
      <AiMarkdown>{[
        "## Result",
        "",
        "- **bold** item",
        "- [x] finished",
        "",
        "| Name | Value |",
        "| --- | --- |",
        "| alpha | `one` |",
        "",
        "```ts",
        "const ready = true;",
        "```",
      ].join("\n")}</AiMarkdown>,
    );

    expect(html).toContain("<h2");
    expect(html).toContain("<strong>bold</strong>");
    expect(html).toContain('type="checkbox"');
    expect(html).toContain("<table");
    expect(html).toContain("language-ts");
  });

  it("does not render raw HTML from a model response", () => {
    const html = renderToStaticMarkup(
      <AiMarkdown>{'<script>alert("no")</script>'}</AiMarkdown>,
    );

    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });

  it.each([
    ["Confirmed in [Project Alpha](zerus-note:project%2Falpha).", "Project Alpha"],
    ["I found one matching note:\n\n- [[zerus:project/alpha|Project Alpha]]", "Project Alpha"],
    ["| Source |\n| --- |\n| [[zerus:project/alpha\\|Project *Alpha*]] |", "Project *Alpha*"],
  ])("keeps internal note citations clickable: %s", (content, label) => {
    const html = renderToStaticMarkup(
      <AiMarkdown onOpenNote={() => undefined}>
        {content}
      </AiMarkdown>,
    );

    expect(html).toContain('href="zerus-note:project%2Falpha"');
    expect(html).toContain(`>${label}</a>`);
    expect(noteIdFromAiHref("zerus-note:project%2Falpha")).toBe("project/alpha");
    expect(noteIdFromAiHref("javascript:alert(1)")).toBeNull();
  });

  it("leaves wikilink examples in code and existing links literal", () => {
    const html = renderToStaticMarkup(
      <AiMarkdown>{[
        "`[[zerus:example|Example]]`",
        "",
        "```md",
        "[[zerus:example|Example]]",
        "```",
        "",
        "[Literal [[zerus:example|Example]]](https://example.com)",
      ].join("\n")}</AiMarkdown>,
    );

    expect(html).not.toContain('href="zerus-note:');
    expect(html.match(/\[\[zerus:example\|Example\]\]/g)).toHaveLength(3);
    expect(html).toContain('href="https://example.com"');
  });
});
