import { describe, expect, it } from "vitest";
import { parseSpreadsheet } from "./table-clipboard";
import { tableText } from "./table-data";
describe("spreadsheet paste", () => {
  it("preserves empty trailing cells and pads ragged rows", () => {
    const table = parseSpreadsheet("Name\tValue\t\nA\tB\n")!;
    expect(table.children).toHaveLength(2);
    expect(table.children.map((row) => row.children.length)).toEqual([3, 3]);
    expect(table.children[1].children.map(tableText)).toEqual(["A", "B", ""]);
  });
  it("reads quoted tabs and escaped quotes and flattens multiline cell whitespace", () => {
    const table = parseSpreadsheet(
      'Name\tValue\n"A\tB"\t"say ""hi""\non two lines"',
    )!;
    expect(table.children[1].children.map(tableText)).toEqual([
      "A\tB",
      'say "hi" on two lines',
    ]);
  });
  it("does not interpret plain text as a table", () => {
    expect(parseSpreadsheet("hello\nworld")).toBeNull();
  });
});
