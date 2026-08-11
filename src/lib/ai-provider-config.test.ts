import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  LOCAL_AI_CONFIG,
  readAiProviderConfig,
  saveAiProviderConfig,
} from "@/lib/ai-provider-config";

describe("AI provider configuration", () => {
  beforeEach(() => {
    const values = new Map<string, string>();
    vi.stubGlobal("localStorage", {
      clear: () => values.clear(),
      getItem: (key: string) => values.get(key) ?? null,
      removeItem: (key: string) => values.delete(key),
      setItem: (key: string, value: string) => values.set(key, value),
    });
  });

  it("defaults to the local model", () => {
    expect(readAiProviderConfig()).toEqual(LOCAL_AI_CONFIG);
  });

  it("persists provider metadata without an API key", () => {
    saveAiProviderConfig({
      provider: "openrouter",
      baseUrl: "https://openrouter.ai/api/v1",
      model: "anthropic/claude-sonnet-4",
    });

    expect(readAiProviderConfig()).toEqual({
      provider: "openrouter",
      baseUrl: "https://openrouter.ai/api/v1",
      model: "anthropic/claude-sonnet-4",
    });
    expect(localStorage.getItem("grimoire.ai.provider.v1")).not.toContain(
      "apiKey",
    );
  });

  it("falls back safely when stored data is invalid", () => {
    localStorage.setItem("grimoire.ai.provider.v1", "not-json");
    expect(readAiProviderConfig()).toEqual(LOCAL_AI_CONFIG);
  });
});
