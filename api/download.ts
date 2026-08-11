type GitHubRelease = {
  html_url: string;
  assets: Array<{
    name: string;
    browser_download_url: string;
  }>;
};

type DownloadRequest = {
  method?: string;
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
    const diskImages = release.assets.filter((asset) =>
      asset.name.toLowerCase().endsWith(".dmg"),
    );
    const appleSiliconImage = diskImages.find((asset) =>
      /(?:aarch64|arm64|apple[-_ ]?silicon)/i.test(asset.name),
    );
    const download = appleSiliconImage ?? diskImages[0];

    redirect(
      response,
      download?.browser_download_url ?? release.html_url,
      "public, s-maxage=300, stale-while-revalidate=86400",
    );
  } catch (error) {
    console.error("Could not resolve the latest Zerus download", error);
    redirect(
      response,
      LATEST_RELEASE_PAGE,
      "public, s-maxage=60, stale-while-revalidate=300",
    );
  }
}
