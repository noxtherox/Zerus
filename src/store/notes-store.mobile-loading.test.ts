import { afterEach, expect, it, vi } from "vitest";

const mobile = vi.hoisted(() => ({ restore: vi.fn(), cacheRead: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ isTauri: () => true, invoke: vi.fn() }));
vi.mock("@/lib/vault/mobile", () => ({
  MobileVault: class { static restore = mobile.restore; },
  MobileFolderVault: class {},
}));
vi.mock("@/lib/mobile-vault-picker", () => ({
  restoreMobileVaultFolder: async () => null,
}));

vi.mock("react", async (importOriginal) => ({
  ...await importOriginal<typeof import("react")>(),
  useSyncExternalStore: (_subscribe: unknown, snapshot: () => unknown) => snapshot(),
}));

vi.mock("@/lib/startup-cache", async (importOriginal) => ({
  ...await importOriginal<typeof import("@/lib/startup-cache")>(),
  readLargeStartupCache: mobile.cacheRead,
}));

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

it.each(["stalled", "slow"])("opens full notes with a %s large startup cache", async (cacheMode) => {
  vi.resetModules();
  const { useVault, getNotes, initStore, prioritizeNoteLoad, synchronizeMobileFiles, updateNoteBody } = await import("./notes-store");
  const largeCache = deferred<unknown>();
  mobile.cacheRead.mockReturnValue(largeCache.promise);
  vi.useFakeTimers();
  const path = "Work/Story.md";
  const content = "# Story\n\n" + "Complete note content. ".repeat(20) + "\n\nFinal paragraph.";
  const updatedAt = new Date(0).toISOString();
  const entries = deferred<Array<{ path: string; updatedAt: string }>>();
  const body = deferred<Array<{ path: string; content: string; updatedAt: string }>>();
  const loadFiles = vi.fn(() => body.promise);
  const listNoteEntries = vi.fn(() => entries.promise);
  mobile.restore.mockResolvedValue({
    kind: "mobile", location: "test-mobile", loadFiles, listNoteEntries,
    listFiles: async () => [], listDirs: async () => [],
    readText: async () => { throw new Error("No metadata"); },
  });
  const storage = new Map([["zerus.startupCache.v1.test-mobile", JSON.stringify({
    version: 1, location: "test-mobile", notes: [{
      id: "story", path, title: "Story", snippet: "Complete note content. ".repeat(6).slice(0, 120),
      updatedAt, pinned: false, content: "# Story\n\nTruncated legacy body",
    }], extraTypes: [], schemas: {}, typeIcons: {}, fileLocations: [],
  })]]);
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => storage.get(key) ?? null,
    setItem: (key: string, value: string) => storage.set(key, value),
    removeItem: (key: string) => storage.delete(key),
  });
  vi.stubGlobal("navigator", { userAgent: "iPhone" });
  vi.stubGlobal("window", { addEventListener: vi.fn() });
  vi.stubGlobal("document", { addEventListener: vi.fn() });
  vi.stubGlobal("indexedDB", { open: () => ({}) });
  initStore();
  await vi.advanceTimersByTimeAsync(1_500);
  for (let i = 0; i < 100 && !getNotes().length; i++) await Promise.resolve();
  expect(getNotes()[0].content).not.toContain("Final paragraph.");
  expect(getNotes()[0].content).not.toContain("Truncated legacy body");
  updateNoteBody("story", "# Story\n\nPartial edit must not replace the file.");
  expect(getNotes()[0].content).not.toContain("Partial edit");
  const callsBeforeSync = listNoteEntries.mock.calls.length;
  await synchronizeMobileFiles();
  expect(listNoteEntries).toHaveBeenCalledTimes(callsBeforeSync);
  if (cacheMode === "slow") {
    largeCache.resolve({
      ...JSON.parse(storage.get("zerus.startupCache.v1.test-mobile")!),
      version: 2,
      notes: [{ id: "story", path, title: "Story", snippet: "", updatedAt, content }],
    });
    for (let i = 0; i < 20; i++) await Promise.resolve();
    expect(getNotes()[0].content).toBe(content);
    expect(useVault().loadingNoteIds.has("story")).toBe(false);
    await prioritizeNoteLoad("story");
    expect(loadFiles).not.toHaveBeenCalled();
    return;
  }
  const first = prioritizeNoteLoad("story");
  const second = prioritizeNoteLoad("story");
  expect(first).toBe(second);
  expect(loadFiles).toHaveBeenCalledExactlyOnceWith([path]);
  body.resolve([{ path, content, updatedAt }]);
  await first;
  expect(getNotes()[0].content).toBe(content);
  const saved = JSON.parse(storage.get("zerus.startupCache.v1.test-mobile")!);
  expect(saved.notes[0].content).toBe(content);
  expect(saved.version).toBe(2);
  await prioritizeNoteLoad("story");
  expect(loadFiles).toHaveBeenCalledTimes(1);
  // A stalled scan keeps the last usable cache, and its late completion must
  // not replace the content that was loaded on demand.
  await vi.advanceTimersByTimeAsync(60_000);
  expect(useVault().status).toBe("ready");
  expect(useVault().isRefreshing).toBe(false);
  expect(useVault().loadingNoteIds.has("story")).toBe(false);
  expect(getNotes()[0].content).toBe(content);
  entries.resolve([{ path, updatedAt }]);
  for (let i = 0; i < 20; i++) await Promise.resolve();
  expect(useVault().status).toBe("ready");
  expect(getNotes()[0].content).toBe(content);
});
