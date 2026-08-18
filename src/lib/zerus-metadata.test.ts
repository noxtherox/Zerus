import { describe, expect, it } from "vitest";
import {
  ZERUS_METADATA_KEYS,
  isReservedZerusProperty,
} from "@/lib/zerus-metadata";

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
});
