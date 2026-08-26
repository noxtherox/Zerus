import {
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
import { invoke } from "@tauri-apps/api/core";
import { TRASH_DIR, MAX_TYPE_DEPTH } from "@/lib/note-utils";
import type { VaultBackend, VaultFile } from "./backend";

const STARTUP_READ_CONCURRENCY = 32;

interface VaultDiscovery {
  notePaths: string[];
  typeDirs: string[];
}

interface DesktopLoadOptions {
  priorityPaths?: string[];
  onPriorityLoaded?: (files: VaultFile[]) => void;
}

async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  mapper: (item: T) => Promise<R>,
): Promise<R[]> {
  const results = new Array<R>(items.length);
  let nextIndex = 0;

  const worker = async () => {
    while (nextIndex < items.length) {
      const index = nextIndex++;
      results[index] = await mapper(items[index]);
    }
  };

  await Promise.all(
    Array.from(
      { length: Math.min(concurrency, items.length) },
      () => worker(),
    ),
  );
  return results;
}

/** Reads/writes notes as real .md files inside a user-chosen folder. */
export class DesktopVault implements VaultBackend {
  readonly kind = "desktop" as const;
  private discoveryInFlight: Promise<VaultDiscovery> | null = null;

  constructor(private readonly root: string) {}

  get location(): string {
    return this.root;
  }

  private abs(relPath: string): string {
    const segments = relPath.split(/[\\/]/);
    if (
      /^(?:[\\/]|[a-z]:[\\/])/i.test(relPath) ||
      segments.some((segment) => segment === "." || segment === "..")
    ) {
      throw new Error(`Unsafe vault path: ${relPath}`);
    }
    return `${this.root}/${relPath}`;
  }

  absolutePath(path: string): string {
    return this.abs(path);
  }

  private discover(): Promise<VaultDiscovery> {
    if (this.discoveryInFlight) return this.discoveryInFlight;
    const notePaths: string[] = [];
    const typeDirs: string[] = [];

    const walk = async (relDir: string, depth: number): Promise<void> => {
      const absDir = relDir ? this.abs(relDir) : this.root;
      const entries = await readDir(absDir);
      await Promise.all(
        entries.map(async (entry) => {
          const relPath = relDir ? `${relDir}/${entry.name}` : entry.name;
          if (entry.isDirectory) {
            const isTrashRoot = relPath === TRASH_DIR;
            if (entry.name.startsWith(".") && !isTrashRoot) return;
            if (!relPath.startsWith(`${TRASH_DIR}/`) && !isTrashRoot) {
              const typeDepth = relPath.split("/").length;
              if (typeDepth <= MAX_TYPE_DEPTH) typeDirs.push(relPath);
            }
            // one extra level inside .trash mirrors the type depth
            const maxDepth = MAX_TYPE_DEPTH + 1;
            if (depth < maxDepth) await walk(relPath, depth + 1);
            return;
          }
          if (entry.isFile && /\.md$/i.test(entry.name)) notePaths.push(relPath);
        }),
      );
    };

    const discovery = walk("", 0).then(() => ({
      notePaths: notePaths.sort((left, right) => left.localeCompare(right)),
      typeDirs: typeDirs.sort((left, right) => left.localeCompare(right)),
    }));
    this.discoveryInFlight = discovery;
    const clearDiscovery = () => {
      if (this.discoveryInFlight === discovery) this.discoveryInFlight = null;
    };
    void discovery.then(clearDiscovery, clearDiscovery);
    return discovery;
  }

  async loadFile(path: string): Promise<VaultFile> {
    const absPath = this.abs(path);
    const [content, info] = await Promise.all([
      readTextFile(absPath),
      stat(absPath),
    ]);
    return {
      path,
      content,
      createdAt: (info.birthtime ?? info.mtime ?? new Date()).toISOString(),
      updatedAt: (info.mtime ?? new Date()).toISOString(),
    };
  }

  loadFiles(
    paths: string[],
    onFileLoaded?: (file: VaultFile) => void,
  ): Promise<VaultFile[]> {
    return mapWithConcurrency(paths, STARTUP_READ_CONCURRENCY, async (path) => {
      const file = await this.loadFile(path);
      onFileLoaded?.(file);
      return file;
    });
  }

  async loadAll(options: DesktopLoadOptions = {}): Promise<VaultFile[]> {
    const { notePaths } = await this.discover();
    const available = new Set(notePaths);
    const requestedPriority = (options.priorityPaths ?? []).filter((path) =>
      available.has(path),
    );
    const priorityPaths = requestedPriority.length
      ? [...new Set(requestedPriority)].slice(0, STARTUP_READ_CONCURRENCY)
      : notePaths
          .filter((path) => !path.startsWith(`${TRASH_DIR}/`))
          .slice(0, STARTUP_READ_CONCURRENCY);
    const prioritySet = new Set(priorityPaths);
    const priorityFiles = await this.loadFiles(priorityPaths, (file) =>
      options.onPriorityLoaded?.([file]),
    );
    const remainingFiles = await this.loadFiles(
      notePaths.filter((path) => !prioritySet.has(path)),
    );
    const filesByPath = new Map(
      [...priorityFiles, ...remainingFiles].map((file) => [file.path, file]),
    );
    return notePaths.map((path) => filesByPath.get(path)!);
  }

  private async ensureParentDir(relPath: string): Promise<void> {
    const dir = relPath.split("/").slice(0, -1).join("/");
    if (!dir) return;
    const absDir = this.abs(dir);
    if (!(await exists(absDir))) {
      await mkdir(absDir, { recursive: true });
    }
  }

  async readText(path: string): Promise<string> {
    return readTextFile(this.abs(path));
  }

  async listFiles(path: string): Promise<string[]> {
    const files: string[] = [];
    const walk = async (relativeDir: string): Promise<void> => {
      const absoluteDir = relativeDir ? this.abs(relativeDir) : this.root;
      if (!(await exists(absoluteDir))) return;
      for (const entry of await readDir(absoluteDir)) {
        const relativePath = relativeDir ? `${relativeDir}/${entry.name}` : entry.name;
        if (entry.isDirectory) await walk(relativePath);
        else if (entry.isFile) files.push(relativePath);
      }
    };
    await walk(path.replace(/\/$/, ""));
    return files.sort();
  }

  async write(path: string, content: string): Promise<void> {
    await this.ensureParentDir(path);
    await writeTextFile(this.abs(path), content);
  }

  async writeNew(path: string, content: string): Promise<void> {
    await invoke("write_new_vault_file", {
      root: this.root,
      relativePath: path,
      content,
    });
  }

  async move(from: string, to: string): Promise<void> {
    await this.ensureParentDir(to);
    await rename(this.abs(from), this.abs(to));
  }

  async removeFile(path: string): Promise<void> {
    await remove(this.abs(path));
  }

  async exists(path: string): Promise<boolean> {
    return exists(this.abs(path));
  }

  async mkDir(path: string): Promise<void> {
    await mkdir(this.abs(path), { recursive: true });
  }

  async removeDir(path: string): Promise<void> {
    const absPath = this.abs(path);
    if (!(await exists(absPath))) return;
    await remove(absPath, { recursive: true });
  }

  async renameDir(from: string, to: string): Promise<void> {
    await this.ensureParentDir(to);
    await rename(this.abs(from), this.abs(to));
  }

  async listDirs(): Promise<string[]> {
    return (await this.discover()).typeDirs;
  }

  async writeBinary(path: string, bytes: Uint8Array): Promise<void> {
    await this.ensureParentDir(path);
    await writeFile(this.abs(path), bytes);
  }

  async readBinary(path: string): Promise<Uint8Array> {
    return readFile(this.abs(path));
  }
}
