import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  forgetDesktopVault,
  loadDesktopVaults,
  rememberDesktopVault,
  vaultNameFromPath,
} from "./vault-registry";

const values = new Map<string, string>();

beforeEach(() => {
  values.clear();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
  });
});

describe("desktop vault registry", () => {
  it("migrates the active vault and keeps newly added vaults", () => {
    rememberDesktopVault("/Users/me/Notes");
    rememberDesktopVault("/Users/me/Work");

    expect(loadDesktopVaults()).toEqual([
      { name: "Work", path: "/Users/me/Work" },
      { name: "Notes", path: "/Users/me/Notes" },
    ]);
  });

  it("deduplicates paths and ignores damaged saved data", () => {
    values.set(
      "zerus.desktopVaults.v1",
      JSON.stringify(["/vault/one", "/vault/one", 42, ""]),
    );
    expect(loadDesktopVaults()).toEqual([
      { name: "one", path: "/vault/one" },
    ]);

    values.set("zerus.desktopVaults.v1", "not json");
    expect(loadDesktopVaults("/vault/current")).toEqual([
      { name: "current", path: "/vault/current" },
    ]);
  });

  it("names POSIX and Windows vault folders", () => {
    expect(vaultNameFromPath("/Users/me/Notes/")).toBe("Notes");
    expect(vaultNameFromPath("C:\\Users\\me\\Notes\\")).toBe("Notes");
  });

  it("forgets a vault without affecting the other saved vaults", () => {
    rememberDesktopVault("/Users/me/Notes");
    rememberDesktopVault("/Users/me/Work");

    expect(forgetDesktopVault("/Users/me/Notes")).toEqual([
      { name: "Work", path: "/Users/me/Work" },
    ]);
    expect(loadDesktopVaults()).toEqual([
      { name: "Work", path: "/Users/me/Work" },
    ]);
  });
});
