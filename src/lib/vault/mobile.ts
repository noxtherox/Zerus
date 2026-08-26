import {
  BaseDirectory,
  exists,
  mkdir,
  readDir,
  readFile,
  readTextFile,
  remove,
  rename,
  stat,
  writeFile,
  writeTextFile,
} from "@tauri-apps/plugin-fs";
import { MAX_TYPE_DEPTH, TRASH_DIR } from "@/lib/note-utils";
import { mobileDiagnostic } from "@/lib/mobile-diagnostics";
import type { VaultBackend, VaultFile, VaultFileEntry } from "./backend";

const ROOT = "vault";
const VAULT_MARKER_PATH = ".zerus/mobile-vault-v1";
const DEFAULT_VAULT_NAME = "Zerus";

const STARTER_NOTES: Array<{ path: string; content: string }> = [
  {
    path: "Ideas/Ideas for Zerus mobile.md",
    content: `---
zerus-pinned: true
---
# Ideas for Zerus mobile

A calm place to capture thoughts before they disappear.

## Mobile principles

- Capture in one tap
- Keep the vault structure familiar
- Make reading feel spacious
- Sync plain Markdown files`,
  },
  {
    path: "Books/The Left Hand of Darkness.md",
    content: `---
zerus-pinned: true
---
# The Left Hand of Darkness

Notes and quotes from Ursula K. Le Guin's novel.

A story about loyalty, identity, and the distance between people.`,
  },
  {
    path: "Home/July garden plan.md",
    content: `# July garden plan

Move the herbs, prune the tomatoes, and order winter seeds.

## Weekend list

- Move the herbs into partial shade
- Prune the tomatoes
- Order winter seeds`,
  },
  {
    path: "Journal/Weekly review.md",
    content: `# Weekly review

What moved forward, what felt stuck, and next week's focus.

## Next week

Test the capture flow with real notes and reduce the number of taps.`,
  },
];

type DiskPath = string | URL;

function assertSafeVaultPath(path: string): void {
  const segments = path.split(/[\\/]/);
  if (
    /^(?:[\\/]|[a-z]:[\\/])/i.test(path) ||
    segments.some((segment) => segment === "." || segment === "..")
  ) {
    throw new Error(`Unsafe vault path: ${path}`);
  }
}

abstract class MobileFilesystemVault implements VaultBackend {
  readonly kind = "mobile" as const;
  abstract readonly location: string;

  protected abstract target(path: string): DiskPath;

  absolutePath(path: string): string | null {
    const target = this.target(path);
    return target instanceof URL ? decodeURIComponent(target.pathname) : null;
  }

  protected baseDirectory(): BaseDirectory | undefined {
    return undefined;
  }

  private options(): { baseDir?: BaseDirectory } {
    const baseDir = this.baseDirectory();
    return baseDir === undefined ? {} : { baseDir };
  }

  private renameOptions(): {
    oldPathBaseDir?: BaseDirectory;
    newPathBaseDir?: BaseDirectory;
  } {
    const baseDir = this.baseDirectory();
    return baseDir === undefined
      ? {}
      : { oldPathBaseDir: baseDir, newPathBaseDir: baseDir };
  }

  private async ensureParentDir(path: string): Promise<void> {
    const dir = path.split("/").slice(0, -1).join("/");
    if (!dir) return;
    await mkdir(this.target(dir), { ...this.options(), recursive: true });
  }

  private async findMarkdownPaths(): Promise<string[]> {
    const paths: string[] = [];
    mobileDiagnostic("vault.files.load.started", { location: this.location });
    const walk = async (relativeDir: string, depth: number): Promise<void> => {
      mobileDiagnostic("vault.directory.read.started", { depth });
      let entries: Awaited<ReturnType<typeof readDir>>;
      try {
        entries = await readDir(this.target(relativeDir), this.options());
        mobileDiagnostic("vault.directory.read.resolved", {
          depth,
          entries: entries.length,
        });
      } catch (error) {
        mobileDiagnostic("vault.directory.read.failed", { depth, error });
        throw error;
      }
      for (const entry of entries) {
        const relativePath = relativeDir
          ? `${relativeDir}/${entry.name}`
          : entry.name;
        if (entry.isDirectory) {
          const isTrashRoot = relativePath === TRASH_DIR;
          if (entry.name.startsWith(".") && !isTrashRoot) continue;
          if (depth < MAX_TYPE_DEPTH + 1) await walk(relativePath, depth + 1);
          continue;
        }
        if (!entry.isFile || !/\.md$/i.test(entry.name)) continue;
        paths.push(relativePath);
      }
    };
    await walk("", 0);
    return paths;
  }

  async listNoteEntries(): Promise<VaultFileEntry[]> {
    const paths = await this.findMarkdownPaths();
    const entries: VaultFileEntry[] = [];
    const concurrency = 12;
    let nextIndex = 0;
    const worker = async () => {
      while (nextIndex < paths.length) {
        const path = paths[nextIndex++];
        const info = await stat(this.target(path), this.options());
        entries.push({
          path,
          createdAt: (info.birthtime ?? info.mtime ?? new Date()).toISOString(),
          updatedAt: (info.mtime ?? new Date()).toISOString(),
        });
      }
    };
    await Promise.all(
      Array.from({ length: Math.min(concurrency, paths.length) }, () => worker()),
    );
    entries.sort(
      (a, b) =>
        new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime() ||
        a.path.localeCompare(b.path),
    );
    mobileDiagnostic("vault.files.index.resolved", { files: entries.length });
    return entries;
  }

  async loadFiles(paths: string[]): Promise<VaultFile[]> {
    const files = await Promise.all(
      paths.map(async (path, index) => {
        assertSafeVaultPath(path);
        mobileDiagnostic("vault.note.read.started", { fileIndex: index + 1 });
        const [content, info] = await Promise.all([
          readTextFile(this.target(path), this.options()),
          stat(this.target(path), this.options()),
        ]);
        mobileDiagnostic("vault.note.read.resolved", { fileIndex: index + 1 });
        return {
          path,
          content,
          createdAt: (info.birthtime ?? info.mtime ?? new Date()).toISOString(),
          updatedAt: (info.mtime ?? new Date()).toISOString(),
        };
      }),
    );
    mobileDiagnostic("vault.files.load.resolved", { files: files.length });
    return files;
  }

  async loadAll(): Promise<VaultFile[]> {
    const entries = await this.listNoteEntries();
    return this.loadFiles(entries.map((entry) => entry.path));
  }

  async readText(path: string): Promise<string> {
    return readTextFile(this.target(path), this.options());
  }

  async listFiles(path: string): Promise<string[]> {
    const files: string[] = [];
    const walk = async (relativeDir: string): Promise<void> => {
      if (!(await exists(this.target(relativeDir), this.options()))) return;
      for (const entry of await readDir(this.target(relativeDir), this.options())) {
        const relativePath = relativeDir ? `${relativeDir}/${entry.name}` : entry.name;
        if (entry.isDirectory) await walk(relativePath);
        else if (entry.isFile) files.push(relativePath);
      }
    };
    await walk(path.replace(/\/$/, ""));
    return files.sort();
  }

  async write(path: string, content: string): Promise<void> {
    assertSafeVaultPath(path);
    await this.ensureParentDir(path);
    await writeTextFile(this.target(path), content, this.options());
  }

  async writeNew(path: string, content: string): Promise<void> {
    assertSafeVaultPath(path);
    await this.ensureParentDir(path);
    await writeTextFile(this.target(path), content, {
      ...this.options(),
      createNew: true,
    });
  }

  async move(from: string, to: string): Promise<void> {
    assertSafeVaultPath(from);
    assertSafeVaultPath(to);
    await this.ensureParentDir(to);
    await rename(this.target(from), this.target(to), this.renameOptions());
  }

  async removeFile(path: string): Promise<void> {
    assertSafeVaultPath(path);
    await remove(this.target(path), this.options());
  }

  async exists(path: string): Promise<boolean> {
    assertSafeVaultPath(path);
    return exists(this.target(path), this.options());
  }

  async mkDir(path: string): Promise<void> {
    assertSafeVaultPath(path);
    await mkdir(this.target(path), { ...this.options(), recursive: true });
  }

  async removeDir(path: string): Promise<void> {
    if (!(await this.exists(path))) return;
    await remove(this.target(path), { ...this.options(), recursive: true });
  }

  async renameDir(from: string, to: string): Promise<void> {
    assertSafeVaultPath(from);
    assertSafeVaultPath(to);
    await this.ensureParentDir(to);
    await rename(this.target(from), this.target(to), this.renameOptions());
  }

  async listDirs(): Promise<string[]> {
    const directories: string[] = [];
    const walk = async (relativeDir: string, depth: number): Promise<void> => {
      const entries = await readDir(this.target(relativeDir), this.options());
      for (const entry of entries) {
        if (!entry.isDirectory || entry.name.startsWith(".")) continue;
        const path = relativeDir ? `${relativeDir}/${entry.name}` : entry.name;
        directories.push(path);
        if (depth + 1 < MAX_TYPE_DEPTH) await walk(path, depth + 1);
      }
    };
    await walk("", 0);
    return directories;
  }

  async writeBinary(path: string, bytes: Uint8Array): Promise<void> {
    assertSafeVaultPath(path);
    await this.ensureParentDir(path);
    await writeFile(this.target(path), bytes, this.options());
  }

  async readBinary(path: string): Promise<Uint8Array> {
    assertSafeVaultPath(path);
    return readFile(this.target(path), this.options());
  }

  async hasVaultMarker(): Promise<boolean> {
    return this.exists(VAULT_MARKER_PATH);
  }

  async hasZerusMetadata(): Promise<boolean> {
    return this.exists(".zerus");
  }

  async rootExists(): Promise<boolean> {
    return exists(this.target(""), this.options());
  }

  async markAsVault(): Promise<void> {
    await this.write(VAULT_MARKER_PATH, "1");
  }
}

/** Persistent Markdown vault stored inside the iOS app container. */
export class MobileVault extends MobileFilesystemVault {
  readonly location = DEFAULT_VAULT_NAME;

  static async open(): Promise<MobileVault> {
    const vault = new MobileVault();
    await vault.initialize();
    return vault;
  }

  static async restore(): Promise<MobileVault | null> {
    const vault = new MobileVault();
    return (await vault.hasVaultMarker()) ? vault : null;
  }

  protected baseDirectory(): BaseDirectory {
    return BaseDirectory.AppData;
  }

  protected target(path: string): string {
    assertSafeVaultPath(path);
    return path ? `${ROOT}/${path}` : ROOT;
  }

  private async initialize(): Promise<void> {
    await mkdir(this.target(".zerus"), {
      baseDir: BaseDirectory.AppData,
      recursive: true,
    });
    if (
      await exists(this.target(VAULT_MARKER_PATH), {
        baseDir: BaseDirectory.AppData,
      })
    ) {
      return;
    }
    for (const note of STARTER_NOTES) {
      await this.write(note.path, note.content);
    }
    await writeTextFile(this.target(VAULT_MARKER_PATH), "1", {
      baseDir: BaseDirectory.AppData,
    });
  }
}

/** User-selected Files or iCloud Drive folder held by a security-scoped bookmark. */
export class MobileFolderVault extends MobileFilesystemVault {
  readonly location: string;
  private readonly root: URL;

  constructor(rootUrl: string, name: string) {
    super();
    this.root = new URL(rootUrl.endsWith("/") ? rootUrl : `${rootUrl}/`);
    this.location = name;
  }

  static async restore(rootUrl: string, name: string): Promise<MobileFolderVault> {
    const vault = new MobileFolderVault(rootUrl, name);
    if (
      name.localeCompare(DEFAULT_VAULT_NAME, undefined, { sensitivity: "accent" }) === 0 ||
      (await vault.hasVaultMarker()) ||
      (await vault.hasZerusMetadata())
    ) {
      return vault;
    }

    const nested = new MobileFolderVault(
      new URL(`${encodeURIComponent(DEFAULT_VAULT_NAME)}/`, vault.root).href,
      DEFAULT_VAULT_NAME,
    );
    if (await nested.rootExists()) return nested;

    // The bookmark itself records the user's choice. Existing desktop vaults do
    // not necessarily contain Zerus metadata and may have a custom name.
    return vault;
  }

  static async locate(rootUrl: string, name: string): Promise<MobileFolderVault | null> {
    mobileDiagnostic("vault.locate.started", { name });
    const selected = new MobileFolderVault(rootUrl, name);
    if (
      name.localeCompare(DEFAULT_VAULT_NAME, undefined, { sensitivity: "accent" }) === 0 ||
      (await selected.hasVaultMarker()) ||
      (await selected.hasZerusMetadata())
    ) {
      mobileDiagnostic("vault.locate.selected-root", { name });
      return selected;
    }

    const nested = new MobileFolderVault(
      new URL(`${encodeURIComponent(DEFAULT_VAULT_NAME)}/`, selected.root).href,
      DEFAULT_VAULT_NAME,
    );
    if (await nested.rootExists()) return nested;

    // Selecting a directory in the document picker is an explicit request to
    // use that directory as the vault. Do not reject custom-named or older
    // vaults just because they predate Zerus's metadata marker.
    mobileDiagnostic("vault.locate.selected-custom-root", { name });
    return selected;
  }

  static async create(rootUrl: string, name: string): Promise<MobileFolderVault> {
    const selected = new MobileFolderVault(rootUrl, name);
    const vault =
      name.localeCompare(DEFAULT_VAULT_NAME, undefined, { sensitivity: "accent" }) === 0
        ? selected
        : new MobileFolderVault(
            new URL(`${encodeURIComponent(DEFAULT_VAULT_NAME)}/`, selected.root).href,
            DEFAULT_VAULT_NAME,
          );
    await vault.markAsVault();
    return vault;
  }

  protected target(path: string): URL {
    assertSafeVaultPath(path);
    const encodedPath = path
      .split("/")
      .filter(Boolean)
      .map(encodeURIComponent)
      .join("/");
    return encodedPath ? new URL(encodedPath, this.root) : this.root;
  }
}
