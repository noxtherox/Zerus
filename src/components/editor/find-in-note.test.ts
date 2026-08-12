import { describe, expect, it } from "vitest";
import { literalMatchRanges } from "./find-in-note";

describe("find in rendered table text", () => {
  it("finds every case-insensitive literal match", () => {
    expect(literalMatchRanges("Alpha beta ALPHA", "alpha")).toEqual([
      { from: 0, to: 5 },
      { from: 11, to: 16 },
    ]);
  });

  it("does not produce ranges for an empty query", () => {
    expect(literalMatchRanges("table text", "")).toEqual([]);
  });
});
