import { describe, expect, it } from "vitest";
import { richCopyHtml } from "./rich-copy";

describe("richCopyHtml", () => {
  it("renders common Markdown and GFM as semantic HTML", () => {
    const html = richCopyHtml([
      "## Update",
      "",
      "- **Ready** for _review_",
      "",
      "| Item | Status |",
      "| --- | --- |",
      "| Export | Done |",
    ].join("\n"));

    expect(html).toContain("<h2>Update</h2>");
    expect(html).toContain("<strong>Ready</strong>");
    expect(html).toContain("<em>review</em>");
    expect(html).toContain("<table>");
  });

  it("treats the first line as the note title when copying from the start", () => {
    expect(
      richCopyHtml("Project Polaris\n\nNext step", {
        includeDocumentTitle: true,
      }),
    ).toContain("<h1>Project Polaris</h1>");
  });

  it("escapes raw HTML instead of placing active markup on the clipboard", () => {
    const html = richCopyHtml('<script>alert("no")</script>');

    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });
});
