import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
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
});
