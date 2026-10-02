import {
  createAgentRun,
  NotesAgentRuntime,
  type NotesAgentPort,
} from "./ai-harness";
import type { AgentSettings } from "./ai-harness-state";
import { runZerusAgent } from "./ai-sdk-agent";
import { notesAgentPrompt } from "./ai-harness-prompt";
import {
  desktopAgentTransport,
  type NativeAiTransport,
} from "./ai-native-model";
import type { AiProviderConfig } from "./ai-provider-config";

export function enableNotesWorkers(
  port: NotesAgentPort,
  config: AiProviderConfig,
  settings: AgentSettings,
  chatId: string,
  ownerId: string,
  parent: NotesAgentRuntime,
  transport?: NativeAiTransport,
  signal?: AbortSignal,
  nativeTools?: boolean,
) {
  if (!settings.workers) return;
  port.analyze = async (question, snapshots) => {
    const ids = new Set(snapshots.map((note) => note.id));
    const budget = Math.floor(
      (settings.maxTotalTokens - (parent.run.usage.budgetTokens ?? 0)) / 2,
    );
    if (budget < 4000)
      throw new Error(
        "Insufficient remaining token budget for independent analysis.",
      );
    const children: NotesAgentRuntime[] = [];
    const results = await Promise.allSettled(
      [
        "Find supporting evidence and useful connections.",
        "Independently check contradictions, missing evidence and coverage.",
      ].map(async (angle) => {
        const notes = port.notes().filter((note) => ids.has(note.id));
        const childSettings = {
          ...settings,
          mode: "ask" as const,
          workers: false,
          maxTotalTokens: budget,
          maxSteps: Math.min(8, settings.maxSteps),
          maxMinutes: Math.min(3, settings.maxMinutes),
          maxOutputTokens: Math.min(3000, settings.maxOutputTokens),
        };
        const run = createAgentRun(
          chatId,
          ownerId,
          `${question}\n${angle}`,
          childSettings,
          notes,
          [],
        );
        run.parentRunId = parent.run.id;
        const runtime = new NotesAgentRuntime(
          run,
          { ...port, analyze: undefined },
          undefined,
          signal,
        );
        children.push(runtime);
        await runtime.initialize();
        const result = await runZerusAgent({
          providerConfig: config,
          streamId: crypto.randomUUID(),
          transport:
            transport ?? desktopAgentTransport(config, crypto.randomUUID()),
          nativeTools,
          systemPrompt: notesAgentPrompt(run, { instructions: "", memory: "" }),
          messages: [{ role: "user", content: run.objective }],
          mutationAuthorized: false,
          settings: childSettings,
          runtime,
          executeTool: (call) => runtime.execute(call),
          abortSignal: signal,
        });
        return result.text;
      }),
    );
    for (const child of children) {
      parent.run.usage.inputTokens += child.run.usage.inputTokens;
      parent.run.usage.outputTokens += child.run.usage.outputTokens;
      parent.run.usage.budgetTokens =
        (parent.run.usage.budgetTokens ?? 0) +
        (child.run.usage.budgetTokens ?? 0);
    }
    await parent.event("activity", "Independent read-only analysis finished", {
      runs: children.map((child) => ({
        id: child.run.id,
        status: child.run.status,
        usage: child.run.usage,
      })),
    });
    return results.map((result) =>
      result.status === "fulfilled"
        ? result.value
        : `Analysis interrupted: ${String(result.reason)}`,
    );
  };
}
