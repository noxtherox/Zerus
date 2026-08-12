import { describe, expect, it } from "vitest";
import {
  appendAssistantMessage,
  CHAT_ROOT,
  createChatWithUserMessage,
  chatContentRevision,
  foldChatEvents,
  loadChatConversations,
  titleFromQuestion,
  transferChatOwnership,
  unansweredTurnIds,
  type ChatDescriptor,
  type ChatEvent,
  type PersistedChatMessage,
} from "./mobile-chat-history";
import type { VaultBackend } from "./vault/backend";

function memoryBackend(): VaultBackend {
  const files = new Map<string, string>();
  const binaries = new Map<string, Uint8Array>();
  return {
    kind: "browser",
    location: "Memory",
    async loadAll() { return []; },
    async listFiles(path) {
      const prefix = `${path.replace(/\/$/, "")}/`;
      return [...files.keys()].filter((candidate) => candidate.startsWith(prefix)).sort();
    },
    async readText(path) {
      const value = files.get(path);
      if (value === undefined) throw new Error(`Missing ${path}`);
      return value;
    },
    async write(path, content) { files.set(path, content); },
    async writeNew(path, content) {
      if (files.has(path)) throw new Error(`Exists ${path}`);
      files.set(path, content);
    },
    async move(from, to) {
      const value = files.get(from);
      if (value !== undefined) { files.delete(from); files.set(to, value); }
    },
    async removeFile(path) { files.delete(path); },
    async exists(path) { return files.has(path) || [...files.keys()].some((candidate) => candidate.startsWith(`${path}/`)); },
    async mkDir() {},
    async removeDir(path) {
      for (const candidate of [...files.keys()]) {
        if (candidate === path || candidate.startsWith(`${path}/`)) files.delete(candidate);
      }
    },
    async renameDir() {},
    async listDirs() { return []; },
    async writeBinary(path, bytes) { binaries.set(path, bytes); },
    async readBinary(path) {
      const value = binaries.get(path);
      if (!value) throw new Error(`Missing ${path}`);
      return value;
    },
  };
}

const descriptor: ChatDescriptor = {
  version: 1,
  id: "chat-1",
  createdAt: "2026-08-04T10:00:00.000Z",
};

function ownership(id: string, generation: number, deviceId: string, name: string): ChatEvent {
  return {
    version: 1,
    id,
    conversationId: descriptor.id,
    at: `2026-08-04T10:0${generation}:00.000Z`,
    deviceId,
    ownerGeneration: generation,
    kind: "ownership",
    owner: { id: deviceId, name },
  };
}

function message(id: string, generation: number, deviceId: string, role: "user" | "assistant", text: string, turnId = id): ChatEvent {
  const value: PersistedChatMessage = {
    id,
    turnId,
    role,
    text,
    createdAt: `2026-08-04T10:0${generation}:01.000Z`,
    deviceId,
    ownerGeneration: generation,
  };
  return {
    version: 1,
    id: `event-${id}`,
    conversationId: descriptor.id,
    at: value.createdAt,
    deviceId,
    ownerGeneration: generation,
    kind: "message",
    message: value,
  };
}

describe("mobile chat event folding", () => {
  it("uses deterministic event IDs to break simultaneous ownership ties", () => {
    const events: ChatEvent[] = [
      ownership("owner-a", 1, "iphone", "iPhone"),
      message("question", 1, "iphone", "user", "Plan the garden"),
      ownership("transfer-a", 2, "ipad", "iPad"),
      ownership("transfer-z", 2, "mac", "Mac"),
    ];

    const conversation = foldChatEvents(descriptor, events);

    expect(conversation?.owner).toEqual({ id: "mac", name: "Mac" });
    expect(conversation?.ownerGeneration).toBe(2);
    expect(conversation?.ownerEventId).toBe("transfer-z");
  });

  it("preserves losing-owner messages but rejects its management events", () => {
    const events: ChatEvent[] = [
      ownership("owner-a", 1, "iphone", "iPhone"),
      message("question", 1, "iphone", "user", "Plan the garden", "turn"),
      ownership("transfer-a", 2, "ipad", "iPad"),
      ownership("transfer-z", 2, "mac", "Mac"),
      message("ipad-answer", 2, "ipad", "assistant", "Use raised beds.", "turn"),
      message("mac-answer", 2, "mac", "assistant", "Start with herbs.", "turn"),
      {
        version: 1, id: "rename-loser", conversationId: descriptor.id,
        at: "2026-08-04T10:03:00.000Z", deviceId: "ipad", ownerGeneration: 2,
        kind: "rename", title: "Losing title",
      },
      {
        version: 1, id: "rename-winner", conversationId: descriptor.id,
        at: "2026-08-04T10:04:00.000Z", deviceId: "mac", ownerGeneration: 2,
        kind: "rename", title: "Garden plan",
      },
    ];

    const conversation = foldChatEvents(descriptor, events);

    expect(conversation?.messages.map((entry) => entry.id)).toEqual([
      "question", "ipad-answer", "mac-answer",
    ]);
    expect(conversation?.title).toBe("Garden plan");
  });

  it("treats an empty summary event as a memory reset", () => {
    const events: ChatEvent[] = [
      ownership("owner-a", 1, "iphone", "iPhone"),
      message("question", 1, "iphone", "user", "Remember this"),
      {
        version: 1, id: "summary", conversationId: descriptor.id,
        at: "2026-08-04T10:03:00.000Z", deviceId: "iphone", ownerGeneration: 1,
        kind: "summary", text: "", coveredMessageIds: [],
      },
    ];

    expect(foldChatEvents(descriptor, events)?.summary).toBeNull();
  });
});

describe("mobile chat vault persistence", () => {
  it("reopens messages and ownership transfers from immutable event files", async () => {
    const backend = memoryBackend();
    const iphone = { id: "iphone", name: "iPhone" };
    const mac = { id: "mac", name: "Mac" };
    const created = await createChatWithUserMessage(backend, iphone, "Where is the plan?");
    let [conversation] = await loadChatConversations(backend);

    await appendAssistantMessage(backend, conversation, iphone, {
      turnId: created.turnId,
      text: "It is in Projects.",
      sources: [],
      contextKind: "matches",
    });
    [conversation] = await loadChatConversations(backend);
    await transferChatOwnership(backend, conversation, mac);
    [conversation] = await loadChatConversations(backend);

    expect(conversation.id).toBe(created.conversationId);
    expect(conversation.messages.map((entry) => entry.text)).toEqual([
      "Where is the plan?", "It is in Projects.",
    ]);
    expect(conversation.owner).toEqual(mac);
    expect(conversation.ownerGeneration).toBe(2);
  });

  it("stores normalized images as assets instead of embedding bytes in events", async () => {
    const backend = memoryBackend();
    await createChatWithUserMessage(backend, { id: "iphone", name: "iPhone" }, "Read this", {
      bytes: new Uint8Array([255, 216, 255, 217]),
      mimeType: "image/jpeg",
      width: 64,
      height: 48,
      name: "receipt.jpg",
    });

    const [conversation] = await loadChatConversations(backend);
    const attachment = conversation.messages[0].attachments?.[0];
    expect(attachment?.path).toMatch(/^\.grimoire\/chats\/[^/]+\/assets\/[^/]+\.jpg$/);
    expect(attachment?.byteLength).toBe(4);
    expect(await backend.readBinary(attachment!.path)).toEqual(new Uint8Array([255, 216, 255, 217]));
    const eventPaths = await backend.listFiles(`${CHAT_ROOT}/${conversation.id}/events`);
    expect(await backend.readText(eventPaths[0])).not.toContain("255,216,255,217");
  });
});

describe("mobile chat helpers", () => {
  it("derives compact titles and stable content revisions", () => {
    expect(titleFromQuestion("  What   changed today?  ")).toBe("What changed today?");
    expect(titleFromQuestion("x".repeat(100))).toHaveLength(62);
    expect(chatContentRevision("same")).toBe(chatContentRevision("same"));
    expect(chatContentRevision("same")).not.toBe(chatContentRevision("different"));
  });

  it("finds persisted questions without answers", () => {
    const user = (id: string): PersistedChatMessage => ({
      id: `user-${id}`, turnId: id, role: "user", text: id,
      createdAt: descriptor.createdAt, deviceId: "iphone", ownerGeneration: 1,
    });
    const assistant: PersistedChatMessage = {
      ...user("answered"), id: "assistant", role: "assistant",
    };
    expect(unansweredTurnIds([user("answered"), assistant, user("interrupted")]))
      .toEqual(["interrupted"]);
  });
});
