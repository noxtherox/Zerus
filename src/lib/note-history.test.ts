import { describe, expect, it } from "vitest";
import {
  DEFAULT_HISTORY_SETTINGS,
  applyHistoryDelta,
  clearNoteHistory,
  createHistoryDelta,
  listNoteHistory,
  materializeHistoryImages,
  preserveCurrentZerusMetadata,
  recordNoteHistory,
  saveHistorySettings,
  updateHistoryVersion,
  type HistorySettings,
} from "./note-history";
import type { VaultBackend, VaultFile } from "./vault/backend";

class MemoryVault implements VaultBackend {
  readonly kind = "browser" as const;
  readonly location = "test";
  readonly text = new Map<string, string>();
  readonly binary = new Map<string, Uint8Array>();

  async loadAll(): Promise<VaultFile[]> { return []; }
  async readText(path: string) { const value = this.text.get(path); if (value === undefined) throw new Error("missing"); return value; }
  async listFiles(path: string) { const prefix = `${path.replace(/\/$/, "")}/`; return [...this.text.keys(), ...this.binary.keys()].filter((item) => item.startsWith(prefix)); }
  async write(path: string, content: string) { this.text.set(path, content); }
  async writeNew(path: string, content: string) { if (await this.exists(path)) throw new Error("exists"); this.text.set(path, content); }
  async move(from: string, to: string) { if (this.text.has(from)) { this.text.set(to, this.text.get(from)!); this.text.delete(from); } }
  async removeFile(path: string) { this.text.delete(path); this.binary.delete(path); }
  async exists(path: string) { return this.text.has(path) || this.binary.has(path); }
  async mkDir() {}
  async removeDir(path: string) { const prefix = `${path.replace(/\/$/, "")}/`; for (const key of [...this.text.keys()]) if (key.startsWith(prefix)) this.text.delete(key); for (const key of [...this.binary.keys()]) if (key.startsWith(prefix)) this.binary.delete(key); }
  async renameDir() {}
  async listDirs() { return []; }
  async writeBinary(path: string, bytes: Uint8Array) { this.binary.set(path, new Uint8Array(bytes)); }
  async readBinary(path: string) { const value = this.binary.get(path); if (!value) throw new Error("missing"); return new Uint8Array(value); }
}

const settings = (checkpointLimit: number | null = 10): HistorySettings => ({
  enabled: true,
  checkpointLimit,
});

async function record(vault: MemoryVault, before: string, after: string, originId = "device-a", checkpointLimit: number | null = 10) {
  await recordNoteHistory(vault, {
    noteId: "note-1",
    before,
    after,
    source: "desktop",
    originId,
    settings: settings(checkpointLimit),
  });
}

describe("note history", () => {
  it("creates reversible deltas for insertions, removals, and replacements", () => {
    for (const [before, after] of [
      ["hello world", "hello brave world"],
      ["one two three", "one three"],
      ["alpha\nbeta", "alpha\ngamma"],
      ["", "new"],
    ]) {
      expect(applyHistoryDelta(before, createHistoryDelta(before, after))).toBe(after);
    }
  });

  it("records a lazy baseline and reconstructs autosaves", async () => {
    const vault = new MemoryVault();
    await record(vault, "# Before", "# After");
    const versions = await listNoteHistory(vault, "note-1");
    expect(versions).toHaveLength(2);
    expect(versions.map((version) => version.content)).toEqual(["# After", "# Before"]);
    expect(versions[1].label).toBe("History started");
  });

  it("preserves concurrent branches instead of overwriting them", async () => {
    const vault = new MemoryVault();
    await record(vault, "base", "branch a", "device-a");
    await record(vault, "base", "branch b", "device-b");
    const versions = await listNoteHistory(vault, "note-1");
    expect(versions.map((version) => version.content)).toEqual(expect.arrayContaining(["branch a", "branch b", "base"]));
    expect(versions.some((version) => version.alternateBranch)).toBe(true);
  });

  it("creates full checkpoints and prunes to the configured checkpoint window", async () => {
    const vault = new MemoryVault();
    let before = "v0";
    for (let index = 1; index <= 101; index += 1) {
      const after = `v${index}`;
      await record(vault, before, after, "device-a", 1);
      before = after;
    }
    const versions = await listNoteHistory(vault, "note-1");
    expect(versions[0].content).toBe("v101");
    expect(versions.filter((version) => version.checkpoint)).toHaveLength(1);
    expect(versions.length).toBeLessThanOrEqual(50);
  });

  it("keeps protected versions when older history is pruned", async () => {
    const vault = new MemoryVault();
    let before = "v0";
    for (let index = 1; index <= 10; index += 1) {
      const after = `v${index}`;
      await record(vault, before, after, "device-a", null);
      before = after;
    }
    const old = (await listNoteHistory(vault, "note-1")).find((version) => version.content === "v3")!;
    await updateHistoryVersion(vault, "note-1", old.id, { kept: true, label: "Milestone" });
    for (let index = 11; index <= 101; index += 1) {
      const after = `v${index}`;
      await record(vault, before, after, "device-a", 1);
      before = after;
    }
    const versions = await listNoteHistory(vault, "note-1");
    expect(versions.find((version) => version.id === old.id)).toMatchObject({ kept: true, label: "Milestone", content: "v3" });
  });

  it("deduplicates local image bytes and restores changed images non-destructively", async () => {
    const vault = new MemoryVault();
    const original = new Uint8Array([1, 2, 3, 4]);
    vault.binary.set("assets/photo.png", original);
    await record(vault, "# Empty", "# Photo\n\n![Photo](assets/photo.png)");
    expect([...vault.binary.keys()].filter((path) => path.startsWith(".zerus/history/blobs/"))).toHaveLength(1);
    vault.binary.set("assets/photo.png", new Uint8Array([9, 9, 9]));
    const version = (await listNoteHistory(vault, "note-1"))[0];
    const restored = await materializeHistoryImages(vault, version);
    expect(restored).toMatch(/!\[Photo\]\(assets\/restored-/);
    const restoredPath = restored.match(/\((assets\/restored-[^)]+)\)/)?.[1];
    expect(restoredPath && [...vault.binary.get(restoredPath)!]).toEqual([1, 2, 3, 4]);
    expect([...vault.binary.get("assets/photo.png")!]).toEqual([9, 9, 9]);
  });

  it("preserves current reserved metadata during restoration", () => {
    const historical = "---\nzerus-id: old\nzerus-pinned: true\nzerus-future: old\ncolor: blue\n---\n# Old";
    const current = "---\nzerus-id: stable\nzerus-archived: true\nzerus-future: current\ncolor: red\n---\n# Current";
    const restored = preserveCurrentZerusMetadata(historical, current);
    expect(restored).toContain("zerus-id: stable");
    expect(restored).toContain("zerus-archived: true");
    expect(restored).not.toContain("zerus-pinned");
    expect(restored).toContain("zerus-future: current");
    expect(restored).toContain("color: blue");
  });

  it("supports synced settings and clearing a single note", async () => {
    const vault = new MemoryVault();
    expect(await saveHistorySettings(vault, { ...DEFAULT_HISTORY_SETTINGS, enabled: false, checkpointLimit: null })).toEqual({ enabled: false, checkpointLimit: null });
    await record(vault, "one", "two");
    await clearNoteHistory(vault, "note-1");
    expect(await listNoteHistory(vault, "note-1")).toEqual([]);
  });
});
