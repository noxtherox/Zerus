import type { VaultBackend, VaultFile } from "./backend";

const STORAGE_KEY = "zerus.browserVault.v1";
const ASSETS_KEY = "zerus.browserVault.assets.v1";
const DIRS_KEY = "zerus.browserVault.dirs.v1";
const DEMO_SEED_VERSION_KEY = "zerus.browserVault.demoSeedVersion";
const DEMO_SEED_VERSION = "2";

interface StoredFile {
  content: string;
  createdAt?: string;
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
  const calendarDate = (offsetDays: number) => {
    const date = new Date();
    date.setHours(12, 0, 0, 0);
    date.setDate(date.getDate() + offsetDays);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  };
  return {
    ".zerus/properties.json": {
      updatedAt: at(65),
      content: JSON.stringify({
        inbox: [
          { name: "Status", type: "list", listOptions: ["Todo", "Waiting", "Done", "Reference"] },
          { name: "Follow up", type: "date" },
          { name: "Source", type: "text" },
        ],
        work: [
          { name: "Status", type: "list", listOptions: ["Planned", "In progress", "Review", "Blocked", "Done"] },
          { name: "Due date", type: "date" },
          { name: "Priority", type: "list", listOptions: ["Low", "Medium", "High"] },
          { name: "Owner", type: "text" },
          { name: "Effort", type: "number" },
          { name: "Reviewed", type: "checkbox" },
        ],
        "personal/reading": [
          { name: "Topic", type: "list", listOptions: ["Design", "Research", "Engineering"] },
          { name: "Next review", type: "date" },
          { name: "Favorite", type: "checkbox" },
        ],
      }, null, 2),
    },
    "inbox/Welcome to Zerus.md": {
      createdAt: at(60),
      updatedAt: at(60),
      content: `---
Status: Reference
Follow up: ${calendarDate(1)}
Source: Browser demo
---
# Welcome to Zerus

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
      createdAt: at(50),
      updatedAt: at(50),
      content: `---
Status: In progress
Due date: ${calendarDate(6)}
Priority: High
Owner: Ava
Effort: 13
Reviewed: false
---
# Project Polaris

The star project. This note is linked from several places — toggle the Backlinks sidebar (link icon, top right) to see them grouped by type.

## Goals

- Ship the northern-lights dashboard
- Keep scope small`,
    },
    "work/meetings/Meeting notes — kickoff.md": {
      createdAt: at(40),
      updatedAt: at(40),
      content: `---
Status: Done
Due date: ${calendarDate(-3)}
Priority: Medium
Owner: Marco
Effort: 2
Reviewed: true
---
# Meeting notes — kickoff

Kickoff for [[Project Polaris]] with the platform team.

- Timeline: 6 weeks
- Next step: draft the spec`,
    },
    "personal/reading/Reading list.md": {
      createdAt: at(30),
      updatedAt: at(30),
      content: `---
Topic: Research
Next review: ${calendarDate(4)}
Favorite: true
---
# Reading list

Things to read on the weekend, some relevant to [[Project Polaris]].

- Designing Data-Intensive Applications
- The Bear app design retrospective`,
    },
    "work/projects/Website refresh.md": {
      createdAt: at(25),
      updatedAt: at(25),
      content: `---
Status: Review
Due date: ${calendarDate(2)}
Priority: High
Owner: Tiago
Effort: 8
Reviewed: false
---
# Website refresh

Final visual pass for the public site before launch.

- Check responsive navigation
- Tighten download messaging
- Verify dark mode`,
    },
    "work/projects/Research archive.md": {
      createdAt: at(22),
      updatedAt: at(22),
      content: `---
Status: Blocked
Due date: ${calendarDate(-12)}
Priority: Medium
Owner: Sofia
Effort: 5
Reviewed: false
---
# Research archive

Consolidate the older interview notes and tag the strongest findings.`,
    },
    "work/projects/October launch.md": {
      createdAt: at(19),
      updatedAt: at(19),
      content: `---
Status: Planned
Due date: ${calendarDate(20)}
Priority: High
Owner: Ava
Effort: 21
Reviewed: false
---
# October launch

Working plan for the next desktop release and its launch notes.`,
    },
    "work/projects/Accessibility review.md": {
      createdAt: at(16),
      updatedAt: at(16),
      content: `---
Status: In progress
Due date: ${calendarDate(0)}
Priority: High
Owner: Marco
Effort: 5
Reviewed: true
---
# Accessibility review

Keyboard, focus, contrast, and screen-reader checks for the core note flow.`,
    },
    "personal/reading/Design systems field notes.md": {
      createdAt: at(13),
      updatedAt: at(13),
      content: `---
Topic: Design
Next review: ${calendarDate(12)}
Favorite: true
---
# Design systems field notes

Patterns worth revisiting for compact desktop interfaces.`,
    },
    "personal/reading/Local-first software.md": {
      createdAt: at(10),
      updatedAt: at(10),
      content: `---
Topic: Engineering
Next review: ${calendarDate(-5)}
Favorite: false
---
# Local-first software

Notes on ownership, synchronization, conflict resolution, and durable file formats.`,
    },
    "inbox/Invoice follow-up.md": {
      createdAt: at(7),
      updatedAt: at(7),
      content: `---
Status: Waiting
Follow up: ${calendarDate(1)}
Source: Email
---
# Invoice follow-up

Check whether the September invoice has been approved.`,
    },
    "inbox/Send launch brief.md": {
      createdAt: at(4),
      updatedAt: at(4),
      content: `---
Status: Todo
Follow up: ${calendarDate(0)}
Source: Meeting
---
# Send launch brief

Share the short launch brief with the desktop team.`,
    },
    "inbox/Renew passport.md": {
      createdAt: at(2),
      updatedAt: at(2),
      content: `---
Status: Todo
Follow up: ${calendarDate(45)}
Source: Personal reminder
---
# Renew passport

Gather the photo and supporting documents before the appointment.`,
    },
  };
}

function mergeSeedSchemas(existing: StoredFile, seeded: StoredFile): StoredFile {
  try {
    const current = JSON.parse(existing.content) as Record<string, Array<{ name?: string }>>;
    const additions = JSON.parse(seeded.content) as Record<string, Array<{ name?: string }>>;
    for (const [typeKey, definitions] of Object.entries(additions)) {
      const present = Array.isArray(current[typeKey]) ? current[typeKey] : [];
      const names = new Set(present.map((definition) => definition.name?.toLowerCase()));
      current[typeKey] = [
        ...present,
        ...definitions.filter((definition) => !names.has(definition.name?.toLowerCase())),
      ];
    }
    return { ...existing, content: JSON.stringify(current, null, 2) };
  } catch {
    return existing;
  }
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
    const seeded = seedFiles();
    this.files = stored ?? seeded;
    let seedChanged = !stored;
    try {
      if (localStorage.getItem(DEMO_SEED_VERSION_KEY) !== DEMO_SEED_VERSION) {
        for (const [path, file] of Object.entries(seeded)) {
          if (path === ".zerus/properties.json" && this.files[path]) {
            const merged = mergeSeedSchemas(this.files[path], file);
            if (merged.content !== this.files[path].content) {
              this.files[path] = merged;
              seedChanged = true;
            }
          } else if (!this.files[path]) {
            this.files[path] = file;
            seedChanged = true;
          }
        }
        localStorage.setItem(DEMO_SEED_VERSION_KEY, DEMO_SEED_VERSION);
      }
    } catch {
      // Browser storage is optional; the in-memory demo still works.
    }
    if (seedChanged) this.persist();

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
      .filter(([path]) => /\.md$/i.test(path) && !path.startsWith(".zerus/"))
      .map(([path, file]) => ({
        path,
        content: file.content,
        createdAt: file.createdAt ?? file.updatedAt,
        updatedAt: file.updatedAt,
      }));
  }

  async loadFiles(paths: string[]): Promise<VaultFile[]> {
    return paths.map((path) => {
      const file = this.files[path];
      if (!file) throw new Error(`No such file: ${path}`);
      return {
        path,
        content: file.content,
        createdAt: file.createdAt ?? file.updatedAt,
        updatedAt: file.updatedAt,
      };
    });
  }

  async readText(path: string): Promise<string> {
    const file = this.files[path];
    if (!file) throw new Error(`No such file: ${path}`);
    return file.content;
  }

  async listFiles(path: string): Promise<string[]> {
    const prefix = path ? `${path.replace(/\/$/, "")}/` : "";
    return [
      ...Object.keys(this.files),
      ...Object.keys(this.assets),
    ].filter((candidate) => candidate.startsWith(prefix)).sort();
  }

  async write(path: string, content: string): Promise<void> {
    const now = new Date().toISOString();
    this.files[path] = {
      content,
      createdAt:
        this.files[path]?.createdAt ?? this.files[path]?.updatedAt ?? now,
      updatedAt: now,
    };
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
    if (file) {
      delete this.files[from];
      this.files[to] = file;
      this.persist();
      return;
    }
    const asset = this.assets[from];
    if (asset === undefined) return;
    delete this.assets[from];
    this.assets[to] = asset;
    this.persistAssets();
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
