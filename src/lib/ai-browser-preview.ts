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
