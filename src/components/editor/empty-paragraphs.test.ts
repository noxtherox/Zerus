import { describe, expect, it, vi } from "vitest";
import {
  EMPTY_LINE_CHARACTER,
  isEmptyLineMarker,
  preserveEmptyParagraphsPlugin,
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


async function editorFixture() {
    const mdx = await import("@mdxeditor/editor");
    const { Realm } = await import("@mdxeditor/gurx");
    const lexical = await import("lexical");
    const { createEditor, $getRoot } = lexical;
    const { mdxJsxFromMarkdown, mdxJsxToMarkdown } = await import("mdast-util-mdx-jsx");
    const { toMarkdown } = await import("mdast-util-to-markdown");
    const { prepareMarkdownForMdxEditor } = await import("./mdx-compat");
    // These pinned runtime exports are omitted from MDXEditor's declarations.
    // Exercise the actual core/plugin registry rather than exporting private visitors.
    const runtime = mdx as typeof mdx & {
      corePlugin: () => ReturnType<typeof preserveEmptyParagraphsPlugin>;
      importMarkdownToLexical: (options: Record<string, unknown>) => void;
    };
    const realm = new Realm();
    runtime.corePlugin().init?.(realm);
    mdx.listsPlugin().init?.(realm);
    mdx.quotePlugin().init?.(realm);
    mdx.headingsPlugin().init?.(realm);
    preserveEmptyParagraphsPlugin().init?.(realm);
    const editor = createEditor({ nodes: realm.getValue(mdx.usedLexicalNodes$), onError(error) { throw error; } });
    vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => setTimeout(() => callback(performance.now()), 0));
    vi.stubGlobal("cancelAnimationFrame", clearTimeout);
    realm.pub(mdx.rootEditor$, editor);
    function importSource(value: string) {
      editor.update(() => {
        $getRoot().clear();
        runtime.importMarkdownToLexical({ root: $getRoot(), markdown: prepareMarkdownForMdxEditor(value), visitors: realm.getValue(mdx.importVisitors$), syntaxExtensions: realm.getValue(mdx.syntaxExtensions$), mdastExtensions: [mdxJsxFromMarkdown()] });
      }, { discrete: true });
    }
    function exportSource() {
      let saved = "";
      editor.getEditorState().read(() => {
        const root = mdx.exportLexicalTreeToMdast({ root: $getRoot(), visitors: realm.getValue(mdx.exportVisitors$), jsxComponentDescriptors: [], jsxIsAvailable: false, addImportStatements: false });
        saved = toMarkdown(root, { extensions: [mdxJsxToMarkdown()], bullet: "-" });
      });
      return saved;
    }
    return { editor, lexical, importSource, exportSource, close() { realm.pub(mdx.rootEditor$, null); vi.unstubAllGlobals(); } };
}

describe("native inline break interoperability", () => {
  it.each([
    ["- abcX<br>\n- Sib\n", "abcX\n"],
    ["- <br>Xabc\n- Sib\n", "\nXabc"],
    ["- aX<br><br>Ybc\n- Sib\n", "aX\n\nYbc"],
    ["> a<br><br>b\n", "a\n\nb"],
    ["Before<br>After\n", "Before\nAfter"],
    ["# Before<br>After\n", "Before\nAfter"],
  ])("keeps editable line breaks through typing, serialization and reopening: %s", async (source, expectedText) => {
    const fixture = await editorFixture();
    const { editor, importSource, exportSource, lexical } = fixture;
    const { $getRoot, $isElementNode, $isLineBreakNode, $getSelection } = lexical;
    function body() {
      let node = $getRoot().getFirstChildOrThrow();
      if ($isElementNode(node) && (node.getType() === "list" || node.getType() === "quote")) node = node.getFirstChildOrThrow();
      if (!$isElementNode(node)) throw new Error("Expected the receiving paragraph/item");
      return node;
    }
    try {
      importSource(source);
      editor.getEditorState().read(() => {
        expect(body().getTextContent()).toBe(expectedText);
        expect(body().getChildren().filter($isLineBreakNode)).toHaveLength(expectedText.split("\n").length - 1);
      });
      // A range immediately after a break must be editable as a text position.
      editor.update(() => {
        const paragraph = body(), index = paragraph.getChildren().findIndex($isLineBreakNode);
        expect(index).toBeGreaterThanOrEqual(0);
        paragraph.select(index + 1, index + 1);
        $getSelection()?.insertText("!");
      }, { discrete: true });
      const typed = expectedText.replace("\n", "\n!");
      const json = editor.getEditorState().toJSON();
      editor.setEditorState(editor.parseEditorState(json));
      editor.getEditorState().read(() => { expect(body().getTextContent()).toBe(typed); });
      const saved = exportSource();
      expect(saved.match(/<br \/>/g)).toHaveLength(expectedText.split("\n").length - 1);
      importSource(saved);
      editor.getEditorState().read(() => {
        expect(body().getTextContent()).toBe(typed);
        expect(body().getChildren().filter($isLineBreakNode)).toHaveLength(expectedText.split("\n").length - 1);
      });
    } finally { fixture.close(); }
  });
});


describe("native empty paragraph interoperability", () => {
  it.each([
    ["A\n\n\u200B\n\nB\n", ["A", "", "B"], "A\n\n\u200B\n\nB\n"],
    ["A\n\n\u200B<br>\n\nB\n", ["A", "\n", "B"], "A\n\n\u200B<br />\n\nB\n"],
    ["A\n\n\u200B<br><br>\n\nB\n", ["A", "\n\n", "B"], "A\n\n\u200B<br /><br />\n\nB\n"],
    ["A\n\n<br />\n\nB\n", ["A", "", "B"], "A\n\n\u200B\n\nB\n"],
    ["Before\u200Bafter\n", ["Before\u200Bafter"], "Before\u200Bafter\n"]
  ])("keeps blank paragraphs editable without importing the marker as text: %s", async (source, expected, canonical) => {
    const fixture = await editorFixture();
    const { editor, importSource, exportSource, lexical } = fixture;
    try {
      importSource(source as string);
      editor.getEditorState().read(() => {
        expect(lexical.$getRoot().getChildren().map(node => node.getTextContent())).toEqual(expected);
      });
      const saved = exportSource();
      expect(saved).toBe(canonical);
      importSource(saved);
      editor.getEditorState().read(() => {
        expect(lexical.$getRoot().getChildren().map(node => node.getTextContent())).toEqual(expected);
      });
      if (expected.length > 1) {
        editor.update(() => {
          const paragraph = lexical.$getRoot().getChildAtIndex(1);
          if (!lexical.$isElementNode(paragraph)) throw new Error("Expected the blank paragraph");
          paragraph.selectStart();
          const selection = lexical.$getSelection();
          if (!lexical.$isRangeSelection(selection)) throw new Error("Expected a typing selection");
          selection.insertLineBreak();
        }, { discrete: true });
        const withTypedBreak = exportSource();
        expect(withTypedBreak).toBe("A\n\n" + EMPTY_LINE_CHARACTER + "<br />".repeat(expected[1].length + 1) + "\n\nB\n");
        importSource(withTypedBreak);
        editor.getEditorState().read(() => {
          expect(lexical.$getRoot().getChildren().map(node => node.getTextContent())).toEqual(["A", "\n" + expected[1], "B"]);
        });
        editor.update(() => {
          const paragraph = lexical.$getRoot().getChildAtIndex(1);
          if (!lexical.$isElementNode(paragraph)) throw new Error("Expected the blank paragraph");
          paragraph.selectStart(); lexical.$getSelection()?.insertText("Typed");
        }, { discrete: true });
        editor.getEditorState().read(() => {
          const actual = lexical.$getRoot().getChildren().map(node => node.getTextContent());
          expect(actual).toEqual(["A", "Typed\n" + expected[1], "B"]);
          expect(actual.every(text => !text.includes(EMPTY_LINE_CHARACTER))).toBe(true);
        });
      }
    } finally { fixture.close(); }
  });
});
