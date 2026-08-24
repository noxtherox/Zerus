import {
  Decoration,
  DecorationSet,
  EditorView,
  MatchDecorator,
  ViewPlugin,
  ViewUpdate,
} from "@codemirror/view";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import {
  EditorSelection,
  type EditorState,
  type Extension,
} from "@codemirror/state";
import { tags } from "@lezer/highlight";
import {
  autocompletion,
  type CompletionContext,
  type CompletionResult,
} from "@codemirror/autocomplete";
import { WIKILINK_REGEX } from "@/lib/note-utils";

// Theme tokens from globals.css / src/lib/theme.ts (user-customizable)
const ACCENT = "rgb(var(--zerus-accent))";
const LINK = "rgb(var(--zerus-link))";
const TEXT = "rgb(var(--zerus-text))";

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
    width: "var(--zerus-note-width)",
    maxWidth: "var(--zerus-note-width)",
    marginInline: "var(--zerus-note-margin-inline)",
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
  ".cm-cursor": {
    borderLeftColor: ACCENT,
    borderLeftWidth: "2px",
    // CodeMirror sizes the caret to the full line box. Scaling around its
    // centre keeps its height proportional to the active body/heading text
    // without inheriting the line-height whitespace above and below glyphs.
    transform: "scaleY(0.72)",
    transformOrigin: "center",
  },
  // Use the platform's native selection painting. CodeMirror's drawSelection
  // layer can briefly retain stale line geometry when live-preview replacement
  // decorations change during a pointer selection, producing a full-line flash.
  "::selection": {
    backgroundColor: "rgb(var(--zerus-accent) / 0.15) !important",
  },
  ".cm-wikilink": {
    color: LINK,
    cursor: "pointer",
    borderRadius: "3px",
  },
  ".cm-wikilink:hover": { textDecoration: "underline" },
  ".cm-wikilink-unresolved": { color: "rgb(var(--zerus-link) / 0.55)" },
  ".cm-external-link": {
    color: LINK,
    cursor: "pointer",
    textDecoration: "underline",
    textDecorationColor: "rgb(var(--zerus-link) / 0.35)",
    textUnderlineOffset: "2px",
  },
  ".cm-external-link:hover": { textDecorationColor: LINK },
  ".cm-inline-tag": {
    color: ACCENT,
    backgroundColor: "rgb(var(--zerus-accent) / 0.08)",
    borderRadius: "9999px",
    padding: "1px 2px",
  },
  ".cm-image-preview": {
    position: "relative",
    boxSizing: "border-box",
    width: "100%",
    maxWidth: "100%",
    // CodeMirror does not include a block widget's vertical margins in its
    // height map. Internal spacing keeps coordinate mapping accurate for the
    // editable lines immediately before and after an image.
    padding: "0 0 6px",
    borderRadius: "6px",
    outline: "none",
  },
  ".cm-image-preview-media": {
    position: "relative",
    width: "fit-content",
    maxWidth: "100%",
    borderRadius: "6px",
  },
  ".cm-image-preview:focus-visible .cm-image-preview-media": {
    boxShadow: `0 0 0 2px ${ACCENT}`,
  },
  ".cm-image-preview.cm-image-selected .cm-image-preview-media": {
    boxShadow: `0 0 0 2px ${ACCENT}`,
  },
  "&.cm-image-selection-active .cm-cursor": {
    display: "none",
  },
  ".cm-image-preview img": {
    display: "block",
    maxWidth: "100%",
    borderRadius: "6px",
    boxShadow: "0 1px 4px rgb(0 0 0 / 0.12)",
  },
  ".cm-image-source-line": {
    display: "none",
  },
  ".cm-image-preview-missing .cm-image-preview-media": {
    padding: "6px 10px",
    fontSize: "12px",
    color: "rgb(var(--zerus-text) / 0.6)",
    backgroundColor: "rgb(var(--zerus-text) / 0.06)",
  },
  ".cm-image-after-hit-area": {
    position: "absolute",
    zIndex: "1",
    left: "0",
    bottom: "calc(-1.65em)",
    width: "100%",
    height: "1.65em",
    cursor: "text",
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
    backgroundColor: "rgb(var(--zerus-text) / 0.4)",
    border: "1.5px solid rgb(var(--zerus-editor-bg))",
    cursor: "ew-resize",
    opacity: "0",
    transition: "opacity 120ms ease",
    touchAction: "none",
  },
  ".cm-image-preview:hover .cm-image-resize-handle": { opacity: "1" },
  ".cm-image-resizing .cm-image-resize-handle": { opacity: "1" },
  ".cm-attachment-card": {
    position: "relative",
    display: "inline-flex",
    alignItems: "center",
    gap: "8px",
    maxWidth: "100%",
    margin: "2px 1px",
    padding: "7px 10px 7px 6px",
    border: "1px solid rgb(var(--zerus-text) / 0.14)",
    borderRadius: "8px",
    backgroundColor: "rgb(var(--zerus-text) / 0.045)",
    boxShadow: "0 1px 2px rgb(0 0 0 / 0.05)",
    verticalAlign: "middle",
  },
  ".cm-attachment-menu-wrap": { position: "relative", display: "inline-flex" },
  ".cm-attachment-menu-trigger": {
    width: "25px",
    height: "25px",
    padding: "0",
    border: "0",
    borderRadius: "5px",
    color: "rgb(var(--zerus-text) / 0.62)",
    background: "transparent",
    cursor: "pointer",
    fontSize: "11px",
    letterSpacing: "-1px",
  },
  ".cm-attachment-menu-trigger:hover": {
    backgroundColor: "rgb(var(--zerus-text) / 0.09)",
  },
  ".cm-attachment-menu": {
    position: "absolute",
    zIndex: "40",
    top: "29px",
    left: "0",
    display: "flex",
    minWidth: "180px",
    flexDirection: "column",
    padding: "4px",
    border: "1px solid rgb(var(--zerus-text) / 0.14)",
    borderRadius: "8px",
    backgroundColor: "rgb(var(--zerus-editor-bg))",
    boxShadow: "0 8px 24px rgb(0 0 0 / 0.18)",
  },
  ".cm-attachment-menu[hidden]": { display: "none" },
  ".cm-attachment-menu button": {
    padding: "6px 8px",
    border: "0",
    borderRadius: "5px",
    color: TEXT,
    background: "transparent",
    cursor: "pointer",
    fontSize: "12px",
    textAlign: "left",
  },
  ".cm-attachment-menu button:hover": {
    backgroundColor: "rgb(var(--zerus-text) / 0.08)",
  },
  ".cm-attachment-icon": { color: ACCENT, fontSize: "13px" },
  ".cm-attachment-name": {
    overflow: "hidden",
    color: TEXT,
    fontSize: "13px",
    fontWeight: "500",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  ".cm-attachment-kind": {
    color: "rgb(var(--zerus-text) / 0.55)",
    fontSize: "10px",
    textTransform: "uppercase",
    letterSpacing: "0.04em",
  },
  ".cm-tooltip.cm-tooltip-autocomplete": {
    border: "1px solid rgb(var(--zerus-text) / 0.12)",
    borderRadius: "8px",
    backgroundColor: "rgb(var(--zerus-editor-bg))",
    boxShadow: "0 8px 24px rgb(0 0 0 / 0.12)",
    overflow: "hidden",
  },
  ".cm-tooltip-autocomplete ul li": { padding: "4px 10px" },
  ".cm-tooltip-autocomplete ul li[aria-selected]": {
    backgroundColor: "rgb(var(--zerus-accent) / 0.12)",
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
    { tag: tags.quote, color: "rgb(var(--zerus-text) / 0.62)", fontStyle: "italic" },
    { tag: tags.monospace, fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: "0.9em", color: ACCENT },
    { tag: tags.processingInstruction, color: "rgb(var(--zerus-text) / 0.45)" },
    { tag: tags.meta, color: "rgb(var(--zerus-text) / 0.45)" },
    { tag: tags.contentSeparator, color: "rgb(var(--zerus-text) / 0.45)" },
  ]),
);

/** Selects logical lines without including the line break after the last line. */
export function lineSelectionBetween(
  state: EditorState,
  anchorPosition: number,
  headPosition = anchorPosition,
) {
  const anchorLine = state.doc.lineAt(anchorPosition);
  const headLine = state.doc.lineAt(headPosition);

  return anchorPosition <= headPosition
    ? EditorSelection.range(anchorLine.from, headLine.to)
    : EditorSelection.range(anchorLine.to, headLine.from);
}

/** Keeps CodeMirror's triple-click line selection out of the following line. */
export const currentLineTripleClickSelection: Extension =
  EditorView.mouseSelectionStyle.of((view, event) => {
    if (event.button !== 0 || event.detail < 3) return null;

    const position = view.posAtCoords({ x: event.clientX, y: event.clientY });
    if (position == null) return null;

    let anchorPosition = position;
    let initialSelection = view.state.selection;

    return {
      update(update) {
        if (!update.docChanged) return;
        anchorPosition = update.changes.mapPos(anchorPosition);
        initialSelection = initialSelection.map(update.changes);
      },
      get(currentEvent, extend, multiple) {
        const headPosition =
          view.posAtCoords({
            x: currentEvent.clientX,
            y: currentEvent.clientY,
          }) ?? anchorPosition;
        const range = lineSelectionBetween(
          view.state,
          anchorPosition,
          headPosition,
        );

        if (extend) {
          return initialSelection.replaceRange(
            initialSelection.main.extend(range.from, range.to, range.assoc),
          );
        }
        if (multiple) return initialSelection.addRange(range);
        return EditorSelection.create([range]);
      },
    };
  });

export function shouldFollowWikilink(
  event: Pick<MouseEvent, "metaKey" | "ctrlKey" | "button">,
  followOnClick = false,
): boolean {
  return event.button === 0 && (followOnClick || event.metaKey || event.ctrlKey);
}

/** Styles [[wikilinks]], marks unresolved ones, and handles link activation. */
export function wikilinkExtension(options: {
  isResolved: (title: string) => boolean;
  onFollow: (title: string) => void;
  /** Mobile has no modifier keys, so a normal tap follows the link. */
  followOnClick?: boolean;
}) {
  const decorator = new MatchDecorator({
    regexp: new RegExp(WIKILINK_REGEX.source, "g"),
    decoration: (match) =>
      Decoration.mark({
        class: options.isResolved(match[1].trim())
          ? "cm-wikilink"
          : "cm-wikilink cm-wikilink-unresolved",
        attributes: {
          title: options.followOnClick ? "Tap to open" : "⌘/Ctrl+Click to open",
        },
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
      if (!shouldFollowWikilink(event, options.followOnClick)) return false;
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
    regexp: /(?:^|(?<=\s))(?:\\)?#[\p{L}\p{N}][\p{L}\p{N}/_-]*/gu,
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
