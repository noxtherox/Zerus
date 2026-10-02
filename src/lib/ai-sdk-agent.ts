import type { ModelMessage } from "@ai-sdk/provider-utils";
import { zodSchema } from "@ai-sdk/provider-utils";
import { ToolLoopAgent, stepCountIs, tool } from "ai";
import type { AiProviderConfig } from "./ai-provider-config";
import {
  DEFAULT_ZERUS_AGENT_CONFIG,
  ZERUS_AGENT_PROMPT_VERSION,
  type ZerusAgentConfig,
} from "./ai-agent-policy";
import type { AiToolResult } from "./ai-tools";
import {
  AI_MUTATION_TOOLS,
  AI_TOOL_DESCRIPTIONS,
  AI_TOOL_SCHEMAS,
  validateAiToolCall,
  type AiToolCall,
  type AiToolName,
} from "./ai-tool-schemas";
import {
  desktopAgentTransport,
  ZerusNativeLanguageModel,
  type NativeAiTransport,
} from "./ai-native-model";
import {
  compactAgentContext,
  agentTokenCounter,
  agentContextText,
} from "./ai-harness-context";
import type { NotesAgentRuntime } from "./ai-harness";
import type { AgentSettings } from "./ai-harness-state";

export interface ZerusAgentToolEvent {
  call: AiToolCall;
  result?: AiToolResult;
}
export interface RunZerusAgentOptions {
  providerConfig: AiProviderConfig;
  streamId: string;
  systemPrompt: string;
  messages: ModelMessage[];
  mutationAuthorized: boolean;
  abortSignal?: AbortSignal;
  onStepStart?: () => void;
  config?: ZerusAgentConfig;
  executeTool: (call: AiToolCall) => Promise<AiToolResult> | AiToolResult;
  onToolStart?: (event: ZerusAgentToolEvent) => void;
  onToolEnd?: (event: ZerusAgentToolEvent) => void;
  transport?: NativeAiTransport;
  nativeTools?: boolean;
  textFallback?: boolean;
  runtime?: NotesAgentRuntime;
  settings?: AgentSettings;
  takeSteering?: () => string[];
}
export interface ZerusAgentResult {
  text: string;
  reasoning: string | null;
  diagnostics: {
    promptVersion: string;
    provider: string;
    model: string;
    stepCount: number;
    toolCallCount: number;
    finishReason: string;
    inputTokens?: number;
    outputTokens?: number;
    elapsedMs: number;
    status: string;
  };
}
export function isReadOnlyCliCall(args: string[]): boolean {
  if (
    args.some(
      (arg) =>
        arg === "--vault" || arg.startsWith("--vault=") || arg === "--yes",
    )
  )
    return false;
  if (
    args.includes("--help") ||
    args.includes("-h") ||
    args.includes("--version") ||
    args.includes("-V")
  )
    return true;
  const [command, subcommand, leaf] = args.filter(
    (arg) => !arg.startsWith("-"),
  );
  return (
    ["search", "links", "history", "doctor"].includes(command) ||
    (command === "note" &&
      (["list", "get"].includes(subcommand) ||
        (subcommand === "property" && leaf === "list"))) ||
    (command === "type" &&
      (subcommand === "list" ||
        (["icon", "view"].includes(subcommand) && leaf === "get"))) ||
    (command === "schema" && subcommand === "list")
  );
}
export async function runZerusAgent(
  options: RunZerusAgentOptions,
): Promise<ZerusAgentResult> {
  const settings = options.settings;
  const config = options.config ?? DEFAULT_ZERUS_AGENT_CONFIG;
  const runtime = options.runtime;
  const maxSteps = settings?.maxSteps ?? config.maxSteps;
  const started = Date.now();
  const timeout = AbortSignal.timeout((settings?.maxMinutes ?? 10) * 60_000);
  const signal = options.abortSignal
    ? AbortSignal.any([options.abortSignal, timeout])
    : timeout;
  const providerTransport =
    options.transport ??
    desktopAgentTransport(options.providerConfig, options.streamId);
  const previousElapsed = runtime?.run.usage.elapsedMs ?? 0;
  let failedRepeated = 0;
  let lastFailure = "";
  let steps = 0;
  let totalCalls = 0;
  let inputTokens: number | undefined;
  let outputTokens: number | undefined;
  let budgetTokens = runtime?.run.usage.budgetTokens ?? 0;
  let preparedInput = 0;
  const spent = () => runtime?.run.usage.budgetTokens ?? budgetTokens;
  async function execute(call: AiToolCall): Promise<AiToolResult> {
    signal.throwIfAborted();
    options.onToolStart?.({ call });
    const mutation =
      AI_MUTATION_TOOLS.has(call.name) ||
      (call.name === "zerus_cli" && !isReadOnlyCliCall(call.arguments.args));
    const result =
      call.name === "zerus_cli" && !isReadOnlyCliCall(call.arguments.args)
        ? {
            ok: false,
            result: {
              error:
                "Use the dedicated scoped note tools for all changes. CLI mutation bypasses are disabled.",
            },
          }
        : mutation && !options.mutationAuthorized
          ? {
              ok: false,
              result: {
                error:
                  "The current user request did not authorize note changes.",
              },
            }
          : await options.executeTool(call);
    const failure = result.ok ? "" : JSON.stringify({ call, result });
    failedRepeated =
      failure && failure === lastFailure ? failedRepeated + 1 : failure ? 1 : 0;
    lastFailure = failure;
    options.onToolEnd?.({ call, result });
    return result;
  }
  const tools = Object.fromEntries(
    (Object.keys(AI_TOOL_SCHEMAS) as AiToolName[]).map((name) => [
      name,
      tool({
        description: AI_TOOL_DESCRIPTIONS[name],
        inputSchema: AI_TOOL_SCHEMAS[name],
        execute: (input: unknown) => execute(validateAiToolCall(name, input)),
      }),
    ]),
  );
  const count = await agentTokenCounter();
  const toolSchemas = await Promise.all(
    (Object.keys(AI_TOOL_SCHEMAS) as AiToolName[]).map(async (name) => ({
      name,
      description: AI_TOOL_DESCRIPTIONS[name],
      inputSchema: await zodSchema(AI_TOOL_SCHEMAS[name]).jsonSchema,
    })),
  );
  const transport: NativeAiTransport = async (request, requestSignal) => {
    requestSignal?.throwIfAborted();
    const estimate =
      count(
        JSON.stringify(request, (key, value) =>
          key === "images" && Array.isArray(value)
            ? value.map((image) => ({ mediaType: image.mediaType }))
            : value,
        ),
      ) +
      request.messages.reduce(
        (sum, message) => sum + message.images.length * 4096,
        0,
      );
    const remaining = (settings?.maxTotalTokens ?? 160000) - spent();
    if (remaining - estimate < 1000)
      throw new Error(
        "The remaining run token budget cannot fit another model call. Resume with a larger budget or a narrower context.",
      );
    const result = await providerTransport(
      {
        ...request,
        maxOutputTokens: Math.min(
          request.maxOutputTokens ??
            settings?.maxOutputTokens ??
            config.maxOutputTokens,
          remaining - estimate,
        ),
      },
      requestSignal,
    );
    budgetTokens =
      spent() +
      (result.usage?.inputTokens ?? estimate) +
      (result.usage?.outputTokens ??
        count(
          result.content +
            (result.reasoning ?? "") +
            JSON.stringify(result.toolCalls ?? []),
        ));
    if (runtime) {
      runtime.run.usage.budgetTokens = budgetTokens;
      runtime.run.usage.inputTokens += result.usage?.inputTokens ?? 0;
      runtime.run.usage.outputTokens += result.usage?.outputTokens ?? 0;
      await runtime.save();
    }
    return result;
  };
  const instructions = options.systemPrompt;
  const reserved =
    count(instructions + JSON.stringify(toolSchemas)) +
    (settings?.maxOutputTokens ?? config.maxOutputTokens) +
    2000;
  const limit = (settings?.maxInputTokens ?? 48000) - reserved;
  if (limit < 1500) {
    const message =
      "The input budget is too small for instructions, tools and the selected output budget.";
    if (runtime) {
      runtime.run.status = "interrupted";
      await runtime.event("error", message);
    }
    throw new Error(message);
  }
  const agent = new ToolLoopAgent({
    model: new ZerusNativeLanguageModel(
      options.providerConfig.model,
      transport,
      (options.providerConfig.provider === "codex" && !options.nativeTools) ||
        options.textFallback === true,
      options.onStepStart,
      settings?.effort,
    ),
    instructions,
    maxOutputTokens: settings?.maxOutputTokens ?? config.maxOutputTokens,
    ...(config.temperature === undefined
      ? {}
      : { temperature: config.temperature }),
    tools,
    stopWhen: [
      stepCountIs(maxSteps),
      () =>
        failedRepeated >= 3 ||
        Boolean(runtime?.run.question) ||
        steps >= maxSteps ||
        spent() >= (settings?.maxTotalTokens ?? 160000),
    ],
    prepareStep: async ({ messages }) => {
      signal.throwIfAborted();
      if ((settings?.maxTotalTokens ?? 160000) - spent() < 1000)
        throw new Error(
          "The run reached its token budget. Saved work can be resumed.",
        );
      const steering = options.takeSteering?.() ?? [];
      for (const text of steering) {
        messages = [...messages, { role: "user", content: text }];
        await runtime?.event("steering", text);
      }
      const compacted = runtime
        ? await compactAgentContext(
            messages,
            limit,
            runtime.run,
            transport,
            signal,
          )
        : { messages, compacted: false };
      const remaining = (settings?.maxTotalTokens ?? 160000) - spent();
      preparedInput =
        count(
          instructions +
            JSON.stringify(toolSchemas) +
            agentContextText(compacted.messages),
        ) +
        compacted.messages.reduce(
          (sum, message) =>
            sum +
            (Array.isArray(message.content)
              ? message.content.filter((part) => part.type === "file").length *
                4096
              : 0),
          0,
        );
      if (preparedInput + 1000 > remaining)
        throw new Error(
          "The remaining run token budget cannot fit the next step. Resume with a larger budget or a narrower context.",
        );
      if (runtime) {
        runtime.run.messages = compacted.messages;
        if (compacted.compacted)
          await runtime.event(
            "compacted",
            "Archived older context; retained objective, permissions, plan and saved changes.",
            { archivedMessages: messages },
          );
        else await runtime.save();
      }
      return {
        messages: compacted.messages,
        maxOutputTokens: Math.min(
          settings?.maxOutputTokens ?? config.maxOutputTokens,
          remaining - preparedInput,
        ),
      };
    },
    onStepEnd: async (step) => {
      steps++;
      totalCalls += step.toolCalls.length;
      if (step.usage.inputTokens !== undefined)
        inputTokens = (inputTokens ?? 0) + step.usage.inputTokens;
      if (step.usage.outputTokens !== undefined)
        outputTokens = (outputTokens ?? 0) + step.usage.outputTokens;
      if (runtime) {
        runtime.run.usage.steps++;
        runtime.run.usage.elapsedMs = previousElapsed + Date.now() - started;
        runtime.run.messages = [
          ...(runtime.run.messages as ModelMessage[]),
          ...step.response.messages,
        ];
        await runtime.event(
          "activity",
          `Step ${steps}: ${step.toolCalls.length ? step.toolCalls.map((call) => call.toolName).join(", ") : "answer"}`,
          { finishReason: step.finishReason, usage: step.usage },
        );
      }
    },
  });
  try {
    let messages = options.messages;
    let result = await agent.generate({ messages, abortSignal: signal });
    // A final answer with unfinished plan items triggers a bounded continuation.
    for (
      let retry = 0;
      runtime &&
      retry < 2 &&
      steps < maxSteps &&
      failedRepeated < 3 &&
      !runtime.run.question &&
      !runtime.run.proposals.some((item) => item.status === "pending") &&
      runtime.run.plan.some((item) => item.status !== "complete") &&
      result.finishReason === "stop";
      retry++
    ) {
      messages = [
        ...messages,
        ...result.response.messages,
        {
          role: "user",
          content:
            "The saved plan still has unfinished steps. Continue the requested work within the existing permissions, or explain a concrete blocker. Verify before marking steps complete.",
        },
      ];
      result = await agent.generate({ messages, abortSignal: signal });
    }
    const status =
      runtime?.run.question ||
      runtime?.run.proposals.some((item) =>
        ["pending", "approved", "applying", "conflict"].includes(item.status),
      )
        ? "waiting"
        : steps >= maxSteps ||
            spent() >= (settings?.maxTotalTokens ?? 160000) ||
            failedRepeated >= 3 ||
            result.finishReason !== "stop" ||
            runtime?.run.plan.some((item) => item.status !== "complete")
          ? "partial"
          : "complete";
    if (runtime) {
      runtime.run.status = status;
      await runtime.event(
        "finished",
        status === "complete"
          ? "Run finished"
          : status === "waiting"
            ? "Waiting for review or an answer"
            : "Run stopped with unfinished work",
        { finishReason: result.finishReason },
      );
    }
    const text =
      result.text ||
      (status === "waiting"
        ? (runtime?.run.question?.question ??
          "Changes are ready for review below.")
        : status === "partial"
          ? "The run reached a limit with work remaining. Review the activity and resume to continue."
          : "Finished. Review the verified changes below.");
    return {
      text,
      reasoning: result.finalStep.reasoningText ?? null,
      diagnostics: {
        promptVersion: ZERUS_AGENT_PROMPT_VERSION,
        provider: options.providerConfig.provider,
        model: options.providerConfig.model,
        stepCount: steps,
        toolCallCount: totalCalls,
        finishReason: result.finishReason,
        inputTokens,
        outputTokens,
        elapsedMs: Date.now() - started,
        status,
      },
    };
  } catch (error) {
    if (runtime) {
      runtime.run.status = "interrupted";
      runtime.run.usage.elapsedMs = previousElapsed + Date.now() - started;
      await runtime.event(
        "error",
        signal.aborted
          ? "Run interrupted. Saved changes and proposals remain available."
          : String(error),
      );
    }
    throw error;
  }
}
