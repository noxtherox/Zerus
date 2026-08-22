import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  DEFAULT_DARK_THEME,
  DEFAULT_LIGHT_THEME,
  DEFAULT_THEME,
  deleteSavedTheme,
  loadSavedThemes,
  loadThemePreferences,
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

describe("theme preferences", () => {
  it("defaults to Paper and Nightshade while matching the system", () => {
    expect(loadThemePreferences()).toEqual({
      mode: "system",
      lightTheme: DEFAULT_LIGHT_THEME,
      darkTheme: DEFAULT_DARK_THEME,
    });
  });

  it("loads independent light and dark customizations", () => {
    const preferences = {
      mode: "dark",
      lightTheme: { ...DEFAULT_LIGHT_THEME, accent: "#123456" },
      darkTheme: { ...DEFAULT_DARK_THEME, accent: "#abcdef" },
    };
    values.set("zerus-theme-preferences", JSON.stringify(preferences));

    expect(loadThemePreferences()).toEqual(preferences);
  });

  it("migrates a previous dark theme without losing it", () => {
    const legacyTheme = { ...DEFAULT_THEME, editorBg: "#101010" };
    values.set("zerus-theme", JSON.stringify(legacyTheme));

    expect(loadThemePreferences()).toEqual({
      mode: "dark",
      lightTheme: DEFAULT_LIGHT_THEME,
      darkTheme: legacyTheme,
    });
  });
});
