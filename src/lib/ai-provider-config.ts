export type AiProvider = "openrouter" | "compatible";

export interface AiProviderConfig {
  provider: AiProvider;
  baseUrl: string;
  model: string;
  favoriteModels: string[];
}

export interface CloudAiModel {
  id: string;
  name: string;
}

export const DEFAULT_AI_CONFIG: AiProviderConfig = {
  provider: "openrouter",
  baseUrl: "https://openrouter.ai/api/v1",
  model: "openai/gpt-5-mini",
  favoriteModels: [],
};

const CONFIG_STORAGE_KEY = "zerus.ai.provider.v1";

export function readAiProviderConfig(): AiProviderConfig {
  try {
    const value = JSON.parse(
      localStorage.getItem(CONFIG_STORAGE_KEY) ?? "null",
    ) as Partial<AiProviderConfig> | null;
    if (
      value &&
      (value.provider === "openrouter" ||
        value.provider === "compatible") &&
      typeof value.baseUrl === "string" &&
      typeof value.model === "string"
    ) {
      return {
        provider: value.provider,
        baseUrl: value.baseUrl,
        model: value.model,
        favoriteModels: Array.isArray(value.favoriteModels)
          ? [...new Set(
              value.favoriteModels
                .filter((model): model is string => typeof model === "string")
                .map((model) => model.trim())
                .filter((model) => model.length > 0 && model.length <= 200),
            )]
          : [],
      };
    }
  } catch {
    // Fall back to the default cloud provider when configuration is missing or stale.
  }
  return DEFAULT_AI_CONFIG;
}

export function saveAiProviderConfig(config: AiProviderConfig) {
  localStorage.setItem(
    CONFIG_STORAGE_KEY,
    JSON.stringify({
      ...config,
      favoriteModels: [...new Set(
        config.favoriteModels
          .map((model) => model.trim())
          .filter((model) => model.length > 0 && model.length <= 200),
      )],
    }),
  );
}
