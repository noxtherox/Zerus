import { isTauri } from "@tauri-apps/api/core";
import { getCurrentWebview } from "@tauri-apps/api/webview";

const INTERFACE_ZOOM_STORAGE_KEY = "zerus.interfaceZoom";

export const INTERFACE_ZOOM_OPTIONS = [80, 90, 100, 110, 125, 150] as const;
export type InterfaceZoom = (typeof INTERFACE_ZOOM_OPTIONS)[number];
export const DEFAULT_INTERFACE_ZOOM: InterfaceZoom = 100;

function isInterfaceZoom(value: unknown): value is InterfaceZoom {
  return INTERFACE_ZOOM_OPTIONS.some((option) => option === value);
}

/** Loads the app-wide interface zoom saved on this device. */
export function loadInterfaceZoom(): InterfaceZoom {
  try {
    const saved = Number(localStorage.getItem(INTERFACE_ZOOM_STORAGE_KEY));
    return isInterfaceZoom(saved) ? saved : DEFAULT_INTERFACE_ZOOM;
  } catch {
    return DEFAULT_INTERFACE_ZOOM;
  }
}

function applyReflowingBrowserZoom(zoom: InterfaceZoom): void {
  document.documentElement.style.fontSize = `${zoom}%`;
}

/** Scales the whole interface while keeping it within the visible viewport. */
export function applyInterfaceZoom(zoom: InterfaceZoom): void {
  // Clear the old CSS zoom implementation. CSS zoom enlarged the existing
  // canvas, which could push fixed and viewport-sized UI outside the window.
  document.documentElement.style.removeProperty("zoom");
  document.documentElement.style.removeProperty("font-size");

  if (isTauri()) {
    void getCurrentWebview()
      .setZoom(zoom / 100)
      .catch(() => applyReflowingBrowserZoom(zoom));
    return;
  }

  // Keep the browser preview useful without scaling the viewport itself.
  applyReflowingBrowserZoom(zoom);
}

/** Saves and immediately applies the app-wide interface zoom. */
export function saveInterfaceZoom(zoom: InterfaceZoom): void {
  applyInterfaceZoom(zoom);
  try {
    localStorage.setItem(INTERFACE_ZOOM_STORAGE_KEY, String(zoom));
  } catch {
    // Persistence is best-effort; the zoom still applies for this session.
  }
}

/** Applies the saved zoom once during startup. */
export function initInterfaceZoom(): void {
  applyInterfaceZoom(loadInterfaceZoom());
}
