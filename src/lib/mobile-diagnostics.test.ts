import { beforeEach, describe, expect, it } from "vitest";
import {
  clearMobileDiagnostics,
  getMobileDiagnostics,
  mobileDiagnostic,
} from "./mobile-diagnostics";

describe("mobile diagnostics", () => {
  beforeEach(() => {
    const values = new Map<string, string>();
    Object.defineProperty(globalThis, "localStorage", {
      configurable: true,
      value: {
        getItem: (key: string) => values.get(key) ?? null,
        setItem: (key: string, value: string) => values.set(key, value),
        removeItem: (key: string) => values.delete(key),
      },
    });
    clearMobileDiagnostics();
  });

  it("records useful events without exposing device file paths", () => {
    mobileDiagnostic("vault.read.failed", {
      error: new Error(
        "denied file:///private/var/mobile/Library/Mobile Documents/secret.md",
      ),
    });

    const report = getMobileDiagnostics();
    expect(report).toContain("vault.read.failed");
    expect(report).toContain("denied file://…");
    expect(report).not.toContain("secret.md");
  });

  it("can clear collected events", () => {
    mobileDiagnostic("picker.invoke.started");
    clearMobileDiagnostics();
    expect(getMobileDiagnostics()).toContain("No diagnostic events yet.");
  });
});
