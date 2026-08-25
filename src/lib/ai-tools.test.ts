import { describe, expect, it } from "vitest";
import type { Note } from "./note-utils";
import {
  AI_TOOL_PROMPT,
  parseAiToolResponse,
  runAiTool,
} from "./ai-tools";

const notes: Note[] = [
  {
    id: "braskem-id",
    path: "Companies/Braskem.md",
    content: "# Braskem\n\nBrazilian company",
    pinned: false,
    updatedAt: "2026-08-11T00:00:00.000Z",
  },
];

describe("parseAiToolResponse", () => {
  it("gives the AI provider concrete tool-call examples", () => {
    expect(AI_TOOL_PROMPT).toContain("<note_append>Brazil</note_append>");
    expect(AI_TOOL_PROMPT).toContain("<note_get>current</note_get>");
    expect(AI_TOOL_PROMPT).toContain("Never include YAML frontmatter");
    expect(AI_TOOL_PROMPT).toContain("update, clean up, replace, or rewrite");
  });

  it("parses the supported typed tool tags", () => {
    expect(
      parseAiToolResponse(
        "<note_append>Braskem is a Brazilian company.</note_append>",
      ).toolCall,
    ).toEqual({
      name: "note_append",
      arguments: { text: "Braskem is a Brazilian company." },
    });
  });

  it("parses one valid CLI-like tool call", () => {
    const parsed = parseAiToolResponse(
      'I will check.\n<zerus_tool>{"name":"search","arguments":{"query":"Brazil"}}</zerus_tool>',
    );
    expect(parsed.content).toBe("I will check.");
    expect(parsed.toolCall).toEqual({
      name: "search",
      arguments: { query: "Brazil", limit: 10 },
    });
    expect(parsed.toolError).toBeNull();
  });

  it("does not execute a malformed tool call", () => {
    expect(
      parseAiToolResponse(
        'zerus_tool>{"name":"note_append","arguments":{"text":"Brazil"}}',
      ).toolError,
    ).toContain("malformed");
  });
});

describe("runAiTool", () => {
  it("reads and searches notes", () => {
    expect(runAiTool({ name: "note_get", arguments: {} }, notes, "braskem-id").ok).toBe(true);
    expect(
      runAiTool(
        { name: "search", arguments: { query: "Brazil", limit: 10 } },
        notes,
        "braskem-id",
      ).result,
    ).toHaveLength(1);
  });

  it("prepares current-note mutations without applying them", () => {
    expect(
      runAiTool(
        { name: "note_append", arguments: { text: "More" } },
        notes,
        "braskem-id",
      ).mutation,
    ).toEqual({
      noteId: "braskem-id",
      action: { type: "append", text: "More" },
    });
  });

  it("offers folder expansion without exposing outside note content", () => {
    const result = runAiTool(
      { name: "search", arguments: { query: "Braskem", limit: 10 } },
      [],
      null,
      {
        outsideNotes: notes,
        scopeLabel: "People",
        promptForExpansion: true,
      },
    );

    expect(result.ok).toBe(false);
    expect(result.result).toMatchObject({
      contextExpansionRequired: true,
      availableInFolders: ["Companies"],
    });
    expect(JSON.stringify(result.result)).not.toContain("Brazilian company");
  });
});
