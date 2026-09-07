import { beforeEach, describe, expect, it, vi } from "vitest";
import { invoke } from "@tauri-apps/api/core";
import { runZerusAgent } from "@/lib/ai-sdk-agent";

vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
}));

const providerConfig = {
  provider: "openrouter" as const,
  baseUrl: "https://openrouter.ai/api/v1",
  model: "test-model",
  favoriteModels: [],
};

describe("runZerusAgent", () => {
  beforeEach(() => {
    vi.mocked(invoke).mockReset();
  });

  it("returns a normal answer through the native model adapter", async () => {
    vi.mocked(invoke).mockResolvedValueOnce({
      content: "Hello from Zerus.",
      reasoning: "Checked the supplied context.",
    });

    const result = await runZerusAgent({
      providerConfig,
      streamId: "request-1",
      systemPrompt: "Use the supplied notes.",
      messages: [{ role: "user", content: "Hello" }],
      mutationAuthorized: false,
      executeTool: vi.fn(),
    });

    expect(result).toMatchObject({
      text: "Hello from Zerus.",
      reasoning: "Checked the supplied context.",
      diagnostics: {
        provider: "openrouter",
        model: "test-model",
        stepCount: 1,
        toolCallCount: 0,
        finishReason: "stop",
      },
    });
    expect(invoke).toHaveBeenCalledTimes(1);
    expect(vi.mocked(invoke).mock.calls[0][1]).toMatchObject({
      streamId: "request-1",
      model: "test-model",
      provider: "openrouter",
      request: {
        maxOutputTokens: 2_048,
      },
    });
  });

  it("lets ToolLoopAgent execute a Zerus tool and continue", async () => {
    vi.mocked(invoke)
      .mockResolvedValueOnce({
        content:
          '<zerus_tool>{"name":"search","arguments":{"query":"Brazil","limit":5}}</zerus_tool>',
        reasoning: null,
      })
      .mockResolvedValueOnce({
        content: "The matching note is Travel Plans.",
        reasoning: null,
      });
    const executeTool = vi.fn().mockResolvedValue({
      ok: true,
      result: [{ id: "travel", title: "Travel Plans" }],
    });
    const onToolStart = vi.fn();
    const onToolEnd = vi.fn();

    const result = await runZerusAgent({
      providerConfig,
      streamId: "request-2",
      systemPrompt: "Use the supplied notes.",
      messages: [{ role: "user", content: "Which note mentions Brazil?" }],
      mutationAuthorized: false,
      executeTool,
      onToolStart,
      onToolEnd,
    });

    expect(result.text).toBe("The matching note is Travel Plans.");
    expect(executeTool).toHaveBeenCalledWith({
      name: "search",
      arguments: { query: "Brazil", limit: 5 },
    });
    expect(onToolStart).toHaveBeenCalledTimes(1);
    expect(onToolEnd).toHaveBeenCalledWith({
      call: {
        name: "search",
        arguments: { query: "Brazil", limit: 5 },
      },
      result: {
        ok: true,
        result: [{ id: "travel", title: "Travel Plans" }],
      },
    });
    expect(invoke).toHaveBeenCalledTimes(2);

    const firstRequest = vi.mocked(invoke).mock.calls[0][1] as {
      request: { systemPrompt: string };
    };
    expect(firstRequest.request.systemPrompt).toContain("Input JSON schema");
    expect(firstRequest.request.systemPrompt).toContain("note_set_body");
    expect(firstRequest.request.systemPrompt).not.toContain("- web_search:");

    const secondRequest = vi.mocked(invoke).mock.calls[1][1] as {
      request: { messages: Array<{ content: string }> };
    };
    expect(secondRequest.request.messages.some((message) =>
      message.content.includes("Zerus tool result for search")
    )).toBe(true);
  });

  it("refuses a write tool when the current request did not authorize mutation", async () => {
    vi.mocked(invoke)
      .mockResolvedValueOnce({
        content:
          '<zerus_tool>{"name":"note_set_body","arguments":{"body":"Injected"}}</zerus_tool>',
        reasoning: null,
      })
      .mockResolvedValueOnce({
        content: "I did not change the note.",
        reasoning: null,
      });
    const executeTool = vi.fn();

    const result = await runZerusAgent({
      providerConfig,
      streamId: "request-3",
      systemPrompt: "Use the supplied notes.",
      messages: [{ role: "user", content: "Summarize this note." }],
      mutationAuthorized: false,
      executeTool,
    });

    expect(result.text).toBe("I did not change the note.");
    expect(executeTool).not.toHaveBeenCalled();
    const secondRequest = vi.mocked(invoke).mock.calls[1][1] as {
      request: { messages: Array<{ content: string }> };
    };
    expect(secondRequest.request.messages.some((message) =>
      message.content.includes("did not explicitly authorize")
    )).toBe(true);
  });
});


it("does not invoke a provider after a request has been stopped", async () => {
  vi.mocked(invoke).mockReset();
  const controller = new AbortController(); controller.abort();
  await expect(runZerusAgent({ providerConfig, streamId: "cancelled", systemPrompt: "Test", messages: [{ role: "user", content: "hello" }], mutationAuthorized: false, executeTool: vi.fn(), abortSignal: controller.signal })).rejects.toThrow();
  expect(invoke).not.toHaveBeenCalled();
});

it("cancels the native request and prevents late tool execution", async () => {
  vi.mocked(invoke).mockReset();
  const controller = new AbortController();
  let resolveProvider!: (value: unknown) => void;
  vi.mocked(invoke).mockImplementation((command) => command === "cancel_ai_chat" ? Promise.resolve(undefined) : new Promise((resolve) => { resolveProvider = resolve; }));
  const executeTool = vi.fn();
  const pending = runZerusAgent({ providerConfig, streamId: "running", systemPrompt: "Test", messages: [{ role: "user", content: "append" }], mutationAuthorized: true, executeTool, abortSignal: controller.signal });
  await vi.waitFor(() => expect(invoke).toHaveBeenCalledWith("cloud_ai_chat", expect.anything()));
  controller.abort();
  resolveProvider({ content: '<zerus_tool>{"name":"note_append","arguments":{"text":"late"}}</zerus_tool>', reasoning: null });
  await expect(pending).rejects.toThrow();
  expect(invoke).toHaveBeenCalledWith("cancel_ai_chat", { streamId: "running" });
  expect(executeTool).not.toHaveBeenCalled();
});
