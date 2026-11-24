import type { RootContent } from "mdast";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";

const parser = unified().use(remarkParse).use(remarkGfm);
export const WIKILINK_REGEX = /\\?\[\\?\[([^\][]+)\]\]/g;

/** Decode only the local fragment used by the native and web rich editors. */
export function noteReferenceFromHref(href: string): string | null {
  if (!href.startsWith("#zerus-note:")) return null;
  try { return decodeURIComponent(href.slice("#zerus-note:".length)); } catch { return null; }
}

type Range = { start: number; end: number };
function markdownRanges(source: string) {
  const tableRanges: Range[] = [], protectedRanges: Range[] = [];
  const fragments: { start: number; reference: string }[] = [];
  const tree = parser.parse(source), definitions = new Map<string, string>();
  function collectDefinitions(node: RootContent) {
    if (node.type === "definition" && !definitions.has(node.identifier)) definitions.set(node.identifier, node.url);
    if ("children" in node) node.children.forEach(collectDefinitions);
  }
  tree.children.forEach(collectDefinitions);
  function visible(node: RootContent): string {
    if (node.type === "text" || node.type === "inlineCode") return node.value;
    if (node.type === "break") return "\n";
    if (node.type === "image" || node.type === "imageReference") return node.alt ?? "";
    return "children" in node ? node.children.map(visible).join("") : "";
  }
  function visit(node: RootContent) {
    if (node.type === "table" && node.position) tableRanges.push({ start: node.position.start.offset!, end: node.position.end.offset! });
    if ((node.type === "link" || node.type === "linkReference") && node.position) {
      const href = node.type === "link" ? node.url : definitions.get(node.identifier);
      const reference = href === undefined ? null : noteReferenceFromHref(href);
      if (reference !== null) {
        const { target } = parseNoteReference(reference);
        if (target) fragments.push({ start: node.position.start.offset!, reference: `${target}|${visible(node)}` });
      }
    }
    if (["code", "inlineCode", "html", "link", "linkReference", "image", "imageReference", "definition"].includes(node.type)) {
      if (node.position) protectedRanges.push({ start: node.position.start.offset!, end: node.position.end.offset! });
    } else if ("children" in node) node.children.forEach(visit);
  }
  tree.children.forEach(visit);
  return { tableRanges, protectedRanges, fragments };
}

/** Transform prose only: examples in code, HTML, and link destinations are literal. */
export function mapWikilinks(source: string, transform: (reference: string, original: string) => string): string {
  if (!/\\?\[\\?\[([^\][]+)\]\]/.test(source)) return source;
  const { tableRanges, protectedRanges } = markdownRanges(source);
  return source.replace(WIKILINK_REGEX, (original, reference: string, start: number) => {
    const end = start + original.length;
    if (protectedRanges.some((range) => start < range.end && end > range.start)) return original;
    const value = transform(reference.replace(/\\\|/g, "|").trim(), original);
    return tableRanges.some((range) => start >= range.start && end <= range.end)
      ? value.replace(/(?<!\\)\|/g, "\\|") : value;
  });
}

/** Body references in reading order, including styled native fragment links. */
export function markdownNoteReferences(source: string): string[] {
  if (!source.includes("#zerus-note:") && !/\\?\[\\?\[([^\][]+)\]\]/.test(source)) return [];
  const { protectedRanges, fragments } = markdownRanges(source);
  const references = [...fragments];
  for (const match of source.matchAll(WIKILINK_REGEX)) {
    const start = match.index, end = start + match[0].length;
    if (!protectedRanges.some(range => start < range.end && end > range.start)) {
      references.push({ start, reference: match[1].replace(/\\\|/g, "|").trim() });
    }
  }
  return references.sort((a, b) => a.start - b.start).map(item => item.reference);
}

export function parseNoteReference(reference: string): { target: string; label: string; id: string | null } {
  const inner = reference.trim().replace(/\\\|/g, "|").replace(/^\[\[|\]\]$/g, "");
  const separator = inner.indexOf("|");
  const target = (separator < 0 ? inner : inner.slice(0, separator)).trim();
  const label = (separator < 0 ? target : inner.slice(separator + 1)).trim();
  return { target, label, id: target.startsWith("zerus:") ? target.slice(6) : null };
}
