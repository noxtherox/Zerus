import { applyLogoForSidebar } from "@/lib/branding";

/**
 * App-wide color theme. Every distinctive Zerus color lives behind a
 * `--zerus-*` CSS variable (an "R G B" triplet so Tailwind opacity modifiers
 * like `bg-zerus-accent/10` keep working). This module owns loading, saving
 * and applying those variables; defaults live in globals.css.
 */

export interface ZerusTheme {
  /** Highlight color: pins, selection tint, tags, cursor, type chip. */
  accent: string;
  /** Wikilinks, URLs and relation chips. */
  link: string;
  /** Main reading text in the editor and note list. */
  text: string;
  /** Editor background (also note cards and inputs on the list). */
  editorBg: string;
  /** Note list & backlinks panel background. */
  surface: string;
  /** Sidebar background. */
  sidebarBg: string;
  /** Sidebar text (dimmer shades are derived from it). */
  sidebarFg: string;
}

export interface SavedTheme {
  name: string;
  theme: ZerusTheme;
}

export type AppearanceMode = "light" | "dark" | "system";
export type ThemeSlot = "light" | "dark";

export interface ThemePreferences {
  mode: AppearanceMode;
  lightTheme: ZerusTheme;
  darkTheme: ZerusTheme;
}

export const DEFAULT_LIGHT_THEME: ZerusTheme = {
  accent: "#d84b40",
  link: "#2563eb",
  text: "#1f2937",
  editorBg: "#ffffff",
  surface: "#f4f5f7",
  sidebarBg: "#e9ebef",
  sidebarFg: "#27303f",
};

export const DEFAULT_DARK_THEME: ZerusTheme = {
  accent: "#a78bfa",
  link: "#8ab4f8",
  text: "#e2ddf0",
  editorBg: "#171522",
  surface: "#1c1930",
  sidebarBg: "#100e1a",
  sidebarFg: "#d5cfe8",
};

/** Kept as the public default for saved-theme compatibility. */
export const DEFAULT_THEME = DEFAULT_LIGHT_THEME;

export const THEME_TOKENS: {
  key: keyof ZerusTheme;
  label: string;
  hint: string;
}[] = [
  { key: "accent", label: "Accent", hint: "Pins, tags, selection, cursor" },
  { key: "link", label: "Links", hint: "Wikilinks and relations" },
  { key: "text", label: "Text", hint: "Main editor & list text" },
  { key: "editorBg", label: "Editor background", hint: "Editor and cards" },
  { key: "surface", label: "List background", hint: "Note list & panels" },
  { key: "sidebarBg", label: "Sidebar background", hint: "Left navigation" },
  { key: "sidebarFg", label: "Sidebar text", hint: "Navigation labels" },
];

export const THEME_PRESETS: { name: string; theme: ZerusTheme }[] = [
  {
    name: "Zerus",
    theme: {
      accent: "#d84b40",
      link: "#0b6acd",
      text: "#020817",
      editorBg: "#ffffff",
      surface: "#f9f8f6",
      sidebarBg: "#1f1f23",
      sidebarFg: "#e4e4e7",
    },
  },
  {
    name: "Ember",
    theme: {
      accent: "#c2410c",
      link: "#b45309",
      text: "#292018",
      editorBg: "#fffcf7",
      surface: "#f8f1e7",
      sidebarBg: "#2c1c12",
      sidebarFg: "#f0e4d7",
    },
  },
  {
    name: "Forest",
    theme: {
      accent: "#2f9e63",
      link: "#0f766e",
      text: "#122117",
      editorBg: "#fdfffc",
      surface: "#f1f6f0",
      sidebarBg: "#14231a",
      sidebarFg: "#d7e8dc",
    },
  },
  {
    name: "Ocean",
    theme: {
      accent: "#0284c7",
      link: "#2563eb",
      text: "#0c1a26",
      editorBg: "#fdfeff",
      surface: "#eff4f8",
      sidebarBg: "#0f1c2e",
      sidebarFg: "#d5e2f0",
    },
  },
  {
    name: "Paper",
    theme: DEFAULT_LIGHT_THEME,
  },
  {
    name: "Parchment",
    theme: {
      accent: "#b85c38",
      link: "#9a5b13",
      text: "#32281f",
      editorBg: "#fffdf8",
      surface: "#f6f0e4",
      sidebarBg: "#ebe1d0",
      sidebarFg: "#4a392a",
    },
  },
  {
    name: "Sage",
    theme: {
      accent: "#2f855a",
      link: "#0f766e",
      text: "#21352b",
      editorBg: "#fbfdf9",
      surface: "#eef4eb",
      sidebarBg: "#dfeadd",
      sidebarFg: "#294332",
    },
  },
  {
    name: "Lavender",
    theme: {
      accent: "#7657d5",
      link: "#6546c4",
      text: "#2d2940",
      editorBg: "#fefcff",
      surface: "#f3f0f8",
      sidebarBg: "#e7e1f1",
      sidebarFg: "#403650",
    },
  },
  {
    name: "Midnight",
    theme: {
      accent: "#e5484d",
      link: "#6ea8fe",
      text: "#dee3ea",
      editorBg: "#14171d",
      surface: "#191d24",
      sidebarBg: "#0e1116",
      sidebarFg: "#cfd6df",
    },
  },
  {
    name: "Nightshade",
    theme: DEFAULT_DARK_THEME,
  },
  {
    name: "Cocoa",
    theme: {
      accent: "#e0a458",
      link: "#d08770",
      text: "#ece1d3",
      editorBg: "#1f1a15",
      surface: "#262019",
      sidebarBg: "#171310",
      sidebarFg: "#e6dccc",
    },
  },
];

const STORAGE_KEY = "zerus-theme";
const THEME_PREFERENCES_STORAGE_KEY = "zerus-theme-preferences";
const SAVED_THEMES_STORAGE_KEY = "zerus-saved-themes";
export const MAX_SAVED_THEME_NAME_LENGTH = 40;

const CSS_VARS: Record<keyof ZerusTheme, string> = {
  accent: "--zerus-accent",
  link: "--zerus-link",
  text: "--zerus-text",
  editorBg: "--zerus-editor-bg",
  surface: "--zerus-surface",
  sidebarBg: "--zerus-sidebar-bg",
  sidebarFg: "--zerus-sidebar-fg",
};

export function isValidHex(value: string): boolean {
  return /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(value.trim());
}

type Rgb = [number, number, number];

function hexToRgb(hex: string): Rgb | null {
  let value = hex.trim().replace(/^#/, "");
  if (value.length === 3) {
    value = [...value].map((char) => char + char).join("");
  }
  if (!/^[0-9a-fA-F]{6}$/.test(value)) return null;
  return [
    parseInt(value.slice(0, 2), 16),
    parseInt(value.slice(2, 4), 16),
    parseInt(value.slice(4, 6), 16),
  ];
}

/** `color` blended over `base` at `weight` (0..1). */
function mix(color: Rgb, base: Rgb, weight: number): Rgb {
  return [0, 1, 2].map((i) =>
    Math.round(color[i] * weight + base[i] * (1 - weight)),
  ) as Rgb;
}

/** → "h s% l%" for the shadcn hsl(var(--…)) variables. */
function rgbToHslTriplet([r, g, b]: Rgb): string {
  const rn = r / 255;
  const gn = g / 255;
  const bn = b / 255;
  const max = Math.max(rn, gn, bn);
  const min = Math.min(rn, gn, bn);
  const l = (max + min) / 2;
  const d = max - min;
  let h = 0;
  let s = 0;
  if (d !== 0) {
    s = d / (1 - Math.abs(2 * l - 1));
    if (max === rn) h = 60 * (((gn - bn) / d) % 6);
    else if (max === gn) h = 60 * ((bn - rn) / d + 2);
    else h = 60 * ((rn - gn) / d + 4);
    if (h < 0) h += 360;
  }
  return `${Math.round(h)} ${Math.round(s * 100)}% ${Math.round(l * 100)}%`;
}

export function applyTheme(theme: ZerusTheme): void {
  const root = document.documentElement;
  for (const key of Object.keys(CSS_VARS) as (keyof ZerusTheme)[]) {
    const rgb = hexToRgb(theme[key]);
    if (rgb) root.style.setProperty(CSS_VARS[key], rgb.join(" "));
  }
  applyLogoForSidebar(theme.sidebarBg);

  // Derive the shadcn neutrals (borders, muted text, dialog/badge surfaces,
  // hover grays) from text-over-editor mixes so dark themes hold together
  // without extra settings.
  const text = hexToRgb(theme.text);
  const editor = hexToRgb(theme.editorBg);
  if (!text || !editor) return;
  const setHsl = (name: string, rgb: Rgb) =>
    root.style.setProperty(name, rgbToHslTriplet(rgb));
  setHsl("--background", editor);
  setHsl("--foreground", text);
  setHsl("--card", editor);
  setHsl("--card-foreground", text);
  setHsl("--popover", editor);
  setHsl("--popover-foreground", text);
  setHsl("--primary", text);
  setHsl("--primary-foreground", editor);
  setHsl("--secondary", mix(text, editor, 0.08));
  setHsl("--secondary-foreground", text);
  setHsl("--muted", mix(text, editor, 0.08));
  setHsl("--muted-foreground", mix(text, editor, 0.62));
  setHsl("--accent", mix(text, editor, 0.07));
  setHsl("--accent-foreground", text);
  setHsl("--border", mix(text, editor, 0.12));
  setHsl("--input", mix(text, editor, 0.12));
  setHsl("--ring", mix(text, editor, 0.6));
}

function systemThemeSlot(): ThemeSlot {
  return typeof window !== "undefined" &&
    window.matchMedia?.("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

export function resolveThemeSlot(mode: AppearanceMode): ThemeSlot {
  return mode === "system" ? systemThemeSlot() : mode;
}

export function applyThemePreferences(preferences: ThemePreferences): void {
  const slot = resolveThemeSlot(preferences.mode);
  const root = document.documentElement;
  root.classList.toggle("dark", slot === "dark");
  root.dataset.zerusAppearance = slot;
  root.style.colorScheme = slot;
  applyTheme(slot === "dark" ? preferences.darkTheme : preferences.lightTheme);
}

export function loadTheme(): ZerusTheme {
  const preferences = loadThemePreferences();
  return {
    ...(resolveThemeSlot(preferences.mode) === "dark"
      ? preferences.darkTheme
      : preferences.lightTheme),
  };
}

function loadLegacyTheme(): ZerusTheme | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<ZerusTheme>;
    const theme = { ...DEFAULT_THEME };
    for (const key of Object.keys(CSS_VARS) as (keyof ZerusTheme)[]) {
      const value = parsed[key];
      if (typeof value === "string" && isValidHex(value)) theme[key] = value;
    }
    return theme;
  } catch {
    return null;
  }
}

function parseCompleteTheme(value: unknown): ZerusTheme | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Partial<ZerusTheme>;
  const theme = { ...DEFAULT_THEME };
  for (const key of Object.keys(CSS_VARS) as (keyof ZerusTheme)[]) {
    const color = candidate[key];
    if (typeof color !== "string" || !isValidHex(color)) return null;
    theme[key] = color.trim();
  }
  return theme;
}

function isAppearanceMode(value: unknown): value is AppearanceMode {
  return value === "light" || value === "dark" || value === "system";
}

function isDarkTheme(theme: ZerusTheme): boolean {
  const background = hexToRgb(theme.editorBg);
  if (!background) return false;
  return (background[0] * 299 + background[1] * 587 + background[2] * 114) /
    1000 < 128;
}

export function loadThemePreferences(): ThemePreferences {
  try {
    const raw = localStorage.getItem(THEME_PREFERENCES_STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as Partial<ThemePreferences>;
      const lightTheme = parseCompleteTheme(parsed.lightTheme);
      const darkTheme = parseCompleteTheme(parsed.darkTheme);
      if (isAppearanceMode(parsed.mode) && lightTheme && darkTheme) {
        return { mode: parsed.mode, lightTheme, darkTheme };
      }
    }
  } catch {
    // Fall through to defaults or migration from the previous single theme.
  }

  const legacy = loadLegacyTheme();
  if (legacy) {
    const legacyIsDark = isDarkTheme(legacy);
    return {
      mode: legacyIsDark ? "dark" : "light",
      lightTheme: legacyIsDark ? { ...DEFAULT_LIGHT_THEME } : legacy,
      darkTheme: legacyIsDark ? legacy : { ...DEFAULT_DARK_THEME },
    };
  }

  return {
    mode: "system",
    lightTheme: { ...DEFAULT_LIGHT_THEME },
    darkTheme: { ...DEFAULT_DARK_THEME },
  };
}

export function saveThemePreferences(preferences: ThemePreferences): void {
  try {
    localStorage.setItem(
      THEME_PREFERENCES_STORAGE_KEY,
      JSON.stringify(preferences),
    );
  } catch {
    // Persistence is best-effort; the themes still apply for this session.
  }
  applyThemePreferences(preferences);
}

export function loadSavedThemes(): SavedTheme[] {
  try {
    const raw = localStorage.getItem(SAVED_THEMES_STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];

    const names = new Set<string>();
    const saved: SavedTheme[] = [];
    for (const item of parsed) {
      if (!item || typeof item !== "object") continue;
      const name =
        typeof item.name === "string"
          ? item.name.trim().slice(0, MAX_SAVED_THEME_NAME_LENGTH)
          : "";
      const theme = parseCompleteTheme(item.theme);
      const normalizedName = name.toLocaleLowerCase();
      if (!name || !theme || names.has(normalizedName)) continue;
      names.add(normalizedName);
      saved.push({ name, theme });
    }
    return saved;
  } catch {
    return [];
  }
}

/** Save a named theme, replacing the existing saved theme with the same name. */
export function saveNamedTheme(
  name: string,
  theme: ZerusTheme,
): SavedTheme[] {
  const cleanName = name.trim().slice(0, MAX_SAVED_THEME_NAME_LENGTH);
  if (!cleanName) return loadSavedThemes();

  const saved = loadSavedThemes();
  const match = saved.findIndex(
    (candidate) =>
      candidate.name.toLocaleLowerCase() === cleanName.toLocaleLowerCase(),
  );
  const nextTheme = { name: cleanName, theme: { ...theme } };
  const next =
    match === -1
      ? [...saved, nextTheme]
      : saved.map((candidate, index) =>
          index === match ? nextTheme : candidate,
        );

  try {
    localStorage.setItem(SAVED_THEMES_STORAGE_KEY, JSON.stringify(next));
  } catch {
    // Persistence is best-effort; keep the in-memory result available to the UI.
  }
  return next;
}

export function deleteSavedTheme(name: string): SavedTheme[] {
  const normalizedName = name.trim().toLocaleLowerCase();
  const next = loadSavedThemes().filter(
    (candidate) => candidate.name.toLocaleLowerCase() !== normalizedName,
  );
  try {
    localStorage.setItem(SAVED_THEMES_STORAGE_KEY, JSON.stringify(next));
  } catch {
    // Persistence is best-effort.
  }
  return next;
}

export function saveTheme(theme: ZerusTheme): void {
  const preferences = loadThemePreferences();
  const slot = resolveThemeSlot(preferences.mode);
  saveThemePreferences({
    ...preferences,
    [slot === "dark" ? "darkTheme" : "lightTheme"]: { ...theme },
  });
}

/** Apply whatever theme is saved (call once on startup). */
export function initTheme(): void {
  applyThemePreferences(loadThemePreferences());
  if (typeof window === "undefined" || !window.matchMedia) return;

  const media = window.matchMedia("(prefers-color-scheme: dark)");
  media.addEventListener("change", () => {
    const preferences = loadThemePreferences();
    if (preferences.mode === "system") applyThemePreferences(preferences);
  });
}
