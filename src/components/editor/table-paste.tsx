import { useEffect } from "react";
import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext";
import {
  $getSelection,
  $isRangeSelection,
  $isElementNode,
  $createParagraphNode,
  $createTextNode,
  $insertNodes,
  PASTE_COMMAND,
  COMMAND_PRIORITY_HIGH,
} from "lexical";
import {
  $getTableCellNodeFromLexicalNode,
  $getTableNodeFromLexicalNodeOrThrow,
  $getTableColumnIndexFromTableCellNode,
  $getTableRowIndexFromTableCellNode,
  $isTableRowNode,
  $isTableCellNode,
  $createTableRowNode,
  $createTableCellNode,
} from "@lexical/table";
import { useCellValue } from "@mdxeditor/gurx";
import {
  exportVisitors$,
  jsxComponentDescriptors$,
  jsxIsAvailable$,
} from "@mdxeditor/editor";
import { $createElementTable } from "./element-table-model";
import { LargeTableNode } from "./large-table-node";
import {
  isLargeTable,
  tableText,
  normalizeTable,
  INLINE_TABLE_CELL_LIMIT,
} from "./table-data";
import { parseSpreadsheet } from "./table-clipboard";
import { $exportSingleTable } from "./table-export";

export function TablePasteBehavior() {
  const [editor] = useLexicalComposerContext();
  const visitors = useCellValue(exportVisitors$);
  const jsxComponentDescriptors = useCellValue(jsxComponentDescriptors$);
  const jsxIsAvailable = useCellValue(jsxIsAvailable$);
  useEffect(
    () =>
      editor.registerCommand(
        PASTE_COMMAND,
        (event) => {
          if (!event || !("clipboardData" in event) || !editor.isEditable())
            return false;
          const data = parseSpreadsheet(
            event.clipboardData?.getData("text/plain") ?? "",
          );
          if (!data) return false;
          const selection = $getSelection();
          if (!$isRangeSelection(selection)) return false;
          event.preventDefault();
          const active = $getTableCellNodeFromLexicalNode(
            selection.anchor.getNode(),
          );
          if (!active) {
            $insertNodes([
              isLargeTable(data)
                ? new LargeTableNode(data)
                : $createElementTable(data, (source, target) => {
                    target.append(
                      $createTextNode(
                        source.children
                          .map((child) =>
                            tableText(child as import("mdast").Nodes),
                          )
                          .join(""),
                      ),
                    );
                  }),
            ]);
            return true;
          }
          const table = $getTableNodeFromLexicalNodeOrThrow(active);
          const rowOffset = $getTableRowIndexFromTableCellNode(active);
          const colOffset = $getTableColumnIndexFromTableCellNode(active);
          const width = Math.max(
            table.getColumnCount(),
            colOffset + data.children[0].children.length,
          );
          const height = Math.max(
            table.getChildrenSize(),
            rowOffset + data.children.length,
          );
          if (isLargeTable(data) || width * height > INLINE_TABLE_CELL_LIMIT) {
            const existing = $exportSingleTable(table, {
              visitors,
              jsxComponentDescriptors,
              jsxIsAvailable,
            });
            const merged = normalizeTable({
              ...existing,
              children: Array.from({ length: height }, (_, r) => ({
                type: "tableRow",
                children: Array.from(
                  { length: width },
                  (_, c) =>
                    data.children[r - rowOffset]?.children[c - colOffset] ??
                    existing.children[r]?.children[c] ?? {
                      type: "tableCell",
                      children: [],
                    },
                ),
              })),
            });
            const replacement = new LargeTableNode(merged);
            table.replace(replacement);
            replacement.selectNext();
            return true;
          }
          const headerRow = table.getFirstChild();
          const alignments = $isTableRowNode(headerRow)
            ? headerRow.getChildren().map((cell) => {
                const p = $isTableCellNode(cell) ? cell.getFirstChild() : null;
                return $isElementNode(p) ? p.getFormatType() : "";
              })
            : [];
          while (table.getChildrenSize() < height)
            table.append($createTableRowNode());
          table.getChildren().forEach((row, r) => {
            if (!$isTableRowNode(row)) return;
            while (row.getChildrenSize() < width)
              row.append($createTableCellNode().append($createParagraphNode()));
            row.getChildren().forEach((cell, c) => {
              const pasted =
                data.children[r - rowOffset]?.children[c - colOffset];
              if (!$isTableCellNode(cell) || !pasted) return;
              cell.clear();
              cell.append(
                $createParagraphNode().append(
                  $createTextNode(tableText(pasted)),
                ),
              );
              const paragraph = cell.getFirstChild();
              if ($isElementNode(paragraph))
                paragraph.setFormat(alignments[c] ?? "");
            });
          });
          active.selectStart();
          return true;
        },
        COMMAND_PRIORITY_HIGH,
      ),
    [editor, visitors, jsxComponentDescriptors, jsxIsAvailable],
  );
  return null;
}
