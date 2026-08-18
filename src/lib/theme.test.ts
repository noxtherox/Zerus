import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  DEFAULT_THEME,
  deleteSavedTheme,
  loadSavedThemes,
  saveNamedTheme,
} from "./theme";

const values = new Map<string, string>();

beforeEach(() => {
  values.clear();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
  });
});

describe("saved themes", () => {
  it("saves and loads a named copy of a theme", () => {
    const theme = { ...DEFAULT_THEME, accent: "#123456" };

    saveNamedTheme("My theme", theme);
    theme.accent = "#abcdef";

    expect(loadSavedThemes()).toEqual([
      {
        name: "My theme",
        theme: { ...DEFAULT_THEME, accent: "#123456" },
      },
    ]);
  });

  it("updates names case-insensitively without creating duplicates", () => {
    saveNamedTheme("Evening", DEFAULT_THEME);
    saveNamedTheme("evening", { ...DEFAULT_THEME, editorBg: "#101010" });

    expect(loadSavedThemes()).toEqual([
      {
        name: "evening",
        theme: { ...DEFAULT_THEME, editorBg: "#101010" },
      },
    ]);
  });

  it("ignores malformed saved themes", () => {
    values.set(
      "zerus-saved-themes",
      JSON.stringify([
        { name: "Valid", theme: DEFAULT_THEME },
        { name: "Broken", theme: { ...DEFAULT_THEME, text: "red" } },
        { name: "", theme: DEFAULT_THEME },
      ]),
    );

    expect(loadSavedThemes()).toEqual([
      { name: "Valid", theme: DEFAULT_THEME },
    ]);
  });

  it("deletes a saved theme by name", () => {
    saveNamedTheme("First", DEFAULT_THEME);
    saveNamedTheme("Second", DEFAULT_THEME);

    deleteSavedTheme("FIRST");

    expect(loadSavedThemes().map(({ name }) => name)).toEqual(["Second"]);
  });
});
