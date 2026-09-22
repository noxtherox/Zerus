import { afterEach, describe, expect, it, vi } from "vitest";
import { DriveDuplicateError, GoogleDriveVault } from "./google-drive";
import { DRIVE_FOLDER, DriveError, decodeDriveBytes, driveJSON, encodeDriveBytes, isDriveSignInExpired, listDriveChildren, type DriveFile, type DriveRequest, type DriveResponse, type DriveTransport } from "@/lib/google-drive";

function fixture() {
  const files = new Map<string, DriveFile>([
    ["vault", { id: "vault", name: "Zerus", mimeType: DRIVE_FOLDER, version: "1", capabilities: { canAddChildren: true } }],
    ["folder", { id: "folder", name: "Notes", parents: ["vault"], mimeType: DRIVE_FOLDER, version: "1" }],
    ["note", { id: "note", name: "Hello.md", parents: ["folder"], mimeType: "text/markdown", version: "1", modifiedTime: "2026-01-01T00:00:00Z" }],
  ]);
  const content = new Map<string, Uint8Array>([["note", new TextEncoder().encode("# Hello\nOriginal")]]);
  const calls: DriveRequest[] = [];
  let generated = 0;
  let rejectWrite = false;
  const json = (value: unknown, status = 200, etag?: string): DriveResponse => ({ status, body: driveJSON(value), etag });
  const transport: DriveTransport = async (request) => {
    calls.push(request);
    if (request.path.endsWith("/generateIds")) return json({ ids: [`new${++generated}`] });
    if (request.path === "/drive/v3/files" && !request.method) {
      const parent = request.query!.q.split("'")[1];
      return json({ files: [...files.values()].filter((file) => file.parents?.includes(parent) && !file.trashed) });
    }
    if (request.method === "POST") {
      const body = new TextDecoder().decode(decodeDriveBytes(request.body!));
      const metadata = request.path.startsWith("/upload") ? JSON.parse(body.split("\r\n\r\n")[1].split("\r\n--")[0]) : JSON.parse(body);
      const file = { ...metadata, version: "1" } as DriveFile;
      files.set(file.id, file);
      return json(file);
    }
    const id = request.path.split("/").at(-1)!;
    const file = files.get(id);
    if (!file) return json({}, 404);
    const v2File = () => ({ id: file.id, title: file.name, mimeType: file.mimeType, parents: file.parents?.map((id) => ({ id })), version: file.version, modifiedDate: file.modifiedTime, labels: { trashed: file.trashed }, etag: `"${file.version}"` });
    if (request.method === "PATCH" || request.method === "PUT") {
      if (rejectWrite || request.ifMatch !== `"${file.version}"`) return json({}, 412);
      if (request.query?.uploadType === "media") content.set(id, decodeDriveBytes(request.body!));
      else {
        const metadata = JSON.parse(new TextDecoder().decode(decodeDriveBytes(request.body!)));
        if (metadata.title) file.name = metadata.title;
        if (metadata.labels) file.trashed = metadata.labels.trashed;
      }
      if (request.query?.addParents) file.parents = [request.query.addParents];
      file.version = String(Number(file.version) + 1);
      return json(request.path.includes("/v2/") ? v2File() : { ...file });
    }
    if (request.query?.alt === "media") return { status: 200, body: encodeDriveBytes(content.get(id)!), etag: `"${file.version}"` };
    return json(request.path.includes("/v2/") ? v2File() : { ...file });
  };
  const vault = new GoogleDriveVault({ accountId: "account", email: "test@example.com", folderId: "vault", name: "Zerus" }, transport);
  return { vault, transport, files, content, calls, rejectWrite: () => { rejectWrite = true; } };
}

describe("Google Drive vault", () => {
  afterEach(() => vi.unstubAllGlobals());
  it("recognizes expired credentials that require interactive reconnection", () => {
    expect(isDriveSignInExpired(new DriveError(401, "Google Drive sign-in expired. Reconnect your account."))).toBe(true);
    expect(isDriveSignInExpired("Google Drive sign-in expired. Disconnect and reconnect your account.")).toBe(true);
    expect(isDriveSignInExpired(new DriveError(429, "Google Drive is busy."))).toBe(false);
  });
  it("looks up exact names and reuses known folders when opening another note", async () => {
    const { vault, files, content, calls } = fixture();
    files.set("second", { id: "second", name: "Second.md", parents: ["folder"], mimeType: "text/markdown", version: "1" });
    content.set("second", new TextEncoder().encode("# Second\nComplete body"));
    await vault.readText("Notes/Hello.md");
    const before = calls.length;
    await vault.readText("Notes/Second.md");
    const lookups = calls.slice(before).filter((request) => request.query?.q);
    expect(lookups).toHaveLength(1);
    expect(lookups[0].query?.q).toContain("name = 'Second.md'");
  });

  it("opens a known note while an unrelated folder scan is stalled", async () => {
    const source = fixture();
    source.files.set("slow", { id: "slow", name: "Slow", parents: ["vault"], mimeType: DRIVE_FOLDER, version: "1" });
    let release!: (value: DriveResponse) => void;
    const stalled = new Promise<DriveResponse>((resolve) => { release = resolve; });
    const transport: DriveTransport = (request) => request.query?.q?.includes("'slow'")
      ? stalled : source.transport(request);
    const vault = new GoogleDriveVault(source.vault.selection, transport);
    const scan = vault.listNoteEntries();
    const note = await vault.loadFiles(["Notes/Hello.md"]);
    expect(note[0].content).toBe("# Hello\nOriginal");
    release({ status: 200, body: driveJSON({ files: [] }) });
    await scan;
  });
  it("recovers pending edits per account and vault without clearing a newer edit", () => {
    const data = new Map<string, string>();
    vi.stubGlobal("localStorage", { getItem: (key: string) => data.get(key) ?? null, setItem: (key: string, value: string) => data.set(key, value), removeItem: (key: string) => data.delete(key) });
    const { vault } = fixture();
    vault.stageDraft("Notes/Hello.md", "First edit", "Original");
    vault.stageDraft("Notes/Hello.md", "Second edit", "Changed elsewhere");
    vault.clearDraft("Notes/Hello.md", "First edit");
    const restored = fixture().vault;
    expect(restored.drafts()).toEqual({ "Notes/Hello.md": { content: "Second edit", snapshot: "Original" } });
    const other = new GoogleDriveVault({ ...vault.selection, accountId: "another-account" });
    expect(other.drafts()).toEqual({});
    restored.clearDraft("Notes/Hello.md", "Second edit");
    expect(restored.drafts()).toEqual({});
  });
  it("does not overwrite a config file whose contents were never downloaded", async () => {
    const { vault, calls } = fixture();
    await vault.listNoteEntries();
    await expect(vault.write("Notes/Hello.md", "Default after a failed load")).rejects.toThrow("not been downloaded");
    expect(calls.some((call) => call.method === "PATCH" || call.method === "PUT")).toBe(false);
  });
  it("saves UTF-8 using the v2 JSON ETag when v3 metadata has no ETag", async () => {
    const { vault, calls, content } = fixture();
    expect(await vault.listDirs()).toEqual(["Notes"]);
    expect(await vault.loadAll()).toMatchObject([{ path: "Notes/Hello.md", content: "# Hello\nOriginal" }]);
    await vault.write("Notes/Hello.md", "# Olá 👋");
    expect(new TextDecoder().decode(content.get("note"))).toBe("# Olá 👋");
    expect(calls.find((call) => call.method === "PUT")?.ifMatch).toBe('"1"');
  });
  it("does not overwrite a version changed by another device", async () => {
    const { vault, files, calls } = fixture();
    await vault.readText("Notes/Hello.md");
    files.get("note")!.version = "2";
    await expect(vault.write("Notes/Hello.md", "Local edit")).rejects.toThrow("changed in Google Drive");
    expect(calls.some((call) => call.method === "PATCH" || call.method === "PUT")).toBe(false);
  });
  it("does not follow a folder that was moved outside the selected vault", async () => {
    const { vault, files, calls } = fixture();
    await vault.readText("Notes/Hello.md");
    files.set("outside", { id: "outside", name: "Other", mimeType: DRIVE_FOLDER, version: "1" });
    files.get("folder")!.parents = ["outside"];
    await expect(vault.write("Notes/Hello.md", "Edit")).rejects.toThrow("no longer inside");
    expect(calls.some((call) => call.method === "PATCH" || call.method === "PUT")).toBe(false);
  });
  it("surfaces a concurrent change between checking the version and uploading", async () => {
    const { vault, rejectWrite, content } = fixture();
    await vault.readText("Notes/Hello.md");
    rejectWrite();
    await expect(vault.write("Notes/Hello.md", "Local edit")).rejects.toThrow("not uploaded");
    expect(new TextDecoder().decode(content.get("note"))).toContain("Original");
  });
  it("rejects duplicate Drive names instead of selecting an arbitrary file", async () => {
    const { vault, files } = fixture();
    files.set("duplicate", { ...files.get("note")!, id: "duplicate" });
    await expect(vault.loadAll()).rejects.toThrow("multiple items");
  });
  it("reviews all copies by ID and preserves their contents while resolving names", async () => {
    const { vault, files, content, calls } = fixture();
    for (const id of ["duplicate", "third"]) {
      files.set(id, { ...files.get("note")!, id });
      content.set(id, new TextEncoder().encode(`Body of ${id}`));
    }
    const conflict = await vault.listNoteEntries().catch((error) => error) as DriveDuplicateError;
    expect(conflict).toBeInstanceOf(DriveDuplicateError);
    expect(conflict.items.map((item) => item.id)).toEqual(["note", "duplicate", "third"]);
    expect(await vault.previewDuplicate(conflict, "duplicate")).toBe("Body of duplicate");
    await vault.renameDuplicate(conflict, "duplicate", "Hello (other).md");
    expect(calls.find((call) => call.method === "PATCH")).toMatchObject({ path: "/drive/v2/files/duplicate", ifMatch: '"1"' });
    const remaining = await vault.listNoteEntries().catch((error) => error) as DriveDuplicateError;
    expect(remaining.items.map((item) => item.id)).toEqual(["note", "third"]);
    await vault.renameDuplicate(remaining, "third", "Hello (third).md");
    expect((await vault.loadAll()).map((item) => item.content).sort()).toEqual(["# Hello\nOriginal", "Body of duplicate", "Body of third"].sort());
  });
  it("rejects stale, moved, unreviewed, invalid and colliding duplicate renames", async () => {
    const { vault, files, calls } = fixture();
    files.set("duplicate", { ...files.get("note")!, id: "duplicate" });
    const conflict = await vault.listNoteEntries().catch((error) => error) as DriveDuplicateError;
    await expect(vault.renameDuplicate(conflict, "other", "Other.md")).rejects.toThrow("not part");
    await expect(vault.renameDuplicate(conflict, "duplicate", "../Other.md")).rejects.toThrow("filename");
    files.set("occupied", { ...files.get("note")!, id: "occupied", name: "Other.md" });
    await expect(vault.renameDuplicate(conflict, "duplicate", "Other.md")).rejects.toThrow("already exists");
    files.get("duplicate")!.version = "2";
    await expect(vault.renameDuplicate(conflict, "duplicate", "New.md")).rejects.toThrow("changed");
    files.get("duplicate")!.version = "1";
    files.get("duplicate")!.parents = ["vault"];
    await expect(vault.renameDuplicate(conflict, "duplicate", "New.md")).rejects.toThrow("changed");
    expect(calls.some((call) => call.method === "PATCH")).toBe(false);
  });
  it("honors the version lock when a reviewed copy changes just before renaming", async () => {
    const { vault, files, rejectWrite } = fixture();
    files.set("duplicate", { ...files.get("note")!, id: "duplicate" });
    const conflict = await vault.listNoteEntries().catch((error) => error) as DriveDuplicateError;
    rejectWrite();
    await expect(vault.renameDuplicate(conflict, "duplicate", "Other.md")).rejects.toThrow("not uploaded");
    expect(files.get("duplicate")!.name).toBe("Hello.md");
  });
  it("can resolve duplicate folders without losing their descendants", async () => {
    const { vault, files } = fixture();
    files.set("secondFolder", { ...files.get("folder")!, id: "secondFolder" });
    const conflict = await vault.listNoteEntries().catch((error) => error) as DriveDuplicateError;
    expect(conflict.path).toBe("Notes");
    await vault.renameDuplicate(conflict, "secondFolder", "Other Notes");
    expect(await vault.listDirs()).toEqual(["Notes", "Other Notes"]);
    expect(await vault.readText("Notes/Hello.md")).toContain("Original");
  });
  it("creates parents and uploads new files in a single multipart creation", async () => {
    const { vault, calls } = fixture();
    await vault.writeNew("Ideas/Another.md", "# Another");
    expect(await vault.exists("Ideas/Another.md")).toBe(true);
    expect(calls.filter((call) => call.method === "POST")).toHaveLength(2);
    expect(calls.filter((call) => call.path.endsWith("generateIds"))).toHaveLength(2);
    await expect(vault.writeNew("Ideas/Another.md", "Replace")).rejects.toThrow("already exists");
  });
  it("refuses a new file if another device created that name since indexing", async () => {
    const { vault, files, calls } = fixture();
    await vault.listDirs();
    files.set("other", { id: "other", name: "New.md", mimeType: "text/markdown", parents: ["folder"], version: "1" });
    await expect(vault.writeNew("Notes/New.md", "# New")).rejects.toThrow("already exists");
    expect(calls.some((call) => call.method === "POST")).toBe(false);
  });
  it("renames folders and updates descendant paths", async () => {
    const { vault } = fixture();
    await vault.renameDir("Notes", "Writing");
    expect(await vault.exists("Notes/Hello.md")).toBe(false);
    expect(await vault.readText("Writing/Hello.md")).toContain("Original");
  });
  it("uses recoverable Drive trash for removal", async () => {
    const { vault, files } = fixture();
    await vault.removeDir("Notes");
    expect(files.get("folder")!.trashed).toBe(true);
    expect(await vault.exists("Notes/Hello.md")).toBe(false);
  });
  it("rejects traversal and moving a folder inside itself", async () => {
    const { vault, calls } = fixture();
    await expect(vault.write("../outside.md", "bad")).rejects.toThrow("Invalid vault path");
    await expect(vault.renameDir("Notes", "Notes/Nested")).rejects.toThrow("itself");
    expect(calls).toHaveLength(0);
  });
  it("fails closed when Drive cannot supply a version lock", async () => {
    const { transport } = fixture();
    const vault = new GoogleDriveVault({ accountId: "account", email: "test@example.com", folderId: "vault", name: "Zerus" }, async (request) => {
      const response = await transport(request);
      if (request.path.includes("/v2/")) {
        const value = JSON.parse(new TextDecoder().decode(decodeDriveBytes(response.body)));
        delete value.etag;
        response.body = driveJSON(value);
      }
      return { ...response, etag: undefined };
    });
    await vault.readText("Notes/Hello.md");
    await expect(vault.write("Notes/Hello.md", "Edit")).rejects.toThrow("version lock");
  });
  it("follows Drive pagination", async () => {
    const tokens: Array<string | undefined> = [];
    const files = await listDriveChildren(async (request) => {
      tokens.push(request.query?.pageToken);
      return { status: 200, body: driveJSON(request.query?.pageToken ? { files: [{ id: "two" }] } : { files: [{ id: "one" }], nextPageToken: "next" }) };
    }, "vault");
    expect(tokens).toEqual([undefined, "next"]);
    expect(files.map((file) => file.id)).toEqual(["one", "two"]);
  });
  it("scans independent Drive folders concurrently with a bounded request count", async () => {
    let active = 0;
    let maximumActive = 0;
    const folders: DriveFile[] = Array.from({ length: 8 }, (_, index) => ({
      id: `folder${index}`,
      name: `Folder ${index}`,
      parents: ["vault"],
      mimeType: DRIVE_FOLDER,
      version: "1",
    }));
    const transport: DriveTransport = async (request) => {
      if (request.path !== "/drive/v3/files") {
        return { status: 200, body: driveJSON({ id: "vault", name: "Zerus", mimeType: DRIVE_FOLDER, capabilities: { canAddChildren: true } }) };
      }
      const parent = request.query!.q.split("'")[1];
      active += 1;
      maximumActive = Math.max(maximumActive, active);
      await new Promise((resolve) => setTimeout(resolve, 5));
      active -= 1;
      return { status: 200, body: driveJSON({ files: parent === "vault" ? folders : [] }) };
    };
    const vault = new GoogleDriveVault({ accountId: "account", email: "test@example.com", folderId: "vault", name: "Zerus" }, transport);
    expect(await vault.listDirs()).toHaveLength(8);
    expect(maximumActive).toBe(4);
  });
});
