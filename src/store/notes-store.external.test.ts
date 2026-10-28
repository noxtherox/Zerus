import { getBacklinksGroupedByType } from "@/lib/links";
import { getNoteProperties } from "@/lib/frontmatter";
import { defaultTypeViewConfig } from "@/lib/note-views";
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
import { basename, dirname, extname, join, normalize } from "node:path";
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
  watch: vi.fn().mockResolvedValue(() => {}),
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
      // DesktopVault can join a native Windows root with slash-separated note paths.
      if (mocks.readTextGatePath !== null && normalize(path) === normalize(mocks.readTextGatePath) && mocks.readTextGate) {
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
      return {
        mtime: info.mtime,
        isFile: info.isFile(),
        isDirectory: info.isDirectory(),
      };
    },
    watch: mocks.watch,
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
  addTypeProperty,
  setNoteProperty,
  attachFileToNote,
  closeExternalNote,
  copyExternalNoteToVault,
  createNote,
  createFileNote,
  getFileHubStatus,
  duplicateNote,
  toggleNoteArchived,
  deleteNoteForever,
  deleteTypeViewPreset,
  flushPendingWrites,
  getNotes,
  getPropertySchemas,
  getNoteConflict,
  initStore,
  moveExternalNoteToVault,
  moveNotesToType,
  openDocumentPathsFromDesktop,
  openExternalNotes,
  prioritizeNoteLoad,
  refreshVaultFromDisk,
  revealNoteInDesktop,
  resolveNoteConflict,
  restoreNote,
  savePastedImage,
  saveTypeViewPreset,
  setNoteType,
  synchronizeDesktopFiles,
  switchDesktopVault,
  trashNote,
  updateTypeProperty,
  updateNoteBody,
  updateTypeView,
} from "./notes-store";
import { isExternalNote, noteReference, noteReferenceMatches, noteTypePath, noteTitle } from "@/lib/note-utils";
import { getNoteAttachments } from "@/lib/note-attachments";
import { getFileHubReference } from "@/lib/file-hubs";
import { getLinkHubReference, setLinkHubReference } from "@/lib/link-hubs";
import { setZerusState } from "@/lib/zerus-metadata";

import { executeBulkAction, previewBulkAction, transitionBulkAction } from "@/lib/bulk-note-actions";

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
        version: 2,
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
          const directory = join(args.root, args.relativeDirectory);
          const extension = extname(args.fileName);
          const stem = basename(args.fileName, extension);
          await nodeStat(directory);
          for (let index = 0; ; index += 1) {
            const fileName = `${stem}${index === 0 ? "" : ` ${index + 1}`}${extension}`;
            const target = join(directory, fileName);
            try {
              await writeFile(target, await readFile(args.source), { flag: "wx" });
              return [args.relativeDirectory, fileName].filter(Boolean).join("/");
            } catch (error) {
              if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
            }
          }
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
    // Finish the save before the original startup scan is allowed to finish.
    // Its older copy must not replace either this edit or its saved baseline.
    expect(await flushPendingWrites()).toBe(true);
    releaseStartupRead();
    await waitFor(() =>
      getNotes().some(
        (note) =>
          note.path === "inbox/Later.md" && note.content === "# Later\n",
      ),
    );
    await waitFor(() => mocks.watch.mock.calls.length > 0);
    expect(getNotes().find((note) => note.id === "cached-welcome")?.content)
      .toContain("Edited safely while other notes were loading.");
    await flushPendingWrites();
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

  it("keeps complete note bodies in the next-launch cache", () => {
    const cached = JSON.parse(storage.get(`zerus.startupCache.v1.${vault}`) ?? "null");
    expect(cached.notes.find((note: { path: string }) =>
      note.path === "inbox/Welcome.md",
    )?.content).toContain("Edited safely while other notes were loading.");
  });

  it("gives concurrently saved chat images distinct files", async () => {
    const images = [
      new Uint8Array([1, 1, 1]),
      new Uint8Array([2, 2, 2]),
      new Uint8Array([3, 3, 3]),
      new Uint8Array([4, 4, 4]),
    ];

    const paths = await Promise.all(
      images.map((bytes) => savePastedImage(bytes, "image/jpeg")),
    );

    expect(new Set(paths).size).toBe(images.length);
    await Promise.all(
      paths.map(async (path, index) => {
        expect(path).not.toBeNull();
        await expect(readFile(join(vault, path!))).resolves.toEqual(
          Buffer.from(images[index]),
        );
      }),
    );
  });

  it("watches the desktop vault recursively instead of polling it every second", async () => {
    await waitFor(() => mocks.watch.mock.calls.length > 0);
    expect(mocks.watch).toHaveBeenCalledWith(
      vault,
      expect.any(Function),
      { recursive: true, delayMs: 500 },
    );
  });

  it("reflects archive metadata changed by the CLI during desktop sync", async () => {
    const note = getNotes().find(
      (candidate) => candidate.path === "inbox/Welcome.md",
    );
    expect(note).toBeDefined();
    const path = join(vault, note!.path);

    await writeFile(path, setZerusState(note!.content, { archived: true }));
    await synchronizeDesktopFiles();
    expect(getNotes().find((candidate) => candidate.id === note!.id)?.archived)
      .toBe(true);

    const archivedContent = await readFile(path, "utf8");
    await writeFile(path, setZerusState(archivedContent, { archived: false }));
    await synchronizeDesktopFiles();
    expect(getNotes().find((candidate) => candidate.id === note!.id)?.archived)
      .toBe(false);
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
    try {
      const saved = await flushPendingWrites();
      expect(saved, JSON.stringify({
        note: getNotes().find((note) => note.id === vaultNote!.id),
        conflict: getNoteConflict(vaultNote!.id),
      })).toBe(true);
      expect(await readFile(join(vault, "inbox", "Welcome.md"), "utf8")).toContain("Written in Zerus");
    } finally {
      releaseStaleScan();
      await staleScan;
    }
    expect(getNoteConflict(vaultNote!.id)).toBeNull();
    expect(getNotes().find((note) => note.id === vaultNote!.id)?.content).toContain(
      "Written in Zerus",
    );

    updateNoteBody(
      vaultNote!.id,
      "# Welcome\n\nStill editing while Zerus regains focus.\n",
    );
    await refreshVaultFromDisk();
    await flushPendingWrites();
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
    const revealCalls = mocks.invoke.mock.calls.filter(
      ([command]) => command === "reveal_in_file_manager",
    );
    expect(revealCalls).toHaveLength(1);
    expect(normalize(revealCalls[0][1]!.path as string)).toBe(
      join(vault, "inbox", "Welcome.md"),
    );

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
    await flushPendingWrites();
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
    await flushPendingWrites();
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

    const imageDirectory = join(root, "one", "images");
    const imagePath = join(imageDirectory, "diagram one.png");
    await mkdir(imageDirectory, { recursive: true });
    await writeFile(imagePath, new Uint8Array([9, 8, 7, 6]));
    updateNoteBody(
      ids[0],
      [
        "# First external",
        "",
        "Simultaneous change from disk.",
        "",
        "![Diagram](images/diagram%20one.png)",
        "![Again](images/diagram%20one.png)",
        "![Remote](https://example.com/remote.png)",
        "",
      ].join("\n"),
    );
    await flushPendingWrites();

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
    const copiedContent = await readFile(
      join(vault, "copies", "First external.md"),
      "utf8",
    );
    expect(copiedContent.match(/assets\/diagram%20one\.png/g)).toHaveLength(2);
    expect(copiedContent).toContain("https://example.com/remote.png");
    await expect(readFile(join(vault, "assets", "diagram one.png")))
      .resolves.toEqual(Buffer.from([9, 8, 7, 6]));
    await expect(nodeStat(imagePath)).resolves.toBeDefined();

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
    await expect(nodeStat(imagePath)).rejects.toThrow();
    await expect(
      readFile(join(vault, "research", "First external 2.md"), "utf8"),
    ).resolves.toContain("Simultaneous change from disk.");
    const movedContent = await readFile(
      join(vault, "research", "First external 2.md"),
      "utf8",
    );
    expect(movedContent.match(/assets\/diagram%20one%202\.png/g)).toHaveLength(2);
    expect(moved?.content).toContain("assets/diagram%20one%202.png");
    await expect(readFile(join(vault, "assets", "diagram one 2.png")))
      .resolves.toEqual(Buffer.from([9, 8, 7, 6]));
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

  it("moves a mixed selection with managed files, attachments, and shared external images", async () => {
    const destination = ["batch-move"];
    const note = (await createNote(["inbox"], "# Batch ordinary\n"))!;
    const managed = (await createNote(["inbox"], "# Batch managed\n"))!;
    const document = join(root, "batch-managed.pdf");
    await writeFile(document, "managed bytes");
    await attachFileToNote(managed.id, document, "copy");
    const linkedSource = join(root, "batch-linked.pdf");
    await writeFile(linkedSource, "linked bytes");
    mocks.picked = linkedSource;
    const linked = (await createFileNote(["inbox"], async () => "external-backup"))!;
    const attachments = getNoteAttachments(getNotes().find((candidate) => candidate.id === linked.id)!);
    const imagePath = join(root, "shared-batch.png");
    await writeFile(imagePath, new Uint8Array([1, 2, 3]));
    const externalPaths = [join(root, "Batch external one.md"), join(root, "Batch external two.md")];
    await Promise.all(externalPaths.map((path) => writeFile(path, "# External\n\n![Shared](shared-batch.png)\n")));
    mocks.picked = externalPaths;
    const externalIds = await openExternalNotes();
    await flushPendingWrites();
    await mkdir(join(vault, "batch-move"), { recursive: true });
    await writeFile(join(vault, "batch-move", "Batch ordinary.md"), "untouched collision");
    const ids = [note.id, managed.id, linked.id, ...externalIds];
    const result = await moveNotesToType([...ids, note.id], destination);
    expect(result).toEqual({ movedIds: ids, skipped: [], failed: [] });
    for (const id of ids) {
      const moved = getNotes().find((candidate) => candidate.id === id)!;
      expect(noteTypePath(moved)).toEqual(destination);
      expect(moved.externalPath).toBeUndefined();
      expect(await readFile(join(vault, moved.path), "utf8")).toBe(moved.content);
    }
    await expect(readFile(join(vault, "batch-move", "Batch ordinary.md"), "utf8")).resolves.toBe("untouched collision");
    const movedManaged = getNotes().find((candidate) => candidate.id === managed.id)!;
    await expect(readFile(join(vault, getFileHubReference(movedManaged)!.path!), "utf8")).resolves.toBe("managed bytes");
    const movedLinked = getNotes().find((candidate) => candidate.id === linked.id)!;
    expect(getNoteAttachments(movedLinked)).toEqual(attachments);
    await expect(readFile(join(vault, attachments[0].path!), "utf8")).resolves.toBe("linked bytes");
    await expect(readFile(linkedSource, "utf8")).resolves.toBe("linked bytes");
    expect((await getFileHubStatus(linked.id))?.resolved.absolutePath).toBe(linkedSource);
    for (const id of externalIds) {
      const moved = getNotes().find((candidate) => candidate.id === id)!;
      const imported = moved.content.match(/!\[Shared\]\(([^)]+)\)/)![1];
      await expect(readFile(join(vault, decodeURIComponent(imported)))).resolves.toEqual(Buffer.from([1, 2, 3]));
    }
    await expect(readFile(imagePath)).resolves.toEqual(Buffer.from([1, 2, 3]));
    for (const path of externalPaths) await expect(nodeStat(path)).rejects.toThrow();
  });

  it("keeps unsaved sources in place and continues moving the rest of a selection", async () => {
    const failed = (await createNote(["inbox"], "# Batch failed save\n"))!;
    const ready = (await createNote(["inbox"], "# Batch ready\n"))!;
    const alreadyThere = (await createNote(["batch-results"], "# Already there\n"))!;
    await flushPendingWrites();
    const failedPath = join(vault, failed.path);
    mocks.failWrites.add(failedPath);
    updateNoteBody(failed.id, "# Batch failed save\n\nUnsaved changes\n");
    try {
      const result = await moveNotesToType([failed.id, "missing-batch-note", alreadyThere.id, ready.id], ["batch-results"]);
      expect(result.movedIds).toEqual([ready.id]);
      expect(result.failed.map((issue) => issue.noteId)).toEqual([failed.id]);
      expect(result.skipped.map((issue) => issue.noteId)).toEqual(["missing-batch-note", alreadyThere.id]);
      expect(getNotes().find((candidate) => candidate.id === failed.id)?.path).toBe(failed.path);
      await expect(readFile(failedPath, "utf8")).resolves.not.toContain("Unsaved changes");
      expect(noteTypePath(getNotes().find((candidate) => candidate.id === ready.id)!)).toEqual(["batch-results"]);
    } finally {
      mocks.failWrites.delete(failedPath);
      await flushPendingWrites();
    }
  });

  it("waits for a file storage choice and cancels without creating a note", async () => {
    const source = join(root, "one", "Cancelled file.pdf");
    await writeFile(source, "source bytes");
    mocks.picked = source;
    const noteIds = getNotes().map((note) => note.id);
    let cancel!: (mode: null) => void;
    const choose = vi.fn(() => new Promise<null>((resolve) => { cancel = resolve; }));
    const pending = createFileNote(["inbox"], choose);
    await waitFor(() => choose.mock.calls.length === 1);
    expect(getNotes().map((note) => note.id)).toEqual(noteIds);
    cancel(null);
    await expect(pending).resolves.toBeNull();
    expect(getNotes().map((note) => note.id)).toEqual(noteIds);
    await expect(readFile(source, "utf8")).resolves.toBe("source bytes");
  });

  it.each(["copy", "external", "external-backup"] as const)(
    "creates a file note using %s while preserving the source",
    async (mode) => {
      const source = join(root, "one", `Storage ${mode}.pdf`);
      await writeFile(source, "original document bytes");
      mocks.picked = source;
      const created = await createFileNote(mode === "copy" ? ["storage", "new-type"] : ["inbox"], async () => mode);
      expect(created).not.toBeNull();
      await flushPendingWrites();
      const note = getNotes().find((candidate) => candidate.id === created!.id)!;
      const hub = getFileHubReference(note)!;
      expect(hub.kind).toBe(mode === "copy" ? "vault" : "local");
      if (mode === "copy") {
        await expect(readFile(join(vault, hub.path!), "utf8")).resolves.toBe("original document bytes");
      } else {
        expect((await getFileHubStatus(note.id))?.resolved.absolutePath).toBe(source);
      }
      const attachments = getNoteAttachments(note);
      expect(attachments).toHaveLength(mode === "external-backup" ? 1 : 0);
      if (mode === "external-backup") {
        expect(attachments[0].kind).toBe("vault");
        expect(note.content).toContain(`](zerus-attachment:${attachments[0].id})`);
        await writeFile(source, "edited external document");
        await expect(readFile(join(vault, attachments[0].path!), "utf8")).resolves.toBe("original document bytes");
        await setNoteType(note.id, ["research"]);
        await trashNote(note.id);
        await restoreNote(note.id);
      }
      await expect(readFile(source, "utf8")).resolves.toBe(
        mode === "external-backup" ? "edited external document" : "original document bytes",
      );
      const disk = await readFile(join(vault, getNotes().find((candidate) => candidate.id === note.id)!.path), "utf8");
      expect(getNoteAttachments(disk)).toEqual(attachments);
    },
  );

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
    await flushPendingWrites();
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

  it("ignores a slow vault load after a newer vault finishes opening", async () => {
    const slowVault = join(root, "slow-vault");
    const fastVault = join(root, "fast-vault");
    await mkdir(slowVault);
    await mkdir(fastVault);
    await writeFile(join(slowVault, "Slow.md"), "# Slow vault\n");
    await writeFile(join(fastVault, "Fast.md"), "# Fast vault\n");
    let release!: () => void;
    let started!: () => void;
    const reading = new Promise<void>((resolve) => { started = resolve; });
    mocks.readTextGatePath = join(slowVault, "Slow.md");
    mocks.readTextGate = new Promise<void>((resolve) => { release = resolve; });
    mocks.onReadTextGate = started;
    const slowSwitch = switchDesktopVault(slowVault);
    try {
      await reading;
      await expect(switchDesktopVault(fastVault)).resolves.toBe(true);
      release();
      await expect(slowSwitch).resolves.toBe(false);
      expect(getNotes().some((note) => note.path === "Fast.md")).toBe(true);
      expect(getNotes().some((note) => note.path === "Slow.md")).toBe(false);
      expect(mocks.invoke).not.toHaveBeenCalledWith("cli_register_vault", {
        vaultPath: slowVault,
      });
    } finally {
      release();
      await slowSwitch;
      await switchDesktopVault(vault);
    }
  });

  it("retries opening the same vault after its first load failed", async () => {
    const unavailable = join(root, "retry-vault");
    await expect(switchDesktopVault(unavailable)).resolves.toBe(false);
    await mkdir(unavailable);
    await writeFile(join(unavailable, "Recovered.md"), "# Recovered\n");
    try {
      await expect(switchDesktopVault(unavailable)).resolves.toBe(true);
      expect(getNotes().some((note) => note.path === "Recovered.md")).toBe(true);
    } finally {
      await switchDesktopVault(vault);
    }
  });

  it("migrates legacy links and preserves identity, navigation and backlinks after save and reopen", async () => {
    const linkVault = join(root, "stable-links-vault");
    await mkdir(join(linkVault, "work"), { recursive: true });
    await writeFile(join(linkVault, "work", "Target.md"), "# Target\n");
    await writeFile(join(linkVault, "work", "Source.md"), "# Source\n\n[[Target]]\n");
    try {
      await switchDesktopVault(linkVault);
      addTypeProperty("work", { name: "Related", type: "relation" });
      const target = getNotes().find((note) => noteTitle(note) === "Target")!;
      const source = getNotes().find((note) => noteTitle(note) === "Source")!;
      setNoteProperty(source.id, "Related", "Target");
      updateNoteBody(target.id, "# Renamed\n");
      expect(await flushPendingWrites()).toBe(true);
      const savedSource = await readFile(join(linkVault, "work", "Source.md"), "utf8");
      expect(savedSource).toContain(`[[zerus:${target.id}|Target]]`);
      expect(getNoteProperties(savedSource).Related).toBe(`zerus:${target.id}|Target`);
      expect(await readFile(join(linkVault, "work", "Renamed.md"), "utf8")).toContain(`zerus-id: ${target.id}`);
      await switchDesktopVault(vault);
      await switchDesktopVault(linkVault);
      const reopenedTarget = getNotes().find((note) => noteTitle(note) === "Renamed")!;
      expect(reopenedTarget.id).toBe(target.id);
      const groups = getBacklinksGroupedByType(reopenedTarget, getNotes(), { work: [{ name: "Related", type: "relation" }] });
      expect([...groups.values()].flat().map((note) => note.id)).toEqual([source.id]);
    } finally {
      await switchDesktopVault(vault);
    }
  });

  it("synchronizes relation additions and removals while keeping the inverse field hidden", async () => {
    const relationVault = join(root, "paired-relations-vault");
    await Promise.all([
      mkdir(join(relationVault, "tasks"), { recursive: true }),
      mkdir(join(relationVault, "epics"), { recursive: true }),
    ]);
    await Promise.all([
      writeFile(join(relationVault, "tasks", "Task.md"), "# Task\n"),
      writeFile(join(relationVault, "epics", "Epic.md"), "# Epic\n"),
    ]);
    try {
      await switchDesktopVault(relationVault);
      addTypeProperty("tasks", {
        name: "Epic",
        type: "relation",
        relationTypeKey: "epics",
        relationInverseHidden: true,
      });
      const task = getNotes().find((note) => noteTitle(note) === "Task")!;
      const epic = getNotes().find((note) => noteTitle(note) === "Epic")!;

      setNoteProperty(task.id, "Epic", "Epic");
      expect(getNoteProperties(getNotes().find((note) => note.id === task.id)!.content).Epic).toBeTruthy();

      const hiddenSchemas = getPropertySchemas();
      expect(hiddenSchemas.epics[0].relationHidden).toBe(true);
      const inverseName = hiddenSchemas.epics[0].name;
      expect(
        getNoteProperties(getNotes().find((note) => note.id === epic.id)!.content)[inverseName],
      ).toBeTruthy();
      const backlinks = getBacklinksGroupedByType(
        getNotes().find((note) => note.id === epic.id)!,
        getNotes(),
        hiddenSchemas,
      );
      expect([...backlinks.values()].flat()).toEqual([]);

      setNoteProperty(epic.id, inverseName, null);
      expect(getNoteProperties(getNotes().find((note) => note.id === task.id)!.content).Epic).toBeUndefined();

      setNoteProperty(task.id, "Epic", "Epic");
      const sourceDefinition = hiddenSchemas.tasks[0];
      updateTypeProperty("tasks", "Epic", {
        ...sourceDefinition,
        relationInverseHidden: false,
      });
      expect(getPropertySchemas().epics[0].relationHidden).toBe(false);
    } finally {
      await switchDesktopVault(vault);
    }
  });

  it("bulk edits relations by note identity and persists synchronized links through undo and redo", async () => {
    const relationVault = join(root, "bulk-relations-vault");
    await Promise.all([
      mkdir(join(relationVault, "tasks"), { recursive: true }),
      mkdir(join(relationVault, "epics"), { recursive: true }),
      mkdir(join(relationVault, ".zerus"), { recursive: true }),
    ]);
    await Promise.all([
      writeFile(join(relationVault, "tasks", "First.md"), "---\nEpics: [Epic]\n---\n# First\n"),
      writeFile(join(relationVault, "tasks", "Second.md"), "# Second\n"),
      writeFile(join(relationVault, "epics", "Epic.md"), "# Epic\n"),
      writeFile(join(relationVault, "epics", "Other.md"), "# Other\n"),
      writeFile(join(relationVault, ".zerus", "properties.json"), JSON.stringify({
        tasks: [{ name: "Epics", type: "relation", relationMultiple: true, relationTypeKey: "epics" }],
      })),
    ]);
    try {
      await switchDesktopVault(relationVault);
      const first = getNotes().find((note) => noteTitle(note) === "First")!;
      const second = getNotes().find((note) => noteTitle(note) === "Second")!;
      const epic = getNotes().find((note) => noteTitle(note) === "Epic")!;
      const other = getNotes().find((note) => noteTitle(note) === "Other")!;
      const noteIds = [first.id, second.id];
      const add = { properties: [{ name: "Epics", operation: "add" as const, value: [noteReference(epic, "Earlier epic title")] }] };
      // A renamed note remains the same target even when a stored label is stale.
      expect(previewBulkAction(noteIds, add).eligibleIds).toEqual([second.id]);
      const added = await executeBulkAction({ location: relationVault, noteIds, mutation: add });
      expect(added.failed).toEqual([]);
      expect(added.successfulIds).toEqual([second.id]);

      const removed = await executeBulkAction({
        location: relationVault, noteIds,
        mutation: { properties: [{ name: "Epics", operation: "remove", value: [noteReference(epic)] }] },
      });
      expect(removed.successfulIds).toEqual(noteIds);
      await flushPendingWrites();
      for (const name of ["First", "Second"]) {
        expect(getNoteProperties(await readFile(join(relationVault, "tasks", `${name}.md`), "utf8")).Epics).toEqual([]);
      }
      const inverseName = getPropertySchemas().epics.find((def) => def.relationPairId === getPropertySchemas().tasks[0].relationPairId)!.name;
      expect(getNoteProperties(await readFile(join(relationVault, "epics", "Epic.md"), "utf8"))[inverseName]).toBeUndefined();

      expect((await transitionBulkAction(relationVault, removed.record!.id, "undo")).conflicts).toEqual([]);
      await flushPendingWrites();
      const restored = getNoteProperties(await readFile(join(relationVault, "tasks", "First.md"), "utf8")).Epics as string[];
      expect(restored).toHaveLength(1);
      expect(noteReferenceMatches(restored[0], epic)).toBe(true);
      expect(getNoteProperties(await readFile(join(relationVault, "epics", "Epic.md"), "utf8"))[inverseName]).toEqual(expect.arrayContaining([noteReference(first), noteReference(second)]));
      expect((await transitionBulkAction(relationVault, removed.record!.id, "redo")).conflicts).toEqual([]);

      const replaced = await executeBulkAction({
        location: relationVault, noteIds,
        mutation: { properties: [{ name: "Epics", operation: "set", value: [noteReference(other)] }] },
      });
      expect(replaced.successfulIds).toEqual(noteIds);
      const cleared = await executeBulkAction({
        location: relationVault, noteIds,
        mutation: { properties: [{ name: "Epics", operation: "clear" }] },
      });
      expect(cleared.successfulIds).toEqual(noteIds);
      await flushPendingWrites();
      for (const name of ["First", "Second"]) {
        expect(getNoteProperties(await readFile(join(relationVault, "tasks", `${name}.md`), "utf8")).Epics).toBe("");
      }
      expect(getNoteProperties(await readFile(join(relationVault, "epics", "Other.md"), "utf8"))[inverseName]).toBeUndefined();
    } finally {
      await switchDesktopVault(vault);
    }
  });

  it("upgrades legacy one-way relations on load and preserves inverse values through removal and reopen", async () => {
    const relationVault = join(root, "legacy-relations-vault");
    await Promise.all([
      mkdir(join(relationVault, "tasks"), { recursive: true }),
      mkdir(join(relationVault, "epics"), { recursive: true }),
      mkdir(join(relationVault, ".zerus"), { recursive: true }),
    ]);
    await Promise.all([
      writeFile(join(relationVault, "tasks", "First.md"), "---\nepic: Epic\n---\n# First\n"),
      writeFile(join(relationVault, "tasks", "Second.md"), "---\nEpic: Epic\nReview epic: Epic\n---\n# Second\n"),
      writeFile(join(relationVault, "epics", "Epic.md"), "# Epic\n"),
      writeFile(join(relationVault, ".zerus", "properties.json"), JSON.stringify({
        tasks: [
          { name: "Epic", type: "relation", relationTypeKey: "epics" },
          { name: "Review epic", type: "relation", relationTypeKey: "epics" },
        ],
        epics: [{ name: "Tasks", type: "relation", relationTypeKey: "tasks" }],
      })),
    ]);
    try {
      await switchDesktopVault(relationVault);
      const first = getNotes().find((note) => noteTitle(note) === "First")!;
      const second = getNotes().find((note) => noteTitle(note) === "Second")!;
      const epic = getNotes().find((note) => noteTitle(note) === "Epic")!;
      const inverse = () => getNoteProperties(getNotes().find((note) => note.id === epic.id)!.content).Tasks;
      expect(inverse()).toEqual(expect.arrayContaining([
        `zerus:${first.id}|First`, `zerus:${second.id}|Second`,
      ]));
      expect(getPropertySchemas().epics[0].relationMultiple).toBe(true);
      expect(getPropertySchemas().epics[0].relationPairId).toBe(getPropertySchemas().tasks[0].relationPairId);
      const reviewInverse = getPropertySchemas().epics.find((definition) =>
        definition.relationPairId === getPropertySchemas().tasks[1].relationPairId,
      )!;
      expect(reviewInverse.name).not.toBe("Tasks");
      expect(getNoteProperties(getNotes().find((note) => note.id === epic.id)!.content)[reviewInverse.name]).toEqual([`zerus:${second.id}|Second`]);
      expect(getBacklinksGroupedByType(getNotes().find((note) => note.id === epic.id)!, getNotes(), getPropertySchemas()).size).toBe(0);
      expect(await flushPendingWrites()).toBe(true);

      await switchDesktopVault(vault);
      await switchDesktopVault(relationVault);
      expect(inverse()).toHaveLength(2);
      setNoteProperty(first.id, "Epic", null);
      expect(inverse()).toEqual([`zerus:${second.id}|Second`]);
      setNoteProperty(second.id, "Review epic", null);
      expect(inverse()).toEqual([`zerus:${second.id}|Second`]);
      expect(await flushPendingWrites()).toBe(true);
      await switchDesktopVault(vault);
      await switchDesktopVault(relationVault);
      expect(getNoteProperties(getNotes().find((note) => note.id === first.id)!.content).epic).toBeUndefined();
      expect(inverse()).toEqual([`zerus:${second.id}|Second`]);
    } finally {
      await switchDesktopVault(vault);
    }
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
  it("duplicates the latest content independently without overwriting files", async () => {
    const original = await createNote(["inbox"], "# Duplicate source\n\nInitial text\n");
    expect(original).not.toBeNull();
    setNoteProperty(original!.id, "Status", "Draft");
    updateNoteBody(original!.id, "# Duplicate source\n\nLatest unsaved text\n");
    toggleNoteArchived(original!.id);
    await writeFile(join(vault, "inbox", "Duplicate source copy.md"), "Unloaded file");
    const copy = await duplicateNote(original!.id);
    expect(copy).not.toBeNull();
    expect(copy!.id).not.toBe(original!.id);
    expect(copy!.path).toBe("inbox/Duplicate source copy 2.md");
    expect(copy!.content).toContain("Latest unsaved text");
    expect(getNoteProperties(copy!.content).Status).toBe("Draft");
    expect(getNoteProperties(copy!.content)["zerus-id"]).toBe(copy!.id);
    expect(copy!.archived).toBe(false);
    expect(getNoteProperties(copy!.content)["zerus-archived"]).toBeUndefined();
    expect(await readFile(join(vault, copy!.path), "utf8")).toBe(copy!.content);
    expect(await readFile(join(vault, "inbox", "Duplicate source copy.md"), "utf8")).toBe("Unloaded file");
    updateNoteBody(copy!.id, "# Edited duplicate\n");
    await flushPendingWrites();
    expect(getNotes().find((note) => note.id === original!.id)!.content).toContain("Latest unsaved text");
    await trashNote(copy!.id);
    expect(await duplicateNote(copy!.id)).toBeNull();
    expect(await duplicateNote("missing-note")).toBeNull();
  });

  it("keeps a managed attachment safe when its duplicate is deleted", async () => {
    const document = join(root, "duplicate-attachment.pdf");
    await writeFile(document, "attachment bytes");
    const original = await createNote(["inbox"], "# Attachment duplicate source\n");
    await attachFileToNote(original!.id, document, "copy");
    const source = getNotes().find((note) => note.id === original!.id)!;
    const copy = await duplicateNote(source.id);
    const reference = getFileHubReference(source)!;
    expect(getFileHubReference(copy!)).toMatchObject({ path: reference.path, managed: false });
    await trashNote(copy!.id);
    await deleteNoteForever(copy!.id);
    expect(await readFile(join(vault, reference.path!), "utf8")).toBe("attachment bytes");
  });

  it("persists saved-view deletion across reopen without changing notes, the active layout, or other presets", async () => {
    const viewVault = join(root, "saved-views-vault");
    await mkdir(join(viewVault, "work"), { recursive: true });
    const notePath = join(viewVault, "work", "Project.md");
    await writeFile(notePath, "# Project\n");
    const presetsPath = join(viewVault, ".zerus", "saved-views.json");
    const activeViewPath = join(viewVault, ".zerus", "views.json");
    const config = { ...defaultTypeViewConfig(), mode: "board" as const, groupBy: "Status" };
    try {
      await switchDesktopVault(viewVault);
      updateTypeView("work", config);
      const removed = saveTypeViewPreset("work", "Remove me", config)!;
      const kept = saveTypeViewPreset("work", "Keep me", config)!;
      const other = saveTypeViewPreset("other", "Other type", config)!;
      expect(await flushPendingWrites()).toBe(true);
      const originalNote = await readFile(notePath, "utf8");
      const originalActiveView = await readFile(activeViewPath, "utf8");

      deleteTypeViewPreset("other", removed.id);
      deleteTypeViewPreset("work", "missing-view");
      deleteTypeViewPreset("", removed.id);
      deleteTypeViewPreset(" / work / ", removed.id);
      expect(await flushPendingWrites()).toBe(true);
      expect(JSON.parse(await readFile(presetsPath, "utf8"))).toEqual({
        work: [kept], other: [other],
      });
      expect(await readFile(activeViewPath, "utf8")).toBe(originalActiveView);
      expect(await readFile(notePath, "utf8")).toBe(originalNote);

      await switchDesktopVault(vault);
      await switchDesktopVault(viewVault);
      const added = saveTypeViewPreset("work", "After reopen", config)!;
      expect(await flushPendingWrites()).toBe(true);
      expect(JSON.parse(await readFile(presetsPath, "utf8"))).toEqual({
        work: [kept, added], other: [other],
      });

      deleteTypeViewPreset("work", kept.id);
      deleteTypeViewPreset("work", added.id);
      expect(await flushPendingWrites()).toBe(true);
      expect(JSON.parse(await readFile(presetsPath, "utf8"))).toEqual({ other: [other] });
    } finally {
      await switchDesktopVault(vault);
    }
  });

});
