import { describe, expect, it } from "vitest";
import type { Note } from "@/lib/note-utils";
import {
  preserveRelationsForTypeMove,
  recoverLegacyMovedRelations,
} from "./relation-schema-migrations";

function note(path: string, content: string): Note {
  return {
    id: path,
    path,
    content,
    pinned: false,
    updatedAt: new Date(0).toISOString(),
  };
}

describe("relation schema migrations", () => {
  const productRelation = {
    name: "Product",
    type: "relation" as const,
    relationTypeKey: "Products",
    relationMultiple: true,
  };

  it("preserves populated relations when a note changes type", () => {
    const schemas = { "Customer Feedback": [productRelation] };
    const moved = note(
      "Customer Feedback/Feedback.md",
      "---\nProduct:\n  - WeldCloud Fleet\n---\n# Feedback\n",
    );

    expect(
      preserveRelationsForTypeMove(moved, ["Work", "Discussions"], schemas),
    ).toEqual({
      ...schemas,
      "Work/Discussions": [productRelation],
    });
  });

  it("does not override a destination field with the same name", () => {
    const schemas = {
      "Customer Feedback": [productRelation],
      Work: [{ name: "Product", type: "text" as const }],
    };
    const moved = note(
      "Customer Feedback/Feedback.md",
      "---\nProduct: WeldCloud Fleet\n---\n# Feedback\n",
    );

    expect(preserveRelationsForTypeMove(moved, ["Work"], schemas)).toBe(schemas);
  });

  it("repairs a legacy moved relation when its targets resolve", () => {
    const schemas = { "Customer Feedback": [productRelation] };
    const notes = [
      note(
        "Work/Discussions/Feedback.md",
        "---\nProduct:\n  - WeldCloud Fleet\n---\n# Feedback\n",
      ),
      note("Products/WeldCloud Fleet.md", "# WeldCloud Fleet\n"),
    ];

    expect(recoverLegacyMovedRelations(notes, schemas)).toEqual({
      ...schemas,
      "Work/Discussions": [productRelation],
    });
  });

  it("leaves ambiguous or unresolved ad-hoc properties alone", () => {
    const schemas = {
      "Customer Feedback": [productRelation],
      Notes: [{ name: "Product", type: "text" as const }],
    };
    const notes = [
      note(
        "Work/Discussions/Feedback.md",
        "---\nProduct: Not a note title\n---\n# Feedback\n",
      ),
      note("Products/WeldCloud Fleet.md", "# WeldCloud Fleet\n"),
    ];

    expect(recoverLegacyMovedRelations(notes, schemas)).toBe(schemas);
  });
});
