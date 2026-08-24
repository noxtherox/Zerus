import { useEffect, useState } from "react";
import { AlertTriangle, Check, Folder, FolderPlus, Loader2, X } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  chooseVaultFolder,
  getDesktopVaultConflictCount,
  getDesktopVaults,
  switchDesktopVault,
} from "@/store/notes-store";
import {
  forgetDesktopVault,
  type DesktopVaultEntry,
} from "@/lib/vault-registry";
import { cn } from "@/lib/utils";

interface VaultSwitcherDialogProps {
  currentPath: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function VaultSwitcherDialog({
  currentPath,
  open,
  onOpenChange,
}: VaultSwitcherDialogProps) {
  const [vaults, setVaults] = useState<DesktopVaultEntry[]>([]);
  const [busyPath, setBusyPath] = useState<string | null>(null);

  useEffect(() => {
    if (open) setVaults(getDesktopVaults());
  }, [currentPath, open]);

  const closeBeforeVaultAction = async () => {
    onOpenChange(false);
    // Let Radix commit the closed portal before loading a vault replaces the
    // sidebar that owns this dialog. Otherwise its backdrop can be orphaned.
    await new Promise<void>((resolve) => {
      requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
    });
  };

  const selectVault = async (path: string) => {
    if (path === currentPath) {
      onOpenChange(false);
      return;
    }
    setBusyPath(path);
    await closeBeforeVaultAction();
    const switched = await switchDesktopVault(path);
    setBusyPath(null);
    if (!switched) setVaults(getDesktopVaults());
  };

  const addVault = async () => {
    setBusyPath("__new__");
    await closeBeforeVaultAction();
    await chooseVaultFolder();
    setBusyPath(null);
    setVaults(getDesktopVaults());
  };

  const removeVault = (path: string) => {
    if (path === currentPath) return;
    setVaults(forgetDesktopVault(path));
  };

  return (
    <Dialog open={open} onOpenChange={(next) => !busyPath && onOpenChange(next)}>
      <DialogContent className="min-w-0 max-w-md gap-5 overflow-x-hidden">
        <DialogHeader>
          <DialogTitle>Vaults</DialogTitle>
          <DialogDescription>
            Switch between your Markdown folders, add another vault, or remove
            an inactive vault from this list. Your files are never deleted.
          </DialogDescription>
        </DialogHeader>

        <div className="min-w-0 space-y-2">
          {vaults.map((vault) => {
            const active = vault.path === currentPath;
            const loading = busyPath === vault.path;
            const conflictCount = getDesktopVaultConflictCount(vault.path);
            return (
              <div
                key={vault.path}
                className={cn(
                  "flex w-full min-w-0 max-w-full items-center gap-3 overflow-hidden rounded-lg border px-3 py-3 text-left transition-colors",
                  active
                    ? "border-primary/40 bg-primary/5"
                    : "border-border hover:bg-accent",
                  busyPath && "cursor-wait opacity-60",
                )}
              >
                <button
                  type="button"
                  disabled={busyPath !== null}
                  onClick={() => void selectVault(vault.path)}
                  className="flex min-w-0 flex-1 items-center gap-3 text-left disabled:cursor-wait"
                >
                  <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-muted">
                    <Folder size={18} />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-medium">{vault.name}</span>
                    <span className="mt-0.5 block max-w-full truncate text-xs text-muted-foreground" title={vault.path}>
                      {vault.path}
                    </span>
                  </span>
                  {loading ? (
                    <Loader2 className="h-4 w-4 shrink-0 animate-spin" />
                  ) : conflictCount > 0 ? (
                    <span
                      className="flex shrink-0 items-center gap-1 text-[11px] font-medium text-amber-600"
                      title={`${conflictCount} note conflict${conflictCount === 1 ? "" : "s"}`}
                    >
                      <AlertTriangle className="h-3.5 w-3.5" />
                      Needs review
                    </span>
                  ) : active ? (
                    <Check className="h-4 w-4 shrink-0 text-primary" aria-label="Current vault" />
                  ) : null}
                </button>
                {!active && (
                  <button
                    type="button"
                    disabled={busyPath !== null}
                    onClick={() => removeVault(vault.path)}
                    className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-accent hover:text-foreground disabled:cursor-wait"
                    aria-label={`Remove ${vault.name} from vault list`}
                    title="Remove from list (files stay on disk)"
                  >
                    <X className="h-4 w-4" />
                  </button>
                )}
              </div>
            );
          })}
        </div>

        <Button
          type="button"
          variant="outline"
          disabled={busyPath !== null}
          onClick={() => void addVault()}
          className="w-full gap-2"
        >
          {busyPath === "__new__" ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <FolderPlus className="h-4 w-4" />
          )}
          Add vault from folder
        </Button>
      </DialogContent>
    </Dialog>
  );
}
