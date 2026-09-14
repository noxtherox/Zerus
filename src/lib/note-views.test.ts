import { describe, expect, it } from "vitest";
import {
  boardColumnOrderKey,
  defaultTypeViewConfig,
  normalizeSavedTypeViews,
  normalizeTypeViewConfigs,
  propertyGroupLabels,
  reconcileBoardColumnOrder,
  sameTypeViewConfig,
  typeViewConfigFor,
} from "./note-views";

describe("note view configuration", () => {
  it("defaults every unknown type to the existing List view", () => {
    expect(typeViewConfigFor({}, "Projects")).toEqual(defaultTypeViewConfig());
    expect(typeViewConfigFor({}, "Projects/Client").visibleProperties).toEqual([]);
  });

  it("keeps property visibility independent for each type and subtype", () => {
    const configs = normalizeTypeViewConfigs({
      Projects: { visibleProperties: ["Owner"] },
      "Projects/Client": { visibleProperties: ["Priority"] },
    });

    expect(typeViewConfigFor(configs, "Projects").visibleProperties).toEqual(["Owner"]);
    expect(typeViewConfigFor(configs, "Projects/Client").visibleProperties).toEqual(["Priority"]);
  });

  it("keeps supported portable settings and strips scope-only filters", () => {
    expect(
      normalizeTypeViewConfigs({
        " Projects / Active ": {
          mode: "board",
          visibleProperties: [" Priority ", "Owner", "priority", 42],
          groupBy: " Status ",
          boardColumnOrder: {
            " Status ": ["Done", "Todo", "Done", 42],
            Empty: "not-an-array",
          },
          dateProperty: " Due ",
          filters: {
            sort: "title-asc",
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
        visibleProperties: ["Priority", "Owner"],
        groupBy: "Status",
        boardColumnOrder: { status: ["Done", "Todo"] },
        dateProperty: "Due",
        filters: {
          sort: "title-asc",
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

  it("keeps creation-date sorting in saved views", () => {
    expect(
      normalizeTypeViewConfigs({
        Projects: {
          filters: { sort: "created-desc" },
        },
      }).Projects.filters.sort,
    ).toBe("created-desc");
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

  it("creates one group per relation for multi-relation values", () => {
    expect(propertyGroupLabels(["Epic One", "Epic Two", "Epic One"])).toEqual([
      "Epic One",
      "Epic Two",
    ]);
    expect(propertyGroupLabels([])).toEqual(["No value"]);
    expect(propertyGroupLabels("Epic One")).toEqual(["Epic One"]);
  });

  it("normalizes named saved views per type", () => {
    expect(
      normalizeSavedTypeViews({
        " Work / Epics ": [
          { id: " active ", name: " Active epics ", config: { mode: "board" } },
          { id: "active", name: "Duplicate", config: { mode: "gallery" } },
          { id: "", name: "Missing id", config: {} },
        ],
      }),
    ).toEqual({
      "Work/Epics": [
        {
          id: "active",
          name: "Active epics",
          config: { ...defaultTypeViewConfig(), mode: "board" },
        },
      ],
    });
  });

  it("compares normalized view configurations", () => {
    expect(
      sameTypeViewConfig(
        { ...defaultTypeViewConfig(), mode: "board", groupBy: " Status " },
        { ...defaultTypeViewConfig(), mode: "board", groupBy: "Status" },
      ),
    ).toBe(true);
    expect(
      sameTypeViewConfig(
        { ...defaultTypeViewConfig(), mode: "board" },
        { ...defaultTypeViewConfig(), mode: "gallery" },
      ),
    ).toBe(false);
  });
});
