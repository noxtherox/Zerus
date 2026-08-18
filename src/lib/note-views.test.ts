import { describe, expect, it } from "vitest";
import {
  boardColumnOrderKey,
  defaultTypeViewConfig,
  normalizeTypeViewConfigs,
  reconcileBoardColumnOrder,
  typeViewConfigFor,
} from "./note-views";

describe("note view configuration", () => {
  it("defaults every unknown type to the existing List view", () => {
    expect(typeViewConfigFor({}, "Projects")).toEqual(defaultTypeViewConfig());
  });

  it("keeps supported portable settings and strips scope-only filters", () => {
    expect(
      normalizeTypeViewConfigs({
        " Projects / Active ": {
          mode: "board",
          groupBy: " Status ",
          boardColumnOrder: {
            " Status ": ["Done", "Todo", "Done", 42],
            Empty: "not-an-array",
          },
          dateProperty: " Due ",
          filters: {
            date: "last-7-days",
            showArchived: true,
            typeKeys: ["Other"],
            fileExtensions: ["pdf"],
            properties: [{ name: "Priority", valueKey: "string:High" }],
          },
        },
      }),
    ).toEqual({
      "Projects/Active": {
        mode: "board",
        groupBy: "Status",
        boardColumnOrder: { status: ["Done", "Todo"] },
        dateProperty: "Due",
        filters: {
          date: "last-7-days",
          showArchived: true,
          typeKeys: [],
          fileExtensions: [],
          properties: [{ name: "Priority", valueKey: "string:High" }],
        },
      },
    });
  });

  it("falls back safely for malformed view files", () => {
    expect(
      normalizeTypeViewConfigs({ Projects: { mode: "timeline", filters: null } }),
    ).toEqual({ Projects: defaultTypeViewConfig() });
  });

  it("reconciles saved Kanban order with current property values", () => {
    expect(
      reconcileBoardColumnOrder(
        ["__no_value__", "Todo", "Doing", "Done"],
        ["Done", "Missing", "Todo", "Done"],
      ),
    ).toEqual(["Done", "Todo", "__no_value__", "Doing"]);
    expect(boardColumnOrderKey(" Status ")).toBe("status");
  });
});
