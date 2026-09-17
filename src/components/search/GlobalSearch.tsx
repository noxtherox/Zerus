import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import {
  Search,
  Sparkles,
  FileText,
  CheckSquare,
  Link2,
  Files,
  Loader2,
} from "@/lib/icons";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { getVaultBackend, loadAllNotes, useVault } from "@/store/notes-store";
import { useTasks } from "@/store/tasks-store";
import {
  loadChatConversations,
  type ChatConversation,
} from "@/lib/mobile-chat-history";
import {
  buildSearchItems,
  COLLECTION_LABELS,
  EMPTY_SEARCH_FILTERS,
  filterSearchItems,
  recentSearchItems,
  recordSearchVisit,
  searchChatRequest,
  searchExcerpt,
  searchPreviewText,
  type SearchChatRequest,
  type SearchFilters,
  type SearchItem,
} from "@/lib/global-search";
import { cn } from "@/lib/utils";

export function GlobalSearchButton({
  compact = false,
  className = "",
}: {
  compact?: boolean;
  className?: string;
}) {
  return (
    <button
      type="button"
      aria-label="Search everything"
      title="Search everything (⌘F / Ctrl+F)"
      onClick={() => window.dispatchEvent(new Event("zerus:global-search"))}
      className={cn(
        "flex items-center gap-2 rounded-md px-3 py-2 text-sm text-muted-foreground hover:bg-muted hover:text-foreground",
        className,
      )}
    >
      <Search size={16} />
      {!compact && (
        <>
          <span className="min-w-0 flex-1 truncate text-left">
            Search everything
          </span>
          <kbd className="text-[10px] opacity-60">⌘F</kbd>
        </>
      )}
    </button>
  );
}
function Highlight({ text, query }: { text: string; query: string }) {
  const tokens = query
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((token) => token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  if (!tokens.length) return <>{text}</>;
  const pattern = new RegExp(`(${tokens.join("|")})`, "gi");
  return (
    <>
      {text.split(pattern).map((part, index) =>
        index % 2 ? (
          <mark
            key={index}
            className="bg-transparent font-medium text-zerus-accent"
          >
            {part}
          </mark>
        ) : (
          part
        ),
      )}
    </>
  );
}
function ItemIcon({ item }: { item: SearchItem }) {
  const Icon =
    item.collection === "tasks"
      ? CheckSquare
      : item.collection === "chats"
        ? Sparkles
        : item.collection === "links"
          ? Link2
          : item.collection === "files"
            ? Files
            : FileText;
  return <Icon size={18} className="mt-0.5 shrink-0 text-muted-foreground" />;
}
export function GlobalSearch({
  onOpenItem,
  onAskAI,
  mobile = false,
}: {
  onOpenItem: (item: SearchItem) => void;
  onAskAI: (request: SearchChatRequest) => void;
  mobile?: boolean;
}) {
  const vault = useVault();
  const tasks = useTasks();
  const [open, setOpen] = useState(false);
  const [recentKeys, setRecentKeys] = useState<string[]>([]);
  const [query, setQuery] = useState("");
  const [viewport, setViewport] = useState({
    height: window.visualViewport?.height ?? window.innerHeight,
    top: 0,
    narrow: window.innerWidth < 640,
  });
  const [filters, setFilters] = useState<SearchFilters>({
    ...EMPTY_SEARCH_FILTERS,
  });
  const [advanced, setAdvanced] = useState(false);
  const [chats, setChats] = useState<ChatConversation[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const [limit, setLimit] = useState(80);
  const input = useRef<HTMLInputElement>(null);
  const hover = useRef<ReturnType<typeof setTimeout> | null>(null);
  const deferredQuery = useDeferredValue(query);
  const items = useMemo(
    () => open ? buildSearchItems(vault.notes, tasks, chats) : [],
    [open, vault.notes, tasks, chats],
  );
  const results = useMemo(() => {
    const matches = filterSearchItems(items, deferredQuery, filters);
    if (
      deferredQuery.trim() ||
      JSON.stringify(filters) !== JSON.stringify(EMPTY_SEARCH_FILTERS)
    )
      return matches;
    const recent = recentKeys;
    return matches
      .filter((item) => recent.includes(item.key))
      .sort((a, b) => recent.indexOf(a.key) - recent.indexOf(b.key));
  }, [items, deferredQuery, filters, recentKeys]);
  const displayed = results.slice(0, limit);
  const selected =
    displayed.find((item) => item.key === selectedKey) ?? displayed[0];
  const blank =
    !query.trim() &&
    JSON.stringify(filters) === JSON.stringify(EMPTY_SEARCH_FILTERS);
  const types = [
    ...new Set(
      items
        .filter((item) => item.note && item.collection === filters.collection)
        .map((item) => item.location),
    ),
  ].sort();
  const properties = [
    ...new Set(
      items
        .filter((item) => item.collection === filters.collection)
        .flatMap((item) => Object.keys(item.properties)),
    ),
  ]
    .filter((key) => !key.startsWith("zerus-"))
    .sort();
  const patch = (value: Partial<SearchFilters>) =>
    setFilters((current) => ({ ...current, ...value }));
  const cancelHover = () => {
    if (hover.current) clearTimeout(hover.current);
  };
  const openItem = (item: SearchItem) => {
    recordSearchVisit(vault.location, item.key);
    setOpen(false);
    onOpenItem(item);
  };
  useEffect(() => {
    const show = () => {
      if (vault.status === "ready") setOpen(true);
    };
    const key = (event: KeyboardEvent) => {
      if (
        (event.metaKey || event.ctrlKey) &&
        !event.shiftKey &&
        !event.altKey &&
        event.key.toLowerCase() === "f" &&
        vault.status === "ready"
      ) {
        event.preventDefault();
        event.stopImmediatePropagation();
        setOpen(true);
        input.current?.focus();
        input.current?.select();
      }
    };
    window.addEventListener("zerus:global-search", show);
    window.addEventListener("keydown", key, true);
    return () => {
      window.removeEventListener("zerus:global-search", show);
      window.removeEventListener("keydown", key, true);
    };
  }, [vault.status]);
  useEffect(() => {
    if (!open) return;
    const sync = () =>
      setViewport({
        height: window.visualViewport?.height ?? window.innerHeight,
        top: window.visualViewport?.offsetTop ?? 0,
        narrow: window.innerWidth < 640,
      });
    sync();
    window.visualViewport?.addEventListener("resize", sync);
    window.visualViewport?.addEventListener("scroll", sync);
    window.addEventListener("resize", sync);
    return () => {
      window.visualViewport?.removeEventListener("resize", sync);
      window.visualViewport?.removeEventListener("scroll", sync);
      window.removeEventListener("resize", sync);
    };
  }, [open]);
  useEffect(() => {
    setQuery("");
    setFilters({ ...EMPTY_SEARCH_FILTERS });
    setChats([]);
    setOpen(false);
  }, [vault.location]);
  useEffect(() => {
    setLimit(80);
    setSelectedKey(null);
    cancelHover();
  }, [deferredQuery, filters]);
  useEffect(() => {
    if (!open) return;
    let active = true;
    setRecentKeys(recentSearchItems(vault.location));
    setLoading(true);
    setError("");
    const backend = getVaultBackend();
    void Promise.allSettled([
      loadAllNotes(),
      backend ? loadChatConversations(backend) : Promise.resolve([]),
    ]).then(([notes, history]) => {
      if (!active) return;
      if (history.status === "fulfilled") setChats(history.value);
      if (
        notes.status === "rejected" ||
        (notes.status === "fulfilled" && !notes.value) ||
        history.status === "rejected"
      )
        setError(
          "Some items could not be loaded. Close and reopen search to retry.",
        );
      setLoading(false);
    });
    return () => {
      active = false;
      cancelHover();
    };
  }, [open, vault.location]);
  const activeKey = selected?.key;
  useEffect(() => {
    if (open && activeKey)
      document
        .getElementById(`global-result-${activeKey}`)
        ?.scrollIntoView({ block: "nearest" });
  }, [activeKey, open]);
  const selectClass =
    "max-w-full rounded-md border border-border/60 bg-background px-2 py-1.5 text-xs text-muted-foreground focus:outline-none focus:ring-1 focus:ring-zerus-accent";
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent
        style={
          viewport.narrow
            ? { height: viewport.height, top: viewport.top }
            : undefined
        }
        aria-describedby={undefined}
        className={cn(
          "flex h-[min(740px,85dvh)] max-w-[1100px] flex-col gap-0 overflow-hidden rounded-2xl border-border/70 bg-zerus-editor p-0 shadow-2xl max-sm:left-0 max-sm:top-0 max-sm:h-[100dvh] max-sm:max-h-none max-sm:w-full max-sm:translate-x-0 max-sm:translate-y-0 max-sm:rounded-none max-sm:pt-[env(safe-area-inset-top)] max-sm:pb-[env(safe-area-inset-bottom)] max-sm:[&>button]:top-[calc(env(safe-area-inset-top)+1rem)]",
          mobile && "h-[100dvh] max-h-none max-w-none rounded-none",
        )}
        onOpenAutoFocus={(event) => {
          event.preventDefault();
          input.current?.focus();
          input.current?.select();
        }}
      >
        <DialogTitle className="sr-only">Search everything</DialogTitle>
        <div className="flex items-center gap-3 px-5 pb-3 pt-5 pr-12">
          <Search size={21} className="shrink-0 text-muted-foreground" />
          <input
            ref={input}
            aria-label="Search everything"
            role="combobox"
            aria-autocomplete="list"
            aria-expanded="true"
            aria-controls="global-search-results"
            aria-activedescendant={
              selected ? `global-result-${selected.key}` : undefined
            }
            autoComplete="off"
            placeholder="Search everything…"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            className="min-w-0 flex-1 bg-transparent text-base outline-none placeholder:text-muted-foreground"
            onKeyDown={(event) => {
              if (event.nativeEvent.isComposing) return;
              if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                event.preventDefault();
                cancelHover();
                const index = displayed.findIndex(
                  (item) => item.key === selected?.key,
                );
                setSelectedKey(
                  displayed[
                    Math.max(
                      0,
                      Math.min(
                        displayed.length - 1,
                        index + (event.key === "ArrowDown" ? 1 : -1),
                      ),
                    )
                  ]?.key ?? null,
                );
              }
              if (event.key === "Enter" && selected) {
                event.preventDefault();
                openItem(selected);
              }
            }}
          />
        </div>
        <div className="flex flex-wrap items-center gap-2 px-5 pb-4">
          <select
            aria-label="Collection"
            className={selectClass}
            value={filters.collection}
            onChange={(event) =>
              setFilters((current) => ({
                ...EMPTY_SEARCH_FILTERS,
                days: current.days,
                archived: current.archived,
                collection: event.target.value as SearchFilters["collection"],
              }))
            }
          >
            {Object.entries(COLLECTION_LABELS).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </select>
          <select
            aria-label="Last modified"
            className={selectClass}
            value={filters.days}
            onChange={(event) => patch({ days: event.target.value })}
          >
            <option value="">Any time</option>
            <option value="1">Last 24 hours</option>
            <option value="7">Last 7 days</option>
            <option value="30">Last 30 days</option>
          </select>
          <button
            className={selectClass}
            onClick={() => setAdvanced((value) => !value)}
            aria-expanded={advanced}
          >
            + Filter
          </button>
          {(query ||
            JSON.stringify(filters) !==
              JSON.stringify(EMPTY_SEARCH_FILTERS)) && (
            <button
              className="px-2 text-xs text-muted-foreground hover:text-foreground"
              onClick={() => {
                setQuery("");
                setFilters({ ...EMPTY_SEARCH_FILTERS });
                input.current?.focus();
              }}
            >
              Clear all
            </button>
          )}
          {advanced && (
            <div className="flex w-full flex-wrap items-center gap-2 pt-2">
              <label className="flex items-center gap-2 text-xs text-muted-foreground">
                <input
                  type="checkbox"
                  checked={filters.archived}
                  onChange={(event) =>
                    patch({ archived: event.target.checked })
                  }
                />
                Include archived
              </label>
              {["notes", "external", "files", "links"].includes(
                filters.collection,
              ) && (
                <>
                  <select
                    aria-label="Note type"
                    className={selectClass}
                    value={filters.type}
                    onChange={(event) => patch({ type: event.target.value })}
                  >
                    <option value="">Any type</option>
                    {types.map((type) => (
                      <option key={type} value={type}>
                        {type || "Untyped"}
                      </option>
                    ))}
                  </select>
                  <select
                    aria-label="Property"
                    className={selectClass}
                    value={filters.property}
                    onChange={(event) =>
                      patch({ property: event.target.value, value: "" })
                    }
                  >
                    <option value="">Any property</option>
                    {properties.map((key) => (
                      <option key={key}>{key}</option>
                    ))}
                  </select>
                  {filters.property && (
                    <input
                      aria-label="Property value"
                      className={selectClass}
                      placeholder="Exact value (optional)"
                      value={filters.value}
                      onChange={(event) => patch({ value: event.target.value })}
                    />
                  )}
                </>
              )}
              {filters.collection === "tasks" && (
                <>
                  <select
                    aria-label="Task status"
                    className={selectClass}
                    value={filters.status}
                    onChange={(event) => patch({ status: event.target.value })}
                  >
                    <option value="">Any status</option>
                    <option value="open">Open</option>
                    <option value="completed">Completed</option>
                  </select>
                  <select
                    aria-label="Task priority"
                    className={selectClass}
                    value={filters.priority}
                    onChange={(event) =>
                      patch({ priority: event.target.value })
                    }
                  >
                    <option value="">Any priority</option>
                    {["none", "low", "medium", "high"].map((value) => (
                      <option key={value}>{value}</option>
                    ))}
                  </select>
                </>
              )}
            </div>
          )}
        </div>
        {(loading || vault.loadingNoteIds.size > 0 || error) && (
          <div
            role="status"
            className="flex items-center gap-2 px-5 pb-2 text-xs text-muted-foreground"
          >
            {(loading || vault.loadingNoteIds.size > 0) && (
              <Loader2 size={13} className="animate-spin" />
            )}
            {error || "Loading searchable content…"}
          </div>
        )}
        <div className="flex min-h-0 flex-1 gap-5 px-3 pb-3">
          <div className="flex min-w-0 flex-1 flex-col">
            <div className="flex justify-between px-3 py-2 text-xs text-muted-foreground">
              <span>
                {blank
                  ? "Recently opened"
                  : `Search results (${results.length})`}
              </span>
              {!blank && <span>Best matches</span>}
            </div>
            <div
              id="global-search-results"
              role="listbox"
              aria-label="Search results"
              className="min-h-0 flex-1 overflow-y-auto"
              onMouseLeave={cancelHover}
            >
              {displayed.map((item) => (
                <button
                  type="button"
                  tabIndex={-1}
                  role="option"
                  aria-selected={selected?.key === item.key}
                  id={`global-result-${item.key}`}
                  key={item.key}
                  onMouseEnter={() => {
                    cancelHover();
                    hover.current = setTimeout(
                      () => setSelectedKey(item.key),
                      200,
                    );
                  }}
                  onFocus={() => setSelectedKey(item.key)}
                  onClick={() => openItem(item)}
                  className={cn(
                    "flex w-full gap-3 rounded-xl px-3 py-3 text-left transition-colors",
                    selected?.key === item.key
                      ? "bg-muted"
                      : "hover:bg-muted/50",
                  )}
                >
                  <ItemIcon item={item} />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-medium">
                      <Highlight text={item.title} query={query} />
                    </div>
                    <div className="mt-1 truncate text-[11px] text-muted-foreground">
                      {COLLECTION_LABELS[item.collection]} · {item.location}
                      {item.archived ? " · Archived" : ""}
                    </div>
                    <p className="mt-1 line-clamp-2 text-xs leading-relaxed text-muted-foreground">
                      <Highlight
                        text={searchExcerpt(item, query)}
                        query={query}
                      />
                    </p>
                  </div>
                </button>
              ))}
              {!displayed.length && !loading && (
                <div className="px-5 py-16 text-center">
                  <Search
                    size={28}
                    className="mx-auto mb-4 text-muted-foreground/50"
                  />
                  <p className="text-sm">
                    {blank
                      ? "Find anything in your workspace"
                      : "No matching items"}
                  </p>
                  <p className="mt-2 text-xs text-muted-foreground">
                    {blank
                      ? "Start typing. Items you open will appear here."
                      : "Try fewer words, change filters, or ask AI."}
                  </p>
                </div>
              )}
              {results.length > limit && (
                <button
                  className="w-full p-3 text-sm text-zerus-accent"
                  onClick={() => setLimit((value) => value + 80)}
                >
                  Show more results
                </button>
              )}
            </div>
          </div>
          {selected && !mobile && (
            <aside
              aria-label="Result preview"
              className="hidden w-[39%] min-w-0 overflow-y-auto rounded-xl border border-border/70 bg-background/30 p-6 md:block"
            >
              <div className="mb-5 flex items-center justify-between">
                <ItemIcon item={selected} />
                <button
                  className="text-xs text-muted-foreground hover:text-foreground"
                  onClick={() => openItem(selected)}
                >
                  Open ↗
                </button>
              </div>
              <p className="mb-2 break-words text-xs text-muted-foreground">
                {selected.location}
              </p>
              <h2 className="mb-4 break-words text-xl font-semibold">
                <Highlight text={selected.title} query={query} />
              </h2>
              <dl className="mb-4 space-y-1 text-xs">
                {Object.entries(selected.properties)
                  .filter(([key]) => !key.startsWith("zerus-"))
                  .map(([key, value]) => (
                    <div key={key} className="flex gap-2">
                      <dt className="text-muted-foreground">{key}</dt>
                      <dd className="break-words">
                        <Highlight text={String(value)} query={query} />
                      </dd>
                    </div>
                  ))}
              </dl>
              <div className="whitespace-pre-wrap break-words text-sm leading-relaxed text-muted-foreground">
                <Highlight
                  text={searchPreviewText(selected).slice(0, 16000)}
                  query={query}
                />
              </div>
            </aside>
          )}
        </div>
        <footer className="flex items-center justify-between gap-3 border-t border-border/60 px-5 py-3">
          <span className="hidden text-[11px] text-muted-foreground sm:block">
            ↑↓ Preview · Enter Open · Esc Close search
          </span>
          <button
            disabled={!query.trim()}
            onClick={() => {
              onAskAI(searchChatRequest(query, selected));
              setOpen(false);
            }}
            className="ml-auto flex items-center gap-2 rounded-lg bg-muted px-3 py-2 text-xs font-medium hover:bg-muted/70 disabled:opacity-40"
          >
            <Sparkles size={15} />
            Ask AI ↗
          </button>
        </footer>
      </DialogContent>
    </Dialog>
  );
}
