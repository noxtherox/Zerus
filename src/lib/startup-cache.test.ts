import { expect, it } from "vitest";
import { compactStartupNotes } from "./startup-cache";

it("keeps the selected full note within a bounded cache without truncating other bodies", () => {
  const selected = { id: "selected", content: "Full note. ".repeat(100) };
  const notes = [{ id: "large", content: "x".repeat(5000) }, selected, { id: "placeholder" }];
  const result = compactStartupNotes(notes, "selected", 3000);
  expect(result[0]).toEqual({ id: "large" });
  expect(result[1]).toEqual(selected);
  expect(result[2]).toEqual({ id: "placeholder" });
  expect(compactStartupNotes(notes, undefined, 0)).toEqual(notes.map(({ id }) => ({ id })));
});
