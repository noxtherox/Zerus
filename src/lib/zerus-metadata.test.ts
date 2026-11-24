import { describe, expect, it } from "vitest";
import {
  ZERUS_METADATA_KEYS,
  isReservedZerusProperty,
  readZerusMetadata,
  setZerusState,
} from "@/lib/zerus-metadata";
import { getNoteProperties, setContentProperty } from "@/lib/frontmatter";

describe("Zerus reserved metadata", () => {
  it("reserves the legacy vault metadata namespace case-insensitively", () => {
    expect(isReservedZerusProperty(ZERUS_METADATA_KEYS.id)).toBe(true);
    expect(isReservedZerusProperty("Zerus-Pinned")).toBe(true);
    expect(isReservedZerusProperty(" zerus-future-key ")).toBe(true);
  });

  it("does not hide ordinary user properties", () => {
    expect(isReservedZerusProperty("status")).toBe(false);
    expect(isReservedZerusProperty("my-zerus-note")).toBe(false);
  });

  it("allows archived notes to remain pinned", () => {
    const pinned = setZerusState("# Note", { pinned: true });
    const archived = setZerusState(pinned, { archived: true });

    expect(readZerusMetadata(archived)).toMatchObject({
      pinned: true,
      archived: true,
    });
  });

  it.each([
    ["true", true], ["TRUE", true], ['"true"', true], ["'TRUE'", true],
    ["false", false], ['"FALSE"', false], ["", false], ['" true "', false],
    ["1", false], ["[true]", false],
  ])("reads reserved flag scalars %s consistently with shared metadata", (raw, enabled) => {
    const id = "28500000-0000-4000-8000-000000000001";
    for (const [idKey, pinKey, archiveKey] of [
      ["zerus-id", "zerus-pinned", "zerus-archived"],
      ["ZeRuS-Id", "Zerus-Pinned", "ZERUS-ARCHIVED"],
    ]) {
      const content = `---\r\n${idKey}: "${id}"\r\n${pinKey}: ${raw}\r\n${archiveKey}: ${raw}\r\nStatus: "true"\r\n---\r\n# Note\r\n`;
      for (const legacy of [false, true]) {
        expect.soft(readZerusMetadata(content, { pinned: legacy, archived: legacy })).toEqual({ id, pinned: enabled, archived: enabled });
      }
      expect(getNoteProperties(content).Status).toBe("true");
    }
  });

  it("uses legacy flags only when a reserved flag is absent", () => {
    expect(readZerusMetadata("# Note", { pinned: true, archived: true })).toEqual({ id: null, pinned: true, archived: true });
    expect(readZerusMetadata("---\nzerus-pinned: false\nzerus-archived: \"false\"\n---\n# Note", { pinned: true, archived: true })).toEqual({ id: null, pinned: false, archived: false });
  });

  it("keeps an explicit empty property key", () => {
    const content = setContentProperty("# Note", "Due", "");

    expect(content).toContain("Due:\n");
    expect(getNoteProperties(content).Due).toBe("");
  });
});
