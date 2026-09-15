import { describe, expect, it } from "vitest";
import { createEditor, $getRoot } from "lexical";
import { CodeBlockNode, $createCodeBlockNode } from "@mdxeditor/editor";
import { codeBlockToParagraph } from "./code-block-text";

describe("turning a code block back into text", () => {
  it.each(["", "  hello\n\n**literal** {name}\n", "first\nsecond\nthird", "\tIndented\n    spaces"])("preserves literal contents and line breaks: %j", code => {
    const editor = createEditor({ nodes: [CodeBlockNode], onError: error => { throw error; } });
    editor.update(() => {
      const block = $createCodeBlockNode({ code, language: "text", meta: "" });
      $getRoot().append(block);
      const paragraph = codeBlockToParagraph(block);
      expect(paragraph.getType()).toBe("paragraph");
      expect(paragraph.getTextContent()).toBe(code);
      expect($getRoot().getChildrenSize()).toBe(1);
    }, { discrete: true });
  });
});
