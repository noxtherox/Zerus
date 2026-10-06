import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { BrowserVault } from "./vault/browser";
import { changeNoteRevision, listTrashedRevisions, purgeRevisionTrash, readNoteRevisions, revisionContent, revisionFiles } from "./note-revisions";
import { getFileHubReference, setFileHubReference } from "./file-hubs";
import { getNoteAttachments, setNoteAttachments } from "./note-attachments";
import { getNoteProperties, setContentProperty } from "./frontmatter";
import type { Note } from "./note-utils";

beforeEach(() => {
  const entries = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => entries.get(key) ?? null,
    setItem: (key: string, value: string) => entries.set(key, value),
    removeItem: (key: string) => entries.delete(key),
  });
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

async function fixture(content = "# Proposal\n\nFirst proposal") {
  const vault = new BrowserVault();
  const note: Note = {
    id: "proposal", path: "work/Proposal.md", content, pinned: false,
    createdAt: "2026-10-01T12:00:00.000Z", updatedAt: "2026-10-02T12:00:00.000Z",
  };
  await vault.write(note.path, note.content);
  return { vault, note };
}

async function edit(vault: BrowserVault, note: Note, content: string) {
  note.content = content;
  await vault.write(note.path, content);
}

describe("deliberate note revisions", () => {
  it("preserves independent file bytes and promotes an old revision as a new version with today's shared title and properties", async () => {
    let content = setFileHubReference("# Proposal\n\nFirst proposal\n\n![chart](assets/chart.png)\n[spec](files/spec.txt)", {
      id: "document", name: "Proposal.pdf", kind: "vault", path: "files/Proposal.pdf", managed: true,
    });
    content = setNoteAttachments(content, [{ id: "sheet", name: "Costs.xlsx", kind: "vault", path: "files/Costs.xlsx", managed: true }]);
    const { vault, note } = await fixture(content);
    for (const file of revisionFiles(content)) await vault.writeBinary(file.path, new Uint8Array([1, 2, 3]));
    const created = await changeNoteRevision(vault, note, { kind: "create" });
    note.content = created.content;
    expect(created.revisions.revisions.map((r) => r.number)).toEqual([1, 2]);
    const first = created.revisions.revisions[0];
    for (const file of revisionFiles(note.content)) await vault.writeBinary(file.path, new Uint8Array([9]));
    for (const file of revisionFiles(content)) await vault.removeFile(file.path);
    for (const file of revisionFiles(first.content)) expect(await vault.readBinary(file.path)).toEqual(new Uint8Array([1, 2, 3]));
    await edit(vault, note, setContentProperty(note.content.replace("# Proposal", "# Approved proposal").replace("First proposal", "Second proposal"), "tags", ["approved"]));
    const promoted = await changeNoteRevision(vault, note, { kind: "promote", revisionId: first.id });
    note.content = promoted.content;
    expect(promoted.revisions.revisions.map((r) => r.number)).toEqual([1, 2, 3]);
    expect(promoted.content).toContain("# Approved proposal\n\nFirst proposal");
    expect(getNoteProperties(promoted.content).tags).toEqual(["approved"]);
    expect(getNoteAttachments(promoted.content)[0].name).toBe("Costs.xlsx");
    for (const file of revisionFiles(promoted.content)) expect(await vault.readBinary(file.path)).toEqual(new Uint8Array([1, 2, 3]));
    const second = promoted.revisions.revisions[1];
    expect(second.content).toContain("Second proposal");
    for (const file of revisionFiles(second.content)) expect(await vault.readBinary(file.path)).toEqual(new Uint8Array([9]));
    // Reopening uses the saved vault, not a component cache or an automatic history entry.
    const reopened = new BrowserVault();
    expect((await readNoteRevisions(reopened, note)).currentId).toBe(promoted.revisions.currentId);
    expect((await readNoteRevisions(reopened, note)).revisions).toHaveLength(3);
  });

  it("moves individual revisions to Trash, falls back to the latest remaining revision, and never reuses a number", async () => {
    const { vault, note } = await fixture();
    const second = await changeNoteRevision(vault, note, { kind: "create" });
    await edit(vault, note, second.content.replace("First proposal", "Second proposal"));
    const third = await changeNoteRevision(vault, note, { kind: "create" });
    await edit(vault, note, third.content.replace("Second proposal", "Third proposal"));
    const deleted = await changeNoteRevision(vault, note, { kind: "trash", revisionId: third.revisions.currentId });
    note.content = deleted.content;
    expect(deleted.revisions.currentId).toBe(second.revisions.currentId);
    expect(deleted.content).toContain("Second proposal");
    expect((await listTrashedRevisions(vault))[0].revision.content).toContain("Third proposal");
    const restored = await changeNoteRevision(vault, note, { kind: "restore", revisionId: third.revisions.currentId });
    note.content = restored.content;
    expect(restored.revisions.currentId).toBe(second.revisions.currentId);
    expect(await listTrashedRevisions(vault)).toEqual([]);
    const fourth = await changeNoteRevision(vault, note, { kind: "create" });
    note.content = fourth.content;
    expect(fourth.revisions.revisions.at(-1)?.number).toBe(4);
    for (const revision of fourth.revisions.revisions.slice(0, -1)) {
      const next = await changeNoteRevision(vault, note, { kind: "trash", revisionId: revision.id });
      note.content = next.content;
    }
    await expect(changeNoteRevision(vault, note, { kind: "trash", revisionId: fourth.revisions.currentId })).rejects.toThrow("whole note");
    expect((await readNoteRevisions(vault, note)).revisions.filter((r) => !r.deletedAt)).toHaveLength(1);
  });

  it("keeps revisions attached to a note across archive, move, whole-note trash, and restoration", async () => {
    const { vault, note } = await fixture();
    const created = await changeNoteRevision(vault, note, { kind: "create" });
    note.content = created.content;
    note.archived = true;
    await edit(vault, note, setContentProperty(note.content, "zerus-archived", true));
    await vault.move(note.path, ".trash/other/Proposal.md");
    note.path = ".trash/other/Proposal.md";
    expect((await readNoteRevisions(vault, note)).revisions).toHaveLength(2);
    await expect(changeNoteRevision(vault, note, { kind: "create" })).rejects.toThrow("Restore this note");
    await vault.move(note.path, "other/Proposal.md");
    note.path = "other/Proposal.md";
    const versions = await readNoteRevisions(new BrowserVault(), note);
    expect(getNoteProperties(revisionContent(versions.revisions[0], note))["zerus-archived"]).toBe(true);
    expect(versions.revisions.map((r) => r.number)).toEqual([1, 2]);
    await expect(readNoteRevisions(vault, { ...note, externalPath: "/outside/Proposal.md" })).rejects.toThrow("Bring this note");
  });

  it("empties revision trash without deleting files used by a surviving revision or another live note", async () => {
    const { vault, note } = await fixture(setFileHubReference("# Proposal\n\nFirst", { id: "file", name: "Document.pdf", kind: "vault", path: "files/doc.pdf", managed: true }));
    await vault.writeBinary("files/doc.pdf", new Uint8Array([42]));
    const created = await changeNoteRevision(vault, note, { kind: "create" });
    note.content = created.content;
    const frozenPath = getFileHubReference(created.revisions.revisions[0].content)!.path!;
    const currentPath = getFileHubReference(note.content)!.path!;
    await vault.write("other/Reference.md", `# Reference\n\n[Shared document](${frozenPath})`);
    const deleted = await changeNoteRevision(vault, note, { kind: "trash", revisionId: "initial" });
    note.content = deleted.content;
    await purgeRevisionTrash(vault, new Set());
    expect(await listTrashedRevisions(vault)).toEqual([]);
    expect(await vault.exists("files/doc.pdf")).toBe(false);
    expect(await vault.readBinary(frozenPath)).toEqual(new Uint8Array([42]));
    expect(await vault.readBinary(currentPath)).toEqual(new Uint8Array([42]));
    await vault.removeFile(note.path);
    await purgeRevisionTrash(vault, new Set([note.id]), false);
    expect(await vault.exists(currentPath)).toBe(false);
    expect(await vault.exists(frozenPath)).toBe(true);
    await vault.removeFile("other/Reference.md");
    await purgeRevisionTrash(vault, new Set());
    expect(await vault.exists(frozenPath)).toBe(false);
  });

  it("does not commit a new revision when a file is missing, external, or the note changes during copying", async () => {
    const { vault, note } = await fixture("# Proposal\n\n![missing](assets/missing.png)");
    await expect(changeNoteRevision(vault, note, { kind: "create" })).rejects.toThrow("missing file");
    expect((await readNoteRevisions(vault, note)).revisions).toHaveLength(1);
    expect(await vault.readText(note.path)).toBe(note.content);
    await edit(vault, note, "# Proposal\n\n![missing](assets/missing.png)\n![present](assets/present.png)");
    await vault.writeBinary("assets/present.png", new Uint8Array([5]));
    await expect(changeNoteRevision(vault, note, { kind: "create" })).rejects.toThrow("missing file");
    expect((await vault.listFiles(".zerus/revisions")).filter((path) => path.includes("/files/"))).toEqual([]);
    await edit(vault, note, setFileHubReference("# Proposal", { id: "outside", name: "Local.pdf", kind: "local", managed: false }));
    await expect(changeNoteRevision(vault, note, { kind: "create" })).rejects.toThrow("Copy linked external files");
    await edit(vault, note, "# Proposal\n\n![chart](assets/chart.png)");
    await vault.writeBinary("assets/chart.png", new Uint8Array([1]));
    const originalRead = vault.readBinary.bind(vault);
    vi.spyOn(vault, "readBinary").mockImplementationOnce(async (path) => {
      await vault.write(note.path, "# Proposal\n\nEdited elsewhere");
      return originalRead(path);
    });
    await expect(changeNoteRevision(vault, note, { kind: "create" })).rejects.toThrow("changed elsewhere");
    expect(await vault.readText(note.path)).toContain("Edited elsewhere");
    expect((await readNoteRevisions(vault, note)).revisions).toHaveLength(1);
  });

  it("recovers a committed revision after interruption between the note and metadata writes", async () => {
    const { vault, note } = await fixture();
    const write = vault.write.bind(vault);
    vi.spyOn(vault, "write").mockImplementation(async (path, content) => {
      if (path.endsWith("/index.json")) throw new Error("storage temporarily unavailable");
      await write(path, content);
    });
    await expect(changeNoteRevision(vault, note, { kind: "create" })).rejects.toThrow("storage temporarily unavailable");
    vi.restoreAllMocks();
    note.content = await vault.readText(note.path);
    const recovered = await readNoteRevisions(new BrowserVault(), note);
    expect(recovered.revisions.map((r) => r.number)).toEqual([1, 2]);
    expect(recovered.currentId).toBe(recovered.revisions[1].id);
  });

  it("leaves the current note and revision intact when the note write fails", async () => {
    const { vault, note } = await fixture();
    const write = vault.write.bind(vault);
    vi.spyOn(vault, "write").mockImplementation(async (path, content) => {
      if (path === note.path) throw new Error("write denied");
      await write(path, content);
    });
    await expect(changeNoteRevision(vault, note, { kind: "create" })).rejects.toThrow("write denied");
    expect(await vault.readText(note.path)).toBe("# Proposal\n\nFirst proposal");
    expect((await readNoteRevisions(vault, note)).revisions.map((r) => r.number)).toEqual([1]);
  });

  it("blocks changes when the note and revision metadata arrive out of order during sync", async () => {
    const { vault, note } = await fixture();
    const created = await changeNoteRevision(vault, note, { kind: "create" });
    await expect(readNoteRevisions(vault, note)).rejects.toThrow("still syncing");
    note.content = created.content;
    expect((await readNoteRevisions(vault, note)).revisions).toHaveLength(2);
    const metadata = (await vault.listFiles(".zerus/revisions")).find((path) => path.endsWith("/index.json"))!;
    await vault.removeFile(metadata);
    await expect(changeNoteRevision(vault, note, { kind: "create" })).rejects.toThrow("has not arrived");
    expect(await vault.readText(note.path)).toBe(created.content);
  });

  it("reports browser storage quota failures instead of claiming an in-memory revision was saved", async () => {
    const { vault, note } = await fixture();
    vi.spyOn(localStorage, "setItem").mockImplementation(() => { throw new Error("quota exceeded"); });
    await expect(changeNoteRevision(vault, note, { kind: "create" })).rejects.toThrow("quota exceeded");
    expect(await vault.readText(note.path)).toBe(note.content);
    await expect(vault.writeBinary("assets/failed.png", new Uint8Array([1]))).rejects.toThrow("quota exceeded");
    expect(await vault.exists("assets/failed.png")).toBe(false);
    expect((await readNoteRevisions(vault, note)).revisions).toHaveLength(1);
    await expect(vault.move(note.path, ".trash/Proposal.md")).rejects.toThrow("quota exceeded");
    expect(await vault.readText(note.path)).toBe(note.content);
    expect(await vault.exists(".trash/Proposal.md")).toBe(false);
    await expect(vault.removeFile(note.path)).rejects.toThrow("quota exceeded");
    expect(await vault.readText(note.path)).toBe(note.content);
  });
});
