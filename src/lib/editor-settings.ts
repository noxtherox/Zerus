import type { VaultBackend } from "@/lib/vault/backend";
import {
  DEFAULT_EDITOR_MODE,
  DEFAULT_MARKDOWN_TYPING_ENABLED,
  EDITOR_MODE_OPTIONS,
  type EditorMode,
} from "@/lib/note-preferences";

export const EDITOR_SETTINGS_PATH = ".zerus/editor-settings.json";

export interface EditorSettings {
  version: 1;
  editorMode: EditorMode;
  markdownTypingEnabled: boolean;
  updatedAt: string;
}

export interface EditorSettingsValues {
  editorMode: EditorMode;
  markdownTypingEnabled: boolean;
}

export const DEFAULT_EDITOR_SETTINGS_VALUES: EditorSettingsValues = {
  editorMode: DEFAULT_EDITOR_MODE,
  markdownTypingEnabled: DEFAULT_MARKDOWN_TYPING_ENABLED,
};

function isEditorMode(value: unknown): value is EditorMode {
  return EDITOR_MODE_OPTIONS.some((mode) => mode === value);
}

function normalizeEditorSettings(value: unknown): EditorSettings | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Partial<EditorSettings>;
  if (
    candidate.version !== 1 ||
    !isEditorMode(candidate.editorMode) ||
    typeof candidate.markdownTypingEnabled !== "boolean"
  ) {
    return null;
  }
  return {
    version: 1,
    editorMode: candidate.editorMode,
    markdownTypingEnabled: candidate.markdownTypingEnabled,
    updatedAt:
      typeof candidate.updatedAt === "string"
        ? candidate.updatedAt
        : new Date(0).toISOString(),
  };
}

export async function readEditorSettings(
  backend: VaultBackend,
): Promise<EditorSettings | null> {
  try {
    return normalizeEditorSettings(
      JSON.parse(await backend.readText(EDITOR_SETTINGS_PATH)),
    );
  } catch {
    return null;
  }
}

export async function writeEditorSettings(
  backend: VaultBackend,
  values: EditorSettingsValues,
): Promise<EditorSettings> {
  const settings: EditorSettings = {
    version: 1,
    editorMode: values.editorMode,
    markdownTypingEnabled: values.markdownTypingEnabled,
    updatedAt: new Date().toISOString(),
  };
  await backend.write(
    EDITOR_SETTINGS_PATH,
    JSON.stringify(settings, null, 2),
  );
  return settings;
}

/** ISO timestamps are compared numerically so invalid clocks lose safely. */
export function newerEditorSettings(
  current: EditorSettings,
  candidate: EditorSettings,
): EditorSettings {
  const currentTime = Date.parse(current.updatedAt);
  const candidateTime = Date.parse(candidate.updatedAt);
  if (!Number.isFinite(candidateTime)) return current;
  if (!Number.isFinite(currentTime) || candidateTime > currentTime) {
    return candidate;
  }
  return current;
}
