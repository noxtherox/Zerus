export function formatMarkdownLink(label: string, url: string): string {
  const safeLabel = label
    .replace(/\\/g, "\\\\")
    .replace(/\[/g, "\\[")
    .replace(/\]/g, "\\]");
  return `[${safeLabel}](${url})`;
}
