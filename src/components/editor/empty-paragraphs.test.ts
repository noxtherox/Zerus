import { describe, expect, it } from "vitest";
import {
  EMPTY_LINE_CHARACTER,
  isEmptyLineMarker,
} from "./empty-paragraphs";

describe("empty editor paragraph preservation", () => {
  it("recognizes an invisible paragraph as an empty editor line", () => {
    expect(
      isEmptyLineMarker({
        type: "paragraph",
        children: [{ type: "text", value: EMPTY_LINE_CHARACTER }],
      }),
    ).toBe(true);
  });

  it("recognizes a legacy standalone Markdown break as an empty editor line", () => {
    expect(
      isEmptyLineMarker({
        type: "mdxJsxFlowElement",
        name: "br",
        attributes: [],
        children: [],
      }),
    ).toBe(true);
  });

  it("does not consume inline breaks that are part of real text", () => {
    expect(
      isEmptyLineMarker({
        type: "paragraph",
        children: [
          { type: "text", value: "Before" },
          {
            type: "mdxJsxTextElement",
            name: "br",
            attributes: [],
            children: [],
          },
        ],
      }),
    ).toBe(false);
  });

  it("does not consume a zero-width character inside real text", () => {
    expect(
      isEmptyLineMarker({
        type: "paragraph",
        children: [{ type: "text", value: `Before${EMPTY_LINE_CHARACTER}` }],
      }),
    ).toBe(false);
  });
});
