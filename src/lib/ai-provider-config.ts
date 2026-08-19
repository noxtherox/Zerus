export type AiProvider = "openai" | "anthropic" | "openrouter" | "compatible";

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

type AiProviderProfile = Omit<AiProviderConfig, "provider">;

interface StoredAiProviderSettings {
  activeProvider: AiProvider;
  profiles: Partial<Record<AiProvider, AiProviderProfile>>;
}

export const DEFAULT_AI_PROVIDER_CONFIGS: Record<AiProvider, AiProviderConfig> = {
  openai: {
    provider: "openai",
    baseUrl: "https://api.openai.com/v1",
    model: "gpt-5.4-mini",
    favoriteModels: [],
  },
  anthropic: {
    provider: "anthropic",
    baseUrl: "https://api.anthropic.com/v1",
    model: "claude-sonnet-5",
    favoriteModels: [],
  },
  openrouter: {
    provider: "openrouter",
    baseUrl: "https://openrouter.ai/api/v1",
    model: "openai/gpt-5.4-mini",
    favoriteModels: [],
  },
  compatible: {
    provider: "compatible",
    baseUrl: "",
    model: "",
    favoriteModels: [],
  },
};

export const DEFAULT_AI_CONFIG = DEFAULT_AI_PROVIDER_CONFIGS.openai;

const LEGACY_CONFIG_STORAGE_KEY = "zerus.ai.provider.v1";
const CONFIG_STORAGE_KEY = "zerus.ai.providers.v2";

function isProvider(value: unknown): value is AiProvider {
  return value === "openai" || value === "anthropic" ||
    value === "openrouter" || value === "compatible";
}

function normalizedFavorites(value: unknown): string[] {
  return Array.isArray(value)
    ? [...new Set(
        value
          .filter((model): model is string => typeof model === "string")
          .map((model) => model.trim())
          .filter((model) => model.length > 0 && model.length <= 200),
      )]
    : [];
}

function normalizedProfile(value: unknown): AiProviderProfile | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const candidate = value as Partial<AiProviderProfile>;
  if (typeof candidate.baseUrl !== "string" || typeof candidate.model !== "string") {
    return null;
  }
  return {
    baseUrl: candidate.baseUrl,
    model: candidate.model,
    favoriteModels: normalizedFavorites(candidate.favoriteModels),
  };
}

function defaultSettings(): StoredAiProviderSettings {
  return {
    activeProvider: DEFAULT_AI_CONFIG.provider,
    profiles: Object.fromEntries(
      Object.entries(DEFAULT_AI_PROVIDER_CONFIGS).map(([provider, config]) => [
        provider,
        {
          baseUrl: config.baseUrl,
          model: config.model,
          favoriteModels: config.favoriteModels,
        },
      ]),
    ),
  };
}

function readSettings(): StoredAiProviderSettings {
  try {
    const value = JSON.parse(localStorage.getItem(CONFIG_STORAGE_KEY) ?? "null") as
      Partial<StoredAiProviderSettings> | null;
    if (value && isProvider(value.activeProvider) && value.profiles &&
      typeof value.profiles === "object" && !Array.isArray(value.profiles)) {
      const settings = defaultSettings();
      settings.activeProvider = value.activeProvider;
      for (const provider of Object.keys(DEFAULT_AI_PROVIDER_CONFIGS) as AiProvider[]) {
        const profile = normalizedProfile(value.profiles[provider]);
        if (profile) settings.profiles[provider] = profile;
      }
      return settings;
    }
  } catch {
    // Try the single-profile format used by earlier builds.
  }

  const settings = defaultSettings();
  try {
    const legacy = JSON.parse(localStorage.getItem(LEGACY_CONFIG_STORAGE_KEY) ?? "null") as
      Partial<AiProviderConfig> | null;
    if (legacy && isProvider(legacy.provider)) {
      const profile = normalizedProfile(legacy);
      if (profile) {
        settings.activeProvider = legacy.provider;
        settings.profiles[legacy.provider] = profile;
      }
    }
  } catch {
    // Fall back to provider defaults when configuration is missing or stale.
  }
  return settings;
}

export function readAiProviderConfig(): AiProviderConfig {
  const settings = readSettings();
  return profileFromSettings(settings.activeProvider, settings);
}

function profileFromSettings(
  provider: AiProvider,
  settings: StoredAiProviderSettings,
): AiProviderConfig {
  const profile = settings.profiles[provider] ?? DEFAULT_AI_PROVIDER_CONFIGS[provider];
  return { provider, ...profile };
}

export function readAiProviderProfile(provider: AiProvider): AiProviderConfig {
  return profileFromSettings(provider, readSettings());
}

export function saveAiProviderConfig(config: AiProviderConfig) {
  const settings = readSettings();
  settings.activeProvider = config.provider;
  settings.profiles[config.provider] = {
    baseUrl: config.baseUrl.trim(),
    model: config.model.trim(),
    favoriteModels: normalizedFavorites(config.favoriteModels),
  };
  localStorage.setItem(
    CONFIG_STORAGE_KEY,
    JSON.stringify(settings),
  );
}
