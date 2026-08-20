import { useCallback, useEffect, useMemo, useRef, useState, type CSSProperties, type TouchEvent as ReactTouchEvent } from "react";
import {
  Archive,
  ArrowLeft,
  Brain,
  Cloud,
  History,
  ImagePlus,
  Loader2,
  Mic,
  MoreHorizontal,
  Plus,
  RotateCcw,
  Search,
  Send,
  Settings2,
  Sparkles,
  Square,
  Trash2,
  X,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import {
  appendAssistantMessage,
  appendUserMessage,
  chatContentRevision,
  createChatWithUserMessage,
  loadChatConversations,
  purgeExpiredChats,
  resetChatSummary,
  renameChat,
  saveChatSummary,
  setChatLifecycle,
  transferChatOwnership,
  unansweredTurnIds,
  type ChatConversation,
  type ChatDevice,
  type ChatImageAttachment,
  type ChatSourceSnapshot,
  type ChatScope,
  type PersistedChatMessage,
} from "@/lib/mobile-chat-history";
import { chatDeviceLabel, getChatDevice } from "@/lib/mobile-device";
import {
  cloudEndpointLabel,
  connectOpenRouter,
  configureCloudAI,
  generateCloudAI,
  getCloudAIStatus,
  getCloudAIModels,
  stopCloudAI,
  type CloudAIStatus,
} from "@/lib/mobile-cloud-ai";
import { mobileDiagnostic } from "@/lib/mobile-diagnostics";
import {
  executeMobileAIActions,
  parseMobileAIActions,
  questionRequestsNoteMutation,
} from "@/lib/mobile-ai-actions";
import { buildNotesPrompt, cleanNotesAnswer } from "@/lib/mobile-ai-response";
import { prepareChatImage, questionReferencesImage, type PreparedChatImage } from "@/lib/mobile-chat-image";
import { horizontalSwipeDirection } from "@/lib/mobile-gestures";
import {
  retrieveNotes,
  type NoteRetrievalResult,
} from "@/lib/mobile-note-retrieval";
import {
  cancelOnDeviceSpeechRecognition,
  getOnDeviceSpeechRecognitionProgress,
  startOnDeviceSpeechRecognition,
  stopOnDeviceSpeechRecognition,
} from "@/lib/mobile-speech-recognition";
import { noteTypePath, type Note } from "@/lib/note-utils";
import type { VaultBackend } from "@/lib/vault/backend";
import { createNote, getNotes, getVaultBackend, trashNote, updateNoteBody } from "@/store/notes-store";
import { noteBody } from "@/lib/frontmatter";
import { readSharedAiSettings, writeSharedAiSettings } from "@/lib/shared-ai-settings";
import { DEFAULT_AI_PROVIDER_CONFIGS, type AiProviderConfig } from "@/lib/ai-provider-config";

type HistoryFilter =
  | "all"
  | "device"
  | "other"
  | "archived"
  | "deleted";

type MobileCloudProvider = "openrouter" | "compatible";

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  if (error && typeof error === "object" && "message" in error) return String(error.message);
  return "The AI provider could not complete that request.";
}

function conversationSummaryPrompt(conversation: ChatConversation, messages: PersistedChatMessage[]): string {
  const transcript = messages
    .map((message) => `${message.role === "user" ? "User" : "Assistant"}: ${message.text}`)
    .join("\n\n");
  return [
    "Update a concise factual memory for an ongoing conversation. Preserve decisions, user preferences, named entities, unresolved questions, and important context. Do not add facts. Return only the updated memory.",
    conversation.summary ? `Previous memory:\n${conversation.summary.text}` : "",
    `Turns to incorporate:\n${transcript}`,
  ].filter(Boolean).join("\n\n");
}

function sourceSnapshots(retrieval: NoteRetrievalResult, notes: Note[]): ChatSourceSnapshot[] {
  return retrieval.notes.map((source) => {
    const current = notes.find((note) => note.id === source.id);
    return {
      noteId: source.id,
      title: source.title,
      type: source.type,
      excerpt: source.excerpt,
      revision: chatContentRevision(current?.content ?? source.excerpt),
    };
  });
}

function filterConversations(
  conversations: ChatConversation[],
  device: ChatDevice,
  filter: HistoryFilter,
  query: string,
): ChatConversation[] {
  const term = query.trim().toLowerCase();
  return conversations.filter((conversation) => {
    const matchesFilter = filter === "deleted" ? Boolean(conversation.deletedAt)
      : filter === "archived" ? Boolean(conversation.archivedAt) && !conversation.deletedAt
      : conversation.archivedAt || conversation.deletedAt ? false
      : filter === "device" ? conversation.owner.id === device.id
      : filter === "other" ? conversation.owner.id !== device.id
      : true;
    if (!matchesFilter) return false;
    if (!term) return true;
    return `${conversation.title} ${conversation.messages.map((message) => message.text).join(" ")}`
      .toLowerCase().includes(term);
  });
}

function HistoryConversationRow({
  conversation,
  device,
  deviceNames,
  onOpen,
  onActions,
}: {
  conversation: ChatConversation;
  device: ChatDevice;
  deviceNames: ChatDevice[];
  onOpen: () => void;
  onActions: () => void;
}) {
  const longPressTimer = useRef<number | null>(null);
  const longPressTriggered = useRef(false);

  const cancelLongPress = () => {
    if (longPressTimer.current !== null) window.clearTimeout(longPressTimer.current);
    longPressTimer.current = null;
  };

  useEffect(() => () => {
    if (longPressTimer.current !== null) window.clearTimeout(longPressTimer.current);
  }, []);

  const beginLongPress = () => {
    cancelLongPress();
    longPressTriggered.current = false;
    longPressTimer.current = window.setTimeout(() => {
      longPressTimer.current = null;
      longPressTriggered.current = true;
      onActions();
    }, 500);
  };

  const openConversation = () => {
    if (longPressTriggered.current) {
      longPressTriggered.current = false;
      return;
    }
    onOpen();
  };

  return (
    <div className="flex select-none items-stretch border-b border-white/[0.07] last:border-0">
      <button
        type="button"
        onClick={openConversation}
        onPointerDown={beginLongPress}
        onPointerUp={cancelLongPress}
        onPointerCancel={cancelLongPress}
        onPointerLeave={cancelLongPress}
        onContextMenu={(event) => { event.preventDefault(); cancelLongPress(); onActions(); }}
        className="flex min-w-0 flex-1 items-center gap-3 px-4 py-4 text-left"
      >
        <div className="min-w-0 flex-1">
          <p className="truncate text-[15px] font-semibold">{conversation.title}</p>
          <p className="mt-1 truncate text-xs text-[#77777d]">{chatDeviceLabel(conversation.owner, deviceNames)} · {conversation.messages.length} messages</p>
        </div>
        {conversation.owner.id !== device.id && <span className="rounded-full bg-white/[0.07] px-2 py-1 text-[10px] text-[#aaa6a0]">Read-only</span>}
      </button>
      <button
        type="button"
        onClick={onActions}
        className="flex w-12 shrink-0 items-center justify-center text-[#77777d] active:bg-white/[0.05]"
        aria-label={`Actions for ${conversation.title}`}
      >
        <MoreHorizontal className="h-5 w-5" />
      </button>
    </div>
  );
}

function PersistedChatImage({ attachment }: { attachment: ChatImageAttachment }) {
  const [url, setUrl] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    let objectUrl: string | null = null;
    const backend = getVaultBackend();
    if (!backend) return;
    void backend.readBinary(attachment.path).then((bytes) => {
      if (!active) return;
      const ownedBytes = new Uint8Array(bytes);
      objectUrl = URL.createObjectURL(new Blob([ownedBytes], { type: attachment.mimeType }));
      setUrl(objectUrl);
    }).catch(() => {
      if (active) setUrl(null);
    });
    return () => {
      active = false;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [attachment.mimeType, attachment.path]);

  if (!url) return <div className="h-28 w-40 animate-pulse rounded-lg bg-white/[0.08]" />;
  return (
    <img
      src={url}
      alt={attachment.name || "Chat attachment"}
      width={attachment.width}
      height={attachment.height}
      className="max-h-72 w-auto max-w-full rounded-lg object-contain"
    />
  );
}

export function PersistentAIChat({
  notes,
  notesReady,
  notesPreparationError,
  onRetryNotesPreparation,
  visible,
  historyVisible,
  onClose,
  onOpenHistory,
  onCloseHistory,
  onOpenNote,
  scope,
}: {
  notes: Note[];
  notesReady: boolean;
  notesPreparationError: string | null;
  onRetryNotesPreparation: () => void;
  visible: boolean;
  historyVisible: boolean;
  onClose: () => void;
  onOpenHistory: () => void;
  onCloseHistory: () => void;
  onOpenNote: (noteId: string) => void;
  scope: ChatScope;
}) {
  const fullViewportHeight = useRef(typeof window === "undefined" ? 0 : (window.visualViewport?.height ?? window.innerHeight));
  const returningFromNote = useRef(false);
  const previousScopeKey = useRef(JSON.stringify(scope));
  const previousOwner = useRef<string | null>(null);
  const speechDraftPrefix = useRef("");
  const speechProgressFailed = useRef(false);
  const swipeStart = useRef<{ x: number; y: number; axis: "horizontal" | "vertical" | null } | null>(null);
  const swipeTimer = useRef<number | null>(null);
  const imageInput = useRef<HTMLInputElement | null>(null);
  const pendingImagesRef = useRef<PreparedChatImage[]>([]);
  const [device, setDevice] = useState<ChatDevice | null>(null);
  const [conversations, setConversations] = useState<ChatConversation[]>([]);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [blankChat, setBlankChat] = useState(false);
  const [optionsOpen, setOptionsOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [memoryOpen, setMemoryOpen] = useState(false);
  const [snapshotOpen, setSnapshotOpen] = useState<ChatSourceSnapshot | null>(null);
  const [historyFilter, setHistoryFilter] = useState<HistoryFilter>("all");
  const [historyQuery, setHistoryQuery] = useState("");
  const [historyActionsId, setHistoryActionsId] = useState<string | null>(null);
  const [cloudStatus, setCloudStatus] = useState<CloudAIStatus | null>(null);
  const [mobileProvider, setMobileProvider] = useState<MobileCloudProvider>("openrouter");
  const [providerProfiles, setProviderProfiles] = useState<Partial<Record<MobileCloudProvider, AiProviderConfig>>>({});
  const [cloudEndpoint, setCloudEndpoint] = useState("https://openrouter.ai/api/v1");
  const [cloudModel, setCloudModel] = useState("openai/gpt-5-mini");
  const [favoriteModels, setFavoriteModels] = useState<string[]>([]);
  const [discoveredModels, setDiscoveredModels] = useState<Array<{ id: string; name: string }>>([]);
  const [modelSearch, setModelSearch] = useState("");
  const [cloudAPIKey, setCloudAPIKey] = useState("");
  const [editingAPIKey, setEditingAPIKey] = useState(false);
  const [draft, setDraft] = useState("");
  const [pendingImages, setPendingImages] = useState<PreparedChatImage[]>([]);
  const [preparingImage, setPreparingImage] = useState(false);
  const [busy, setBusy] = useState(false);
  const [streamingText, setStreamingText] = useState("");
  const [memoryBusy, setMemoryBusy] = useState(false);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [undoChanges, setUndoChanges] = useState<Array<{ id: string; content: string | null }>>([]);
  const [speechState, setSpeechState] = useState<"idle" | "starting" | "listening" | "stopping">("idle");
  const [speechEngine, setSpeechEngine] = useState<string | null>(null);
  const [speechBuild, setSpeechBuild] = useState<string | null>(null);
  const [viewport, setViewport] = useState({
    height: typeof window === "undefined" ? 0 : window.innerHeight,
    offsetTop: 0,
    keyboardOpen: false,
  });
  const [swipeX, setSwipeX] = useState(0);
  const [swipeDragging, setSwipeDragging] = useState(false);
  const [swipeSettling, setSwipeSettling] = useState(false);

  useEffect(() => {
    const nextScopeKey = JSON.stringify(scope);
    if (previousScopeKey.current === nextScopeKey) return;
    previousScopeKey.current = nextScopeKey;
    setConversationId(null);
    setBlankChat(true);
    setOptionsOpen(false);
    setDraft("");
    for (const image of pendingImagesRef.current) URL.revokeObjectURL(image.previewUrl);
    pendingImagesRef.current = [];
    setPendingImages([]);
  }, [scope]);

  const replacePendingImages = (images: PreparedChatImage[]) => {
    for (const image of pendingImagesRef.current) URL.revokeObjectURL(image.previewUrl);
    pendingImagesRef.current = images;
    setPendingImages(images);
  };

  const current = conversations.find((conversation) => conversation.id === conversationId) ?? null;
  const isOwner = Boolean(current && device && current.owner.id === device.id);
  const canEditCurrent = Boolean(isOwner && !current?.archivedAt && !current?.deletedAt);
  const messages = current?.messages ?? [];
  const deviceNames = useMemo(() => {
    const values = conversations.map((conversation) => conversation.owner);
    if (device) values.push(device);
    return values;
  }, [conversations, device]);

  const refreshHistory = useCallback(async (selectPreferred = false, selectedId?: string) => {
    const backend = getVaultBackend();
    if (!backend || !device) return [];
    setHistoryLoading(true);
    try {
      let loaded = await loadChatConversations(backend);
      if (await purgeExpiredChats(backend, loaded, device)) {
        loaded = await loadChatConversations(backend);
      }
      setConversations(loaded);
      setConversationId((existingId) => {
        if (selectedId) return selectedId;
        if (existingId && loaded.some((conversation) => conversation.id === existingId)) return existingId;
        if (!selectPreferred || blankChat) return null;
        return loaded.find((conversation) =>
          conversation.owner.id === device.id && !conversation.archivedAt && !conversation.deletedAt,
        )?.id ?? null;
      });
      return loaded;
    } catch (historyError) {
      setError(`Could not load chat history: ${errorMessage(historyError)}`);
      return [];
    } finally {
      setHistoryLoading(false);
    }
  }, [blankChat, device]);

  useEffect(() => { void getChatDevice().then(setDevice); }, []);

  useEffect(() => {
    const visualViewport = window.visualViewport;
    const syncViewport = () => {
      const height = visualViewport?.height ?? window.innerHeight;
      if (height > fullViewportHeight.current) fullViewportHeight.current = height;
      setViewport({
        height,
        offsetTop: visualViewport?.offsetTop ?? 0,
        keyboardOpen: fullViewportHeight.current - height > 120,
      });
    };
    syncViewport();
    visualViewport?.addEventListener("resize", syncViewport);
    visualViewport?.addEventListener("scroll", syncViewport);
    window.addEventListener("resize", syncViewport);
    return () => {
      visualViewport?.removeEventListener("resize", syncViewport);
      visualViewport?.removeEventListener("scroll", syncViewport);
      window.removeEventListener("resize", syncViewport);
    };
  }, []);

  useEffect(() => {
    let active = true;
    const backend = getVaultBackend();
    void (async () => {
      const shared = backend ? await readSharedAiSettings(backend) : null;
      const profiles: Partial<Record<MobileCloudProvider, AiProviderConfig>> = {};
      for (const provider of ["openrouter", "compatible"] as const) {
        const profile = shared?.settings.profiles[provider];
        if (profile) profiles[provider] = { provider, ...profile };
      }
      setProviderProfiles(profiles);

      const selectedProvider: MobileCloudProvider = shared?.active.provider === "openrouter" ||
        shared?.active.provider === "compatible"
        ? shared.active.provider
        : "openrouter";
      const selected = profiles[selectedProvider] ??
        (shared?.active.provider !== "codex" && shared?.active.provider !== "anthropic"
          ? { ...shared.active, provider: selectedProvider }
          : DEFAULT_AI_PROVIDER_CONFIGS[selectedProvider]);
      setMobileProvider(selectedProvider);
      setFavoriteModels(selected.favoriteModels);
      if (selected.baseUrl) {
        try {
          return await configureCloudAI({ endpoint: selected.baseUrl, model: selected.model });
        } catch {
          // The synced profile is still useful even when this device needs credentials.
        }
      }
      return getCloudAIStatus();
    })().then((next) => {
      if (!active) return;
      setCloudStatus(next);
      setCloudEndpoint(next.endpoint);
      setCloudModel(next.model);
      setEditingAPIKey(!next.configured);
    }).catch((statusError) => {
      if (active) setError(errorMessage(statusError));
    });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    if (!visible || !device) return;
    if (returningFromNote.current) {
      returningFromNote.current = false;
      void refreshHistory(false);
    } else if (!conversationId && !blankChat) {
      void refreshHistory(true);
    } else {
      void refreshHistory(false);
    }
  }, [blankChat, conversationId, device, refreshHistory, visible]);

  useEffect(() => {
    if (!visible || !device) return;
    const timer = window.setInterval(() => void refreshHistory(false), 3_000);
    return () => window.clearInterval(timer);
  }, [device, refreshHistory, visible]);

  useEffect(() => {
    if (!current || !device) return;
    const ownerKey = `${current.ownerGeneration}:${current.owner.id}`;
    if (previousOwner.current && previousOwner.current !== ownerKey && current.owner.id !== device.id) {
      setNotice(`This conversation is now owned by ${chatDeviceLabel(current.owner, deviceNames)}.`);
    }
    previousOwner.current = ownerKey;
  }, [current, device, deviceNames]);

  useEffect(() => {
    if (visible || speechState === "idle") return;
    void cancelOnDeviceSpeechRecognition();
    setSpeechState("idle");
  }, [speechState, visible]);

  useEffect(() => {
    if (speechState !== "listening") return;
    let active = true;
    let requestInFlight = false;

    const refreshTranscript = async () => {
      if (requestInFlight) return;
      requestInFlight = true;
      try {
        const progress = await getOnDeviceSpeechRecognitionProgress();
        if (!active) return;
        if (progress.engine) setSpeechEngine(progress.engine);
        if (progress.build) setSpeechBuild(progress.build);
        const transcript = progress.transcript.trim();
        const prefix = speechDraftPrefix.current;
        setDraft(`${prefix}${prefix && transcript ? (/\s$/.test(prefix) ? "" : " ") : ""}${transcript}`);
      } catch (progressError) {
        if (!active || speechProgressFailed.current) return;
        speechProgressFailed.current = true;
        const message = errorMessage(progressError);
        setError(`Live transcription failed: ${message}`);
        mobileDiagnostic("speech recognition progress failed", progressError);
      } finally {
        requestInFlight = false;
      }
    };

    void refreshTranscript();
    const timer = window.setInterval(() => void refreshTranscript(), 150);
    return () => {
      active = false;
      window.clearInterval(timer);
    };
  }, [speechState]);

  useEffect(() => {
    if (!historyVisible) setHistoryActionsId(null);
  }, [historyVisible]);

  const saveCloudSettings = async () => {
    setBusy(true);
    setError(null);
    try {
      const next = await configureCloudAI({
        endpoint: cloudEndpoint,
        model: cloudModel,
        apiKey: cloudAPIKey || undefined,
      });
      setCloudStatus(next);
      setCloudEndpoint(next.endpoint);
      setCloudModel(next.model);
      setCloudAPIKey("");
      setEditingAPIKey(false);
      const savedProfile: AiProviderConfig = {
        provider: mobileProvider,
        baseUrl: next.endpoint,
        model: next.model,
        favoriteModels: [...new Set([...favoriteModels, next.model])],
      };
      setProviderProfiles((current) => ({ ...current, [mobileProvider]: savedProfile }));
      const backend = getVaultBackend();
      if (backend) {
        await writeSharedAiSettings(backend, savedProfile);
      }
      setSettingsOpen(false);
    } catch (configurationError) {
      setError(errorMessage(configurationError));
    } finally {
      setBusy(false);
    }
  };

  const signInWithOpenRouter = async () => {
    setBusy(true);
    setError(null);
    try {
      const next = await connectOpenRouter();
      setCloudStatus(next);
      setCloudEndpoint(next.endpoint);
      setCloudModel(next.model);
      setMobileProvider("openrouter");
      setEditingAPIKey(false);
      setFavoriteModels((current) => current.includes(next.model) ? current : [...current, next.model]);
      setDiscoveredModels(await getCloudAIModels());
      setModelSearch("");
      const savedProfile: AiProviderConfig = {
        provider: "openrouter",
        baseUrl: next.endpoint,
        model: next.model,
        favoriteModels: [...new Set([...favoriteModels, next.model])],
      };
      setProviderProfiles((current) => ({ ...current, openrouter: savedProfile }));
      const backend = getVaultBackend();
      if (backend) {
        await writeSharedAiSettings(backend, savedProfile);
      }
      setSettingsOpen(false);
    } catch (connectionError) {
      setError(errorMessage(connectionError));
    } finally {
      setBusy(false);
    }
  };

  const discoverModels = async () => {
    setBusy(true);
    setError(null);
    try {
      const next = await configureCloudAI({
        endpoint: cloudEndpoint,
        model: cloudModel,
        apiKey: cloudAPIKey || undefined,
      });
      setCloudStatus(next);
      setCloudAPIKey("");
      setEditingAPIKey(false);
      setDiscoveredModels(await getCloudAIModels());
      setModelSearch("");
    } catch (modelError) {
      setError(`${errorMessage(modelError)} You can still enter a model ID manually.`);
    } finally {
      setBusy(false);
    }
  };

  const selectMobileProvider = async (provider: MobileCloudProvider) => {
    if (provider === mobileProvider || busy) return;
    const currentProfile: AiProviderConfig = {
      provider: mobileProvider,
      baseUrl: cloudEndpoint,
      model: cloudModel,
      favoriteModels,
    };
    const profiles = { ...providerProfiles, [mobileProvider]: currentProfile };
    const nextProfile = profiles[provider] ?? DEFAULT_AI_PROVIDER_CONFIGS[provider];
    setProviderProfiles(profiles);
    setMobileProvider(provider);
    setCloudEndpoint(nextProfile.baseUrl);
    setCloudModel(nextProfile.model);
    setFavoriteModels(nextProfile.favoriteModels);
    setCloudAPIKey("");
    setDiscoveredModels([]);
    setModelSearch("");
    setError(null);
    if (!nextProfile.baseUrl) {
      setEditingAPIKey(true);
      return;
    }
    setBusy(true);
    try {
      const next = await configureCloudAI({ endpoint: nextProfile.baseUrl, model: nextProfile.model });
      setCloudStatus(next);
      setEditingAPIKey(!next.configured);
    } catch {
      setEditingAPIKey(true);
    } finally {
      setBusy(false);
    }
  };

  const generateAnswerWithCloud = (
    prompt: string,
    images: Array<{ bytes: Uint8Array; mimeType: string }> = [],
    onDelta?: (delta: string) => void,
  ) => generateCloudAI(prompt, images, onDelta);

  const updateMemory = async (conversation: ChatConversation, backend: VaultBackend, localDevice: ChatDevice) => {
    if (conversation.owner.id !== localDevice.id) return;
    const candidates = conversation.messages.slice(0, -6);
    if (candidates.length < 4) return;
    const covered = new Set(conversation.summary?.coveredMessageIds ?? []);
    const newMessages = candidates.filter((message) => !covered.has(message.id));
    if (newMessages.length < 4) return;
    setMemoryBusy(true);
    try {
      const text = await generateAnswerWithCloud(conversationSummaryPrompt(conversation, newMessages));
      await saveChatSummary(backend, conversation, localDevice, text, candidates.map((message) => message.id));
      await refreshHistory(false, conversation.id);
    } catch (summaryError) {
      mobileDiagnostic("mobile-ai.summary.error", { error: errorMessage(summaryError) });
    } finally {
      setMemoryBusy(false);
    }
  };

  const generateAnswer = async (
    backend: VaultBackend,
    conversation: ChatConversation,
    localDevice: ChatDevice,
    turnId: string,
    question: string,
  ) => {
    const activeScope = conversation.scope;
    const scopedNotes = activeScope.kind === "note"
      ? notes.filter((note) => note.id === activeScope.noteId)
      : activeScope.kind === "type"
        ? notes.filter((note) =>
          activeScope.path.every((part, index) => noteTypePath(note)[index] === part))
        : notes;
    const retrieval = retrieveNotes(scopedNotes, question);
    const previousMessages = conversation.messages.filter((message) => message.turnId !== turnId);
    const turnMessage = conversation.messages.find((message) =>
      message.turnId === turnId && message.role === "user");
    const previousImages = questionReferencesImage(question)
      ? [...previousMessages].reverse().find((message) => message.attachments?.length)?.attachments
      : undefined;
    const attachments = turnMessage?.attachments?.length ? turnMessage.attachments : previousImages ?? [];
    const images = await Promise.all(attachments.slice(0, 4).map(async (attachment) => ({
      bytes: await backend.readBinary(attachment.path),
      mimeType: attachment.mimeType,
    })));
    const mutationRequested = questionRequestsNoteMutation(
      question,
      retrieval.notes.map((note) => note.title),
    );
    const directAnswer = images.length || mutationRequested ? null : retrieval.directAnswer;
    const prompt = directAnswer ? null : buildNotesPrompt(
      retrieval, previousMessages, question, conversation.summary?.text ?? null, images.length > 0,
    );
    mobileDiagnostic("mobile-ai.question", {
      engine: "cloud",
      direct: Boolean(directAnswer),
      image: images.length > 0,
      selectedNotes: retrieval.notes.length,
      totalNotes: retrieval.totalNotes,
      promptChars: prompt?.length ?? 0,
    });
    setStreamingText("");
    const generated = directAnswer ?? await generateAnswerWithCloud(
      prompt!,
      images,
      (delta) => setStreamingText((current) => current + delta),
    );
    setStreamingText("");
    let answer = generated;
    let changedNoteIds: string[] = [];
    if (!directAnswer) {
      const parsed = parseMobileAIActions(generated);
      if (parsed.malformed) {
        throw new Error("The AI returned a note change that was not safe to apply. Please try again.");
      }
      if (parsed.actions.length) {
        if (!mutationRequested) {
          throw new Error("The AI tried to change a note without an explicit note-editing request. Nothing was changed.");
        }
        const before = new Map(getNotes().map((note) => [note.id, note.content]));
        const result = await executeMobileAIActions(parsed.actions, {
          getNotes,
          createNote,
          updateNoteBody,
        });
        changedNoteIds = result.changedNoteIds;
        setUndoChanges(result.changedNoteIds.map((id) => ({ id, content: before.get(id) ?? null })));
        answer = result.message;
      } else {
        answer = cleanNotesAnswer(parsed.visibleText, prompt!, retrieval, images.length > 0);
      }
    }
    await appendAssistantMessage(backend, conversation, localDevice, {
      turnId,
      text: answer,
      sources: sourceSnapshots(retrieval, notes),
      contextKind: retrieval.contextKind,
    });
    const loaded = await refreshHistory(false, conversation.id);
    const updated = loaded.find((candidate) => candidate.id === conversation.id);
    mobileDiagnostic("mobile-ai.answer", {
      engine: "cloud",
      direct: Boolean(directAnswer),
      image: images.length > 0,
      changedNoteIds,
    });
    if (updated) void updateMemory(updated, backend, localDevice);
  };

  const send = async () => {
    const submittedImages = pendingImages;
    const question = draft.trim() || (submittedImages.length ? "What is in these images?" : "");
    const backend = getVaultBackend();
    if (!question || !backend || !device || !notesReady || busy || memoryBusy || !cloudStatus?.configured) return;
    if (current && !canEditCurrent) return;
    setDraft("");
    setBusy(true);
    setStreamingText("");
    setError(null);
    try {
      let working = current;
      let turnId: string;
      if (!working) {
        const created = await createChatWithUserMessage(backend, device, question, submittedImages, scope);
        turnId = created.turnId;
        setBlankChat(false);
        const loaded = await refreshHistory(false, created.conversationId);
        working = loaded.find((conversation) => conversation.id === created.conversationId) ?? null;
        if (!working) throw new Error("The new conversation could not be reopened.");
      } else {
        turnId = await appendUserMessage(backend, working, device, question, submittedImages);
        const loaded = await refreshHistory(false, working.id);
        working = loaded.find((conversation) => conversation.id === working!.id) ?? working;
      }
      replacePendingImages([]);
      await generateAnswer(backend, working, device, turnId, question);
    } catch (generationError) {
      mobileDiagnostic("mobile-ai.error", { engine: "cloud", error: errorMessage(generationError) });
      setError(errorMessage(generationError));
      await refreshHistory(false);
    } finally {
      setBusy(false);
      setStreamingText("");
    }
  };

  const retryTurn = async (turnId: string) => {
    const backend = getVaultBackend();
    const question = current?.messages.find((message) => message.turnId === turnId && message.role === "user")?.text;
    if (!backend || !device || !current || !question || !notesReady || !canEditCurrent || busy || memoryBusy || !cloudStatus?.configured) return;
    setBusy(true);
    setError(null);
    try { await generateAnswer(backend, current, device, turnId, question); }
    catch (generationError) { setError(errorMessage(generationError)); }
    finally { setBusy(false); }
  };

  const selectImages = async (files: readonly File[]) => {
    if (!files.length || pendingImages.length >= 4) return;
    setPreparingImage(true);
    setError(null);
    try {
      const available = 4 - pendingImages.length;
      const prepared: PreparedChatImage[] = [];
      for (const file of files.slice(0, available)) prepared.push(await prepareChatImage(file));
      pendingImagesRef.current = [...pendingImagesRef.current, ...prepared];
      setPendingImages((current) => [...current, ...prepared]);
    } catch (imageError) {
      setError(errorMessage(imageError));
    } finally {
      setPreparingImage(false);
      if (imageInput.current) imageInput.current.value = "";
    }
  };

  const transferOwnership = async (conversation: ChatConversation) => {
    const backend = getVaultBackend();
    if (!backend || !device || conversation.owner.id === device.id) return;
    const from = chatDeviceLabel(conversation.owner, deviceNames);
    const to = chatDeviceLabel(device, deviceNames);
    if (!window.confirm(`Move this conversation from ${from} to ${to}? The other device will become read-only after syncing.`)) return;
    await transferChatOwnership(backend, conversation, device);
    setBlankChat(false);
    await refreshHistory(false, conversation.id);
    setOptionsOpen(false);
    setHistoryActionsId(null);
  };

  const mutateConversation = async (conversation: ChatConversation, kind: "archive" | "restore" | "delete") => {
    const backend = getVaultBackend();
    if (!backend || !device || conversation.owner.id !== device.id) return;
    if (kind === "delete" && !window.confirm("Move this conversation to Recently Deleted? It will be permanently removed after 30 days.")) return;
    await setChatLifecycle(backend, conversation, device, kind);
    setOptionsOpen(false);
    setHistoryActionsId(null);
    if (conversation.id === current?.id && kind !== "restore") {
      setConversationId(null);
      setBlankChat(true);
    }
    await refreshHistory(false);
  };

  const mutateCurrent = async (kind: "archive" | "restore" | "delete") => {
    if (!current || !isOwner) return;
    await mutateConversation(current, kind);
  };

  const renameConversation = async (conversation: ChatConversation) => {
    const backend = getVaultBackend();
    if (!backend || !device || conversation.owner.id !== device.id) return;
    const title = window.prompt("Conversation title", conversation.title)?.trim();
    if (!title || title === conversation.title) return;
    await renameChat(backend, conversation, device, title);
    await refreshHistory(false, conversation.id === current?.id ? conversation.id : undefined);
    setOptionsOpen(false);
    setHistoryActionsId(null);
  };

  const renameCurrent = async () => {
    if (!current || !isOwner) return;
    await renameConversation(current);
  };

  const resetMemory = async () => {
    const backend = getVaultBackend();
    if (!backend || !device || !current || !isOwner) return;
    if (!window.confirm("Reset this conversation's rolling memory? The transcript will remain unchanged.")) return;
    await resetChatSummary(backend, current, device);
    await refreshHistory(false, current.id);
    setMemoryOpen(false);
  };

  const toggleSpeech = async () => {
    if (speechState === "starting" || speechState === "stopping") return;
    setError(null);
    if (speechState === "listening") {
      setSpeechState("stopping");
      try {
        const transcript = (await stopOnDeviceSpeechRecognition()).trim();
        const prefix = speechDraftPrefix.current;
        if (transcript) setDraft(`${prefix}${prefix && !/\s$/.test(prefix) ? " " : ""}${transcript}`);
      } catch (speechError) { setError(errorMessage(speechError)); }
      finally { setSpeechState("idle"); }
      return;
    }
    setSpeechState("starting");
    speechDraftPrefix.current = draft;
    speechProgressFailed.current = false;
    try {
      const result = await startOnDeviceSpeechRecognition(navigator.language);
      setSpeechEngine(result.engine ?? null);
      setSpeechBuild(result.build ?? null);
      setSpeechState("listening");
    } catch (speechError) {
      setError(errorMessage(speechError));
      setSpeechState("idle");
    }
  };

  const startNewChat = () => {
    setConversationId(null);
    setBlankChat(true);
    setDraft("");
    replacePendingImages([]);
    setError(null);
    setOptionsOpen(false);
  };

  const close = () => {
    setOptionsOpen(false);
    setMemoryOpen(false);
    setSnapshotOpen(null);
    setConversationId(null);
    setBlankChat(false);
    replacePendingImages([]);
    onClose();
  };

  useEffect(() => () => {
    if (swipeTimer.current !== null) window.clearTimeout(swipeTimer.current);
    for (const image of pendingImagesRef.current) URL.revokeObjectURL(image.previewUrl);
  }, []);

  const finishSwipe = (complete?: () => void) => {
    setSwipeDragging(false);
    if (!complete) {
      setSwipeSettling(true);
      setSwipeX(0);
      swipeTimer.current = window.setTimeout(() => setSwipeSettling(false), 240);
      return;
    }
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setSwipeX(0);
      complete();
      return;
    }
    setSwipeSettling(true);
    setSwipeX(window.innerWidth);
    swipeTimer.current = window.setTimeout(() => {
      setSwipeSettling(false);
      setSwipeX(0);
      complete();
    }, 240);
  };

  const handleSwipeStart = (event: ReactTouchEvent<HTMLDivElement>) => {
    if (swipeSettling || optionsOpen || settingsOpen || memoryOpen || snapshotOpen || historyActionsId) return;
    if ((event.target as HTMLElement).closest("textarea, input, [contenteditable='true']")) return;
    const touch = event.touches[0];
    if (!touch) return;
    swipeStart.current = { x: touch.clientX, y: touch.clientY, axis: null };
  };

  const handleSwipeMove = (event: ReactTouchEvent<HTMLDivElement>) => {
    const start = swipeStart.current;
    const touch = event.touches[0];
    if (!start || !touch) return;
    const deltaX = touch.clientX - start.x;
    const deltaY = touch.clientY - start.y;
    if (!start.axis && Math.max(Math.abs(deltaX), Math.abs(deltaY)) >= 8) {
      start.axis = Math.abs(deltaX) > Math.abs(deltaY) ? "horizontal" : "vertical";
      if (start.axis === "horizontal") setSwipeDragging(true);
    }
    if (start.axis !== "horizontal") return;
    event.preventDefault();
    setSwipeX(Math.max(0, deltaX));
  };

  const handleSwipeEnd = (event: ReactTouchEvent<HTMLDivElement>) => {
    const start = swipeStart.current;
    const touch = event.changedTouches[0];
    swipeStart.current = null;
    if (!start || !touch || start.axis !== "horizontal") {
      setSwipeDragging(false);
      setSwipeX(0);
      return;
    }
    const direction = horizontalSwipeDirection(start, { x: touch.clientX, y: touch.clientY });
    if (direction === "right") {
      finishSwipe(historyVisible ? onCloseHistory : close);
    } else {
      finishSwipe();
    }
  };

  const openSource = (source: ChatSourceSnapshot) => {
    const note = notes.find((candidate) => candidate.id === source.noteId);
    if (note) {
      returningFromNote.current = true;
      onOpenNote(note.id);
    } else {
      setSnapshotOpen(source);
    }
  };

  const canChat = Boolean(cloudStatus?.configured);
  const savedCloudKeyApplies = Boolean(
    cloudStatus?.configured
    && cloudStatus.endpoint.replace(/\/+$/, "") === cloudEndpoint.trim().replace(/\/+$/, ""),
  );
  const unanswered = new Set(unansweredTurnIds(messages));
  const filteredHistory = device ? filterConversations(conversations, device, historyFilter, historyQuery) : [];
  const normalizedModelSearch = modelSearch.trim().toLowerCase();
  const filteredModels = normalizedModelSearch
    ? discoveredModels.filter((model) => `${model.name} ${model.id}`.toLowerCase().includes(normalizedModelSearch))
    : discoveredModels;
  const historyActionsConversation = conversations.find((conversation) => conversation.id === historyActionsId) ?? null;
  const viewportStyle: CSSProperties = {
    top: viewport.offsetTop,
    height: viewport.height,
    paddingBottom: viewport.keyboardOpen ? 0 : "env(safe-area-inset-bottom)",
  };

  return (
    <div
      className={cn("absolute inset-x-0 z-[75] flex-col overflow-hidden bg-[#1c1d1e]", visible ? "flex" : "hidden")}
      style={{
        ...viewportStyle,
        transform: `translate3d(${swipeX}px, 0, 0)`,
        transition: swipeDragging ? "none" : "transform 240ms cubic-bezier(0.22, 1, 0.36, 1)",
        willChange: swipeDragging || swipeSettling ? "transform" : undefined,
        touchAction: "pan-y",
      }}
      role={visible ? "dialog" : undefined}
      aria-modal={visible ? "true" : undefined}
      aria-label={visible ? "AI notes chat" : undefined}
      onTouchStart={handleSwipeStart}
      onTouchMove={handleSwipeMove}
      onTouchEnd={handleSwipeEnd}
      onTouchCancel={() => { swipeStart.current = null; finishSwipe(); }}
    >
      <header className="flex shrink-0 items-center gap-3 border-b border-white/[0.07] px-4 pb-3" style={{ paddingTop: "calc(env(safe-area-inset-top, 0px) + 0.75rem)" }}>
        <Button variant="ghost" size="icon" onClick={close} className="h-10 w-10 rounded-full bg-white/[0.08]" aria-label="Close AI chat"><ArrowLeft className="h-5 w-5" /></Button>
        <div className="min-w-0 flex-1">
          <h2 className="truncate text-[18px] font-semibold">{current?.title ?? "New chat"}</h2>
          <button type="button" onClick={() => setSettingsOpen(true)} className="flex max-w-full items-center gap-1.5 truncate text-xs text-[#8e8e93]" aria-label="Change chat model">
            <Cloud className="h-3 w-3 shrink-0 text-[#ef847d]" />
            <span className="truncate">{cloudStatus ? cloudEndpointLabel(cloudStatus.endpoint) : "Cloud"} · {cloudStatus?.model ?? "setup needed"}</span>
          </button>
        </div>
        <Button variant="ghost" size="icon" onClick={() => setOptionsOpen(true)} className="h-10 w-10 rounded-full bg-white/[0.08]" aria-label="Chat options"><MoreHorizontal className="h-5 w-5" /></Button>
      </header>

      {notice && <button type="button" onClick={() => setNotice(null)} className="shrink-0 bg-[#df5149]/15 px-4 py-2 text-left text-xs text-[#ef847d]">{notice} <span className="float-right">Dismiss</span></button>}
      {undoChanges.length > 0 && <div className="flex shrink-0 items-center gap-2 bg-[#df5149]/15 px-4 py-2 text-xs text-[#ef847d]">
        <span className="min-w-0 flex-1">AI updated {undoChanges.length} {undoChanges.length === 1 ? "note" : "notes"}.</span>
        <button type="button" className="font-semibold" onClick={() => {
          for (const change of undoChanges) {
            if (change.content === null) void trashNote(change.id);
            else updateNoteBody(change.id, noteBody(change.content));
          }
          setUndoChanges([]);
        }}>Undo</button>
        <button type="button" aria-label="Dismiss undo" onClick={() => setUndoChanges([])}><X className="h-3.5 w-3.5" /></button>
      </div>}

      {!canChat ? (
        <main className="flex min-h-0 flex-1 flex-col items-center justify-center px-7 text-center">
          <span className="flex h-16 w-16 items-center justify-center rounded-[20px] bg-[#df5149]/15 text-[#ef6b62]"><Cloud className="h-8 w-8" /></span>
          <h3 className="mt-5 text-[24px] font-bold">Cloud notes chat</h3>
          <p className="mt-2 max-w-xs text-sm leading-5 text-[#9b9893]">Connect OpenRouter or another OpenAI-compatible API. Matching note excerpts are sent with each question.</p>
          <Button onClick={() => setSettingsOpen(true)} className="mt-6 h-12 w-full max-w-xs rounded-[14px] bg-[#df5149] font-semibold text-white"><Settings2 className="mr-2 h-5 w-5" />Set up cloud chat</Button>
          {error && <p className="mt-4 max-w-xs rounded-[13px] bg-[#df5149]/10 px-4 py-3 text-sm leading-5 text-[#ef847d]">{error}</p>}
        </main>
      ) : (
        <>
          <main className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 py-5">
            {messages.length === 0 && <div className="mx-auto mt-12 max-w-xs text-center"><Sparkles className="mx-auto h-7 w-7 text-[#ef6b62]" /><p className="mt-3 text-[17px] font-semibold">Ask about your notes</p><p className="mt-1 text-sm leading-5 text-[#8e8e93]">This chat is saved with the vault after your first message.</p></div>}
            <div className="space-y-3">
              {messages.map((message) => (
                <div key={message.id} className={cn("max-w-[88%]", message.role === "user" && "ml-auto")}>
                  {message.role === "user" && message.attachments?.map((attachment) => (
                    <div key={attachment.id} className="mb-1 flex justify-end">
                      <PersistedChatImage attachment={attachment} />
                    </div>
                  ))}
                  <div className={cn("whitespace-pre-wrap rounded-[18px] px-4 py-3 text-[15px] leading-6", message.role === "user" ? "bg-[#df5149] text-white" : "bg-[#292a2b] text-[#f2efea]")}>{message.text}</div>
                  {message.role === "assistant" && message.sources && message.sources.length > 0 && <div className="mt-2 px-1"><p className="mb-1.5 text-[11px] font-medium text-[#77777d]">{message.contextKind === "similar" ? "Similar notes" : message.contextKind === "choices" ? "Choose a note" : message.contextKind === "matches" ? "Matching context" : "Recent context (no direct match)"}</p><div className="flex flex-wrap gap-1.5">{message.sources.map((source) => {
                    const note = notes.find((candidate) => candidate.id === source.noteId);
                    const changed = note ? chatContentRevision(note.content) !== source.revision : false;
                    const showType = message.contextKind === "similar" || message.contextKind === "choices";
                    return <button type="button" onClick={() => openSource(source)} key={`${message.id}-${source.noteId}`} title={note ? `Open ${source.title}` : `View saved excerpt from ${source.title}`} className="max-w-full truncate rounded-full border border-white/[0.08] bg-white/[0.045] px-2.5 py-1 text-[11px] text-[#aaa6a0]">{source.title}{showType ? ` · ${source.type}` : ""}{!note ? " · deleted" : changed ? " · changed" : ""}</button>;
                  })}</div></div>}
                  {message.role === "user" && unanswered.has(message.turnId) && !busy && notesReady && canEditCurrent && <button type="button" onClick={() => void retryTurn(message.turnId)} className="mt-1 flex items-center gap-1 text-xs text-[#ef847d]"><RotateCcw className="h-3 w-3" />Retry interrupted answer</button>}
                </div>
              ))}
              {busy && <div className="max-w-[90%] rounded-[18px] bg-[#292a2b] px-4 py-3 text-sm text-[#ddd9d4]">
                {streamingText ? <p className="whitespace-pre-wrap leading-6">{streamingText}</p> : <p className="flex items-center text-[#aaa6a0]"><Loader2 className="mr-2 h-4 w-4 animate-spin text-[#ef6b62]" />Searching notes…</p>}
                <button type="button" onClick={() => void stopCloudAI()} className="mt-2 flex items-center gap-1.5 text-xs font-semibold text-[#ef847d]"><Square className="h-3 w-3 fill-current" />Stop</button>
              </div>}
              {memoryBusy && <p className="flex items-center text-xs text-[#77777d]"><Brain className="mr-1.5 h-3.5 w-3.5" />Updating conversation memory…</p>}
              {error && <p className="rounded-[13px] bg-[#df5149]/10 px-4 py-3 text-sm leading-5 text-[#ef847d]">{error}</p>}
            </div>
          </main>
          {!canEditCurrent && current ? <div className="shrink-0 border-t border-white/[0.07] bg-[#202122] px-4 py-3 text-center"><p className="text-xs text-[#9b9893]">{current.deletedAt ? "This conversation is in Recently Deleted." : current.archivedAt ? "This conversation is archived." : `Read-only · owned by ${chatDeviceLabel(current.owner, deviceNames)}`}</p>{!isOwner && <Button onClick={() => void transferOwnership(current)} className="mt-2 h-10 rounded-full bg-[#df5149] px-5 text-sm text-white">Continue on this device</Button>}</div> : <form className="shrink-0 border-t border-white/[0.07] bg-[#202122]/95 p-3 backdrop-blur-xl" onSubmit={(event) => { event.preventDefault(); void send(); }}>
            {!notesReady && <div className="mb-2 flex items-center justify-center text-xs text-[#aaa6a0]" aria-live="polite">{notesPreparationError ? <><span>{notesPreparationError}</span><button type="button" onClick={onRetryNotesPreparation} className="ml-2 font-semibold text-[#ef847d]">Retry</button></> : <><Loader2 className="mr-2 h-4 w-4 animate-spin text-[#ef6b62]" />Preparing all notes for search…</>}</div>}
            {speechState !== "idle" && <div className="mb-2 flex items-center justify-center gap-2 text-xs font-medium text-[#ef847d]"><span className={cn("h-2 w-2 rounded-full bg-[#ef6b62]", speechState === "listening" && "animate-pulse")} />{speechState === "starting" ? "Preparing on-device dictation…" : speechState === "stopping" ? "Finishing transcript…" : `Live transcription · ${speechEngine === "speechAnalyzer" ? "SpeechAnalyzer" : "legacy engine"}${speechBuild ? ` · build ${speechBuild}` : ""}`}</div>}
            {pendingImages.length > 0 && <div className="mb-2 flex gap-2 overflow-x-auto pb-1">
              {pendingImages.map((image, index) => <div key={image.previewUrl} className="relative shrink-0">
                <img src={image.previewUrl} alt={`Selected attachment ${index + 1}`} width={image.width} height={image.height} className="h-20 w-20 rounded-lg object-cover" />
                <button type="button" onClick={() => {
                  URL.revokeObjectURL(image.previewUrl);
                  const next = pendingImagesRef.current.filter((candidate) => candidate !== image);
                  pendingImagesRef.current = next;
                  setPendingImages(next);
                }} className="absolute -right-1 -top-1 flex h-7 w-7 items-center justify-center rounded-full bg-[#3b3c3d] text-[#c4c0bb]" aria-label={`Remove image ${index + 1}`}><X className="h-4 w-4" /></button>
              </div>)}
            </div>}
            <div className="flex min-w-0 items-end gap-2 rounded-[24px] border border-white/[0.11] bg-[#2b2c2d] p-1.5 pl-1 focus-within:border-[#df5149]/65">
              <input ref={imageInput} type="file" accept="image/*" multiple className="hidden" onChange={(event) => { void selectImages(Array.from(event.target.files ?? [])); event.currentTarget.value = ""; }} />
              <button type="button" onClick={() => imageInput.current?.click()} disabled={busy || memoryBusy || preparingImage || pendingImages.length >= 4 || speechState !== "idle"} className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-white/[0.08] text-[#c4c0bb] disabled:opacity-50" aria-label="Add images" title="Add images">{preparingImage ? <Loader2 className="h-[17px] w-[17px] animate-spin" /> : <ImagePlus className="h-[18px] w-[18px]" />}</button>
              <textarea value={draft} onChange={(event) => setDraft(event.target.value)} rows={1} enterKeyHint="send" placeholder={speechState === "listening" ? "Listening…" : pendingImages.length ? "Ask about these images" : "Ask about your notes"} className="max-h-28 min-h-9 min-w-0 flex-1 resize-none bg-transparent px-2 py-1.5 text-[16px] leading-6 text-white outline-none placeholder:text-[#77777d]" />
              <button type="button" onClick={() => void toggleSpeech()} disabled={busy || memoryBusy || speechState === "starting" || speechState === "stopping"} aria-label={speechState === "listening" ? "Stop dictation" : "Dictate message"} className={cn("flex h-9 w-9 shrink-0 items-center justify-center rounded-full disabled:opacity-50", speechState === "listening" ? "bg-[#df5149] text-white" : "bg-white/[0.08] text-[#c4c0bb]")}>{speechState === "starting" || speechState === "stopping" ? <Loader2 className="h-[17px] w-[17px] animate-spin" /> : speechState === "listening" ? <Square className="h-3.5 w-3.5 fill-current" /> : <Mic className="h-[18px] w-[18px]" />}</button>
              <button type="submit" disabled={(!draft.trim() && !pendingImages.length) || !notesReady || busy || memoryBusy || preparingImage || speechState !== "idle"} className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[#df5149] text-white disabled:bg-white/[0.09] disabled:text-[#77777d]" aria-label="Send message"><Send className="h-[18px] w-[18px]" /></button>
            </div>
          </form>}
        </>
      )}

      {optionsOpen && <div className="absolute inset-0 z-20 flex items-end bg-black/55" onClick={() => setOptionsOpen(false)}><div className="w-full rounded-t-[26px] bg-[#292a2b] px-4 pb-[calc(env(safe-area-inset-bottom)+1rem)] pt-3" onClick={(event) => event.stopPropagation()}><div className="mx-auto mb-3 h-1 w-10 rounded-full bg-white/20" /><button type="button" onClick={startNewChat} className="flex w-full items-center gap-3 border-b border-white/[0.07] px-2 py-3.5 text-left"><Plus className="h-5 w-5 text-[#ef6b62]" />New chat</button><button type="button" onClick={() => { setOptionsOpen(false); onOpenHistory(); }} className="flex w-full items-center gap-3 border-b border-white/[0.07] px-2 py-3.5 text-left"><History className="h-5 w-5 text-[#ef6b62]" />Conversation history</button><button type="button" onClick={() => { setOptionsOpen(false); setSettingsOpen(true); }} className="flex w-full items-center gap-3 border-b border-white/[0.07] px-2 py-3.5 text-left"><Settings2 className="h-5 w-5 text-[#ef6b62]" />Chat model</button>{current?.summary && <button type="button" onClick={() => { setOptionsOpen(false); setMemoryOpen(true); }} className="flex w-full items-center gap-3 border-b border-white/[0.07] px-2 py-3.5 text-left"><Brain className="h-5 w-5 text-[#ef6b62]" />Conversation memory</button>}{current && !isOwner && <button type="button" onClick={() => void transferOwnership(current)} className="flex w-full items-center gap-3 px-2 py-3.5 text-left text-[#ef847d]"><RotateCcw className="h-5 w-5" />Continue on this device</button>}{current && isOwner && <><button type="button" onClick={() => void renameCurrent()} className="flex w-full items-center gap-3 border-b border-white/[0.07] px-2 py-3.5 text-left">Rename</button>{current.archivedAt || current.deletedAt ? <button type="button" onClick={() => void mutateCurrent("restore")} className="flex w-full items-center gap-3 border-b border-white/[0.07] px-2 py-3.5 text-left"><RotateCcw className="h-5 w-5" />Restore</button> : <button type="button" onClick={() => void mutateCurrent("archive")} className="flex w-full items-center gap-3 border-b border-white/[0.07] px-2 py-3.5 text-left"><Archive className="h-5 w-5" />Archive</button>}{!current.deletedAt && <button type="button" onClick={() => void mutateCurrent("delete")} className="flex w-full items-center gap-3 px-2 py-3.5 text-left text-[#ef847d]"><Trash2 className="h-5 w-5" />Delete</button>}</>}</div></div>}

      {settingsOpen && <div className="absolute inset-0 z-40 flex flex-col bg-[#1c1d1e]" role="dialog" aria-modal="true" aria-label="Chat model settings">
        <header className="flex shrink-0 items-center gap-3 border-b border-white/[0.07] px-4 pb-3" style={{ paddingTop: "calc(env(safe-area-inset-top, 0px) + 0.75rem)" }}>
          <Button variant="ghost" size="icon" onClick={() => setSettingsOpen(false)} className="h-10 w-10 rounded-full bg-white/[0.08]" aria-label="Back to chat"><ArrowLeft className="h-5 w-5" /></Button>
          <h2 className="text-[20px] font-semibold">Chat model</h2>
        </header>
        <main className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pb-[calc(env(safe-area-inset-bottom)+1.5rem)] pt-5">
          <div className="mx-auto max-w-lg space-y-5">
            <p className="text-xs leading-5 text-[#9b9893]">Questions and matching note excerpts are sent to the selected provider. Credentials stay in the iOS Keychain and are never written to your vault.</p>

            <div className="grid grid-cols-2 rounded-xl bg-[#292a2b] p-1" aria-label="AI provider">
              {(["openrouter", "compatible"] as MobileCloudProvider[]).map((provider) => <button key={provider} type="button" onClick={() => void selectMobileProvider(provider)} className={cn("min-h-10 rounded-lg px-3 text-sm font-semibold", mobileProvider === provider ? "bg-[#df5149] text-white" : "text-[#aaa6a0]")}>{provider === "openrouter" ? "OpenRouter" : "OpenAI-compatible"}</button>)}
            </div>

            {mobileProvider === "openrouter" ? <div className="space-y-3">
              <div className="rounded-xl bg-[#292a2b] px-4 py-3"><p className="text-sm font-medium">OpenRouter account</p><p className="mt-1 text-xs text-[#8e8e93]">{savedCloudKeyApplies ? "Connected securely with a credential stored in Keychain." : "Sign in securely in your browser. Zerus never writes this credential to the vault."}</p></div>
              <Button onClick={() => void signInWithOpenRouter()} disabled={busy} className="h-12 w-full rounded-xl bg-[#df5149] font-semibold text-white">
                {busy ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Cloud className="mr-2 h-4 w-4" />}
                {savedCloudKeyApplies ? "Reconnect OpenRouter" : "Connect OpenRouter"}
              </Button>
            </div> : <>
              <label className="block"><span className="mb-1.5 block text-xs font-medium text-[#c4c0bb]">API endpoint</span><Input value={cloudEndpoint} onChange={(event) => setCloudEndpoint(event.target.value)} inputMode="url" autoCapitalize="none" autoCorrect="off" className="h-12 rounded-xl border-white/[0.09] bg-[#202122] text-base" placeholder="https://api.example.com/v1" /></label>
              {savedCloudKeyApplies && !editingAPIKey ? <div className="flex items-center gap-3 rounded-xl bg-[#292a2b] px-4 py-3"><div className="min-w-0 flex-1"><p className="text-sm font-medium">API key stored securely</p><p className="mt-0.5 text-xs text-[#8e8e93]">The key is hidden and remains in Keychain.</p></div><Button type="button" variant="outline" onClick={() => setEditingAPIKey(true)} className="h-9 shrink-0 rounded-lg border-white/[0.1] bg-white/[0.04]">Change API key</Button></div> : <label className="block"><span className="mb-1.5 block text-xs font-medium text-[#c4c0bb]">API key</span><Input type="password" value={cloudAPIKey} onChange={(event) => setCloudAPIKey(event.target.value)} autoCapitalize="none" autoCorrect="off" autoComplete="new-password" className="h-12 rounded-xl border-white/[0.09] bg-[#202122] text-base" placeholder="Enter API key" /></label>}
            </>}

            <label className="block"><span className="mb-1.5 block text-xs font-medium text-[#c4c0bb]">Model ID</span><Input value={cloudModel} onChange={(event) => setCloudModel(event.target.value)} autoCapitalize="none" autoCorrect="off" className="h-12 rounded-xl border-white/[0.09] bg-[#202122] text-base" placeholder={mobileProvider === "openrouter" ? "openai/gpt-5.4-mini" : "Model ID"} /></label>
            <div>
              <div className="mb-2 flex items-center justify-between gap-2"><span className="text-xs font-medium text-[#c4c0bb]">Favourite models</span><button type="button" onClick={() => setFavoriteModels((current) => current.includes(cloudModel.trim()) ? current : [...current, cloudModel.trim()].filter(Boolean))} className="text-xs font-semibold text-[#ef847d]">Save current</button></div>
              <div className="flex flex-wrap gap-2">{favoriteModels.length ? favoriteModels.map((model) => <button key={model} type="button" onClick={() => setCloudModel(model)} className={cn("max-w-full truncate rounded-full border px-3 py-1.5 text-xs", model === cloudModel ? "border-[#df5149] bg-[#df5149]/15 text-[#ef847d]" : "border-white/[0.09] bg-white/[0.05] text-[#aaa6a0]")}>{model}</button>) : <p className="text-xs text-[#77777d]">Save models here for quick switching.</p>}</div>
            </div>

            <Button type="button" variant="outline" onClick={() => void discoverModels()} disabled={busy || !cloudEndpoint.trim() || (!savedCloudKeyApplies && !cloudAPIKey.trim())} className="h-12 w-full rounded-xl border-white/[0.1] bg-white/[0.04]">{busy && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}Test connection & discover models</Button>
            {discoveredModels.length > 0 && <div className="space-y-2">
              <div className="relative"><Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[#77777d]" /><Input value={modelSearch} onChange={(event) => setModelSearch(event.target.value)} enterKeyHint="search" autoCapitalize="none" autoCorrect="off" placeholder="Search models" className="h-12 rounded-xl border-white/[0.09] bg-[#202122] pl-9 text-base" /></div>
              <div className="max-h-72 space-y-1 overflow-y-auto rounded-xl bg-[#202122] p-2">{filteredModels.length ? filteredModels.map((model) => <button key={model.id} type="button" onClick={() => { setCloudModel(model.id); setFavoriteModels((current) => current.includes(model.id) ? current : [...current, model.id]); }} className="block w-full rounded-lg px-2 py-2 text-left text-xs active:bg-white/[0.07]"><span className="block truncate font-medium text-[#ddd9d4]">{model.name}</span><span className="block truncate text-[11px] text-[#77777d]">{model.id}</span></button>) : <p className="px-2 py-5 text-center text-xs text-[#77777d]">No models match “{modelSearch}”.</p>}</div>
            </div>}
            {error && <p className="rounded-xl bg-[#df5149]/10 px-3 py-2.5 text-xs leading-5 text-[#ef847d]">{error}</p>}
            <Button onClick={() => void saveCloudSettings()} disabled={busy || !cloudEndpoint.trim() || !cloudModel.trim() || (!savedCloudKeyApplies && !cloudAPIKey.trim())} className="h-12 w-full rounded-xl bg-[#df5149] font-semibold text-white">{busy && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}Save {mobileProvider === "openrouter" ? "OpenRouter" : "compatible"} model</Button>
          </div>
        </main>
      </div>}

      {historyVisible && device && <div className="absolute inset-0 z-30 flex flex-col bg-[#1c1d1e]"><header className="flex items-center gap-3 border-b border-white/[0.07] px-4 pb-3 pt-[calc(env(safe-area-inset-top)+0.75rem)]"><Button variant="ghost" size="icon" onClick={onCloseHistory} className="rounded-full bg-white/[0.08]" aria-label="Back to chat"><ArrowLeft className="h-5 w-5" /></Button><h2 className="flex-1 text-[20px] font-semibold">Conversation history</h2><Button variant="ghost" size="icon" onClick={() => { startNewChat(); onCloseHistory(); }} className="rounded-full bg-[#df5149] text-white"><Plus className="h-5 w-5" /></Button></header><div className="px-4 pt-4"><div className="relative"><Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-[#77777d]" /><Input value={historyQuery} onChange={(event) => setHistoryQuery(event.target.value)} placeholder="Search conversations" className="h-11 rounded-xl border-white/[0.08] bg-[#292a2b] pl-9" /></div><div className="mt-3 flex gap-2 overflow-x-auto pb-2">{(["all", "device", "other", "archived", "deleted"] as HistoryFilter[]).map((filter) => <button type="button" key={filter} onClick={() => setHistoryFilter(filter)} className={cn("whitespace-nowrap rounded-full px-3 py-1.5 text-xs", historyFilter === filter ? "bg-[#df5149] text-white" : "bg-white/[0.07] text-[#aaa6a0]")}>{filter === "all" ? "All" : filter === "device" ? "This device" : filter === "other" ? "Other devices" : filter === "archived" ? "Archived" : "Recently Deleted"}</button>)}</div></div><main className="min-h-0 flex-1 overflow-y-auto px-4 py-3">{historyLoading && filteredHistory.length === 0 ? <Loader2 className="mx-auto mt-12 h-6 w-6 animate-spin text-[#ef6b62]" /> : filteredHistory.length === 0 ? <p className="mt-12 text-center text-sm text-[#77777d]">No conversations found.</p> : <div className="overflow-hidden rounded-[16px] bg-[#252627]">{filteredHistory.map((conversation) => <HistoryConversationRow key={conversation.id} conversation={conversation} device={device} deviceNames={deviceNames} onOpen={() => { setConversationId(conversation.id); setBlankChat(false); onCloseHistory(); }} onActions={() => setHistoryActionsId(conversation.id)} />)}</div>}</main></div>}

      {historyActionsConversation && device && <div className="absolute inset-0 z-40 flex items-end bg-black/60" onClick={() => setHistoryActionsId(null)} role="dialog" aria-modal="true" aria-label={`Actions for ${historyActionsConversation.title}`}><div className="w-full select-none rounded-t-[26px] bg-[#292a2b] px-4 pb-[calc(env(safe-area-inset-bottom)+1rem)] pt-3" onClick={(event) => event.stopPropagation()}><div className="mx-auto mb-3 h-1 w-10 rounded-full bg-white/20" /><p className="truncate border-b border-white/[0.07] px-2 pb-3 text-sm font-semibold text-[#d4d0ca]">{historyActionsConversation.title}</p>{historyActionsConversation.owner.id !== device.id ? <button type="button" onClick={() => void transferOwnership(historyActionsConversation)} className="flex w-full items-center gap-3 px-2 py-3.5 text-left text-[#ef847d]"><RotateCcw className="h-5 w-5" />Continue on this device</button> : <><button type="button" onClick={() => void renameConversation(historyActionsConversation)} className="flex w-full items-center gap-3 border-b border-white/[0.07] px-2 py-3.5 text-left">Rename</button>{historyActionsConversation.archivedAt || historyActionsConversation.deletedAt ? <button type="button" onClick={() => void mutateConversation(historyActionsConversation, "restore")} className="flex w-full items-center gap-3 border-b border-white/[0.07] px-2 py-3.5 text-left"><RotateCcw className="h-5 w-5" />Restore</button> : <button type="button" onClick={() => void mutateConversation(historyActionsConversation, "archive")} className="flex w-full items-center gap-3 border-b border-white/[0.07] px-2 py-3.5 text-left"><Archive className="h-5 w-5" />Archive</button>}{!historyActionsConversation.deletedAt && <button type="button" onClick={() => void mutateConversation(historyActionsConversation, "delete")} className="flex w-full items-center gap-3 px-2 py-3.5 text-left text-[#ef847d]"><Trash2 className="h-5 w-5" />Delete</button>}</>}</div></div>}

      {memoryOpen && current?.summary && <div className="absolute inset-0 z-40 flex items-end bg-black/60" onClick={() => setMemoryOpen(false)}><div className="max-h-[75%] w-full overflow-y-auto rounded-t-[26px] bg-[#292a2b] p-5 pb-[calc(env(safe-area-inset-bottom)+1rem)]" onClick={(event) => event.stopPropagation()}><div className="flex items-center justify-between"><h2 className="flex items-center gap-2 text-lg font-semibold"><Brain className="h-5 w-5 text-[#ef6b62]" />Conversation memory</h2><Button variant="ghost" size="icon" onClick={() => setMemoryOpen(false)}><X className="h-5 w-5" /></Button></div><p className="mt-4 whitespace-pre-wrap text-sm leading-6 text-[#d4d0ca]">{current.summary.text}</p><p className="mt-4 text-xs text-[#77777d]">Covers {current.summary.coveredMessageIds.length} messages.</p>{isOwner && <Button variant="ghost" onClick={() => void resetMemory()} className="mt-3 text-[#ef847d]">Reset memory</Button>}</div></div>}

      {snapshotOpen && <div className="absolute inset-0 z-40 flex items-end bg-black/60" onClick={() => setSnapshotOpen(null)}><div className="max-h-[78%] w-full overflow-y-auto rounded-t-[26px] bg-[#292a2b] p-5 pb-[calc(env(safe-area-inset-bottom)+1rem)]" onClick={(event) => event.stopPropagation()}><div className="flex items-center justify-between"><div><p className="text-xs text-[#ef847d]">Saved source snapshot</p><h2 className="mt-1 text-lg font-semibold">{snapshotOpen.title}</h2></div><Button variant="ghost" size="icon" onClick={() => setSnapshotOpen(null)}><X className="h-5 w-5" /></Button></div><p className="mt-4 whitespace-pre-wrap rounded-xl bg-black/15 p-4 text-sm leading-6 text-[#d4d0ca]">{snapshotOpen.excerpt}</p></div></div>}
    </div>
  );
}
