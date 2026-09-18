import { describe, expect, it } from "vitest";
import {
  markdownImageReferences,
  replaceMarkdownImageReferences,
} from "./markdown-image-references";

describe("Markdown image references", () => {
  it("finds inline and reference-style image destinations without touching links", () => {
    const content = [
      "![inline](pictures/one.png)",
      "![wrapped](<pictures/two two.png> \"Title\")",
      "![reference][diagram]",
      "",
      "[diagram]: ../three.png 'Diagram'",
      "[ordinary](document.md)",
    ].join("\n");

    const references = markdownImageReferences(content);
    expect(references.map((reference) => reference.path)).toEqual([
      "pictures/one.png",
      "pictures/two two.png",
      "../three.png",
    ]);
    const replacements = new Map(
      references.map((reference, index) => [reference.start, `assets/${index}.png`]),
    );
    expect(replaceMarkdownImageReferences(content, replacements, references)).toBe([
      "![inline](assets/0.png)",
      "![wrapped](<assets/1.png> \"Title\")",
      "![reference][diagram]",
      "",
      "[diagram]: assets/2.png 'Diagram'",
      "[ordinary](document.md)",
    ].join("\n"));
  });

  it("returns each repeated inline reference independently", () => {
    const content = "![one](same.png) ![two](same.png)";
    expect(markdownImageReferences(content).map((reference) => reference.path))
      .toEqual(["same.png", "same.png"]);
  });
});
