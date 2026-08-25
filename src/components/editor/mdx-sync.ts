const MAX_PENDING_ECHOES = 100;
const ECHOES_TO_KEEP_AFTER_TRIM = 50;

/** Records Markdown emitted by the editor until React echoes it back as a prop. */
export function recordLocalMarkdownEcho(queue: string[], markdown: string): void {
  queue.push(markdown);
  if (queue.length > MAX_PENDING_ECHOES) {
    queue.splice(0, queue.length - ECHOES_TO_KEEP_AFTER_TRIM);
  }
}

/** Consumes a locally-produced prop value without treating it as an external edit. */
export function consumeLocalMarkdownEcho(
  queue: string[],
  markdown: string,
): boolean {
  const index = queue.indexOf(markdown);
  if (index < 0) return false;
  queue.splice(0, index + 1);
  return true;
}
