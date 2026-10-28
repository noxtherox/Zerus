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

describe.each(["ai-sdk", "pi"] as const)("runZerusAgent (%s)", (engine) => {
  beforeEach(() => {
    vi.mocked(invoke).mockReset();
  });

  it("returns a normal answer through the native model adapter", async () => {
    vi.mocked(invoke).mockResolvedValueOnce({
      content: "Hello from Zerus.",
      reasoning: "Checked the supplied context.",
    });

    const result = await runZerusAgent({
      engine,
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
        maxOutputTokens: 8_192,
      },
    });
  });

  it("retains attached image bytes through later tool steps", async () => {
    vi.mocked(invoke)
      .mockResolvedValueOnce({ content: "", toolCalls: [{ id: "image-search", name: "note_list", arguments: "{}" }] })
      .mockResolvedValueOnce({ content: "Compared the image with your notes." });
    const result = await runZerusAgent({
      engine, providerConfig, streamId: "image", systemPrompt: "Compare the attached image.",
      messages: [{ role: "user", content: [
        { type: "text", text: "Compare this." },
        { type: "file", mediaType: "image/png", data: { type: "data", data: "aW1hZ2U=" } },
      ] }],
      mutationAuthorized: false, executeTool: async () => ({ ok: true, result: [] }),
    });
    expect(result.text).toBe("Compared the image with your notes.");
    for (const [, args] of vi.mocked(invoke).mock.calls) {
      expect(args).toMatchObject({ request: { messages: expect.arrayContaining([
        expect.objectContaining({ role: "user", images: [{ mediaType: "image/png", data: "aW1hZ2U=" }] }),
      ]) } });
    }
  });

  it.each([
    { provider: "openrouter" as const, nativeTools: false },
    { provider: "codex" as const, nativeTools: true },
  ])("executes a Zerus tool and continue ($provider, nativeTools=$nativeTools)", async ({ provider, nativeTools }) => {
    vi.mocked(invoke)
      .mockResolvedValueOnce({
        content: "",
        toolCalls: [
          {
            id: "tool-eval",
            name: "search",
            arguments: '{"query": "Brazil", "limit": 5}',
          },
        ],
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
      engine,
      providerConfig: { ...providerConfig, provider, baseUrl: provider === "codex" ? "codex://chatgpt" : providerConfig.baseUrl },
      nativeTools,
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
      request: { tools: Array<{ name: string; inputSchema: unknown }> };
    };
    expect(
      firstRequest.request.tools.find((tool) => tool.name === "search")
        ?.inputSchema,
    ).toHaveProperty("properties");
    const secondRequest = vi.mocked(invoke).mock.calls[1][1] as {
      request: {
        messages: Array<{ role: string; toolCallId?: string; content: string }>;
      };
    };
    expect(
      secondRequest.request.messages.find((message) => message.role === "tool"),
    ).toMatchObject({ toolCallId: "tool-eval" });
    expect(
      secondRequest.request.messages.find((message) => message.role === "tool")
        ?.content,
    ).toContain("Travel Plans");
  });

  it("lets the agent run a read-only Zerus CLI command", async () => {
    vi.mocked(invoke)
      .mockResolvedValueOnce({
        content: "",
        toolCalls: [
          {
            id: "tool-eval",
            name: "zerus_cli",
            arguments: '{"args": ["note", "list"]}',
          },
        ],
        reasoning: null,
      })
      .mockResolvedValueOnce({
        content: "You have one note.",
        reasoning: null,
      });
    const executeTool = vi.fn().mockResolvedValue({
      ok: true,
      result: { stdout: '{"ok":true}' },
    });

    const result = await runZerusAgent({
      engine,
      providerConfig,
      streamId: "request-cli",
      systemPrompt: "Use the Zerus CLI when useful.",
      messages: [{ role: "user", content: "List my notes." }],
      mutationAuthorized: false,
      executeTool,
    });

    expect(result.text).toBe("You have one note.");
    expect(executeTool).toHaveBeenCalledWith({
      name: "zerus_cli",
      arguments: { args: ["note", "list"] },
    });
  });

  it("refuses a mutating CLI command without current user authorization", async () => {
    vi.mocked(invoke)
      .mockResolvedValueOnce({
        content: "",
        toolCalls: [
          {
            id: "tool-eval",
            name: "zerus_cli",
            arguments: '{"args": ["note", "archive", "--path", "Done.md"]}',
          },
        ],
        reasoning: null,
      })
      .mockResolvedValueOnce({
        content: "I did not archive it.",
        reasoning: null,
      });
    const executeTool = vi.fn();

    const result = await runZerusAgent({
      engine,
      providerConfig,
      streamId: "request-cli-write",
      systemPrompt: "Use the Zerus CLI when useful.",
      messages: [{ role: "user", content: "How do archives work?" }],
      mutationAuthorized: false,
      executeTool,
    });

    expect(result.text).toBe("I did not archive it.");
    expect(executeTool).not.toHaveBeenCalled();
  });

  it("requires previewed consent before any CLI command using --yes", async () => {
    vi.mocked(invoke)
      .mockResolvedValueOnce({
        content: "",
        toolCalls: [
          {
            id: "tool-eval",
            name: "zerus_cli",
            arguments: '{"args": ["saved-link", "delete", "Link 1", "--yes"]}',
          },
        ],
        reasoning: null,
      })
      .mockResolvedValueOnce({
        content: "I asked for confirmation.",
        reasoning: null,
      });
    const executeTool = vi.fn();

    await runZerusAgent({
      engine,
      providerConfig,
      streamId: "request-cli-unconfirmed-destructive",
      systemPrompt: "Preview destructive actions first.",
      messages: [{ role: "user", content: "Delete Link 1." }],
      mutationAuthorized: true,
      executeTool,
    });

    expect(executeTool).not.toHaveBeenCalled();
  });

  it("refuses a legacy CLI mutation bypass even after text consent", async () => {
    vi.mocked(invoke)
      .mockResolvedValueOnce({
        content: "",
        toolCalls: [
          {
            id: "tool-eval",
            name: "zerus_cli",
            arguments: '{"args": ["saved-link", "delete", "Link 1", "--yes"]}',
          },
        ],
        reasoning: null,
      })
      .mockResolvedValueOnce({ content: "Deleted Link 1.", reasoning: null });
    const executeTool = vi.fn().mockResolvedValue({
      ok: true,
      result: { stdout: '{"ok":true}' },
    });

    await runZerusAgent({
      engine,
      providerConfig,
      streamId: "request-cli-confirmed-destructive",
      systemPrompt: "Apply the confirmed action.",
      messages: [{ role: "user", content: "Yes." }],
      mutationAuthorized: false,
      executeTool,
    });

    expect(executeTool).not.toHaveBeenCalled();
  });

  it("refuses a write tool when the current request did not authorize mutation", async () => {
    vi.mocked(invoke)
      .mockResolvedValueOnce({
        content: "",
        toolCalls: [
          {
            id: "tool-eval",
            name: "note_set_body",
            arguments: '{"body": "Injected"}',
          },
        ],
        reasoning: null,
      })
      .mockResolvedValueOnce({
        content: "I did not change the note.",
        reasoning: null,
      });
    const executeTool = vi.fn();

    const result = await runZerusAgent({
      engine,
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
    expect(
      secondRequest.request.messages.some((message) =>
        message.content.includes("did not authorize"),
      ),
    ).toBe(true);
  });

it("does not invoke a provider after a request has been stopped", async () => {
  vi.mocked(invoke).mockReset();
  const controller = new AbortController();
  controller.abort();
  await expect(
    runZerusAgent({
      engine,
      providerConfig,
      streamId: "cancelled",
      systemPrompt: "Test",
      messages: [{ role: "user", content: "hello" }],
      mutationAuthorized: false,
      executeTool: vi.fn(),
      abortSignal: controller.signal,
    }),
  ).rejects.toThrow();
  expect(invoke).not.toHaveBeenCalled();
});

it("cancels the native request and prevents late tool execution", async () => {
  vi.mocked(invoke).mockReset();
  const controller = new AbortController();
  let resolveProvider!: (value: unknown) => void;
  vi.mocked(invoke).mockImplementation((command) =>
    command === "cancel_ai_chat"
      ? Promise.resolve(undefined)
      : new Promise((resolve) => {
          resolveProvider = resolve;
        }),
  );
  const executeTool = vi.fn();
  const pending = runZerusAgent({
      engine,
    providerConfig,
    streamId: "running",
    systemPrompt: "Test",
    messages: [{ role: "user", content: "append" }],
    mutationAuthorized: true,
    executeTool,
    abortSignal: controller.signal,
  });
  await vi.waitFor(() =>
    expect(invoke).toHaveBeenCalledWith("cloud_ai_chat", expect.anything()),
  );
  controller.abort();
  resolveProvider({
    content: "",
    toolCalls: [
      { id: "tool-eval", name: "note_append", arguments: '{"text": "late"}' },
    ],
    reasoning: null,
  });
  await expect(pending).rejects.toThrow();
  expect(invoke).toHaveBeenCalledWith("cancel_ai_chat", {
    streamId: "running",
  });
  expect(executeTool).not.toHaveBeenCalled();
});

it.each([
  { provider: "openrouter" as const, textFallback: true },
  { provider: "codex" as const, textFallback: false },
])("continues text tool calls when $provider returns an empty native tool array", async ({ provider, textFallback }) => {
  vi.mocked(invoke).mockReset();
  vi.mocked(invoke)
    .mockResolvedValueOnce({
      content:
        '<zerus_tool>{"name":"note_get","arguments":{"start":16000,"length":1000}}</zerus_tool>',
      toolCalls: [],
      reasoning: "Deciding on tool usage",
    })
    .mockResolvedValueOnce({ content: "Read the later passage." });
  const executeTool = vi
    .fn()
    .mockResolvedValue({
      ok: true,
      result: { body: "Later passage", nextStart: null },
    });
  const result = await runZerusAgent({
      engine,
    providerConfig: { ...providerConfig, provider },
    streamId: "fallback",
    textFallback,
    systemPrompt: "Read notes",
    messages: [{ role: "user", content: "Read the appendix" }],
    mutationAuthorized: false,
    executeTool,
  });
  expect(executeTool).toHaveBeenCalledWith({
    name: "note_get",
    arguments: { start: 16000, length: 1000 },
  });
  expect(result.text).toBe("Read the later passage.");
  expect(result.diagnostics).toMatchObject({ stepCount: 2, toolCallCount: 1 });
  const first = vi.mocked(invoke).mock.calls[0][1] as {
    request: { tools?: unknown };
  };
  expect(first.request.tools).toBeUndefined();
});

});
