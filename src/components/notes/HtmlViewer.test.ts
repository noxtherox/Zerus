import { describe, expect, it } from "vitest";
import {
  analyzeHtmlPreview,
  htmlPreviewFingerprint,
  htmlPreviewNeedsPermission,
  prepareFullHtmlPreview,
  prepareHtmlPreview,
} from "@/lib/html-preview";

describe("HTML file preview", () => {
  it("injects the restrictive policy into an existing head", () => {
    const html = prepareHtmlPreview("<!doctype html><html><head><title>Report</title></head><body>Done</body></html>");

    expect(html).toContain('<head><meta http-equiv="Content-Security-Policy"');
    expect(html).toContain("default-src 'none'");
    expect(html).toContain("<title>Report</title>");
  });

  it("adds a head when a self-contained fragment does not provide one", () => {
    const html = prepareHtmlPreview("<main>Hello</main>");

    expect(html).toMatch(/^<head><meta http-equiv="Content-Security-Policy"/);
    expect(html).toContain("<main>Hello</main>");
  });

  it("detects executable scripts and their external domains", () => {
    const analysis = analyzeHtmlPreview(`
      <script src="https://cdn.example.com/react.js"></script>
      <script>fetch("https://api.example.com/data")</script>
      <img src="data:image/png;base64,abc">
    `);

    expect(analysis.hasScripts).toBe(true);
    expect(analysis.externalScriptUrls).toEqual(["https://cdn.example.com/react.js"]);
    expect(analysis.domains).toEqual(["api.example.com", "cdn.example.com"]);
    expect(analysis.origins).toEqual(["https://api.example.com", "https://cdn.example.com"]);
    expect(htmlPreviewNeedsPermission(analysis)).toBe(true);
  });

  it("limits full preview networking to detected origins", () => {
    const source = '<script src="https://cdn.example.com/tool.js"></script>';
    const html = prepareFullHtmlPreview(source);

    expect(html).toContain("script-src 'unsafe-inline' 'unsafe-eval' blob: https://cdn.example.com");
    expect(html).toContain("connect-src https://cdn.example.com");
    expect(html).toContain("form-action 'none'");
    expect(html).toContain("object-src 'none'");
  });

  it("removes meta refresh from safe previews", () => {
    const html = prepareHtmlPreview('<meta http-equiv="refresh" content="0; url=https://evil.example">Safe');

    expect(html).not.toContain("evil.example");
    expect(html).toContain("Safe");
  });

  it("fingerprints the exact file bytes", async () => {
    const bytes = new TextEncoder().encode("approved HTML");

    expect(await htmlPreviewFingerprint(bytes)).toBe(
      "e2a50c7c3b11e43a4d814d4b1c261908c5681784ad4558944c4aa8be07c39435",
    );
  });

  it("does not flag static self-contained HTML", () => {
    const analysis = analyzeHtmlPreview(
      "<html><style>body { color: red }</style><body><img src='data:image/png;base64,abc'></body></html>",
    );

    expect(analysis).toMatchObject({ hasScripts: false, externalUrls: [] });
    expect(htmlPreviewNeedsPermission(analysis)).toBe(false);
  });

  it("ignores non-executable structured-data scripts", () => {
    const analysis = analyzeHtmlPreview(
      '<script type="application/ld+json">{"name":"Report"}</script>',
    );

    expect(analysis.hasScripts).toBe(false);
  });
});
