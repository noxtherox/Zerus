import { afterEach, expect, it, vi } from "vitest";
import { loadLinkPreview, saveLinkPreview } from "./link-preview";

afterEach(() => vi.unstubAllGlobals());

it("requires a fresh opt-in for a changed URL and keeps links independent", () => {
  const values = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
    removeItem: (key: string) => values.delete(key),
  });
  expect(loadLinkPreview("one", "https://example.com/")).toBe(false);
  saveLinkPreview("one", "https://example.com/", true);
  expect(loadLinkPreview("one", "https://example.com/")).toBe(true);
  expect(loadLinkPreview("one", "https://example.org/")).toBe(false);
  expect(loadLinkPreview("two", "https://example.com/")).toBe(false);
  saveLinkPreview("one", "https://example.com/", false);
  expect(loadLinkPreview("one", "https://example.com/")).toBe(false);
});

it("defaults to no network preview when device storage is unavailable", () => {
  vi.stubGlobal("localStorage", {
    getItem: () => { throw new Error("Unavailable"); },
    setItem: () => { throw new Error("Unavailable"); },
    removeItem: () => { throw new Error("Unavailable"); },
  });
  expect(loadLinkPreview("one", "https://example.com/")).toBe(false);
  expect(() => saveLinkPreview("one", "https://example.com/", true)).not.toThrow();
  expect(() => saveLinkPreview("one", "https://example.com/", false)).not.toThrow();
});
