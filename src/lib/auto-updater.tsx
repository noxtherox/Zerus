import { useEffect, useRef, useState } from "react";
import { isTauri } from "@tauri-apps/api/core";
import { checkForAppUpdate, installAppUpdate, type AppUpdate } from "./app-update";
import { toast } from "sonner";
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

const CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000;
const REMIND_LATER_MS = 24 * 60 * 60 * 1000;
const REMINDER_STORAGE_KEY = "zerus-update-reminder";

interface DeferredUpdate {
  version: string;
  remindAfter: number;
}

function loadDeferredUpdate(): DeferredUpdate | null {
  try {
    const value = localStorage.getItem(REMINDER_STORAGE_KEY);
    if (!value) return null;
    const parsed = JSON.parse(value) as Partial<DeferredUpdate>;
    return typeof parsed.version === "string" &&
      typeof parsed.remindAfter === "number"
      ? { version: parsed.version, remindAfter: parsed.remindAfter }
      : null;
  } catch {
    return null;
  }
}

function deferUpdate(version: string) {
  localStorage.setItem(
    REMINDER_STORAGE_KEY,
    JSON.stringify({ version, remindAfter: Date.now() + REMIND_LATER_MS }),
  );
}

export function AutoUpdater() {
  const availableUpdate = useRef<AppUpdate | null>(null);
  const checkInProgress = useRef(false);
  const lastCheckAt = useRef(0);
  const [version, setVersion] = useState<string | null>(null);
  const [notes, setNotes] = useState<string | null>(null);
  const [installing, setInstalling] = useState(false);
  const [progress, setProgress] = useState<number | null>(null);

  const closeAvailableUpdate = async () => {
    const update = availableUpdate.current;
    availableUpdate.current = null;
    setVersion(null);
    setNotes(null);
    setProgress(null);
    if (update) await update.close().catch(() => undefined);
  };

  const remindLater = () => {
    if (!version || installing) return;
    deferUpdate(version);
    void closeAvailableUpdate();
  };

  const installUpdate = async () => {
    const update = availableUpdate.current;
    if (!update || installing) return;

    setInstalling(true);
    let downloaded = 0;
    let total: number | undefined;

    try {
      const { flushPendingWrites } = await import("@/store/notes-store");
      const result = await installAppUpdate(update, flushPendingWrites, (event) => {
        if (event.event === "Started") {
          total = event.data.contentLength;
          setProgress(total ? 0 : null);
        } else if (event.event === "Progress") {
          downloaded += event.data.chunkLength;
          if (total) {
            setProgress(
              Math.min(100, Math.round((downloaded / total) * 100)),
            );
          }
        } else {
          setProgress(100);
        }
      });
      setInstalling(false);
      if (result === "canceled") {
        setProgress(null);
        return;
      }
      if (update.source === "ms-store") {
        toast.success(result === "up-to-date"
          ? "Microsoft Store reports no pending updates."
          : "Microsoft Store finished the update. Reopen Zerus if needed.");
      }
      await closeAvailableUpdate();
    } catch (error) {
      toast.error(update.source === "ms-store" ? "The Microsoft Store update could not be installed." : `Zerus ${update.version} could not be installed.`, {
        description: String(error),
      });
      setInstalling(false);
      setProgress(null);
    }
  };

  useEffect(() => {
    if (!import.meta.env.PROD || !isTauri()) return undefined;

    let disposed = false;
    const checkForUpdate = async () => {
      const now = Date.now();
      if (
        checkInProgress.current ||
        availableUpdate.current ||
        now - lastCheckAt.current < CHECK_INTERVAL_MS
      ) {
        return;
      }

      checkInProgress.current = true;
      lastCheckAt.current = now;

      try {
        const update = await checkForAppUpdate(import.meta.env.VITE_DISTRIBUTION);
        if (!update) return;
        if (disposed) {
          await update.close();
          return;
        }

        const deferred = loadDeferredUpdate();
        if (
          deferred?.version === update.version &&
          deferred.remindAfter > Date.now()
        ) {
          await update.close();
          return;
        }

        localStorage.removeItem(REMINDER_STORAGE_KEY);
        availableUpdate.current = update;
        setVersion(update.version);
        setNotes(update.body?.trim() || null);
      } catch (error) {
        console.warn("Zerus update check failed", error);
      } finally {
        checkInProgress.current = false;
      }
    };

    const check = () => void checkForUpdate();
    const checkWhenVisible = () => {
      if (document.visibilityState === "visible") check();
    };

    check();
    const interval = window.setInterval(check, CHECK_INTERVAL_MS);
    window.addEventListener("focus", check);
    document.addEventListener("visibilitychange", checkWhenVisible);

    return () => {
      disposed = true;
      window.clearInterval(interval);
      window.removeEventListener("focus", check);
      document.removeEventListener("visibilitychange", checkWhenVisible);
      const update = availableUpdate.current;
      availableUpdate.current = null;
      if (update) void update.close().catch(() => undefined);
    };
  }, []);

  const isStore = availableUpdate.current?.source === "ms-store";

  return (
    <AlertDialog
      open={version !== null}
      onOpenChange={(open) => {
        if (!open && !installing) remindLater();
      }}
    >
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{isStore ? "A Zerus update is available" : `Zerus ${version} is available`}</AlertDialogTitle>
          <AlertDialogDescription>
            {isStore
              ? installing
                ? "Saving your changes and updating through Microsoft Store… Follow any Windows prompts. Zerus may close during installation."
                : "Microsoft Store has an update for Zerus. Your changes will be saved first. Windows may ask for confirmation and close Zerus to install it."
              : installing
              ? progress === null
                ? "Downloading the update…"
                : progress < 100
                  ? `Downloading the update… ${progress}%`
                  : "Installing the update. Zerus will restart when it is ready…"
              : "Would you like to download and install it now? Zerus will restart after the update is installed."}
          </AlertDialogDescription>
          {!installing && notes && (
            <p className="max-h-32 overflow-y-auto whitespace-pre-wrap rounded-md bg-muted/60 p-3 text-xs text-muted-foreground">
              {notes}
            </p>
          )}
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={installing} onClick={remindLater}>
            Remind me later
          </AlertDialogCancel>
          <AlertDialogAction
            disabled={installing}
            onClick={(event) => {
              event.preventDefault();
              void installUpdate();
            }}
          >
            {installing
              ? isStore
                ? "Updating…"
                : progress === null
                ? "Downloading…"
                : progress < 100
                  ? `Downloading… ${progress}%`
                  : "Installing…"
              : isStore ? "Update" : "Download and install"}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
