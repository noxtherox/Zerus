import { useSyncExternalStore } from "react";

const KEY = "zerus.codeBlocks";
const EVENT = "zerus:editor-preferences";
export function loadCodeBlocksEnabled(): boolean {
  try { return localStorage.getItem(KEY) === "true"; } catch { return false; }
}
export function saveCodeBlocksEnabled(enabled: boolean) {
  localStorage.setItem(KEY, String(enabled));
  window.dispatchEvent(new Event(EVENT));
}
function subscribe(listener: () => void) {
  window.addEventListener(EVENT, listener);
  window.addEventListener("storage", listener);
  return () => {
    window.removeEventListener(EVENT, listener);
    window.removeEventListener("storage", listener);
  };
}
export function useCodeBlocksEnabled() {
  return useSyncExternalStore(subscribe, loadCodeBlocksEnabled, () => false);
}
