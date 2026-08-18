import { describe, expect, it } from "vitest";
import type { Note } from "./note-utils";
import {
  LOCAL_AI_TOOL_PROMPT,
  parseLocalAiToolResponse,
  runLocalAiTool,
} from "./local-ai-tools";

const notes: Note[] = [
  {
    id: "braskem-id",
    path: "Companies/Braskem.md",
    content: "# Braskem\n\nBrazilian company",
    pinned: false,
    updatedAt: "2026-08-11T00:00:00.000Z",
  },
];

describe("parseLocalAiToolResponse", () => {
  it("gives the small local model concrete tool-call examples", () => {
    expect(LOCAL_AI_TOOL_PROMPT).toContain("<note_append>Brazil</note_append>");
    expect(LOCAL_AI_TOOL_PROMPT).toContain("<note_get>current</note_get>");
  });

  it("parses the typed tags Qwen reliably generates", () => {
    expect(
      parseLocalAiToolResponse(
        "<note_append>Braskem is a Brazilian company.</note_append>",
      ).toolCall,
    ).toEqual({
      name: "note_append",
      arguments: { text: "Braskem is a Brazilian company." },
    });
  });

  it("parses one valid CLI-like tool call", () => {
    const parsed = parseLocalAiToolResponse(
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
      parseLocalAiToolResponse(
        'zerus_tool>{"name":"note_append","arguments":{"text":"Brazil"}}',
      ).toolError,
    ).toContain("malformed");
  });
});

describe("runLocalAiTool", () => {
  it("reads and searches notes", () => {
    expect(runLocalAiTool({ name: "note_get", arguments: {} }, notes, "braskem-id").ok).toBe(true);
    expect(
      runLocalAiTool(
        { name: "search", arguments: { query: "Brazil", limit: 10 } },
        notes,
        "braskem-id",
      ).result,
    ).toHaveLength(1);
  });

  it("prepares current-note mutations without applying them", () => {
    expect(
      runLocalAiTool(
        { name: "note_append", arguments: { text: "More" } },
        notes,
        "braskem-id",
      ).mutation,
    ).toEqual({
      noteId: "braskem-id",
      action: { type: "append", text: "More" },
    });
  });
});
