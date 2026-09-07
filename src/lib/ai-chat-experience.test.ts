import { describe, expect, it } from "vitest";
import {
  budgetChatHistory,
  visibleChatStream,
  planAiUndo,
} from "./ai-chat-experience";

describe("chat request boundaries", () => {
  it("keeps complete recent turns without modifying the saved transcript", () => {
    const messages = [
      { role: "user" as const, content: "older question" },
      { role: "assistant" as const, content: "older answer" },
      { role: "user" as const, content: "recent" },
      { role: "assistant" as const, content: "reply" },
      { role: "user" as const, content: "now" },
    ];
    expect(budgetChatHistory(messages, 14)).toEqual({
      messages: messages.slice(2),
      omitted: 2,
    });
    expect(messages).toHaveLength(5);
    expect(() =>
      budgetChatHistory([{ role: "user", content: "too large" }], 3),
    ).toThrow("too long");
  });
  it("hides partially streamed tool and edit syntax on both platforms", () => {
    expect(visibleChatStream('Looking it up.\n<zerus_tool>{"name":')).toBe(
      "Looking it up.",
    );
    expect(visibleChatStream('Updated.\n<zerus-action>{"action":')).toBe(
      "Updated.",
    );
    expect(visibleChatStream("Hello <zer")).toBe("Hello");
    expect(visibleChatStream("Source: [Plan](zerus-note:")).toBe("Source:");
    expect(visibleChatStream("### Result\n\n- One\n- Two")).toContain("- Two");
  });
});

it("undo restores the original across multiple AI edits and refuses later user changes", () => {
  const changes = [
    { noteId: "a", title: "A", before: "original", after: "edit1" },
    { noteId: "a", title: "A", before: "edit1", after: "edit2" },
  ];
  expect(planAiUndo(changes, new Map([["a", "edit2"]]))).toEqual(
    new Map([["a", "original"]]),
  );
  expect(() => planAiUndo(changes, new Map([["a", "user edit"]]))).toThrow(
    "note changed",
  );
});
