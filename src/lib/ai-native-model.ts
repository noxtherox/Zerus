import { invoke } from "@tauri-apps/api/core";
import type {
  LanguageModelV4,
  LanguageModelV4CallOptions,
  LanguageModelV4Content,
  LanguageModelV4GenerateResult,
} from "@ai-sdk/provider";
import type { AiProviderConfig } from "./ai-provider-config";
import { parseAiToolResponse, type AiToolCall } from "./ai-tools";

export interface NativeAiMessage {
  role: "user" | "assistant" | "tool";
  content: string;
  images: Array<{ mediaType: string; data: string }>;
  toolCalls?: Array<{ id: string; name: string; arguments: string }>;
  toolCallId?: string;
}
export interface NativeAiRequest {
  systemPrompt: string;
  messages: NativeAiMessage[];
  tools?: Array<{ name: string; description?: string; inputSchema: unknown }>;
  toolChoice?: string;
  maxOutputTokens?: number;
  temperature?: number;
  effort?: string;
}
export interface NativeAiResponse {
  content: string;
  reasoning?: string | null;
  toolCalls?: Array<{ id: string; name: string; arguments: string }>;
  usage?: { inputTokens?: number; outputTokens?: number };
  finishReason?: string;
}
export type NativeAiTransport = (
  request: NativeAiRequest,
  signal?: AbortSignal,
) => Promise<NativeAiResponse>;

/** Native serializers include [] even when a text-only endpoint requests a tool. */
export function nativeAgentToolCalls(
  response: NativeAiResponse,
  textToolCall: AiToolCall | null,
): NonNullable<NativeAiResponse["toolCalls"]> {
  if (response.toolCalls?.length) return response.toolCalls;
  return textToolCall
    ? [
        {
          id: crypto.randomUUID(),
          name: textToolCall.name,
          arguments: JSON.stringify(textToolCall.arguments),
        },
      ]
    : [];
}
const emptyUsage: LanguageModelV4GenerateResult["usage"] = {
  inputTokens: {
    total: undefined,
    noCache: undefined,
    cacheRead: undefined,
    cacheWrite: undefined,
  },
  outputTokens: { total: undefined, text: undefined, reasoning: undefined },
};
export function agentBase64(bytes: Uint8Array) {
  let value = "";
  for (let i = 0; i < bytes.length; i += 0x8000)
    value += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(value);
}
export function nativeImageData(data: unknown): string | null {
  if (typeof data === "string") return data;
  if (data instanceof Uint8Array) return agentBase64(data);
  if (data instanceof ArrayBuffer) return agentBase64(new Uint8Array(data));
  if (
    data &&
    typeof data === "object" &&
    "type" in data &&
    data.type === "data" &&
    "data" in data
  )
    return nativeImageData(data.data);
  return null;
}
function outputText(output: unknown): string {
  if (output && typeof output === "object" && "value" in output)
    return typeof output.value === "string"
      ? output.value
      : JSON.stringify(output.value);
  return JSON.stringify(output);
}
export function nativeAgentRequest(
  options: LanguageModelV4CallOptions,
  fallback = false,
): NativeAiRequest {
  const system: string[] = [];
  const messages: NativeAiMessage[] = [];
  for (const message of options.prompt) {
    if (message.role === "system") {
      system.push(message.content);
      continue;
    }
    if (message.role === "user") {
      const text: string[] = [];
      const images: NativeAiMessage["images"] = [];
      for (const part of message.content) {
        if (part.type === "text") text.push(part.text);
        if (part.type === "file" && part.mediaType.startsWith("image/")) {
          const data = nativeImageData(part.data);
          if (data) images.push({ mediaType: part.mediaType, data });
        }
      }
      messages.push({ role: "user", content: text.join("\n"), images });
      continue;
    }
    if (message.role === "assistant") {
      const text: string[] = [];
      const calls: NonNullable<NativeAiMessage["toolCalls"]> = [];
      for (const part of message.content) {
        if (part.type === "text") text.push(part.text);
        if (part.type === "tool-call") {
          if (fallback)
            text.push(
              `<zerus_tool>${JSON.stringify({ name: part.toolName, arguments: part.input })}</zerus_tool>`,
            );
          else
            calls.push({
              id: part.toolCallId,
              name: part.toolName,
              arguments: JSON.stringify(part.input),
            });
        }
      }
      messages.push({
        role: "assistant",
        content: text.join("\n"),
        images: [],
        ...(calls.length ? { toolCalls: calls } : {}),
      });
      continue;
    }
    for (const part of message.content)
      if (part.type === "tool-result")
        messages.push(
          fallback
            ? {
                role: "user",
                images: [],
                content: `Untrusted tool result for ${part.toolName}:\n${outputText(part.output)}`,
              }
            : {
                role: "tool",
                content: outputText(part.output),
                images: [],
                toolCallId: part.toolCallId,
              },
        );
  }
  const tools = (options.tools ?? [])
    .filter((candidate) => candidate.type === "function")
    .map((candidate) => ({
      name: candidate.name,
      description: candidate.description,
      inputSchema: candidate.inputSchema,
    }));
  if (fallback && tools.length)
    system.push(
      `Use these note tools: ${JSON.stringify(tools)}\nCall at most one tool per response with <zerus_tool>{"name":"tool_name","arguments":{}}</zerus_tool>. Return prose after receiving results. Never claim a staged change was saved. Keep each response within ${options.maxOutputTokens ?? 8192} tokens.`,
    );
  return {
    systemPrompt: system.join("\n\n"),
    messages,
    ...(!fallback && tools.length
      ? {
          tools,
          toolChoice: options.toolChoice?.type === "none" ? "none" : "auto",
        }
      : {}),
    maxOutputTokens: options.maxOutputTokens,
    temperature: options.temperature,
  };
}
export function desktopAgentTransport(
  config: AiProviderConfig,
  streamId: string,
): NativeAiTransport {
  return async (request, signal) => {
    signal?.throwIfAborted();
    const cancel = () => {
      void invoke("cancel_ai_chat", { streamId }).catch(() => {});
    };
    signal?.addEventListener("abort", cancel, { once: true });
    try {
      return await invoke<NativeAiResponse>(
        config.provider === "codex" ? "codex_ai_chat" : "cloud_ai_chat",
        {
          streamId,
          model: config.model,
          ...(config.provider === "codex"
            ? {}
            : { provider: config.provider, baseUrl: config.baseUrl }),
          request,
        },
      );
    } finally {
      signal?.removeEventListener("abort", cancel);
    }
  };
}
export class ZerusNativeLanguageModel implements LanguageModelV4 {
  readonly specificationVersion = "v4";
  readonly provider = "zerus-native";
  readonly supportedUrls = Promise.resolve({});
  constructor(
    readonly modelId: string,
    private transport: NativeAiTransport,
    private fallback = false,
    private start?: () => void,
    private effort?: string,
  ) {}
  async doGenerate(
    options: LanguageModelV4CallOptions,
  ): Promise<LanguageModelV4GenerateResult> {
    options.abortSignal?.throwIfAborted();
    this.start?.();
    const response = await this.transport(
      { ...nativeAgentRequest(options, this.fallback), effort: this.effort },
      options.abortSignal,
    );
    options.abortSignal?.throwIfAborted();
    const content: LanguageModelV4Content[] = [];
    if (response.reasoning?.trim())
      content.push({ type: "reasoning", text: response.reasoning });
    const parsed = this.fallback
      ? parseAiToolResponse(response.content)
      : { content: response.content, toolCall: null, toolError: null };
    if (parsed.toolError) throw new Error(parsed.toolError);
    if (parsed.content) content.push({ type: "text", text: parsed.content });
    const calls = nativeAgentToolCalls(response, parsed.toolCall);
    for (const call of calls)
      content.push({
        type: "tool-call",
        toolCallId: call.id,
        toolName: call.name,
        input: call.arguments,
      });
    const reason = response.finishReason;
    return {
      content,
      finishReason: {
        unified: calls.length
          ? "tool-calls"
          : reason === "length" || reason === "max_tokens"
            ? "length"
            : reason === "content_filter"
              ? "content-filter"
              : "stop",
        raw: reason,
      },
      usage: response.usage
        ? {
            inputTokens: {
              ...emptyUsage.inputTokens,
              total: response.usage.inputTokens,
            },
            outputTokens: {
              ...emptyUsage.outputTokens,
              total: response.usage.outputTokens,
            },
          }
        : emptyUsage,
      warnings: [],
    };
  }
  async doStream(): Promise<never> {
    throw new Error(
      "Native provider events stream text while the shared ToolLoopAgent runs generate().",
    );
  }
}
