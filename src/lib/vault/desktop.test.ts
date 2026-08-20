import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";

const readState = vi.hoisted(() => ({ active: 0, maxActive: 0, dirs: 0 }));

vi.mock("@tauri-apps/plugin-fs", async () => {
  const fs = await import("node:fs/promises");
  return {
    exists: async (path: string) =>
      fs.access(path).then(() => true).catch(() => false),
    mkdir: (path: string, options?: { recursive?: boolean }) =>
      fs.mkdir(path, options),
    readDir: async (path: string) => {
      readState.dirs += 1;
      return (await fs.readdir(path, { withFileTypes: true })).map((entry) => ({
        name: entry.name,
        isDirectory: entry.isDirectory(),
        isFile: entry.isFile(),
      }));
    },
    readFile: async (path: string) => new Uint8Array(await fs.readFile(path)),
    readTextFile: async (path: string) => {
      readState.active += 1;
      readState.maxActive = Math.max(readState.maxActive, readState.active);
      await new Promise((resolve) => setTimeout(resolve, 5));
      try {
        return await fs.readFile(path, "utf8");
      } finally {
        readState.active -= 1;
      }
    },
    remove: (path: string, options?: { recursive?: boolean }) =>
      fs.rm(path, { force: true, recursive: options?.recursive ?? false }),
    rename: (from: string, to: string) => fs.rename(from, to),
    stat: async (path: string) => {
      const info = await fs.stat(path);
      return { mtime: info.mtime };
    },
    writeFile: (path: string, bytes: Uint8Array) => fs.writeFile(path, bytes),
    writeTextFile: (path: string, content: string) => fs.writeFile(path, content),
  };
});

vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));

import { DesktopVault } from "./desktop";

describe("DesktopVault startup loading", () => {
  it("loads notes concurrently while preserving vault discovery rules", async () => {
    const root = await mkdtemp(join(tmpdir(), "zerus-desktop-vault-"));
    await Promise.all([
      mkdir(join(root, "Notes"), { recursive: true }),
      mkdir(join(root, "Projects", "Active"), { recursive: true }),
      mkdir(join(root, "Areas", "Work", "Clients", "Acme", "Projects"), {
        recursive: true,
      }),
      mkdir(join(root, ".hidden"), { recursive: true }),
      mkdir(join(root, ".trash", "Notes"), { recursive: true }),
    ]);
    await Promise.all([
      writeFile(join(root, "Notes", "One.md"), "# One\n"),
      writeFile(join(root, "Notes", "Two.md"), "# Two\n"),
      writeFile(join(root, "Projects", "Active", "Three.md"), "# Three\n"),
      writeFile(
        join(root, "Areas", "Work", "Clients", "Acme", "Projects", "Deep.md"),
        "# Deep\n",
      ),
      writeFile(join(root, ".hidden", "Ignored.md"), "# Ignored\n"),
      writeFile(join(root, ".trash", "Notes", "Deleted.md"), "# Deleted\n"),
    ]);

    readState.active = 0;
    readState.maxActive = 0;
    readState.dirs = 0;
    const vault = new DesktopVault(root);
    const priorityLoaded: string[] = [];
    const [files, dirs] = await Promise.all([
      vault.loadAll({
        priorityPaths: ["Notes/Two.md"],
        onPriorityLoaded: (loaded) =>
          priorityLoaded.push(...loaded.map((file) => file.path)),
      }),
      vault.listDirs(),
    ]);

    expect(files.map((file) => file.path)).toEqual([
      ".trash/Notes/Deleted.md",
      "Areas/Work/Clients/Acme/Projects/Deep.md",
      "Notes/One.md",
      "Notes/Two.md",
      "Projects/Active/Three.md",
    ]);
    expect(readState.maxActive).toBeGreaterThan(1);
    expect(priorityLoaded).toEqual(["Notes/Two.md"]);
    expect(dirs).toEqual([
      "Areas",
      "Areas/Work",
      "Areas/Work/Clients",
      "Areas/Work/Clients/Acme",
      "Areas/Work/Clients/Acme/Projects",
      "Notes",
      "Projects",
      "Projects/Active",
    ]);
    expect(readState.dirs).toBe(11);
  });
});
