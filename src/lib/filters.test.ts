import { describe, expect, it } from "vitest";
import { filterNotes, propertyValueKey, type NoteListFilters } from "./filters";
import type { Note } from "./note-utils";
import { setFileHubReference } from "./file-hubs";
import { setLinkHubReference } from "./link-hubs";

function note(id: string, path: string, properties: string, updatedAt: string): Note {
  return {
    id,
    path,
    content: `---\n${properties}\n---\n# ${id}`,
    pinned: false,
    updatedAt,
  };
}

const notes = [
  note("one", "work/one.md", "status: active\ntags: [red, urgent]", "2026-07-16T08:00:00.000Z"),
  note("two", "personal/two.md", "status: active\ntags: [blue]", "2026-07-12T08:00:00.000Z"),
  note("three", "work/three.md", "status: done", "2026-06-01T08:00:00.000Z"),
  note("nested", "work/projects/nested.md", "status: active", "2026-07-15T08:00:00.000Z"),
];

const empty: NoteListFilters = {
  sort: "updated-desc",
  date: null,
  showArchived: false,
  typeKeys: [],
  fileExtensions: [],
  properties: [],
};

describe("note list filters", () => {
  it("searches the complete note collection regardless of type-tree batching", () => {
    const manyNotes = Array.from({ length: 35 }, (_, index) =>
      note(
        `note-${index + 1}`,
        `type-${index + 1}/note-${index + 1}.md`,
        "status: active",
        "2026-07-16T08:00:00.000Z",
      ),
    );

    expect(filterNotes(manyNotes, { kind: "all" }, "note-35")).toEqual([
      manyNotes[34],
    ]);
  });

  it("hides archived notes until the archived toggle is enabled", () => {
    const archived = { ...notes[0], id: "archived", archived: true };

    expect(
      filterNotes([notes[0], archived], { kind: "all" }, "").map(
        (item) => item.id,
      ),
    ).toEqual(["one"]);
    expect(
      filterNotes([notes[0], archived], { kind: "all" }, "", {
        ...empty,
        showArchived: true,
      }).map((item) => item.id),
    ).toEqual(["one", "archived"]);
  });

  it("can hide notes from nested sub-types for a selected type", () => {
    expect(
      filterNotes(notes, { kind: "type", path: ["work"] }, "").map(
        (item) => item.id,
      ),
    ).toContain("nested");
    expect(
      filterNotes(
        notes,
        { kind: "type", path: ["work"], includeSubtypes: false },
        "",
      ).map((item) => item.id),
    ).toEqual(["one", "three"]);
  });

  it("allows multiple types using OR semantics", () => {
    expect(filterNotes(notes, { kind: "all" }, "", { ...empty, typeKeys: ["work"] }).map((item) => item.id)).toEqual(["one", "three"]);
    expect(filterNotes(notes, { kind: "all" }, "", { ...empty, typeKeys: ["work", "personal"] }).map((item) => item.id)).toEqual(["one", "two", "three"]);
  });

  it("combines property filters and matches individual list values", () => {
    const filtered = filterNotes(notes, { kind: "all" }, "", {
      ...empty,
      properties: [
        { name: "status", valueKey: propertyValueKey("active") },
        { name: "tags", valueKey: propertyValueKey("red") },
      ],
    });
    expect(filtered.map((item) => item.id)).toEqual(["one"]);
  });

  it("filters by updated date from the local start of day", () => {
    const filtered = filterNotes(notes, { kind: "all" }, "", { ...empty, date: "last-7-days" }, new Date(2026, 6, 16, 12));
    expect(filtered.map((item) => item.id)).toEqual(["one", "nested", "two"]);
  });

  it("sorts by update time or title while keeping pinned notes first", () => {
    const pinned = { ...notes[2], pinned: true };

    expect(
      filterNotes(notes, { kind: "all" }, "", {
        ...empty,
        sort: "updated-asc",
      }).map((item) => item.id),
    ).toEqual(["three", "two", "nested", "one"]);
    expect(
      filterNotes([notes[0], notes[1], pinned], { kind: "all" }, "", {
        ...empty,
        sort: "title-desc",
      }).map((item) => item.id),
    ).toEqual(["three", "two", "one"]);
  });

  it("shows only active notes with attached documents in the files section", () => {
    const fileNote = {
      ...notes[0],
      content: setFileHubReference(notes[0].content, {
        id: "proposal-file",
        name: "Proposal.pdf",
        kind: "vault",
        path: "work/Proposal.pdf",
        managed: false,
      }),
    };
    const trashedFileNote = {
      ...fileNote,
      id: "trashed-file",
      path: ".trash/work/one.md",
    };

    expect(
      filterNotes([fileNote, notes[1], trashedFileNote], { kind: "files" }, "").map(
        (item) => item.id,
      ),
    ).toEqual(["one"]);
  });

  it("filters files by document extension", () => {
    const pdf = {
      ...notes[0],
      content: setFileHubReference(notes[0].content, {
        id: "pdf-file",
        name: "Proposal.pdf",
        kind: "vault",
        path: "work/Proposal.pdf",
        managed: false,
      }),
    };
    const presentation = {
      ...notes[1],
      content: setFileHubReference(notes[1].content, {
        id: "slides-file",
        name: "Slides.pptx",
        kind: "vault",
        path: "personal/Slides.pptx",
        managed: false,
      }),
    };

    expect(
      filterNotes(
        [pdf, presentation],
        { kind: "files" },
        "",
        { ...empty, fileExtensions: ["pptx"] },
      ).map((item) => item.id),
    ).toEqual(["two"]);
  });

  it("shows only active notes with URLs in the links section", () => {
    const linkNote = {
      ...notes[0],
      content: setLinkHubReference(notes[0].content, {
        id: "example-link",
        url: "https://example.com/guide",
      }),
    };
    const trashedLinkNote = {
      ...linkNote,
      id: "trashed-link",
      path: ".trash/work/one.md",
    };

    expect(
      filterNotes(
        [linkNote, notes[1], trashedLinkNote],
        { kind: "links" },
        "",
      ).map((item) => item.id),
    ).toEqual(["one"]);
  });
});
