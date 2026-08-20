import type { VaultBackend } from "@/lib/vault/backend";
import type { NoteContextKind } from "@/lib/mobile-note-retrieval";
import type { StoredAiMessage } from "@/lib/ai-conversations";

export const CHAT_ROOT = ".zerus/chats";
export const CHAT_TOMBSTONE_ROOT = ".zerus/chat-tombstones";
export const CHAT_RETENTION_MS = 30 * 24 * 60 * 60 * 1_000;

const immutableJsonCache = new WeakMap<VaultBackend, Map<string, unknown>>();

export interface ChatDevice {
  id: string;
  name: string;
}

export type ChatScope =
  | { kind: "vault" }
  | { kind: "type"; path: string[] }
  | { kind: "note"; noteId: string; title: string };

export interface ChatSourceSnapshot {
  noteId: string;
  title: string;
  type: string;
  excerpt: string;
  revision: string;
}

export interface ChatImageAttachment {
  id: string;
  path: string;
  mimeType: "image/jpeg";
  width: number;
  height: number;
  byteLength: number;
  name?: string;
}

export interface NewChatImageAttachment {
  bytes: Uint8Array;
  mimeType: "image/jpeg";
  width: number;
  height: number;
  name?: string;
}

export interface PersistedChatMessage {
  id: string;
  turnId: string;
  role: "user" | "assistant";
  text: string;
  createdAt: string;
  deviceId: string;
  ownerGeneration: number;
  sources?: ChatSourceSnapshot[];
  contextKind?: NoteContextKind;
  attachments?: ChatImageAttachment[];
}

export interface ChatDescriptor {
  version: 1;
  id: string;
  createdAt: string;
  scope?: ChatScope;
  legacyKey?: string;
}

interface ChatEventBase {
  version: 1;
  id: string;
  conversationId: string;
  at: string;
  deviceId: string;
  ownerGeneration: number;
}

export type ChatEvent =
  | (ChatEventBase & { kind: "ownership"; owner: ChatDevice })
  | (ChatEventBase & { kind: "message"; message: PersistedChatMessage })
  | (ChatEventBase & { kind: "rename"; title: string })
  | (ChatEventBase & { kind: "archive" | "restore" | "delete" })
  | (ChatEventBase & {
      kind: "summary";
      text: string;
      coveredMessageIds: string[];
    });

export interface ChatSummary {
  text: string;
  coveredMessageIds: string[];
  updatedAt: string;
}

export interface ChatConversation {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  owner: ChatDevice;
  ownerGeneration: number;
  ownerEventId: string;
  messages: PersistedChatMessage[];
  summary: ChatSummary | null;
  archivedAt: string | null;
  deletedAt: string | null;
  scope: ChatScope;
}

export interface NewAssistantMessage {
  turnId: string;
  text: string;
  sources: ChatSourceSnapshot[];
  contextKind: NoteContextKind;
}

function uuid(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`;
}

function stableId(value: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

function eventPath(conversationId: string, eventId: string): string {
  return `${CHAT_ROOT}/${conversationId}/events/${eventId}.json`;
}

async function storeImageAttachment(
  backend: VaultBackend,
  conversationId: string,
  image?: NewChatImageAttachment | NewChatImageAttachment[],
): Promise<ChatImageAttachment[] | undefined> {
  const images = (Array.isArray(image) ? image : image ? [image] : []).slice(0, 4);
  if (!images.length) return undefined;
  return Promise.all(images.map(async (entry) => {
    const id = uuid();
    const path = `${CHAT_ROOT}/${conversationId}/assets/${id}.jpg`;
    await backend.writeBinary(path, entry.bytes);
    return {
      id,
      path,
      mimeType: entry.mimeType,
      width: entry.width,
      height: entry.height,
      byteLength: entry.bytes.byteLength,
      name: entry.name,
    };
  }));
}

function compareEvents(a: ChatEvent, b: ChatEvent): number {
  return (
    a.ownerGeneration - b.ownerGeneration ||
    a.at.localeCompare(b.at) ||
    a.id.localeCompare(b.id)
  );
}

function latestOwnership(events: ChatEvent[]): Extract<ChatEvent, { kind: "ownership" }> | null {
  return events
    .filter((event): event is Extract<ChatEvent, { kind: "ownership" }> => event.kind === "ownership")
    .sort((a, b) => a.ownerGeneration - b.ownerGeneration || a.id.localeCompare(b.id))
    .at(-1) ?? null;
}

function eventWasWrittenByGenerationOwner(event: ChatEvent, events: ChatEvent[]): boolean {
  const owner = events
    .filter((candidate): candidate is Extract<ChatEvent, { kind: "ownership" }> =>
      candidate.kind === "ownership" && candidate.ownerGeneration === event.ownerGeneration)
    .sort((a, b) => a.id.localeCompare(b.id))
    .at(-1);
  return Boolean(owner && owner.owner.id === event.deviceId);
}

export function foldChatEvents(
  descriptor: ChatDescriptor,
  sourceEvents: ChatEvent[],
): ChatConversation | null {
  const events = sourceEvents
    .filter((event) => event.conversationId === descriptor.id)
    .sort(compareEvents);
  const ownership = latestOwnership(events);
  if (!ownership) return null;

  const validEvents = events.filter((event) =>
    event.kind === "ownership" || event.kind === "message" || eventWasWrittenByGenerationOwner(event, events),
  );
  const messagesById = new Map<string, PersistedChatMessage>();
  for (const event of validEvents) {
    if (event.kind === "message") messagesById.set(event.message.id, event.message);
  }
  const messages = [...messagesById.values()].sort(
    (a, b) => a.createdAt.localeCompare(b.createdAt) ||
      (a.turnId === b.turnId && a.role !== b.role ? (a.role === "user" ? -1 : 1) : a.id.localeCompare(b.id)),
  );
  if (messages.length === 0) return null;

  const renames = validEvents.filter(
    (event): event is Extract<ChatEvent, { kind: "rename" }> => event.kind === "rename",
  );
  const lifecycle = validEvents.filter((event) =>
    event.kind === "archive" || event.kind === "restore" || event.kind === "delete",
  );
  let archivedAt: string | null = null;
  let deletedAt: string | null = null;
  for (const event of lifecycle) {
    if (event.kind === "archive") archivedAt = event.at;
    if (event.kind === "delete") deletedAt = event.at;
    if (event.kind === "restore") {
      archivedAt = null;
      deletedAt = null;
    }
  }
  const summaryEvent = validEvents
    .filter((event): event is Extract<ChatEvent, { kind: "summary" }> => event.kind === "summary")
    .at(-1);
  const latestActivity = validEvents
    .filter((event) => event.kind === "message" || event.kind === "ownership")
    .at(-1)?.at ?? descriptor.createdAt;

  return {
    id: descriptor.id,
    title: renames.at(-1)?.title ?? titleFromQuestion(messages.find((message) => message.role === "user")?.text ?? "New chat"),
    createdAt: descriptor.createdAt,
    updatedAt: latestActivity,
    owner: ownership.owner,
    ownerGeneration: ownership.ownerGeneration,
    ownerEventId: ownership.id,
    messages,
    summary: summaryEvent?.text.trim() ? {
      text: summaryEvent.text,
      coveredMessageIds: summaryEvent.coveredMessageIds,
      updatedAt: summaryEvent.at,
    } : null,
    archivedAt,
    deletedAt,
    scope: descriptor.scope ?? { kind: "vault" },
  };
}

function isChatDescriptor(value: unknown): value is ChatDescriptor {
  if (!value || typeof value !== "object") return false;
  const descriptor = value as Partial<ChatDescriptor>;
  return descriptor.version === 1 && typeof descriptor.id === "string" && typeof descriptor.createdAt === "string";
}

function isChatEvent(value: unknown): value is ChatEvent {
  if (!value || typeof value !== "object") return false;
  const event = value as Partial<ChatEvent>;
  return event.version === 1 && typeof event.id === "string" &&
    typeof event.conversationId === "string" && typeof event.at === "string" &&
    typeof event.deviceId === "string" && typeof event.ownerGeneration === "number" &&
    typeof event.kind === "string";
}

async function readJson(backend: VaultBackend, path: string): Promise<unknown | null> {
  let backendCache = immutableJsonCache.get(backend);
  if (!backendCache) {
    backendCache = new Map();
    immutableJsonCache.set(backend, backendCache);
  }
  if (backendCache.has(path)) return backendCache.get(path) ?? null;
  try {
    const value = JSON.parse(await backend.readText(path)) as unknown;
    backendCache.set(path, value);
    return value;
  } catch {
    return null;
  }
}

export async function loadChatConversations(backend: VaultBackend): Promise<ChatConversation[]> {
  const paths = await backend.listFiles(CHAT_ROOT);
  const descriptorPaths = paths.filter((path) => path.endsWith("/conversation.json"));
  const tombstones = new Set(
    (await backend.listFiles(CHAT_TOMBSTONE_ROOT))
      .map((path) => path.match(/\/([^/]+)\.json$/)?.[1])
      .filter((id): id is string => Boolean(id)),
  );
  const conversations = await Promise.all(descriptorPaths.map(async (descriptorPath) => {
    const descriptorValue = await readJson(backend, descriptorPath);
    if (!isChatDescriptor(descriptorValue) || tombstones.has(descriptorValue.id)) return null;
    const prefix = `${CHAT_ROOT}/${descriptorValue.id}/events/`;
    const eventValues = await Promise.all(
      paths.filter((path) => path.startsWith(prefix) && path.endsWith(".json"))
        .map((path) => readJson(backend, path)),
    );
    return foldChatEvents(descriptorValue, eventValues.filter(isChatEvent));
  }));
  return conversations
    .filter((conversation): conversation is ChatConversation => conversation !== null)
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt) || b.id.localeCompare(a.id));
}

export async function loadDesktopScopedConversation(
  backend: VaultBackend,
  legacyKey: string,
): Promise<ChatConversation | null> {
  const id = `desktop-${stableId(legacyKey)}`;
  return (await loadChatConversations(backend)).find((conversation) => conversation.id === id) ?? null;
}

/** Mirrors the legacy desktop panel into the shared append-only chat store. */
export async function syncDesktopConversation(
  backend: VaultBackend,
  legacyKey: string,
  scope: ChatScope,
  messages: StoredAiMessage[],
  device: ChatDevice = { id: "desktop", name: "Desktop" },
): Promise<void> {
  if (!messages.length) return;
  const id = `desktop-${stableId(legacyKey)}`;
  const descriptorPath = `${CHAT_ROOT}/${id}/conversation.json`;
  if (!(await backend.exists(descriptorPath))) {
    const createdAt = new Date().toISOString();
    const descriptor: ChatDescriptor = { version: 1, id, createdAt, scope, legacyKey };
    await backend.writeNew(descriptorPath, JSON.stringify(descriptor, null, 2));
    const ownership: ChatEvent = {
      version: 1,
      id: `${id}-owner-1`,
      conversationId: id,
      at: createdAt,
      deviceId: device.id,
      ownerGeneration: 1,
      kind: "ownership",
      owner: device,
    };
    await backend.writeNew(eventPath(id, ownership.id), JSON.stringify(ownership, null, 2));
  }
  const existing = await loadDesktopScopedConversation(backend, legacyKey);
  if (existing && existing.owner.id !== device.id) return;
  const start = existing?.messages.length ?? 0;
  for (let index = start; index < messages.length; index += 1) {
    const source = messages[index];
    const at = new Date(Date.now() + index).toISOString();
    const message: PersistedChatMessage = {
      id: `${id}-message-${index}`,
      turnId: `${id}-turn-${Math.floor(index / 2)}`,
      role: source.role,
      text: source.content,
      createdAt: at,
      deviceId: device.id,
      ownerGeneration: existing?.ownerGeneration ?? 1,
      attachments: source.attachments?.map((attachment) => ({ ...attachment })),
    };
    const event: ChatEvent = {
      version: 1,
      id: `${id}-event-${index}`,
      conversationId: id,
      at,
      deviceId: device.id,
      ownerGeneration: existing?.ownerGeneration ?? 1,
      kind: "message",
      message,
    };
    if (!(await backend.exists(eventPath(id, event.id)))) {
      await backend.writeNew(eventPath(id, event.id), JSON.stringify(event, null, 2));
    }
  }
}

async function writeEvent(backend: VaultBackend, event: ChatEvent): Promise<void> {
  await backend.writeNew(eventPath(event.conversationId, event.id), JSON.stringify(event, null, 2));
}

function baseEvent(conversation: ChatConversation, device: ChatDevice): ChatEventBase {
  return {
    version: 1,
    id: uuid(),
    conversationId: conversation.id,
    at: new Date().toISOString(),
    deviceId: device.id,
    ownerGeneration: conversation.ownerGeneration,
  };
}

export async function createChatWithUserMessage(
  backend: VaultBackend,
  device: ChatDevice,
  text: string,
  image?: NewChatImageAttachment | NewChatImageAttachment[],
  scope: ChatScope = { kind: "vault" },
): Promise<{ conversationId: string; turnId: string }> {
  const conversationId = uuid();
  const turnId = uuid();
  const createdAt = new Date().toISOString();
  const descriptor: ChatDescriptor = { version: 1, id: conversationId, createdAt, scope };
  const ownership: ChatEvent = {
    version: 1,
    id: uuid(),
    conversationId,
    at: createdAt,
    deviceId: device.id,
    ownerGeneration: 1,
    kind: "ownership",
    owner: device,
  };
  const attachments = await storeImageAttachment(backend, conversationId, image);
  const message: PersistedChatMessage = {
    id: uuid(), turnId, role: "user", text, createdAt,
    deviceId: device.id, ownerGeneration: 1, attachments,
  };
  const messageEvent: ChatEvent = {
    version: 1,
    id: uuid(),
    conversationId,
    at: createdAt,
    deviceId: device.id,
    ownerGeneration: 1,
    kind: "message",
    message,
  };
  await backend.writeNew(`${CHAT_ROOT}/${conversationId}/conversation.json`, JSON.stringify(descriptor, null, 2));
  await writeEvent(backend, ownership);
  await writeEvent(backend, messageEvent);
  return { conversationId, turnId };
}

export async function appendUserMessage(
  backend: VaultBackend,
  conversation: ChatConversation,
  device: ChatDevice,
  text: string,
  image?: NewChatImageAttachment | NewChatImageAttachment[],
): Promise<string> {
  const event = baseEvent(conversation, device);
  const turnId = uuid();
  const attachments = await storeImageAttachment(backend, conversation.id, image);
  const message: PersistedChatMessage = {
    id: uuid(), turnId, role: "user", text, createdAt: event.at,
    deviceId: device.id, ownerGeneration: conversation.ownerGeneration, attachments,
  };
  await writeEvent(backend, { ...event, kind: "message", message });
  return turnId;
}

export async function appendAssistantMessage(
  backend: VaultBackend,
  conversation: ChatConversation,
  device: ChatDevice,
  assistant: NewAssistantMessage,
): Promise<void> {
  const event = baseEvent(conversation, device);
  const message: PersistedChatMessage = {
    id: uuid(), turnId: assistant.turnId, role: "assistant", text: assistant.text,
    createdAt: event.at, deviceId: device.id, ownerGeneration: conversation.ownerGeneration,
    sources: assistant.sources, contextKind: assistant.contextKind,
  };
  await writeEvent(backend, { ...event, kind: "message", message });
}

export async function transferChatOwnership(
  backend: VaultBackend,
  conversation: ChatConversation,
  device: ChatDevice,
): Promise<void> {
  const event: ChatEvent = {
    ...baseEvent(conversation, device),
    ownerGeneration: conversation.ownerGeneration + 1,
    kind: "ownership",
    owner: device,
  };
  await writeEvent(backend, event);
}

export async function renameChat(backend: VaultBackend, conversation: ChatConversation, device: ChatDevice, title: string): Promise<void> {
  await writeEvent(backend, { ...baseEvent(conversation, device), kind: "rename", title: title.trim() });
}

export async function setChatLifecycle(
  backend: VaultBackend,
  conversation: ChatConversation,
  device: ChatDevice,
  kind: "archive" | "restore" | "delete",
): Promise<void> {
  await writeEvent(backend, { ...baseEvent(conversation, device), kind });
}

export async function saveChatSummary(
  backend: VaultBackend,
  conversation: ChatConversation,
  device: ChatDevice,
  text: string,
  coveredMessageIds: string[],
): Promise<void> {
  await writeEvent(backend, {
    ...baseEvent(conversation, device), kind: "summary", text, coveredMessageIds,
  });
}

export async function resetChatSummary(
  backend: VaultBackend,
  conversation: ChatConversation,
  device: ChatDevice,
): Promise<void> {
  await saveChatSummary(backend, conversation, device, "", []);
}

export async function purgeExpiredChats(
  backend: VaultBackend,
  conversations: ChatConversation[],
  device: ChatDevice,
  now = Date.now(),
): Promise<boolean> {
  let purged = false;
  for (const conversation of conversations) {
    if (!conversation.deletedAt || conversation.owner.id !== device.id) continue;
    if (now - new Date(conversation.deletedAt).getTime() < CHAT_RETENTION_MS) continue;
    const tombstonePath = `${CHAT_TOMBSTONE_ROOT}/${conversation.id}.json`;
    if (!(await backend.exists(tombstonePath))) {
      await backend.writeNew(tombstonePath, JSON.stringify({
        version: 1,
        conversationId: conversation.id,
        purgedAt: new Date(now).toISOString(),
      }, null, 2));
    }
    await backend.removeDir(`${CHAT_ROOT}/${conversation.id}`);
    purged = true;
  }
  return purged;
}

export function titleFromQuestion(question: string): string {
  const compact = question.replace(/\s+/g, " ").trim();
  if (compact.length <= 64) return compact || "New chat";
  return `${compact.slice(0, 61).trimEnd()}…`;
}

export function chatContentRevision(content: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < content.length; index += 1) {
    hash ^= content.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

export function unansweredTurnIds(messages: PersistedChatMessage[]): string[] {
  const userTurns = new Set(messages.filter((message) => message.role === "user").map((message) => message.turnId));
  for (const message of messages) {
    if (message.role === "assistant") userTurns.delete(message.turnId);
  }
  return [...userTurns];
}
