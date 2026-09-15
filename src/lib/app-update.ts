import { invoke } from "@tauri-apps/api/core";
import type { DownloadEvent } from "@tauri-apps/plugin-updater";

export type InstallResult = "completed" | "canceled" | "up-to-date";
export interface AppUpdate {
  source: "ms-store" | "direct";
  /** Reminder identity; Store package identities are not app version numbers. */
  version: string;
  body?: string;
  downloadAndInstall: (onEvent: (event: DownloadEvent) => void) => Promise<InstallResult>;
  close: () => Promise<void>;
}

export async function checkForAppUpdate(distribution: string | undefined): Promise<AppUpdate | null> {
  if (distribution === "ms-store") {
    const identity = await invoke<string | null>("check_store_update");
    if (!identity) return null;
    return {
      source: "ms-store",
      version: `ms-store:${identity}`,
      downloadAndInstall: () => invoke<InstallResult>("install_store_update"),
      close: async () => {},
    };
  }
  const { check } = await import("@tauri-apps/plugin-updater");
  const update = await check({ timeout: 30_000 });
  if (!update) return null;
  return {
    source: "direct",
    version: update.version,
    body: update.body,
    downloadAndInstall: async (onEvent) => {
      await update.downloadAndInstall(onEvent);
      return "completed";
    },
    close: () => update.close(),
  };
}

export async function installAppUpdate(
  update: AppUpdate,
  save: () => Promise<boolean>,
  onEvent: (event: DownloadEvent) => void,
): Promise<InstallResult> {
  if (!(await save())) {
    throw new Error("Your changes could not be saved. Resolve any note conflicts or save errors, then try again.");
  }
  const result = await update.downloadAndInstall(onEvent);
  // Microsoft owns the lifecycle of Store updates, including closing the app.
  if (result === "completed" && update.source === "direct") {
    const { relaunch } = await import("@tauri-apps/plugin-process");
    await relaunch();
  }
  return result;
}
