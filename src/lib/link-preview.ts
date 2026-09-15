const STORAGE_PREFIX = "zerus.linkPreview.v1.";

/** Bind the opt-in to the URL so editing a saved link does not load a new site automatically. */
export function loadLinkPreview(id: string, url: string): boolean {
  try {
    return localStorage.getItem(`${STORAGE_PREFIX}${id}`) === url;
  } catch {
    return false;
  }
}

export function saveLinkPreview(id: string, url: string, enabled: boolean): void {
  try {
    if (enabled) localStorage.setItem(`${STORAGE_PREFIX}${id}`, url);
    else localStorage.removeItem(`${STORAGE_PREFIX}${id}`);
  } catch {
    // The choice still applies this session if storage is unavailable.
  }
}
