import { invoke } from "@tauri-apps/api/core";
import { mobileDiagnostic } from "@/lib/mobile-diagnostics";

export interface MobileVaultLocation {
  url: string;
  name: string;
  persisted?: boolean;
  bookmarkWarning?: string;
}

interface MobileVaultLocationResponse {
  vault: MobileVaultLocation | null;
}

export interface MobilePickedFile {
  path: string;
  name: string;
}

interface MobilePickedFilesResponse {
  files: MobilePickedFile[];
}

export async function pickMobileVaultFolder(): Promise<MobileVaultLocation | null> {
  mobileDiagnostic("picker.invoke.started");
  try {
    const response = await invoke<MobileVaultLocationResponse>(
      "plugin:mobile-vault|pick_vault_folder",
    );
    mobileDiagnostic("picker.invoke.resolved", {
      selected: response.vault !== null,
      name: response.vault?.name,
      scheme: response.vault ? new URL(response.vault.url).protocol : undefined,
      persisted: response.vault?.persisted,
      bookmarkWarning: response.vault?.bookmarkWarning,
    });
    return response.vault;
  } catch (error) {
    mobileDiagnostic("picker.invoke.failed", { error });
    throw error;
  }
}

export async function restoreMobileVaultFolder(): Promise<MobileVaultLocation | null> {
  mobileDiagnostic("bookmark.restore.started");
  try {
    const response = await invoke<MobileVaultLocationResponse>(
      "plugin:mobile-vault|restore_vault_folder",
    );
    mobileDiagnostic("bookmark.restore.resolved", {
      found: response.vault !== null,
      name: response.vault?.name,
    });
    return response.vault;
  } catch (error) {
    mobileDiagnostic("bookmark.restore.failed", { error });
    throw error;
  }
}

export async function clearMobileVaultFolder(): Promise<void> {
  await invoke("plugin:mobile-vault|clear_vault_folder");
}

export async function pickMobileExternalNotes(): Promise<MobilePickedFile[]> {
  const response = await invoke<MobilePickedFilesResponse>(
    "plugin:mobile-vault|pick_external_notes",
  );
  return response.files;
}

export async function pickMobileFiles(): Promise<MobilePickedFile[]> {
  const response = await invoke<MobilePickedFilesResponse>(
    "plugin:mobile-vault|pick_files",
  );
  return response.files;
}

export async function pickMobileFileLocationFolder(): Promise<MobilePickedFile | null> {
  const response = await invoke<MobilePickedFilesResponse>(
    "plugin:mobile-vault|pick_external_folder",
  );
  return response.files[0] ?? null;
}

export async function openMobileFile(
  path: string,
  mode: "preview" | "refresh" = "preview",
): Promise<void> {
  await invoke("plugin:mobile-vault|open_file", { request: { path, mode } });
}
