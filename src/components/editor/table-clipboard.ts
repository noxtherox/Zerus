import type * as Mdast from "mdast";
import { normalizeTable } from "./table-data";

/** Spreadsheet TSV, including quoted tabs, escaped quotes and multiline cells. */
export function parseSpreadsheet(text: string): Mdast.Table | null {
  if (!text.includes("\t")) return null;
  const rows: string[][] = [];
  let row: string[] = [],
    cell = "",
    quoted = false;
  const source = text.replace(/\r\n?/g, "\n");
  for (let i = 0; i < source.length; i++) {
    const char = source[i];
    if (char === '"' && (quoted || !cell)) {
      if (quoted && source[i + 1] === '"') {
        cell += '"';
        i++;
      } else quoted = !quoted;
    } else if (!quoted && (char === "\t" || char === "\n")) {
      row.push(cell);
      cell = "";
      if (char === "\n") {
        rows.push(row);
        row = [];
      }
    } else cell += char;
  }
  if (cell || row.length || !source.endsWith("\n")) {
    row.push(cell);
    rows.push(row);
  }
  if (!rows.length) return null;
  return normalizeTable({
    type: "table",
    children: rows.map((values) => ({
      type: "tableRow",
      children: values.map((value) => ({
        type: "tableCell",
        children: value
          ? [{ type: "text", value: value.replace(/\n/g, " ") }]
          : [],
      })),
    })),
  });
}
