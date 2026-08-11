import type { VaultBackend, VaultFile } from "./backend";

const STORAGE_KEY = "zerus.browserVault.v1";
const ASSETS_KEY = "zerus.browserVault.assets.v1";
const DIRS_KEY = "zerus.browserVault.dirs.v1";

interface StoredFile {
  content: string;
  updatedAt: string;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function seedFiles(): Record<string, StoredFile> {
  const now = Date.now();
  const at = (offsetMinutes: number) =>
    new Date(now - offsetMinutes * 60_000).toISOString();
  return {
    "inbox/Welcome to Zerus.md": {
      updatedAt: at(60),
      content: `# Welcome to Zerus

Zerus is a Bear-style notes app where your notes are plain markdown files in folders, and the folders are your **types**: every note has a type, and optionally a sub-type and sub-sub-type.

## The basics

- The sidebar shows your type tree — it mirrors the folder structure of your vault.
- The first line of a note is its title; the filename follows it.
- Change a note's type from the selector at the top of the editor: it moves the file.

## Linking

Type \`[[\` to link to another note — try it! For example: [[Project Polaris]].

Cmd/Ctrl+Click a link to follow it. Open [[Project Polaris]] and toggle the **Backlinks** sidebar with the link button at the top right: notes that link to it are grouped by their type, so you can see *where* a note is referenced from at a glance.

> In the desktop app you point Zerus at any folder of .md files and they show up here with their types.`,
    },
    "work/projects/Project Polaris.md": {
      updatedAt: at(50),
      content: `# Project Polaris

The star project. This note is linked from several places — toggle the Backlinks sidebar (link icon, top right) to see them grouped by type.

## Goals

- Ship the northern-lights dashboard
- Keep scope small`,
    },
    "work/meetings/Meeting notes — kickoff.md": {
      updatedAt: at(40),
      content: `# Meeting notes — kickoff

Kickoff for [[Project Polaris]] with the platform team.

- Timeline: 6 weeks
- Next step: draft the spec`,
    },
    "personal/reading/Reading list.md": {
      updatedAt: at(30),
      content: `# Reading list

Things to read on the weekend, some relevant to [[Project Polaris]].

- Designing Data-Intensive Applications
- The Bear app design retrospective`,
    },
  };
}

/**
 * Virtual vault for running in a plain browser (Dyad preview) where there is
 * no filesystem access. Same path semantics as the desktop vault, persisted
 * in localStorage.
 */
export class BrowserVault implements VaultBackend {
  readonly kind = "browser" as const;
  readonly location = "Browser storage";

  private files: Record<string, StoredFile>;
  private assets: Record<string, string>; // path -> base64 bytes
  private dirs: string[]; // folders declared without notes (empty types)

  constructor() {
    let stored: Record<string, StoredFile> | null = null;
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) stored = JSON.parse(raw) as Record<string, StoredFile>;
    } catch {
      stored = null;
    }
    this.files = stored ?? seedFiles();
    if (!stored) this.persist();

    let assets: Record<string, string> | null = null;
    try {
      const raw = localStorage.getItem(ASSETS_KEY);
      if (raw) assets = JSON.parse(raw) as Record<string, string>;
    } catch {
      assets = null;
    }
    this.assets = assets ?? {};

    let dirs: string[] | null = null;
    try {
      const raw = localStorage.getItem(DIRS_KEY);
      if (raw) dirs = JSON.parse(raw) as string[];
    } catch {
      dirs = null;
    }
    this.dirs = dirs ?? [];
  }

  private persist() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.files));
    } catch {
      // storage full or unavailable — keep working in memory
    }
  }

  private persistAssets() {
    try {
      localStorage.setItem(ASSETS_KEY, JSON.stringify(this.assets));
    } catch {
      // storage full or unavailable — keep working in memory
    }
  }

  private persistDirs() {
    try {
      localStorage.setItem(DIRS_KEY, JSON.stringify(this.dirs));
    } catch {
      // storage full or unavailable — keep working in memory
    }
  }

  async loadAll(): Promise<VaultFile[]> {
    // only .md files are notes — config files (.zerus/…) also live in
    // `files` via write(), and must not show up as notes
    return Object.entries(this.files)
      .filter(([path]) => /\.md$/i.test(path))
      .map(([path, file]) => ({
        path,
        content: file.content,
        updatedAt: file.updatedAt,
      }));
  }

  async readText(path: string): Promise<string> {
    const file = this.files[path];
    if (!file) throw new Error(`No such file: ${path}`);
    return file.content;
  }

  async write(path: string, content: string): Promise<void> {
    this.files[path] = { content, updatedAt: new Date().toISOString() };
    this.persist();
  }

  async writeNew(path: string, content: string): Promise<void> {
    if (path in this.files || path in this.assets) {
      throw new Error(`File already exists: ${path}`);
    }
    await this.write(path, content);
  }

  async move(from: string, to: string): Promise<void> {
    const file = this.files[from];
    if (!file) return;
    delete this.files[from];
    this.files[to] = file;
    this.persist();
  }

  async removeFile(path: string): Promise<void> {
    if (path in this.assets) {
      delete this.assets[path];
      this.persistAssets();
      return;
    }
    delete this.files[path];
    this.persist();
  }

  async exists(path: string): Promise<boolean> {
    return path in this.files || path in this.assets;
  }

  async mkDir(path: string): Promise<void> {
    if (this.dirs.includes(path)) return;
    this.dirs.push(path);
    this.persistDirs();
  }

  async removeDir(path: string): Promise<void> {
    const prefix = `${path}/`;
    this.dirs = this.dirs.filter(
      (dir) => dir !== path && !dir.startsWith(prefix),
    );
    this.persistDirs();
    for (const filePath of Object.keys(this.files)) {
      if (filePath === path || filePath.startsWith(prefix)) {
        delete this.files[filePath];
      }
    }
    this.persist();
  }

  async renameDir(from: string, to: string): Promise<void> {
    const remapPath = (path: string): string =>
      path === from ? to : `${to}/${path.slice(from.length + 1)}`;
    const prefix = `${from}/`;

    this.dirs = this.dirs.map((dir) =>
      dir === from || dir.startsWith(prefix) ? remapPath(dir) : dir,
    );
    this.persistDirs();

    for (const [path, file] of Object.entries(this.files)) {
      if (path !== from && !path.startsWith(prefix)) continue;
      delete this.files[path];
      this.files[remapPath(path)] = file;
    }
    this.persist();

    for (const [path, data] of Object.entries(this.assets)) {
      if (path !== from && !path.startsWith(prefix)) continue;
      delete this.assets[path];
      this.assets[remapPath(path)] = data;
    }
    this.persistAssets();
  }

  async listDirs(): Promise<string[]> {
    return [...this.dirs];
  }

  async writeBinary(path: string, bytes: Uint8Array): Promise<void> {
    this.assets[path] = bytesToBase64(bytes);
    this.persistAssets();
  }

  async readBinary(path: string): Promise<Uint8Array> {
    const stored = this.assets[path];
    if (stored === undefined) throw new Error(`No such asset: ${path}`);
    return base64ToBytes(stored);
  }
}
