import { describe, expect, it } from "vitest";
import { getNoteProperties, setContentProperty, splitFrontmatter, withBody } from "./frontmatter";

describe("frontmatter boundaries", () => {
  it.each([
    { content: "---\nStatus: Active\n---\n# Body\n---\nText\n", raw: "Status: Active", body: "# Body\n---\nText\n" },
    { content: "---\r\nStatus: Active\r\n...  \r\n# Body\r\n", raw: "Status: Active\r", body: "# Body\r\n" },
    { content: "---\n---\nBody", raw: "", body: "Body" },
    { content: "---\nStatus: Active\n---", raw: "Status: Active", body: "" },
    { content: "---\nStatus: Active\n---not a fence\nBody", raw: null, body: "---\nStatus: Active\n---not a fence\nBody" },
    { content: "---\nStatus: Active\r---\nBody", raw: null, body: "---\nStatus: Active\r---\nBody" },
    { content: "# Body\n---\n", raw: null, body: "# Body\n---\n" },
  ])("preserves the exact body of $content", ({ content, raw, body }) => {
    expect(splitFrontmatter(content)).toEqual({ raw, body });
  });

  it("reads and edits header properties without interpreting body fences as metadata", () => {
    const content = "---\nStatus: Active\nTags: [one, two]\n---\n# Note\n\n---\nStatus: Body text\n";
    expect(getNoteProperties(content)).toEqual({ Status: "Active", Tags: ["one", "two"] });
    const edited = setContentProperty(content, "Status", "Done");
    expect(getNoteProperties(edited).Status).toBe("Done");
    expect(splitFrontmatter(edited).body).toBe("# Note\n\n---\nStatus: Body text\n");
    expect(withBody(content, "# Replacement")).toBe("---\nStatus: Active\nTags: [one, two]\n---\n# Replacement");
  });
});
