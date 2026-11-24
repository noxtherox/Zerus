import {
  addExportVisitor$,
  addImportVisitor$,
  addLexicalNode$,
  lexical,
  realmPlugin,
  type LexicalExportVisitor,
  type MdastImportVisitor,
} from "@mdxeditor/editor";
import type { Nodes, RootContent } from "mdast";

type EmptyLineParagraph = Extract<RootContent, { type: "paragraph" }>;
type LegacyEmptyLineElement = Extract<
  RootContent,
  { type: "mdxJsxFlowElement" }
>;

export const EMPTY_LINE_CHARACTER = "\u200B";

const EMPTY_LINE_PARAGRAPH: EmptyLineParagraph = {
  type: "paragraph",
  children: [{ type: "text", value: EMPTY_LINE_CHARACTER }],
};

/** True for an invisible paragraph marker or the legacy standalone HTML break. */
export function isEmptyLineMarker(node: RootContent): boolean {
  if (
    node.type === "paragraph" &&
    node.children.length >= 1 &&
    node.children[0]?.type === "text" &&
    node.children[0].value === EMPTY_LINE_CHARACTER &&
    node.children.slice(1).every(isInlineBreakElement)
  ) {
    return true;
  }

  return (
    node.type === "mdxJsxFlowElement" &&
    node.name === "br" &&
    node.attributes.length === 0 &&
    node.children.length === 0
  );
}

// Retain explicit inline HTML break spelling while giving Lexical a real
// line-break node for text extraction, caret movement and selection replacement.
// Text-bearing keyboard paragraphs keep their existing export policy.
class HTMLLineBreakNode extends lexical.LineBreakNode {
  static getType() { return "zerus-html-linebreak"; }
  static clone(node: HTMLLineBreakNode) { return new HTMLLineBreakNode(node.getKey()); }
  static importJSON(value: lexical.SerializedLineBreakNode) {
    return lexical.$applyNodeReplacement(new HTMLLineBreakNode()).updateFromJSON(value);
  }
}

type InlineBreakElement = Extract<Nodes, { type: "mdxJsxTextElement" }>;

function isInlineBreakElement(node: Nodes): node is InlineBreakElement {
  return node.type === "mdxJsxTextElement" && node.name === "br" &&
    node.attributes.length === 0 && node.children.length === 0;
}

const inlineBreakImportVisitor: MdastImportVisitor<InlineBreakElement> = {
  priority: 110,
  testNode: isInlineBreakElement,
  visitNode: ({ actions }) => {
    actions.addAndStepInto(lexical.$applyNodeReplacement(new HTMLLineBreakNode()));
  },
};

const inlineBreakExportVisitor: LexicalExportVisitor<HTMLLineBreakNode, InlineBreakElement> = {
  priority: 110,
  testLexicalNode: (node): node is HTMLLineBreakNode => node instanceof HTMLLineBreakNode,
  visitLexicalNode: ({ actions, mdastParent }) => {
    actions.appendToParent(mdastParent, { type: "mdxJsxTextElement", name: "br", attributes: [], children: [] });
  },
};

const emptyParagraphImportVisitor: MdastImportVisitor<
  EmptyLineParagraph | LegacyEmptyLineElement
> = {
  priority: 100,
  testNode: (node): node is EmptyLineParagraph | LegacyEmptyLineElement =>
    isEmptyLineMarker(node as RootContent),
  visitNode: ({ lexicalParent, mdastNode }) => {
    // Append directly: addAndStepInto would also import the hidden marker text.
    if (!lexical.$isElementNode(lexicalParent)) {
      throw new Error("An empty paragraph needs a container");
    }
    const paragraph = lexical.$createParagraphNode();
    lexicalParent.append(paragraph);
    if (mdastNode.type === "paragraph") {
      mdastNode.children.slice(1).filter(isInlineBreakElement).forEach(() => {
        paragraph.append(lexical.$applyNodeReplacement(new HTMLLineBreakNode()));
      });
    }
  },
};

const emptyParagraphExportVisitor: LexicalExportVisitor<
  lexical.ParagraphNode,
  EmptyLineParagraph
> = {
  priority: 100,
  testLexicalNode: lexical.$isParagraphNode,
  visitLexicalNode: ({ lexicalNode, mdastParent, actions }) => {
    const parent = lexicalNode.getParent();
    const isOnlyDocumentParagraph =
      parent?.getType() === "root" && parent.getChildrenSize() === 1;
    const children = lexicalNode.getChildren();
    if (children.length > 0 && children.every(lexical.$isLineBreakNode)) {
      // The anchor prevents a break-only paragraph from becoming a standalone
      // HTML block, whose legacy meaning is a single empty paragraph.
      actions.appendToParent(mdastParent, {
        type: "paragraph",
        children: [{ type: "text", value: EMPTY_LINE_CHARACTER }, ...children.map(() => ({
          type: "mdxJsxTextElement" as const, name: "br", attributes: [], children: [],
        }))],
      });
      return;
    }
    if (!lexicalNode.isEmpty() || isOnlyDocumentParagraph) {
      actions.nextVisitor();
      return;
    }

    // A zero-width character survives Markdown round-trips without exposing an
    // HTML tag in renderers that do not know about Zerus's empty-line marker.
    actions.appendToParent(mdastParent, {
      ...EMPTY_LINE_PARAGRAPH,
      children: [...EMPTY_LINE_PARAGRAPH.children],
    });
  },
};

/** Keeps intentional blank editor lines when Markdown is saved and reopened. */
export const preserveEmptyParagraphsPlugin = realmPlugin({
  init(realm) {
    realm.pub(addLexicalNode$, HTMLLineBreakNode);
    realm.pub(addImportVisitor$, [emptyParagraphImportVisitor, inlineBreakImportVisitor]);
    realm.pub(addExportVisitor$, [emptyParagraphExportVisitor, inlineBreakExportVisitor]);
  },
});
