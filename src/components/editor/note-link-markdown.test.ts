import { describe, expect, it } from "vitest";
import { prepareNoteLinks, restoreNoteLinks, noteReferenceFromHref } from "./note-link-markdown";

describe("editor note links", () => {
  it.each(["[[Old name]]", "[[zerus:abc|Readable name]]", "[[zerus:abc|A *literal* label]]"])("round-trips %s without losing the target", (link) => {
    const source = `# Title\n\nSee ${link}.`;
    expect(prepareNoteLinks(source)).toContain("#zerus-note:");
    expect(restoreNoteLinks(prepareNoteLinks(source))).toBe(source);
  });
  it("leaves code examples untouched", () => {
    const source = "`[[Title]]`\n\n```md\n[[Title]]\n```";
    expect(prepareNoteLinks(source)).toBe(source);
  });
  it("keeps identity when the visible label is edited", () => {
    expect(restoreNoteLinks("[New label](#zerus-note:zerus%3Aabc%7COld%20label)")).toBe("[[zerus:abc|New label]]");
    expect(noteReferenceFromHref("#zerus-note:%invalid")).toBeNull();
  });
});

it("preserves a table cell when an ID link contains the alias separator", () => {
  const source = "| Link |\n| --- |\n| [[zerus:abc\\|Label]] |";
  const prepared = prepareNoteLinks(source);
  expect(prepared).toContain("#zerus-note:");
  expect(restoreNoteLinks(prepared)).toBe(source);
});
