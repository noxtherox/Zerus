import { describe, expect, it } from "vitest";
import { isEmptyLineMarker } from "./empty-paragraphs";

describe("empty editor paragraph preservation", () => {
  it("recognizes a standalone Markdown break as an empty editor line", () => {
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
});
