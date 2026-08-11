import {
  Decoration,
  DecorationSet,
  EditorView,
  MatchDecorator,
  ViewPlugin,
  ViewUpdate,
} from "@codemirror/view";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { type EditorState, type Extension } from "@codemirror/state";
import { tags } from "@lezer/highlight";
import {
  autocompletion,
  type CompletionContext,
  type CompletionResult,
} from "@codemirror/autocomplete";
import { WIKILINK_REGEX } from "@/lib/note-utils";

// Theme tokens from globals.css / src/lib/theme.ts (user-customizable)
const ACCENT = "rgb(var(--grim-accent))";
const LINK = "rgb(var(--grim-link))";
const TEXT = "rgb(var(--grim-text))";

export const editorTheme = EditorView.theme({
  "&": {
    height: "100%",
    fontSize: "15px",
    backgroundColor: "transparent",
  },
  "&.cm-focused": { outline: "none" },
  ".cm-content": {
    fontFamily:
      "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
    padding: "24px 32px 120px",
    lineHeight: "1.65",
    caretColor: ACCENT,
    boxSizing: "border-box",
    width: "var(--grim-note-width)",
    maxWidth: "var(--grim-note-width)",
    marginInline: "var(--grim-note-margin-inline)",
  },
  ".cm-line": { padding: "0" },
  ".cm-title-line": {
    color: TEXT,
    fontSize: "1.55em",
    fontWeight: "700",
    lineHeight: "1.3",
  },
  // An explicit Markdown heading already has a syntax-highlight font size.
  // Let the title line own the size so `# Title` does not scale twice.
  ".cm-title-line *": { fontSize: "inherit !important" },
  ".cm-cursor": { borderLeftColor: ACCENT, borderLeftWidth: "2px" },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground": {
    backgroundColor: "rgb(var(--grim-accent) / 0.15) !important",
  },
  ".cm-wikilink": {
    color: LINK,
    cursor: "pointer",
    borderRadius: "3px",
  },
  ".cm-wikilink:hover": { textDecoration: "underline" },
  ".cm-wikilink-unresolved": { color: "rgb(var(--grim-link) / 0.55)" },
  ".cm-external-link": {
    color: LINK,
    cursor: "pointer",
    textDecoration: "underline",
    textDecorationColor: "rgb(var(--grim-link) / 0.35)",
    textUnderlineOffset: "2px",
  },
  ".cm-external-link:hover": { textDecorationColor: LINK },
  ".cm-inline-tag": {
    color: ACCENT,
    backgroundColor: "rgb(var(--grim-accent) / 0.08)",
    borderRadius: "9999px",
    padding: "1px 2px",
  },
  ".cm-image-preview": {
    position: "relative",
    width: "fit-content",
    maxWidth: "100%",
    margin: "4px 0 10px",
    borderRadius: "6px",
  },
  ".cm-image-preview img": {
    display: "block",
    maxWidth: "100%",
    borderRadius: "6px",
    boxShadow: "0 1px 4px rgb(0 0 0 / 0.12)",
  },
  ".cm-image-preview-missing": {
    padding: "6px 10px",
    fontSize: "12px",
    color: "rgb(var(--grim-text) / 0.6)",
    backgroundColor: "rgb(var(--grim-text) / 0.06)",
  },
  ".cm-image-resize-handle": {
    position: "absolute",
    top: "50%",
    right: "-5px",
    transform: "translateY(-50%)",
    width: "8px",
    height: "44px",
    maxHeight: "60%",
    borderRadius: "9999px",
    backgroundColor: "rgb(var(--grim-text) / 0.4)",
    border: "1.5px solid rgb(var(--grim-editor-bg))",
    cursor: "ew-resize",
    opacity: "0",
    transition: "opacity 120ms ease",
    touchAction: "none",
  },
  ".cm-image-preview:hover .cm-image-resize-handle": { opacity: "1" },
  ".cm-image-resizing .cm-image-resize-handle": { opacity: "1" },
  ".cm-tooltip.cm-tooltip-autocomplete": {
    border: "1px solid rgb(var(--grim-text) / 0.12)",
    borderRadius: "8px",
    backgroundColor: "rgb(var(--grim-editor-bg))",
    boxShadow: "0 8px 24px rgb(0 0 0 / 0.12)",
    overflow: "hidden",
  },
  ".cm-tooltip-autocomplete ul li": { padding: "4px 10px" },
  ".cm-tooltip-autocomplete ul li[aria-selected]": {
    backgroundColor: "rgb(var(--grim-accent) / 0.12)",
    color: "inherit",
  },
});

/** The body line Zerus uses as the note title: its first non-empty line. */
export function titleLineFrom(state: EditorState): number {
  for (let lineNumber = 1; lineNumber <= state.doc.lines; lineNumber += 1) {
    const line = state.doc.line(lineNumber);
    if (line.text.trim()) return line.from;
  }

  // Keep a new empty note title-sized before the user starts typing.
  return state.doc.line(1).from;
}

/** Keeps the note title visually H1-sized without changing its Markdown. */
export const titleLineExtension: Extension = EditorView.decorations.compute(
  ["doc"],
  (state) =>
    Decoration.set([
      Decoration.line({ class: "cm-title-line" }).range(titleLineFrom(state)),
    ]),
);

export const markdownHighlighting = syntaxHighlighting(
  HighlightStyle.define([
    { tag: tags.heading1, fontSize: "1.55em", fontWeight: "700", color: TEXT },
    { tag: tags.heading2, fontSize: "1.3em", fontWeight: "700", color: TEXT },
    { tag: tags.heading3, fontSize: "1.15em", fontWeight: "600", color: TEXT },
    { tag: tags.heading4, fontWeight: "600" },
    { tag: tags.strong, fontWeight: "700" },
    { tag: tags.emphasis, fontStyle: "italic" },
    { tag: tags.strikethrough, textDecoration: "line-through" },
    { tag: tags.link, color: LINK },
    { tag: tags.url, color: LINK },
    { tag: tags.quote, color: "rgb(var(--grim-text) / 0.62)", fontStyle: "italic" },
    { tag: tags.monospace, fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: "0.9em", color: ACCENT },
    { tag: tags.processingInstruction, color: "rgb(var(--grim-text) / 0.45)" },
    { tag: tags.meta, color: "rgb(var(--grim-text) / 0.45)" },
    { tag: tags.contentSeparator, color: "rgb(var(--grim-text) / 0.45)" },
  ]),
);

/** Styles [[wikilinks]], marking unresolved ones, and handles Cmd/Ctrl+Click. */
export function wikilinkExtension(options: {
  isResolved: (title: string) => boolean;
  onFollow: (title: string) => void;
}) {
  const decorator = new MatchDecorator({
    regexp: new RegExp(WIKILINK_REGEX.source, "g"),
    decoration: (match) =>
      Decoration.mark({
        class: options.isResolved(match[1].trim())
          ? "cm-wikilink"
          : "cm-wikilink cm-wikilink-unresolved",
        attributes: { title: "⌘/Ctrl+Click to open" },
      }),
  });

  const plugin = ViewPlugin.fromClass(
    class {
      decorations: DecorationSet;
      constructor(view: EditorView) {
        this.decorations = decorator.createDeco(view);
      }
      update(update: ViewUpdate) {
        // Rebuild fully so resolved/unresolved state stays fresh as titles change
        if (update.docChanged || update.viewportChanged) {
          this.decorations = decorator.createDeco(update.view);
        }
      }
    },
    { decorations: (instance) => instance.decorations },
  );

  const clickHandler = EditorView.domEventHandlers({
    mousedown: (event, view) => {
      if (!event.metaKey && !event.ctrlKey) return false;
      const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
      if (pos == null) return false;
      const line = view.state.doc.lineAt(pos);
      const regex = new RegExp(WIKILINK_REGEX.source, "g");
      for (const match of line.text.matchAll(regex)) {
        const start = line.from + (match.index ?? 0);
        const end = start + match[0].length;
        if (pos >= start && pos <= end) {
          event.preventDefault();
          options.onFollow(match[1].trim());
          return true;
        }
      }
      return false;
    },
  });

  return [plugin, clickHandler];
}

/** Highlights Bear-style inline #tags. */
export const inlineTagExtension = (() => {
  const decorator = new MatchDecorator({
    regexp: /(?:^|(?<=\s))#[\p{L}\p{N}][\p{L}\p{N}/_-]*/gu,
    decoration: () => Decoration.mark({ class: "cm-inline-tag" }),
  });
  return ViewPlugin.fromClass(
    class {
      decorations: DecorationSet;
      constructor(view: EditorView) {
        this.decorations = decorator.createDeco(view);
      }
      update(update: ViewUpdate) {
        this.decorations = decorator.updateDeco(update, this.decorations);
      }
    },
    { decorations: (instance) => instance.decorations },
  );
})();

/** Autocomplete note titles after typing `[[`. */
export function wikilinkAutocomplete(getTitles: () => string[]) {
  const source = (context: CompletionContext): CompletionResult | null => {
    const match = context.matchBefore(/\[\[([^[\]]*)$/);
    if (!match) return null;
    const from = match.from + 2;
    return {
      from,
      options: getTitles().map((title) => ({
        label: title,
        type: "text",
        apply: (view, _completion, applyFrom, applyTo) => {
          const closed =
            view.state.sliceDoc(applyTo, applyTo + 2) === "]]";
          const insert = closed ? title : `${title}]]`;
          view.dispatch({
            changes: { from: applyFrom, to: applyTo, insert },
            selection: { anchor: applyFrom + title.length + 2 },
          });
        },
      })),
      validFor: /^[^[\]]*$/,
    };
  };
  return autocompletion({ override: [source], icons: false });
}
