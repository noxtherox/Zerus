import {
  Annotation,
  StateEffect,
  StateField,
  type Extension,
  type Transaction,
} from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { isolateHistory } from "@codemirror/commands";

export type PasteMode = "source" | "markdown" | "plain";
export const ZERUS_MARKDOWN_CLIPBOARD_TYPE = "application/x-zerus-markdown";

export const pasteHistoryStart = StateEffect.define<null>();
export const pasteChoiceHistory = Annotation.define<boolean>();

/** Tracks a paste until a non-choice document edit commits the next action. */
export const pasteHistoryTracking = StateField.define<boolean>({
  create: () => false,
  update(pending, transaction) {
    if (transaction.effects.some((effect) => effect.is(pasteHistoryStart))) {
      return true;
    }
    if (transaction.annotation(pasteChoiceHistory)) return pending;
    return transaction.docChanged ? false : pending;
  },
});

/** Keeps paste interpretations together without merging later typing. */
export function joinEditorHistoryEvent(
  transaction: Transaction,
  isAdjacent: boolean,
): boolean {
  if (transaction.annotation(pasteChoiceHistory)) return true;
  if (transaction.startState.field(pasteHistoryTracking, false)) return false;
  return isAdjacent;
}

export interface PasteChoice {
  mode: PasteMode;
  label: string;
  description: string;
  text: string;
}

export interface PasteChoiceSession {
  from: number;
  to: number;
  choices: PasteChoice[];
  selectedMode: PasteMode;
  anchor: { left: number; bottom: number };
}

interface ClipboardPaste {
  plainText: string;
  html?: string;
  internalMarkdown?: string;
}

function normalizeNewlines(value: string): string {
  return value.replace(/\r\n?/g, "\n");
}

export function looksLikeMarkdown(value: string): boolean {
  const text = normalizeNewlines(value);
  return (
    /(?:^|\n)\s{0,3}(?:#{1,6}\s|>\s|[-+*]\s|\d+[.)]\s|```|~~~)/.test(text) ||
    /(?:\*\*|__|~~|`)[^\n]+(?:\*\*|__|~~|`)/.test(text) ||
    /(?:^|[^\w*])\*(?![\s*])[^*\n]+(?<!\s)\*(?![\w*])/.test(text) ||
    /(?:^|[^\w_])_(?![\s_])[^_\n]+(?<!\s)_(?![\w_])/.test(text) ||
    /!?\[[^\]\n]+\]\([^)\n]+\)/.test(text) ||
    /(?:^|\n)\s*\|?.+\|.+\n\s*\|?\s*:?-{3,}/.test(text)
  );
}

/** Encode Markdown-looking plain text so clean mode displays it literally. */
export function escapeMarkdownPlainText(value: string): string {
  const escaped = normalizeNewlines(value)
    .split("\n")
    .map((line) =>
      line
        .replace(/([\\`*_~])/g, "\\$1")
        .replace(/^(\s*)(#{1,6}|>|[-+])(?=\s)/, "$1\\$2")
        .replace(/^(\s*)(\d+)([.)])(?=\s)/, "$1$2\\$3")
        .replace(/!?\[(?=[^\]\n]+\]\([^)\n]+\))/g, (match) =>
          match === "![" ? "!\\[" : "\\[",
        )
        .replace(/<(?=\/?[A-Za-z][^>]*>)/g, "\\<"),
    )
    .join("\n");

  if (!/(?:^|\n)\s*\|?.+\|.+\n\s*\|?\s*:?-{3,}/.test(escaped)) {
    return escaped;
  }
  return escaped.replace(/\|/g, "\\|");
}

function inlineCode(value: string): string {
  const fence = value.includes("``") ? "```" : value.includes("`") ? "``" : "`";
  return `${fence}${value}${fence}`;
}

function renderList(element: Element, ordered: boolean): string {
  const items = [...element.children].filter((child) => child.tagName === "LI");
  return items
    .map((item, index) => {
      const rendered = renderChildren(item).trim().replace(/\n{2,}/g, "\n");
      const lines = rendered.split("\n");
      const marker = ordered ? `${index + 1}. ` : "- ";
      return `${marker}${lines[0] ?? ""}${lines
        .slice(1)
        .map((line) => `\n  ${line}`)
        .join("")}`;
    })
    .join("\n");
}

function renderTable(element: Element): string {
  const rows = [...element.querySelectorAll("tr")]
    .map((row) =>
      [...row.querySelectorAll(":scope > th, :scope > td")].map((cell) =>
        (cell.textContent ?? "").trim().replace(/\|/g, "\\|"),
      ),
    )
    .filter((row) => row.length > 0);
  if (rows.length === 0) return "";
  const width = Math.max(...rows.map((row) => row.length));
  const padded = rows.map((row) => [
    ...row,
    ...Array.from({ length: width - row.length }, () => ""),
  ]);
  const line = (cells: string[]) => `| ${cells.join(" | ")} |`;
  return [
    line(padded[0]),
    line(Array.from({ length: width }, () => "---")),
    ...padded.slice(1).map(line),
  ].join("\n");
}

function renderNode(node: Node): string {
  if (node.nodeType === Node.TEXT_NODE) {
    return (node.textContent ?? "").replace(/[\t\n\r ]+/g, " ");
  }
  if (!(node instanceof Element)) return "";

  const tag = node.tagName.toLowerCase();
  const content = () => renderChildren(node);
  switch (tag) {
    case "br":
      return "\n";
    case "p":
    case "div":
    case "section":
    case "article":
      return `${content().trim()}\n\n`;
    case "h1":
    case "h2":
    case "h3":
    case "h4":
    case "h5":
    case "h6":
      return `${"#".repeat(Number(tag[1]))} ${content().trim()}\n\n`;
    case "strong":
    case "b":
      return `**${content()}**`;
    case "em":
    case "i":
      return `*${content()}*`;
    case "del":
    case "s":
    case "strike":
      return `~~${content()}~~`;
    case "code":
      return node.parentElement?.tagName === "PRE"
        ? node.textContent ?? ""
        : inlineCode(node.textContent ?? "");
    case "pre": {
      const value = node.textContent?.replace(/\n$/, "") ?? "";
      const fence = value.includes("```") ? "````" : "```";
      return `${fence}\n${value}\n${fence}\n\n`;
    }
    case "a": {
      const label = content().trim();
      const href = node.getAttribute("href")?.trim();
      return href ? `[${label || href}](${href})` : label;
    }
    case "img": {
      const source = node.getAttribute("src")?.trim();
      if (!source) return "";
      return `![${node.getAttribute("alt") ?? ""}](${source})`;
    }
    case "blockquote":
      return `${content()
        .trim()
        .split("\n")
        .map((line) => `> ${line}`)
        .join("\n")}\n\n`;
    case "ul":
      return `${renderList(node, false)}\n\n`;
    case "ol":
      return `${renderList(node, true)}\n\n`;
    case "table":
      return `${renderTable(node)}\n\n`;
    case "hr":
      return "---\n\n";
    case "script":
    case "style":
    case "meta":
    case "title":
      return "";
    default:
      return content();
  }
}

function renderChildren(node: Node): string {
  return [...node.childNodes].map(renderNode).join("");
}

/** Convert the rich clipboard fragment to the Markdown Zerus stores on disk. */
export function richHtmlToMarkdown(html: string): string {
  if (typeof DOMParser === "undefined") return "";
  try {
    const parsed = new DOMParser().parseFromString(html, "text/html");
    return renderChildren(parsed.body)
      .replace(/\u00a0/g, " ")
      .replace(/[ \t]+\n/g, "\n")
      .replace(/\n{3,}/g, "\n\n")
      .trim();
  } catch {
    return "";
  }
}

export function pasteChoices({
  plainText,
  html,
  internalMarkdown,
}: ClipboardPaste): { defaultText: string; choices: PasteChoice[] } {
  const interpreted = normalizeNewlines(plainText);
  const literal = escapeMarkdownPlainText(interpreted);
  const rich = html ? richHtmlToMarkdown(html) : "";
  const internal = internalMarkdown
    ? normalizeNewlines(internalMarkdown)
    : undefined;
  const defaultText = internal ?? (rich || literal);
  const candidates: PasteChoice[] = [
    {
      mode: "source",
      label: "Keep source formatting",
      description: internal
        ? "Preserve Zerus formatting"
        : rich
          ? "Match the copied content"
          : "Keep Markdown characters literal",
      text: defaultText,
    },
  ];

  if (!internal && looksLikeMarkdown(interpreted)) {
    candidates.push({
      mode: "markdown",
      label: "Interpret Markdown",
      description: "Turn syntax into formatting",
      text: interpreted,
    });
  }
  if (rich || internal) {
    candidates.push({
      mode: "plain",
      label: "Plain text",
      description: "Remove copied formatting",
      text: literal,
    });
  }

  const choices = candidates.filter(
    (candidate, index) =>
      candidates.findIndex((other) => other.text === candidate.text) === index,
  );
  return { defaultText, choices: choices.length > 1 ? choices : [] };
}

interface PasteOptionsExtensionOptions {
  onShow: (session: PasteChoiceSession) => void;
  onDismiss: () => void;
}

export function pasteOptionsExtension({
  onShow,
  onDismiss,
}: PasteOptionsExtensionOptions): Extension {
  return EditorView.domEventHandlers({
    paste: (event, view) => {
      if (!event.clipboardData || view.state.selection.ranges.length !== 1) {
        onDismiss();
        return false;
      }
      const plainText = event.clipboardData.getData("text/plain");
      const html = event.clipboardData.getData("text/html") || undefined;
      const internalMarkdown =
        event.clipboardData.getData(ZERUS_MARKDOWN_CLIPBOARD_TYPE) || undefined;
      const result = pasteChoices({ plainText, html, internalMarkdown });
      if (result.choices.length === 0) {
        onDismiss();
        return false;
      }

      event.preventDefault();
      const selection = view.state.selection.main;
      const from = selection.from;
      const to = from + result.defaultText.length;
      view.dispatch({
        changes: { from, to: selection.to, insert: result.defaultText },
        selection: { anchor: to },
        effects: pasteHistoryStart.of(null),
        annotations: isolateHistory.of("before"),
        userEvent: "input.paste",
      });
      const coordinates = view.coordsAtPos(to);
      onShow({
        from,
        to,
        choices: result.choices,
        selectedMode: "source",
        anchor: {
          left: coordinates?.left ?? 0,
          bottom: coordinates?.bottom ?? 0,
        },
      });
      return true;
    },
  });
}

/** Swap a recent paste interpretation within the original paste history event. */
export function applyPasteChoice(
  view: EditorView,
  session: PasteChoiceSession,
  choice: PasteChoice,
): PasteChoiceSession {
  if (choice.mode === session.selectedMode) return session;
  view.dispatch({
    changes: { from: session.from, to: session.to, insert: choice.text },
    selection: { anchor: session.from + choice.text.length },
    annotations: pasteChoiceHistory.of(true),
  });
  return {
    ...session,
    to: session.from + choice.text.length,
    selectedMode: choice.mode,
  };
}
