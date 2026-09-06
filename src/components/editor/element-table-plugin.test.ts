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
import { describe, expect, it } from "vitest";
import { $createElementTable, $exportElementTable } from "./element-table-model";

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
});
