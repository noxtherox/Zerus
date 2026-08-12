import { describe, expect, it } from "vitest";
import { buildTypeTreeFromCounts } from "./note-utils";

describe("buildTypeTreeFromCounts", () => {
  it("rolls direct counts up through parent types and preserves empty types", () => {
    const tree = buildTypeTreeFromCounts(
      { "work/projects": 8, "work/meetings": 3, personal: 2 },
      [["ideas"]],
    );

    expect(tree).toEqual([
      { name: "ideas", path: ["ideas"], count: 0, children: [] },
      { name: "personal", path: ["personal"], count: 2, children: [] },
      {
        name: "work",
        path: ["work"],
        count: 11,
        children: [
          { name: "meetings", path: ["work", "meetings"], count: 3, children: [] },
          { name: "projects", path: ["work", "projects"], count: 8, children: [] },
        ],
      },
    ]);
  });
});
