import { describe, expect, it } from "vitest";
import type { VaultBackend } from "./vault/backend";
import {
  EDITOR_SETTINGS_PATH,
  newerEditorSettings,
  readEditorSettings,
  writeEditorSettings,
} from "./editor-settings";

function settingsBackend(initial?: string) {
  const files = new Map<string, string>();
  if (initial !== undefined) files.set(EDITOR_SETTINGS_PATH, initial);
  const backend = {
    readText: async (path: string) => {
      const value = files.get(path);
      if (value === undefined) throw new Error("missing");
      return value;
    },
    write: async (path: string, content: string) => {
      files.set(path, content);
    },
  } as unknown as VaultBackend;
  return { backend, files };
}

describe("vault editor settings", () => {
  it("returns null for missing, malformed, or unsupported settings", async () => {
    expect(await readEditorSettings(settingsBackend().backend)).toBeNull();
    expect(
      await readEditorSettings(settingsBackend("{broken").backend),
    ).toBeNull();
    expect(
      await readEditorSettings(
        settingsBackend(JSON.stringify({ version: 2 })).backend,
      ),
    ).toBeNull();
  });

  it("writes and reads both synchronized editor preferences", async () => {
    const target = settingsBackend();
    await writeEditorSettings(target.backend, {
      editorMode: "markdown-aware",
      markdownTypingEnabled: false,
    });

    expect(await readEditorSettings(target.backend)).toMatchObject({
      version: 1,
      editorMode: "markdown-aware",
      markdownTypingEnabled: false,
    });
  });

  it("uses the latest timestamp for offline conflict resolution", () => {
    const older = {
      version: 1 as const,
      editorMode: "clean" as const,
      markdownTypingEnabled: true,
      updatedAt: "2026-01-01T00:00:00.000Z",
    };
    const newer = {
      ...older,
      markdownTypingEnabled: false,
      updatedAt: "2026-01-02T00:00:00.000Z",
    };
    expect(newerEditorSettings(older, newer)).toBe(newer);
    expect(newerEditorSettings(newer, older)).toBe(newer);
  });
});
