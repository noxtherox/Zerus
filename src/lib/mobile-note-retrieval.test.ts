import { describe, expect, it } from "vitest";
import { retrieveNotes } from "./mobile-note-retrieval";
import type { Note } from "./note-utils";

function makeNote(id: string, content: string, updatedAt = "2026-01-01T00:00:00.000Z"): Note {
  return { id, path: `people/${id}.md`, content, pinned: false, updatedAt };
}

describe("mobile note retrieval", () => {
  it("finds an exact person note even when it is beyond the first 12 notes", () => {
    const unrelated = Array.from({ length: 14 }, (_, index) =>
      makeNote(`unrelated-${index}`, `# Project ${index}\n\nRoutine project notes.`),
    );
    const sarah = makeNote("sarah", "# Sarah Holm\n\nSarah is the design lead for Atlas.");

    const result = retrieveNotes([...unrelated, sarah], "Who is Sarah Holm?");

    expect(result.matched).toBe(true);
    expect(result.notes[0].id).toBe("sarah");
    expect(result.notes[0].excerpt).toContain("Sarah is the design lead");
  });

  it("searches frontmatter metadata", () => {
    const note = makeNote(
      "atlas",
      "---\nowner: Sarah Holm\nstatus: active\n---\n# Atlas\n\nA confidential launch project.",
    );

    const result = retrieveNotes([note], "What is Sarah Holm working on?");

    expect(result.notes[0].id).toBe("atlas");
    expect(result.notes[0].excerpt).toContain("A confidential launch project.");
    expect(result.notes[0].excerpt).toContain("Relevant properties:\nowner: Sarah Holm");
    expect(result.notes[0].excerpt.indexOf("A confidential launch project.")).toBeLessThan(
      result.notes[0].excerpt.indexOf("Relevant properties:"),
    );
  });

  it("does not include unrelated or internal frontmatter in the model excerpt", () => {
    const note = makeNote(
      "navsea",
      "---\ngrimoire-id: secret\nstatus: Backlog\nJIRA Key: DS-286\n---\n# NAVSEA\n\nNAVSEA supports the naval systems command.",
    );

    const result = retrieveNotes([note], "What is NAVSEA?");

    expect(result.notes[0].excerpt).toContain("NAVSEA supports the naval systems command.");
    expect(result.notes[0].excerpt).not.toContain("grimoire-id");
    expect(result.notes[0].excerpt).toContain("status: Backlog");
    expect(result.notes[0].excerpt).toContain("JIRA Key: DS-286");
  });

  it("preserves the first non-empty body line in model context", () => {
    const note = makeNote("sarah", "Sarah Holm leads research.\nSecond line.");

    const result = retrieveNotes([note], "Sarah Holm");

    expect(result.notes[0].excerpt).toContain("Sarah Holm leads research.");
  });

  it("uses recent notes as a fallback for broad unmatched prompts", () => {
    const older = makeNote("older", "# Old note\n\nAlpha", "2026-01-01T00:00:00.000Z");
    const newer = makeNote("newer", "# New note\n\nBeta", "2026-02-01T00:00:00.000Z");

    const result = retrieveNotes([older, newer], "Summarize everything recently");

    expect(result.matched).toBe(false);
    expect(result.notes[0].id).toBe("newer");
  });

  it("answers an exact latest-note lookup without invoking the model", () => {
    const older = makeNote("older", "# Old note\n\nAlpha", "2026-01-01T00:00:00.000Z");
    const newer = makeNote("newer", "# New note\n\nBeta", "2026-02-01T00:00:00.000Z");

    const result = retrieveNotes([older, newer], "What is my latest note?");

    expect(result.notes.map((note) => note.id)).toEqual(["newer"]);
    expect(result.directAnswer).toBe("Your latest note is “New note”.");
  });

  it("keeps summary requests on the model-backed path", () => {
    const note = makeNote("newer", "# New note\n\nBeta", "2026-02-01T00:00:00.000Z");

    const result = retrieveNotes([note], "Summarize my latest note");

    expect(result.directAnswer).toBeUndefined();
  });

  it("answers an exact empty note from humanized frontmatter without the model", () => {
    const note = makeNote(
      "Jon Hofmann",
      "---\ntype: Person\ntitle: Jon Hofmann\ncompany:\n  - \"[[ESAB]]\"\n  - \nregion:\n  - \"[[Global]]\"\nrole: Product Managing Director - Digital Solutions\n---\n",
    );

    const result = retrieveNotes([note], "What about jon hofmann?");

    expect(result.kind).toBe("exact");
    expect(result.contextKind).toBe("matches");
    expect(result.directAnswer).toContain("Jon Hofmann is a people note.");
    expect(result.directAnswer).toContain("role: Product Managing Director - Digital Solutions.");
    expect(result.directAnswer).toContain("company: ESAB.");
    expect(result.directAnswer).not.toContain("type:");
    expect(result.directAnswer).not.toContain("[[");
  });

  it("returns a deterministic suggestion instead of assuming a fuzzy title", () => {
    const intended = makeNote("Jon Hofmann", "# Jon Hofmann\n\nLeads Digital Solutions.");
    const unrelated = [
      makeNote("Jonatan Akerlind", "# Jonatan Akerlind\n\nEngineer."),
      makeNote("Jonas Glimden", "# Jonas Glimden\n\nDesigner."),
      makeNote("John Deere", "# John Deere\n\nCompany."),
    ];

    const result = retrieveNotes([intended, ...unrelated], "Who is John Hoffman?");

    expect(result.kind).toBe("similar");
    expect(result.contextKind).toBe("similar");
    expect(result.directAnswer).toContain("couldn’t find an exact note");
    expect(result.notes.map((note) => note.title)).toEqual(["Jon Hofmann"]);
  });

  it("explains why an exact empty note cannot be summarized", () => {
    const note = makeNote("Project Atlas", "---\nstatus: Active\nowner: \"[[Alex Morgan]]\"\n---\n# Project Atlas\n\n");

    const result = retrieveNotes([note], "Summarize Project Atlas");

    expect(result.kind).toBe("exact");
    expect(result.directAnswer).toContain("has no body content to summarize");
    expect(result.directAnswer).toContain("status: Active.");
    expect(result.directAnswer).toContain("owner: Alex Morgan.");
  });

  it("reports an empty exact note with no properties", () => {
    const note = makeNote("Scratchpad", "# Scratchpad\n\n");

    const result = retrieveNotes([note], "Open Scratchpad");

    expect(result.directAnswer).toBe("I found “Scratchpad”, a people note, but it has no content or properties.");
  });

  it("treats case and accents as exact but changed letters as fuzzy", () => {
    const note = makeNote("José Launch Plan", "# José Launch Plan\n\nLaunch details.");

    expect(retrieveNotes([note], "Summarize jose launch plan").kind).toBe("exact");
    expect(retrieveNotes([note], "Summarize Jose Launch Plans").kind).toBe("similar");
  });

  it("returns duplicate exact titles as typed choices", () => {
    const meeting = { ...makeNote("meeting", "# Quarterly Review\n\nMeeting notes."), path: "Meetings/Quarterly Review.md" };
    const project = { ...makeNote("project", "# Quarterly Review\n\nProject notes."), path: "Projects/Quarterly Review.md" };

    const result = retrieveNotes([meeting, project], "Open Quarterly Review");

    expect(result.kind).toBe("ambiguous");
    expect(result.contextKind).toBe("choices");
    expect(result.notes.map((note) => note.type)).toEqual(["Meetings", "Projects"]);
    expect(result.directAnswer).toContain("Choose the one you meant");
  });

  it("caps deterministic metadata properties and values", () => {
    const note = makeNote(
      "Project Atlas",
      "---\none: 1\ntwo: 2\nthree: 3\nfour: 4\nfive: 5\nsix: 6\npeople:\n  - A\n  - B\n  - C\n  - D\n  - E\n  - F\n---\n",
    );

    const result = retrieveNotes([note], "Project Atlas");

    expect(result.directAnswer).toContain("one: 1.");
    expect(result.directAnswer).toContain("five: 5.");
    expect(result.directAnswer).not.toContain("six: 6.");
    expect(result.directAnswer).toContain("And 2 more properties.");
  });
});
