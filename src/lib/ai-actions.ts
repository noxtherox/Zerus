export type AiNoteAction =
  | { type: "append"; text: string }
  | { type: "replace_body"; body: string };

export interface ParsedAiResponse {
  content: string;
  action: AiNoteAction | null;
  actionError: string | null;
}

const ACTION_PATTERN = /<zerus_action>\s*([\s\S]*?)\s*<\/zerus_action>/gi;
const MAX_ACTION_TEXT_LENGTH = 100_000;

/**
 * Handles the safest edit command without relying on a small model to produce
 * valid structured output. Broader requests still go to the configured AI provider.
 */
export function directAiNoteAction(
  request: string,
): AiNoteAction | null {
  if (!/\b(?:add|append|put)\b/i.test(request)) return null;
  if (!/\b(?:note|end|bottom)\b/i.test(request)) return null;
  if (/\b(?:do not|don't|never)\s+(?:add|append|put)\b/i.test(request)) {
    return null;
  }

  const quoted = [
    ...request.matchAll(/"([^"\r\n]+)"|“([^”\r\n]+)”/g),
  ];
  if (quoted.length !== 1) return null;
  const text = (quoted[0][1] ?? quoted[0][2] ?? "").trim();
  if (!text || text.length > MAX_ACTION_TEXT_LENGTH) return null;
  return { type: "append", text };
}

export function parseAiResponse(raw: string): ParsedAiResponse {
  const matches = [...raw.matchAll(ACTION_PATTERN)];
  const content = raw.replace(ACTION_PATTERN, "").trim();
  if (matches.length === 0) {
    if (/<?zerus_action>/i.test(raw)) {
      return {
        content: "I couldn't prepare a valid note edit.",
        action: null,
        actionError: "The AI provider returned a malformed note edit.",
      };
    }
    return { content: raw.trim(), action: null, actionError: null };
  }
  if (matches.length !== 1) {
    return {
      content,
      action: null,
      actionError: "The AI provider returned more than one note edit.",
    };
  }

  try {
    const payload: unknown = JSON.parse(matches[0][1]);
    if (!payload || typeof payload !== "object" || !("type" in payload)) {
      throw new Error("The note edit is missing its type.");
    }
    if (
      payload.type === "append" &&
      "text" in payload &&
      typeof payload.text === "string" &&
      payload.text.trim()
    ) {
      if (payload.text.length > MAX_ACTION_TEXT_LENGTH) {
        throw new Error("The note edit is too large.");
      }
      return {
        content,
        action: { type: "append", text: payload.text },
        actionError: null,
      };
    }
    if (
      payload.type === "replace_body" &&
      "body" in payload &&
      typeof payload.body === "string" &&
      payload.body.trim()
    ) {
      if (payload.body.length > MAX_ACTION_TEXT_LENGTH) {
        throw new Error("The note edit is too large.");
      }
      return {
        content,
        action: { type: "replace_body", body: payload.body },
        actionError: null,
      };
    }
    throw new Error("The AI provider returned an unsupported or empty note edit.");
  } catch (error) {
    return {
      content,
      action: null,
      actionError: error instanceof Error ? error.message : String(error),
    };
  }
}

export function applyAiNoteAction(
  currentBody: string,
  action: AiNoteAction,
): string {
  if (action.type === "replace_body") return action.body;
  if (!currentBody.trim()) return action.text.trim();
  return `${currentBody.trimEnd()}\n\n${action.text.trim()}`;
}
