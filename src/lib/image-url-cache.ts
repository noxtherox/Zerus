interface CachedImageUrl {
  invalidated: boolean;
  promise: Promise<string | null>;
}

type RevokeUrl = (url: string) => void;

/**
 * Owns blob URLs by vault path so a changed image can be invalidated without
 * blanking every image currently mounted in the app.
 */
export class ImageUrlCache {
  private readonly entries = new Map<string, CachedImageUrl>();
  private readonly pathsByUrl = new Map<string, string>();

  constructor(private readonly revokeUrl: RevokeUrl = URL.revokeObjectURL) {}

  get(
    path: string,
    load: () => Promise<string | null>,
  ): Promise<string | null> {
    const existing = this.entries.get(path);
    if (existing) return existing.promise;

    const entry: CachedImageUrl = {
      invalidated: false,
      promise: Promise.resolve(null),
    };
    entry.promise = load().then((url) => {
      if (entry.invalidated && url?.startsWith("blob:")) {
        this.revokeUrl(url);
        return null;
      }
      if (url) this.pathsByUrl.set(url, path);
      return url;
    });
    this.entries.set(path, entry);
    return entry.promise;
  }

  invalidate(path: string): void {
    const entry = this.entries.get(path);
    if (!entry) return;
    this.entries.delete(path);
    entry.invalidated = true;
    void entry.promise.then((url) => {
      if (url) this.pathsByUrl.delete(url);
      if (url?.startsWith("blob:")) this.revokeUrl(url);
    });
  }

  /** Recovers the durable vault reference when a rendered image is copied. */
  pathForUrl(url: string): string | null {
    return this.pathsByUrl.get(url) ?? null;
  }

  clear(): void {
    for (const path of [...this.entries.keys()]) this.invalidate(path);
  }
}
