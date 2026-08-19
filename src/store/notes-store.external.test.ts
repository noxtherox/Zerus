import {
  mkdtemp,
  mkdir,
  readFile,
  realpath,
  rm,
  stat as nodeStat,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  picked: null as string | string[] | null,
  invoke: vi.fn(),
  failWrites: new Set<string>(),
  writeNewGate: null as Promise<void> | null,
  readTextGatePath: null as string | null,
  readTextGate: null as Promise<void> | null,
  onReadTextGate: null as (() => void) | null,
  onCloseRequested: vi.fn().mockResolvedValue(() => {}),
  destroyWindow: vi.fn(),
  listen: vi.fn().mockResolvedValue(() => {}),
}));

vi.mock("@tauri-apps/api/core", () => ({
  invoke: mocks.invoke,
  isTauri: () => true,
}));

vi.mock("@tauri-apps/api/window", () => ({
  getCurrentWindow: () => ({
    onCloseRequested: mocks.onCloseRequested,
    destroy: mocks.destroyWindow,
  }),
}));

vi.mock("@tauri-apps/api/event", () => ({
  listen: mocks.listen,
}));

vi.mock("@tauri-apps/plugin-dialog", () => ({
  open: () => Promise.resolve(mocks.picked),
}));

vi.mock("@tauri-apps/plugin-fs", async () => {
  const fs = await import("node:fs/promises");
  return {
    exists: async (path: string) =>
      fs
        .access(path)
        .then(() => true)
        .catch(() => false),
    mkdir: (path: string, options?: { recursive?: boolean }) =>
      fs.mkdir(path, options),
    readDir: async (path: string) =>
      (await fs.readdir(path, { withFileTypes: true })).map((entry) => ({
        name: entry.name,
        isDirectory: entry.isDirectory(),
        isFile: entry.isFile(),
      })),
    readFile: async (path: string) => new Uint8Array(await fs.readFile(path)),
    readTextFile: async (path: string) => {
      const content = await fs.readFile(path, "utf8");
      if (path === mocks.readTextGatePath && mocks.readTextGate) {
        const gate = mocks.readTextGate;
        const onGate = mocks.onReadTextGate;
        mocks.readTextGatePath = null;
        mocks.readTextGate = null;
        mocks.onReadTextGate = null;
        onGate?.();
        await gate;
      }
      return content;
    },
    remove: (path: string, options?: { recursive?: boolean }) =>
      fs.rm(path, { force: true, recursive: options?.recursive ?? false }),
    rename: (from: string, to: string) => fs.rename(from, to),
    stat: async (path: string) => {
      const info = await fs.stat(path);
      return { mtime: info.mtime };
    },
    writeFile: (path: string, bytes: Uint8Array) => fs.writeFile(path, bytes),
    writeTextFile: (
      path: string,
      content: string,
      options?: { createNew?: boolean },
    ) => {
      if (mocks.failWrites.has(path))
        throw new Error("simulated write failure");
      return fs.writeFile(path, content, {
        encoding: "utf8",
        flag: options?.createNew ? "wx" : "w",
      });
    },
  };
});

vi.mock("@/utils/toast", () => ({ showError: vi.fn() }));

import {
  attachFileToNote,
  closeExternalNote,
  copyExternalNoteToVault,
  createNote,
  deleteNoteForever,
  getNotes,
  getNoteConflict,
  initStore,
  moveExternalNoteToVault,
  openDocumentPathsFromDesktop,
  openExternalNotes,
  prioritizeNoteLoad,
  refreshVaultFromDisk,
  revealNoteInDesktop,
  resolveNoteConflict,
  restoreNote,
  setNoteType,
  synchronizeDesktopFiles,
  switchDesktopVault,
  trashNote,
  updateNoteBody,
} from "./notes-store";
import { isExternalNote, noteTypePath } from "@/lib/note-utils";
import { getFileHubReference } from "@/lib/file-hubs";
import { getLinkHubReference, setLinkHubReference } from "@/lib/link-hubs";

const storage = new Map<string, string>();
vi.stubGlobal("localStorage", {
  getItem: (key: string) => storage.get(key) ?? null,
  setItem: (key: string, value: string) => storage.set(key, value),
  removeItem: (key: string) => storage.delete(key),
  clear: () => storage.clear(),
});

async function waitFor(
  check: () => boolean | Promise<boolean>,
  timeoutMs = 2_000,
) {
  const started = Date.now();
  while (!(await check())) {
    if (Date.now() - started > timeoutMs)
      throw new Error("Timed out waiting for store");
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

describe("external note store workflow", () => {
  let root: string;
  let vault: string;
  let firstPath: string;
  let secondPath: string;
  let missingPath: string;
  let startupSnapshotContent: string;

  beforeAll(async () => {
    root = await mkdtemp(join(tmpdir(), "zerus-external-test-"));
    root = await realpath(root);
    vault = join(root, "vault");
    firstPath = join(root, "one", "First external.md");
    secondPath = join(root, "two", "Second external.md");
    missingPath = join(root, "offline", "Temporarily unavailable.md");
    await Promise.all([
      mkdir(join(vault, "inbox"), { recursive: true }),
      mkdir(join(root, "one"), { recursive: true }),
      mkdir(join(root, "two"), { recursive: true }),
    ]);
    await Promise.all([
      writeFile(join(vault, "inbox", "Welcome.md"), "# Welcome\n", "utf8"),
      writeFile(join(vault, "inbox", "Later.md"), "# Later\n", "utf8"),
      writeFile(firstPath, "# First external\n", "utf8"),
      writeFile(secondPath, "# Second external\n", "utf8"),
    ]);
    storage.set("zerus.vaultPath", vault);
    storage.set(
      `zerus.startupCache.v1.${vault}`,
      JSON.stringify({
        version: 1,
        location: vault,
        notes: [
          {
            id: "cached-welcome",
            path: "inbox/Welcome.md",
            title: "Welcome from cache",
            snippet: "Available before the disk read finishes.",
            pinned: false,
            archived: false,
            updatedAt: new Date(0).toISOString(),
          },
          {
            id: "cached-later",
            path: "inbox/Later.md",
            title: "Later from cache",
            snippet: "Still waiting for its disk read.",
            pinned: false,
            archived: false,
            updatedAt: new Date(0).toISOString(),
          },
        ],
        extraTypes: [["inbox"]],
        schemas: {},
        typeIcons: {},
        fileLocations: [],
      }),
    );
    storage.set(
      "zerus.externalPaths",
      JSON.stringify([missingPath, join(vault, "inbox", "Welcome.md")]),
    );
    mocks.invoke.mockImplementation(
      async (command: string, args: Record<string, string>) => {
        if (command === "take_pending_open_files") return [];
        if (command === "canonicalize_path") return realpath(args.path);
        if (command === "write_new_vault_file") {
          const gate = mocks.writeNewGate;
          mocks.writeNewGate = null;
          if (gate) await gate;
          const target = join(args.root, args.relativePath);
          await mkdir(dirname(target), { recursive: true });
          await writeFile(target, args.content, {
            encoding: "utf8",
            flag: "wx",
          });
        }
        if (command === "copy_file_into_vault") {
          const target = join(args.root, args.relativeDirectory, args.fileName);
          await mkdir(dirname(target), { recursive: true });
          await writeFile(target, await readFile(args.source));
          return [args.relativeDirectory, args.fileName].filter(Boolean).join("/");
        }
      },
    );
    let releaseStartupRead!: () => void;
    mocks.readTextGatePath = join(vault, "inbox", "Later.md");
    mocks.readTextGate = new Promise<void>((resolve) => {
      releaseStartupRead = resolve;
    });
    initStore();
    await waitFor(() =>
      getNotes().some((note) => note.id === "cached-later"),
    );
    startupSnapshotContent = getNotes().find(
      (note) => note.id === "cached-later",
    )!.content;
    await waitFor(() => mocks.readTextGatePath === null);
    await prioritizeNoteLoad("cached-later");
    expect(
      getNotes().find((note) => note.id === "cached-later")?.content,
    ).toBe("# Later\n");
    await waitFor(() =>
      getNotes().some(
        (note) => note.id === "cached-welcome" && note.content === "# Welcome\n",
      ),
    );
    updateNoteBody(
      "cached-welcome",
      "# Welcome\n\nEdited safely while other notes were loading.\n",
    );
    releaseStartupRead();
    await waitFor(() =>
      getNotes().some(
        (note) =>
          note.path === "inbox/Later.md" && note.content === "# Later\n",
      ),
    );
    await waitFor(async () =>
      (await readFile(join(vault, "inbox", "Welcome.md"), "utf8")).includes(
        "Edited safely while other notes were loading.",
      ),
    );
  });

  afterAll(async () => {
    await rm(root, { recursive: true, force: true });
  });

  it("shows the cached note index before the first disk read finishes", () => {
    expect(startupSnapshotContent).toContain("Later from cache");
    expect(startupSnapshotContent).toContain("Still waiting for its disk read.");
  });

  it("opens, edits, reveals, closes, and moves files from different folders", async () => {
    expect(mocks.invoke).toHaveBeenCalledWith("cli_register_vault", {
      vaultPath: vault,
    });
    expect(
      getNotes().filter((note) => note.path === "inbox/Welcome.md"),
    ).toHaveLength(1);
    const vaultNote = getNotes().find(
      (note) => note.path === "inbox/Welcome.md",
    );
    expect(vaultNote).toBeDefined();

    let releaseStaleScan!: () => void;
    let staleScanStarted!: () => void;
    const staleScanBlocked = new Promise<void>((resolve) => {
      staleScanStarted = resolve;
    });
    mocks.readTextGatePath = join(vault, "inbox", "Welcome.md");
    mocks.readTextGate = new Promise<void>((resolve) => {
      releaseStaleScan = resolve;
    });
    mocks.onReadTextGate = staleScanStarted;
    const staleScan = synchronizeDesktopFiles();
    await staleScanBlocked;
    updateNoteBody(
      vaultNote!.id,
      "# Welcome\n\nWritten in Zerus while a disk scan was running.\n",
    );
    await waitFor(async () =>
      (await readFile(join(vault, "inbox", "Welcome.md"), "utf8")).includes(
        "Written in Zerus",
      ),
    );
    releaseStaleScan();
    await staleScan;
    expect(getNoteConflict(vaultNote!.id)).toBeNull();
    expect(getNotes().find((note) => note.id === vaultNote!.id)?.content).toContain(
      "Written in Zerus",
    );

    updateNoteBody(
      vaultNote!.id,
      "# Welcome\n\nStill editing while Zerus regains focus.\n",
    );
    await refreshVaultFromDisk();
    expect(getNoteConflict(vaultNote!.id)).toBeNull();
    expect(getNotes().find((note) => note.id === vaultNote!.id)?.content).toContain(
      "Still editing while Zerus regains focus.",
    );
    await waitFor(async () =>
      (await readFile(join(vault, "inbox", "Welcome.md"), "utf8")).includes(
        "Still editing while Zerus regains focus.",
      ),
    );

    await revealNoteInDesktop(vaultNote!.id);
    expect(mocks.invoke).toHaveBeenCalledWith("reveal_in_file_manager", {
      path: join(vault, "inbox", "Welcome.md"),
    });

    mocks.picked = join(vault, "inbox", "Welcome.md");
    await expect(openExternalNotes()).resolves.toEqual([vaultNote?.id]);

    mocks.picked = [firstPath, secondPath];
    const ids = await openExternalNotes();

    expect(ids).toHaveLength(2);
    const externalNotes = getNotes().filter(isExternalNote);
    expect(externalNotes.map((note) => note.externalPath)).toEqual([
      firstPath,
      secondPath,
    ]);
    expect(externalNotes.map(noteTypePath)).toEqual([[], []]);

    updateNoteBody(ids[0], "# First external\n\nEdited outside the vault.\n");
    await waitFor(async () =>
      (await readFile(firstPath, "utf8")).includes("Edited outside the vault."),
    );

    await writeFile(
      firstPath,
      "# First external\n\nChanged safely by an AI tool.\n",
      "utf8",
    );
    await synchronizeDesktopFiles();
    expect(getNotes().find((note) => note.id === ids[0])?.content).toContain(
      "Changed safely by an AI tool.",
    );

    updateNoteBody(
      ids[0],
      "# First external\n\nUnsaved change currently shown in Zerus.\n",
    );
    await writeFile(
      firstPath,
      "# First external\n\nSimultaneous change from disk.\n",
      "utf8",
    );
    await waitFor(() => getNoteConflict(ids[0]) !== null);
    expect(await readFile(firstPath, "utf8")).toContain(
      "Simultaneous change from disk.",
    );
    expect(getNoteConflict(ids[0])?.currentContent).toContain(
      "Unsaved change currently shown in Zerus.",
    );
    await resolveNoteConflict(ids[0], "disk");
    expect(getNotes().find((note) => note.id === ids[0])?.content).toContain(
      "Simultaneous change from disk.",
    );

    await revealNoteInDesktop(ids[0]);
    expect(mocks.invoke).toHaveBeenCalledWith("reveal_in_file_manager", {
      path: firstPath,
    });

    updateNoteBody(ids[1], "# Second external\n\nUnsaved edit.\n");
    mocks.failWrites.add(secondPath);
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    await closeExternalNote(ids[1]);
    expect(errorSpy).toHaveBeenCalled();
    errorSpy.mockRestore();
    expect(getNotes().some((note) => note.id === ids[1])).toBe(true);
    mocks.failWrites.delete(secondPath);
    await closeExternalNote(ids[1]);
    expect(getNotes().some((note) => note.id === ids[1])).toBe(false);
    await expect(nodeStat(secondPath)).resolves.toBeDefined();
    await expect(readFile(secondPath, "utf8")).resolves.toContain(
      "Unsaved edit.",
    );

    const copied = await copyExternalNoteToVault(ids[0], ["copies"]);
    expect(copied).not.toBeNull();
    expect(copied?.id).not.toBe(ids[0]);
    expect(copied?.externalPath).toBeUndefined();
    expect(copied && noteTypePath(copied)).toEqual(["copies"]);
    expect(getNotes().find((note) => note.id === ids[0])?.externalPath).toBe(
      firstPath,
    );
    await expect(nodeStat(firstPath)).resolves.toBeDefined();
    await expect(
      readFile(join(vault, "copies", "First external.md"), "utf8"),
    ).resolves.toContain("Simultaneous change from disk.");

    await expect(
      moveExternalNoteToVault(ids[0], ["..", "outside"]),
    ).resolves.toBe(false);
    await expect(nodeStat(firstPath)).resolves.toBeDefined();
    await mkdir(join(vault, "research"), { recursive: true });
    await writeFile(
      join(vault, "research", "First external.md"),
      "# Unrelated file\n",
      "utf8",
    );
    let releaseWriteNew!: () => void;
    mocks.writeNewGate = new Promise<void>((resolve) => {
      releaseWriteNew = resolve;
    });
    const move = moveExternalNoteToVault(ids[0], ["research"]);
    await waitFor(() =>
      mocks.invoke.mock.calls.some(
        ([command]) => command === "write_new_vault_file",
      ),
    );
    updateNoteBody(
      ids[0],
      "# First external\n\nLate edit must not be accepted.\n",
    );
    expect(
      getNotes().find((note) => note.id === ids[0])?.content,
    ).not.toContain("Late edit must not be accepted.");
    releaseWriteNew();
    await expect(move).resolves.toBe(true);
    const moved = getNotes().find((note) => note.id === ids[0]);
    expect(moved?.externalPath).toBeUndefined();
    expect(moved && noteTypePath(moved)).toEqual(["research"]);
    await expect(nodeStat(firstPath)).rejects.toThrow();
    await expect(
      readFile(join(vault, "research", "First external 2.md"), "utf8"),
    ).resolves.toContain("Simultaneous change from disk.");
    await expect(
      readFile(join(vault, "research", "First external.md"), "utf8"),
    ).resolves.toBe("# Unrelated file\n");

    updateNoteBody(ids[0], "# First external\n\nSaved during shutdown.\n");
    expect(mocks.onCloseRequested).toHaveBeenCalledOnce();
    const closeHandler = mocks.onCloseRequested.mock
      .calls[0][0] as unknown as (event: {
      preventDefault: () => void;
    }) => Promise<void>;
    const preventDefault = vi.fn();
    await closeHandler({ preventDefault });
    expect(preventDefault).toHaveBeenCalledOnce();
    expect(mocks.destroyWindow).toHaveBeenCalledOnce();
    await expect(
      readFile(join(vault, "research", "First external 2.md"), "utf8"),
    ).resolves.toContain("Saved during shutdown.");

    expect(JSON.parse(storage.get("zerus.externalPaths") ?? "[]")).toEqual([
      missingPath,
    ]);
  });

  it("keeps linked sources untouched and manages copied documents with their hub", async () => {
    const document = join(root, "one", "Product Walkthrough.mp4");
    await writeFile(document, "video bytes");

    const linked = await createNote(["inbox"], "# Linked video\n\nContext\n");
    expect(linked).toBeDefined();
    await expect(attachFileToNote(linked!.id, document, "local")).resolves.toEqual({
      status: "attached",
      noteId: linked!.id,
    });
    expect(getFileHubReference(getNotes().find((note) => note.id === linked!.id)!)).toMatchObject({
      name: "Product Walkthrough.mp4",
      kind: "local",
      managed: false,
    });
    await setNoteType(linked!.id, ["research"]);
    await trashNote(linked!.id);
    await restoreNote(linked!.id);
    await expect(readFile(document, "utf8")).resolves.toBe("video bytes");

    const managedDocument = join(root, "two", "Quarterly Review.pptx");
    await writeFile(managedDocument, "managed presentation bytes");
    const managed = await createNote(["inbox"], "# Managed presentation\n");
    expect(managed).toBeDefined();
    await expect(attachFileToNote(managed!.id, managedDocument, "copy")).resolves.toEqual({
      status: "attached",
      noteId: managed!.id,
    });
    let managedNote = getNotes().find((note) => note.id === managed!.id)!;
    expect(getFileHubReference(managedNote)).toMatchObject({
      kind: "vault",
      path: "inbox/Quarterly Review.pptx",
      managed: true,
    });
    await setNoteType(managed!.id, ["research"]);
    managedNote = getNotes().find((note) => note.id === managed!.id)!;
    expect(getFileHubReference(managedNote)?.path).toBe("research/Quarterly Review.pptx");
    await expect(nodeStat(join(vault, "research", "Quarterly Review.pptx"))).resolves.toBeDefined();
    await trashNote(managed!.id);
    managedNote = getNotes().find((note) => note.id === managed!.id)!;
    expect(getFileHubReference(managedNote)?.path).toBe(
      ".trash/research/Quarterly Review.pptx",
    );
    await restoreNote(managed!.id);
    await deleteNoteForever(managed!.id);
    await expect(nodeStat(join(vault, "research", "Quarterly Review.pptx"))).rejects.toThrow();
    await expect(readFile(document, "utf8")).resolves.toBe("video bytes");
    await expect(readFile(managedDocument, "utf8")).resolves.toBe(
      "managed presentation bytes",
    );
  });

  it("keeps desktop-opened files linked until the user copies one into the vault", async () => {
    const presentation = join(root, "one", "Automatic Import.pptx");
    await writeFile(presentation, "presentation bytes");

    const ids = await openDocumentPathsFromDesktop([presentation]);

    expect(ids).toHaveLength(1);
    const imported = getNotes().find((note) => note.id === ids[0]);
    expect(imported).toBeDefined();
    expect(getFileHubReference(imported!)).toMatchObject({
      name: "Automatic Import.pptx",
      kind: "local",
      managed: false,
    });

    await expect(
      attachFileToNote(imported!.id, presentation, "copy"),
    ).resolves.toEqual({ status: "attached", noteId: imported!.id });
    const copiedNote = getNotes().find((note) => note.id === imported!.id)!;
    expect(getFileHubReference(copiedNote)).toMatchObject({
      name: "Automatic Import.pptx",
      kind: "vault",
      path: "inbox/Automatic Import.pptx",
      managed: true,
    });
    await expect(
      readFile(join(vault, "inbox", "Automatic Import.pptx"), "utf8"),
    ).resolves.toBe("presentation bytes");
    await expect(readFile(presentation, "utf8")).resolves.toBe(
      "presentation bytes",
    );

    await synchronizeDesktopFiles();
    expect(getNotes().find((note) => note.id === ids[0])).toBeDefined();
  });

  it("switches vaults without discarding an unresolved conflict", async () => {
    const originalVault = storage.get("zerus.vaultPath") as string;
    const otherVault = join(root, "other-vault");
    await mkdir(join(otherVault, "inbox"), { recursive: true });
    await writeFile(
      join(otherVault, "inbox", "Other.md"),
      "# Other vault\n",
      "utf8",
    );

    const note = getNotes().find(
      (candidate) => candidate.path === "inbox/Welcome.md",
    );
    expect(note).toBeDefined();
    updateNoteBody(
      note!.id,
      `${note!.content}\nLocal version awaiting review.\n`,
    );
    const localContent = getNotes().find(
      (candidate) => candidate.id === note!.id,
    )!.content;
    await writeFile(
      join(originalVault, note!.path),
      `${note!.content}\nChanged on disk.\n`,
      "utf8",
    );
    await waitFor(() => getNoteConflict(note!.id) !== null);

    await expect(switchDesktopVault(otherVault)).resolves.toBe(true);
    expect(getNotes().some((candidate) => candidate.path === "inbox/Other.md")).toBe(true);

    const closeHandler = mocks.onCloseRequested.mock
      .calls[0][0] as unknown as (event: {
      preventDefault: () => void;
    }) => Promise<void>;
    const destroyCount = mocks.destroyWindow.mock.calls.length;
    await closeHandler({ preventDefault: vi.fn() });
    expect(mocks.destroyWindow).toHaveBeenCalledTimes(destroyCount);

    await expect(switchDesktopVault(originalVault)).resolves.toBe(true);
    const restored = getNotes().find((candidate) => candidate.path === note!.path);
    expect(restored?.content).toBe(localContent);
    expect(restored && getNoteConflict(restored.id)?.currentContent).toBe(localContent);
    await resolveNoteConflict(restored!.id, "disk");
  });

  it("does not duplicate a legacy typed link during repeated desktop syncs", async () => {
    const url = "https://example.com/legacy-link";
    const path = join(vault, "inbox", "Legacy link.md");
    await writeFile(
      path,
      setLinkHubReference("# Legacy link\n", { id: "legacy-link", url }),
      "utf8",
    );

    await synchronizeDesktopFiles();
    await synchronizeDesktopFiles();

    expect(
      getNotes().filter((note) => getLinkHubReference(note)?.url === url),
    ).toHaveLength(1);
  });
});
