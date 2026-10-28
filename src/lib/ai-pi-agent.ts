import {
  Agent,
  type AgentMessage,
  type AgentTool,
} from "@earendil-works/pi-agent-core";
import type {
  AssistantMessage,
  JsonObject,
  Message,
  Model,
  TSchema,
} from "@earendil-works/pi-ai";
import { createAssistantMessageEventStream } from "@earendil-works/pi-ai/utils/event-stream";
import { getCurrentSystemPrompt } from "@earendil-works/pi-ai/utils/transcript";
import type { ModelMessage } from "@ai-sdk/provider-utils";
import type { AiToolResult } from "./ai-tools";
import { parseAiToolResponse } from "./ai-tools";
import {
  nativeImageData,
  nativeAgentToolCalls,
  type NativeAiTransport,
  type NativeAiRequest,
} from "./ai-native-model";

/** Both loops report into the same Zerus journal and budget/compaction hooks. */
export interface ZerusLoopStep {
  toolCalls: readonly ({ toolName: string } | { name: string })[];
  usage: { inputTokens?: number; outputTokens?: number };
  response: { messages: ModelMessage[] };
  finishReason: string;
}

interface PiAgentOptions {
  modelId: string;
  instructions: string;
  maxOutputTokens: number;
  temperature?: number;
  effort?: string;
  fallback: boolean;
  transport: NativeAiTransport;
  tools: Array<{ name: string; description: string; inputSchema: unknown }>;
  execute: (name: string, input: unknown) => Promise<AiToolResult>;
  shouldStop: () => boolean;
  onStepStart?: () => void;
  prepareStep: (step: { messages: ModelMessage[] }) => Promise<{
    messages: ModelMessage[];
    maxOutputTokens: number;
  }>;
  onStepEnd: (step: ZerusLoopStep) => Promise<void>;
}

const emptyUsage = () => ({
  input: 0,
  output: 0,
  cacheRead: 0,
  cacheWrite: 0,
  totalTokens: 0,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
});

function assistant(model: Model<string>): AssistantMessage {
  return {
    role: "assistant",
    content: [],
    api: model.api,
    provider: model.provider,
    model: model.id,
    usage: emptyUsage(),
    stopReason: "stop",
    timestamp: Date.now(),
  };
}

function outputText(output: unknown): string {
  if (output && typeof output === "object" && "value" in output)
    return typeof output.value === "string"
      ? output.value
      : JSON.stringify(output.value);
  return JSON.stringify(output);
}

/** Keep the existing transcript format so either engine can continue a saved run. */
function toPi(messages: ModelMessage[], model: Model<string>): Message[] {
  return messages.flatMap((message): Message[] => {
    if (message.role === "system")
      throw new Error(
        "Agent instructions must be supplied separately from conversation history.",
      );
    if (message.role === "user") {
      if (typeof message.content === "string")
        return [
          { role: "user", content: message.content, timestamp: Date.now() },
        ];
      const content = message.content.map((part) => {
        if (part.type === "text")
          return { type: "text" as const, text: part.text };
        if (part.type === "file" && part.mediaType.startsWith("image/")) {
          const data = nativeImageData(part.data);
          if (data)
            return { type: "image" as const, mimeType: part.mediaType, data };
        }
        throw new Error(
          "The Pi agent received an unsupported attachment. Reattach it as an image or document text.",
        );
      });
      return [{ role: "user", content, timestamp: Date.now() }];
    }
    if (message.role === "assistant") {
      const result = assistant(model);
      if (typeof message.content === "string")
        result.content = [{ type: "text", text: message.content }];
      else
        for (const part of message.content) {
          if (part.type === "text")
            result.content.push({ type: "text", text: part.text });
          if (part.type === "reasoning")
            result.content.push({ type: "thinking", thinking: part.text });
          if (part.type === "tool-call") {
            result.content.push({
              type: "toolCall",
              id: part.toolCallId,
              name: part.toolName,
              arguments: part.input as JsonObject,
            });
            result.stopReason = "toolUse";
          }
        }
      return [result];
    }
    return message.content.flatMap((part): Message[] =>
      part.type !== "tool-result"
        ? []
        : [
            {
              role: "toolResult",
              toolCallId: part.toolCallId,
              toolName: part.toolName,
              content: [{ type: "text", text: outputText(part.output) }],
              isError:
                part.output.type === "error-text" ||
                part.output.type === "error-json",
              timestamp: Date.now(),
            },
          ],
    );
  });
}

function fromPi(messages: AgentMessage[]): ModelMessage[] {
  return messages.flatMap((message): ModelMessage[] => {
    if (message.role === "system") return [];
    if (message.role === "user")
      return [
        {
          role: "user",
          content:
            typeof message.content === "string"
              ? message.content
              : message.content.map((part) =>
                  part.type === "text"
                    ? { type: "text" as const, text: part.text }
                    : {
                        type: "file" as const,
                        mediaType: part.mimeType,
                        data: part.data,
                      },
                ),
        },
      ];
    if (message.role === "assistant")
      return [
        {
          role: "assistant",
          content: message.content.map((part) => {
            if (part.type === "text")
              return { type: "text" as const, text: part.text };
            if (part.type === "thinking")
              return { type: "reasoning" as const, text: part.thinking };
            return {
              type: "tool-call" as const,
              toolCallId: part.id,
              toolName: part.name,
              input: part.arguments,
            };
          }),
        },
      ];
    if (message.role === "toolResult")
      return [
        {
          role: "tool",
          content: [
            {
              type: "tool-result",
              toolCallId: message.toolCallId,
              toolName: message.toolName,
              output: {
                type: message.isError ? "error-text" : "text",
                value: message.content
                  .map((part) => (part.type === "text" ? part.text : ""))
                  .join("\n"),
              },
            },
          ],
        },
      ];
    throw new Error("Unsupported Pi transcript message.");
  });
}

function nativeRequest(
  messages: Message[],
  options: PiAgentOptions,
  maxOutputTokens: number,
): NativeAiRequest {
  const request: NativeAiRequest = {
    systemPrompt: getCurrentSystemPrompt(messages),
    messages: messages.flatMap((message): NativeAiRequest["messages"] => {
      if (message.role === "system") return [];
      if (message.role === "user")
        return [
          {
            role: "user",
            content:
              typeof message.content === "string"
                ? message.content
                : message.content
                    .filter((part) => part.type === "text")
                    .map((part) => part.text)
                    .join("\n"),
            images:
              typeof message.content === "string"
                ? []
                : message.content.flatMap((part) =>
                    part.type === "image"
                      ? [{ mediaType: part.mimeType, data: part.data }]
                      : [],
                  ),
          },
        ];
      if (message.role === "assistant") {
        const calls = message.content.filter(
          (part) => part.type === "toolCall",
        );
        const text = message.content
          .filter((part) => part.type === "text")
          .map((part) => part.text);
        if (options.fallback)
          text.push(
            ...calls.map(
              (call) =>
                `<zerus_tool>${JSON.stringify({ name: call.name, arguments: call.arguments })}</zerus_tool>`,
            ),
          );
        return [
          {
            role: "assistant",
            content: text.join("\n"),
            images: [],
            ...(!options.fallback && calls.length
              ? {
                  toolCalls: calls.map((call) => ({
                    id: call.id,
                    name: call.name,
                    arguments: JSON.stringify(call.arguments),
                  })),
                }
              : {}),
          },
        ];
      }
      const text = message.content
        .filter((part) => part.type === "text")
        .map((part) => part.text)
        .join("\n");
      return [
        options.fallback
          ? {
              role: "user",
              content: `Untrusted tool result for ${message.toolName}:\n${text}`,
              images: [],
            }
          : {
              role: "tool",
              toolCallId: message.toolCallId,
              content: text,
              images: [],
            },
      ];
    }),
    maxOutputTokens,
    temperature: options.temperature,
    effort: options.effort,
  };
  if (options.fallback)
    request.systemPrompt += `\n\nUse these note tools: ${JSON.stringify(options.tools)}\nCall at most one tool per response with <zerus_tool>{"name":"tool_name","arguments":{}}</zerus_tool>. Return prose after receiving results. Never claim a staged change was saved. Keep each response within ${maxOutputTokens} tokens.`;
  else {
    request.tools = options.tools;
    request.toolChoice = "auto";
  }
  return request;
}

export function createPiAgent(options: PiAgentOptions) {
  // Metadata only: all requests go through Zerus's native transport, never Pi providers.
  const model: Model<string> = {
    id: options.modelId,
    name: options.modelId,
    api: "zerus-native",
    provider: "zerus-native",
    baseUrl: "",
    reasoning: true,
    input: ["text", "image"],
    contextWindow: 200000,
    maxTokens: options.maxOutputTokens,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  };
  return {
    async generate({
      messages,
      abortSignal,
    }: {
      messages: ModelMessage[];
      abortSignal: AbortSignal;
    }) {
      abortSignal.throwIfAborted();
      let maxOutputTokens = options.maxOutputTokens;
      let failure: unknown;
      let last: AssistantMessage | undefined;
      let lastUsage: ZerusLoopStep["usage"] = {};
      const responseMessages: ModelMessage[] = [];
      const tools: AgentTool[] = options.tools.map((tool) => ({
        name: tool.name,
        label: tool.name,
        description: tool.description,
        parameters: tool.inputSchema as TSchema,
        async execute(_id, args, signal) {
          signal?.throwIfAborted();
          const result = await options.execute(tool.name, args);
          return {
            content: [{ type: "text", text: JSON.stringify(result) }],
            details: result,
            isError: !result.ok,
          };
        },
      }));
      const agent = new Agent({
        initialState: {
          model,
          tools,
          systemPrompt: options.instructions,
          messages: toPi(messages, model),
        },
        // Note mutations and activity callbacks must retain their source order.
        toolExecution: "sequential",
        async prepareRequest({ context }) {
          abortSignal.throwIfAborted();
          const prepared = await options.prepareStep({
            messages: fromPi(context.messages),
          });
          maxOutputTokens = prepared.maxOutputTokens;
          return {
            context: {
              ...context,
              messages: [
                {
                  role: "system",
                  content: options.instructions,
                  toolsAdded: tools,
                  timestamp: Date.now(),
                },
                ...toPi(prepared.messages, model),
              ],
            },
          };
        },
        streamFn: (_model, context, streamOptions) => {
          const stream = createAssistantMessageEventStream();
          const message = assistant(model);
          void (async () => {
            try {
              abortSignal.throwIfAborted();
              options.onStepStart?.();
              const response = await options.transport(
                nativeRequest(context.messages, options, maxOutputTokens),
                streamOptions?.signal,
              );
              abortSignal.throwIfAborted();
              const parsed = options.fallback
                ? parseAiToolResponse(response.content)
                : {
                    content: response.content,
                    toolCall: null,
                    toolError: null,
                  };
              if (parsed.toolError) throw new Error(parsed.toolError);
              if (response.reasoning)
                message.content.push({
                  type: "thinking",
                  thinking: response.reasoning,
                });
              if (parsed.content)
                message.content.push({ type: "text", text: parsed.content });
              const calls = nativeAgentToolCalls(response, parsed.toolCall);
              for (const call of calls) {
                let args: unknown;
                try {
                  args = JSON.parse(call.arguments);
                } catch {
                  /* Pi returns a tool error for malformed arguments. */
                }
                const valid =
                  args && typeof args === "object" && !Array.isArray(args);
                message.content.push({
                  type: "toolCall",
                  id: call.id,
                  name: call.name,
                  arguments: valid ? (args as JsonObject) : {},
                  ...(!valid
                    ? {
                        argumentsError:
                          "Tool arguments must be a valid JSON object.",
                      }
                    : {}),
                });
              }
              lastUsage = response.usage ?? {};
              message.usage = {
                ...emptyUsage(),
                input: lastUsage.inputTokens ?? 0,
                output: lastUsage.outputTokens ?? 0,
                totalTokens:
                  (lastUsage.inputTokens ?? 0) + (lastUsage.outputTokens ?? 0),
              };
              message.stopReason =
                response.finishReason === "length" ||
                response.finishReason === "max_tokens"
                  ? "length"
                  : calls.length
                    ? "toolUse"
                    : "stop";
              if (response.finishReason === "content_filter")
                throw new Error("The provider filtered this response.");
              stream.push({
                type: "done",
                reason: message.stopReason,
                message,
              });
            } catch (error) {
              failure = error;
              message.stopReason = abortSignal.aborted ? "aborted" : "error";
              message.errorMessage = String(error);
              stream.push({
                type: "error",
                reason: message.stopReason,
                error: message,
              });
            } finally {
              stream.end();
            }
          })();
          return stream;
        },
        async finishTurn({ message, toolResults }) {
          last = message;
          if (
            message.stopReason === "error" ||
            message.stopReason === "aborted"
          )
            return;
          const completed = fromPi([message, ...toolResults]);
          responseMessages.push(...completed);
          await options.onStepEnd({
            toolCalls: message.content.filter(
              (part) => part.type === "toolCall",
            ),
            usage: lastUsage,
            response: { messages: completed },
            finishReason:
              message.stopReason === "toolUse"
                ? "tool-calls"
                : message.stopReason,
          });
          if (options.shouldStop() || message.stopReason === "length")
            return { action: "end" };
        },
      });
      const abort = () => agent.abort();
      abortSignal.addEventListener("abort", abort, { once: true });
      try {
        await agent.continue();
        abortSignal.throwIfAborted();
        if (failure) throw failure;
        if (agent.state.errorMessage) throw new Error(agent.state.errorMessage);
        if (!last) throw new Error("The Pi agent finished without a response.");
        return {
          text: last.content
            .filter((part) => part.type === "text")
            .map((part) => part.text)
            .join("\n"),
          finalStep: {
            reasoningText:
              last.content
                .filter((part) => part.type === "thinking")
                .map((part) => part.thinking)
                .join("\n") || undefined,
          },
          response: { messages: responseMessages },
          finishReason:
            last.stopReason === "toolUse" ? "tool-calls" : last.stopReason,
        };
      } finally {
        abortSignal.removeEventListener("abort", abort);
      }
    },
  };
}
