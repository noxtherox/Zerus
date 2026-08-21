import { describe, expect, it } from "vitest";
import { inlineMarkupEdit } from "./inline-markup";

describe("inlineMarkupEdit", () => {
  it.each([
    ["**", "bold"],
    ["*", "italic"],
    ["~~", "strikethrough"],
  ])("keeps a selected line's newline outside %s markup", (marker) => {
    const edit = inlineMarkupEdit("Full line\n", marker, "placeholder");

    expect(edit.insert).toBe(`${marker}Full line${marker}\n`);
    expect(edit.selectionFrom).toBe(marker.length);
    expect(edit.selectionTo).toBe(marker.length + "Full line".length);
  });

  it("keeps a list prefix outside inline markup", () => {
    const edit = inlineMarkupEdit("  - Full list item\n", "**", "bold text");

    expect(edit.insert).toBe("  - **Full list item**\n");
    expect(edit.selectionFrom).toBe(6);
    expect(edit.selectionTo).toBe(20);
  });

  it("removes markup from a fully selected formatted list line", () => {
    const edit = inlineMarkupEdit("- **Full list item**\n", "**", "bold text");

    expect(edit.insert).toBe("- Full list item\n");
    expect(edit.selectionFrom).toBe(2);
    expect(edit.selectionTo).toBe(16);
  });

  it("retains the placeholder behavior for an empty selection", () => {
    expect(inlineMarkupEdit("", "**", "bold text")).toEqual({
      insert: "**bold text**",
      selectionFrom: 2,
      selectionTo: 11,
    });
  });
});
