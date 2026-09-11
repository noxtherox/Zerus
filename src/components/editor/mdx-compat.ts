import type { RootContent } from "mdast";
import { toMarkdown } from "mdast-util-to-markdown";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import { fromMarkdown } from "mdast-util-from-markdown";
import { mdxJsxFromMarkdown } from "mdast-util-mdx-jsx";
import { mdxJsx } from "micromark-extension-mdx-jsx";
import { mdxMd } from "micromark-extension-mdx-md";
import { unified } from "unified";

const markdownParser = unified().use(remarkParse).use(remarkGfm);

/** MDX disables CommonMark autolinks; convert only actual link nodes. */
function expandAutolinks(source: string): string {
  if (!source.includes("<")) return source;
  const replacements: { start: number; end: number; markdown: string }[] = [];
  function visit(node: RootContent) {
    const start = node.position?.start.offset;
    const end = node.position?.end.offset;
    if (node.type === "link" && start !== undefined && end !== undefined && source[start] === "<") {
      replacements.push({ start, end, markdown: toMarkdown(node, { resourceLink: true }).trimEnd() });
    } else if ("children" in node) {
      node.children.forEach(visit);
    }
  }
  markdownParser.parse(source).children.forEach(visit);
  for (const { start, end, markdown } of replacements.reverse()) {
    source = source.slice(0, start) + markdown + source.slice(end);
  }
  return source;
}

function isEscaped(source: string, at: number): boolean {
  let slashes = 0;
  for (let index = at - 1; index >= 0 && source[index] === "\\"; index -= 1) {
    slashes += 1;
  }
  return slashes % 2 === 1;
}

/** Removes mdast's encoding of invisible trailing spaces outside code fences. */
export function cleanMarkdownFromMdxEditor(source: string): string {
  let fence: { marker: "`" | "~"; length: number } | null = null;

  return source
    .split(/(?<=\n)/u)
    .map((line) => {
      const content = line.replace(/\r?\n$/u, "");
      const newline = line.slice(content.length);
      const fenceMatch = content.match(/^( {0,3})(`{3,}|~{3,})/u);

      if (fenceMatch) {
        const marker = fenceMatch[2][0] as "`" | "~";
        const length = fenceMatch[2].length;
        if (!fence) fence = { marker, length };
        else if (fence.marker === marker && length >= fence.length) fence = null;
        return line;
      }

      if (fence) return line;
      return `${content.replace(/[ \t]*&#x20;$/iu, "")}${newline}`;
    })
    .join("");
}

/**
 * Use CommonMark's node boundaries instead of guessing which characters start
 * JSX. Only prose is escaped: code, destinations, and Markdown syntax retain
 * their original source. Valid HTML remains formatted; malformed HTML is shown
 * literally if the editor's JSX tokenizer cannot parse it.
 */
export function prepareMarkdownForMdxEditor(input: string): string {
  const source = expandAutolinks(cleanMarkdownFromMdxEditor(input));
  const tree = markdownParser.parse(source);

  function prepare(literalHtml: boolean): string {
    const replacements: { start: number; end: number; value: string }[] = [];
    function visit(node: RootContent) {
      const start = node.position?.start.offset;
      const end = node.position?.end.offset;
      if (node.type === "code" && start !== undefined && end !== undefined &&
          !/^[ \t]*(`{3,}|~{3,})/u.test(source.slice(start, end))) {
        // MDX disables indented code. Fences preserve its literal contents.
        const prefix = source.slice(source.lastIndexOf("\n", start - 1) + 1, start)
          .replace(/[^> \t]/gu, " ");
        const value = toMarkdown(node, { fences: true }).trimEnd().replace(/\n/gu, `\n${prefix}`);
        replacements.push({ start, end, value });
      } else if ((node.type === "text" || node.type === "html") && start !== undefined && end !== undefined) {
        const original = source.slice(start, end);
        const value = node.type === "html" && !literalHtml
          ? original.replace(/<br\s*>/giu, "<br />")
          : original.replace(/[<{}]/gu, (character, offset: number) =>
            isEscaped(original, offset) ? character : `\\${character}`);
        if (value !== original) replacements.push({ start, end, value });
      } else if ("children" in node) {
        node.children.forEach(visit);
      }
    }
    tree.children.forEach(visit);
    let result = source;
    for (const { start, end, value } of replacements.reverse()) {
      result = result.slice(0, start) + value + result.slice(end);
    }
    return result;
  }

  const prepared = prepare(false);
  try {
    // Match the HTML syntax extensions enabled by MDXEditor's core plugin.
    fromMarkdown(prepared, {
      extensions: [mdxJsx(), mdxMd()],
      mdastExtensions: [mdxJsxFromMarkdown()],
    });
    return prepared;
  } catch {
    return prepare(true);
  }
}
