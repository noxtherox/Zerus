import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { RootContent } from "mdast";
import { mapWikilinks, parseNoteReference } from "@/lib/wikilinks";

// A local fragment survives Lexical's URL sanitization and never opens an external page.
const PREFIX = "#zerus-note:";
export function noteReferenceFromHref(href: string): string | null {
  if (!href.startsWith(PREFIX)) return null;
  try { return decodeURIComponent(href.slice(PREFIX.length)); } catch { return null; }
}

/** Render readable labels as real editor links while preserving their exact target. */
export function prepareNoteLinks(markdown: string): string {
  return mapWikilinks(markdown, (reference) => {
    const { label } = parseNoteReference(reference);
    return `[${label.replace(/[\\[\]*_`]/g, "\\$&")}](${PREFIX}${encodeURIComponent(reference)})`;
  });
}

export function restoreNoteLinks(markdown: string): string {
  const edits: { start: number; end: number; value: string }[] = [];
  function visit(node: RootContent, inTable = false) {
    inTable ||= node.type === "table";
    if (node.type === "link" && node.position) {
      const reference = noteReferenceFromHref(node.url);
      if (reference !== null) {
        const label = node.children.map((child) => "value" in child ? child.value : "").join("");
        const { target, label: previousLabel } = parseNoteReference(reference);
        const next = label === previousLabel ? reference : `${target}|${label}`;
        edits.push({ start: node.position.start.offset!, end: node.position.end.offset!, value: `[[${inTable ? next.replace(/(?<!\\)\|/g, "\\|") : next}]]` });
      }
    } else if ("children" in node) node.children.forEach((child) => visit(child, inTable));
  }
  unified().use(remarkParse).use(remarkGfm).parse(markdown).children.forEach((child) => visit(child));
  for (const edit of edits.reverse()) markdown = markdown.slice(0, edit.start) + edit.value + markdown.slice(edit.end);
  return markdown;
}
