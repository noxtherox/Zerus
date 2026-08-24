import { describe, expect, it, vi } from "vitest";
import { ImageUrlCache } from "./image-url-cache";

describe("ImageUrlCache", () => {
  it("reuses a URL for the same vault path", async () => {
    const load = vi.fn(async () => "blob:first");
    const cache = new ImageUrlCache();

    await expect(cache.get("assets/a.png", load)).resolves.toBe("blob:first");
    await expect(cache.get("assets/a.png", load)).resolves.toBe("blob:first");
    expect(load).toHaveBeenCalledTimes(1);
  });

  it("invalidates only the changed image", async () => {
    const revoke = vi.fn();
    const cache = new ImageUrlCache(revoke);
    await cache.get("assets/a.png", async () => "blob:a");
    await cache.get("assets/b.png", async () => "blob:b");

    cache.invalidate("assets/a.png");
    await Promise.resolve();

    expect(revoke).toHaveBeenCalledWith("blob:a");
    expect(revoke).not.toHaveBeenCalledWith("blob:b");
    await expect(
      cache.get("assets/b.png", async () => "blob:replacement"),
    ).resolves.toBe("blob:b");
  });

  it("does not expose a blob URL that resolves after invalidation", async () => {
    let resolve!: (url: string) => void;
    const pending = new Promise<string>((done) => {
      resolve = done;
    });
    const revoke = vi.fn();
    const cache = new ImageUrlCache(revoke);
    const result = cache.get("assets/a.png", () => pending);

    cache.invalidate("assets/a.png");
    resolve("blob:late");

    await expect(result).resolves.toBeNull();
    expect(revoke).toHaveBeenCalledWith("blob:late");
  });
});
