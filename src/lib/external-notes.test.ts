import { describe, expect, it } from "vitest";
import { filterNotes } from "./filters";
import {
  type Note,
  buildTypeTree,
  getAllTypePaths,
  isExternalNote,
  normalizeFsPath,
  noteAbsolutePath,
  noteContainingFolder,
  noteTypePath,
  parseTypePath,
  reorderTypeTree,
} from "./note-utils";

const vaultNote: Note = {
  id: "vault",
  path: "work/Vault note.md",
  content: "# Vault note",
  pinned: false,
  updatedAt: "2026-07-15T10:00:00.000Z",
};

const externalNote: Note = {
  id: "external",
  path: "Review me.md",
  externalPath: "/Users/test/Desktop/Review me.md",
  content: "# Review me",
  pinned: false,
  updatedAt: "2026-07-15T11:00:00.000Z",
};

describe("external notes", () => {
  it("keeps external notes separate from vault filters and types", () => {
    expect(filterNotes([vaultNote, externalNote], { kind: "all" }, "")).toEqual(
      [vaultNote],
    );
    expect(
      filterNotes([vaultNote, externalNote], { kind: "external" }, ""),
    ).toEqual([externalNote]);
    expect(
      buildTypeTree([vaultNote, externalNote]).map((node) => node.name),
    ).toEqual(["work"]);
    expect(getAllTypePaths([vaultNote, externalNote])).toEqual([["work"]]);
  });

  it("reports the real path for external and vault notes", () => {
    expect(isExternalNote(externalNote)).toBe(true);
    expect(noteAbsolutePath(externalNote, "/vault")).toBe(
      "/Users/test/Desktop/Review me.md",
    );
    expect(noteAbsolutePath(vaultNote, "/vault/")).toBe(
      "/vault/work/Vault note.md",
    );
    expect(noteContainingFolder(vaultNote, "/vault/")).toBe("/vault/work");
    expect(noteContainingFolder(externalNote, "/vault")).toBe(
      "/Users/test/Desktop",
    );
  });

  it("normalizes Windows paths and rejects traversal type segments", () => {
    expect(normalizeFsPath("C:\\Vault\\Work\\Note.md")).toBe(
      normalizeFsPath("c:/vault/work/note.md"),
    );
    expect(normalizeFsPath("//SERVER/Share/Note.md")).toBe(
      normalizeFsPath("\\\\server\\share\\note.md"),
    );
    expect(parseTypePath("../outside/research")).toEqual([
      "outside",
      "research",
    ]);
    expect(parseTypePath("Work/Client Projects")).toEqual([
      "Work",
      "Client Projects",
    ]);
  });

  it("preserves deeply nested type paths", () => {
    const deepPath = ["work", "clients", "acme", "projects", "website"];
    const deepNote = {
      ...vaultNote,
      path: `${deepPath.join("/")}/Plan.md`,
    };

    expect(parseTypePath(deepPath.join("/"))).toEqual(deepPath);
    expect(noteTypePath(deepNote)).toEqual(deepPath);
    expect(getAllTypePaths([deepNote])).toContainEqual(deepPath);
    expect(
      buildTypeTree([deepNote])[0].children[0].children[0].children[0]
        .children[0].path,
    ).toEqual(deepPath);
  });

  it("orders types at each level and only reorders siblings", () => {
    const notes: Note[] = [
      { ...vaultNote, id: "a", path: "alpha/one/A.md" },
      { ...vaultNote, id: "b", path: "alpha/two/B.md" },
      { ...vaultNote, id: "c", path: "beta/C.md" },
    ];
    const tree = buildTypeTree(notes, [], ["beta", "alpha", "alpha/two"]);

    expect(tree.map((node) => node.name)).toEqual(["beta", "alpha"]);
    expect(tree[1].children.map((node) => node.name)).toEqual(["two", "one"]);
    expect(reorderTypeTree(tree, "alpha/one", "alpha/two", "before")).toEqual([
      "beta",
      "alpha",
      "alpha/one",
      "alpha/two",
    ]);
    expect(reorderTypeTree(tree, "beta", "alpha/two", "before")).toBeNull();
  });
});
