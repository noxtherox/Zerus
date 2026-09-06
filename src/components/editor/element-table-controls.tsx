import { useEffect, useRef, useState } from "react";
import { TablePlugin } from "@lexical/react/LexicalTablePlugin";
import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext";
import { useLexicalEditable } from "@lexical/react/useLexicalEditable";
import {
  $getNodeByKey,
  $getSelection,
  $isRangeSelection,
  $isElementNode,
  $createParagraphNode,
  KEY_ESCAPE_COMMAND,
  KEY_ENTER_COMMAND,
  COMMAND_PRIORITY_HIGH,
  COMMAND_PRIORITY_LOW,
  type NodeKey,
} from "lexical";
import {
  INSERT_TABLE_COMMAND,
  $getTableCellNodeFromLexicalNode,
  $getTableNodeFromLexicalNodeOrThrow,
  $getTableColumnIndexFromTableCellNode,
  $getTableRowIndexFromTableCellNode,
  $isTableCellNode,
  $isTableRowNode,
  $isTableSelection,
  $insertTableRowAtSelection,
  $insertTableColumnAtSelection,
  $deleteTableRowAtSelection,
  $deleteTableColumnAtSelection,
  TableCellHeaderStates,
  TableNode,
} from "@lexical/table";
import { useCellValue } from "@mdxeditor/gurx";
import {
  rootEditor$,
  exportVisitors$,
  jsxComponentDescriptors$,
  jsxIsAvailable$,
} from "@mdxeditor/editor";
import { Table2 } from "@/lib/icons";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";

import { TablePasteBehavior } from "./table-paste";
import { LargeTableNode } from "./large-table-node";
import { INLINE_TABLE_CELL_LIMIT, INLINE_TABLE_TEXT_LIMIT } from "./table-data";
import { $exportSingleTable } from "./table-export";

export function ElementTableBehavior() {
  const [editor] = useLexicalComposerContext();
  const editable = useLexicalEditable();
  const visitors = useCellValue(exportVisitors$);
  const jsxComponentDescriptors = useCellValue(jsxComponentDescriptors$);
  const jsxIsAvailable = useCellValue(jsxIsAvailable$);
  const [cellKey, setCellKey] = useState<NodeKey | null>(null);
  const [expanded, setExpanded] = useState(false);
  const expandedElement = useRef<HTMLElement | null>(null);
  const currentCell = useRef<HTMLElement | null>(null);
  const scrollSnapshot = useRef<
    Array<{ element: HTMLElement; top: number; left: number }>
  >([]);
  useEffect(
    () =>
      editor.registerUpdateListener(({ editorState }) => {
        editorState.read(() => {
          const selection = $getSelection();
          const node =
            $isRangeSelection(selection) || $isTableSelection(selection)
              ? selection.anchor.getNode()
              : null;
          const cell = node ? $getTableCellNodeFromLexicalNode(node) : null;
          setCellKey(cell?.getKey() ?? null);
          currentCell.current = cell
            ? editor.getElementByKey(cell.getKey())
            : null;
        });
      }),
    [editor],
  );
  useEffect(() => {
    if (!cellKey) return;
    const element = editor.getElementByKey(cellKey);
    element?.setAttribute("data-zerus-active-cell", "true");
    return () => element?.removeAttribute("data-zerus-active-cell");
  }, [editor, cellKey]);
  useEffect(
    () =>
      editor.registerNodeTransform(TableNode, (table) => {
        const cells = table
          .getChildren()
          .reduce(
            (count, row) =>
              count + ($isTableRowNode(row) ? row.getChildrenSize() : 0),
            0,
          );
        if (
          cells > INLINE_TABLE_CELL_LIMIT ||
          table.getTextContentSize() > INLINE_TABLE_TEXT_LIMIT
        ) {
          const data = $exportSingleTable(table, {
            visitors,
            jsxComponentDescriptors,
            jsxIsAvailable,
          });
          const replacement = new LargeTableNode(data);
          table.replace(replacement);
          replacement.selectNext();
          setExpanded(false);
          return;
        }
        // Markdown always has a header row, including after deleting the old header.
        table.getChildren().forEach((row, r) => {
          if (!$isTableRowNode(row)) return;
          row.getChildren().forEach((cell) => {
            if (!$isTableCellNode(cell)) return;
            const state =
              r === 0
                ? TableCellHeaderStates.ROW
                : TableCellHeaderStates.NO_STATUS;
            if (cell.getHeaderStyles() !== state) cell.setHeaderStyles(state);
          });
        });
      }),
    [editor, visitors, jsxComponentDescriptors, jsxIsAvailable],
  );
  useEffect(() => {
    const viewport = window.visualViewport;
    const reveal = () =>
      currentCell.current?.scrollIntoView({
        block: "nearest",
        inline: "nearest",
      });
    viewport?.addEventListener("resize", reveal);
    return () => viewport?.removeEventListener("resize", reveal);
  }, []);
  useEffect(() => {
    if (!expanded) return;
    const release = () => {
      expandedElement.current?.classList.remove("zerus-table-expanded");
      expandedElement.current = null;
      for (const { element, top, left } of scrollSnapshot.current) {
        element.scrollTop = top;
        element.scrollLeft = left;
      }
      scrollSnapshot.current = [];
    };
    return release;
  }, [expanded]);
  useEffect(
    () =>
      editor.registerCommand(
        KEY_ESCAPE_COMMAND,
        () => {
          if (expanded) {
            setExpanded(false);
            return true;
          }
          if (!cellKey) return false;
          const cell = $getNodeByKey(cellKey);
          if (!$isTableCellNode(cell)) return false;
          const table = $getTableNodeFromLexicalNodeOrThrow(cell);
          let next = table.getNextSibling();
          if (!$isElementNode(next)) {
            next = $createParagraphNode();
            table.insertAfter(next);
          }
          if ($isElementNode(next)) next.selectStart();
          return true;
        },
        COMMAND_PRIORITY_LOW,
      ),
    [editor, expanded, cellKey],
  );
  useEffect(
    () =>
      editor.registerCommand(
        KEY_ENTER_COMMAND,
        (event) => {
          const selection = $getSelection();
          if (!$isRangeSelection(selection) || editor.isComposing())
            return false;
          const cell = $getTableCellNodeFromLexicalNode(
            selection.anchor.getNode(),
          );
          if (!cell) return false;
          event?.preventDefault();
          const table = $getTableNodeFromLexicalNodeOrThrow(cell);
          const col = $getTableColumnIndexFromTableCellNode(cell);
          const rowIndex = $getTableRowIndexFromTableCellNode(cell);
          const row =
            table.getChildAtIndex(rowIndex + 1) ??
            $insertTableRowAtSelection(true);
          if ($isTableRowNode(row)) {
            const next = row.getChildAtIndex(col);
            if ($isTableCellNode(next)) next.selectStart();
          }
          return true;
        },
        COMMAND_PRIORITY_HIGH,
      ),
    [editor],
  );
  const act = (action: string) => {
    if (!cellKey || !editable) return;
    editor.update(
      () => {
        const cell = $getNodeByKey(cellKey);
        if (!$isTableCellNode(cell)) return;
        const table = $getTableNodeFromLexicalNodeOrThrow(cell);
        const header = table.getFirstChild();
        const alignments = $isTableRowNode(header)
          ? header.getChildren().map((cell) => {
              const paragraph = $isTableCellNode(cell)
                ? cell.getFirstChild()
                : null;
              return $isElementNode(paragraph) ? paragraph.getFormatType() : "";
            })
          : [];
        cell.selectStart();
        if (action === "row-before") $insertTableRowAtSelection(false);
        if (action === "row-after") $insertTableRowAtSelection(true);
        if (action === "column-before") $insertTableColumnAtSelection(false);
        if (action === "column-after") $insertTableColumnAtSelection(true);
        if (action === "delete-row") $deleteTableRowAtSelection();
        if (action === "delete-column") $deleteTableColumnAtSelection();
        if (
          table.isAttached() &&
          (action === "row-before" ||
            action === "row-after" ||
            action === "delete-row")
        ) {
          table.getChildren().forEach((row) => {
            if (!$isTableRowNode(row)) return;
            row.getChildren().forEach((cell, c) => {
              if ($isTableCellNode(cell))
                cell.getChildren().forEach((p) => {
                  if ($isElementNode(p)) p.setFormat(alignments[c] ?? "");
                });
            });
          });
        }
        if (action === "delete-table") {
          table.selectNext();
          table.remove();
          setExpanded(false);
        }
        if (action === "left" || action === "center" || action === "right") {
          const index = $getTableColumnIndexFromTableCellNode(cell);
          table.getChildren().forEach((row) => {
            if (!$isTableRowNode(row)) return;
            const target = row.getChildAtIndex(index);
            if ($isTableCellNode(target))
              target.getChildren().forEach((p) => {
                if ($isElementNode(p)) p.setFormat(action);
              });
          });
        }
      },
      { tag: "history-push" },
    );
    editor.focus();
  };
  const expand = () => {
    if (expanded) {
      setExpanded(false);
      editor.focus();
      return;
    }
    editor.getEditorState().read(() => {
      const cell = cellKey && $getNodeByKey(cellKey);
      if (!$isTableCellNode(cell)) return;
      const table = $getTableNodeFromLexicalNodeOrThrow(cell);
      const el = editor.getElementByKey(table.getKey());
      const wrapper = el?.tagName === "TABLE" ? el.parentElement : el;
      if (wrapper) {
        scrollSnapshot.current = [];
        for (
          let element: HTMLElement | null = wrapper;
          element;
          element = element.parentElement
        ) {
          scrollSnapshot.current.push({
            element,
            top: element.scrollTop,
            left: element.scrollLeft,
          });
        }
        wrapper.classList.add("zerus-table-expanded");
        expandedElement.current = wrapper;
        setExpanded(true);
      }
    });
  };
  return (
    <>
      <TablePasteBehavior />
      <TablePlugin
        hasCellMerge={false}
        hasCellBackgroundColor={false}
        hasHorizontalScroll
        hasTabHandler
      />
      {(cellKey || expanded) && (
        <div
          className={`zerus-table-tools${expanded ? " is-expanded" : ""}`}
          role="toolbar"
          aria-label="Table controls"
          onMouseDown={(event) => event.preventDefault()}
        >
          <Popover>
            <PopoverTrigger asChild>
              <button type="button">Table actions</button>
            </PopoverTrigger>
            <PopoverContent
              className="zerus-table-actions"
              onOpenAutoFocus={(event) => event.preventDefault()}
            >
              {editable && (
                <>
                  {[
                    ["row-before", "Insert row above"],
                    ["row-after", "Insert row below"],
                    ["column-before", "Insert column left"],
                    ["column-after", "Insert column right"],
                    ["left", "Align column left"],
                    ["center", "Align column center"],
                    ["right", "Align column right"],
                    ["delete-row", "Delete row"],
                    ["delete-column", "Delete column"],
                    ["delete-table", "Delete table"],
                  ].map(([action, label]) => (
                    <button
                      type="button"
                      key={action}
                      onClick={() => act(action)}
                    >
                      {label}
                    </button>
                  ))}
                </>
              )}
              <p>
                Tab: next cell · Shift+Tab: previous · Enter: next row
                <br />
                Escape: leave table
              </p>
            </PopoverContent>
          </Popover>
          <button type="button" onClick={expand}>
            {expanded ? "Close expanded table" : "Expand table"}
          </button>
        </div>
      )}
    </>
  );
}

export function InsertElementTable() {
  const editor = useCellValue(rootEditor$);
  const [open, setOpen] = useState(false);
  const [rows, setRows] = useState(3);
  const [columns, setColumns] = useState(3);
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <button
          type="button"
          className="zerus-mdx-toolbar-action"
          title="Insert table"
          aria-label="Insert table"
          disabled={!editor}
        >
          <Table2 size={16} />
        </button>
      </PopoverTrigger>
      <PopoverContent className="zerus-table-insert">
        <strong>Insert table</strong>
        <label>
          Rows, including header
          <input
            type="number"
            min={2}
            max={20}
            value={rows}
            onChange={(event) => setRows(Number(event.target.value))}
          />
        </label>
        <label>
          Columns
          <input
            type="number"
            min={1}
            max={12}
            value={columns}
            onChange={(event) => setColumns(Number(event.target.value))}
          />
        </label>
        <button
          type="button"
          disabled={
            !Number.isInteger(rows) ||
            rows < 2 ||
            rows > 20 ||
            !Number.isInteger(columns) ||
            columns < 1 ||
            columns > 12
          }
          onClick={() => {
            editor?.dispatchCommand(INSERT_TABLE_COMMAND, {
              columns: String(columns),
              rows: String(rows),
              includeHeaders: { rows: true, columns: false },
            });
            setOpen(false);
            editor?.focus();
          }}
        >
          Insert {rows} × {columns} table
        </button>
      </PopoverContent>
    </Popover>
  );
}
