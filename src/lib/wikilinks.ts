import type { RootContent } from "mdast";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";

const parser = unified().use(remarkParse).use(remarkGfm);
export const WIKILINK_REGEX = /\\?\[\\?\[([^\][]+)\]\]/g;

/** Transform prose only: examples in code, HTML, and link destinations are literal. */
export function mapWikilinks(
  source: string,
  transform: (reference: string, original: string) => string,
): string {
  const tableRanges: { start: number; end: number }[] = [];
  const protectedRanges: { start: number; end: number }[] = [];
  function visit(node: RootContent) {
    if (node.type === "table" && node.position) tableRanges.push({ start: node.position.start.offset!, end: node.position.end.offset! });
    if (["code", "inlineCode", "html", "link", "linkReference", "image", "imageReference", "definition"].includes(node.type)) {
      if (node.position) {
        protectedRanges.push({ start: node.position.start.offset!, end: node.position.end.offset! });
      }
    } else if ("children" in node) {
      node.children.forEach(visit);
    }
  }
  parser.parse(source).children.forEach(visit);
  return source.replace(WIKILINK_REGEX, (original, reference: string, start: number) => {
    const end = start + original.length;
    if (protectedRanges.some((range) => start < range.end && end > range.start)) return original;
    const value = transform(reference.replace(/\\\|/g, "|").trim(), original);
    return tableRanges.some((range) => start >= range.start && end <= range.end)
      ? value.replace(/(?<!\\)\|/g, "\\|") : value;
  });
}

export function parseNoteReference(reference: string): { target: string; label: string; id: string | null } {
  const inner = reference.trim().replace(/\\\|/g, "|").replace(/^\[\[|\]\]$/g, "");
  const separator = inner.indexOf("|");
  const target = (separator < 0 ? inner : inner.slice(0, separator)).trim();
  const label = (separator < 0 ? target : inner.slice(separator + 1)).trim();
  return { target, label, id: target.startsWith("zerus:") ? target.slice(6) : null };
}
