export interface StoredAiToolCall {
  name: string;
  arguments: string;
  result: string;
  status: "running" | "complete" | "error";
}

export interface StoredAiImageAttachment {
  id: string;
  path: string;
  mimeType: "image/jpeg";
  width: number;
  height: number;
  byteLength: number;
  name?: string;
}

export interface StoredAiMessage {
  role: "user" | "assistant";
  content: string;
  attachments?: StoredAiImageAttachment[];
  reasoning?: string | null;
  editApplied?: boolean;
  toolCalls?: StoredAiToolCall[];
}

interface StoredAiConversation {
  messages: StoredAiMessage[];
  updatedAt: number;
}

type StoredAiConversations = Record<string, StoredAiConversation>;

const STORAGE_KEY = "zerus.ai.conversations.v1";
const MAX_CONVERSATIONS = 50;
const MAX_MESSAGES = 64;
const MAX_STORAGE_LENGTH = 4_000_000;

function readAll(): StoredAiConversations {
  try {
    const parsed = JSON.parse(
      localStorage.getItem(STORAGE_KEY) ?? "null",
    ) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};

    const conversations: StoredAiConversations = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (!value || typeof value !== "object" || Array.isArray(value)) continue;
      const candidate = value as Partial<StoredAiConversation>;
      if (!Array.isArray(candidate.messages)) continue;
      const messages = candidate.messages.filter(isStoredMessage).slice(-MAX_MESSAGES);
      conversations[key] = {
        messages,
        updatedAt:
          typeof candidate.updatedAt === "number" && Number.isFinite(candidate.updatedAt)
            ? candidate.updatedAt
            : 0,
      };
    }
    return conversations;
  } catch {
    return {};
  }
}

function isStoredMessage(value: unknown): value is StoredAiMessage {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const candidate = value as Partial<StoredAiMessage>;
  return (
    (candidate.role === "user" || candidate.role === "assistant") &&
    typeof candidate.content === "string" &&
    (candidate.attachments === undefined ||
      (Array.isArray(candidate.attachments) &&
        candidate.attachments.length <= 4 &&
        candidate.attachments.every(isStoredImageAttachment))) &&
    (candidate.reasoning === undefined ||
      candidate.reasoning === null ||
      typeof candidate.reasoning === "string") &&
    (candidate.editApplied === undefined ||
      typeof candidate.editApplied === "boolean") &&
    (candidate.toolCalls === undefined ||
      (Array.isArray(candidate.toolCalls) &&
        candidate.toolCalls.length <= 13 &&
        candidate.toolCalls.every(isStoredToolCall)))
  );
}

function isStoredImageAttachment(value: unknown): value is StoredAiImageAttachment {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const candidate = value as Partial<StoredAiImageAttachment>;
  return (
    typeof candidate.id === "string" &&
    candidate.id.length > 0 &&
    candidate.id.length <= 100 &&
    typeof candidate.path === "string" &&
    candidate.path.startsWith("assets/") &&
    candidate.path.length <= 1_000 &&
    candidate.mimeType === "image/jpeg" &&
    typeof candidate.width === "number" &&
    Number.isFinite(candidate.width) &&
    candidate.width > 0 &&
    candidate.width <= 4_096 &&
    typeof candidate.height === "number" &&
    Number.isFinite(candidate.height) &&
    candidate.height > 0 &&
    candidate.height <= 4_096 &&
    typeof candidate.byteLength === "number" &&
    Number.isFinite(candidate.byteLength) &&
    candidate.byteLength > 0 &&
    candidate.byteLength <= 3 * 1_024 * 1_024 &&
    (candidate.name === undefined ||
      (typeof candidate.name === "string" && candidate.name.length <= 255))
  );
}

function isStoredToolCall(value: unknown): value is StoredAiToolCall {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const candidate = value as Partial<StoredAiToolCall>;
  return (
    typeof candidate.name === "string" &&
    candidate.name.length > 0 &&
    candidate.name.length <= 100 &&
    typeof candidate.arguments === "string" &&
    typeof candidate.result === "string" &&
    (candidate.status === "running" ||
      candidate.status === "complete" ||
      candidate.status === "error")
  );
}

function persist(conversations: StoredAiConversations) {
  const oldestFirst = () =>
    Object.entries(conversations).sort(
      ([, left], [, right]) => left.updatedAt - right.updatedAt,
    );

  while (Object.keys(conversations).length > MAX_CONVERSATIONS) {
    const oldestKey = oldestFirst()[0]?.[0];
    if (!oldestKey) break;
    delete conversations[oldestKey];
  }

  let encoded = JSON.stringify(conversations);
  while (encoded.length > MAX_STORAGE_LENGTH && Object.keys(conversations).length > 1) {
    const oldestKey = oldestFirst()[0]?.[0];
    if (!oldestKey) break;
    delete conversations[oldestKey];
    encoded = JSON.stringify(conversations);
  }

  try {
    localStorage.setItem(STORAGE_KEY, encoded);
  } catch {
    // Conversation persistence is best-effort when browser storage is full.
  }
}

export function aiConversationKey(
  vaultLocation: string | null,
  noteId: string | null,
  fallbackContextKey: string | null,
): string | null {
  if (noteId) return `${vaultLocation ?? "browser"}\u0000note:${noteId}`;
  return fallbackContextKey
    ? `${vaultLocation ?? "browser"}\u0000context:${fallbackContextKey}`
    : null;
}

export function readAiConversation(key: string | null): StoredAiMessage[] {
  if (!key) return [];
  return readAll()[key]?.messages ?? [];
}

export function saveAiConversation(key: string | null, messages: StoredAiMessage[]) {
  if (!key) return;
  const conversations = readAll();
  conversations[key] = {
    messages: messages.filter(isStoredMessage).slice(-MAX_MESSAGES),
    updatedAt: Date.now(),
  };
  persist(conversations);
}

export function clearAiConversation(key: string | null) {
  if (!key) return;
  const conversations = readAll();
  delete conversations[key];
  persist(conversations);
}
