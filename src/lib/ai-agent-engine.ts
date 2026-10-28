export type AiAgentEngine = "ai-sdk" | "pi";

const STORAGE_KEY = "zerus.ai.desktop-agent-engine.v1";

export function readDesktopAgentEngine(): AiAgentEngine {
  try {
    return localStorage.getItem(STORAGE_KEY) === "pi" ? "pi" : "ai-sdk";
  } catch {
    return "ai-sdk";
  }
}

export function saveDesktopAgentEngine(engine: AiAgentEngine): void {
  localStorage.setItem(STORAGE_KEY, engine);
}
