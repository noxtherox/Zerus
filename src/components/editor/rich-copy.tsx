import { renderToStaticMarkup } from "react-dom/server";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { keymap, EditorView } from "@codemirror/view";

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

export function richCopyExtension(firstLineIsTitle: boolean) {
  let richCopyRequested = false;

  return [
    keymap.of([
      {
        key: "Mod-Shift-c",
        run: (view) => {
          if (view.state.selection.ranges.every(({ from, to }) => from === to)) {
            return true;
          }

          richCopyRequested = true;
          try {
            document.execCommand("copy");
          } finally {
            richCopyRequested = false;
          }
          return true;
        },
      },
    ]),
    EditorView.domEventHandlers({
      copy: (event, view) => {
        if (!richCopyRequested || !event.clipboardData) return false;

        const ranges = view.state.selection.ranges.filter(
          ({ from, to }) => from !== to,
        );
        if (ranges.length === 0) return false;

        const markdown = ranges
          .map(({ from, to }) => view.state.sliceDoc(from, to))
          .join("\n");
        event.clipboardData.setData("text/plain", markdown);
        event.clipboardData.setData(
          "text/html",
          richCopyHtml(markdown, {
            includeDocumentTitle:
              firstLineIsTitle && ranges.length === 1 && ranges[0].from === 0,
          }),
        );
        event.preventDefault();
        return true;
      },
    }),
  ];
}
