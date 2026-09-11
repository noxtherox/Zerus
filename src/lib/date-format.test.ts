import { describe, expect, it } from "vitest";
import { DATE_FORMATS, formatDate, parseDateInput } from "./date-format";

describe("numeric date formats", () => {
  it.each([
    ["DD/MM/YYYY", "31/12/2026"],
    ["MM/DD/YYYY", "12/31/2026"],
    ["YYYY-MM-DD", "2026-12-31"],
    ["DD.MM.YYYY", "31.12.2026"],
  ] as const)("displays and parses %s", (format, expected) => {
    expect(formatDate("2026-12-31", format)).toBe(expected);
    expect(parseDateInput(expected, format)).toBe("2026-12-31");
  });
  it("rejects impossible and ambiguous input without normalizing dates", () => {
    expect(parseDateInput("29/02/2024", "DD/MM/YYYY")).toBe("2024-02-29");
    for (const input of ["29/02/2026", "31/04/2026", "1/13/2026", "12/31/2026", "1/2/26", "garbage"]) {
      expect(parseDateInput(input, "DD/MM/YYYY")).toBeNull();
    }
    expect(parseDateInput("1/2/2026", "DD/MM/YYYY")).toBe("2026-02-01");
    expect(parseDateInput("", "DD/MM/YYYY")).toBe("");
  });
  it("keeps calendar dates intact across timezones and formats local completion timestamps", () => {
    for (const format of DATE_FORMATS) {
      expect(parseDateInput(formatDate("2026-01-01", format), format)).toBe("2026-01-01");
    }
    const local = new Date(2026, 0, 1, 23, 30).toISOString();
    expect(formatDate(local, "DD/MM/YYYY")).toBe("01/01/2026");
    expect(formatDate("2026-02-30", "DD/MM/YYYY")).toBe("2026-02-30");
    expect(formatDate("unknown", "DD/MM/YYYY")).toBe("unknown");
  });
});
