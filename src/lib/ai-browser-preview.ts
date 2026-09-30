import type { AiContext } from "./ai-context";

/** A labelled, local-only preview. It never sends notes or credentials to a provider. */
export async function previewChatAnswer(
  context: AiContext,
  signal: AbortSignal,
  onText: (text: string) => void,
): Promise<string> {
  const text = context.sources.length
    ? [
        "This is a **local preview**, showing the note excerpts selected for your question. AI-generated answers are available in the desktop app.",
        ...context.sources.map(
          (source) =>
            `### [${source.title}](zerus-note:${encodeURIComponent(source.noteId)})\n\n${source.excerpt}`,
        ),
      ].join("\n\n")
    : "This is a **local preview**. No notes are included in the current context. Select notes above to try the chat controls.";
  for (let length = 0; length < text.length; length += 60) {
    signal.throwIfAborted();
    onText(text.slice(0, length + 60));
    await new Promise<void>((resolve, reject) => {
      const abort = () => {
        clearTimeout(timer);
        reject(new DOMException("Stopped", "AbortError"));
      };
      const timer = setTimeout(() => {
        signal.removeEventListener("abort", abort);
        resolve();
      }, 30);
      signal.addEventListener("abort", abort, { once: true });
    });
  }
  signal.throwIfAborted();
  return text;
}

/** Exercise the real journal and tools in a clearly labelled offline preview. */
export async function previewNotesAgent(
  runtime: import("./ai-harness").NotesAgentRuntime,
  question: string,
  context: AiContext,
  signal: AbortSignal,
  onText: (text: string) => void,
): Promise<string> {
  const { directAiNoteAction } = await import("./ai-actions");
  const action = directAiNoteAction(question);
  let text: string;
  if (action && context.noteId) {
    await runtime.execute({
      name: "note_get",
      arguments: { selector: context.noteId },
    });
    const call =
      action.type === "append"
        ? {
            name: "note_append" as const,
            arguments: { selector: context.noteId, text: action.text },
          }
        : {
            name: "note_set_body" as const,
            arguments: { selector: context.noteId, body: action.body },
          };
    const result = await runtime.execute(call);
    text = result.ok
      ? runtime.run.receipts.length
        ? "**Local preview:** the requested change was saved and verified. Review or undo it below."
        : "**Local preview:** the requested change is ready for review below. Approve it to save."
      : `**Local preview:** ${(result.result as { error: string }).error}`;
  } else {
    await runtime.execute({ name: "note_list", arguments: { limit: 5 } });
    if (context.noteId)
      await runtime.execute({
        name: "note_get",
        arguments: { selector: context.noteId },
      });
    text = await previewChatAnswer(context, signal, onText);
  }
  runtime.run.status = runtime.run.proposals.some(
    (item) => item.status === "pending",
  )
    ? "waiting"
    : "complete";
  await runtime.event(
    "finished",
    "Offline preview finished. No provider contacted.",
  );
  onText(text);
  return text;
}
