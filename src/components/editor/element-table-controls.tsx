import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { TablePlugin } from "@lexical/react/LexicalTablePlugin";
import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext";
import { useLexicalEditable } from "@lexical/react/useLexicalEditable";
import {
  $getNodeByKey,
  $getNearestNodeFromDOMNode,
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
  $isTableNode,
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
import { Ellipsis, Table2, X } from "@/lib/icons";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";

import {
  DropdownMenu, DropdownMenuTrigger, DropdownMenuContent,
  DropdownMenuItem, DropdownMenuSeparator, DropdownMenuSub,
  DropdownMenuSubTrigger, DropdownMenuSubContent, DropdownMenuPortal,
  DropdownMenuRadioGroup, DropdownMenuRadioItem,
} from "@/components/ui/dropdown-menu";

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
  const [hoveredCellKey, setHoveredCellKey] = useState<NodeKey | null>(null);
  const controlsKey = hoveredCellKey ?? cellKey;
  const resizing = useRef(false);
  const resizeDrag = useRef<{ x: number; width: number; column: number; tableKey: NodeKey; widths: number[]; changed: boolean } | null>(null);
  const controlsRef = useRef<HTMLDivElement | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [menuContext, setMenuContext] = useState({ row: 0, column: 0, rows: 0, columns: 0, alignment: "left" });
  const openMenu = (open: boolean) => {
    if (open && controlsKey) editor.getEditorState().read(() => {
      const cell = $getNodeByKey(controlsKey);
      if (!$isTableCellNode(cell)) return;
      const table = $getTableNodeFromLexicalNodeOrThrow(cell);
      const paragraph = cell.getFirstChild();
      setMenuContext({
        row: $getTableRowIndexFromTableCellNode(cell),
        column: $getTableColumnIndexFromTableCellNode(cell),
        rows: table.getChildrenSize(), columns: table.getColumnCount(),
        alignment: ($isElementNode(paragraph) && paragraph.getFormatType()) || "left",
      });
    });
    setMenuOpen(open);
  };
  const [cellRect, setCellRect] = useState<{ left: number; top: number; width: number; height: number } | null>(null);
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
  useEffect(() => {
    const trackHover = (event: PointerEvent) => {
      if (event.pointerType !== "mouse" || menuOpen || resizing.current) return;
      const target = event.target;
      if (!(target instanceof Element)) return;
      if (controlsRef.current?.contains(target)) return;
      const cellElement = target.closest("td, th");
      if (!cellElement || !editor.getRootElement()?.contains(cellElement)) {
        setHoveredCellKey(null);
        return;
      }
      editor.read(() => {
        const node = $getNearestNodeFromDOMNode(cellElement);
        const cell = node && $getTableCellNodeFromLexicalNode(node);
        setHoveredCellKey(cell?.getKey() ?? null);
      });
    };
    const clearHover = () => { if (!menuOpen) setHoveredCellKey(null); };
    document.addEventListener("pointermove", trackHover);
    document.documentElement.addEventListener("pointerleave", clearHover);
    window.addEventListener("blur", clearHover);
    return () => {
      document.removeEventListener("pointermove", trackHover);
      document.documentElement.removeEventListener("pointerleave", clearHover);
      window.removeEventListener("blur", clearHover);
    };
  }, [editor, menuOpen]);
  // Keep the controls attached to the hovered or selected cell, including nested scrolling
  // and the mobile keyboard viewport. Hide them when the cell is clipped.
  useLayoutEffect(() => {
    if (!controlsKey) {
      setCellRect(null);
      setMenuOpen(false);
      return;
    }
    const element = editor.getElementByKey(controlsKey);
    if (!element) return;
    let frame = 0;
    const measure = () => {
      editor.getEditorState().read(() => {
        const cell = $getNodeByKey(controlsKey);
        if (!$isTableCellNode(cell)) return;
        const table = $getTableNodeFromLexicalNodeOrThrow(cell);
        const host = editor.getElementByKey(table.getKey());
        const tableElement = host?.tagName === "TABLE" ? host : host?.querySelector("table");
        const widths = table.getColWidths();
        if (tableElement instanceof HTMLElement) {
          tableElement.style.width = widths ? `${widths.reduce((sum, width) => sum + width, 0)}px` : "";
          tableElement.toggleAttribute("data-zerus-resized", !!widths);
        }
      });
      const rect = element.getBoundingClientRect();
      const viewport = window.visualViewport;
      let left = viewport?.offsetLeft ?? 0;
      let top = viewport?.offsetTop ?? 0;
      let right = left + (viewport?.width ?? window.innerWidth);
      let bottom = top + (viewport?.height ?? window.innerHeight);
      for (let parent = element.parentElement; parent; parent = parent.parentElement) {
        const style = getComputedStyle(parent);
        const bounds = parent.getBoundingClientRect();
        if (/(auto|scroll|hidden|clip)/.test(style.overflowX)) {
          left = Math.max(left, bounds.left);
          right = Math.min(right, bounds.right);
        }
        if (/(auto|scroll|hidden|clip)/.test(style.overflowY)) {
          top = Math.max(top, bounds.top);
          bottom = Math.min(bottom, bounds.bottom);
        }
        if (style.position === "fixed") break;
      }
      const visible = element.isConnected && rect.right > left && rect.left < right && rect.top >= top && rect.bottom <= bottom;
      setCellRect(visible ? {
        left: Math.max(rect.left, left + 16), top: rect.top,
        width: Math.min(rect.right, right - 16) - Math.max(rect.left, left + 16), height: rect.height,
      } : null);
    };
    const schedule = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(measure);
    };
    const observer = new ResizeObserver(schedule);
    observer.observe(element);
    if (editor.getRootElement()) observer.observe(editor.getRootElement()!);
    const unregister = editor.registerUpdateListener(schedule);
    window.addEventListener("scroll", schedule, true);
    window.addEventListener("resize", schedule);
    window.visualViewport?.addEventListener("resize", schedule);
    window.visualViewport?.addEventListener("scroll", schedule);
    measure();
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      unregister();
      window.removeEventListener("scroll", schedule, true);
      window.removeEventListener("resize", schedule);
      window.visualViewport?.removeEventListener("resize", schedule);
      window.visualViewport?.removeEventListener("scroll", schedule);
    };
  }, [editor, controlsKey, expanded]);
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
  const getResizeTarget = () => {
    if (!controlsKey || !editable) return null;
    return editor.getEditorState().read(() => {
      const cell = $getNodeByKey(controlsKey);
      if (!$isTableCellNode(cell)) return null;
      const table = $getTableNodeFromLexicalNodeOrThrow(cell);
      const element = editor.getElementByKey(cell.getKey())?.closest("table");
      const header = element?.rows[0];
      if (!header) return null;
      return {
        tableKey: table.getKey(),
        column: $getTableColumnIndexFromTableCellNode(cell),
        widths: Array.from(header.cells, (cell) => cell.getBoundingClientRect().width),
      };
    });
  };
  const resizeColumn = (target: { tableKey: NodeKey; column: number; widths: number[] }, width: number, merge = false) => {
    editor.update(() => {
      const table = $getNodeByKey(target.tableKey);
      if (!$isTableNode(table)) return;
      const widths = [...target.widths];
      widths[target.column] = Math.round(Math.min(720, Math.max(80, width)));
      table.setColWidths(widths);
    }, { tag: merge ? "history-merge" : "history-push" });
  };
  const act = (action: string) => {
    setMenuOpen(false);
    if (!controlsKey || !editable) return;
    editor.update(
      () => {
        const cell = $getNodeByKey(controlsKey);
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
        if (action === "move-row-up" || action === "move-row-down") {
          const row = cell.getParent();
          const sibling = action === "move-row-up" ? row?.getPreviousSibling() : row?.getNextSibling();
          if ($isTableRowNode(row) && $isTableRowNode(sibling)) {
            if (action === "move-row-up") sibling.insertBefore(row);
            else sibling.insertAfter(row);
          }
        }
        if (action === "move-column-left" || action === "move-column-right") {
          const index = $getTableColumnIndexFromTableCellNode(cell);
          const nextIndex = index + (action === "move-column-left" ? -1 : 1);
          if (nextIndex >= 0 && nextIndex < table.getColumnCount()) {
            table.getChildren().forEach((row) => {
              if (!$isTableRowNode(row)) return;
              const moving = row.getChildAtIndex(index);
              const sibling = row.getChildAtIndex(nextIndex);
              if (!$isTableCellNode(moving) || !$isTableCellNode(sibling)) return;
              if (nextIndex < index) sibling.insertBefore(moving);
              else sibling.insertAfter(moving);
            });
            const widths = table.getColWidths();
            if (widths) {
              const reordered = [...widths];
              [reordered[index], reordered[nextIndex]] = [reordered[nextIndex], reordered[index]];
              table.setColWidths(reordered);
            }
          }
        }
        if (
          table.isAttached() &&
          (action === "row-before" ||
            action === "row-after" ||
            action === "delete-row" ||
            action === "move-row-up" ||
            action === "move-row-down")
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
      const cell = controlsKey && $getNodeByKey(controlsKey);
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
    editor.focus();
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
      {controlsKey && cellRect && createPortal(
        <div
          ref={controlsRef}
          className={`zerus-table-cell-tools${hoveredCellKey || menuOpen ? " is-visible" : ""}`}
          style={cellRect}
          role="group"
          aria-label="Table cell controls"
          onMouseDown={(event) => event.preventDefault()}
        >
          {editable && <>
            <div
              className="zerus-table-column-resize"
              role="separator"
              aria-orientation="vertical"
              aria-label="Resize column"
              title="Drag to resize column"
              tabIndex={0}
              onPointerDown={(event) => {
                if (event.button !== 0) return;
                const target = getResizeTarget();
                if (!target) return;
                event.preventDefault();
                event.currentTarget.setPointerCapture(event.pointerId);
                resizing.current = true;
                resizeDrag.current = { ...target, x: event.clientX, width: target.widths[target.column], changed: false };
              }}
              onPointerMove={(event) => {
                const drag = resizeDrag.current;
                if (!drag) return;
                resizeColumn(drag, drag.width + event.clientX - drag.x, drag.changed);
                drag.changed = true;
              }}
              onPointerUp={(event) => {
                event.currentTarget.releasePointerCapture(event.pointerId);
                resizing.current = false;
                resizeDrag.current = null;
              }}
              onLostPointerCapture={() => { resizing.current = false; resizeDrag.current = null; }}
              onKeyDown={(event) => {
                if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
                const target = getResizeTarget();
                if (!target) return;
                event.preventDefault();
                resizeColumn(target, target.widths[target.column] + (event.key === "ArrowRight" ? 16 : -16));
              }}
            />
          </>}
          <DropdownMenu open={menuOpen} onOpenChange={openMenu} modal={false}>
            <DropdownMenuTrigger asChild>
              <button type="button" className="zerus-table-more" title="Table actions" aria-label="Table actions"><Ellipsis size={17} /></button>
            </DropdownMenuTrigger>
            <DropdownMenuContent className="zerus-table-context-menu" side="bottom" align="end"
              onCloseAutoFocus={(event) => event.preventDefault()}>
              {editable && <>
                <DropdownMenuSub>
                  <DropdownMenuSubTrigger>Align Column</DropdownMenuSubTrigger>
                  <DropdownMenuPortal>
                    <DropdownMenuSubContent className="zerus-table-context-menu">
                      <DropdownMenuRadioGroup value={menuContext.alignment} onValueChange={act}>
                        <DropdownMenuRadioItem value="left">Left</DropdownMenuRadioItem>
                        <DropdownMenuRadioItem value="center">Center</DropdownMenuRadioItem>
                        <DropdownMenuRadioItem value="right">Right</DropdownMenuRadioItem>
                      </DropdownMenuRadioGroup>
                    </DropdownMenuSubContent>
                  </DropdownMenuPortal>
                </DropdownMenuSub>
                <DropdownMenuSeparator />
                {[
                  ["row-after", "Add Row"], ["row-before", "Add Row Above"],
                  ["column-after", "Add Column"], ["column-before", "Add Column Before"],
                ].map(([action, label]) => <DropdownMenuItem key={action} onSelect={() => act(action)}>{label}</DropdownMenuItem>)}
                <DropdownMenuSeparator />
                <DropdownMenuItem disabled={menuContext.row === 0} onSelect={() => act("move-row-up")}>Move Row Up</DropdownMenuItem>
                <DropdownMenuItem disabled={menuContext.row >= menuContext.rows - 1} onSelect={() => act("move-row-down")}>Move Row Down</DropdownMenuItem>
                <DropdownMenuItem disabled={menuContext.column === 0} onSelect={() => act("move-column-left")}>Move Column Left</DropdownMenuItem>
                <DropdownMenuItem disabled={menuContext.column >= menuContext.columns - 1} onSelect={() => act("move-column-right")}>Move Column Right</DropdownMenuItem>
                <DropdownMenuSeparator />
                <DropdownMenuItem onSelect={() => act("delete-row")}>Delete Row</DropdownMenuItem>
                <DropdownMenuItem onSelect={() => act("delete-column")}>Delete Column</DropdownMenuItem>
                <DropdownMenuSeparator />
              </>}
              <DropdownMenuSub>
                <DropdownMenuSubTrigger>Table</DropdownMenuSubTrigger>
                <DropdownMenuPortal>
                  <DropdownMenuSubContent className="zerus-table-context-menu">
                    <DropdownMenuItem onSelect={() => { setMenuOpen(false); expand(); }}>{expanded ? "Close Expanded Table" : "Expand Table"}</DropdownMenuItem>
                    {editable && <DropdownMenuItem onSelect={() => act("delete-table")}>Delete Table</DropdownMenuItem>}
                  </DropdownMenuSubContent>
                </DropdownMenuPortal>
              </DropdownMenuSub>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>, document.body,
      )}
      {expanded && createPortal(
        <button type="button" className="zerus-table-close-expanded" onClick={expand} aria-label="Close expanded table" title="Close expanded table"><X size={18} /></button>, document.body,
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
