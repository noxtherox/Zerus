import { useCallback, useEffect, useRef, useState } from "react";
import {
  DEFAULT_AGENT_SETTINGS,
  loadAgentGuidance,
  loadAgentRuns,
  loadAgentSettings,
  loadNoteWorkflows,
  normalizeAgentSettings,
  saveAgentGuidance,
  saveAgentSettings,
  type AgentRun,
  type AgentSettings,
} from "@/lib/ai-harness-state";
import {
  createAgentRun,
  NotesAgentRuntime,
  type NotesAgentPort,
} from "@/lib/ai-harness";
import type { Note } from "@/lib/note-utils";
import type { VaultBackend } from "@/lib/vault/backend";

export function useNotesAgent(
  backend: VaultBackend | null,
  chatId: string | null,
) {
  const [settings, setSettings] = useState<AgentSettings>({
    ...DEFAULT_AGENT_SETTINGS,
  });
  const [guidance, setGuidance] = useState({ instructions: "", memory: "" });
  const [workflows, setWorkflows] = useState<
    Array<{ id: string; title: string; instructions: string }>
  >([]);
  const [runs, setRuns] = useState<AgentRun[]>([]);
  const [queued, setQueued] = useState<string[]>([]);
  const [error, setError] = useState("");
  const [pendingSteering, setPendingSteering] = useState<string[]>([]);
  const active = useRef<NotesAgentRuntime | null>(null);
  const resume = useRef<AgentRun | null>(null);
  const steering = useRef<string[]>([]);
  const update = useCallback(
    (run: AgentRun) =>
      setRuns((previous) =>
        [run, ...previous.filter((item) => item.id !== run.id)].sort((a, b) =>
          b.updatedAt.localeCompare(a.updatedAt),
        ),
      ),
    [],
  );
  useEffect(() => {
    let cancelled = false;
    active.current = null;
    resume.current = null;
    steering.current = [];
    setPendingSteering([]);
    setRuns([]);
    setQueued([]);
    setError("");
    if (backend) {
      void Promise.all([
        loadAgentSettings(backend),
        loadAgentGuidance(backend),
        loadNoteWorkflows(backend),
        chatId ? loadAgentRuns(backend, chatId) : Promise.resolve([]),
      ])
        .then(([settings, guidance, workflows, runs]) => {
          if (!cancelled) {
            setSettings(settings);
            setGuidance(guidance);
            setWorkflows(workflows);
            setRuns((current) =>
              [
                ...current,
                ...runs.filter(
                  (run) => !current.some((item) => item.id === run.id),
                ),
              ].sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)),
            );
          }
        })
        .catch((error) => {
          if (!cancelled) setError(String(error));
        });
    }
    return () => {
      cancelled = true;
    };
  }, [backend, chatId]);
  const changeSettings = async (patch: Partial<AgentSettings>) => {
    const next = normalizeAgentSettings({ ...settings, ...patch });
    setSettings(next);
    try {
      if (backend) await saveAgentSettings(backend, next);
    } catch (error) {
      setError(String(error));
    }
  };
  const saveGuidance = async (
    kind: "memory" | "instructions",
    text: string,
  ) => {
    if (!backend) return;
    await saveAgentGuidance(backend, kind, text);
    setGuidance((current) => ({ ...current, [kind]: text }));
  };
  const start = async (
    port: NotesAgentPort,
    ownerId: string,
    objective: string,
    notes: Note[],
    createTypes: string[],
    modeOverride?: "ask",
    targetChatId?: string,
    signal?: AbortSignal,
    writeTargetId?: string,
  ) => {
    const recovered = resume.current;
    resume.current = null;
    if (recovered?.scopeKey && recovered.scopeKey !== port.scopeKey)
      throw new Error("Restore the saved run context before resuming.");
    if (
      recovered &&
      recovered.readIds.some(
        (id) =>
          !notes.some((note) => note.id === id) &&
          !recovered.receipts.some((receipt) =>
            receipt.after.some((note) => note.id === id),
          ),
      )
    )
      throw new Error(
        "The saved run has a different context. Restore its note context before resuming.",
      );
    const run =
      recovered ??
      createAgentRun(
        targetChatId ?? chatId!,
        ownerId,
        objective,
        { ...settings, ...(modeOverride ? { mode: modeOverride } : {}) },
        notes,
        createTypes,
        writeTargetId,
      );
    if (recovered && settings.writeScope === "current") {
      run.writeIds = run.writeIds.filter((id) => id === writeTargetId);
      run.createTypes = [];
    }
    if (modeOverride || settings.mode === "ask") {
      run.mode = "ask";
      run.writeIds = [];
    }
    run.scopeKey = port.scopeKey;
    run.question = undefined;
    run.status = "running";
    run.ownerId = ownerId;
    const runtime = new NotesAgentRuntime(run, port, update, signal);
    active.current = runtime;
    await runtime.initialize();
    return runtime;
  };
  const interact = async (
    run: AgentRun,
    port: NotesAgentPort,
    action: (runtime: NotesAgentRuntime) => Promise<unknown>,
  ) => {
    setError("");
    const runtime = new NotesAgentRuntime(run, port, update);
    try {
      await action(runtime);
    } catch (error) {
      setError(String(error));
    }
  };
  return {
    settings,
    changeSettings,
    guidance,
    saveGuidance,
    workflows,
    workflow:
      workflows.find((item) => item.id === settings.workflow)?.instructions ??
      "",
    runs,
    error,
    setError,
    active,
    start,
    interact,
    requestResume: (run: AgentRun) => {
      resume.current = run;
    },
    steer: (text: string) => {
      if (text.trim()) {
        steering.current.push(text.trim());
        setPendingSteering([...steering.current]);
      }
    },
    takeSteering: () => {
      const values = steering.current;
      steering.current = [];
      setPendingSteering([]);
      return values;
    },
    pendingSteering,
    queue: (text: string) => {
      if (text.trim()) setQueued((values) => [...values, text.trim()]);
    },
    queued,
    takeQueued: () => {
      const text = queued[0];
      setQueued((values) => values.slice(1));
      return text;
    },
    removeQueued: (index: number) =>
      setQueued((values) => values.filter((_, position) => index !== position)),
  };
}
export type NotesAgentUI = ReturnType<typeof useNotesAgent>;
