import type { VaultBackend, VaultFile, VaultFileEntry } from "./backend";
import { MAX_TYPE_DEPTH, TRASH_DIR } from "@/lib/note-utils";
import {
  DRIVE_FIELDS, DRIVE_FOLDER, DriveError, decodeDriveBytes, driveFetch, driveId,
  driveJSON, driveTransport, encodeDriveBytes, listDriveChildren, parseDriveJSON,
  type DriveFile, type DriveTransport, type DriveVaultSelection,
} from "@/lib/google-drive";

// Drive v3 omits the file ETag. Keep conditional reads and updates on v2,
// whose File resource exposes the tag explicitly, including in the JSON body.
const LOCK_FIELDS = "id,title,mimeType,parents(id),modifiedDate,createdDate,version,labels(trashed),etag";
interface LockedDriveFile {
  id: string; title: string; mimeType: string; parents?: { id: string }[];
  modifiedDate?: string; createdDate?: string; version?: string;
  labels?: { trashed?: boolean }; etag?: string;
}
function lockedFile(response: Parameters<typeof parseDriveJSON>[0]): { file: DriveFile; etag?: string } {
  const value = parseDriveJSON<LockedDriveFile>(response);
  return { etag: value.etag ?? response.etag, file: {
    id: value.id, name: value.title, mimeType: value.mimeType,
    parents: value.parents?.map((parent) => parent.id), version: value.version,
    modifiedTime: value.modifiedDate, createdTime: value.createdDate, trashed: value.labels?.trashed,
  } };
}

function safePath(path: string, allowRoot = false): string {
  if ((allowRoot && path === "")) return path;
  if (!path || path.split("/").some((part) => !part || part === "." || part === "..") || path.includes("\\") || path.includes(String.fromCharCode(0))) {
    throw new Error("Invalid vault path.");
  }
  return path;
}

/** Online Drive vault. Tokens and HTTP requests remain in the native iOS layer. */
export class GoogleDriveVault implements VaultBackend {
  readonly kind = "mobile" as const;
  readonly location: string;
  private files = new Map<string, DriveFile>();
  private loaded = false;
  private indexing: Promise<void> | null = null;
  private mutations: Promise<unknown> = Promise.resolve();
  private readIds = new Set<string>();

  constructor(readonly selection: DriveVaultSelection, private transport: DriveTransport = driveTransport(selection.accountId)) {
    driveId(selection.folderId);
    this.location = `Google Drive · ${selection.name}`;
  }

  get cacheIdentity(): string {
    return `mobile:google-drive:${this.selection.accountId}:${this.selection.folderId}`;
  }

  private get draftKey(): string { return `zerus.drive-drafts.v1:${this.selection.accountId}:${this.selection.folderId}`; }
  drafts(): Record<string, { content: string; snapshot?: string }> {
    const value = localStorage.getItem(this.draftKey);
    if (!value) return {};
    const parsed = JSON.parse(value);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Could not read saved Google Drive drafts.");
    for (const [path, draft] of Object.entries(parsed)) {
      safePath(path);
      if (!draft || typeof draft !== "object" || typeof (draft as { content?: unknown }).content !== "string") throw new Error("Could not read a saved Google Drive draft.");
    }
    return parsed;
  }
  stageDraft(path: string, content: string, snapshot?: string): void {
    safePath(path);
    const drafts = this.drafts();
    drafts[path] = { content, snapshot: drafts[path]?.snapshot ?? snapshot };
    // Persist before accepting the edit so app termination cannot lose a failed upload.
    localStorage.setItem(this.draftKey, JSON.stringify(drafts));
  }
  clearDraft(path: string, savedContent?: string): void {
    const drafts = this.drafts();
    if (savedContent !== undefined && drafts[path]?.content !== savedContent) return;
    delete drafts[path];
    if (Object.keys(drafts).length) localStorage.setItem(this.draftKey, JSON.stringify(drafts));
    else localStorage.removeItem(this.draftKey);
  }

  private async metadata(id: string): Promise<{ file: DriveFile; etag?: string }> {
    const response = await driveFetch(this.transport, { path: `/drive/v3/files/${driveId(id)}`, query: { fields: DRIVE_FIELDS } });
    return { file: parseDriveJSON<DriveFile>(response), etag: response.etag };
  }

  private async assertInsideVault(file: DriveFile): Promise<void> {
    let current = file;
    const visited = new Set<string>();
    while (current.id !== this.selection.folderId) {
      if (current.trashed || visited.has(current.id) || visited.size >= 64 || current.parents?.length !== 1) {
        throw new Error("This item is no longer inside the selected Drive vault. Reload the vault before continuing.");
      }
      visited.add(current.id);
      current = (await this.metadata(current.parents[0])).file;
    }
    if (current.trashed) throw new Error("The Google Drive vault has been moved to trash.");
  }

  async validate(): Promise<void> {
    const { file } = await this.metadata(this.selection.folderId);
    if (file.trashed || file.mimeType !== DRIVE_FOLDER || !file.capabilities?.canAddChildren) {
      throw new Error("Choose a writable Google Drive folder for this vault.");
    }
  }

  private async index(refresh = false): Promise<void> {
    if (this.indexing) return this.indexing;
    if (this.loaded && !refresh) return;
    this.indexing = (async () => {
      await this.validate();
      const next = new Map<string, DriveFile>();
      const seen = new Set<string>();
      const walk = async (id: string, parent: string, depth: number): Promise<void> => {
        if (depth > 64 || seen.has(id)) throw new Error("The Google Drive folder tree is too deep or contains a cycle.");
        seen.add(id);
        const entries = await listDriveChildren(this.transport, id);
        for (const entry of entries) {
          // Google allows names that cannot be represented by a filesystem vault.
          if (entry.name.includes("/") || entry.name.includes("\\") || entry.name === "." || entry.name === "..") {
            throw new Error(`Rename “${entry.name}” in Google Drive before opening this vault.`);
          }
          const path = safePath(parent ? `${parent}/${entry.name}` : entry.name);
          if (next.has(path)) throw new Error(`Google Drive contains multiple items named “${path}”. Rename the duplicates before opening the vault.`);
          next.set(path, entry);
          // Shortcuts are deliberately not traversed outside the selected vault.
          if (entry.mimeType === DRIVE_FOLDER) await walk(entry.id, path, depth + 1);
        }
      };
      await walk(this.selection.folderId, "", 0);
      this.files = next;
      this.loaded = true;
    })();
    try { await this.indexing; } finally { this.indexing = null; }
  }

  private async lookup(path: string): Promise<DriveFile | undefined> {
    safePath(path);
    await this.index();
    return this.files.get(path);
  }

  async listNoteEntries(): Promise<VaultFileEntry[]> {
    await this.index(true);
    return [...this.files].filter(([path, file]) => {
      const parts = path.split("/");
      const hidden = parts.slice(0, -1).some((part, index) => part.startsWith(".") && !(index === 0 && part === TRASH_DIR));
      return !hidden && parts.length <= MAX_TYPE_DEPTH + 3 && /\.md$/i.test(path) && !file.mimeType.startsWith("application/vnd.google-apps.");
    }).map(([path, file]) => ({ path, createdAt: file.createdTime, updatedAt: file.modifiedTime ?? new Date(0).toISOString() }))
      .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt) || a.path.localeCompare(b.path));
  }

  async loadFiles(paths: string[]): Promise<VaultFile[]> {
    const files: VaultFile[] = [];
    // Bound network concurrency; mobile pagination supplies a small batch.
    for (let index = 0; index < paths.length; index += 4) {
      files.push(...await Promise.all(paths.slice(index, index + 4).map(async (path) => {
        const content = await this.readText(path);
        const file = this.files.get(path)!;
        return { path, content, createdAt: file.createdTime, updatedAt: file.modifiedTime ?? new Date(0).toISOString() };
      })));
    }
    return files;
  }
  async loadAll(): Promise<VaultFile[]> { return this.loadFiles((await this.listNoteEntries()).map((file) => file.path)); }
  async readText(path: string): Promise<string> { return new TextDecoder().decode(await this.readBinary(path)); }

  async readBinary(path: string): Promise<Uint8Array> {
    const item = await this.lookup(path);
    if (!item) throw new DriveError(404, `File not found: ${path}`);
    if (item.mimeType.startsWith("application/vnd.google-apps.")) throw new Error("Google Docs and shortcuts cannot be opened as vault files.");
    const before = await this.metadata(item.id);
    if (before.file.name !== item.name || JSON.stringify(before.file.parents) !== JSON.stringify(item.parents)) {
      throw new Error(`“${path}” moved in Google Drive. Reload the vault before continuing.`);
    }
    await this.assertInsideVault(before.file);
    const response = await driveFetch(this.transport, { path: `/drive/v3/files/${driveId(item.id)}`, query: { alt: "media" } });
    const after = await this.metadata(item.id);
    if (before.file.version !== after.file.version) throw new Error(`“${path}” changed while downloading. Retry opening it.`);
    this.files.set(path, after.file);
    this.readIds.add(item.id);
    return decodeDriveBytes(response.body);
  }

  async listFiles(path: string): Promise<string[]> {
    safePath(path, true);
    await this.index();
    const prefix = path ? `${path}/` : "";
    return [...this.files].filter(([key, file]) => key.startsWith(prefix) && file.mimeType !== DRIVE_FOLDER).map(([key]) => key).sort();
  }
  async listDirs(): Promise<string[]> {
    await this.index();
    return [...this.files].filter(([path, file]) => file.mimeType === DRIVE_FOLDER && path.split("/").length <= MAX_TYPE_DEPTH && !path.split("/").some((part) => part.startsWith("."))).map(([path]) => path).sort();
  }
  async exists(path: string): Promise<boolean> { return Boolean(await this.lookup(path)); }

  private mutate<T>(action: () => Promise<T>): Promise<T> {
    const task = this.mutations.then(action);
    this.mutations = task.catch(() => undefined);
    return task;
  }

  private async parent(path: string): Promise<string> {
    const parts = safePath(path).split("/");
    parts.pop();
    let id = this.selection.folderId;
    let relative = "";
    for (const part of parts) {
      relative = relative ? `${relative}/${part}` : part;
      const existing = await this.lookup(relative);
      if (existing && existing.mimeType !== DRIVE_FOLDER) throw new Error(`“${relative}” is not a folder.`);
      id = existing?.id ?? (await this.create(relative, id, DRIVE_FOLDER)).id;
    }
    return id;
  }

  private async create(path: string, parentId: string, mimeType: string, bytes?: Uint8Array): Promise<DriveFile> {
    await this.assertInsideVault((await this.metadata(parentId)).file);
    // Drive permits duplicate names. Check fresh siblings rather than trusting the index.
    const name = path.split("/").at(-1)!;
    if ((await listDriveChildren(this.transport, parentId)).some((file) => file.name === name)) {
      throw new Error(`“${path}” already exists in Google Drive. Reload before retrying.`);
    }
    const { ids } = parseDriveJSON<{ ids: string[] }>(await driveFetch(this.transport, { path: "/drive/v3/files/generateIds", query: { count: "1", space: "drive" } }));
    const metadata = { id: ids[0], name, parents: [parentId], mimeType };
    let response;
    if (bytes) {
      const boundary = `zerus_${crypto.randomUUID()}`;
      const head = new TextEncoder().encode(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}\r\n--${boundary}\r\nContent-Type: ${mimeType}\r\n\r\n`);
      const tail = new TextEncoder().encode(`\r\n--${boundary}--\r\n`);
      const body = new Uint8Array(head.length + bytes.length + tail.length);
      body.set(head); body.set(bytes, head.length); body.set(tail, head.length + bytes.length);
      response = await driveFetch(this.transport, { path: "/upload/drive/v3/files", method: "POST", query: { uploadType: "multipart", fields: DRIVE_FIELDS }, contentType: `multipart/related; boundary=${boundary}`, body: encodeDriveBytes(body) });
    } else {
      response = await driveFetch(this.transport, { path: "/drive/v3/files", method: "POST", query: { fields: DRIVE_FIELDS }, contentType: "application/json", body: driveJSON(metadata) });
    }
    const file = parseDriveJSON<DriveFile>(response);
    this.files.set(path, file);
    this.readIds.add(file.id);
    return file;
  }

  private async unchanged(path: string, item: DriveFile): Promise<string> {
    const current = lockedFile(await driveFetch(this.transport, { path: `/drive/v2/files/${driveId(item.id)}`, query: { fields: LOCK_FIELDS } }));
    await this.assertInsideVault(current.file);
    if (current.file.trashed || !item.version || current.file.version !== item.version) {
      throw new DriveError(412, `“${path}” changed in Google Drive. Your changes have not overwritten it. Copy your edit before reloading.`);
    }
    if (!current.etag) throw new Error("Google Drive did not provide a version lock. The file was left unchanged.");
    return current.etag;
  }

  private async put(path: string, bytes: Uint8Array, onlyNew = false): Promise<void> {
    const existing = await this.lookup(path);
    if (onlyNew && existing) throw new Error(`File already exists: ${path}`);
    if (!existing) {
      await this.create(path, await this.parent(path), "application/octet-stream", bytes);
      return;
    }
    if (existing.mimeType.startsWith("application/vnd.google-apps.")) throw new Error("Cannot overwrite a folder, Google document, or shortcut.");
    if (!this.readIds.has(existing.id)) throw new Error(`“${path}” has not been downloaded successfully. Reload before editing it.`);
    const etag = await this.unchanged(path, existing);
    const response = await driveFetch(this.transport, { path: `/upload/drive/v2/files/${driveId(existing.id)}`, method: "PUT", query: { uploadType: "media", fields: LOCK_FIELDS }, contentType: "application/octet-stream", body: encodeDriveBytes(bytes), ifMatch: etag });
    this.files.set(path, lockedFile(response).file);
  }
  write(path: string, content: string): Promise<void> { return this.writeBinary(path, new TextEncoder().encode(content)); }
  writeNew(path: string, content: string): Promise<void> { return this.mutate(() => this.put(path, new TextEncoder().encode(content), true)); }
  writeBinary(path: string, bytes: Uint8Array): Promise<void> { return this.mutate(() => this.put(path, bytes)); }
  mkDir(path: string): Promise<void> {
    return this.mutate(async () => {
      const existing = await this.lookup(path);
      if (existing?.mimeType === DRIVE_FOLDER) return;
      if (existing) throw new Error(`“${path}” is not a folder.`);
      await this.create(path, await this.parent(path), DRIVE_FOLDER);
    });
  }
  move(from: string, to: string): Promise<void> {
    return this.mutate(async () => {
      safePath(from); safePath(to);
      if (from === to) return;
      if (to.startsWith(`${from}/`)) throw new Error("Cannot move a folder into itself.");
      const item = await this.lookup(from);
      if (!item) throw new Error(`File not found: ${from}`);
      if (await this.lookup(to)) throw new Error(`File already exists: ${to}`);
      const parentId = await this.parent(to);
      if ((await listDriveChildren(this.transport, parentId)).some((file) => file.name === to.split("/").at(-1))) throw new Error(`File already exists: ${to}`);
      const response = await driveFetch(this.transport, { path: `/drive/v2/files/${driveId(item.id)}`, method: "PATCH", ifMatch: await this.unchanged(from, item), contentType: "application/json", body: driveJSON({ title: to.split("/").at(-1) }), query: { fields: LOCK_FIELDS, ...(item.parents?.includes(parentId) ? {} : { addParents: parentId, removeParents: (item.parents ?? []).join(",") }) } });
      this.files.delete(from);
      this.files.set(to, lockedFile(response).file);
      for (const [path, child] of [...this.files]) if (path.startsWith(`${from}/`)) { this.files.delete(path); this.files.set(`${to}${path.slice(from.length)}`, child); }
    });
  }
  renameDir(from: string, to: string): Promise<void> { return this.move(from, to); }
  private trash(path: string, directory: boolean): Promise<void> {
    return this.mutate(async () => {
      const item = await this.lookup(path);
      if (!item) return;
      if ((item.mimeType === DRIVE_FOLDER) !== directory) throw new Error("Unexpected file type.");
      await driveFetch(this.transport, { path: `/drive/v2/files/${driveId(item.id)}`, method: "PATCH", ifMatch: await this.unchanged(path, item), contentType: "application/json", body: driveJSON({ labels: { trashed: true } }) });
      for (const key of [...this.files.keys()]) if (key === path || key.startsWith(`${path}/`)) this.files.delete(key);
    });
  }
  removeFile(path: string): Promise<void> { return this.trash(path, false); }
  removeDir(path: string): Promise<void> { return this.trash(path, true); }
}
