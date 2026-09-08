import { describe, expect, it } from "vitest";
import { findPdfMatches } from "./pdf-search";

describe("PDF text search", () => {
  it("finds literal case-insensitive matches in page order", () => {
    expect(findPdfMatches(["A+B a+b", "A+B"], "a+b")).toEqual([
      { page: 1, start: 0, end: 3 }, { page: 1, start: 4, end: 7 }, { page: 2, start: 0, end: 3 },
    ]);
  });
  it("matches across line breaks and repeated spaces with original highlight offsets", () => {
    expect(findPdfMatches(["first\n   second"], "first second")).toEqual([{ page: 1, start: 0, end: 15 }]);
  });
  it("handles ligatures, composed accents, and surrogate pairs", () => {
    expect(findPdfMatches(["ﬁle Café 😀"], "file")).toEqual([{ page: 1, start: 0, end: 3 }]);
    expect(findPdfMatches(["ﬁle Café 😀"], "café")).toEqual([{ page: 1, start: 4, end: 8 }]);
    expect(findPdfMatches(["ﬁle Café 😀"], "😀")).toEqual([{ page: 1, start: 9, end: 11 }]);
  });
  it("ignores empty queries and pages without text", () => {
    expect(findPdfMatches(["text"], "  ")).toEqual([]);
    expect(findPdfMatches([""], "text")).toEqual([]);
  });
});
