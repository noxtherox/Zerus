import { afterEach, describe, expect, it, vi } from "vitest";
import { loadLinkOption, saveLinkOption, searchLinkNotes, linkedNoteExcerpt } from "./vault-link-options";
import { noteReference, type Note } from "@/lib/note-utils";
import { restoreNoteLinks } from "./note-link-markdown";

const note = (id: string, path: string, content = "# Same title\n\nA short excerpt."): Note => ({ id, path, content, pinned: false, updatedAt: "2026-09-15" });
afterEach(() => vi.unstubAllGlobals());

describe("vault link picker", () => {
  it("remembers either option and tolerates unavailable storage", () => {
    const data = new Map<string, string>();
    vi.stubGlobal("localStorage", { getItem: (key: string) => data.get(key), setItem: (key: string, value: string) => data.set(key, value) });
    expect(loadLinkOption()).toBe("note");
    saveLinkOption("web");
    expect(loadLinkOption()).toBe("web");
    saveLinkOption("note");
    expect(loadLinkOption()).toBe("note");
    vi.stubGlobal("localStorage", { getItem: () => { throw Error(); }, setItem: () => { throw Error(); } });
    expect(loadLinkOption()).toBe("note");
    expect(() => saveLinkOption("web")).not.toThrow();
  });

  it("distinguishes duplicate titles by folder and excludes trash and external files", () => {
    const notes = [note("a", "work/same.md"), note("b", "personal/same.md"), note("c", ".trash/same.md"), { ...note("d", "same.md"), externalPath: "/other/same.md" }];
    expect(searchLinkNotes(notes, "same").map((n) => n.id)).toEqual(["a", "b"]);
    expect(searchLinkNotes(notes, "SAME work").map((n) => n.id)).toEqual(["a"]);
    expect(searchLinkNotes(notes, "absent")).toEqual([]);
  });

  it("saves a selected note as a stable wikilink with a custom label", () => {
    const target = note("stable-id", "work/same.md");
    const url = `#zerus-note:${encodeURIComponent(noteReference(target))}`;
    expect(restoreNoteLinks(`[Selected words](${url})`)).toBe("[[zerus:stable-id|Selected words]]");
  });

  it("omits metadata and repeated title from the excerpt", () => {
    expect(linkedNoteExcerpt(note("a", "same.md", "---\nsecret: hidden\n---\n# Same title\n\nTalk to [[zerus:abc|Jane]] about **delivery**."))).toBe("Talk to Jane about delivery.");
  });
});
