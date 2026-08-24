import { describe, expect, it } from "vitest";
import { readableCopyText, richCopyHtml } from "./rich-copy";

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

describe("readableCopyText", () => {
  it("removes Markdown syntax while retaining readable structure", () => {
    expect(
      readableCopyText([
        "## Update",
        "",
        "- **Ready** for [review](https://example.com)",
        "- [x] Shipped",
        "",
        "> A useful quote",
        "",
        "Use `inline code` here.",
      ].join("\n")),
    ).toBe([
      "Update",
      "",
      "• Ready for review",
      "☑ Shipped",
      "",
      "› A useful quote",
      "",
      "Use inline code here.",
    ].join("\n"));
  });

  it("turns a Markdown table into tab-separated readable text", () => {
    expect(
      readableCopyText(
        "| Name | Status |\n| --- | --- |\n| Zerus | Ready |",
      ),
    ).toBe("Name\tStatus\nZerus\tReady");
  });

  it("keeps fenced code content but removes the fence", () => {
    expect(readableCopyText("```ts\nconst answer = 42;\n```"))
      .toBe("const answer = 42;");
  });

  it("copies escaped Markdown and repeated backslashes exactly as displayed", () => {
    expect(
      readableCopyText("\\*\\*literal\\*\\* and \\\\ path"),
    ).toBe("**literal** and \\ path");
  });
});
