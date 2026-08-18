import { describe, expect, it } from "vitest";
import {
  appendMarkdownTableColumn,
  appendMarkdownTableRow,
  createMarkdownTable,
  MAX_TABLE_COLUMNS,
  MAX_TABLE_ROWS,
  parseMarkdownTable,
  serializeMarkdownTable,
  serializeTableCellRange,
  tableCellRangeIndices,
} from "./markdown-table";

describe("parseMarkdownTable", () => {
  it("parses a standard Markdown table", () => {
    expect(
      parseMarkdownTable(
        "| Type | Count |\n|------|-------|\n| PQR | 33 |\n| WPS | 74 |",
      ),
    ).toEqual({
      headers: ["Type", "Count"],
      alignments: [null, null],
      rows: [
        ["PQR", "33"],
        ["WPS", "74"],
      ],
    });
  });

  it("supports alignment markers and escaped pipes", () => {
    expect(
      parseMarkdownTable(
        "Name | Description | Total\n:--- | :---: | ---:\nPQR | A\\|B | 33",
      ),
    ).toEqual({
      headers: ["Name", "Description", "Total"],
      alignments: ["left", "center", "right"],
      rows: [["PQR", "A|B", "33"]],
    });
  });

  it("preserves backslashes that do not escape a pipe", () => {
    expect(
      parseMarkdownTable(
        "| Path | Count |\n| --- | ---: |\n| C:\\notes | 1 |",
      )?.rows,
    ).toEqual([["C:\\notes", "1"]]);
  });

  it("rejects malformed delimiter rows", () => {
    expect(
      parseMarkdownTable("| Type | Count |\n| nope | --- |"),
    ).toBeNull();
  });
});

describe("table growth", () => {
  const base = {
    headers: ["Name", "Total"],
    alignments: [null, "right" as const],
    rows: [["PQR", "33"]],
  };

  it("appends an empty body row", () => {
    expect(appendMarkdownTableRow(base)?.rows).toEqual([
      ["PQR", "33"],
      ["", ""],
    ]);
  });

  it("appends a named column to every row", () => {
    expect(appendMarkdownTableColumn(base)).toEqual({
      headers: ["Name", "Total", "Column 3"],
      alignments: [null, "right", null],
      rows: [["PQR", "33", ""]],
    });
  });

  it("refuses to grow past the table limits", () => {
    expect(
      appendMarkdownTableRow({
        ...base,
        rows: Array.from({ length: MAX_TABLE_ROWS }, () => ["", ""]),
      }),
    ).toBeNull();
    expect(
      appendMarkdownTableColumn({
        headers: Array(MAX_TABLE_COLUMNS).fill("Column"),
        alignments: Array(MAX_TABLE_COLUMNS).fill(null),
        rows: [],
      }),
    ).toBeNull();
  });
});

describe("createMarkdownTable", () => {
  it("creates the requested number of columns and body rows", () => {
    expect(parseMarkdownTable(createMarkdownTable(4, 3))).toEqual({
      headers: ["Column 1", "Column 2", "Column 3", "Column 4"],
      alignments: [null, null, null, null],
      rows: [
        ["", "", "", ""],
        ["", "", "", ""],
        ["", "", "", ""],
      ],
    });
  });

  it("clamps sizes to supported limits", () => {
    const table = parseMarkdownTable(createMarkdownTable(0, 100));
    expect(table?.headers).toHaveLength(1);
    expect(table?.rows).toHaveLength(50);
  });
});

describe("serializeMarkdownTable", () => {
  it("preserves alignments and escapes cell pipes", () => {
    expect(
      serializeMarkdownTable({
        headers: ["Name", "Total"],
        alignments: ["left", "right"],
        rows: [["A | B", "33"]],
      }),
    ).toBe(
      "| Name | Total |\n| :--- | ---: |\n| A \\| B | 33 |",
    );
  });

  it("normalizes line breaks because GFM table cells are single-line", () => {
    expect(
      serializeMarkdownTable({
        headers: ["Name"],
        alignments: [null],
        rows: [["Line one\nLine two"]],
      }),
    ).toContain("| Line one Line two |");
  });
});

describe("table cell ranges", () => {
  it("selects every cell in a rectangular range in either drag direction", () => {
    expect(tableCellRangeIndices(1, 8, 3)).toEqual([1, 2, 4, 5, 7, 8]);
    expect(tableCellRangeIndices(8, 1, 3)).toEqual([1, 2, 4, 5, 7, 8]);
  });

  it("serializes a rectangular range as rows and tab-separated columns", () => {
    expect(
      serializeTableCellRange(
        ["A", "B", "C", "1", "2", "3", "4", "5", "6"],
        1,
        8,
        3,
      ),
    ).toBe("B\tC\n2\t3\n5\t6");
  });

  it("returns an empty range for invalid coordinates", () => {
    expect(tableCellRangeIndices(-1, 2, 3)).toEqual([]);
    expect(serializeTableCellRange(["A"], 0, 0, 0)).toBe("");
  });
});
