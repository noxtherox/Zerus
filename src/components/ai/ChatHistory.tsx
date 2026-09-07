import { useState } from "react";
import type { ChatConversation, ChatDevice } from "@/lib/mobile-chat-history";
import {
  renameChat,
  setChatLifecycle,
  transferChatOwnership,
} from "@/lib/mobile-chat-history";
import { getVaultBackend } from "@/store/notes-store";
import { showError } from "@/utils/toast";

export function ChatHistory({
  chats,
  device,
  onSelect,
  onRefresh,
  onClose,
  onNew,
}: {
  chats: ChatConversation[];
  device: ChatDevice | null;
  onSelect: (chat: ChatConversation) => void;
  onRefresh: () => Promise<void>;
  onClose: () => void;
  onNew: () => void;
}) {
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState("all");
  const [busy, setBusy] = useState(false);
  const [renameId, setRenameId] = useState<string | null>(null);
  const [title, setTitle] = useState("");
  const filtered = chats.filter((chat) => {
    if (
      filter === "deleted"
        ? !chat.deletedAt
        : filter === "archived"
          ? !chat.archivedAt || chat.deletedAt
          : chat.archivedAt ||
            chat.deletedAt ||
            (filter === "device" && chat.owner.id !== device?.id) ||
            (filter === "other" && chat.owner.id === device?.id)
    )
      return false;
    return `${chat.title} ${chat.messages.map((message) => message.text).join(" ")}`
      .toLowerCase()
      .includes(query.toLowerCase());
  });
  const mutate = async (
    chat: ChatConversation,
    kind: "rename" | "archive" | "restore" | "delete" | "move",
  ) => {
    const backend = getVaultBackend();
    if (!backend || !device || busy) return;
    setBusy(true);
    try {
      if (kind === "move") await transferChatOwnership(backend, chat, device);
      else if (kind === "rename") {
        if (!title.trim()) return;
        await renameChat(backend, chat, device, title);
        setRenameId(null);
      } else await setChatLifecycle(backend, chat, device, kind);
      await onRefresh();
    } catch (error) {
      showError(String(error));
    } finally {
      setBusy(false);
    }
  };
  return (
    <section
      className="absolute inset-0 z-30 flex flex-col bg-zerus-editor"
      aria-label="Conversation history"
    >
      <header className="flex items-center justify-between border-b p-3">
        <h2 className="text-sm font-semibold">Chat history</h2>
        <div className="flex gap-2">
          <button className="rounded border px-2 py-1 text-xs" onClick={onNew}>
            New chat
          </button>
          <button
            className="rounded border px-2 py-1 text-xs"
            onClick={onClose}
          >
            Back
          </button>
        </div>
      </header>
      <div className="space-y-2 border-b p-3">
        <input
          aria-label="Search chat history"
          placeholder="Search titles and messages…"
          className="w-full rounded-md border bg-background p-2 text-sm"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
        <select
          aria-label="Filter chat history"
          className="w-full rounded-md border bg-background p-2 text-sm"
          value={filter}
          onChange={(event) => setFilter(event.target.value)}
        >
          {[
            ["all", "All chats"],
            ["device", "This device"],
            ["other", "Other devices"],
            ["archived", "Archived"],
            ["deleted", "Recently deleted"],
          ].map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto p-3">
        {filtered.length === 0 && (
          <p className="py-8 text-center text-sm text-muted-foreground">
            {query
              ? "No conversations match your search."
              : "No conversations here yet."}
          </p>
        )}
        {filtered.map((chat) => (
          <article key={chat.id} className="mb-3 rounded-lg border p-3">
            <button className="w-full text-left" onClick={() => onSelect(chat)}>
              <p className="truncate text-sm font-medium">{chat.title}</p>
              <p className="mt-1 text-xs text-muted-foreground">
                {chat.owner.name} · {chat.messages.length} messages ·{" "}
                {new Date(chat.updatedAt).toLocaleDateString()}
              </p>
            </button>
            {renameId === chat.id ? (
              <form
                className="mt-2 flex gap-2"
                onSubmit={(event) => {
                  event.preventDefault();
                  void mutate(chat, "rename");
                }}
              >
                <input
                  autoFocus
                  aria-label="Conversation title"
                  className="min-w-0 flex-1 rounded border bg-background p-1 text-sm"
                  value={title}
                  onChange={(event) => setTitle(event.target.value)}
                />
                <button disabled={busy || !title.trim()} type="submit">
                  Save
                </button>
                <button type="button" onClick={() => setRenameId(null)}>
                  Cancel
                </button>
              </form>
            ) : (
              <div className="mt-2 flex flex-wrap gap-3 text-xs text-muted-foreground">
                {chat.owner.id === device?.id ? (
                  <>
                    <button
                      disabled={busy}
                      onClick={() => {
                        setRenameId(chat.id);
                        setTitle(chat.title);
                      }}
                    >
                      Rename
                    </button>
                    <button
                      disabled={busy}
                      onClick={() =>
                        void mutate(
                          chat,
                          chat.archivedAt || chat.deletedAt
                            ? "restore"
                            : "archive",
                        )
                      }
                    >
                      {chat.archivedAt || chat.deletedAt
                        ? "Restore"
                        : "Archive"}
                    </button>
                    {!chat.deletedAt && (
                      <button
                        disabled={busy}
                        onClick={() => void mutate(chat, "delete")}
                      >
                        Delete
                      </button>
                    )}
                  </>
                ) : (
                  <button
                    disabled={busy}
                    onClick={() => void mutate(chat, "move")}
                  >
                    Continue on this device
                  </button>
                )}
              </div>
            )}
          </article>
        ))}
      </div>
      {filter === "deleted" && (
        <p className="border-t p-3 text-xs text-muted-foreground">
          Deleted chats can be restored for 30 days.
        </p>
      )}
    </section>
  );
}
