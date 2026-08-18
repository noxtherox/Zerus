export type MobileAIEngine = "local" | "cloud";

const ENGINE_KEY = "zerus.mobile-ai-engine.v1";

export function loadMobileAIEngine(storage: Pick<Storage, "getItem"> = localStorage): MobileAIEngine {
  return storage.getItem(ENGINE_KEY) === "cloud" ? "cloud" : "local";
}

export function saveMobileAIEngine(
  engine: MobileAIEngine,
  storage: Pick<Storage, "setItem"> = localStorage,
): void {
  storage.setItem(ENGINE_KEY, engine);
}

export function cloudEndpointLabel(endpoint: string): string {
  try {
    const host = new URL(endpoint).hostname.toLowerCase();
    return host === "openrouter.ai" ? "OpenRouter" : host;
  } catch {
    return "Cloud";
  }
}
