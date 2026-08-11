import { afterEach, describe, expect, it, vi } from "vitest";
import { applyLogoForSidebar } from "./branding";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("applyLogoForSidebar", () => {
  it("updates app logo contrast without replacing the browser favicon", () => {
    const dataset: Record<string, string> = {};
    const querySelector = vi.fn();
    vi.stubGlobal("document", {
      documentElement: { dataset },
      querySelector,
    });

    applyLogoForSidebar("#1f1f23");

    expect(dataset.grimSidebarTone).toBe("dark");
    expect(querySelector).not.toHaveBeenCalled();
  });
});
