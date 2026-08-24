import { renderToStaticMarkup } from "react-dom/server";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { EditorView } from "@codemirror/view";
import { ZERUS_MARKDOWN_CLIPBOARD_TYPE } from "./paste-options";
import {
  markdownEscapeUnits,
  transformPreservingMarkdownEscapes,
} from "@/lib/markdown-escapes";
import { deleteCleanSelection } from "./live-preview";

function withDocumentTitle(markdown: string) {
  const lineBreak = markdown.indexOf("\n");
  const firstLine = lineBreak === -1 ? markdown : markdown.slice(0, lineBreak);
  if (!firstLine.trim() || /^\s{0,3}#{1,6}(?:\s|$)/.test(firstLine)) {
    return markdown;
  }

  return lineBreak === -1
    ? `# ${markdown}`
    : `# ${firstLine}${markdown.slice(lineBreak)}`;
}

export function richCopyHtml(
  markdown: string,
  options: { includeDocumentTitle?: boolean } = {},
) {
  const source = options.includeDocumentTitle
    ? withDocumentTitle(markdown)
    : markdown;

  return renderToStaticMarkup(
    <ReactMarkdown remarkPlugins={[remarkGfm]}>{source}</ReactMarkdown>,
  );
}

/** Produce the readable fallback used by apps that only accept plain text. */
export function readableCopyText(markdown: string): string {
  let inFence = false;
  const lines = markdown.replace(/\r\n?/g, "\n").split("\n");
  const readable = lines.flatMap((sourceLine) => {
    if (/^\s{0,3}(?:```|~~~)/.test(sourceLine)) {
      inFence = !inFence;
      return [];
    }
    if (inFence) return [sourceLine];
    if (/^\s*\|?\s*:?-{3,}/.test(sourceLine)) return [];

    let line = sourceLine
      .replace(/^\s{0,3}#{1,6}\s+/, "")
      .replace(/^\s*[-+*]\s+\[([ xX])\]\s+/, (_, state: string) =>
        state === " " ? "☐ " : "☑ ",
      )
      .replace(/^(\s*)[-+*]\s+/, "$1• ")
      .replace(/^\s*(?:>\s*)+/, "› ");

    line = transformPreservingMarkdownEscapes(line, (value) => {
      let transformed = value;
      if (/^\s*\|?.+\|.+\|?\s*$/.test(transformed)) {
        transformed = transformed
          .replace(/^\s*\|/, "")
          .replace(/\|\s*$/, "")
          .replace(/\s*\|\s*/g, "\t")
          .trim();
      }
      return transformed
        .replace(/!\[([^\]]*)\]\([^)]+\)/g, "$1")
        .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
        .replace(/\[([^\]]+)\]\[[^\]]*\]/g, "$1")
        .replace(/<(https?:\/\/[^>]+)>/g, "$1")
        .replace(/(\*\*|__|~~)(?=\S)(.+?\S)\1/g, "$2")
        .replace(/(`+)([^`\n]+?)\1/g, "$2")
        .replace(/\*([^*\n]+)\*/g, "$1")
        .replace(/_([^_\n]+)_/g, "$1");
    });
    return [line];
  });

  return readable.join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

export function richCopyExtension(firstLineIsTitle: boolean) {
  const writeSelection = (event: ClipboardEvent, view: EditorView) => {
    if (!event.clipboardData) return false;

    const ranges = view.state.selection.ranges.filter(
      ({ from, to }) => from !== to,
    );
    if (ranges.length === 0) return false;

    const units = markdownEscapeUnits(view.state.doc.toString());
    const markdown = ranges
      .map(({ from, to }) => {
        const leading = units.find((unit) => unit.visibleFrom === from);
        return view.state.sliceDoc(leading?.escapeFrom ?? from, to);
      })
      .join("\n");
    const includeDocumentTitle =
      firstLineIsTitle && ranges.length === 1 && ranges[0].from === 0;
    event.clipboardData.setData("text/plain", readableCopyText(markdown));
    event.clipboardData.setData(
      "text/html",
      richCopyHtml(markdown, { includeDocumentTitle }),
    );
    try {
      event.clipboardData.setData(ZERUS_MARKDOWN_CLIPBOARD_TYPE, markdown);
    } catch {
      // Some WebViews reject custom MIME types; HTML still preserves formatting.
    }
    event.preventDefault();
    return true;
  };

  return EditorView.domEventHandlers({
    copy: writeSelection,
    cut: (event, view) => {
      if (view.state.readOnly || !writeSelection(event, view)) return false;
      if (!deleteCleanSelection(view, "forward")) {
        view.dispatch({
          changes: view.state.selection.ranges
            .filter((range) => !range.empty)
            .map((range) => ({ from: range.from, to: range.to })),
          userEvent: "delete.cut",
        });
      }
      return true;
    },
  });
}
