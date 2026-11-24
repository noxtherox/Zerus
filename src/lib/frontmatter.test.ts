import { describe, expect, it } from "vitest";
import { getNoteProperties, setContentProperty, splitFrontmatter, withBody, renameContentProperty } from "./frontmatter";

describe("frontmatter boundaries", () => {
  it.each([0, 1, 2])("agrees with native YAML/body semantics after %i UTF-8 marks", (count) => {
    const prefix = "\uFEFF".repeat(count);
    const source = prefix + "---\r\nzerus-id: bom-note\r\nStatus: Active\r\n---\r\n# Body\r\n";
    // Tauri's UTF-8 TextDecoder removes one physical BOM; web/import callers
    // can also pass the original string. Both must identify the same note.
    for (const content of [source, new TextDecoder("utf-8").decode(new TextEncoder().encode(source))]) {
      const retained = /^\uFEFF*/.exec(content)![0];
      expect(getNoteProperties(content)).toEqual({ "zerus-id": "bom-note", Status: "Active" });
      expect(splitFrontmatter(content).body).toBe("# Body\r\n");
      expect(withBody(content, "# Replacement\r\n")).toBe(content.replace("# Body\r\n", "# Replacement\r\n"));
      const updated = setContentProperty(content, "Status", "Done");
      expect(updated.startsWith(retained + "---")).toBe(true);
      expect(getNoteProperties(updated)["zerus-id"]).toBe("bom-note");
      expect(getNoteProperties(renameContentProperty(updated, "Status", "Stage")).Stage).toBe("Done");
    }
    const headerless = prefix + "# Body\r\n";
    expect(withBody(headerless, "# Replacement\r\n")).toBe(prefix + "# Replacement\r\n");
    expect(getNoteProperties(setContentProperty(headerless, "zerus-id", "new-id"))["zerus-id"]).toBe("new-id");
  });

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

  it.each([
    { header: String.raw`Values: ["one,two", "a\"b", "C:\\docs\\a,b", ""]`, expected: ["one,two", 'a"b', "C:\\docs\\a,b", ""] },
    { header: "Values: ['one,two', 'Bob''s note', plain,]", expected: ["one,two", "Bob's note", "plain"] },
    { header: String.raw`Values: ["{\"id\":\"backup\",\"name\":\"Report, notes.pdf\"}"]`, expected: ['{"id":"backup","name":"Report, notes.pdf"}'] },
  ])("reads quoted inline lists without splitting their contents: $header", ({ header, expected }) => {
    const content = `---\n${header}\nStatus: Active\n---\n# Body\n`;
    expect(getNoteProperties(content).Values).toEqual(expected);
    const edited = setContentProperty(content, "Status", "Done");
    expect(getNoteProperties(edited).Values).toEqual(expected);
    expect(splitFrontmatter(edited).body).toBe("# Body\n");
  });

  it("preserves unsupported inline structures while editing another property", () => {
    const foreign = "foreign: [one, {nested: [a, b]}]";
    const content = `---\n${foreign}\nStatus: Active\n---\n# Body`;
    const edited = setContentProperty(content, "Status", "Done");
    expect(edited).toContain(foreign + "\n");
    expect(getNoteProperties(edited).Status).toBe("Done");
    expect(splitFrontmatter(edited).body).toBe("# Body");
  });

});
