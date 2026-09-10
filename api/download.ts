import { detectDownloadPlatform } from "../src/lib/download-platform.js";

type GitHubRelease = {
  html_url: string;
  assets: Array<{
    name: string;
    browser_download_url: string;
  }>;
};

type DownloadRequest = {
  method?: string;
  url?: string;
  headers?: Record<string, string | string[] | undefined>;
};

type DownloadResponse = {
  statusCode: number;
  setHeader(name: string, value: string): void;
  end(body?: string): void;
};

const LATEST_RELEASE_API =
  "https://api.github.com/repos/noxtherox/zerus/releases/latest";
const LATEST_RELEASE_PAGE =
  "https://github.com/noxtherox/zerus/releases/latest";

function redirect(response: DownloadResponse, location: string, cache: string) {
  response.statusCode = 307;
  response.setHeader("Location", location);
  response.setHeader("Cache-Control", cache);
  response.end();
}

export default async function handler(
  request: DownloadRequest,
  response: DownloadResponse,
) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    response.statusCode = 405;
    response.setHeader("Allow", "GET, HEAD");
    response.end("Method not allowed");
    return;
  }

  const requestedPlatform = new URL(request.url ?? "/api/download", "http://localhost")
    .searchParams.get("platform");
  const userAgent = request.headers?.["user-agent"];
  const platform = requestedPlatform === "windows" || requestedPlatform === "macos"
    ? requestedPlatform
    : detectDownloadPlatform({ userAgent: typeof userAgent === "string" ? userAgent : "" });

  // A shared cached redirect must never send another device the wrong installer.
  response.setHeader("Vary", "User-Agent");
  if (platform === "other") {
    redirect(response, LATEST_RELEASE_PAGE, "private, no-store");
    return;
  }

  try {
    const githubResponse = await fetch(LATEST_RELEASE_API, {
      headers: {
        Accept: "application/vnd.github+json",
        "User-Agent": "zerus-download-redirect",
        "X-GitHub-Api-Version": "2022-11-28",
      },
    });

    if (!githubResponse.ok) {
      throw new Error(`GitHub returned ${githubResponse.status}`);
    }

    const release = (await githubResponse.json()) as GitHubRelease;
    const installers = release.assets.filter((asset) =>
      asset.name.toLowerCase().endsWith(platform === "windows" ? ".exe" : ".dmg"),
    );
    const preferredInstaller = installers.find((asset) =>
      platform === "windows"
        ? /(?:x64|x86_64|amd64)/i.test(asset.name)
        : /(?:aarch64|arm64|apple[-_ ]?silicon)/i.test(asset.name),
    );
    const download = preferredInstaller ?? installers[0];

    redirect(
      response,
      download?.browser_download_url ?? release.html_url,
      "private, no-store",
    );
  } catch (error) {
    console.error("Could not resolve the latest Zerus download", error);
    redirect(
      response,
      LATEST_RELEASE_PAGE,
      "private, no-store",
    );
  }
}
