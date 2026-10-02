import type { VaultBackend } from "@/lib/vault/backend";

export const AI_CHAT_PREFERENCES_PATH = ".zerus/ai/chat-preferences.json";
const STORAGE_KEY = "zerus.ai.chat-preferences.v1";

export interface AiChatPreferences {
  version: 1;
  simpleMode: boolean;
}

function parsePreferences(text: string | null): AiChatPreferences | null {
  try {
    const value = JSON.parse(text ?? "null") as Partial<AiChatPreferences> | null;
    return value?.version === 1 && typeof value.simpleMode === "boolean"
      ? { version: 1, simpleMode: value.simpleMode }
      : null;
  } catch {
    return null;
  }
}

export function readLocalChatPreferences(): AiChatPreferences {
  return parsePreferences(localStorage.getItem(STORAGE_KEY)) ?? {
    version: 1,
    simpleMode: false,
  };
}

export function saveLocalChatPreferences(preferences: AiChatPreferences): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(preferences));
}

export async function readChatPreferences(backend: VaultBackend): Promise<AiChatPreferences | null> {
  if (!(await backend.exists(AI_CHAT_PREFERENCES_PATH))) return null;
  return parsePreferences(await backend.readText(AI_CHAT_PREFERENCES_PATH));
}

export async function writeChatPreferences(
  backend: VaultBackend,
  preferences: AiChatPreferences,
): Promise<void> {
  await backend.write(AI_CHAT_PREFERENCES_PATH, JSON.stringify(preferences, null, 2));
}
