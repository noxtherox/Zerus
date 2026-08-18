import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { describe, expect, it, vi } from "vitest";

vi.mock("@tauri-apps/plugin-fs", async () => {
  const fs = await import("node:fs/promises");
  return {
    exists: async (path: string | URL) =>
      fs.access(path).then(() => true).catch(() => false),
    mkdir: (path: string | URL, options?: { recursive?: boolean }) =>
      fs.mkdir(path, options),
    readDir: async (path: string | URL) =>
      (await fs.readdir(path, { withFileTypes: true })).map((entry) => ({
        name: entry.name,
        isDirectory: entry.isDirectory(),
        isFile: entry.isFile(),
      })),
    readFile: async (path: string | URL) => new Uint8Array(await fs.readFile(path)),
    readTextFile: (path: string | URL) => fs.readFile(path, "utf8"),
    remove: (path: string | URL, options?: { recursive?: boolean }) =>
      fs.rm(path, { force: true, recursive: options?.recursive ?? false }),
    rename: (from: string | URL, to: string | URL) => fs.rename(from, to),
    stat: async (path: string | URL) => {
      const info = await fs.stat(path);
      return { mtime: info.mtime };
    },
    writeFile: (path: string | URL, bytes: Uint8Array) => fs.writeFile(path, bytes),
    writeTextFile: (path: string | URL, content: string) => fs.writeFile(path, content),
  };
});

import { MobileFolderVault } from "./mobile";

describe("MobileFolderVault discovery", () => {
  it("opens a custom-named existing vault without adding metadata", async () => {
    const root = await mkdtemp(join(tmpdir(), "zerus-mobile-vault-"));
    const notePath = join(root, "Ideas", "Existing.md");
    await mkdir(join(root, "Ideas"), { recursive: true });
    await writeFile(notePath, "# Existing vault\n", "utf8");

    const vault = await MobileFolderVault.locate(pathToFileURL(root).href, "My Notes");

    expect(vault).not.toBeNull();
    expect(vault?.location).toBe("My Notes");
    expect(vault?.absolutePath("Ideas/Existing.md")).toBe(notePath);
    expect((await vault?.loadAll())?.map((file) => file.path)).toEqual([
      "Ideas/Existing.md",
    ]);
    await expect(readFile(join(root, ".zerus", "mobile-vault-v1"))).rejects.toThrow();
  });

  it("finds a Zerus vault inside the selected iCloud parent folder", async () => {
    const root = await mkdtemp(join(tmpdir(), "zerus-mobile-parent-"));
    const vaultRoot = join(root, "Zerus");
    await mkdir(join(vaultRoot, "Journal"), { recursive: true });
    await writeFile(join(vaultRoot, "Journal", "Today.md"), "# Today\n", "utf8");

    const vault = await MobileFolderVault.locate(pathToFileURL(root).href, "iCloud Drive");

    expect(vault?.location).toBe("Zerus");
    expect((await vault?.loadAll())?.map((file) => file.path)).toEqual([
      "Journal/Today.md",
    ]);
  });

  it("indexes every note while loading content only for the requested page", async () => {
    const root = await mkdtemp(join(tmpdir(), "grimoire-mobile-page-"));
    await mkdir(join(root, "Ideas"), { recursive: true });
    await writeFile(join(root, "Ideas", "Older.md"), "# Older\n", "utf8");
    await new Promise((resolve) => setTimeout(resolve, 5));
    await writeFile(join(root, "Ideas", "Newest.md"), "# Newest\n", "utf8");

    const vault = new MobileFolderVault(pathToFileURL(root).href, "Grimoire");
    const entries = await vault.listNoteEntries();

    expect(entries.map((entry) => entry.path).sort()).toEqual([
      "Ideas/Newest.md",
      "Ideas/Older.md",
    ]);
    const files = await vault.loadFiles(["Ideas/Newest.md"]);
    expect(files).toEqual([
      expect.objectContaining({ path: "Ideas/Newest.md", content: "# Newest\n" }),
    ]);
  });
});
