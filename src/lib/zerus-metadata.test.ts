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

  it("keeps an explicit empty property key", () => {
    const content = setContentProperty("# Note", "Due", "");

    expect(content).toContain("Due:\n");
    expect(getNoteProperties(content).Due).toBe("");
  });
});
