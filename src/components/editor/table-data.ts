import type * as Mdast from "mdast";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import { toMarkdown } from "mdast-util-to-markdown";
import { gfmTableToMarkdown } from "mdast-util-gfm-table";

// Conservative cross-device defaults, pending physical iPhone profiling.
export const INLINE_TABLE_CELL_LIMIT = 500;
export const INLINE_TABLE_TEXT_LIMIT = 50_000;
export const TABLE_PAGE_ROWS = 20;
export const TABLE_PAGE_COLUMNS = 8;
const parser = unified().use(remarkParse).use(remarkGfm);
export function tableText(node: Mdast.Nodes): string {
  if ("value" in node) return String(node.value);
  if (node.type === "image") return node.alt ?? "";
  return "children" in node
    ? node.children.map((child) => tableText(child as Mdast.Nodes)).join("")
    : "";
}
export function isLargeTable(table: Mdast.Table): boolean {
  return (
    table.children.reduce((sum, row) => sum + row.children.length, 0) >
      INLINE_TABLE_CELL_LIMIT ||
    tableText(table).length > INLINE_TABLE_TEXT_LIMIT
  );
}
export function cellMarkdown(cell: Mdast.TableCell): string {
  return toMarkdown(
    {
      type: "root",
      children: [{ type: "paragraph", children: cell.children }],
    },
    { extensions: [gfmTableToMarkdown()] },
  ).trimEnd();
}
export function parseCellMarkdown(value: string): Mdast.TableCell {
  const root = parser.parse(value);
  if (
    root.children.length > 1 ||
    (root.children[0] && root.children[0].type !== "paragraph")
  ) {
    throw new Error(
      "Use inline Markdown in a cell: text, bold, code, links, or images.",
    );
  }
  if (/[\r\n]/.test(value))
    throw new Error("Table cells must fit on one line.");
  return {
    type: "tableCell",
    children:
      root.children[0]?.type === "paragraph" ? root.children[0].children : [],
  };
}
export function normalizeTable(table: Mdast.Table): Mdast.Table {
  const width = table.children.reduce(
    (width, row) => Math.max(width, row.children.length),
    1,
  );
  return {
    ...table,
    align: Array.from({ length: width }, (_, i) => table.align?.[i] ?? null),
    children: table.children.map((row) => ({
      ...row,
      children: Array.from(
        { length: width },
        (_, i) => row.children[i] ?? { type: "tableCell", children: [] },
      ),
    })),
  };
}

// Table snapshots are immutable; history can release old cache entries normally.
const markdownCache = new WeakMap<Mdast.Table, string>();
export function tableMarkdown(table: Mdast.Table): string {
  const cached = markdownCache.get(table);
  if (cached !== undefined) return cached;
  const markdown = toMarkdown(table, {
    extensions: [gfmTableToMarkdown({ tablePipeAlign: false })],
  });
  markdownCache.set(table, markdown);
  return markdown;
}
