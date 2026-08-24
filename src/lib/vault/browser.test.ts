import { beforeEach, describe, expect, it, vi } from "vitest";
import { BrowserVault } from "./browser";

const values = new Map<string, string>();

beforeEach(() => {
  values.clear();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
  });
  vi.stubGlobal("btoa", (value: string) => value);
  vi.stubGlobal("atob", (value: string) => value);
});

describe("BrowserVault binary moves", () => {
  it("moves an image into and back out of Zerus Trash", async () => {
    const vault = new BrowserVault();
    const bytes = new Uint8Array([1, 2, 3, 4]);
    await vault.writeBinary("assets/image.png", bytes);

    await vault.move("assets/image.png", ".trash/assets/image.png");
    await expect(vault.readBinary("assets/image.png")).rejects.toThrow();
    await expect(vault.readBinary(".trash/assets/image.png")).resolves.toEqual(bytes);

    await vault.move(".trash/assets/image.png", "assets/image.png");
    await expect(vault.readBinary("assets/image.png")).resolves.toEqual(bytes);
  });
});
