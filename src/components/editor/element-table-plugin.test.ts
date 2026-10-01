import {
  $createTextNode,
  $getRoot,
  $isElementNode,
  $isParagraphNode,
  $isTextNode,
  createEditor,
  type LexicalNode,
} from "lexical";
import {
  $isTableCellNode,
  $isTableNode,
  $isTableRowNode,
  TableCellNode,
  TableNode,
  TableRowNode,
} from "@lexical/table";
import type * as Mdast from "mdast";
import { fromMarkdown } from "mdast-util-from-markdown";
import { gfmTableFromMarkdown, gfmTableToMarkdown } from "mdast-util-gfm-table";
import { toMarkdown } from "mdast-util-to-markdown";
import { gfmTable } from "micromark-extension-gfm-table";
import { mdxJsx } from "micromark-extension-mdx-jsx";
import { mdxMd } from "micromark-extension-mdx-md";
import { mdxJsxFromMarkdown } from "mdast-util-mdx-jsx";
import { describe, expect, it } from "vitest";
import { $createElementTable, $exportElementTable } from "./element-table-model";
import { prepareMarkdownForMdxEditor } from "./mdx-compat";
import {
  getTableColumnWidths,
  tableWidthsFromMarkdown,
  withTableWidthSerialization,
} from "./table-widths";

function tableFixture(rows: number, columns: number): Mdast.Table {
  return {
    type: "table",
    align: Array.from({ length: columns }, (_, index) =>
      index === 1 ? "center" : null,
    ),
    children: Array.from({ length: rows }, (_, rowIndex) => ({
      type: "tableRow",
      children: Array.from({ length: columns }, (_, columnIndex) => ({
        type: "tableCell",
        children: [{ type: "text", value: `${rowIndex}:${columnIndex}` }],
      })),
    })),
  };
}

function appendPlainText(source: Mdast.Parent, parent: LexicalNode) {
  if (!$isElementNode(parent)) throw new Error("Expected an element parent");
  source.children.forEach((child) => {
    if (child.type === "text") parent.append($createTextNode(child.value));
  });
}

describe("element table plugin", () => {
  it("keeps a 103-cell document in one Lexical tree", () => {
    const editor = createEditor({ nodes: [TableNode, TableRowNode, TableCellNode] });
    const fixture = tableFixture(103, 1);

    editor.update(
      () => {
        $getRoot().append($createElementTable(fixture, appendPlainText));
      },
      { discrete: true },
    );

    editor.getEditorState().read(() => {
      const table = $getRoot().getFirstChild();
      expect($isTableNode(table)).toBe(true);
      if (!$isTableNode(table)) return;
      const rows = table.getChildren().filter($isTableRowNode);
      const cells = rows.flatMap((row) => row.getChildren().filter($isTableCellNode));
      expect(rows).toHaveLength(103);
      expect(cells).toHaveLength(103);
      expect(cells.every((cell) => $isParagraphNode(cell.getFirstChild()))).toBe(true);
    });
  });

  it("round-trips dimensions, text, headers, and alignment", () => {
    const editor = createEditor({ nodes: [TableNode, TableRowNode, TableCellNode] });
    const fixture = tableFixture(4, 3);

    editor.update(
      () => {
        const table = $createElementTable(fixture, appendPlainText);
        $getRoot().append(table);
        const exported = $exportElementTable(table, {
          visit(node, parent) {
            if ($isTextNode(node)) parent.children.push({ type: "text", value: node.getTextContent() });
          },
          visitChildren(node, parent) {
            if (!$isElementNode(node)) return;
            node.getChildren().forEach((child) => {
              if ($isTextNode(child)) {
                parent.children.push({ type: "text", value: child.getTextContent() });
              }
            });
          },
        });
        expect(exported).toEqual(fixture);
        const firstRow = table.getFirstChild();
        expect($isTableRowNode(firstRow)).toBe(true);
        if (!$isTableRowNode(firstRow)) return;
        expect(
          firstRow.getChildren().every((cell) =>
            $isTableCellNode(cell) ? cell.hasHeader() : false,
          ),
        ).toBe(true);
      },
      { discrete: true },
    );
  });

  it.each(["CommonMark", "formatted editor", "escaped marker", "HTML fallback", "quoted table", "list table"])(
    "preserves resized column widths through %s without visible metadata",
    (mode) => {
      const fixture = tableFixture(2, 3);
      const editor = createEditor({ nodes: [TableNode, TableRowNode, TableCellNode] });
      let exported: Mdast.Table | null = null;

      editor.update(
        () => {
          const table = $createElementTable(fixture, appendPlainText);
          table.setColWidths([120, 240, 160]);
          $getRoot().append(table);
          exported = $exportElementTable(table, {
            visit() {},
            visitChildren(node, parent) {
              if (!$isElementNode(node)) return;
              node.getChildren().forEach((child) => {
                if ($isTextNode(child)) {
                  parent.children.push({ type: "text", value: child.getTextContent() });
                }
              });
            },
          });
        },
        { discrete: true },
      );

      expect(exported).not.toBeNull();
      const markdown = toMarkdown(exported!, {
        extensions: [withTableWidthSerialization(gfmTableToMarkdown())],
      });
      expect(markdown).toContain("<!-- zerus-table-widths: 120,240,160 -->");

      let source = markdown;
      if (mode === "escaped marker") source = source.replace("<!--", "\\<!--");
      if (mode === "HTML fallback") source = `<div title=unquoted>Text</div>\n\n${source}`;
      if (mode === "quoted table") source = source.trimEnd().split("\n").map((line) => `> ${line}`).join("\n");
      if (mode === "list table") source = `- Table:\n\n${source.trimEnd().split("\n").map((line) => `  ${line}`).join("\n")}`;
      const usesMdx = mode !== "CommonMark";
      const prepared = usesMdx ? prepareMarkdownForMdxEditor(source) : source;
      const reparsed = fromMarkdown(prepared, {
        extensions: [gfmTable(), ...(usesMdx ? [mdxJsx(), mdxMd()] : [])],
        mdastExtensions: [gfmTableFromMarkdown(), ...(usesMdx ? [mdxJsxFromMarkdown()] : []), tableWidthsFromMarkdown],
      });
      const container = mode === "quoted table"
        ? reparsed.children[0] as Mdast.Blockquote
        : mode === "list table"
          ? (reparsed.children[0] as Mdast.List).children[0]
          : reparsed;
      const table = container.children.find((node) => node.type === "table");
      expect(table?.type).toBe("table");
      if (table?.type !== "table") throw new Error("Expected a restored table");
      expect(getTableColumnWidths(table)).toEqual([120, 240, 160]);
      expect(container.children.filter((node) => node !== table)).toHaveLength(mode === "HTML fallback" || mode === "list table" ? 1 : 0);
      if (usesMdx) expect(prepareMarkdownForMdxEditor(prepared)).toBe(prepared);
    },
  );
});
