import { invoke } from "@tauri-apps/api/core";
import type { ChatDevice } from "@/lib/mobile-chat-history";

const DEVICE_ID_KEY = "grimoire.chat.deviceId.v1";
const CUSTOM_DEVICE_NAME_KEY = "grimoire.chat.deviceName.v1";

function randomId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) return crypto.randomUUID();
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

function persistentDeviceId(): string {
  try {
    const current = localStorage.getItem(DEVICE_ID_KEY);
    if (current) return current;
    const created = randomId();
    localStorage.setItem(DEVICE_ID_KEY, created);
    return created;
  } catch {
    return randomId();
  }
}

function fallbackDeviceName(): string {
  const userAgent = typeof navigator === "undefined" ? "" : navigator.userAgent;
  if (/iphone/i.test(userAgent)) return "iPhone";
  if (/ipad/i.test(userAgent)) return "iPad";
  if (/android/i.test(userAgent)) return "Android device";
  if (/macintosh|mac os/i.test(userAgent)) return "Mac";
  if (/windows/i.test(userAgent)) return "Windows PC";
  return "This device";
}

async function advertisedDeviceName(): Promise<string> {
  try {
    const custom = localStorage.getItem(CUSTOM_DEVICE_NAME_KEY)?.trim();
    if (custom) return custom;
  } catch {
    // Fall through to the advertised OS name.
  }
  if (typeof window !== "undefined" && "__TAURI_INTERNALS__" in window) {
    try {
      const response = await invoke<{ name: string }>("plugin:mobile-vault|device_name");
      if (response.name.trim()) return response.name.trim();
    } catch {
      // Browser previews and older native builds use the platform fallback.
    }
  }
  return fallbackDeviceName();
}

export async function getChatDevice(): Promise<ChatDevice> {
  return { id: persistentDeviceId(), name: await advertisedDeviceName() };
}

export function chatDeviceLabel(device: ChatDevice, devices: ChatDevice[]): string {
  const duplicates = devices.filter((candidate) => candidate.name === device.name && candidate.id !== device.id);
  return duplicates.length === 0 ? device.name : `${device.name} · ${device.id.slice(-4).toUpperCase()}`;
}
