export const MAX_HTML_PREVIEW_BYTES = 10 * 1024 * 1024;

const SAFE_PREVIEW_CSP = [
  "default-src 'none'",
  "img-src data: blob:",
  "media-src data: blob:",
  "style-src 'unsafe-inline'",
  "font-src data:",
  "base-uri 'none'",
  "form-action 'none'",
].join("; ");

export interface HtmlPreviewAnalysis {
  hasScripts: boolean;
  externalUrls: string[];
  externalScriptUrls: string[];
  domains: string[];
  origins: string[];
}

function attributeValue(attributes: string, name: string): string | null {
  const match = attributes.match(
    new RegExp(`\\b${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, "i"),
  );
  return match?.[1] ?? match?.[2] ?? match?.[3] ?? null;
}

function externalUrl(value: string): string | null {
  const trimmed = value.trim();
  if (/^https?:\/\//i.test(trimmed)) return trimmed;
  if (trimmed.startsWith("//")) return `https:${trimmed}`;
  return null;
}

function addExternalUrl(target: Set<string>, value: string | null): void {
  const url = value ? externalUrl(value) : null;
  if (url) target.add(url);
}

/** Detects executable HTML and statically discoverable remote dependencies. */
export function analyzeHtmlPreview(source: string): HtmlPreviewAnalysis {
  const externalUrls = new Set<string>();
  const externalScriptUrls = new Set<string>();
  let hasScripts = false;

  for (const match of source.matchAll(/<script\b([^>]*)>/gi)) {
    const attributes = match[1] ?? "";
    const type = attributeValue(attributes, "type")?.toLowerCase();
    const executable = !type || !["application/json", "application/ld+json"].includes(type);
    if (!executable) continue;
    hasScripts = true;
    const src = attributeValue(attributes, "src");
    const url = src ? externalUrl(src) : null;
    if (url) {
      externalUrls.add(url);
      externalScriptUrls.add(url);
    }
  }

  const resourceTag = /<(?:img|iframe|embed|source|video|audio|input)\b([^>]*)>/gi;
  for (const match of source.matchAll(resourceTag)) {
    const attributes = match[1] ?? "";
    addExternalUrl(externalUrls, attributeValue(attributes, "src"));
    addExternalUrl(externalUrls, attributeValue(attributes, "poster"));
    const srcset = attributeValue(attributes, "srcset");
    if (srcset) {
      for (const candidate of srcset.split(",")) {
        addExternalUrl(externalUrls, candidate.trim().split(/\s+/)[0] ?? null);
      }
    }
  }
  for (const match of source.matchAll(/<link\b([^>]*)>/gi)) {
    addExternalUrl(externalUrls, attributeValue(match[1] ?? "", "href"));
  }
  for (const match of source.matchAll(/<object\b([^>]*)>/gi)) {
    addExternalUrl(externalUrls, attributeValue(match[1] ?? "", "data"));
  }
  for (const match of source.matchAll(/(?:url\(|@import\s+)(?:\s*["']?)(https?:\/\/|\/\/)([^\s"')]+)["']?\s*\)?/gi)) {
    addExternalUrl(externalUrls, `${match[1]}${match[2]}`);
  }
  for (const match of source.matchAll(/\b(?:fetch|EventSource|WebSocket)\s*\(\s*["'](https?:\/\/|\/\/)([^"']+)/gi)) {
    addExternalUrl(externalUrls, `${match[1]}${match[2]}`);
  }
  if (/\bon[a-z]+\s*=/i.test(source) || /javascript\s*:/i.test(source)) {
    hasScripts = true;
  }

  const urls = [...externalUrls];
  const domains = [...new Set(urls.flatMap((value) => {
    try {
      return [new URL(value).hostname];
    } catch {
      return [];
    }
  }))].sort();
  const origins = [...new Set(urls.flatMap((value) => {
    try {
      return [new URL(value).origin];
    } catch {
      return [];
    }
  }))].sort();
  return {
    hasScripts,
    externalUrls: urls,
    externalScriptUrls: [...externalScriptUrls],
    domains,
    origins,
  };
}

export function htmlPreviewNeedsPermission(analysis: HtmlPreviewAnalysis): boolean {
  return analysis.hasScripts || analysis.externalUrls.length > 0;
}

/** Adds a restrictive policy without otherwise rewriting the attached document. */
function injectPolicy(source: string, policy: string): string {
  // Target-only base elements keep ordinary links from replacing the preview.
  // Popups are not granted by the iframe sandbox, so those link navigations fail closed.
  const policyTag = `<meta http-equiv="Content-Security-Policy" content="${policy}"><base target="_blank">`;
  const head = /<head(?:\s[^>]*)?>/i;
  if (head.test(source)) return source.replace(head, (match) => `${match}${policyTag}`);

  const doctype = /<!doctype[^>]*>/i;
  if (doctype.test(source)) {
    return source.replace(doctype, (match) => `${match}<head>${policyTag}</head>`);
  }
  return `<head>${policyTag}</head>${source}`;
}

/** Adds a restrictive policy and removes declarative redirects. */
export function prepareHtmlPreview(source: string): string {
  const withoutRefresh = source.replace(
    /<meta\b(?=[^>]*\bhttp-equiv\s*=\s*(?:["']?refresh["']?))[^>]*>/gi,
    "",
  );
  return injectPolicy(withoutRefresh, SAFE_PREVIEW_CSP);
}

/** Allows active content to contact only origins discovered in the approved file. */
export function prepareFullHtmlPreview(
  source: string,
  analysis = analyzeHtmlPreview(source),
): string {
  const origins = analysis.origins.join(" ");
  const withOrigins = (base: string) => origins ? `${base} ${origins}` : base;
  const policy = [
    "default-src 'none'",
    withOrigins("script-src 'unsafe-inline' 'unsafe-eval' blob:"),
    withOrigins("connect-src"),
    withOrigins("img-src data: blob:"),
    withOrigins("media-src data: blob:"),
    withOrigins("style-src 'unsafe-inline'"),
    withOrigins("font-src data:"),
    withOrigins("frame-src"),
    withOrigins("worker-src blob:"),
    origins ? `navigate-to ${origins}` : "navigate-to 'none'",
    "object-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
  ].join("; ");
  return injectPolicy(source, policy);
}

export async function htmlPreviewFingerprint(bytes: Uint8Array): Promise<string> {
  const stableBytes = new Uint8Array(bytes.byteLength);
  stableBytes.set(bytes);
  const digest = await crypto.subtle.digest("SHA-256", stableBytes);
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}
