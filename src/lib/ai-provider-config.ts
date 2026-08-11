export type AiProvider = "local" | "openrouter" | "compatible";

export interface AiProviderConfig {
  provider: AiProvider;
  baseUrl: string;
  model: string;
}

export interface CloudAiModel {
  id: string;
  name: string;
}

export const LOCAL_AI_CONFIG: AiProviderConfig = {
  provider: "local",
  baseUrl: "",
  model: "Qwen3-1.7B-4bit",
};

const CONFIG_STORAGE_KEY = "zerus.ai.provider.v1";

export function readAiProviderConfig(): AiProviderConfig {
  try {
    const value = JSON.parse(
      localStorage.getItem(CONFIG_STORAGE_KEY) ?? "null",
    ) as Partial<AiProviderConfig> | null;
    if (
      value &&
      (value.provider === "local" ||
        value.provider === "openrouter" ||
        value.provider === "compatible") &&
      typeof value.baseUrl === "string" &&
      typeof value.model === "string"
    ) {
      return value.provider === "local"
        ? LOCAL_AI_CONFIG
        : (value as AiProviderConfig);
    }
  } catch {
    // Fall back to local AI when an older configuration cannot be read.
  }
  return LOCAL_AI_CONFIG;
}

export function saveAiProviderConfig(config: AiProviderConfig) {
  localStorage.setItem(CONFIG_STORAGE_KEY, JSON.stringify(config));
}
