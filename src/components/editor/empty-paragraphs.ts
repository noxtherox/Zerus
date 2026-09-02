import {
  addExportVisitor$,
  addImportVisitor$,
  lexical,
  realmPlugin,
  type LexicalExportVisitor,
  type MdastImportVisitor,
} from "@mdxeditor/editor";
import type { RootContent } from "mdast";

type EmptyLineElement = Extract<RootContent, { type: "mdxJsxFlowElement" }>;

const EMPTY_LINE_ELEMENT: EmptyLineElement = {
  type: "mdxJsxFlowElement",
  name: "br",
  attributes: [],
  children: [],
};

/** True for the standalone break used to round-trip one empty editor line. */
export function isEmptyLineMarker(node: RootContent): node is EmptyLineElement {
  return (
    node.type === "mdxJsxFlowElement" &&
    node.name === "br" &&
    node.attributes.length === 0 &&
    node.children.length === 0
  );
}

const emptyParagraphImportVisitor: MdastImportVisitor<EmptyLineElement> = {
  priority: 100,
  testNode: (node): node is EmptyLineElement =>
    isEmptyLineMarker(node as RootContent),
  visitNode: ({ actions }) => {
    // Do not import the marker itself. An actually empty Lexical paragraph is
    // editable like the blank line the user originally created.
    actions.addAndStepInto(lexical.$createParagraphNode());
  },
};

const emptyParagraphExportVisitor: LexicalExportVisitor<
  lexical.ParagraphNode,
  EmptyLineElement
> = {
  priority: 100,
  testLexicalNode: lexical.$isParagraphNode,
  visitLexicalNode: ({ lexicalNode, mdastParent, actions }) => {
    const parent = lexicalNode.getParent();
    const isOnlyDocumentParagraph =
      parent?.getType() === "root" && parent.getChildrenSize() === 1;
    if (!lexicalNode.isEmpty() || isOnlyDocumentParagraph) {
      actions.nextVisitor();
      return;
    }

    // A standalone HTML break is valid, visible Markdown and survives parsing.
    // The import visitor above turns it back into an empty editor paragraph.
    actions.appendToParent(mdastParent, { ...EMPTY_LINE_ELEMENT });
  },
};

/** Keeps intentional blank editor lines when Markdown is saved and reopened. */
export const preserveEmptyParagraphsPlugin = realmPlugin({
  init(realm) {
    realm.pub(addImportVisitor$, emptyParagraphImportVisitor);
    realm.pub(addExportVisitor$, emptyParagraphExportVisitor);
  },
});
