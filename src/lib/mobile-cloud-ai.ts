import { addPluginListener, invoke } from "@tauri-apps/api/core";

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

export interface CloudAIModel {
  id: string;
  name: string;
}

export function cloudEndpointLabel(endpoint: string): string {
  try {
    const host = new URL(endpoint).hostname.toLowerCase();
    return host === "openrouter.ai" ? "OpenRouter" : host;
  } catch {
    return "Cloud";
  }
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

export async function connectOpenRouter(): Promise<CloudAIStatus> {
  return invoke<CloudAIStatus>("plugin:mobile-vault|connect_openrouter");
}

export async function getCloudAIModels(): Promise<CloudAIModel[]> {
  return (await invoke<{ models: CloudAIModel[] }>("plugin:mobile-vault|cloud_ai_models")).models;
}

export async function generateCloudAI(
  prompt: string,
  images: CloudAIImageInput[] = [],
  onDelta?: (delta: string) => void,
): Promise<string> {
  const streamId = crypto.randomUUID();
  const listener = onDelta ? await addPluginListener<{ streamId: string; delta: string }>(
    "mobile-vault",
    "cloud-ai-delta",
    (payload) => {
      if (payload.streamId === streamId) onDelta(payload.delta);
    },
  ) : null;
  try {
    const response = await invoke<{ answer: string }>("plugin:mobile-vault|generate_cloud_ai", {
      request: {
        prompt,
        streamId,
        images: images.slice(0, 4).map((image) => ({
          bytes: Array.from(image.bytes),
          mimeType: image.mimeType,
        })),
      },
    });
    return response.answer;
  } finally {
    await listener?.unregister();
  }
}

export async function stopCloudAI(): Promise<void> {
  await invoke("plugin:mobile-vault|stop_cloud_ai");
}
