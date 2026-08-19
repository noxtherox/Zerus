import { describe, expect, it } from "vitest";
import { cloudEndpointLabel } from "./mobile-cloud-ai";

describe("cloudEndpointLabel", () => {
  it("uses a friendly OpenRouter label", () => {
    expect(cloudEndpointLabel("https://openrouter.ai/api/v1")).toBe(
      "OpenRouter",
    );
  });

  it("falls back safely for custom and invalid endpoints", () => {
    expect(cloudEndpointLabel("https://ai.example.com/v1")).toBe(
      "ai.example.com",
    );
    expect(cloudEndpointLabel("not a URL")).toBe("Cloud");
  });
});
