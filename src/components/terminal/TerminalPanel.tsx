import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { FitAddon } from "@xterm/addon-fit";
import { SearchAddon } from "@xterm/addon-search";
import { WebLinksAddon } from "@xterm/addon-web-links";
import { Terminal } from "@xterm/xterm";
import {
  Copy,
  Ellipsis,
  OctagonX,
  RefreshCw,
  Search,
  SquareTerminal,
  TextCursorInput,
  X,
} from "@/lib/icons";
import "@xterm/xterm/css/xterm.css";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { openExternalUrl } from "@/lib/external-links";
import {
  desktopPlatform,
  primaryModifierLabel,
  quoteTerminalArgument,
} from "@/lib/desktop-platform";
import type { Note } from "@/lib/note-utils";
import {
  normalizeFsPath,
  noteAbsolutePath,
  noteTitle,
} from "@/lib/note-utils";
import { cn } from "@/lib/utils";
import { showError } from "@/utils/toast";

const DEFAULT_WIDTH = 420;
const MIN_WIDTH = 320;
const WIDTH_STORAGE_KEY = "zerus.terminal.width";

interface SessionInfo {
  sessionId: number;
  workingDirectory: string;
}

interface TerminalOutputEvent {
  sessionId: number;
  data: number[];
}

interface TerminalExitEvent {
  sessionId: number;
  exitCode: number | null;
  signal: string | null;
  error: string | null;
}

interface SessionEntry {
  info: SessionInfo;
  running: boolean;
  exit: TerminalExitEvent | null;
}

interface TerminalView {
  terminal: Terminal;
  fitAddon: FitAddon;
  searchAddon: SearchAddon;
  dataDisposable: { dispose: () => void };
  resizeObserver: ResizeObserver;
}

interface TerminalPanelProps {
  open: boolean;
  note: Note | null;
  targetDirectory: string | null;
  vaultLocation: string | null;
  onOpenChange: (open: boolean) => void;
}

function storedWidth(): number {
  const value = Number(localStorage.getItem(WIDTH_STORAGE_KEY));
  return Number.isFinite(value) && value >= MIN_WIDTH ? value : DEFAULT_WIDTH;
}

function terminalTheme() {
  const styles = getComputedStyle(document.documentElement);
  const rgb = (name: string, fallback: string) => {
    const value = styles.getPropertyValue(name).trim();
    return value ? `rgb(${value.split(/\s+/).join(", ")})` : fallback;
  };
  return {
    background: rgb("--grim-editor-bg", "#ffffff"),
    foreground: rgb("--grim-text", "#020817"),
    cursor: rgb("--grim-accent", "#d84b40"),
    selectionBackground: "rgba(128, 128, 128, 0.28)",
  };
}

function pathsMatch(left: string | null, right: string | null): boolean {
  return !!left && !!right && normalizeFsPath(left) === normalizeFsPath(right);
}

function directoryName(path: string | null): string {
  if (!path) return "Terminal";
  const normalized = path.replace(/[\\/]+$/, "").replace(/\\/g, "/");
  return normalized.split("/").pop() || path;
}

export function TerminalPanel({
  open,
  note,
  targetDirectory,
  vaultLocation,
  onOpenChange,
}: TerminalPanelProps) {
  const panelRef = useRef<HTMLDivElement>(null);
  const viewsRef = useRef(new Map<number, TerminalView>());
  const outputBufferRef = useRef(new Map<number, Uint8Array[]>());
  const activeSessionIdRef = useRef<number | null>(null);
  const targetDirectoryRef = useRef(targetDirectory);
  const startingDirectoriesRef = useRef(new Set<string>());
  const focusTerminalOnMenuCloseRef = useRef(false);
  const focusActiveSessionRef = useRef(false);
  const previousOpenRef = useRef(open);
  const openRef = useRef(open);
  if (open && !previousOpenRef.current) focusActiveSessionRef.current = true;
  previousOpenRef.current = open;
  openRef.current = open;
  targetDirectoryRef.current = targetDirectory;

  const [entries, setEntries] = useState<SessionEntry[]>([]);
  const [activeSessionId, setActiveSessionId] = useState<number | null>(null);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [restartConfirmOpen, setRestartConfirmOpen] = useState(false);
  const [endConfirmOpen, setEndConfirmOpen] = useState(false);
  const [width, setWidth] = useState(storedWidth);

  activeSessionIdRef.current = activeSessionId;

  const notePath = note ? noteAbsolutePath(note, vaultLocation) : null;
  const activeEntry =
    entries.find((entry) => entry.info.sessionId === activeSessionId) ?? null;
  const runningCount = entries.filter((entry) => entry.running).length;

  const resizeSession = useCallback((sessionId: number) => {
    if (!openRef.current || activeSessionIdRef.current !== sessionId) return;
    const view = viewsRef.current.get(sessionId);
    if (!view) return;
    try {
      view.fitAddon.fit();
      void invoke("terminal_resize", {
        sessionId,
        rows: view.terminal.rows,
        cols: view.terminal.cols,
      }).catch(() => {});
    } catch {
      // The panel may be between display states; the next observer tick retries.
    }
  }, []);

  const disposeView = useCallback((sessionId: number) => {
    const view = viewsRef.current.get(sessionId);
    if (!view) return;
    view.resizeObserver.disconnect();
    view.dataDisposable.dispose();
    view.terminal.dispose();
    viewsRef.current.delete(sessionId);
    outputBufferRef.current.delete(sessionId);
  }, []);

  const attachTerminal = useCallback(
    (info: SessionInfo, container: HTMLDivElement | null) => {
      if (!container || viewsRef.current.has(info.sessionId)) return;
      const terminal = new Terminal({
        allowProposedApi: false,
        convertEol: false,
        cursorBlink: true,
        fontFamily:
          "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
        fontSize: 13.5,
        scrollback: 10_000,
        theme: terminalTheme(),
      });
      const fitAddon = new FitAddon();
      const searchAddon = new SearchAddon();
      terminal.loadAddon(fitAddon);
      terminal.loadAddon(searchAddon);
      terminal.loadAddon(
        new WebLinksAddon((event, uri) => {
          event.preventDefault();
          void openExternalUrl(uri);
        }),
      );
      terminal.open(container);

      const dataDisposable = terminal.onData((data) => {
        void invoke("terminal_write", {
          sessionId: info.sessionId,
          data,
        }).catch(() => {});
      });
      terminal.attachCustomKeyEventHandler((event) => {
        if (
          event.type === "keydown" &&
          (desktopPlatform === "macos"
            ? event.metaKey
            : event.ctrlKey && event.shiftKey) &&
          event.key.toLowerCase() === "c" &&
          terminal.hasSelection()
        ) {
          void navigator.clipboard.writeText(terminal.getSelection());
          return false;
        }
        return true;
      });

      const resizeObserver = new ResizeObserver(() =>
        resizeSession(info.sessionId),
      );
      resizeObserver.observe(container);
      viewsRef.current.set(info.sessionId, {
        terminal,
        fitAddon,
        searchAddon,
        dataDisposable,
        resizeObserver,
      });

      const chunks = outputBufferRef.current.get(info.sessionId);
      if (chunks) {
        outputBufferRef.current.delete(info.sessionId);
        for (const chunk of chunks) terminal.write(chunk);
      }
      if (activeSessionIdRef.current === info.sessionId) {
        requestAnimationFrame(() => {
          resizeSession(info.sessionId);
          if (focusActiveSessionRef.current) {
            focusActiveSessionRef.current = false;
            terminal.focus();
          }
        });
      }
    },
    [resizeSession],
  );

  const startSession = useCallback(async (directory: string) => {
    const key = normalizeFsPath(directory);
    if (startingDirectoriesRef.current.has(key)) return;
    startingDirectoriesRef.current.add(key);
    setError(null);
    try {
      const info = await invoke<SessionInfo>("terminal_start", {
        workingDirectory: directory,
        rows: 24,
        cols: 80,
      });
      setEntries((current) => {
        const existing = current.find(
          (entry) => entry.info.sessionId === info.sessionId,
        );
        if (existing) {
          return current.map((entry) =>
            entry.info.sessionId === info.sessionId
              ? { ...entry, info, running: true, exit: null }
              : entry,
          );
        }
        return [...current, { info, running: true, exit: null }];
      });
      if (pathsMatch(targetDirectoryRef.current, info.workingDirectory)) {
        setActiveSessionId(info.sessionId);
      }
    } catch (startError) {
      const message = String(startError);
      setError(message);
      showError(`Failed to open terminal: ${message}`);
    } finally {
      startingDirectoriesRef.current.delete(key);
    }
  }, []);

  useEffect(() => {
    let disposed = false;
    const unlisteners: Array<() => void> = [];
    const views = viewsRef.current;
    void Promise.all([
      listen<TerminalOutputEvent>("zerus-terminal-output", ({ payload }) => {
        const view = viewsRef.current.get(payload.sessionId);
        if (view) {
          view.terminal.write(new Uint8Array(payload.data));
          return;
        }
        const chunks = outputBufferRef.current.get(payload.sessionId) ?? [];
        chunks.push(new Uint8Array(payload.data));
        outputBufferRef.current.set(payload.sessionId, chunks);
      }),
      listen<TerminalExitEvent>("zerus-terminal-exit", ({ payload }) => {
        setEntries((current) =>
          current.map((entry) =>
            entry.info.sessionId === payload.sessionId
              ? { ...entry, running: false, exit: payload }
              : entry,
          ),
        );
      }),
    ]).then(async (listeners) => {
      if (disposed) {
        listeners.forEach((unlisten) => unlisten());
        return;
      }
      unlisteners.push(...listeners);
      try {
        const infos = await invoke<SessionInfo[]>("terminal_status");
        if (!disposed) {
          setEntries(
            infos.map((info) => ({ info, running: true, exit: null })),
          );
        }
      } catch {
        // No native sessions are expected on a fresh frontend mount.
      } finally {
        if (!disposed) setReady(true);
      }
    });

    return () => {
      disposed = true;
      unlisteners.forEach((unlisten) => unlisten());
      for (const sessionId of views.keys()) disposeView(sessionId);
    };
  }, [disposeView]);

  useEffect(() => {
    if (!ready || !open || !targetDirectory) return;
    const matching = [...entries]
      .reverse()
      .find((entry) =>
        pathsMatch(entry.info.workingDirectory, targetDirectory),
      );
    if (matching) {
      setActiveSessionId(matching.info.sessionId);
      requestAnimationFrame(() => {
        resizeSession(matching.info.sessionId);
        if (focusActiveSessionRef.current) {
          focusActiveSessionRef.current = false;
          viewsRef.current.get(matching.info.sessionId)?.terminal.focus();
        }
      });
      return;
    }
    void startSession(targetDirectory);
  }, [entries, open, ready, resizeSession, startSession, targetDirectory]);

  useEffect(() => {
    const applyTheme = () => {
      const theme = terminalTheme();
      for (const view of viewsRef.current.values()) {
        view.terminal.options.theme = theme;
      }
    };
    const observer = new MutationObserver(applyTheme);
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["class", "style"],
    });
    return () => observer.disconnect();
  }, []);

  const exitLabel = useMemo(() => {
    const exit = activeEntry?.exit;
    if (!exit) return null;
    if (exit.error) return `Terminal stopped: ${exit.error}`;
    if (exit.signal) return `Terminal ended by ${exit.signal}`;
    return `Terminal exited with status ${exit.exitCode ?? "unknown"}.`;
  }, [activeEntry?.exit]);

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
        window.innerWidth * 0.6,
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

  const removeEntry = useCallback(
    (sessionId: number) => {
      disposeView(sessionId);
      setEntries((current) =>
        current.filter((entry) => entry.info.sessionId !== sessionId),
      );
    },
    [disposeView],
  );

  const restartActiveSession = async () => {
    setRestartConfirmOpen(false);
    const entry = activeEntry;
    if (!entry) return;
    if (entry.running) {
      await invoke("terminal_stop", { sessionId: entry.info.sessionId }).catch(
        () => {},
      );
    }
    removeEntry(entry.info.sessionId);
    await startSession(entry.info.workingDirectory);
  };

  const insertCurrentNotePath = async () => {
    const entry = activeEntry;
    const view = entry ? viewsRef.current.get(entry.info.sessionId) : null;
    if (!entry?.running || !notePath) return;
    focusTerminalOnMenuCloseRef.current = true;
    try {
      await invoke("terminal_write", {
        sessionId: entry.info.sessionId,
        data: quoteTerminalArgument(notePath),
      });
      view?.terminal.focus();
    } catch (insertError) {
      showError(`Failed to insert note path: ${String(insertError)}`);
    }
  };

  const startCurrentDirectory = () => {
    if (!targetDirectory) return;
    if (
      activeEntry &&
      pathsMatch(activeEntry.info.workingDirectory, targetDirectory)
    ) {
      removeEntry(activeEntry.info.sessionId);
    }
    void startSession(targetDirectory);
  };

  return (
    <div
      ref={panelRef}
      className={cn(
        "relative h-full shrink-0 border-l border-border/70 bg-grim-editor",
        !open && "hidden",
      )}
      style={{
        width: `min(${width}px, 60vw)`,
        maxWidth: "calc(100% - 240px)",
      }}
    >
      <div
        className="absolute inset-y-0 -left-1 z-20 w-2 cursor-col-resize touch-none"
        onPointerDown={handleResizeStart}
        role="separator"
        aria-label="Resize terminal panel"
      />
      <div className="flex h-full min-w-0 flex-col">
        <div className="flex h-11 shrink-0 items-center gap-1 border-b border-border/60 px-2">
          <SquareTerminal className="mx-1 shrink-0 text-grim-accent" size={16} />
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-1.5 truncate text-xs font-medium">
              <span>Terminal</span>
              {runningCount > 1 && (
                <span className="text-[10px] font-normal text-muted-foreground">
                  · {runningCount} sessions
                </span>
              )}
            </div>
            <div
              className="truncate text-[10px] text-muted-foreground"
              title={
                activeEntry?.info.workingDirectory ?? targetDirectory ?? undefined
              }
            >
              {activeEntry?.info.workingDirectory ??
                targetDirectory ??
                "Select a folder or note"}
            </div>
          </div>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7 shrink-0"
                title="Terminal actions"
                aria-label="Terminal actions"
              >
                <Ellipsis size={16} />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent
              align="end"
              className="w-60"
              onCloseAutoFocus={(event) => {
                if (!focusTerminalOnMenuCloseRef.current) return;
                event.preventDefault();
                focusTerminalOnMenuCloseRef.current = false;
                requestAnimationFrame(() => {
                  if (activeSessionIdRef.current !== null) {
                    viewsRef.current
                      .get(activeSessionIdRef.current)
                      ?.terminal.focus();
                  }
                });
              }}
            >
              {runningCount > 1 && (
                <>
                  <DropdownMenuItem disabled>
                    {runningCount} folder sessions running
                  </DropdownMenuItem>
                  <DropdownMenuSeparator />
                </>
              )}
              <DropdownMenuItem
                disabled={!notePath || !activeEntry?.running}
                onSelect={() => void insertCurrentNotePath()}
              >
                <TextCursorInput className="mr-2" size={14} />
                Insert current note path
              </DropdownMenuItem>
              <DropdownMenuItem
                disabled={!notePath}
                onSelect={() =>
                  notePath && void navigator.clipboard.writeText(notePath)
                }
              >
                <Copy className="mr-2" size={14} />
                Copy current note path
              </DropdownMenuItem>
              <DropdownMenuItem
                disabled={!activeEntry}
                onSelect={() => setSearchOpen((current) => !current)}
              >
                <Search className="mr-2" size={14} />
                {searchOpen ? "Hide output search" : "Search terminal output"}
              </DropdownMenuItem>
              <DropdownMenuItem
                disabled={!activeEntry}
                onSelect={() => setRestartConfirmOpen(true)}
              >
                <RefreshCw className="mr-2" size={14} />
                Restart shell in {directoryName(activeEntry?.info.workingDirectory ?? null)}
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                disabled={!activeEntry?.running}
                className="text-destructive focus:text-destructive"
                onSelect={() => setEndConfirmOpen(true)}
              >
                <OctagonX className="mr-2" size={14} />
                End this folder session
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          <Button
            variant="ghost"
            size="icon"
            className="h-7 w-7 shrink-0"
            title={`Hide terminal (${primaryModifierLabel}J)`}
            onClick={() => onOpenChange(false)}
          >
            <X size={14} />
          </Button>
        </div>
        {searchOpen && (
          <form
            className="flex h-9 shrink-0 items-center gap-1 border-b border-border/50 px-2"
            onSubmit={(event) => {
              event.preventDefault();
              if (activeSessionIdRef.current !== null) {
                viewsRef.current
                  .get(activeSessionIdRef.current)
                  ?.searchAddon.findNext(searchQuery);
              }
            }}
          >
            <Input
              autoFocus
              value={searchQuery}
              onChange={(event) => {
                setSearchQuery(event.target.value);
                if (activeSessionIdRef.current !== null) {
                  viewsRef.current
                    .get(activeSessionIdRef.current)
                    ?.searchAddon.findNext(event.target.value, {
                      incremental: true,
                    });
                }
              }}
              placeholder="Search output"
              className="h-7 text-xs"
            />
            <Button type="submit" variant="ghost" size="sm" className="h-7 px-2">
              Next
            </Button>
          </form>
        )}
        <div className="relative min-h-0 flex-1">
          {entries.map((entry) => (
            <div
              key={entry.info.sessionId}
              ref={(container) => attachTerminal(entry.info, container)}
              className={cn(
                "absolute inset-0 p-2",
                entry.info.sessionId !== activeSessionId &&
                  "invisible pointer-events-none",
              )}
            />
          ))}
        </div>
        {(exitLabel || error) && (
          <div className="flex shrink-0 items-center gap-2 border-t border-border/60 px-3 py-2 text-xs">
            <span className="min-w-0 flex-1 truncate text-muted-foreground">
              {error ?? exitLabel}
            </span>
            {targetDirectory && (
              <Button
                size="sm"
                className="h-7 shrink-0 gap-1.5 text-xs"
                onClick={startCurrentDirectory}
              >
                <RefreshCw size={13} /> Start new shell
              </Button>
            )}
          </div>
        )}
        {note && (
          <div className="shrink-0 truncate border-t border-border/40 px-3 py-1.5 text-[10px] text-muted-foreground">
            Selected note:{" "}
            <span title={notePath ?? undefined}>{noteTitle(note)}</span>
          </div>
        )}
      </div>

      <AlertDialog open={restartConfirmOpen} onOpenChange={setRestartConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Restart this folder’s terminal?</AlertDialogTitle>
            <AlertDialogDescription>
              This ends the current shell and any process running inside it. Its
              terminal output will be cleared. Other folder sessions are not affected.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep running</AlertDialogCancel>
            <AlertDialogAction onClick={() => void restartActiveSession()}>
              End and restart
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      <AlertDialog open={endConfirmOpen} onOpenChange={setEndConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>End this folder’s terminal?</AlertDialogTitle>
            <AlertDialogDescription>
              This stops the shell and any process running inside it. Other folder
              sessions keep running, and this terminal’s output remains visible.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep running</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              onClick={() => {
                setEndConfirmOpen(false);
                if (activeEntry?.running) {
                  void invoke("terminal_stop", {
                    sessionId: activeEntry.info.sessionId,
                  });
                }
              }}
            >
              End terminal
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
