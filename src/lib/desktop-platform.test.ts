import { describe, expect, it } from "vitest";
import { detectDesktopPlatform } from "./desktop-platform";

describe("desktop platform helpers", () => {
  it("recognizes the supported desktop platforms", () => {
    expect(detectDesktopPlatform("Mozilla/5.0 (Windows NT 10.0; Win64; x64)")).toBe(
      "windows",
    );
    expect(detectDesktopPlatform("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")).toBe(
      "macos",
    );
    expect(detectDesktopPlatform("Mozilla/5.0 (X11; Linux x86_64)")).toBe(
      "linux",
    );
  });

});
