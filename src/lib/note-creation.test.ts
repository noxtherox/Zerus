import { describe, expect, it } from "vitest";
import type { NoteFilter } from "./filters";
import { noteCreationType } from "./note-creation";

describe("noteCreationType", () => {
  it("uses the configured default in every type-neutral section", () => {
    const configuredDefault = ["Notes"];
    const filters: NoteFilter[] = [
      { kind: "all" },
      { kind: "external" },
      { kind: "files" },
      { kind: "links" },
      { kind: "trash" },
    ];

    for (const filter of filters) {
      expect(noteCreationType(filter, configuredDefault)).toEqual(["Notes"]);
    }
  });

  it("keeps an explicitly selected type", () => {
    expect(
      noteCreationType(
        { kind: "type", path: ["Work", "Projects"] },
        ["Notes"],
      ),
    ).toEqual(["Work", "Projects"]);
  });
});
