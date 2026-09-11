import { useState } from "react";
import { Check, RotateCcw, Save, Trash2 } from "lucide-react";
import {
  DEFAULT_DARK_THEME,
  DEFAULT_LIGHT_THEME,
  MAX_SAVED_THEME_NAME_LENGTH,
  THEME_PRESETS,
  THEME_TOKENS,
  deleteSavedTheme,
  loadSavedThemes,
  loadThemePreferences,
  resolveThemeSlot,
  saveNamedTheme,
  saveThemePreferences,
  type AppearanceMode,
  type ThemeSlot,
  type ZerusTheme,
} from "@/lib/theme";

const modeLabels: Record<AppearanceMode, string> = {
  light: "Light",
  dark: "Dark",
  system: "System",
};

function ThemeSwatch({ theme }: { theme: ZerusTheme }) {
  return (
    <span
      className="flex h-7 w-12 shrink-0 overflow-hidden rounded-full border border-zerus-text/10"
      aria-hidden="true"
    >
      {[theme.sidebarBg, theme.surface, theme.accent].map((color) => (
        <span key={color} className="h-full flex-1" style={{ backgroundColor: color }} />
      ))}
    </span>
  );
}

export function MobileThemeSettings() {
  const [preferences, setPreferences] = useState(loadThemePreferences);
  const [editingTheme, setEditingTheme] = useState<ThemeSlot>(() =>
    resolveThemeSlot(loadThemePreferences().mode),
  );
  const [savedThemes, setSavedThemes] = useState(loadSavedThemes);
  const [themeName, setThemeName] = useState("");

  const theme =
    editingTheme === "light" ? preferences.lightTheme : preferences.darkTheme;
  const cleanThemeName = themeName.trim();
  const hasBuiltInName = THEME_PRESETS.some(
    (preset) => preset.name.toLocaleLowerCase() === cleanThemeName.toLocaleLowerCase(),
  );

  const savePreferences = (next: typeof preferences) => {
    setPreferences(next);
    saveThemePreferences(next);
  };

  const setMode = (mode: AppearanceMode) => {
    savePreferences({ ...preferences, mode });
    setEditingTheme(resolveThemeSlot(mode));
  };

  const selectThemeToCustomize = (slot: ThemeSlot) => {
    savePreferences({ ...preferences, mode: slot });
    setEditingTheme(slot);
  };

  const updateTheme = (nextTheme: ZerusTheme) => {
    const key = editingTheme === "light" ? "lightTheme" : "darkTheme";
    savePreferences({ ...preferences, [key]: { ...nextTheme } });
  };

  const updateColor = (key: keyof ZerusTheme, color: string) => {
    updateTheme({ ...theme, [key]: color });
  };

  const saveCurrentTheme = () => {
    if (!cleanThemeName || hasBuiltInName) return;
    setSavedThemes(saveNamedTheme(cleanThemeName, theme));
    setThemeName("");
  };

  const reset = () => {
    const next = {
      mode: "system" as const,
      lightTheme: { ...DEFAULT_LIGHT_THEME },
      darkTheme: { ...DEFAULT_DARK_THEME },
    };
    savePreferences(next);
    setEditingTheme(resolveThemeSlot(next.mode));
  };

  return (
    <section aria-labelledby="mobile-appearance-heading">
      <p
        id="mobile-appearance-heading"
        className="mb-2 mt-6 text-xs font-semibold uppercase tracking-[0.08em] text-zerus-text/45"
      >
        Appearance
      </p>
      <div className="space-y-5 rounded-[16px] bg-zerus-surface p-4">
        <div>
          <span className="block text-[15px] font-semibold">Theme</span>
          <p className="mt-0.5 text-xs leading-4 text-zerus-text/55">
            Choose an appearance or follow this device.
          </p>
          <div className="mt-3 grid grid-cols-3 gap-2" role="group" aria-label="Appearance mode">
            {(Object.keys(modeLabels) as AppearanceMode[]).map((mode) => {
              const selected = preferences.mode === mode;
              return (
                <button
                  type="button"
                  key={mode}
                  onClick={() => setMode(mode)}
                  aria-pressed={selected}
                  className="flex min-h-11 items-center justify-center gap-1.5 rounded-[11px] border border-zerus-text/10 bg-zerus-editor px-2 text-sm font-semibold text-zerus-text transition active:scale-[0.98]"
                >
                  {selected && <Check className="h-3.5 w-3.5 text-zerus-accent" />}
                  {modeLabels[mode]}
                </button>
              );
            })}
          </div>
        </div>

        <div className="border-t border-zerus-text/10 pt-4">
          <span className="block text-[15px] font-semibold">Customize</span>
          <p className="mt-0.5 text-xs leading-4 text-zerus-text/55">
            Presets and colours are saved separately for light and dark mode.
          </p>
          <div className="mt-3 grid grid-cols-2 gap-2" role="group" aria-label="Theme to customize">
            {(["light", "dark"] as ThemeSlot[]).map((slot) => (
              <button
                type="button"
                key={slot}
                onClick={() => selectThemeToCustomize(slot)}
                aria-pressed={editingTheme === slot}
                className={`min-h-10 rounded-[10px] border px-3 text-sm font-semibold transition ${
                  editingTheme === slot
                    ? "border-zerus-accent bg-zerus-accent/10 text-zerus-accent"
                    : "border-zerus-text/10 bg-zerus-editor text-zerus-text/70"
                }`}
              >
                {slot === "light" ? "Light theme" : "Dark theme"}
              </button>
            ))}
          </div>
        </div>

        <div className="border-t border-zerus-text/10 pt-4">
          <p className="mb-2 text-xs font-semibold text-zerus-text/55">
            Presets for the {editingTheme} theme
          </p>
          <div className="grid grid-cols-2 gap-2">
            {THEME_PRESETS.map((preset) => (
              <button
                type="button"
                key={preset.name}
                onClick={() => updateTheme(preset.theme)}
                className="flex min-h-11 items-center gap-2 rounded-[11px] border border-zerus-text/10 bg-zerus-editor px-3 text-left text-sm font-medium text-zerus-text transition active:scale-[0.98]"
              >
                <ThemeSwatch theme={preset.theme} />
                <span className="truncate">{preset.name}</span>
              </button>
            ))}
          </div>
        </div>

        {savedThemes.length > 0 && (
          <div className="border-t border-zerus-text/10 pt-4">
            <p className="mb-2 text-xs font-semibold text-zerus-text/55">Saved themes</p>
            <div className="space-y-2">
              {savedThemes.map((saved) => (
                <div key={saved.name} className="flex overflow-hidden rounded-[11px] border border-zerus-text/10 bg-zerus-editor">
                  <button type="button" onClick={() => updateTheme(saved.theme)} className="flex min-h-11 min-w-0 flex-1 items-center gap-2 px-3 text-left text-sm font-medium">
                    <ThemeSwatch theme={saved.theme} />
                    <span className="truncate">{saved.name}</span>
                  </button>
                  <button
                    type="button"
                    onClick={() => setSavedThemes(deleteSavedTheme(saved.name))}
                    className="flex w-11 shrink-0 items-center justify-center border-l border-zerus-text/10 text-zerus-text/45"
                    aria-label={`Delete saved theme ${saved.name}`}
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        <div className="space-y-2 border-t border-zerus-text/10 pt-4">
          {THEME_TOKENS.map((token) => (
            <label key={token.key} htmlFor={`mobile-theme-${token.key}`} className="flex min-h-11 items-center gap-3">
              <span className="min-w-0 flex-1">
                <span className="block text-sm font-medium">{token.label}</span>
                <span className="block truncate text-xs text-zerus-text/50">{token.hint}</span>
              </span>
              <span className="font-mono text-[11px] uppercase text-zerus-text/50">{theme[token.key]}</span>
              <input
                id={`mobile-theme-${token.key}`}
                type="color"
                value={theme[token.key]}
                onChange={(event) => updateColor(token.key, event.target.value)}
                className="h-9 w-11 shrink-0 cursor-pointer rounded-[9px] border border-zerus-text/10 bg-transparent p-1"
              />
            </label>
          ))}
        </div>

        <div className="border-t border-zerus-text/10 pt-4">
          <label htmlFor="mobile-theme-name" className="text-sm font-medium">Save this theme</label>
          <div className="mt-2 flex gap-2">
            <input
              id="mobile-theme-name"
              value={themeName}
              maxLength={MAX_SAVED_THEME_NAME_LENGTH}
              onChange={(event) => setThemeName(event.target.value)}
              onKeyDown={(event) => event.key === "Enter" && saveCurrentTheme()}
              placeholder="Theme name"
              className="min-h-11 min-w-0 flex-1 rounded-[11px] border border-zerus-text/10 bg-zerus-editor px-3 text-base text-zerus-text placeholder:text-zerus-text/40"
            />
            <button
              type="button"
              onClick={saveCurrentTheme}
              disabled={!cleanThemeName || hasBuiltInName}
              className="flex min-h-11 shrink-0 items-center gap-1.5 rounded-[11px] bg-zerus-accent px-3 text-sm font-semibold text-white disabled:opacity-40"
            >
              <Save className="h-4 w-4" /> Save
            </button>
          </div>
          {hasBuiltInName && <p className="mt-2 text-xs text-destructive">Choose a different name from the built-in themes.</p>}
        </div>

        <button
          type="button"
          onClick={reset}
          className="flex min-h-11 w-full items-center justify-center gap-2 border-t border-zerus-text/10 pt-4 text-sm font-semibold text-zerus-accent"
        >
          <RotateCcw className="h-4 w-4" /> Reset appearance
        </button>
      </div>
    </section>
  );
}
