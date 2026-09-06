import {
  $createTableCellNode,
  $createTableNode,
  $createTableRowNode,
  $isTableCellNode,
  $isTableNode,
  $isTableRowNode,
  TableCellHeaderStates,
  type TableCellNode,
  type TableNode,
} from "@lexical/table";
import type {
  LexicalExportVisitor,
  MdastImportVisitor,
} from "@mdxeditor/editor";
import {
  $createParagraphNode,
  $isElementNode,
  $isParagraphNode,
  type LexicalNode,
  type ParagraphNode,
} from "lexical";
import type * as Mdast from "mdast";

import { LargeTableNode } from "./large-table-node";
import { isLargeTable, normalizeTable } from "./table-data";

type ImportChildren = (
  source: Mdast.Parent,
  parent: TableCellNode | ParagraphNode,
) => void;

type ExportActions = Parameters<
  NonNullable<
    LexicalExportVisitor<LexicalNode, Mdast.Nodes>["visitLexicalNode"]
  >
>[0]["actions"];

function paragraphAlignment(
  align: Mdast.AlignType,
): "left" | "center" | "right" | undefined {
  if (align === "left" || align === "center" || align === "right") return align;
  return undefined;
}

/** Builds a native Lexical table: one editor tree for the whole table. */
export function $createElementTable(
  mdastTable: Mdast.Table,
  importChildren: ImportChildren,
): TableNode {
  const table = $createTableNode();

  mdastTable.children.forEach((mdastRow, rowIndex) => {
    const row = $createTableRowNode();
    mdastRow.children.forEach((mdastCell, columnIndex) => {
      const cell = $createTableCellNode(
        rowIndex === 0
          ? TableCellHeaderStates.ROW
          : TableCellHeaderStates.NO_STATUS,
      );
      const paragraph = $createParagraphNode();
      const alignment = paragraphAlignment(
        mdastTable.align?.[columnIndex] ?? null,
      );
      if (alignment) paragraph.setFormat(alignment);
      cell.append(paragraph);
      importChildren(mdastCell, paragraph);
      row.append(cell);
    });
    table.append(row);
  });

  return table;
}

function getCellParagraph(cell: TableCellNode): ParagraphNode | null {
  const firstChild = cell.getFirstChild();
  return $isParagraphNode(firstChild) ? firstChild : null;
}

/** Serializes a native Lexical table back to standard GFM table nodes. */
export function $exportElementTable(
  table: TableNode,
  actions: Pick<ExportActions, "visit" | "visitChildren">,
): Mdast.Table {
  const rows = table.getChildren().filter($isTableRowNode);
  const headerCells = rows[0]?.getChildren().filter($isTableCellNode) ?? [];
  const align = headerCells.map((cell): Mdast.AlignType => {
    const format = getCellParagraph(cell)?.getFormatType();
    return format === "left" || format === "center" || format === "right"
      ? format
      : null;
  });

  return {
    type: "table",
    align,
    children: rows.map((row): Mdast.TableRow => ({
      type: "tableRow",
      children: row
        .getChildren()
        .filter($isTableCellNode)
        .map((cell): Mdast.TableCell => {
          const mdastCell: Mdast.TableCell = {
            type: "tableCell",
            children: [],
          };
          const children = cell.getChildren();
          children.forEach((child, index) => {
            if ($isParagraphNode(child)) {
              if (index > 0 && mdastCell.children.length > 0) {
                mdastCell.children.push({ type: "text", value: " " });
              }
              actions.visitChildren(child, mdastCell);
            } else {
              actions.visit(child, mdastCell);
            }
          });
          return mdastCell;
        }),
    })),
  };
}

export const MdastElementTableVisitor: MdastImportVisitor<Mdast.Table> = {
  testNode: "table",
  visitNode({ mdastNode, lexicalParent, actions }) {
    if (!$isElementNode(lexicalParent)) {
      throw new Error("A Markdown table must be inside an element node.");
    }
    const normalized = normalizeTable(mdastNode);
    if (isLargeTable(normalized)) {
      lexicalParent.append(new LargeTableNode(normalized));
      return;
    }
    lexicalParent.append(
      $createElementTable(normalized, (source, parent) => {
        actions.visitChildren(source, parent);
      }),
    );
  },
};

export const LexicalElementTableVisitor: LexicalExportVisitor<
  TableNode,
  Mdast.Table
> = {
  testLexicalNode: $isTableNode,
  visitLexicalNode({ lexicalNode, mdastParent, actions }) {
    actions.appendToParent(
      mdastParent,
      $exportElementTable(lexicalNode, actions),
    );
  },
};

export const LargeTableExportVisitor: LexicalExportVisitor<
  LargeTableNode,
  Mdast.Table
> = {
  testLexicalNode: (node): node is LargeTableNode =>
    node instanceof LargeTableNode,
  visitLexicalNode({ lexicalNode, mdastParent, actions }) {
    actions.appendToParent(mdastParent, lexicalNode.__table);
  },
};
