import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  DEFAULT_AI_CONFIG,
  readAiProviderConfig,
  readAiProviderProfile,
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

  it("defaults to the cloud provider", () => {
    expect(readAiProviderConfig()).toEqual(DEFAULT_AI_CONFIG);
    expect(DEFAULT_AI_CONFIG.provider).toBe("openai");
  });

  it("persists first-class OpenAI and Anthropic providers", () => {
    for (const config of [
      { provider: "openai" as const, baseUrl: "https://api.openai.com/v1", model: "gpt-5.4-mini" },
      { provider: "anthropic" as const, baseUrl: "https://api.anthropic.com/v1", model: "claude-sonnet-5" },
    ]) {
      saveAiProviderConfig({ ...config, favoriteModels: [config.model] });
      expect(readAiProviderConfig()).toEqual({ ...config, favoriteModels: [config.model] });
    }
  });

  it("persists provider metadata without an API key", () => {
    saveAiProviderConfig({
      provider: "openrouter",
      baseUrl: "https://openrouter.ai/api/v1",
      model: "anthropic/claude-sonnet-4",
      favoriteModels: ["anthropic/claude-sonnet-4", "openai/gpt-5"],
    });

    expect(readAiProviderConfig()).toEqual({
      provider: "openrouter",
      baseUrl: "https://openrouter.ai/api/v1",
      model: "anthropic/claude-sonnet-4",
      favoriteModels: ["anthropic/claude-sonnet-4", "openai/gpt-5"],
    });
    expect(localStorage.getItem("zerus.ai.providers.v2")).not.toContain(
      "apiKey",
    );
  });

  it("migrates older provider settings without a favourites list", () => {
    localStorage.setItem("zerus.ai.provider.v1", JSON.stringify({
      provider: "openrouter",
      baseUrl: "https://openrouter.ai/api/v1",
      model: "anthropic/claude-sonnet-4",
    }));

    expect(readAiProviderConfig()).toEqual({
      provider: "openrouter",
      baseUrl: "https://openrouter.ai/api/v1",
      model: "anthropic/claude-sonnet-4",
      favoriteModels: [],
    });
  });

  it("keeps a separate saved endpoint, model, and favourites for every provider", () => {
    saveAiProviderConfig({
      provider: "compatible",
      baseUrl: "https://example.test/v1",
      model: "custom-vision",
      favoriteModels: ["custom-vision"],
    });
    saveAiProviderConfig({
      provider: "openai",
      baseUrl: "https://api.openai.com/v1",
      model: "gpt-5.4-mini",
      favoriteModels: ["gpt-5.4-mini"],
    });

    expect(readAiProviderConfig().provider).toBe("openai");
    expect(readAiProviderProfile("compatible")).toEqual({
      provider: "compatible",
      baseUrl: "https://example.test/v1",
      model: "custom-vision",
      favoriteModels: ["custom-vision"],
    });
  });

  it("migrates the removed local provider to the cloud default", () => {
    localStorage.setItem("zerus.ai.provider.v1", JSON.stringify({
      provider: "local",
      baseUrl: "",
      model: "Qwen3-1.7B-4bit",
    }));

    expect(readAiProviderConfig()).toEqual(DEFAULT_AI_CONFIG);
  });

  it("normalizes favourite model IDs before saving", () => {
    saveAiProviderConfig({
      provider: "openrouter",
      baseUrl: "https://openrouter.ai/api/v1",
      model: "openai/gpt-5",
      favoriteModels: [" openai/gpt-5 ", "openai/gpt-5", ""],
    });

    expect(readAiProviderConfig().favoriteModels).toEqual(["openai/gpt-5"]);
  });

  it("falls back safely when stored data is invalid", () => {
    localStorage.setItem("zerus.ai.provider.v1", "not-json");
    expect(readAiProviderConfig()).toEqual(DEFAULT_AI_CONFIG);
  });
});
