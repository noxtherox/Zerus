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

  it("keeps internal note citations clickable", () => {
    const html = renderToStaticMarkup(
      <AiMarkdown onOpenNote={() => undefined}>
        {"Confirmed in [Project Alpha](zerus-note:project%2Falpha)."}
      </AiMarkdown>,
    );

    expect(html).toContain('href="zerus-note:project%2Falpha"');
    expect(noteIdFromAiHref("zerus-note:project%2Falpha")).toBe("project/alpha");
    expect(noteIdFromAiHref("javascript:alert(1)")).toBeNull();
  });
});
