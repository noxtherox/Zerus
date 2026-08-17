import { describe, expect, it, vi } from "vitest";
import { chatContentRevision } from "./mobile-chat-history";
import {
  executeMobileAIActions,
  parseMobileAIActions,
  questionRequestsNoteMutation,
} from "./mobile-ai-actions";
import type { Note } from "./note-utils";

function note(content = "# Project Atlas\n\nOriginal text\n"): Note {
  return {
    id: "atlas",
    path: "projects/Project Atlas.md",
    content,
    pinned: false,
    updatedAt: "2026-08-15T10:00:00.000Z",
  };
}

describe("mobile AI note actions", () => {
  it("extracts actions without exposing protocol markup", () => {
    const parsed = parseMobileAIActions(
      'I can do that.\n<grimoire-action>{"action":"create_note","title":"Trip","body":"Pack light."}</grimoire-action>',
    );
    expect(parsed.actions).toEqual([{ action: "create_note", title: "Trip", body: "Pack light.", type: undefined }]);
    expect(parsed.visibleText).toBe("I can do that.");
    expect(parsed.malformed).toBe(false);
  });

  it("rejects malformed and unsafe type paths", () => {
    const parsed = parseMobileAIActions(
      '<grimoire-action>{"action":"create_note","title":"Oops","body":"x","type":["../outside"]}</grimoire-action>',
    );
    expect(parsed.actions).toEqual([]);
    expect(parsed.malformed).toBe(true);
  });

  it("requires an explicit current note-mutation request", () => {
    expect(questionRequestsNoteMutation("Please create a note called Trip ideas")).toBe(true);
    expect(questionRequestsNoteMutation("Could you append this to my Project Atlas note?")).toBe(true);
    expect(questionRequestsNoteMutation("Update Project Atlas with the new deadline", ["Project Atlas"])).toBe(true);
    expect(questionRequestsNoteMutation("What would you add to my Project Atlas note?")).toBe(false);
  });

  it("creates notes through the shared store operations", async () => {
    const createNote = vi.fn(async (_type: string[], content: string) => note(content));
    const result = await executeMobileAIActions(
      [{ action: "create_note", title: "Trip", body: "Pack light.", type: ["travel"] }],
      { getNotes: () => [], createNote, updateNoteBody: vi.fn() },
    );
    expect(createNote).toHaveBeenCalledWith(["travel"], "# Trip\n\nPack light.\n");
    expect(result.message).toBe("Created “Trip”.");
  });

  it("refuses stale edits before changing the note", async () => {
    const existing = note();
    const updateNoteBody = vi.fn();
    await expect(executeMobileAIActions(
      [{ action: "append_note", noteId: existing.id, revision: "stale", text: "New text" }],
      { getNotes: () => [existing], createNote: vi.fn(), updateNoteBody },
    )).rejects.toThrow("changed after the AI read it");
    expect(updateNoteBody).not.toHaveBeenCalled();
  });

  it("appends with the current revision and preserves the title", async () => {
    const existing = note();
    const updateNoteBody = vi.fn();
    await executeMobileAIActions(
      [{ action: "append_note", noteId: existing.id, revision: chatContentRevision(existing.content), text: "New text" }],
      { getNotes: () => [existing], createNote: vi.fn(), updateNoteBody },
    );
    expect(updateNoteBody).toHaveBeenCalledWith(existing.id, "# Project Atlas\n\nOriginal text\n\nNew text\n");
  });

  it("makes a guarded, focused text replacement", async () => {
    const existing = note();
    const updateNoteBody = vi.fn();
    await executeMobileAIActions(
      [{
        action: "replace_note_text",
        noteId: existing.id,
        revision: chatContentRevision(existing.content),
        oldText: "Original text",
        newText: "Revised text",
      }],
      { getNotes: () => [existing], createNote: vi.fn(), updateNoteBody },
    );
    expect(updateNoteBody).toHaveBeenCalledWith(existing.id, "# Project Atlas\n\nRevised text\n");
  });
});
