/** A markdown file in the vault, path is vault-relative with forward slashes. */
export interface VaultFile {
  path: string;
  content: string;
  /** Filesystem creation time when available; falls back to updatedAt. */
  createdAt?: string;
  updatedAt: string;
}

/** Lightweight note metadata used to paginate without reading file contents. */
export interface VaultFileEntry {
  path: string;
  createdAt?: string;
  updatedAt: string;
}

export interface VaultBackend {
  readonly kind: "desktop" | "browser" | "mobile";
  /** Human-readable location of the vault (absolute path, or a label). */
  readonly location: string;
  /** Device filesystem path for a vault-relative file, when the shell can open it. */
  absolutePath?(path: string): string | null;
  loadAll(): Promise<VaultFile[]>;
  /** Optional fast path for backends that can discover notes before reading them. */
  listNoteEntries?(): Promise<VaultFileEntry[]>;
  /** Loads only the requested notes. Paths must be vault-relative. */
  loadFiles?(paths: string[]): Promise<VaultFile[]>;
  /** Reads any text file in the vault (config etc.), throws if missing. */
  readText(path: string): Promise<string>;
  /** Recursively lists files below an arbitrary vault-relative metadata folder. */
  listFiles(path: string): Promise<string[]>;
  write(path: string, content: string): Promise<void>;
  /** Atomically creates a file and fails if the path already exists. */
  writeNew(path: string, content: string): Promise<void>;
  move(from: string, to: string): Promise<void>;
  removeFile(path: string): Promise<void>;
  exists(path: string): Promise<boolean>;
  /** Creates a folder so a type can exist before it has any notes. */
  mkDir(path: string): Promise<void>;
  /** Removes a folder and everything still inside it (deleting a type). */
  removeDir(path: string): Promise<void>;
  /** Renames/moves a folder and everything inside it (editing a type). */
  renameDir(from: string, to: string): Promise<void>;
  /** All note folders (vault-relative), including ones with no notes. */
  listDirs(): Promise<string[]>;
  /** Binary asset support (pasted images etc.). */
  writeBinary(path: string, bytes: Uint8Array): Promise<void>;
  readBinary(path: string): Promise<Uint8Array>;
}
