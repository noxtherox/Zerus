import { describe, expect, it } from "vitest";
import { cloudEndpointLabel, loadMobileAIEngine, saveMobileAIEngine } from "./mobile-ai-engine";

describe("mobile AI engine preferences", () => {
  it("defaults malformed and missing preferences to local AI", () => {
    expect(loadMobileAIEngine({ getItem: () => null })).toBe("local");
    expect(loadMobileAIEngine({ getItem: () => "remote" })).toBe("local");
  });

  it("persists cloud selection", () => {
    let value = "";
    saveMobileAIEngine("cloud", { setItem: (_key, next) => { value = next; } });
    expect(value).toBe("cloud");
    expect(loadMobileAIEngine({ getItem: () => value })).toBe("cloud");
  });

  it("uses a friendly OpenRouter endpoint label", () => {
    expect(cloudEndpointLabel("https://openrouter.ai/api/v1")).toBe("OpenRouter");
    expect(cloudEndpointLabel("https://ai.example.com/v1")).toBe("ai.example.com");
  });
});
