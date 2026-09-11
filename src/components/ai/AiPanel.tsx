import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import type { ModelMessage } from "@ai-sdk/provider-utils";
import { isTauri, invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { nativeFileDropPoint } from "@/lib/native-file-drop";
import { readFile, stat } from "@tauri-apps/plugin-fs";
import { selectDocumentContext, prepareChatDocument, validateDocumentBatch, MAX_CHAT_FILE_BYTES, MAX_CHAT_TOTAL_BYTES, type ChatDocument } from "@/lib/chat-documents";
import {
  Check,
  Code2,
  Loader2,
  Paperclip,
  Plus,
  Send,
  Settings,
  Sparkles,
  X,
} from "@/lib/icons";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { AiProviderDialog } from "@/components/ai/AiProviderDialog";
import { AiMarkdown } from "@/components/ai/AiMarkdown";
import {
  readAiProviderConfig,
  saveAiProviderConfig,
  CODEX_PROVIDER_URL,
  type AiProvider,
  type AiProviderConfig,
  type CloudAiModel,
} from "@/lib/ai-provider-config";
import {
  legacyAiConversations,
  type StoredAiMessage,
  type StoredAiImageAttachment,
  type StoredAiToolCall,
} from "@/lib/ai-conversations";
import { noteTitle, type Note } from "@/lib/note-utils";
import { ChatAnswerActions } from "./ChatAnswerActions";
import { ChatContextPicker } from "./ChatContextPicker";
import { ChatHistory } from "./ChatHistory";
import {
  budgetChatHistory,
  visibleChatStream,
  chatActivityLabel,
} from "@/lib/ai-chat-experience";
import type { AiNoteChange } from "@/lib/ai-conversations";
import {
  buildAiContext,
  notesInAiScope,
  type AiContext,
  type AiKnowledgeScope,
} from "@/lib/ai-context";
import {
  applyAiNoteAction,
  directAiNoteAction,
  parseAiResponse,
} from "@/lib/ai-actions";
import { runAiTool, type AiToolCall } from "@/lib/ai-tools";
import { previewChatAnswer } from "@/lib/ai-browser-preview";
import { runZerusAgent } from "@/lib/ai-sdk-agent";
import { authorizesAiNoteMutation } from "@/lib/ai-agent-policy";
import { noteBody } from "@/lib/frontmatter";
import {
  getImageUrl,
  getNotes,
  getVaultBackend,
  readVaultImage,
  savePastedImage,
  updateNoteBody,
} from "@/store/notes-store";
import {
  readSharedAiSettings,
  shouldApplySharedAiSettings,
  writeSharedAiSettings,
} from "@/lib/shared-ai-settings";
import {
  imageFilesFromClipboard,
  prepareChatImage,
  type PreparedChatImage,
} from "@/lib/mobile-chat-image";
import { cn } from "@/lib/utils";
import { showError, showSuccess } from "@/utils/toast";
import {
  chatContentRevision,
  loadChatConversations,
  loadChatsWithRetention,
  desktopChatMessages,
  saveDesktopChat,
  syncDesktopConversation,
  transferChatOwnership,
  type ChatConversation,
  type ChatDevice,
  type ChatScope,
} from "@/lib/mobile-chat-history";
import { chatDeviceLabel, getChatDevice } from "@/lib/mobile-device";

const BROWSER_PREVIEW = !isTauri();
const DEFAULT_WIDTH = 440;
const MIN_WIDTH = 340;
const WIDTH_STORAGE_KEY = "zerus.ai.width";

type ChatMessage = StoredAiMessage;

interface AiChatReasoningEvent {
  streamId: string;
  reasoning: string;
}

interface CodexAiStatus {
  available: boolean;
  connected: boolean;
  accountLabel: string | null;
  planType: string | null;
  models: CloudAiModel[];
}

interface AiPanelProps {
  open: boolean;
  note: Note | null;
  notes: Note[];
  scope: AiKnowledgeScope;
  vaultLocation: string | null;
  onOpenChange: (open: boolean) => void;
  onOpenNote: (noteId: string) => void;
}

const MAX_CHAT_IMAGES = 4;
const MAX_TOOL_DETAIL_LENGTH = 6_000;

function formatToolDetail(value: unknown): string {
  let detail: string;
  try {
    detail = JSON.stringify(value, null, 2) ?? String(value);
  } catch {
    detail = String(value);
  }
  return detail.length > MAX_TOOL_DETAIL_LENGTH
    ? `${detail.slice(0, MAX_TOOL_DETAIL_LENGTH)}\n…truncated`
    : detail;
}

function toolCallActivity(
  call: AiToolCall,
  status: StoredAiToolCall["status"],
  result = "",
): StoredAiToolCall {
  return {
    name: call.name,
    arguments: formatToolDetail(call.arguments),
    result,
    status,
  };
}

function ToolCallList({ toolCalls }: { toolCalls: StoredAiToolCall[] }) {
  return (
    <div className="mt-2 space-y-1.5 border-t border-current/15 pt-2 text-xs">
      {toolCalls.map((toolCall, index) => (
        <details
          key={`${toolCall.name}-${index}`}
          className="rounded-md border border-current/10 bg-background/25 px-2 py-1.5"
        >
          <summary className="flex cursor-pointer list-none items-center gap-1.5 font-medium [&::-webkit-details-marker]:hidden">
            {toolCall.status === "running" ? (
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
            ) : toolCall.status === "complete" ? (
              <Check className="h-3.5 w-3.5 text-emerald-500" />
            ) : (
              <X className="h-3.5 w-3.5 text-destructive" />
            )}
            <Code2 className="h-3.5 w-3.5" />
            <span>{chatActivityLabel(toolCall.name)}</span>
            <span className="ml-auto font-normal opacity-70">
              {toolCall.status === "running"
                ? "Running"
                : toolCall.status === "complete"
                  ? "Completed"
                  : "Failed"}
            </span>
          </summary>
          <div className="mt-2 space-y-2">
            <div>
              <div className="mb-1 opacity-60">Arguments</div>
              <pre className="max-h-48 overflow-auto whitespace-pre-wrap break-words rounded bg-background/40 p-2 font-mono text-[11px]">
                {toolCall.arguments}
              </pre>
            </div>
            {toolCall.result && (
              <div>
                <div className="mb-1 opacity-60">Result</div>
                <pre className="max-h-48 overflow-auto whitespace-pre-wrap break-words rounded bg-background/40 p-2 font-mono text-[11px]">
                  {toolCall.result}
                </pre>
              </div>
            )}
          </div>
        </details>
      ))}
    </div>
  );
}

function ChatImage({ attachment }: { attachment: StoredAiImageAttachment }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    let disposed = false;
    void getImageUrl(attachment.path).then((value) => {
      if (!disposed) setUrl(value);
    });
    return () => {
      disposed = true;
    };
  }, [attachment.path]);

  if (!url) {
    return (
      <div className="aspect-video animate-pulse rounded-lg bg-black/15" />
    );
  }
  return (
    <img
      src={url}
      alt={attachment.name || "AI chat attachment"}
      className="max-h-56 w-full rounded-lg object-contain"
    />
  );
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(
      ...bytes.subarray(offset, offset + chunkSize),
    );
  }
  return btoa(binary);
}

function attachmentMarkdown(attachment: StoredAiImageAttachment): string {
  const fallback = attachment.name?.replace(/\.[^.]+$/, "") || "Attached image";
  const alt =
    fallback.split("[").join("").split("]").join("").trim() || "Attached image";
  return `![${alt}](${attachment.path})`;
}

function asksToAppendAttachedImage(value: string): boolean {
  return /\b(?:append|add|put|insert|attach)\b[\s\S]*\b(?:image|photo|picture|screenshot|it|this)\b/i.test(
    value,
  );
}

function storedWidth(): number {
  const value = Number(localStorage.getItem(WIDTH_STORAGE_KEY));
  return Number.isFinite(value) && value >= MIN_WIDTH ? value : DEFAULT_WIDTH;
}

export function AiPanel({
  open,
  note,
  notes,
  scope,
  vaultLocation,
  onOpenChange,
  onOpenNote,
}: AiPanelProps) {
  const panelRef = useRef<HTMLDivElement>(null);
  const [fileDragOver, setFileDragOver] = useState(false);
  const [pendingDocuments, setPendingDocuments] = useState<ChatDocument[]>([]);
  const [documentContextStatus, setDocumentContextStatus] = useState("");
  const selectingFiles = useRef(false);
  const imageInputRef = useRef<HTMLInputElement>(null);
  const pendingAttachmentsRef = useRef<PreparedChatImage[]>([]);
  const requestIdRef = useRef(0);
  const sendInFlightRef = useRef(false);
  const activeStreamIdRef = useRef<string | null>(null);
  const contextRef = useRef<AiContext | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);
  const followOutput = useRef(true);
  const [selectedNoteIds, setSelectedNoteIds] = useState<string[] | null>(null);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [conversations, setConversations] = useState<ChatConversation[]>([]);
  const [chatId, setChatId] = useState<string>(() => crypto.randomUUID());
  const [historyReady, setHistoryReady] = useState(false);
  const [inlineError, setInlineError] = useState("");
  const streamTextRef = useRef("");
  const [streamingText, updateStreamingText] = useState("");
  const setStreamingText = (text: string) => {
    streamTextRef.current = text;
    updateStreamingText(text);
  };
  const [historyOmitted, setHistoryOmitted] = useState(0);
  const [showJump, setShowJump] = useState(false);
  const saveQueue = useRef<Promise<unknown>>(Promise.resolve());
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [width, setWidth] = useState(storedWidth);
  const [providerConfig, setProviderConfig] = useState(readAiProviderConfig);
  const [providerDialogOpen, setProviderDialogOpen] = useState(false);
  const [cloudModels, setCloudModels] = useState<CloudAiModel[]>([]);
  const [cloudModelsSource, setCloudModelsSource] = useState("");
  const [loadingModels, setLoadingModels] = useState(false);
  const [cloudReady, setCloudReady] = useState(BROWSER_PREVIEW);
  const [streamingReasoning, setStreamingReasoning] = useState("");
  const [streamingToolCalls, setStreamingToolCalls] = useState<
    StoredAiToolCall[]
  >([]);
  const [pendingAttachments, setPendingAttachments] = useState<
    PreparedChatImage[]
  >([]);
  const [preparingImages, setPreparingImages] = useState(false);
  const [codexStatus, setCodexStatus] = useState<CodexAiStatus | null>(null);
  const [chatDevice, setChatDevice] = useState<ChatDevice | null>(null);
  const [sharedConversation, setSharedConversation] =
    useState<ChatConversation | null>(null);

  const effectiveScope = useMemo<AiKnowledgeScope>(
    () =>
      selectedNoteIds !== null
        ? { kind: "selection", noteIds: selectedNoteIds }
        : sharedConversation?.scope.kind === "note"
          ? { kind: "selection", noteIds: [sharedConversation.scope.noteId] }
          : (sharedConversation?.scope ?? scope),
    [selectedNoteIds, sharedConversation?.scope, scope],
  );
  const deferredDraft = useDeferredValue(draft);
  const context = useMemo(
    () =>
      buildAiContext(note, notes, effectiveScope, vaultLocation, deferredDraft),
    [note, notes, effectiveScope, vaultLocation, deferredDraft],
  );
  const scopedNotes = useMemo(
    () => notesInAiScope(notes, effectiveScope),
    [notes, effectiveScope],
  );
  const scopedNoteIds = useMemo(
    () => new Set(scopedNotes.map((candidate) => candidate.id)),
    [scopedNotes],
  );
  const outsideNotes = useMemo(
    () => notes.filter((candidate) => !scopedNoteIds.has(candidate.id)),
    [notes, scopedNoteIds],
  );
  contextRef.current = context;
  const sharedScope = effectiveScope as ChatScope;
  const ownsSharedConversation =
    !sharedConversation ||
    Boolean(
      chatDevice &&
        sharedConversation.owner.id === chatDevice.id &&
        !sharedConversation.archivedAt &&
        !sharedConversation.deletedAt,
    );

  useEffect(() => {
    let active = true;
    void getChatDevice().then((device) => {
      if (active) setChatDevice(device);
    });
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (!open) return;
    const backend = getVaultBackend();
    if (!backend) return;
    let active = true;
    void readSharedAiSettings(backend).then((shared) => {
      const local = readAiProviderConfig();
      if (!active || !shared || !shouldApplySharedAiSettings(local, shared.active)) return;
      saveAiProviderConfig(shared.active);
      setProviderConfig(shared.active);
    });
    return () => {
      active = false;
    };
  }, [open, vaultLocation]);

  useEffect(() => {
    if (!open || BROWSER_PREVIEW) return;
    let disposed = false;
    if (providerConfig.provider === "codex") {
      void invoke<CodexAiStatus>("codex_ai_status")
        .then((status) => {
          if (disposed) return;
          setCodexStatus(status);
          setCloudReady(status.connected);
          setCloudModels(status.models);
          setCloudModelsSource(`codex:${CODEX_PROVIDER_URL}`);
        })
        .catch(() => {
          if (!disposed) setCloudReady(false);
        });
      return () => {
        disposed = true;
      };
    }
    void invoke<CodexAiStatus>("codex_ai_status")
      .then((status) => {
        if (!disposed) setCodexStatus(status);
      })
      .catch(() => {
        if (!disposed) setCodexStatus(null);
      });
    void invoke("cloud_ai_configure", {
      provider: providerConfig.provider,
      baseUrl: providerConfig.baseUrl,
      apiKey: null,
    })
      .then(() => {
        if (!disposed) setCloudReady(true);
      })
      .catch(() => {
        if (!disposed) setCloudReady(false);
      });
    return () => {
      disposed = true;
    };
  }, [open, providerConfig.baseUrl, providerConfig.provider]);

  useEffect(() => {
    let disposed = false;
    let unlisten: (() => void) | undefined;
    void listen<AiChatReasoningEvent>("ai-chat-reasoning", (event) => {
      if (event.payload.streamId === activeStreamIdRef.current) {
        setStreamingReasoning(event.payload.reasoning);
      }
    })
      .then((stopListening) => {
        if (disposed) stopListening();
        else unlisten = stopListening;
      })
      .catch(() => {});
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, []);

  useEffect(() => {
    let disposed = false;
    let unlisten: (() => void) | undefined;
    void listen<{ streamId: string; text: string }>("ai-chat-text", (event) => {
      if (event.payload.streamId === activeStreamIdRef.current)
        setStreamingText(visibleChatStream(event.payload.text));
    })
      .then((stop) => {
        if (disposed) stop();
        else unlisten = stop;
      })
      .catch(() => {});
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, []);

  useEffect(() => {
    if (followOutput.current)
      bottomRef.current?.scrollIntoView({ block: "end" });
    else setShowJump(true);
  }, [messages, streamingText, streamingToolCalls]);
  useEffect(
    () => () => {
      abortRef.current?.abort();
      requestIdRef.current += 1;
    },
    [],
  );

  useEffect(() => {
    pendingAttachmentsRef.current = pendingAttachments;
  }, [pendingAttachments]);

  useEffect(
    () => () => {
      for (const attachment of pendingAttachmentsRef.current) {
        URL.revokeObjectURL(attachment.previewUrl);
      }
    },
    [],
  );

  const vaultBackend = getVaultBackend();
  const historyStorageKey = `zerus.ai.active-chat.${vaultLocation ?? "browser"}`;
  const refreshHistory = async () => {
    const backend = getVaultBackend();
    if (!backend || !chatDevice) return;
    const loaded = await loadChatsWithRetention(backend, chatDevice);
    setConversations(loaded);
    setSharedConversation(loaded.find((chat) => chat.id === chatId) ?? null);
  };
  useEffect(() => {
    if (!chatDevice) return;
    let active = true;
    const backend = getVaultBackend();
    if (!backend) return;
    setHistoryReady(false);
    abortRef.current?.abort();
    requestIdRef.current += 1;
    setSending(false);
    sendInFlightRef.current = false;
    void (async () => {
      // One-way migration: keep old desktop sessions available alongside mobile chats.
      for (const legacy of legacyAiConversations(vaultLocation)) {
        const legacyNote = notes.find(
          (candidate) => candidate.id === legacy.noteId,
        );
        const legacyScope: ChatScope = legacy.noteId
          ? {
              kind: "note",
              noteId: legacy.noteId,
              title: legacyNote ? noteTitle(legacyNote) : "Note",
            }
          : { kind: "selection", noteIds: [] };
        if (legacy.messages.length)
          await syncDesktopConversation(
            backend,
            legacy.key,
            legacyScope,
            legacy.messages,
            chatDevice,
          );
      }
      const loaded = await loadChatsWithRetention(backend, chatDevice);
      if (!active) return;
      setConversations(loaded);
      const savedId = localStorage.getItem(historyStorageKey);
      const selected = loaded.find(
        (chat) => chat.id === savedId && !chat.deletedAt && !chat.archivedAt,
      );
      setSharedConversation(selected ?? null);
      setChatId(selected?.id ?? crypto.randomUUID());
      setMessages(selected ? desktopChatMessages(selected) : []);
      setHistoryReady(true);
    })().catch((error) => {
      if (active) {
        setInlineError(`Could not load chat history: ${String(error)}`);
        setHistoryReady(true);
      }
    });
    return () => {
      active = false;
    };
    // History belongs to the vault, not the selected note.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chatDevice, vaultLocation]);

  const persistChat = async (
    next: ChatMessage[],
    id = chatId,
    chatScope = sharedScope,
  ) => {
    const backend = vaultBackend;
    const saveRequestId = requestIdRef.current;
    if (!backend || !chatDevice)
      throw new Error("Chat history is not ready yet.");
    const pending = saveQueue.current
      .catch(() => {})
      .then(() => saveDesktopChat(backend, id, chatScope, next, chatDevice));
    saveQueue.current = pending;
    const saved = await pending;
    if (saved && requestIdRef.current === saveRequestId) {
      setSharedConversation(saved);
      setConversations((current) => [
        saved,
        ...current.filter((chat) => chat.id !== saved.id),
      ]);
    }
    if (requestIdRef.current === saveRequestId)
      localStorage.setItem(historyStorageKey, id);
  };
  const selectConversation = (chat: ChatConversation) => {
    if (sending) return;
    requestIdRef.current += 1;
    setPendingDocuments([]);
    setDocumentContextStatus("");
    setChatId(chat.id);
    setSharedConversation(chat);
    setMessages(desktopChatMessages(chat));
    setSelectedNoteIds(null);
    setDraft("");
    setInlineError("");
    setHistoryOpen(false);
    localStorage.setItem(historyStorageKey, chat.id);
    if (chat.scope.kind === "note") onOpenNote(chat.scope.noteId);
    followOutput.current = true;
  };
  const takeSharedConversation = async () => {
    const backend = getVaultBackend();
    if (!backend || !chatDevice || !sharedConversation) return;
    try {
      await transferChatOwnership(backend, sharedConversation, chatDevice);
      await refreshHistory();
    } catch (error) {
      showError(String(error));
    }
  };

  useEffect(() => {
    if (!open || sending || !chatDevice) return;
    let active = true;
    const backend = getVaultBackend();
    const refresh = async () => {
      if (!backend) return;
      try {
        const loaded = await loadChatConversations(backend);
        if (!active) return;
        setConversations(loaded);
        const selected = loaded.find((chat) => chat.id === chatId);
        if (selected) {
          setSharedConversation(selected);
          if (selected.owner.id !== chatDevice.id) setMessages(desktopChatMessages(selected));
        }
      } catch { /* Leave the visible transcript intact if a sync read fails. */ }
    };
    window.addEventListener("focus", refresh);
    const timer = window.setInterval(() => void refresh(), 5000);
    return () => { active = false; window.clearInterval(timer); window.removeEventListener("focus", refresh); };
  }, [open, sending, chatId, chatDevice]);

  const selectImages = async (files: readonly File[]) => {
    if (!files.length || selectingFiles.current || sending || !ownsSharedConversation) return;
    selectingFiles.current = true;
    setPreparingImages(true);
    const selectionId = requestIdRef.current;
    try {
      const documents = [...pendingDocuments];
      validateDocumentBatch(documents, files);
      for (const file of files.filter((file) => !file.type.startsWith("image/") && !/\.(png|jpe?g|gif|webp|heic|avif|bmp)$/i.test(file.name))) {
        const document = await prepareChatDocument(file);
        documents.push(document);
        validateDocumentBatch(documents, []);
      }
      if (selectionId !== requestIdRef.current) return;
      setPendingDocuments(documents);
      await selectImageFiles(files.filter((file) => file.type.startsWith("image/") || /\.(png|jpe?g|gif|webp|heic|avif|bmp)$/i.test(file.name)));
    } catch (error) { showError(String(error)); }
    finally { selectingFiles.current = false; setPreparingImages(false); }
  };

  const selectFilesRef = useRef(selectImages);
  selectFilesRef.current = selectImages;
  useEffect(() => {
    if (!isTauri() || !open) return;
    let disposed = false;
    let unlisten: (() => void) | undefined;
    void getCurrentWindow().onDragDropEvent(async ({ payload }) => {
      if (payload.type === "leave") { setFileDragOver(false); return; }
      const scale = await getCurrentWindow().scaleFactor();
      if (disposed) return;
      const { x, y } = nativeFileDropPoint(payload.position, scale);
      const target = document.elementFromPoint(x, y);
      const overChat = Boolean(target && panelRef.current?.contains(target));
      setFileDragOver(payload.type !== "drop" && overChat);
      if (payload.type !== "drop" || !overChat) return;
      try {
        const files: File[] = [];
        let totalBytes = 0;
        for (const path of payload.paths) {
          const size = (await stat(path)).size;
          if (size > MAX_CHAT_FILE_BYTES) throw new Error("Files must be under 50 MB.");
          totalBytes += size;
          if (totalBytes > MAX_CHAT_TOTAL_BYTES) throw new Error("Uploads exceed the 100 MB processing budget.");
          const bytes = await readFile(path);
          const name = path.split(/[\\/]/).pop() || "file";
          const extension = name.split(".").pop()?.toLowerCase() ?? "";
          const imageType = /^(png|jpe?g|gif|webp|heic|avif|bmp)$/.test(extension) ? `image/${extension === "jpg" ? "jpeg" : extension}` : "";
          files.push(new File([bytes], name, { type: imageType }));
        }
        if (!disposed) await selectFilesRef.current(files);
      } catch (error) { showError(String(error)); }
    }).then((stop) => { if (disposed) stop(); else unlisten = stop; }).catch((error) => { if (!disposed) showError(`File drop setup failed: ${String(error)}`); });
    return () => { disposed = true; unlisten?.(); };
  }, [open]);

  const selectImageFiles = async (files: readonly File[]) => {
    if (!files.length) return;
    const available = MAX_CHAT_IMAGES - pendingAttachments.length;
    if (available <= 0) {
      showError(`You can attach up to ${MAX_CHAT_IMAGES} images per message.`);
      return;
    }
    const selected = files.slice(0, available);
    if (files.length > available) {
      showError(
        `Only the first ${available} image${available === 1 ? "" : "s"} were added.`,
      );
    }
    const selectionRequestId = requestIdRef.current;
    setPreparingImages(true);
    const prepared: PreparedChatImage[] = [];
    try {
      for (const file of selected) prepared.push(await prepareChatImage(file));
      if (selectionRequestId !== requestIdRef.current) {
        for (const attachment of prepared)
          URL.revokeObjectURL(attachment.previewUrl);
        return;
      }
      setPendingAttachments((current) => [...current, ...prepared]);
    } catch (error) {
      for (const attachment of prepared)
        URL.revokeObjectURL(attachment.previewUrl);
      showError(String(error));
    } finally {
      setPreparingImages(false);
      if (imageInputRef.current) imageInputRef.current.value = "";
    }
  };

  const sendMessage = async (retryIndex?: number, regenerate = false) => {
    const retryMessage = retryIndex === undefined ? null : messages[retryIndex];
    const selectedAttachments = retryMessage ? [] : pendingAttachments;
    const content =
      retryMessage?.content ??
      (draft.trim() ||
        (selectedAttachments.length || pendingDocuments.length
          ? "Summarize these attached files."
          : ""));
    const currentContext = buildAiContext(
      note,
      getNotes(),
      effectiveScope,
      vaultLocation,
      content,
    );
    const providerReady = BROWSER_PREVIEW || Boolean(cloudReady && providerConfig.model);
    if (
      !currentContext ||
      !historyReady ||
      !providerReady ||
      !content ||
      !ownsSharedConversation ||
      sending ||
      sendInFlightRef.current ||
      preparingImages
    )
      return;
    sendInFlightRef.current = true;

    let storedAttachments: StoredAiImageAttachment[] =
      retryMessage?.attachments ?? [];
    const currentImageBytes = new Map<string, Uint8Array>();
    try {
      if (!retryMessage)
        storedAttachments = await Promise.all(
          selectedAttachments.map(async (attachment) => {
            const path = await savePastedImage(
              attachment.bytes,
              attachment.mimeType,
            );
            if (!path)
              throw new Error("The image could not be saved in this vault.");
            currentImageBytes.set(path, attachment.bytes);
            return {
              id: crypto.randomUUID(),
              path,
              mimeType: attachment.mimeType,
              width: attachment.width,
              height: attachment.height,
              byteLength: attachment.bytes.byteLength,
              name: attachment.name,
            };
          }),
        );
    } catch (error) {
      sendInFlightRef.current = false;
      showError(String(error));
      return;
    }

    const userMessage: ChatMessage =
      retryMessage && !regenerate
        ? retryMessage
        : {
            id: crypto.randomUUID(),
            turnId: crypto.randomUUID(),
            role: "user",
            content,
            documents: retryMessage?.documents ?? pendingDocuments,
            ...(storedAttachments.length
              ? { attachments: storedAttachments }
              : {}),
          };
    const history =
      retryMessage && !regenerate
        ? messages.slice(0, retryIndex! + 1)
        : [...messages, userMessage];
    const requestId = requestIdRef.current + 1;
    requestIdRef.current = requestId;
    setMessages(history);
    setDraft("");
    setPendingDocuments([]);
    setDocumentContextStatus("");
    setPendingAttachments((current) => {
      for (const attachment of current)
        URL.revokeObjectURL(attachment.previewUrl);
      return [];
    });
    setSending(true);
    setInlineError("");
    setStreamingText("");
    followOutput.current = true;
    const controller = new AbortController();
    abortRef.current = controller;
    const changes: AiNoteChange[] = [];
    const applyChange = (id: string, after: string) => {
      const latest = getNotes().find((candidate) => candidate.id === id);
      if (!latest) throw new Error("Note is no longer available.");
      changes.push({
        noteId: id,
        title: noteTitle(latest),
        before: noteBody(latest.content),
        after,
      });
      updateNoteBody(id, after);
    };
    const finishAnswer = async (answer: ChatMessage) => {
      const next = [
        ...history,
        {
          ...answer,
          id: crypto.randomUUID(),
          turnId: userMessage.turnId,
          sources: currentContext.sources,
          changes: [...changes],
        },
      ];
      if (requestIdRef.current === requestId) setMessages(next);
      await persistChat(next);
    };
    try {
      await persistChat(history);
    } catch (error) {
      setInlineError(String(error));
      setSending(false);
      sendInFlightRef.current = false;
      return;
    }
    if (controller.signal.aborted) {
      setSending(false);
      sendInFlightRef.current = false;
      return;
    }
    setStreamingReasoning("");
    setStreamingToolCalls([]);

    try {
      if (
        !regenerate &&
        storedAttachments.length > 0 &&
        asksToAppendAttachedImage(content) &&
        currentContext.noteId
      ) {
        const latestNote = getNotes().find(
          (candidate) => candidate.id === currentContext.noteId,
        );
        if (
          latestNote &&
          contextRef.current?.noteId === currentContext.noteId
        ) {
          const markdown = storedAttachments
            .map(attachmentMarkdown)
            .join("\n\n");
          applyChange(
            latestNote.id,
            applyAiNoteAction(noteBody(latestNote.content), {
              type: "append",
              text: markdown,
            }),
          );
          await finishAnswer({
            role: "assistant",
            content:
              storedAttachments.length === 1
                ? "Added the image to the end of the note."
                : "Added the images to the end of the note.",
            editApplied: true,
          });
          setSending(false);
          sendInFlightRef.current = false;
          showSuccess("Note updated");
          return;
        }
      }

      const directAction =
        !regenerate && storedAttachments.length === 0
          ? (userMessage.documents?.length ? null : directAiNoteAction(content))
          : null;
      if (directAction && currentContext.noteId) {
        const latestNote = getNotes().find(
          (candidate) => candidate.id === currentContext.noteId,
        );
        if (
          latestNote &&
          contextRef.current?.noteId === currentContext.noteId
        ) {
          applyChange(
            latestNote.id,
            applyAiNoteAction(noteBody(latestNote.content), directAction),
          );
          await finishAnswer({
            role: "assistant",
            content: "Added the text to the end of the note.",
            editApplied: true,
          });
          setSending(false);
          sendInFlightRef.current = false;
          showSuccess("Note updated");
          return;
        }
      }

      const budgeted = budgetChatHistory(history.map((message) => ({ ...message, documents: undefined })));
      const documents = history.flatMap((message) => message.documents ?? []);
      const selectedModel = cloudModels.find((model) => model.id === providerConfig.model) ?? { id: providerConfig.model };
      const contextModel = providerConfig.provider === "codex" ? { ...selectedModel, id: `codex:${selectedModel.id}` } : selectedModel;
      const existingText = currentContext.sessionContext + (sharedConversation?.summary?.text.slice(0, 8000) ?? "") + budgeted.messages.map((message) => message.content).join("\n");
      const imageCount = budgeted.messages.reduce((sum, message) => sum + (message.attachments?.length ?? 0), 0);
      const documentContext = documents.length ? await selectDocumentContext(documents, content, contextModel, existingText, imageCount) : null;
      setDocumentContextStatus(documentContext ? `${documentContext.excerpts ? "Using file excerpts" : "Full file context"}${documentContext.fallback ? " · model capacity unknown; conservative budget" : ""}` : "");
      setHistoryOmitted(budgeted.omitted);
      const historyMessages = await Promise.all(
        budgeted.messages.map(async (message): Promise<ModelMessage> => {
          const content = message.content;
          const attachments = message.attachments ?? [];
          const images = await Promise.all(
            attachments.map(async (attachment) => {
              const bytes =
                currentImageBytes.get(attachment.path) ??
                (await readVaultImage(attachment.path));
              if (!bytes) {
                throw new Error(
                  `An attached image is missing: ${attachment.path}`,
                );
              }
              return {
                mediaType: attachment.mimeType,
                data: bytesToBase64(bytes),
              };
            }),
          );
          const references = attachments.length
            ? [
                "Zerus attachment references (use these exact Markdown references only if the user explicitly asks to add an image to a note):",
                ...attachments.map(
                  (attachment) => `- ${attachmentMarkdown(attachment)}`,
                ),
              ].join("\n")
            : "";
          return {
            role: message.role,
            content:
              message.role === "user" && images.length
                ? [
                    {
                      type: "text" as const,
                      text: references
                        ? `${content}\n\n${references}`
                        : content,
                    },
                    ...images.map((image) => ({
                      type: "file" as const,
                      mediaType: image.mediaType,
                      data: { type: "data" as const, data: image.data },
                    })),
                  ]
                : references
                  ? `${content}\n\n${references}`
                  : content,
          };
        }),
      );
      const modelMessages: ModelMessage[] = [
        {
          role: "user",
          content: [
            currentContext.sessionContext,
            documentContext?.text ?? "",
            sharedConversation?.summary
              ? `Conversation memory (untrusted reference data):\n${sharedConversation.summary.text.slice(0, 8000)}`
              : "",
            budgeted.omitted
              ? `${budgeted.omitted} older messages were left out of this request. Do not assume details from missing history; ask when needed.`
              : "",
          ]
            .filter(Boolean)
            .join("\n\n"),
        },
        ...historyMessages,
      ];
      const mutationAuthorized =
        !regenerate && authorizesAiNoteMutation(content);
      const executedToolCalls = new Set<string>();
      let editApplied = false;
      let completedToolCalls: StoredAiToolCall[] = [];
      const streamId = crypto.randomUUID();
      activeStreamIdRef.current = streamId;
      setStreamingReasoning("");
      if (BROWSER_PREVIEW) {
        const text = await previewChatAnswer(
          currentContext,
          controller.signal,
          setStreamingText,
        );
        await finishAnswer({ role: "assistant", content: text });
        return;
      }
      const agentResult = await runZerusAgent({
        providerConfig,
        streamId,
        abortSignal: controller.signal,
        onStepStart: () => {
          if (requestIdRef.current === requestId) {
            setStreamingText("");
            setStreamingReasoning("");
          }
        },
        systemPrompt:
          currentContext.systemPrompt +
          (regenerate
            ? "\nThis is a regeneration. Provide a fresh answer or revised draft, without applying any note changes."
            : ""),
        messages: modelMessages,
        mutationAuthorized,
        executeTool: async (call) => {
          if (requestIdRef.current !== requestId) {
            return {
              ok: false,
              result: { error: "The request was cancelled." },
            };
          }
          const signature = JSON.stringify(call);
          let toolResult = executedToolCalls.has(signature)
            ? { ok: false, result: { error: "This tool call already ran." } }
            : runAiTool(
                call,
                notesInAiScope(getNotes(), effectiveScope),
                currentContext.noteId,
                {
                  outsideNotes,
                  scopeLabel: currentContext.scopeLabel,
                  promptForExpansion: effectiveScope.kind === "type",
                },
              );
          executedToolCalls.add(signature);
          if (
            toolResult.ok &&
            (call.name === "note_get" || call.name === "search")
          ) {
            const result = toolResult.result as { matches?: unknown[] };
            const entries = Array.isArray(result)
              ? result
              : (result?.matches ?? [result]);
            for (const value of entries) {
              if (!value || typeof value !== "object" || !("id" in value))
                continue;
              const item = value as {
                id: string;
                title?: string;
                body?: string;
                excerpt?: string;
              };
              const source = getNotes().find(
                (candidate) => candidate.id === item.id,
              );
              if (!source) continue;
              const snapshot = {
                noteId: source.id,
                title: noteTitle(source),
                type: source.path,
                excerpt: item.body ?? item.excerpt ?? "",
                revision: chatContentRevision(source.content),
              };
              const index = currentContext.sources.findIndex(
                (candidate) => candidate.noteId === source.id,
              );
              if (index >= 0) currentContext.sources[index] = snapshot;
              else currentContext.sources.push(snapshot);
            }
          }

          if (toolResult.mutation) {
            const latestChat = vaultBackend
              ? (await loadChatConversations(vaultBackend)).find(
                  (chat) => chat.id === chatId,
                )
              : null;
            if (
              controller.signal.aborted ||
              !latestChat ||
              latestChat.owner.id !== chatDevice?.id ||
              latestChat.archivedAt ||
              latestChat.deletedAt
            ) {
              return {
                ok: false,
                result: {
                  error:
                    "This conversation is no longer writable on this device.",
                },
              };
            }
            const latestNote = getNotes().find(
              (candidate) => candidate.id === toolResult.mutation?.noteId,
            );
            const action = toolResult.mutation.action;
            if (
              !latestNote ||
              contextRef.current?.noteId !== currentContext.noteId
            ) {
              toolResult = {
                ok: false,
                result: {
                  error: "The selected note changed before the tool ran.",
                },
              };
            } else {
              const latestBody = noteBody(latestNote.content);
              if (
                action.type === "replace_body" &&
                latestBody !== currentContext.noteBody
              ) {
                toolResult = {
                  ok: false,
                  result: {
                    error:
                      "The note changed while the AI was thinking; replacement refused.",
                  },
                };
              } else {
                applyChange(
                  latestNote.id,
                  applyAiNoteAction(latestBody, action),
                );
                editApplied = true;
                toolResult = {
                  ok: true,
                  result: {
                    message: "The current note was updated successfully.",
                  },
                };
                showSuccess("Note updated by AI");
              }
            }
          }
          return toolResult;
        },
        onToolStart: ({ call }) => {
          if (controller.signal.aborted) return;
          setStreamingText("");
          completedToolCalls = [
            ...completedToolCalls,
            toolCallActivity(call, "running"),
          ];
          setStreamingToolCalls(completedToolCalls);
        },
        onToolEnd: ({ call, result }) => {
          if (controller.signal.aborted) return;
          const activity = toolCallActivity(
            call,
            result?.ok ? "complete" : "error",
            formatToolDetail(
              result ?? { ok: false, result: { error: "No tool result." } },
            ),
          );
          completedToolCalls = [...completedToolCalls.slice(0, -1), activity];
          setStreamingToolCalls(completedToolCalls);
        },
      });
      if (requestIdRef.current !== requestId) return;
      if (import.meta.env.DEV) {
        console.debug(
          "[Zerus AI] generation completed",
          agentResult.diagnostics,
        );
      }

      // Accept the action format used by development builds before tools were introduced.
      const parsed = parseAiResponse(agentResult.text);
      const finalContent = parsed.content;
      if (parsed.actionError) {
        showError(`The AI note edit was not applied: ${parsed.actionError}`);
      } else if (parsed.action && !mutationAuthorized) {
        showError(
          "The AI note edit was refused because the current request did not explicitly authorize a change.",
        );
      } else if (parsed.action) {
        const latestNote = getNotes().find(
          (candidate) => candidate.id === currentContext.noteId,
        );
        if (
          !latestNote ||
          contextRef.current?.noteId !== currentContext.noteId
        ) {
          showError(
            "The AI edit was not applied because the selected note changed.",
          );
        } else {
          const latestBody = noteBody(latestNote.content);
          if (
            parsed.action.type === "replace_body" &&
            latestBody !== currentContext.noteBody
          ) {
            showError(
              "The AI edit was not applied because the note changed while it was thinking.",
            );
          } else {
            applyChange(
              latestNote.id,
              applyAiNoteAction(latestBody, parsed.action),
            );
            editApplied = true;
            showSuccess("Note updated by AI");
          }
        }
      }

      await finishAnswer({
        role: "assistant",
        content:
          finalContent ||
          (editApplied
            ? "Updated the note."
            : "I couldn't finish that request."),
        reasoning: agentResult.reasoning,
        editApplied,
        toolCalls: completedToolCalls,
      });
    } catch (error) {
      if (requestIdRef.current !== requestId) return;
      const message = String(error);
      if (changes.length || streamTextRef.current.trim()) {
        try {
          await finishAnswer({
            role: "assistant",
            content: [
              streamTextRef.current,
              changes.length
                ? "The request ended after making changes to your note. Review or undo those changes below."
                : "Answer interrupted. You can regenerate to try again.",
            ]
              .filter(Boolean)
              .join("\n\n"),
            interrupted: true,
            editApplied: changes.length > 0,
          });
        } catch {
          /* Keep the visible answer and change snapshots available even if persistence failed. */
        }
      }
      setInlineError(
        controller.signal.aborted
          ? "Answer stopped. You can retry this question."
          : `Could not finish: ${message}`,
      );
    } finally {
      if (requestIdRef.current === requestId) {
        activeStreamIdRef.current = null;
        setStreamingReasoning("");
        setStreamingText("");
        setStreamingToolCalls([]);
        setSending(false);
        sendInFlightRef.current = false;
      }
    }
  };

  const newSession = () => {
    requestIdRef.current += 1;
    sendInFlightRef.current = false;
    activeStreamIdRef.current = null;
    abortRef.current?.abort();
    setChatId(crypto.randomUUID());
    setSharedConversation(null);
    setSelectedNoteIds(null);
    localStorage.removeItem(historyStorageKey);
    setHistoryOpen(false);
    setInlineError("");
    setStreamingText("");
    setHistoryOmitted(0);
    setShowJump(false);
    setMessages([]);
    setPendingDocuments([]);
    setDocumentContextStatus("");
    setDraft("");
    setPendingAttachments((current) => {
      for (const attachment of current)
        URL.revokeObjectURL(attachment.previewUrl);
      return [];
    });
    setStreamingReasoning("");
    setStreamingToolCalls([]);
    setSending(false);
  };

  const loadCloudModels = async (
    provider: AiProvider,
    baseUrl: string,
    apiKey: string,
  ) => {
    setLoadingModels(true);
    try {
      const models = await invoke<CloudAiModel[]>("cloud_ai_models", {
        provider,
        baseUrl,
        apiKey: apiKey.trim() || null,
      });
      setCloudModels(models);
      setCloudModelsSource(`${provider}:${baseUrl}`);
      setCloudReady(true);
      showSuccess(`Loaded ${models.length} cloud models`);
    } catch (error) {
      setCloudReady(false);
      showError(String(error));
    } finally {
      setLoadingModels(false);
    }
  };

  const applyCodexStatus = (status: CodexAiStatus) => {
    setCodexStatus(status);
    setCloudReady(status.connected);
    setCloudModels(status.models);
    setCloudModelsSource(`codex:${CODEX_PROVIDER_URL}`);
    return status.connected;
  };

  const connectCodex = async () => {
    try {
      const status = await invoke<CodexAiStatus>("codex_ai_login");
      const connected = applyCodexStatus(status);
      if (connected) showSuccess("ChatGPT connected through Codex");
      return connected;
    } catch (error) {
      showError(String(error));
      return false;
    }
  };

  const refreshCodex = async () => {
    setLoadingModels(true);
    try {
      const status = await invoke<CodexAiStatus>("codex_ai_status");
      const connected = applyCodexStatus(status);
      if (!status.available)
        showError("Install ChatGPT or Codex CLI to use ChatGPT sign-in.");
      return connected;
    } catch (error) {
      showError(String(error));
      return false;
    } finally {
      setLoadingModels(false);
    }
  };

  const connectOpenRouter = async () => {
    try {
      await invoke("openrouter_oauth_login");
      setCloudReady(true);
      showSuccess("OpenRouter connected securely");
      return true;
    } catch (error) {
      showError(String(error));
      return false;
    }
  };

  const saveProvider = async (config: AiProviderConfig, apiKey: string) => {
    try {
      if (config.provider === "codex") {
        const status = await invoke<CodexAiStatus>("codex_ai_status");
        if (!applyCodexStatus(status)) {
          throw new Error("Connect ChatGPT before saving this provider.");
        }
      } else {
        await invoke("cloud_ai_configure", {
          provider: config.provider,
          baseUrl: config.baseUrl,
          apiKey: apiKey.trim() || null,
        });
        setCloudReady(true);
      }
      saveAiProviderConfig(config);
      const backend = getVaultBackend();
      if (backend && config.provider !== "codex") {
        await writeSharedAiSettings(backend, config);
      }
      setProviderConfig(config);
      setProviderDialogOpen(false);
      newSession();
    } catch (error) {
      showError(String(error));
    }
  };

  const handleResizeStart = (event: React.PointerEvent<HTMLDivElement>) => {
    event.preventDefault();
    const startX = event.clientX;
    const startWidth = panelRef.current?.getBoundingClientRect().width ?? width;
    const handle = event.currentTarget;
    handle.setPointerCapture(event.pointerId);
    const onMove = (moveEvent: PointerEvent) => {
      const editorAreaWidth =
        panelRef.current?.parentElement?.getBoundingClientRect().width ??
        window.innerWidth;
      const maxWidth = Math.min(
        window.innerWidth * 0.65,
        Math.max(MIN_WIDTH, editorAreaWidth - 240),
      );
      setWidth(
        Math.round(
          Math.max(
            MIN_WIDTH,
            Math.min(maxWidth, startWidth - (moveEvent.clientX - startX)),
          ),
        ),
      );
    };
    const onUp = () => {
      handle.removeEventListener("pointermove", onMove);
      handle.removeEventListener("pointerup", onUp);
      setWidth((current) => {
        localStorage.setItem(WIDTH_STORAGE_KEY, String(current));
        return current;
      });
    };
    handle.addEventListener("pointermove", onMove);
    handle.addEventListener("pointerup", onUp);
  };

  const aiReady = cloudReady;
  const activeCloudModels =
    `${providerConfig.provider}:${providerConfig.baseUrl}` === cloudModelsSource
      ? cloudModels
      : [];
  const favoriteCloudModels = providerConfig.favoriteModels
    .map((id) => ({
      id,
      name: activeCloudModels.find((model) => model.id === id)?.name ?? id,
    }))
    .filter(
      (model, index, models) =>
        models.findIndex(({ id }) => id === model.id) === index,
    );
  const currentModelName =
    activeCloudModels.find(({ id }) => id === providerConfig.model)?.name ??
    providerConfig.model;

  return (
    <>
      <div
        ref={panelRef}
        data-ai-chat="true"
        onDragOver={(event) => { if (!event.dataTransfer.types.includes("Files")) return; event.preventDefault(); event.stopPropagation(); event.dataTransfer.dropEffect = "copy"; setFileDragOver(true); }}
        onDragLeave={(event) => { if (!(event.relatedTarget instanceof Node) || !event.currentTarget.contains(event.relatedTarget)) setFileDragOver(false); }}
        onDrop={(event) => { event.preventDefault(); event.stopPropagation(); setFileDragOver(false); void selectImages(Array.from(event.dataTransfer.files)); }}
        className={cn(
          "relative h-full shrink-0 border-l border-border/70 bg-zerus-editor",
          !open && "hidden",
        )}
        style={{
          width: `min(${width}px, 65vw)`,
          maxWidth: "calc(100% - 240px)",
        }}
      >
        {fileDragOver && <div className="pointer-events-none absolute inset-0 z-50 flex items-center justify-center border-2 border-zerus-accent bg-zerus-editor/95"><div className="flex items-center gap-2 text-sm font-medium"><Paperclip size={18} />Drop files into chat</div></div>}
        <div
          className="absolute inset-y-0 -left-2 z-20 w-4 cursor-col-resize touch-none"
          onPointerDown={handleResizeStart}
          role="separator"
          aria-label="Resize AI panel"
        />
        <div className="flex h-full min-w-0 flex-col" inert={historyOpen}>
          <header className="flex h-14 shrink-0 items-center border-b border-border/60 px-3">
            <div className="flex min-w-0 flex-1 items-center gap-2.5">
              <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-zerus-accent/10 text-zerus-accent">
                <Sparkles size={15} />
              </div>
              <div className="flex min-w-0 flex-1 flex-col justify-center gap-0.5">
                <Select
                  value={providerConfig.model}
                  onValueChange={(model) => {
                    const next = { ...providerConfig, model };
                    saveAiProviderConfig(next);
                    setProviderConfig(next);
                  }}
                >
                  <SelectTrigger
                    disabled={BROWSER_PREVIEW || sending}
                    className="h-4 w-fit max-w-full gap-1 border-0 bg-transparent p-0 text-xs font-medium leading-4 shadow-none focus:ring-0 [&>svg]:h-3 [&>svg]:w-3"
                  >
                    <SelectValue placeholder="Choose a model">
                      {currentModelName}
                    </SelectValue>
                  </SelectTrigger>
                  <SelectContent>
                    {favoriteCloudModels.length > 0 ? (
                      favoriteCloudModels.map((model) => (
                        <SelectItem key={model.id} value={model.id}>
                          {model.name}
                        </SelectItem>
                      ))
                    ) : (
                      <p className="px-2 py-1.5 text-sm text-muted-foreground">
                        No saved favourites
                      </p>
                    )}
                  </SelectContent>
                </Select>
                <div className="truncate text-[10px] leading-3 text-muted-foreground">
                  {context?.scopeLabel ?? "Folder context"} ·{" "}
                  {
                    {
                      openai: "OpenAI",
                      codex: "ChatGPT · Codex",
                      anthropic: "Claude",
                      openrouter: "OpenRouter",
                      compatible: "Cloud API",
                    }[providerConfig.provider]
                  }{" "}
                  · web search off · provider defaults
                </div>
              </div>
            </div>
            <div className="ml-2 flex shrink-0 items-center gap-0.5">
              <Button
                variant="ghost"
                size="sm"
                className="h-8 px-2 text-xs"
                disabled={sending}
                onClick={() => {
                  void refreshHistory().catch((error) =>
                    setInlineError(String(error)),
                  );
                  setHistoryOpen(true);
                }}
              >
                History
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8 rounded-md"
                onClick={() => setProviderDialogOpen(true)}
                disabled={BROWSER_PREVIEW || sending}
                title="Configure AI chat"
                aria-label="Configure AI chat"
              >
                <Settings size={14} />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8 rounded-md"
                onClick={newSession}
                disabled={sending}
                title="New chat"
                aria-label="New chat"
              >
                <Plus size={14} />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8 rounded-md"
                onClick={() => onOpenChange(false)}
                aria-label="Close AI chat"
              >
                <X size={15} />
              </Button>
            </div>
          </header>

          <div className="truncate border-b px-3 py-2 text-xs font-medium">
            {sharedConversation?.title ?? "New chat"}
          </div>
          <ChatContextPicker
            note={note}
            notes={notes}
            scope={effectiveScope}
            selected={selectedNoteIds ?? (effectiveScope.kind === "selection" ? effectiveScope.noteIds : null)}
            onChange={(ids) =>
              setSelectedNoteIds(
                ids ??
                  notesInAiScope(notes, scope).map((candidate) => candidate.id),
              )
            }
            disabled={sending || !ownsSharedConversation}
          />
          <details className="border-b px-3 py-2 text-xs">
            <summary className="cursor-pointer text-muted-foreground">
              Preview context · {context?.sources.length ?? 0} excerpts
            </summary>
            <div className="max-h-48 space-y-3 overflow-auto py-2">
              {context?.sources.map((source) => (
                <div key={source.noteId}>
                  <p className="font-medium">{source.title}</p>
                  <p className="mt-1 whitespace-pre-wrap text-muted-foreground">
                    {source.excerpt}
                  </p>
                </div>
              ))}
              {context?.sources.length === 0 && (
                <p>No note excerpts selected.</p>
              )}
            </div>
          </details>
          {sharedConversation?.summary && (
            <details className="border-b px-3 py-2 text-xs">
              <summary className="cursor-pointer">Conversation memory</summary>
              <p className="max-h-40 overflow-auto whitespace-pre-wrap py-2">
                {sharedConversation.summary.text}
              </p>
            </details>
          )}
          {BROWSER_PREVIEW && (
            <p className="border-b px-3 py-2 text-xs text-muted-foreground">
              Local preview · answers show retrieved excerpts. Cloud AI runs in
              the desktop app.
            </p>
          )}
          {!cloudReady && (
            <div className="flex items-center gap-2 border-b border-border/60 bg-muted/40 px-3 py-2 text-xs">
              <span className="min-w-0 flex-1 text-muted-foreground">
                {providerConfig.provider === "codex"
                  ? "Connect your ChatGPT account to enable AI chat."
                  : "Enter your provider API key to enable cloud chat."}
              </span>
              <Button
                variant="outline"
                size="sm"
                className="h-7"
                onClick={() => setProviderDialogOpen(true)}
              >
                Configure
              </Button>
            </div>
          )}

          {sharedConversation && chatDevice && !ownsSharedConversation && (
            <div className="flex items-center gap-2 border-b border-border/60 bg-muted/40 px-3 py-2 text-xs">
              <span className="min-w-0 flex-1 text-muted-foreground">
                {sharedConversation.deletedAt
                  ? "This conversation is in Recently deleted."
                  : sharedConversation.archivedAt
                    ? "This conversation is archived."
                    : `Read-only · owned by ${chatDeviceLabel(sharedConversation.owner, [chatDevice, sharedConversation.owner])}`}
              </span>
              {sharedConversation.owner.id !== chatDevice.id && (
                <Button
                  variant="outline"
                  size="sm"
                  className="h-7"
                  onClick={() => void takeSharedConversation()}
                >
                  Move here
                </Button>
              )}
            </div>
          )}

          <div
            className="min-h-0 flex-1 space-y-4 overflow-y-auto px-4 py-4"
            onScroll={(event) => {
              const el = event.currentTarget;
              followOutput.current =
                el.scrollHeight - el.scrollTop - el.clientHeight < 80;
              if (followOutput.current) setShowJump(false);
            }}
          >
            {messages.length === 0 ? (
              <div className="flex h-full items-center justify-center text-center text-sm text-muted-foreground">
                <div className="max-w-64">
                  <p className="font-medium text-foreground">
                    What would you like to work on?
                  </p>
                  <p className="mt-2">
                    Ask about {context?.scopeLabel ?? "your notes"}.
                  </p>
                  <div className="mt-4 flex flex-col gap-2">
                    {[
                      note
                        ? "Summarize this note"
                        : "Summarize the main ideas in these notes",
                      "Find related ideas in my notes",
                      "Extract action items from these notes",
                    ].map((prompt) => (
                      <button
                        key={prompt}
                        disabled={sending}
                        onClick={() => setDraft(prompt)}
                        className="rounded-lg border p-2 text-left text-xs hover:bg-muted"
                      >
                        {prompt}
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            ) : (
              messages.map((message, index) => (
                <div
                  key={message.id ?? `${message.role}-${index}`}
                  className={cn(
                    "max-w-[92%] rounded-xl px-3 py-2 text-sm",
                    message.role === "user"
                      ? "ml-auto bg-zerus-accent text-white"
                      : "border border-border/70 bg-muted/35",
                  )}
                >
                  {message.documents?.map((document, index) => <div key={index} className="mb-2 flex min-w-0 items-center gap-2 text-xs"><Paperclip size={14} className="shrink-0" /><span className="break-all">{document.name}</span></div>)}
                  {message.attachments && message.attachments.length > 0 && (
                    <div
                      className={cn(
                        "mb-2 grid gap-2",
                        message.attachments.length > 1 && "grid-cols-2",
                      )}
                    >
                      {message.attachments.map((attachment) => (
                        <ChatImage
                          key={attachment.id}
                          attachment={attachment}
                        />
                      ))}
                    </div>
                  )}
                  <AiMarkdown
                    inverted={message.role === "user"}
                    onOpenNote={onOpenNote}
                  >
                    {message.content}
                  </AiMarkdown>
                  {message.reasoning && (
                    <details className="mt-2 border-t border-current/15 pt-2 text-xs opacity-80">
                      <summary className="cursor-pointer">Reasoning</summary>
                      <div className="mt-1 whitespace-pre-wrap">
                        {message.reasoning}
                      </div>
                    </details>
                  )}
                  {message.toolCalls && message.toolCalls.length > 0 && (
                    <ToolCallList toolCalls={message.toolCalls} />
                  )}
                  {message.sources && message.sources.length > 0 && (
                    <details className="mt-3 border-t border-current/15 pt-2 text-xs">
                      <summary className="cursor-pointer">
                        Context used · {message.sources.length} notes
                      </summary>
                      <div className="mt-2 space-y-2">
                        {message.sources.map((source) => (
                          <details key={source.noteId}>
                            <summary className="cursor-pointer">
                              {source.title}
                            </summary>
                            <p className="my-2 whitespace-pre-wrap text-muted-foreground">
                              {source.excerpt}
                            </p>
                            <button
                              className="underline"
                              onClick={() => onOpenNote(source.noteId)}
                            >
                              Open current note
                            </button>
                          </details>
                        ))}
                      </div>
                    </details>
                  )}
                  {message.role === "assistant" && (
                    <ChatAnswerActions
                      text={message.content}
                      note={note}
                      changes={message.changes}
                      disabled={sending || !ownsSharedConversation}
                      onRegenerate={() => {
                        const userIndex = messages
                          .slice(0, index)
                          .map((candidate) => candidate.role)
                          .lastIndexOf("user");
                        if (userIndex >= 0) void sendMessage(userIndex, true);
                      }}
                    />
                  )}
                  {message.role === "user" &&
                    index === messages.length - 1 &&
                    !sending && (
                      <button
                        className="mt-2 rounded border px-2 py-1 text-xs"
                        disabled={!ownsSharedConversation}
                        onClick={() => void sendMessage(index)}
                      >
                        Retry answer
                      </button>
                    )}
                  {message.editApplied && (
                    <div className="mt-2 flex items-center gap-1.5 border-t border-current/15 pt-2 text-xs text-emerald-500">
                      <Check size={13} />
                      Note updated
                    </div>
                  )}
                </div>
              ))
            )}
            {sending && (
              <>
                {streamingToolCalls.length > 0 && (
                  <div className="max-w-[92%] rounded-xl border border-border/70 bg-muted/35 px-3 py-2 text-muted-foreground">
                    <div className="text-xs font-medium">Activity</div>
                    <ToolCallList toolCalls={streamingToolCalls} />
                  </div>
                )}
                {streamingText && (
                  <div className="max-w-[92%] rounded-xl border border-border/70 bg-muted/35 px-3 py-2 text-sm">
                    <AiMarkdown onOpenNote={onOpenNote}>
                      {streamingText}
                    </AiMarkdown>
                  </div>
                )}
                {streamingReasoning ? (
                  <div className="max-w-[92%] rounded-xl border border-border/70 bg-muted/35 px-3 py-2 text-xs text-muted-foreground">
                    <div className="mb-1 flex items-center gap-2 font-medium">
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      Reasoning
                    </div>
                    <details>
                      <summary className="cursor-pointer">
                        Show thinking
                      </summary>
                      <div className="whitespace-pre-wrap">
                        {streamingReasoning}
                      </div>
                    </details>
                  </div>
                ) : (
                  <div className="flex items-center gap-2 text-xs text-muted-foreground">
                    <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    Preparing your answer…
                  </div>
                )}
              </>
            )}
            <div ref={bottomRef} />
          </div>

          {showJump && (
            <button
              className="mx-auto mb-2 rounded-full border px-3 py-1 text-xs"
              onClick={() => {
                followOutput.current = true;
                bottomRef.current?.scrollIntoView({ block: "end" });
                setShowJump(false);
              }}
            >
              Jump to latest
            </button>
          )}
          {inlineError && (
            <div
              role="alert"
              className="border-t border-destructive/30 bg-destructive/10 p-3 text-xs"
            >
              {inlineError}
            </div>
          )}
          {documentContextStatus && <p role="status" className="px-3 py-1 text-[11px] text-muted-foreground">{documentContextStatus}</p>}
          {historyOmitted > 0 && (
            <p className="px-3 py-1 text-[11px] text-muted-foreground">
              Using recent conversation context. Full history remains saved.
            </p>
          )}
          <div className="shrink-0 border-t border-border/60 p-3">
            <input
              ref={imageInputRef}
              type="file"
              multiple
              className="hidden"
              onChange={(event) =>
                void selectImages(Array.from(event.target.files ?? []))
              }
            />
            {pendingDocuments.map((document, index) => <div key={index} className="mb-2 flex min-w-0 items-center gap-2 text-xs"><Paperclip size={14} className="shrink-0" /><span className="min-w-0 flex-1 break-all">{document.name}</span><button type="button" aria-label={`Remove ${document.name}`} onClick={() => setPendingDocuments((current) => current.filter((_, position) => position !== index))}><X size={14} /></button></div>)}
            {pendingAttachments.length > 0 && (
              <div className="mb-2 flex gap-2 overflow-x-auto pb-1">
                {pendingAttachments.map((attachment, index) => (
                  <div
                    key={`${attachment.name}-${index}`}
                    className="group relative h-16 w-16 shrink-0 overflow-hidden rounded-lg border border-border/70 bg-muted"
                  >
                    <img
                      src={attachment.previewUrl}
                      alt={attachment.name || "Selected attachment"}
                      className="h-full w-full object-cover"
                    />
                    <button
                      type="button"
                      className="absolute right-1 top-1 flex h-5 w-5 items-center justify-center rounded-full bg-black/70 text-white opacity-90 transition-opacity hover:opacity-100"
                      onClick={() =>
                        setPendingAttachments((current) =>
                          current.filter((candidate) => {
                            if (candidate === attachment) {
                              URL.revokeObjectURL(candidate.previewUrl);
                              return false;
                            }
                            return true;
                          }),
                        )
                      }
                      aria-label={`Remove ${attachment.name || "image"}`}
                      title="Remove image"
                    >
                      <X size={12} />
                    </button>
                  </div>
                ))}
              </div>
            )}
            <Textarea
              aria-label="Message AI"
              value={draft}
              onChange={(event) => setDraft(event.target.value)}
              onPaste={(event) => {
                const images = imageFilesFromClipboard(
                  event.clipboardData.items,
                );
                if (!images.length) return;
                event.preventDefault();
                void selectImages(images);
              }}
              onKeyDown={(event) => {
                if (
                  event.key === "Enter" &&
                  !event.shiftKey &&
                  !event.nativeEvent.isComposing
                ) {
                  event.preventDefault();
                  void sendMessage();
                }
              }}
              placeholder={`Ask about ${context?.scopeLabel ?? "this context"}…`}
              className="min-h-20 resize-none"
              disabled={
                !context || sending || !aiReady || !ownsSharedConversation
              }
            />
            <div className="mt-2 flex items-center justify-between">
              <Button
                variant="ghost"
                size="sm"
                className="h-8 gap-1.5 px-2 text-muted-foreground"
                onClick={() => imageInputRef.current?.click()}
                disabled={
                  !context ||
                  sending ||
                  !aiReady ||
                  !ownsSharedConversation ||
                  preparingImages
                }
                title="Attach files"
              >
                {preparingImages ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <Paperclip size={14} />
                )}
                Attach
              </Button>
              {sending ? (
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    abortRef.current?.abort();
                    setInlineError("Stopping answer…");
                  }}
                >
                  Stop
                </Button>
              ) : (
                <Button
                  size="sm"
                  className="h-8 gap-1.5"
                  onClick={() => void sendMessage()}
                  disabled={
                    !context ||
                    sending ||
                    !aiReady ||
                    !ownsSharedConversation ||
                    preparingImages ||
                    (!draft.trim() && pendingAttachments.length === 0 && pendingDocuments.length === 0)
                  }
                >
                  <Send size={14} />
                  Send
                </Button>
              )}
            </div>
          </div>
        </div>
        {historyOpen && (
          <ChatHistory
            chats={conversations}
            device={chatDevice}
            onSelect={selectConversation}
            onRefresh={refreshHistory}
            onClose={() => setHistoryOpen(false)}
            onNew={newSession}
          />
        )}
      </div>
      <AiProviderDialog
        open={providerDialogOpen}
        config={providerConfig}
        models={cloudModels}
        modelsSource={cloudModelsSource}
        loadingModels={loadingModels}
        codexAvailable={codexStatus?.available ?? false}
        codexConnected={codexStatus?.connected ?? false}
        codexAccountLabel={codexStatus?.accountLabel ?? ""}
        codexPlanType={codexStatus?.planType ?? ""}
        onOpenChange={setProviderDialogOpen}
        onLoadModels={loadCloudModels}
        onConnectCodex={connectCodex}
        onRefreshCodex={refreshCodex}
        onConnectOpenRouter={connectOpenRouter}
        onSave={(config, apiKey) => void saveProvider(config, apiKey)}
      />
    </>
  );
}
