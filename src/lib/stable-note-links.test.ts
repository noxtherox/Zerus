import { describe, expect, it, vi } from "vitest";
import * as wikilinks from "./wikilinks";
import { stabilizeNoteLinks } from "./stable-note-links";
import { findNoteByTitle, getOutgoingLinkTitles, noteReference, type Note } from "./note-utils";
import { getBacklinksGroupedByType } from "./links";
import { getNoteProperties } from "./frontmatter";

const note = (id: string, content: string): Note => ({ id, content, path: `work/${id}.md`, pinned: false, updatedAt: "2026-09-11" });
const schemas = { work: [{ name: "Related", type: "relation" as const, relationMultiple: true }] };

describe("stable note references", () => {
  it("skips parsing stable links across successive prose edits", () => {
    const parse = vi.spyOn(wikilinks, "mapWikilinks");
    try {
      for (const text of ["a", "ab", "abc"]) {
        const source = note("source", `# Source\n\n[[zerus:target|Target]] ${text}`);
        expect(stabilizeNoteLinks(source, [], {})).toBe(source.content);
      }
      expect(parse).not.toHaveBeenCalled();
    } finally { parse.mockRestore(); }
  });

  it("does not reparse unchanged notes or resolve labelled IDs while typing a title", () => {
    const target = note("target", "# Original");
    const source = note("source", "# Source\n\n[[zerus:target|Original]]");
    const parse = vi.spyOn(wikilinks, "mapWikilinks");
    const resolve = vi.fn(() => target);
    try {
      for (const title of ["N", "Ne", "New"]) {
        const renamed = { ...target, content: `# ${title}` };
        expect(stabilizeNoteLinks(source, [source, renamed], {}, resolve)).toBe(source.content);
      }
      expect(parse).not.toHaveBeenCalled();
      expect(resolve).not.toHaveBeenCalled();
    } finally {
      parse.mockRestore();
    }
  });

  it("rechecks unresolved and ambiguous legacy links when the catalogue changes", () => {
    const source = note("source", "# Source\n\n[[Target]]");
    const target = note("target", "# Target");
    expect(stabilizeNoteLinks(source, [source], {})).toBe(source.content);
    expect(stabilizeNoteLinks(source, [source, target], {})).toContain("[[zerus:target|Target]]");
    expect(stabilizeNoteLinks(source, [source, target, note("duplicate", "# Target")], {})).toBe(source.content);
  });

  it("invalidates cached results for content and relation schema changes", () => {
    const target = note("target", "# Target");
    const source = note("source", "---\nRelated: Target\n---\n# Source");
    expect(stabilizeNoteLinks(source, [target], {})).toBe(source.content);
    expect(getNoteProperties(stabilizeNoteLinks(source, [target], schemas)).Related).toBe("zerus:target|Target");
    source.content += "\n\n[[Target]]";
    expect(stabilizeNoteLinks(source, [target], schemas)).toContain("[[zerus:target|Target]]");
  });

  it("keeps body and relation backlinks after renaming, moving, and reopening", () => {
    const target = note("target-id", "# Original");
    const source = note("source-id", "---\nRelated:\n  - Original\n---\n# Source\n\n[[Original|My label]]");
    const content = stabilizeNoteLinks(source, [source, target], schemas);
    expect(content).toContain("[[zerus:target-id|My label]]");
    expect(getNoteProperties(content).Related).toEqual(["zerus:target-id|Original"]);
    const renamed = { ...target, path: "elsewhere/Renamed.md", content: "# Renamed" };
    const reopened = JSON.parse(JSON.stringify([{ ...source, content }, renamed]));
    expect(findNoteByTitle("zerus:target-id|Original", reopened)?.id).toBe(target.id);
    expect([...getBacklinksGroupedByType(renamed, reopened, schemas).values()].flat().map(n => n.id)).toEqual([source.id]);
  });

  it("does not guess duplicate titles or redirect a missing ID to a namesake", () => {
    const a = note("a", "# Same");
    const b = note("b", "# Same");
    const source = note("s", "# Source\n\n[[Same]] [[Missing]]");
    expect(stabilizeNoteLinks(source, [a, b, source], {})).toBe(source.content);
    expect(findNoteByTitle("zerus:deleted|Same", [a, b])).toBeUndefined();
    expect(findNoteByTitle(noteReference(b), [a, b])).toBe(b);
  });

  it("leaves code, unrelated properties and unresolved links untouched; is idempotent", () => {
    const target = note("a", "# Target");
    const source = note("s", '---\nText: Target\nRelated: Target\n---\n# Source\n\n`[[Target]]`\n\n```md\n[[Target]]\n```\n\n[[Target]] [[Missing]]');
    const content = stabilizeNoteLinks(source, [target], schemas);
    expect(content).toContain("Text: Target");
    expect(content).toContain("`[[Target]]`");
    expect(content).toContain("```md\n[[Target]]\n```");
    expect(content).toContain("[[Missing]]");
    expect(getOutgoingLinkTitles(content)).toEqual(["zerus:a|Target", "Missing"]);
    expect(stabilizeNoteLinks({ ...source, content }, [target], schemas)).toBe(content);
  });

  it("repairs ID-only references with readable fallback labels", () => {
    const target = note("target-id", "# Readable target");
    const source = note(
      "source-id",
      '---\nRelated: "zerus:target-id"\n---\n# Source\n\n[[zerus:target-id]]',
    );
    const content = stabilizeNoteLinks(source, [source, target], schemas);
    expect(getNoteProperties(content).Related).toBe(
      "zerus:target-id|Readable target",
    );
    expect(content).toContain("[[zerus:target-id|Readable target]]");
  });

  it("handles reciprocal ID relations without hiding a separate body backlink", () => {
    const a = note("a", '---\nRelated: "zerus:b|Old B"\n---\n# New A');
    const b = note("b", '---\nRelated: "zerus:a|Old A"\n---\n# New B');
    expect([...getBacklinksGroupedByType(a, [a, b], schemas).values()].flat()).toEqual([]);
    b.content += "\n\n[[zerus:a|Old A]]";
    expect([...getBacklinksGroupedByType(a, [a, b], schemas).values()].flat()).toEqual([b]);
  });
});

it("escapes ID alias separators during migration inside tables", () => {
  const target = note("id", "# Target");
  const source = note("source", "# Source\n\n| Link |\n| --- |\n| [[Target]] |");
  const content = stabilizeNoteLinks(source, [target], {});
  expect(content).toContain("[[zerus:id\\|Target]]");
  expect(getOutgoingLinkTitles(content)).toEqual(["zerus:id|Target"]);
});


it("indexes native styled fragment links in document order while excluding literal examples", () => {
  const target = note("target", "# Renamed target");
  const codeOnly = note("code-only", "# Example only");
  const source = note("source", [
    "# Source", "[[zerus:before|Before]]",
    "[**Project** plan](#zerus-note:zerus%3Atarget%7CProject%20plan)",
    "`[Example](#zerus-note:zerus%3Acode-only%7CExample)`",
    "```md\n[Example](#zerus-note:zerus%3Acode-only%7CExample)\n```",
    "![Example](#zerus-note:zerus%3Acode-only%7CExample)",
    "<div>[Example](#zerus-note:zerus%3Acode-only%7CExample)</div>",
    "[Web](https://example.com/#zerus-note:zerus%3Acode-only%7CExample)",
    "| Link |\n| --- |\n| [Café \\[Q4\\] \\| plan](#zerus-note:zerus%3Atarget%7CCaf%C3%A9%20%5BQ4%5D%20%7C%20plan) |",
    "[Reference **label**][native-target]", "[native-target]: #zerus-note:zerus%3Atarget%7COld%20label",
    "[[zerus:after|After]]", "[Broken](#zerus-note:%invalid)",
  ].join("\n\n"));
  const original = source.content;
  expect(getOutgoingLinkTitles(source.content)).toEqual([
    "zerus:before|Before", "zerus:target|Project plan", "zerus:target|Café [Q4] | plan", "zerus:target|Reference label", "zerus:after|After",
  ]);
  expect([...getBacklinksGroupedByType(target, [source, target, codeOnly], {}).values()].flat()).toEqual([source]);
  expect([...getBacklinksGroupedByType(codeOnly, [source, target, codeOnly], {}).values()].flat()).toEqual([]);
  expect(source.content).toBe(original);
});
