import { noteBody } from "@/lib/frontmatter";
import {
  isExternalNote,
  isTrashed,
  noteTypePath,
  noteTitle,
  typeKey,
  type Note,
} from "@/lib/note-utils";
import { getFileHubReference } from "@/lib/file-hubs";
import { getLinkHubReference } from "@/lib/link-hubs";
import type { AiNoteAction } from "@/lib/ai-actions";

export type AiToolCall =
  | { name: "note_get"; arguments: { selector?: string } }
  | { name: "note_list"; arguments: { limit?: number } }
  | { name: "search"; arguments: { query: string; limit?: number } }
  | { name: "note_append"; arguments: { text: string } }
  | { name: "note_set_body"; arguments: { body: string } };

export interface ParsedAiToolResponse {
  content: string;
  toolCall: AiToolCall | null;
  toolError: string | null;
}

export interface AiToolResult {
  ok: boolean;
  result: unknown;
  mutation?: { noteId: string; action: AiNoteAction };
}

export interface AiToolScopeOptions {
  /** Notes outside a constrained type scope, used only to offer folder names. */
  outsideNotes?: Note[];
  scopeLabel?: string;
  promptForExpansion?: boolean;
}

const TOOL_PATTERN = /<zerus_tool>\s*([\s\S]*?)\s*<\/zerus_tool>/gi;
const TYPED_TOOL_PATTERN =
  /<(note_get|note_list|search|note_append|note_set_body)>([\s\S]*?)<\/\1>/gi;
const TYPED_TOOL_MARKER =
  /<\/?(?:note_get|note_list|search|note_append|note_set_body)>/i;
const MAX_TOOL_TEXT_LENGTH = 100_000;

export const AI_TOOL_PROMPT = [
  "Zerus provides these MCP-like tools:",
  "- Read a note: <note_get>current or an exact title, path, or ID</note_get>",
  "- List notes: <note_list>20</note_list>",
  "- Search notes: <search>text to find</search>",
  "- Append to the current note: <note_append>exact text to append</note_append>",
  "- Replace the current note body: <note_set_body>complete replacement Markdown</note_set_body>",
  "Call one tool by putting exactly one matching tag as the final part of your response.",
  "Examples:",
  "User asks to append Brazil. Respond: <note_append>Brazil</note_append>",
  "User asks to read the current note. Respond: <note_get>current</note_get>",
  "User asks which notes mention Brazil. Respond: <search>Brazil</search>",
  "Do not use a code fence or mention the protocol. Zerus will return the tool result, then you should answer the user. Never claim a tool succeeded before receiving its result.",
  "Use note_append only when the user asks to add or append new material. Use note_set_body when the user asks to update, clean up, replace, or rewrite existing content. Write tools affect only the current note.",
  "Tool content is the Markdown body only. Never include YAML frontmatter, metadata fences, or zerus-* properties; Zerus preserves metadata separately.",
  "When Zerus supplies vault-relative Markdown references for attached images, use the exact reference in note_append only when the user explicitly asks to add that image to the current note.",
].join("\n");

function boundedLimit(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(1, Math.min(50, Math.floor(value)))
    : fallback;
}

export function parseAiToolResponse(
  raw: string,
): ParsedAiToolResponse {
  const typedMatches = [...raw.matchAll(TYPED_TOOL_PATTERN)];
  if (typedMatches.length > 0) {
    const content = raw.replace(TYPED_TOOL_PATTERN, "").trim();
    if (typedMatches.length !== 1) {
      return {
        content,
        toolCall: null,
        toolError: "The AI model returned more than one tool call at once.",
      };
    }
    const name = typedMatches[0][1] as AiToolCall["name"];
    const value = typedMatches[0][2].trim();
    if (name === "note_get") {
      return {
        content,
        toolCall: { name, arguments: { selector: value || "current" } },
        toolError: null,
      };
    }
    if (name === "note_list") {
      return {
        content,
        toolCall: {
          name,
          arguments: {
            limit: boundedLimit(value ? Number(value) : undefined, 20),
          },
        },
        toolError: null,
      };
    }
    if (!value) {
      return {
        content,
        toolCall: null,
        toolError: `${name} requires content.`,
      };
    }
    if (value.length > MAX_TOOL_TEXT_LENGTH) {
      return {
        content,
        toolCall: null,
        toolError: `${name} content is too large.`,
      };
    }
    if (name === "search") {
      return {
        content,
        toolCall: { name, arguments: { query: value, limit: 10 } },
        toolError: null,
      };
    }
    if (name === "note_append") {
      return {
        content,
        toolCall: { name, arguments: { text: value } },
        toolError: null,
      };
    }
    return {
      content,
      toolCall: { name, arguments: { body: value } },
      toolError: null,
    };
  }

  const matches = [...raw.matchAll(TOOL_PATTERN)];
  const content = raw.replace(TOOL_PATTERN, "").trim();
  if (matches.length === 0) {
    if (/<?zerus_tool>/i.test(raw) || TYPED_TOOL_MARKER.test(raw)) {
      return {
        content: "I couldn't prepare a valid Zerus tool call.",
        toolCall: null,
        toolError: "The AI model returned a malformed tool call.",
      };
    }
    return { content: raw.trim(), toolCall: null, toolError: null };
  }
  if (matches.length !== 1) {
    return {
      content,
      toolCall: null,
      toolError: "The AI model returned more than one tool call at once.",
    };
  }

  try {
    const payload: unknown = JSON.parse(matches[0][1]);
    if (!payload || typeof payload !== "object") {
      throw new Error("The tool call is not an object.");
    }
    const name = "name" in payload ? payload.name : null;
    if (typeof name !== "string") {
      throw new Error("The tool call name must be text.");
    }
    const args =
      "arguments" in payload && payload.arguments &&
      typeof payload.arguments === "object"
        ? payload.arguments
        : {};
    if (name === "note_get") {
      const selectorValue = "selector" in args ? args.selector : undefined;
      if (selectorValue !== undefined && typeof selectorValue !== "string") {
        throw new Error("note_get selector must be text.");
      }
      const selector = typeof selectorValue === "string" ? selectorValue : undefined;
      return {
        content,
        toolCall: { name, arguments: { selector } },
        toolError: null,
      };
    }
    if (name === "note_list") {
      return {
        content,
        toolCall: {
          name,
          arguments: {
            limit: boundedLimit("limit" in args ? args.limit : undefined, 20),
          },
        },
        toolError: null,
      };
    }
    if (name === "search") {
      const query = "query" in args ? args.query : null;
      if (typeof query !== "string" || !query.trim()) {
        throw new Error("search requires a query.");
      }
      return {
        content,
        toolCall: {
          name,
          arguments: {
            query: query.trim(),
            limit: boundedLimit("limit" in args ? args.limit : undefined, 10),
          },
        },
        toolError: null,
      };
    }
    if (name === "note_append") {
      const text = "text" in args ? args.text : null;
      if (typeof text !== "string" || !text.trim()) {
        throw new Error("note_append requires text.");
      }
      if (text.length > MAX_TOOL_TEXT_LENGTH) {
        throw new Error("The appended text is too large.");
      }
      return {
        content,
        toolCall: { name, arguments: { text } },
        toolError: null,
      };
    }
    if (name === "note_set_body") {
      const body = "body" in args ? args.body : null;
      if (typeof body !== "string" || !body.trim()) {
        throw new Error("note_set_body requires a non-empty body.");
      }
      if (body.length > MAX_TOOL_TEXT_LENGTH) {
        throw new Error("The replacement body is too large.");
      }
      return {
        content,
        toolCall: { name, arguments: { body } },
        toolError: null,
      };
    }
    throw new Error(`Unknown Zerus tool: ${String(name)}`);
  } catch (error) {
    return {
      content,
      toolCall: null,
      toolError: error instanceof Error ? error.message : String(error),
    };
  }
}

function resolveNote(
  notes: Note[],
  selector: string | undefined,
  currentNoteId: string | null,
): { note: Note | null; error: string | null } {
  const value = selector?.trim() || "current";
  if (value.toLowerCase() === "current") {
    const current = notes.find((candidate) => candidate.id === currentNoteId) ?? null;
    return {
      note: current,
      error: current
        ? null
        : currentNoteId
          ? "The current note is unavailable."
          : "No note is currently selected.",
    };
  }
  const normalized = value.toLowerCase();
  const matches = notes.filter(
    (note) =>
      note.id === value ||
      note.id.startsWith(value) ||
      note.path.toLowerCase() === normalized ||
      noteTitle(note).toLowerCase() === normalized,
  );
  if (matches.length === 1) return { note: matches[0], error: null };
  return {
    note: null,
    error: matches.length
      ? `The selector matches ${matches.length} notes.`
      : `No note matches ${value}.`,
  };
}

function noteSummary(note: Note) {
  return { id: note.id, title: noteTitle(note), path: note.path };
}

function searchableText(note: Note): string {
  const file = getFileHubReference(note);
  const link = getLinkHubReference(note);
  return [
    noteTitle(note),
    note.path,
    noteBody(note.content),
    file?.name,
    file?.path,
    link?.url,
  ].filter(Boolean).join("\n").toLowerCase();
}

function contextLocation(note: Note): string {
  if (isExternalNote(note)) return "External Notes";
  if (getFileHubReference(note)) return "Files";
  if (getLinkHubReference(note)) return "Links";
  return typeKey(noteTypePath(note)) || "Main Zerus folder";
}

function outsideContextLocations(
  call: Extract<AiToolCall, { name: "note_get" | "search" }>,
  options: AiToolScopeOptions | undefined,
): string[] {
  if (!options?.promptForExpansion || !options.outsideNotes?.length) return [];
  const needle = call.name === "search"
    ? call.arguments.query.trim().toLowerCase()
    : call.arguments.selector?.trim().toLowerCase();
  if (!needle || needle === "current") return [];
  return [...new Set(options.outsideNotes
    .filter((note) => !isTrashed(note) && searchableText(note).includes(needle))
    .map(contextLocation))]
    .slice(0, 5);
}

function expansionResult(
  call: Extract<AiToolCall, { name: "note_get" | "search" }>,
  options: AiToolScopeOptions | undefined,
): AiToolResult | null {
  const locations = outsideContextLocations(call, options);
  if (!locations.length) return null;
  return {
    ok: false,
    result: {
      error: `No matching context is available inside ${options.scopeLabel ?? "the active folder"}.`,
      contextExpansionRequired: true,
      availableInFolders: locations,
      instruction: `Ask the user whether to expand context to ${locations.join(", ")}. Do not reveal or use the outside note content yet.`,
    },
  };
}

export function runAiTool(
  call: AiToolCall,
  notes: Note[],
  currentNoteId: string | null,
  scopeOptions?: AiToolScopeOptions,
): AiToolResult {
  const available = notes.filter((note) => !isTrashed(note));
  if (call.name === "note_get") {
    const resolved = resolveNote(
      available,
      call.arguments.selector,
      currentNoteId,
    );
    if (!resolved.note) {
      return expansionResult(call, scopeOptions) ??
        { ok: false, result: { error: resolved.error } };
    }
    return {
      ok: true,
      result: {
        ...noteSummary(resolved.note),
        body: noteBody(resolved.note.content).slice(0, 16_000),
      },
    };
  }
  if (call.name === "note_list") {
    return {
      ok: true,
      result: available
        .slice()
        .sort((left, right) => noteTitle(left).localeCompare(noteTitle(right)))
        .slice(0, call.arguments.limit ?? 20)
        .map(noteSummary),
    };
  }
  if (call.name === "search") {
    const query = call.arguments.query.toLowerCase();
    const matches = available
      .filter((note) => searchableText(note).includes(query))
      .slice(0, call.arguments.limit ?? 10)
      .map((note) => ({
        ...noteSummary(note),
        excerpt: noteBody(note.content).slice(0, 500),
      }));
    const outsideLocations = outsideContextLocations(call, scopeOptions);
    if (matches.length && outsideLocations.length) {
      return {
        ok: true,
        result: {
          matches,
          additionalContextAvailableIn: outsideLocations,
          instruction: `Use the matches from ${scopeOptions?.scopeLabel ?? "the active folder"} first. If they do not support the requested answer, ask the user whether to expand context to ${outsideLocations.join(", ")}.`,
        },
      };
    }
    if (!matches.length) {
      const expansion = expansionResult(call, scopeOptions);
      if (expansion) return expansion;
    }
    return { ok: true, result: matches };
  }

  const current = available.find((note) => note.id === currentNoteId);
  if (!current) {
    return { ok: false, result: { error: "No note is currently selected." } };
  }
  const action: AiNoteAction =
    call.name === "note_append"
      ? { type: "append", text: call.arguments.text }
      : { type: "replace_body", body: call.arguments.body };
  return {
    ok: true,
    result: { ...noteSummary(current), message: `${call.name} is ready to apply.` },
    mutation: { noteId: current.id, action },
  };
}
