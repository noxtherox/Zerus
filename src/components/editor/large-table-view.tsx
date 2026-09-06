import { TableCellPreview } from "./table-cell-preview";
import { toast } from "sonner";
import { useEffect, useRef, useState } from "react";
import {
  $getNodeByKey,
  UNDO_COMMAND,
  REDO_COMMAND,
  type NodeKey,
} from "lexical";
import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext";
import { useLexicalEditable } from "@lexical/react/useLexicalEditable";
import type * as Mdast from "mdast";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  cellMarkdown,
  parseCellMarkdown,
  tableText,
  tableMarkdown,
  TABLE_PAGE_ROWS,
  TABLE_PAGE_COLUMNS,
} from "./table-data";
import { LargeTableNode } from "./large-table-node";

export function LargeTableView({
  table,
  nodeKey,
}: {
  table: Mdast.Table;
  nodeKey: NodeKey;
}) {
  const [editor] = useLexicalComposerContext();
  const editable = useLexicalEditable();
  const [open, setOpen] = useState(false);
  const dialogRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const viewport = window.visualViewport;
    if (!open || !viewport) return;
    let frame = 0;
    const position = () => {
      dialogRef.current?.style.setProperty('--zerus-table-viewport-height', `${viewport.height}px`);
      dialogRef.current?.style.setProperty('--zerus-table-viewport-top', `${viewport.offsetTop}px`);
    };
    const resize = () => {
      position();
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const dialog = dialogRef.current;
        if (dialog?.querySelector('.zerus-table-cell-editor') && window.matchMedia('(max-width: 640px)').matches) dialog.scrollTop = 0;
      });
    };
    position();
    viewport.addEventListener('resize', resize);
    viewport.addEventListener('scroll', position);
    return () => {
      cancelAnimationFrame(frame);
      viewport.removeEventListener('resize', resize);
      viewport.removeEventListener('scroll', position);
    };
  }, [open]);
  const [page, setPage] = useState(0);
  const [columnPage, setColumnPage] = useState(0);
  const [active, setActive] = useState<{
    row: number;
    col: number;
    draft: string;
  } | null>(null);
  const [error, setError] = useState("");
  const copyMarkdown = async () => {
    try {
      await navigator.clipboard.writeText(tableMarkdown(table));
      toast.success("Table Markdown copied");
    } catch {
      toast.error("Could not copy the table.");
    }
  };
  const rows = table.children.length;
  const columns = table.children[0]?.children.length ?? 0;
  const rowStart = Math.min(page * TABLE_PAGE_ROWS + 1, Math.max(1, rows - 1));
  const colStart = Math.min(
    columnPage * TABLE_PAGE_COLUMNS,
    Math.max(0, columns - 1),
  );
  const change = (next: Mdast.Table) =>
    editor.update(
      () => {
        const node = $getNodeByKey(nodeKey);
        if (node instanceof LargeTableNode) node.setTable(next);
      },
      { tag: "history-push" },
    );
  const structure = (action: string) => {
    if (!active) return;
    const { row: r, col: c } = active;
    let next = table;
    const empty = (): Mdast.TableCell => ({ type: "tableCell", children: [] });
    if (action === "row-before" || action === "row-after") {
      const children = [...table.children];
      children.splice(r + (action === "row-after" ? 1 : 0), 0, {
        type: "tableRow",
        children: Array.from({ length: columns }, empty),
      });
      next = { ...table, children };
    }
    if (action === "delete-row" && rows > 1)
      next = { ...table, children: table.children.filter((_, i) => i !== r) };
    if (action === "column-before" || action === "column-after") {
      const index = c + (action === "column-after" ? 1 : 0);
      const align = [...(table.align ?? Array(columns).fill(null))];
      align.splice(index, 0, null);
      next = {
        ...table,
        align,
        children: table.children.map((row) => {
          const children = [...row.children];
          children.splice(index, 0, empty());
          return { ...row, children };
        }),
      };
    }
    if (action === "delete-column" && columns > 1)
      next = {
        ...table,
        align: table.align?.filter((_, i) => i !== c),
        children: table.children.map((row) => ({
          ...row,
          children: row.children.filter((_, i) => i !== c),
        })),
      };
    if (action === "left" || action === "center" || action === "right")
      next = {
        ...table,
        align: Array.from({ length: columns }, (_, i) =>
          i === c ? action : (table.align?.[i] ?? null),
        ),
      };
    change(next);
    setActive(null);
    setError("");
  };
  const save = () => {
    if (!active) return;
    try {
      const cell = parseCellMarkdown(active.draft);
      change({
        ...table,
        children: table.children.map((row, r) =>
          r === active.row
            ? {
                ...row,
                children: row.children.map((old, c) =>
                  c === active.col ? cell : old,
                ),
              }
            : row,
        ),
      });
      setActive(null);
      setError("");
    } catch (cause) {
      setError((cause as Error).message);
    }
  };
  const renderRow = (row: Mdast.TableRow, r: number) => (
    <tr key={r}>
      {row.children
        .slice(colStart, colStart + TABLE_PAGE_COLUMNS)
        .map((cell, i) => {
          const col = colStart + i;
          const Tag = r === 0 ? "th" : "td";
          return (
            <Tag
              key={col}
              scope={r === 0 ? "col" : undefined}
              style={{ textAlign: table.align?.[col] ?? undefined }}
            >
              <button
                type="button"
                disabled={!!active}
                aria-label={`${editable ? "Edit" : "View"} row ${r + 1}, column ${col + 1}`}
                onClick={() => {
                  setError("");
                  setActive({ row: r, col, draft: cellMarkdown(cell) });
                }}
              >
                <TableCellPreview cell={cell} />
              </button>
            </Tag>
          );
        })}
    </tr>
  );
  return (
    <div contentEditable={false}>
      <Dialog
        onOpenChange={(value) => {
          setOpen(value);
          setActive(null);
          setError("");
        }}
      >
        <div className="zerus-table-summary">
          <div>
            <strong>Table</strong>
            <span>
              {rows} rows · {columns} columns
            </span>
            <p>
              {table.children[0]?.children
                .slice(0, 4)
                .map((cell) => tableText(cell).slice(0, 60))
                .join(" · ")}
            </p>
          </div>
          <DialogTrigger asChild>
            <button type="button">Open table</button>
          </DialogTrigger>
        </div>
        <DialogContent
          ref={dialogRef}
          className={`zerus-table-dialog${active ? " is-editing" : ""}`}
          onInteractOutside={(event) => {
            if (active) event.preventDefault();
          }}
          onEscapeKeyDown={(event) => {
            if (active) {
              event.preventDefault();
              setActive(null);
            }
          }}
        >
          <DialogTitle>Table</DialogTitle>
          <DialogDescription>
            {rows} rows · {columns} columns. Select a cell to{" "}
            {editable ? "edit" : "view"} its inline Markdown.
          </DialogDescription>
          <div className="zerus-table-pagination">
            <button onClick={() => void copyMarkdown()}>Copy Markdown</button>
            <button
              disabled={page === 0 || !!active}
              onClick={() => setPage(page - 1)}
            >
              Previous rows
            </button>
            <span aria-live="polite">
              {rows > 1
                ? `Rows ${rowStart + 1}–${Math.min(rowStart + TABLE_PAGE_ROWS, rows)}`
                : "Header only"}
            </span>
            <button
              disabled={rowStart + TABLE_PAGE_ROWS >= rows || !!active}
              onClick={() => setPage(page + 1)}
            >
              Next rows
            </button>
            <button
              disabled={columnPage === 0 || !!active}
              onClick={() => setColumnPage(columnPage - 1)}
            >
              Previous columns
            </button>
            <span>
              Columns {colStart + 1}–
              {Math.min(colStart + TABLE_PAGE_COLUMNS, columns)}
            </span>
            <button
              disabled={colStart + TABLE_PAGE_COLUMNS >= columns || !!active}
              onClick={() => setColumnPage(columnPage + 1)}
            >
              Next columns
            </button>
          </div>
          <div className="zerus-table-grid">
            <table>
              <thead>
                {table.children[0] && renderRow(table.children[0], 0)}
              </thead>
              <tbody>
                {table.children
                  .slice(rowStart, rowStart + TABLE_PAGE_ROWS)
                  .map((row, i) => renderRow(row, rowStart + i))}
              </tbody>
            </table>
          </div>
          {active && (
            <div className="zerus-table-cell-editor">
              <label htmlFor={`${nodeKey}-cell`}>
                Row {active.row + 1}, column {active.col + 1} · Markdown
              </label>
              <input
                id={`${nodeKey}-cell`}
                autoFocus
                value={active.draft}
                readOnly={!editable}
                onChange={(event) =>
                  setActive({ ...active, draft: event.target.value })
                }
                onKeyDown={(event) => {
                  if (editable && event.key === "Enter") {
                    event.preventDefault();
                    save();
                  }
                }}
              />
              <div>
                {editable && <button onClick={save}>Save cell</button>}
                <button onClick={() => setActive(null)}>
                  {editable ? "Cancel" : "Done"}
                </button>
              </div>
              {editable && (
                <label>
                  Row and column actions
                  <select
                    aria-label="Row and column actions"
                    value=""
                    onChange={(event) => structure(event.target.value)}
                    disabled={
                      active.draft !==
                      cellMarkdown(
                        table.children[active.row].children[active.col],
                      )
                    }
                  >
                    <option value="">Choose action…</option>
                    <option value="row-before">Insert row above</option>
                    <option value="row-after">Insert row below</option>
                    <option value="column-before">Insert column left</option>
                    <option value="column-after">Insert column right</option>
                    <option value="left">Align column left</option>
                    <option value="center">Align column center</option>
                    <option value="right">Align column right</option>
                    <option value="delete-row" disabled={rows <= 1}>
                      Delete row
                    </option>
                    <option value="delete-column" disabled={columns <= 1}>
                      Delete column
                    </option>
                  </select>
                </label>
              )}
              {error && <p role="alert">{error}</p>}
            </div>
          )}
          {editable && !active && (
            <div className="zerus-table-pagination">
              <button
                onClick={() => editor.dispatchCommand(UNDO_COMMAND, undefined)}
              >
                Undo
              </button>
              <button
                onClick={() => editor.dispatchCommand(REDO_COMMAND, undefined)}
              >
                Redo
              </button>
              <button
                onClick={() =>
                  editor.update(
                    () => {
                      const node = $getNodeByKey(nodeKey);
                      if (node) {
                        node.selectNext();
                        node.remove();
                      }
                    },
                    { tag: "history-push" },
                  )
                }
              >
                Delete table
              </button>
              <button
                onClick={() =>
                  change({
                    ...table,
                    children: [
                      ...table.children,
                      {
                        type: "tableRow",
                        children: Array.from({ length: columns }, () => ({
                          type: "tableCell",
                          children: [],
                        })),
                      },
                    ],
                  })
                }
              >
                Add row
              </button>
              <button
                onClick={() =>
                  change({
                    ...table,
                    align: [...(table.align ?? []), null],
                    children: table.children.map((row) => ({
                      ...row,
                      children: [
                        ...row.children,
                        { type: "tableCell", children: [] },
                      ],
                    })),
                  })
                }
              >
                Add column
              </button>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
