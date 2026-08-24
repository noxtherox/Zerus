import { describe, expect, it, vi } from "vitest";
import {
  createImageMutationQueue,
  imageReferenceCount,
  loadedNotesShareImage,
  moveImageWithRollback,
  unloadedNotesReferenceImage,
} from "./image-lifecycle";

describe("image lifecycle reference checks", () => {
  it("serializes overlapping image mutations", async () => {
    const run = createImageMutationQueue();
    const events: string[] = [];
    let release!: () => void;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    const first = run(async () => {
      events.push("first:start");
      await gate;
      events.push("first:end");
    });
    const second = run(async () => {
      events.push("second");
    });

    await Promise.resolve();
    expect(events).toEqual(["first:start"]);
    release();
    await Promise.all([first, second]);
    expect(events).toEqual(["first:start", "first:end", "second"]);
  });

  it("counts only exact Markdown image paths", () => {
    const content =
      "![one](assets/a.png) ![two](assets/a.png) ![other](assets/a.png.bak)";
    expect(imageReferenceCount(content, "assets/a.png")).toBe(2);
  });

  it("treats another use in the same note or any use in another note as shared", () => {
    expect(
      loadedNotesShareImage(
        [{ id: "current", content: "![a](assets/a.png) ![b](assets/a.png)" }],
        "current",
        "assets/a.png",
      ),
    ).toBe(true);
    expect(
      loadedNotesShareImage(
        [
          { id: "current", content: "![a](assets/a.png)" },
          { id: "other", content: "![a](assets/a.png)" },
        ],
        "current",
        "assets/a.png",
      ),
    ).toBe(true);
  });

  it("scans unloaded active and trash notes in pagination batches", async () => {
    const loadFiles = vi.fn(async (paths: string[]) =>
      paths.map((path) => ({
        path,
        updatedAt: "2026-08-24T00:00:00.000Z",
        content:
          path === ".trash/old.md" ? "![still used](assets/a.png)" : "plain",
      })),
    );
    const entries = [
      { path: "loaded.md", updatedAt: "" },
      { path: "later.md", updatedAt: "" },
      { path: ".trash/old.md", updatedAt: "" },
    ];

    await expect(
      unloadedNotesReferenceImage(
        { loadFiles },
        entries,
        new Set(["loaded.md"]),
        "assets/a.png",
        1,
      ),
    ).resolves.toBe(true);
    expect(loadFiles).toHaveBeenCalledWith([".trash/old.md"]);
  });

  it("rolls a file move back when the trash index cannot be persisted", async () => {
    const move = vi.fn(async () => undefined);
    const persistenceError = new Error("disk full");

    await expect(
      moveImageWithRollback(
        { move },
        "assets/a.png",
        ".trash/assets/a.png",
        async () => {
          throw persistenceError;
        },
      ),
    ).rejects.toBe(persistenceError);
    expect(move.mock.calls).toEqual([
      ["assets/a.png", ".trash/assets/a.png"],
      [".trash/assets/a.png", "assets/a.png"],
    ]);
  });
});
