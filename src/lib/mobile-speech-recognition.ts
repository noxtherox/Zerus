import { invoke } from "@tauri-apps/api/core";

export interface SpeechRecognitionStatus {
  listening: boolean;
  onDevice: boolean;
  engine?: string;
  build?: string;
}

export interface SpeechRecognitionProgress {
  listening: boolean;
  onDevice: boolean;
  transcript: string;
  engine?: string;
  build?: string;
}

export async function startOnDeviceSpeechRecognition(
  locale?: string,
): Promise<SpeechRecognitionStatus> {
  return invoke<SpeechRecognitionStatus>(
    "plugin:mobile-vault|start_speech_recognition",
    { request: { locale: locale ?? null } },
  );
}

export async function getOnDeviceSpeechRecognitionProgress(): Promise<SpeechRecognitionProgress> {
  return invoke<SpeechRecognitionProgress>(
    "plugin:mobile-vault|speech_recognition_progress",
  );
}

export async function stopOnDeviceSpeechRecognition(): Promise<string> {
  const response = await invoke<{ transcript: string }>(
    "plugin:mobile-vault|stop_speech_recognition",
  );
  return response.transcript;
}

export async function cancelOnDeviceSpeechRecognition(): Promise<void> {
  await invoke("plugin:mobile-vault|cancel_speech_recognition");
}
