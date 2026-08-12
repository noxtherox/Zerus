import { invoke } from "@tauri-apps/api/core";

export interface CloudAIStatus {
  endpoint: string;
  model: string;
  configured: boolean;
}

export interface CloudAIConfiguration {
  endpoint: string;
  model: string;
  apiKey?: string;
}

export interface CloudAIImageInput {
  bytes: Uint8Array;
  mimeType: string;
}

export async function getCloudAIStatus(): Promise<CloudAIStatus> {
  return invoke<CloudAIStatus>("plugin:mobile-vault|cloud_ai_status");
}

export async function configureCloudAI(configuration: CloudAIConfiguration): Promise<CloudAIStatus> {
  return invoke<CloudAIStatus>("plugin:mobile-vault|configure_cloud_ai", {
    request: {
      endpoint: configuration.endpoint,
      model: configuration.model,
      apiKey: configuration.apiKey?.trim() || null,
    },
  });
}

export async function generateCloudAI(prompt: string, image?: CloudAIImageInput): Promise<string> {
  const response = await invoke<{ answer: string }>("plugin:mobile-vault|generate_cloud_ai", {
    request: {
      prompt,
      imageBytes: image ? Array.from(image.bytes) : null,
      imageMimeType: image?.mimeType ?? null,
    },
  });
  return response.answer;
}
