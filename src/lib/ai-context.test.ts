import { describe, expect, it } from "vitest";
import {
  buildAiContext,
  injectAiSessionContext,
} from "./ai-context";
import type { Note } from "./note-utils";

function note(id: string, path: string, content: string): Note {
  return {
    id,
    path,
    content,
    pinned: false,
    updatedAt: "2026-08-11T00:00:00.000Z",
  };
}

describe("buildAiContext", () => {
  const vault = "/vault";
  const alpha = note("alpha", "projects/alpha.md", "# Alpha\nCurrent body");
  const beta = note("beta", "projects/beta.md", "# Beta\nSibling body");
  const elsewhere = note("travel", "travel/lisbon.md", "# Lisbon\nPack");

  it("includes the current note and sibling notes from only its folder", () => {
    const context = buildAiContext(
      alpha,
      [alpha, beta, elsewhere],
      "/vault/projects",
      vault,
    );

    expect(context?.sessionContext).toContain("Title: Alpha");
    expect(context?.sessionContext).toContain("### Beta");
    expect(context?.sessionContext).not.toContain("Lisbon");
  });

  it("uses a different session key when the selected note changes", () => {
    const alphaContext = buildAiContext(
      alpha,
      [alpha, beta],
      "/vault/projects",
      vault,
    );
    const betaContext = buildAiContext(
      beta,
      [alpha, beta],
      "/vault/projects",
      vault,
    );

    expect(alphaContext?.key).not.toBe(betaContext?.key);
  });

  it("injects the current note before every visible session message", () => {
    const context = buildAiContext(
      alpha,
      [alpha, beta],
      "/vault/projects",
      vault,
    );
    expect(context).not.toBeNull();

    const messages = injectAiSessionContext(context!, [
      {
        role: "user",
        content: "What is this note?",
        imagePaths: [],
      },
    ]);

    expect(messages).toHaveLength(2);
    expect(messages[0].content).toContain("## Current note");
    expect(messages[0].content).toContain("Title: Alpha");
    expect(messages[0].content).toContain("Current body");
    expect(messages[1].content).toBe("What is this note?");
  });

  it("supports a folder-only session", () => {
    const context = buildAiContext(
      null,
      [alpha, beta],
      "/vault/projects",
      vault,
    );

    expect(context?.noteId).toBeNull();
    expect(context?.sessionContext).toContain("No note is currently selected");
    expect(context?.sessionContext).toContain("### Alpha");
  });
});
