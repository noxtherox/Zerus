import { describe, expect, it } from "vitest";
import {
  effectiveProperties,
  effectivePropertyDefinitions,
  listPropertyValue,
  listOptionToCreate,
  listPickerLabel,
  listSelections,
  normalizeListOptions,
  propertyDefinitionOwner,
  schemaKeyFor,
} from "./properties";

describe("list properties", () => {
  it("normalizes blank and duplicate options", () => {
    expect(normalizeListOptions([" Todo ", "", "todo", "Done"])).toEqual([
      "Todo",
      "Done",
    ]);
  });

  it("reads both legacy scalar values and arrays as selections", () => {
    expect(listSelections("Todo")).toEqual(["Todo"]);
    expect(listSelections(["Todo", "Done"])).toEqual(["Todo", "Done"]);
    expect(listSelections(undefined)).toEqual([]);
  });

  it("serializes one or many selections according to the configured mode", () => {
    expect(listPropertyValue(["Todo", "Done"], false)).toBe("Todo");
    expect(listPropertyValue(["Todo", "Done"], true)).toEqual([
      "Todo",
      "Done",
    ]);
    expect(listPropertyValue([], true)).toBeNull();
  });

  it("offers a normalized typed option only when it does not already exist", () => {
    expect(listOptionToCreate("  Deep Work  ", ["Personal"])).toBe("Deep Work");
    expect(listOptionToCreate("work", ["Work", "Personal"])).toBeNull();
    expect(listOptionToCreate("   ", [])).toBeNull();
  });

  it("invites creation when a creatable selector has no options", () => {
    expect(listPickerLabel(0, 0, "Create category")).toBe("Create category");
    expect(listPickerLabel(0, 2, "Create category")).toBe("Select");
    expect(listPickerLabel(1, 2, "Create category")).toBe("Add");
  });
});

describe("type property inheritance", () => {
  const schemas = {
    Development: [
      { name: "Company", type: "relation" as const },
      { name: "Status", type: "text" as const },
    ],
    "Development/Initiatives": [
      { name: "Epics", type: "relation" as const },
      { name: "Status", type: "list" as const, listOptions: ["Active"] },
    ],
  };

  it("uses the complete type path as the schema key", () => {
    expect(schemaKeyFor(["Development", "Initiatives"])).toBe(
      "Development/Initiatives",
    );
  });

  it("inherits parent properties and lets the subtype override by name", () => {
    expect(
      effectiveProperties(["Development", "Initiatives"], schemas),
    ).toEqual([
      { name: "Company", type: "relation" },
      { name: "Status", type: "list", listOptions: ["Active"] },
      { name: "Epics", type: "relation" },
    ]);
  });

  it("retains the owner of every effective definition", () => {
    expect(
      effectivePropertyDefinitions(
        ["Development", "Initiatives"],
        schemas,
      ).map(({ def, ownerKey }) => [def.name, ownerKey]),
    ).toEqual([
      ["Company", "Development"],
      ["Status", "Development/Initiatives"],
      ["Epics", "Development/Initiatives"],
    ]);
    expect(
      propertyDefinitionOwner(
        ["Development", "Initiatives"],
        schemas,
        "status",
      ),
    ).toBe("Development/Initiatives");
  });
});
