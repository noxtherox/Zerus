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
  it("preserves native Markdown links whose labels cannot fit in a wikilink", () => {
    const source = "[Plan \\[Q4\\] | café](#zerus-note:zerus%3Astable%7CPlan%20%5BQ4%5D%20%7C%20caf%C3%A9)";
    expect(restoreNoteLinks(source)).toBe(source);
    expect(prepareNoteLinks(restoreNoteLinks(source))).toBe(source);
    expect(noteReferenceFromHref("#zerus-note:zerus%3Astable%7CPlan%20%5BQ4%5D%20%7C%20caf%C3%A9")).toBe("zerus:stable|Plan [Q4] | café");
    const table = "| Link |\n| --- |\n| [Plan \\[Q4\\] \\| café](#zerus-note:zerus%3Astable%7CPlan%20%5BQ4%5D%20%7C%20caf%C3%A9) |";
    expect(restoreNoteLinks(table)).toBe(table);
    const closingParenthesis = "[Odd \\] ) label](#zerus-note:zerus%3Astable%7COdd%20%5D%20%29%20label)";
    expect(restoreNoteLinks(closingParenthesis)).toBe(closingParenthesis);
    const mixed = "[**Project** plan](#zerus-note:zerus%3Aproject%2D123%7CProject%20plan)";
    expect(restoreNoteLinks(mixed)).toBe("[**Project** plan](#zerus-note:zerus%3Aproject-123%7CProject%20plan)");
    const codeCell = "| Link |\n| --- |\n| [`code` plain](#zerus-note:zerus%3Aalpha%7Ccode%20plain) |";
    expect(restoreNoteLinks(codeCell)).toBe(codeCell);
    expect(prepareNoteLinks(restoreNoteLinks(codeCell))).toBe(codeCell);
  });
});

it("preserves a table cell when an ID link contains the alias separator", () => {
  const source = "| Link |\n| --- |\n| [[zerus:abc\\|Label]] |";
  const prepared = prepareNoteLinks(source);
  expect(prepared).toContain("#zerus-note:");
  expect(restoreNoteLinks(prepared)).toBe(source);
});
