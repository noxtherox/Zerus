import {
  addExportVisitor$,
  addImportVisitor$,
  lexical,
  realmPlugin,
  type LexicalExportVisitor,
  type MdastImportVisitor,
} from "@mdxeditor/editor";
import type { RootContent } from "mdast";

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
    node.children.length === 1 &&
    node.children[0]?.type === "text" &&
    node.children[0].value === EMPTY_LINE_CHARACTER
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

const emptyParagraphImportVisitor: MdastImportVisitor<
  EmptyLineParagraph | LegacyEmptyLineElement
> = {
  priority: 100,
  testNode: (node): node is EmptyLineParagraph | LegacyEmptyLineElement =>
    isEmptyLineMarker(node as RootContent),
  visitNode: ({ actions }) => {
    // Do not import the marker itself. An actually empty Lexical paragraph is
    // editable like the blank line the user originally created.
    actions.addAndStepInto(lexical.$createParagraphNode());
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
    realm.pub(addImportVisitor$, emptyParagraphImportVisitor);
    realm.pub(addExportVisitor$, emptyParagraphExportVisitor);
  },
});
