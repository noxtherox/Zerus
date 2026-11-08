import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { RootContent } from "mdast";
import { mapWikilinks, parseNoteReference } from "@/lib/wikilinks";

// A local fragment survives Lexical's URL sanitization and never opens an external page.
const parser = unified().use(remarkParse).use(remarkGfm);
const PREFIX = "#zerus-note:";
function encodeReference(reference: string): string {
  return encodeURIComponent(reference).replace(/[!'()*]/g, character => `%${character.charCodeAt(0).toString(16).toUpperCase()}`);
}
export function noteReferenceFromHref(href: string): string | null {
  if (!href.startsWith(PREFIX)) return null;
  try { return decodeURIComponent(href.slice(PREFIX.length)); } catch { return null; }
}

/** Render readable labels as real editor links while preserving their exact target. */
export function prepareNoteLinks(markdown: string): string {
  return mapWikilinks(markdown, (reference) => {
    const { label } = parseNoteReference(reference);
    return `[${label.replace(/[\\[\]*_`<>&]/g, "\\$&")}](${PREFIX}${encodeReference(reference)})`;
  });
}

export function restoreNoteLinks(markdown: string): string {
  if (!markdown.includes(PREFIX)) return markdown;
  const edits: { start: number; end: number; value: string }[] = [];
  function visit(node: RootContent, inTable = false) {
    inTable ||= node.type === "table";
    if (node.type === "link" && node.position) {
      const reference = noteReferenceFromHref(node.url);
      if (reference !== null) {
        function textContent(child: RootContent): string {
          if (child.type === "text" || child.type === "inlineCode") return child.value;
          if (child.type === "break") return "\n";
          return "children" in child ? child.children.map(textContent).join("") : "";
        }
        const label = node.children.map(textContent).join("");
        const { target, label: previousLabel } = parseNoteReference(reference);
        const next = label === previousLabel ? reference : `${target}|${label}`;
        const formatted = node.children.some(child => child.type !== "text");
        const last = node.children.at(-1)?.position?.end.offset;
        const labelSource = formatted && last !== undefined ? markdown.slice(node.position.start.offset! + 1, last) : label.replace(/[\\[\]*_`~<>&]/g, "\\$&");
        const value = formatted || /[\\[\]|\r\n<>&]/.test(label) || /[\\[\]\r\n]/.test(target)
          ? `[${labelSource}](${PREFIX}${encodeReference(next)})`
          : `[[${next}]]`;
        edits.push({ start: node.position.start.offset!, end: node.position.end.offset!, value: inTable ? value.replace(/(?<!\\)\|/g, "\\|") : value });
      }
    } else if ("children" in node) node.children.forEach((child) => visit(child, inTable));
  }
  parser.parse(markdown).children.forEach((child) => visit(child));
  for (const edit of edits.reverse()) markdown = markdown.slice(0, edit.start) + edit.value + markdown.slice(edit.end);
  return markdown;
}
