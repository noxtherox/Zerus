import { afterEach, describe, expect, it, vi } from "vitest";
import { detectDownloadPlatform, getDownloadOption } from "./download-platform";
import handler from "../../api/download";

afterEach(() => vi.unstubAllGlobals());

describe("device downloads", () => {
  it.each([
    [{ userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" }, "windows"],
    [{ userAgentData: { platform: "Windows" } }, "windows"],
    [{ userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" }, "macos"],
    [{ userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)" }, "other"],
    [{ userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", platform: "MacIntel", maxTouchPoints: 5 }, "other"],
    [{ userAgent: "Mozilla/5.0 (Linux; Android 15)" }, "other"],
    [{ userAgent: "Mozilla/5.0 (X11; Linux x86_64)" }, "other"],
    [{}, "other"],
  ] as const)("detects %j as %s", (device, expected) => {
    expect(detectDownloadPlatform(device)).toBe(expected);
  });

  const assets = [
    { name: "Zerus_aarch64.dmg", browser_download_url: "https://example.com/mac.dmg" },
    { name: "Zerus_x64-setup.exe", browser_download_url: "https://example.com/windows.exe" },
    { name: "Zerus_x64-setup.exe.sig", browser_download_url: "https://example.com/windows.exe.sig" },
  ];

  function response() {
    const headers: Record<string, string> = {};
    return { statusCode: 200, headers, setHeader: (key: string, value: string) => { headers[key] = value; }, end: vi.fn() };
  }

  it.each(["windows", "macos"] as const)("routes the %s button to its matching installer", async (platform) => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ assets, html_url: "https://example.com/releases" }) }));
    const res = response();
    await handler({ method: "GET", url: getDownloadOption(platform).href }, res);
    expect(res.statusCode).toBe(307);
    expect(res.headers.Location).toBe(platform === "windows" ? assets[1].browser_download_url : assets[0].browser_download_url);
    expect(res.headers["Cache-Control"]).toBe("private, no-store");
  });

  it("detects Windows for direct endpoint visits", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ assets, html_url: "https://example.com/releases" }) }));
    const res = response();
    await handler({ method: "HEAD", headers: { "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" } }, res);
    expect(res.headers.Location).toBe(assets[1].browser_download_url);
  });

  it("falls back to the release page when a Windows installer is missing", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true, json: async () => ({ assets: [assets[0]], html_url: "https://example.com/releases" }) }));
    const res = response();
    await handler({ method: "GET", url: getDownloadOption("windows").href }, res);
    expect(res.headers.Location).toBe("https://example.com/releases");
  });

  it("does not offer desktop installers to mobile devices", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const res = response();
    await handler({ method: "GET", headers: { "user-agent": "iPhone; CPU iPhone OS like Mac OS X" } }, res);
    expect(res.headers.Location).toBe(getDownloadOption("other").href);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
