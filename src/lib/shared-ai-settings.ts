import {
  DEFAULT_AI_PROVIDER_CONFIGS,
  type AiProvider,
  type AiProviderConfig,
} from "@/lib/ai-provider-config";
import type { VaultBackend } from "@/lib/vault/backend";

export const SHARED_AI_SETTINGS_PATH = ".zerus/ai-settings.json";

export interface SharedAiSettings {
  version: 1;
  activeProvider: AiProvider;
  profiles: Partial<Record<AiProvider, Omit<AiProviderConfig, "provider">>>;
  updatedAt: string;
}

function isProvider(value: unknown): value is AiProvider {
  return value === "codex" || value === "openai" || value === "anthropic" ||
    value === "openrouter" || value === "compatible";
}

function normalizeProfile(provider: AiProvider, value: unknown): AiProviderConfig | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Partial<Omit<AiProviderConfig, "provider">>;
  if (typeof candidate.baseUrl !== "string" || typeof candidate.model !== "string") return null;
  return {
    provider,
    baseUrl: candidate.baseUrl.trim(),
    model: candidate.model.trim(),
    favoriteModels: Array.isArray(candidate.favoriteModels)
      ? [...new Set(candidate.favoriteModels.filter((model): model is string =>
        typeof model === "string" && Boolean(model.trim())).map((model) => model.trim()))].slice(0, 50)
      : [],
  };
}

export async function readSharedAiSettings(
  backend: VaultBackend,
): Promise<{ active: AiProviderConfig; settings: SharedAiSettings } | null> {
  try {
    const value = JSON.parse(await backend.readText(SHARED_AI_SETTINGS_PATH)) as Partial<SharedAiSettings>;
    if (value.version !== 1 || !isProvider(value.activeProvider) || !value.profiles) return null;
    const profiles: SharedAiSettings["profiles"] = {};
    for (const provider of Object.keys(DEFAULT_AI_PROVIDER_CONFIGS) as AiProvider[]) {
      const profile = normalizeProfile(provider, value.profiles[provider]);
      if (profile) profiles[provider] = {
        baseUrl: profile.baseUrl,
        model: profile.model,
        favoriteModels: profile.favoriteModels,
      };
    }
    const active = normalizeProfile(value.activeProvider, profiles[value.activeProvider]) ??
      DEFAULT_AI_PROVIDER_CONFIGS[value.activeProvider];
    return {
      active,
      settings: {
        version: 1,
        activeProvider: value.activeProvider,
        profiles,
        updatedAt: typeof value.updatedAt === "string" ? value.updatedAt : new Date(0).toISOString(),
      },
    };
  } catch {
    return null;
  }
}

export async function writeSharedAiSettings(
  backend: VaultBackend,
  config: AiProviderConfig,
): Promise<void> {
  const current = await readSharedAiSettings(backend);
  const profiles = current?.settings.profiles ?? {};
  profiles[config.provider] = {
    baseUrl: config.baseUrl.trim(),
    model: config.model.trim(),
    favoriteModels: [...new Set(config.favoriteModels.map((model) => model.trim()).filter(Boolean))],
  };
  const settings: SharedAiSettings = {
    version: 1,
    activeProvider: config.provider,
    profiles,
    updatedAt: new Date().toISOString(),
  };
  await backend.write(SHARED_AI_SETTINGS_PATH, JSON.stringify(settings, null, 2));
}
