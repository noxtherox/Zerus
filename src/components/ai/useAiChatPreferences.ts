import { useEffect, useRef, useState } from "react";
import {
  readChatPreferences,
  readLocalChatPreferences,
  saveLocalChatPreferences,
  writeChatPreferences,
  type AiChatPreferences,
} from "@/lib/ai-chat-preferences";
import type { VaultBackend } from "@/lib/vault/backend";

export function useAiChatPreferences(backend: VaultBackend | null, visible: boolean) {
  const [preferences, setPreferences] = useState(readLocalChatPreferences);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const revision = useRef(0);

  useEffect(() => {
    if (!visible) return;
    let active = true;
    const startedAt = revision.current;
    // Read local state again when switching between the desktop and mobile views.
    setPreferences(readLocalChatPreferences());
    if (backend) {
      void readChatPreferences(backend).then((saved) => {
        if (!active || revision.current !== startedAt || !saved) return;
        setPreferences(saved);
        saveLocalChatPreferences(saved);
      }).catch((error) => {
        if (active) setError(`Could not load chat preferences: ${String(error)}`);
      });
    }
    return () => { active = false; };
  }, [backend, visible]);

  const changeSimpleMode = async (simpleMode: boolean) => {
    if (saving) return;
    revision.current += 1;
    setSaving(true);
    setError("");
    const next: AiChatPreferences = { version: 1, simpleMode };
    try {
      if (backend) await writeChatPreferences(backend, next);
      saveLocalChatPreferences(next);
      setPreferences(next);
    } catch (error) {
      setError(`Could not save chat preferences: ${String(error)}`);
    } finally {
      setSaving(false);
    }
  };

  return { simpleMode: preferences.simpleMode, changeSimpleMode, saving, error };
}
