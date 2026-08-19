import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  aiConversationKey,
  clearAiConversation,
  readAiConversation,
  saveAiConversation,
} from "@/lib/ai-conversations";

describe("AI conversations", () => {
  beforeEach(() => {
    const values = new Map<string, string>();
    vi.stubGlobal("localStorage", {
      clear: () => values.clear(),
      getItem: (key: string) => values.get(key) ?? null,
      removeItem: (key: string) => values.delete(key),
      setItem: (key: string, value: string) => values.set(key, value),
    });
  });

  it("keeps conversations separate for each note and vault", () => {
    const alpha = aiConversationKey("/Vault", "alpha.md", null);
    const beta = aiConversationKey("/Vault", "beta.md", null);
    const otherVault = aiConversationKey("/Other", "alpha.md", null);

    saveAiConversation(alpha, [{ role: "user", content: "About alpha" }]);
    saveAiConversation(beta, [{ role: "user", content: "About beta" }]);

    expect(readAiConversation(alpha)).toEqual([
      { role: "user", content: "About alpha" },
    ]);
    expect(readAiConversation(beta)).toEqual([
      { role: "user", content: "About beta" },
    ]);
    expect(readAiConversation(otherVault)).toEqual([]);
  });

  it("clears only the selected note's session", () => {
    const alpha = aiConversationKey("/Vault", "alpha.md", null);
    const beta = aiConversationKey("/Vault", "beta.md", null);
    saveAiConversation(alpha, [{ role: "user", content: "Alpha" }]);
    saveAiConversation(beta, [{ role: "user", content: "Beta" }]);

    clearAiConversation(alpha);

    expect(readAiConversation(alpha)).toEqual([]);
    expect(readAiConversation(beta)).toHaveLength(1);
  });

  it("ignores malformed stored history", () => {
    localStorage.setItem("zerus.ai.conversations.v1", "not-json");
    expect(readAiConversation("anything")).toEqual([]);
  });

  it("keeps the most recent 64 messages", () => {
    const key = aiConversationKey("/Vault", "alpha.md", null);
    saveAiConversation(
      key,
      Array.from({ length: 70 }, (_, index) => ({
        role: index % 2 === 0 ? ("user" as const) : ("assistant" as const),
        content: String(index),
      })),
    );

    const messages = readAiConversation(key);
    expect(messages).toHaveLength(64);
    expect(messages[0].content).toBe("6");
    expect(messages[63].content).toBe("69");
  });

  it("persists bounded tool-call activity with the assistant message", () => {
    const key = aiConversationKey("/Vault", "alpha.md", null);
    saveAiConversation(key, [{
      role: "assistant",
      content: "I found it.",
      toolCalls: [{
        name: "search",
        arguments: '{"query":"alpha"}',
        result: '{"ok":true,"matches":1}',
        status: "complete",
      }],
    }]);

    expect(readAiConversation(key)[0].toolCalls).toEqual([{
      name: "search",
      arguments: '{"query":"alpha"}',
      result: '{"ok":true,"matches":1}',
      status: "complete",
    }]);
  });

  it("persists vault-relative image references without image bytes", () => {
    const key = aiConversationKey("/Vault", "alpha.md", null);
    saveAiConversation(key, [{
      role: "user",
      content: "What is in this image?",
      attachments: [{
        id: "image-1",
        path: "assets/pasted-20260819-120000.jpg",
        mimeType: "image/jpeg",
        width: 1024,
        height: 768,
        byteLength: 123456,
        name: "receipt.jpg",
      }],
    }]);

    expect(readAiConversation(key)[0].attachments?.[0].path).toBe(
      "assets/pasted-20260819-120000.jpg",
    );
    expect(JSON.stringify(readAiConversation(key))).not.toContain("base64");
  });

  it("rejects image references outside the vault assets folder", () => {
    const key = aiConversationKey("/Vault", "alpha.md", null);
    saveAiConversation(key, [{
      role: "user",
      content: "unsafe",
      attachments: [{
        id: "image-1",
        path: "../secret.jpg",
        mimeType: "image/jpeg",
        width: 100,
        height: 100,
        byteLength: 100,
      }],
    }]);

    expect(readAiConversation(key)).toEqual([]);
  });
});
