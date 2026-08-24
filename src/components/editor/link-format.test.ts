import { describe, expect, it } from "vitest";
import { formatMarkdownLink } from "./link-format";

describe("formatMarkdownLink", () => {
  it("creates a link with the chosen label and destination", () => {
    expect(formatMarkdownLink("Zerus", "https://zerus.app/")).toBe(
      "[Zerus](https://zerus.app/)",
    );
  });

  it("escapes Markdown brackets and backslashes in the visible label", () => {
    expect(formatMarkdownLink("A [useful] \\ link", "https://example.com/")).toBe(
      "[A \\[useful\\] \\\\ link](https://example.com/)",
    );
  });
});
