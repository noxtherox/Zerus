import { describe, expect, it } from "vitest";
import { formatTaskDate } from "./tasks";

describe("relative task dates", () => {
  it.each([
    ["2026-09-09", "Today"],
    ["2026-09-08", "Yesterday"],
    ["2026-09-10", "Tomorrow"],
    ["2026-09-01", "8 days ago"],
    ["2026-10-01", "In 22 days"],
  ])("formats %s relative to the local calendar day", (date, expected) => {
    expect(formatTaskDate(date, "2026-09-09")).toBe(expected);
  });

  it("handles year, leap-day, and daylight-saving boundaries", () => {
    expect(formatTaskDate("2025-12-31", "2026-01-01")).toBe("Yesterday");
    expect(formatTaskDate("2024-02-29", "2024-03-01")).toBe("Yesterday");
    expect(formatTaskDate("2026-03-28", "2026-03-30")).toBe("2 days ago");
    expect(formatTaskDate("2026-10-24", "2026-10-26")).toBe("2 days ago");
  });

  it("preserves malformed dates without crashing or normalizing them", () => {
    for (const date of ["unknown", "2026-02-30", "", "2026-13-01"]) {
      expect(formatTaskDate(date, "2026-09-09")).toBe(date);
    }
  });
});
