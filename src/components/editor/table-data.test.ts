import { describe, expect, it } from "vitest";
import type * as Mdast from "mdast";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import { toMarkdown } from "mdast-util-to-markdown";
import { gfmTableToMarkdown } from "mdast-util-gfm-table";
import {
  createEditor,
  $getRoot,
  $createParagraphNode,
  $createTextNode,
} from "lexical";
import { LargeTableNode } from "./large-table-node";
import {
  isLargeTable,
  normalizeTable,
  parseCellMarkdown,
  cellMarkdown,
  tableMarkdown,
  TABLE_PAGE_ROWS,
  TABLE_PAGE_COLUMNS,
} from "./table-data";

const parser = unified().use(remarkParse).use(remarkGfm);
function fixture(rows: number, columns: number): Mdast.Table {
  return {
    type: "table",
    align: Array.from({ length: columns }, () => null),
    children: Array.from({ length: rows }, (_, r) => ({
      type: "tableRow",
      children: Array.from({ length: columns }, (_, c) =>
        parseCellMarkdown(`cell ${r}:${c}`),
      ),
    })),
  };
}
describe("table safety and Markdown", () => {
  it("does not multiply long cells into padding across every saved row", () => {
    const table = fixture(100, 1);
    table.children[1].children[0] = parseCellMarkdown("x".repeat(50_000));
    const markdown = tableMarkdown(table);
    expect(markdown.length).toBeLessThan(60_000);
    expect(markdown).toContain("cell 99:0");
    expect(
      (parser.parse(markdown).children[0] as Mdast.Table).children,
    ).toHaveLength(100);
  });
  it("bounds the mounted table in both dimensions", () => {
    expect(isLargeTable(fixture(10, 10))).toBe(false);
    expect(isLargeTable(fixture(100, 10))).toBe(true);
    expect(isLargeTable(fixture(1000, 10))).toBe(true);
    expect(isLargeTable(fixture(2, 600))).toBe(true);
    expect((TABLE_PAGE_ROWS + 1) * TABLE_PAGE_COLUMNS).toBeLessThan(200);
    expect(
      isLargeTable({
        ...fixture(2, 1),
        children: [
          {
            type: "tableRow",
            children: [parseCellMarkdown("x".repeat(50_001))],
          },
        ],
      }),
    ).toBe(true);
  });
  it("round trips inline formatting, escaped pipes, code, links, and empty cells", () => {
    for (const value of [
      "**bold** and *italic*",
      "[link](https://example.com/a)",
      "`a|b`",
      "a\\|b",
      "",
      "![alt](photo.png)",
    ]) {
      const cell = parseCellMarkdown(value);
      const table: Mdast.Table = {
        type: "table",
        align: ["center"],
        children: [
          { type: "tableRow", children: [cell] },
          { type: "tableRow", children: [parseCellMarkdown("body")] },
        ],
      };
      const encoded = toMarkdown(table, { extensions: [gfmTableToMarkdown()] });
      const decoded = parser.parse(encoded).children[0] as Mdast.Table;
      expect(cellMarkdown(decoded.children[0].children[0])).toBe(
        cellMarkdown(cell),
      );
      expect(decoded.align).toEqual(["center"]);
    }
  });
  it("rejects block content instead of silently flattening it", () => {
    expect(() => parseCellMarkdown("# heading")).toThrow();
    expect(() => parseCellMarkdown("first\nsecond")).toThrow();
  });
  it("pads ragged tables without dropping cells", () => {
    const table = fixture(2, 2);
    table.children[1].children.pop();
    const result = normalizeTable(table);
    expect(result.children[1].children).toHaveLength(2);
    expect(result.children[1].children[1].children).toEqual([]);
    expect(table.children[1].children).toHaveLength(1);
  });
  it("keeps 10,000 cells in one node and preserves them through surrounding edits and JSON reload", () => {
    const data = fixture(1000, 10);
    const editor = createEditor({ nodes: [LargeTableNode] });
    editor.update(
      () => {
        $getRoot().append(
          new LargeTableNode(data),
          $createParagraphNode().append($createTextNode("After table")),
        );
      },
      { discrete: true },
    );
    editor.update(
      () => {
        $getRoot().append(
          $createParagraphNode().append($createTextNode("More text")),
        );
      },
      { discrete: true },
    );
    const serialized = editor.getEditorState().toJSON();
    const restored = editor.parseEditorState(JSON.stringify(serialized));
    restored.read(() => {
      expect($getRoot().getChildrenSize()).toBe(3);
      const table = $getRoot().getFirstChild() as LargeTableNode;
      expect(table.__table).toEqual(data);
      expect(table.isInline()).toBe(false);
    });
  });
});
