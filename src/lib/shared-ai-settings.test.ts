import { describe, expect, it } from "vitest";
import { readSharedAiSettings, writeSharedAiSettings } from "./shared-ai-settings";
import type { VaultBackend } from "./vault/backend";

function memoryBackend(): VaultBackend {
  const files = new Map<string, string>();
  return {
    kind: "browser",
    location: "Memory",
    async loadAll() { return []; },
    async readText(path) {
      const value = files.get(path);
      if (value === undefined) throw new Error(`Missing ${path}`);
      return value;
    },
    async listFiles(path) { return [...files.keys()].filter((candidate) => candidate.startsWith(`${path}/`)); },
    async write(path, content) { files.set(path, content); },
    async writeNew(path, content) { files.set(path, content); },
    async move(from, to) { const value = files.get(from); if (value !== undefined) { files.delete(from); files.set(to, value); } },
    async removeFile(path) { files.delete(path); },
    async exists(path) { return files.has(path); },
    async mkDir() {},
    async removeDir() {},
    async renameDir() {},
    async listDirs() { return []; },
    async writeBinary() {},
    async readBinary() { throw new Error("Missing binary"); },
  };
}

describe("shared AI provider settings", () => {
  it("preserves independent OpenRouter and compatible profiles", async () => {
    const backend = memoryBackend();

    await writeSharedAiSettings(backend, {
      provider: "openrouter",
      baseUrl: "https://openrouter.ai/api/v1",
      model: "openai/gpt-5.4-mini",
      favoriteModels: ["openai/gpt-5.4-mini"],
    });
    await writeSharedAiSettings(backend, {
      provider: "compatible",
      baseUrl: "https://models.example.test/v1",
      model: "local-model",
      favoriteModels: ["local-model", "local-fast"],
    });

    const shared = await readSharedAiSettings(backend);
    expect(shared?.settings.activeProvider).toBe("compatible");
    expect(shared?.settings.profiles.openrouter).toEqual({
      baseUrl: "https://openrouter.ai/api/v1",
      model: "openai/gpt-5.4-mini",
      favoriteModels: ["openai/gpt-5.4-mini"],
    });
    expect(shared?.settings.profiles.compatible).toEqual({
      baseUrl: "https://models.example.test/v1",
      model: "local-model",
      favoriteModels: ["local-model", "local-fast"],
    });
  });
});
