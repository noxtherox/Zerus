import { invoke } from "@tauri-apps/api/core";

export type LocalAIPhase =
  | "notDownloaded"
  | "downloading"
  | "downloaded"
  | "loading"
  | "ready"
  | "generating"
  | "failed";

export interface LocalAIStatus {
  phase: LocalAIPhase;
  progress: number | null;
  error: string | null;
  modelName: string;
  modelId: string;
  approximateBytes: number;
}

export async function getLocalAIStatus(): Promise<LocalAIStatus> {
  return invoke<LocalAIStatus>("plugin:mobile-vault|local_ai_status");
}

export async function downloadLocalAI(): Promise<LocalAIStatus> {
  return invoke<LocalAIStatus>("plugin:mobile-vault|download_local_ai");
}

export async function cancelLocalAIDownload(): Promise<LocalAIStatus> {
  return invoke<LocalAIStatus>("plugin:mobile-vault|cancel_local_ai_download");
}

export async function loadLocalAI(): Promise<LocalAIStatus> {
  return invoke<LocalAIStatus>("plugin:mobile-vault|load_local_ai");
}

export interface LocalAIImageInput {
  bytes: Uint8Array;
  mimeType: string;
}

export async function generateLocalAI(prompt: string, image?: LocalAIImageInput): Promise<string> {
  const response = await invoke<{ answer: string }>("plugin:mobile-vault|generate_local_ai", {
    request: {
      prompt,
      imageBytes: image ? Array.from(image.bytes) : null,
      imageMimeType: image?.mimeType ?? null,
    },
  });
  return response.answer;
}

export async function deleteLocalAI(): Promise<LocalAIStatus> {
  return invoke<LocalAIStatus>("plugin:mobile-vault|delete_local_ai");
}
