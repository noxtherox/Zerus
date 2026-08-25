import { describe, expect, it } from "vitest";
import {
  buildAiContext,
  injectAiSessionContext,
} from "./ai-context";
import type { Note } from "./note-utils";
import { setFileHubReference } from "./file-hubs";
import { setLinkHubReference } from "./link-hubs";

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
      { kind: "type", path: ["projects"] },
      vault,
    );

    expect(context?.sessionContext).toContain("Title: Alpha");
    expect(context?.sessionContext).toContain("Citation: [Alpha](zerus-note:alpha)");
    expect(context?.sessionContext).toContain('<zerus_context kind="reference-data">');
    expect(context?.sessionContext).toContain("</zerus_context>");
    expect(context?.sessionContext).toContain("### Beta");
    expect(context?.sessionContext).toContain("Citation: [Beta](zerus-note:beta)");
    expect(context?.sessionContext).not.toContain("Lisbon");
  });

  it("uses a different session key when the selected note changes", () => {
    const alphaContext = buildAiContext(
      alpha,
      [alpha, beta],
      { kind: "type", path: ["projects"] },
      vault,
    );
    const betaContext = buildAiContext(
      beta,
      [alpha, beta],
      { kind: "type", path: ["projects"] },
      vault,
    );

    expect(alphaContext?.key).not.toBe(betaContext?.key);
  });

  it("injects the current note before every visible session message", () => {
    const context = buildAiContext(
      alpha,
      [alpha, beta],
      { kind: "type", path: ["projects"] },
      vault,
    );
    expect(context).not.toBeNull();

    const messages = injectAiSessionContext(context!, [
      {
        role: "user",
        content: "What is this note?",
        images: [],
      },
    ]);

    expect(messages).toHaveLength(2);
    expect(messages[0].content).toContain("## Current note");
    expect(messages[0].content).toContain("Title: Alpha");
    expect(messages[0].content).toContain("Current body");
    expect(messages[1].content).toBe("What is this note?");
  });

  it("keeps frontmatter and internal metadata out of AI context", () => {
    const privateAlpha = note(
      "alpha",
      "projects/alpha.md",
      "---\nzerus-id: private-id\nstatus: draft\n---\n# Alpha\nCurrent body",
    );
    const context = buildAiContext(
      privateAlpha,
      [privateAlpha],
      { kind: "type", path: ["projects"] },
      vault,
    );

    expect(context?.sessionContext).toContain("# Alpha\nCurrent body");
    expect(context?.sessionContext).not.toContain("private-id");
    expect(context?.sessionContext).not.toContain("status: draft");
    expect(context?.systemPrompt).toContain("Zerus agent policy version:");
  });

  it("supports a folder-only session", () => {
    const context = buildAiContext(
      null,
      [alpha, beta],
      { kind: "type", path: ["projects"] },
      vault,
    );

    expect(context?.noteId).toBeNull();
    expect(context?.sessionContext).toContain("No note is currently selected");
    expect(context?.sessionContext).toContain("### Alpha");
  });

  it("keeps type context constrained while vault context spans ordinary notes", () => {
    const person = note("person", "People/Sarah.md", "# Sarah\nWorks at Acme");
    const company = note("company", "Companies/Acme.md", "# Acme\nCompany profile");
    const scoped = buildAiContext(
      null,
      [person, company],
      { kind: "type", path: ["People"] },
      vault,
    );
    const vaultWide = buildAiContext(
      null,
      [person, company],
      { kind: "vault" },
      vault,
    );

    expect(scoped?.scopedNoteIds).toEqual(["person"]);
    expect(scoped?.systemPrompt).toContain("ask the user to expand the context");
    expect(vaultWide?.scopedNoteIds).toEqual(["company", "person"]);
  });

  it("separates external notes, files, and links into callable scopes", () => {
    const external = { ...note("external", "outside.md", "# Outside"), externalPath: "/elsewhere/outside.md" };
    const file = note(
      "file",
      "inbox/proposal.md",
      setFileHubReference("# Proposal\n", {
        id: "file-1",
        name: "proposal.pdf",
        kind: "vault",
        path: "files/proposal.pdf",
        managed: true,
      }),
    );
    const link = note(
      "link",
      ".zerus/links/example.md",
      setLinkHubReference("# Example\n", { id: "link-1", url: "https://example.com" }),
    );
    const all = [alpha, external, file, link];

    expect(buildAiContext(null, all, { kind: "external" }, vault)?.scopedNoteIds).toEqual(["external"]);
    expect(buildAiContext(null, all, { kind: "files" }, vault)?.scopedNoteIds).toEqual(["file"]);
    expect(buildAiContext(null, all, { kind: "links" }, vault)?.scopedNoteIds).toEqual(["link"]);
  });
});
