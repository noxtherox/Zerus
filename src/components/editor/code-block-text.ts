import type { CodeBlockNode } from "@mdxeditor/editor";
import { $createParagraphNode, $createLineBreakNode, $createTextNode } from "lexical";

export function codeBlockToParagraph(node: CodeBlockNode) {
  const paragraph = $createParagraphNode();
  node.getCode().split("\n").forEach((line, index) => {
    if (index) paragraph.append($createLineBreakNode());
    if (line) paragraph.append($createTextNode(line));
  });
  node.replace(paragraph);
  return paragraph;
}

