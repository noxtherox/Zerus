import {
  Decoration,
  type DecorationSet,
  EditorView,
  ViewPlugin,
  type ViewUpdate,
  WidgetType,
  keymap,
} from "@codemirror/view";
import {
  EditorSelection,
  EditorState,
  type Extension,
  type Range,
  StateEffect,
  StateField,
} from "@codemirror/state";
import { syntaxTree } from "@codemirror/language";
import { WIKILINK_REGEX } from "@/lib/note-utils";
import { normalizeExternalUrl } from "@/lib/external-links";
import { tableDecoration } from "./markdown-table";

const ACCENT = "rgb(var(--zerus-accent))";

// The editor uses a proportional UI font, where a space is roughly 0.25em
// wide. Keep this in sync with the rendered leading whitespace so wrapped
// list text starts under the item's text instead of drifting farther right.
const PROPORTIONAL_SPACE_WIDTH_EM = 0.25;

const toggleEffect = StateEffect.define<boolean>();

const INLINE_MARKS: Record<string, string> = {
  Emphasis: "EmphasisMark",
  StrongEmphasis: "EmphasisMark",
  InlineCode: "CodeMark",
  Strikethrough: "StrikethroughMark",
  Link: "LinkMark",
};

const BARE_LINK_REGEX =
  /(?:https?:\/\/|www\.)[^\s<>{}[\]"]+|(?:[a-z\d](?:[a-z\d-]*[a-z\d])?\.)+[a-z]{2,}(?:\/[^\s<>{}[\]"]*)?/giu;

interface ExternalLinkMatch {
  url: string;
  from: number;
  to: number;
}

export function listItemIndentEm(
  leadingWhitespace: number,
  marker: string,
  isTaskItem: boolean,
): number {
  const markerIndent = isTaskItem
    ? 1.35
    : /^[-*+]$/.test(marker)
      ? 0.8
      : Math.max(1.1, marker.replace(/\D/g, "").length * 0.55 + 0.55);

  return leadingWhitespace * PROPORTIONAL_SPACE_WIDTH_EM + markerIndent;
}

function trimLinkPunctuation(value: string): string {
  return value.replace(/[.,!?;:]+$/g, "");
}

/** A bare domain in the first Markdown heading is title text, not an implicit URL. */
function isTitleHeadingLine(
  state: EditorState,
  lineFrom: number,
  lineText: string,
): boolean {
  return (
    state.sliceDoc(0, lineFrom).trim().length === 0 &&
    /^#{1,6}(?:\s|$)/.test(lineText)
  );
}

/** Resolve a rendered Markdown link or a pasted web address at a document position. */
export function externalLinkAt(
  state: EditorState,
  pos: number,
): ExternalLinkMatch | null {
  for (const bias of [-1, 1] as const) {
    let node = syntaxTree(state).resolveInner(pos, bias);
    for (; node; node = node.parent) {
      if (node.name === "Image") break;
      if (node.name === "Link") {
        const urlNode = node.getChild("URL");
        const url =
          urlNode &&
          normalizeExternalUrl(state.sliceDoc(urlNode.from, urlNode.to));
        if (url) return { url, from: node.from, to: node.to };
      }
      if (node.name === "URL") {
        const url = normalizeExternalUrl(state.sliceDoc(node.from, node.to));
        if (url) return { url, from: node.from, to: node.to };
      }
    }
  }

  const line = state.doc.lineAt(pos);
  if (isTitleHeadingLine(state, line.from, line.text)) return null;
  for (const match of line.text.matchAll(BARE_LINK_REGEX)) {
    const raw = trimLinkPunctuation(match[0]);
    const from = line.from + (match.index ?? 0);
    const to = from + raw.length;
    if (pos < from || pos > to) continue;
    const url = normalizeExternalUrl(raw);
    if (url) return { url, from, to };
  }
  return null;
}

/** Whether syntax-hiding is active. Toggled with Mod-E (source mode). */
export const livePreviewEnabled = StateField.define<boolean>({
  create: () => true,
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(toggleEffect)) value = effect.value;
    }
    return value;
  },
});

export function toggleLivePreview(view: EditorView): boolean {
  view.dispatch({
    effects: toggleEffect.of(!view.state.field(livePreviewEnabled)),
  });
  return true;
}

/**
 * A click at the visual end of styled text can map to the source position at
 * the start of its hidden closing marker. In live preview that position is
 * surprising: pressing Enter there splits the Markdown construct. Move only
 * collapsed cursors at that exact boundary past the complete construct.
 */
export function moveCursorPastClosingMarkup(
  state: EditorState,
  selection: EditorSelection,
): EditorSelection {
  let changed = false;
  const ranges = selection.ranges.map((range) => {
    if (!range.empty) return range;

    const pos = range.head;
    let target = pos;

    for (const bias of [1, -1] as const) {
      let node = syntaxTree(state).resolveInner(pos, bias);
      for (; node; node = node.parent) {
        const markName = INLINE_MARKS[node.name];
        if (!markName) continue;

        const marks = node.getChildren(markName);
        // For links, the visual label ends at `]`, while the final mark is
        // the closing `)` after the hidden destination.
        const closingMark =
          node.name === "Link" ? marks[1] : marks[marks.length - 1];
        // Keep walking through nested constructs whose closing syntax starts
        // where the inner construct ends (for example `***bold italic***`).
        if (closingMark?.from === target) target = Math.max(target, node.to);
      }
    }

    if (target === pos) return range;
    changed = true;
    return EditorSelection.cursor(target, range.assoc);
  });

  return changed
    ? EditorSelection.create(ranges, selection.mainIndex)
    : selection;
}

const keepCursorOutsideClosingMarkup = EditorState.transactionFilter.of(
  (transaction) => {
    if (
      !transaction.selection ||
      transaction.docChanged ||
      !transaction.startState.field(livePreviewEnabled)
    ) {
      return transaction;
    }

    const selection = moveCursorPastClosingMarkup(
      transaction.state,
      transaction.newSelection,
    );
    return selection === transaction.newSelection
      ? transaction
      : [transaction, { selection, sequential: true }];
  },
);

/** True when any selection range touches [from, to], including boundaries. */
function touches(state: EditorState, from: number, to: number): boolean {
  return state.selection.ranges.some(
    (range) => range.from <= to && range.to >= from,
  );
}

class BulletWidget extends WidgetType {
  override eq(): boolean {
    return true;
  }
  override toDOM(): HTMLElement {
    const span = document.createElement("span");
    span.className = "cm-list-bullet";
    span.textContent = "•";
    return span;
  }
}

class HrWidget extends WidgetType {
  override eq(): boolean {
    return true;
  }
  override toDOM(): HTMLElement {
    const span = document.createElement("span");
    span.className = "cm-rendered-hr";
    return span;
  }
}

class CheckboxWidget extends WidgetType {
  constructor(private readonly checked: boolean) {
    super();
  }
  override eq(other: CheckboxWidget): boolean {
    return other.checked === this.checked;
  }
  override toDOM(view: EditorView): HTMLElement {
    const input = document.createElement("input");
    input.type = "checkbox";
    input.className = "cm-task-checkbox";
    input.checked = this.checked;
    input.addEventListener("mousedown", (event) => {
      event.preventDefault();
      const pos = view.posAtDOM(input);
      const marker = view.state.sliceDoc(pos, pos + 3);
      if (!/^\[[ xX]\]$/.test(marker)) return;
      view.dispatch({
        changes: { from: pos + 1, to: pos + 2, insert: this.checked ? " " : "x" },
      });
    });
    return input;
  }
}

function buildDecorations(view: EditorView): DecorationSet {
  if (!view.state.field(livePreviewEnabled)) return Decoration.none;
  const { state } = view;
  const decos: Range<Decoration>[] = [];
  const decoratedListLines = new Set<number>();

  const hide = (from: number, to: number) => {
    if (from < to) decos.push(Decoration.replace({}).range(from, to));
  };
  /** Hides [from, to] plus one trailing space, if present. */
  const hideWithSpace = (from: number, to: number) => {
    hide(from, to + (state.sliceDoc(to, to + 1) === " " ? 1 : 0));
  };

  for (const { from, to } of view.visibleRanges) {
    for (const match of state.sliceDoc(from, to).matchAll(BARE_LINK_REGEX)) {
      const raw = trimLinkPunctuation(match[0]);
      const start = from + (match.index ?? 0);
      const line = state.doc.lineAt(start);
      if (isTitleHeadingLine(state, line.from, line.text)) continue;
      if (!raw || !normalizeExternalUrl(raw)) continue;
      decos.push(
        Decoration.mark({
          class: "cm-external-link",
          attributes: { title: "Open in browser" },
        }).range(start, start + raw.length),
      );
    }

    // [[wikilinks]]: hide the brackets, keep the title (styled elsewhere).
    const regex = new RegExp(WIKILINK_REGEX.source, "g");
    for (const match of state.sliceDoc(from, to).matchAll(regex)) {
      const start = from + (match.index ?? 0);
      const end = start + match[0].length;
      if (touches(state, start, end)) continue;
      hide(start, start + 2);
      hide(end - 2, end);
    }

    syntaxTree(state).iterate({
      from,
      to,
      enter: (node) => {
        const name = node.name;

        if (/^ATXHeading[1-6]$/.test(name)) {
          // Reveal on the whole line: `#` governs the whole heading.
          if (touches(state, node.from, node.to)) return;
          const mark = node.node.getChild("HeaderMark");
          if (mark) hideWithSpace(mark.from, mark.to);
          return;
        }

        switch (name) {
          case "Emphasis":
          case "StrongEmphasis": {
            if (touches(state, node.from, node.to)) return;
            for (const mark of node.node.getChildren("EmphasisMark")) {
              hide(mark.from, mark.to);
            }
            return;
          }
          case "InlineCode": {
            if (touches(state, node.from, node.to)) return;
            for (const mark of node.node.getChildren("CodeMark")) {
              hide(mark.from, mark.to);
            }
            return;
          }
          case "Strikethrough": {
            if (touches(state, node.from, node.to)) return;
            for (const mark of node.node.getChildren("StrikethroughMark")) {
              hide(mark.from, mark.to);
            }
            return;
          }
          case "Link": {
            // Only true `[text](url)` links; bare `[ref]` (e.g. inside
            // wikilinks) has no URL child and is left alone.
            const url = node.node.getChild("URL");
            if (!url) return;
            if (touches(state, node.from, node.to)) return false;
            const marks = node.node.getChildren("LinkMark");
            if (marks.length < 2) return false;
            decos.push(
              Decoration.mark({
                class: "cm-external-link",
                attributes: { title: "Open in browser" },
              }).range(marks[0].to, marks[1].from),
            );
            hide(marks[0].from, marks[0].to);
            hide(marks[1].from, node.to);
            return false;
          }
          case "Image": {
            // The preview widget below the line does the showing; hide the
            // markdown itself unless the cursor is on its line.
            const line = state.doc.lineAt(node.from);
            if (touches(state, line.from, line.to)) return false;
            hide(node.from, node.to);
            return false;
          }
          case "Blockquote": {
            for (let pos = node.from; pos <= node.to; ) {
              const line = state.doc.lineAt(pos);
              decos.push(
                Decoration.line({ class: "cm-blockquote-line" }).range(
                  line.from,
                ),
              );
              pos = line.to + 1;
            }
            return;
          }
          case "QuoteMark": {
            const line = state.doc.lineAt(node.from);
            if (touches(state, line.from, line.to)) return;
            hideWithSpace(node.from, node.to);
            return;
          }
          case "ListMark": {
            const line = state.doc.lineAt(node.from);
            if (!decoratedListLines.has(line.from)) {
              const leadingWhitespace = state
                .sliceDoc(line.from, node.from)
                .match(/^\s*/)?.[0].length ?? 0;
              const marker = state.sliceDoc(node.from, node.to);
              const isTaskItem = node.node.nextSibling?.name === "Task";
              const indent = listItemIndentEm(
                leadingWhitespace,
                marker,
                isTaskItem,
              );

              decos.push(
                Decoration.line({
                  class: "cm-list-item-line",
                  attributes: {
                    style: `--cm-list-indent: ${indent}em`,
                  },
                }).range(line.from),
              );
              // Keep the hanging indent on the Markdown prefix rather than
              // shifting the whole editable line with `text-indent`.
              // WKWebView can leave a stale native caret behind when that
              // property changes during Tab/Shift+Tab, which looks like a
              // duplicated caret overlapping the bullet.
              decos.push(
                Decoration.mark({ class: "cm-list-item-prefix" }).range(
                  line.from,
                  node.to,
                ),
              );
              decoratedListLines.add(line.from);
            }

            if (node.node.nextSibling?.name === "Task") {
              // Task items get a checkbox; drop the bullet entirely.
              if (touches(state, node.from, node.to)) return;
              hideWithSpace(node.from, node.to);
              return;
            }
            const text = state.sliceDoc(node.from, node.to);
            if (!/^[-*+]$/.test(text)) return;
            if (touches(state, node.from, node.to)) return;
            decos.push(
              Decoration.replace({ widget: new BulletWidget() }).range(
                node.from,
                node.to,
              ),
            );
            return;
          }
          case "TaskMarker": {
            if (touches(state, node.from, node.to)) return;
            const checked = /x/i.test(state.sliceDoc(node.from, node.to));
            decos.push(
              Decoration.replace({ widget: new CheckboxWidget(checked) }).range(
                node.from,
                node.to,
              ),
            );
            return;
          }
          case "HorizontalRule": {
            const line = state.doc.lineAt(node.from);
            if (touches(state, line.from, line.to)) return;
            decos.push(
              Decoration.replace({ widget: new HrWidget() }).range(
                node.from,
                node.to,
              ),
            );
            return;
          }
          case "FencedCode": {
            for (let pos = node.from; pos <= node.to; ) {
              const line = state.doc.lineAt(pos);
              decos.push(
                Decoration.line({ class: "cm-codeblock-line" }).range(
                  line.from,
                ),
              );
              pos = line.to + 1;
            }
            if (touches(state, node.from, node.to)) return;
            const marks = node.node.getChildren("CodeMark");
            if (marks.length) {
              const info = node.node.getChild("CodeInfo");
              hide(marks[0].from, info ? info.to : marks[0].to);
              if (marks.length > 1) {
                const last = marks[marks.length - 1];
                hide(last.from, last.to);
              }
            }
            return;
          }
        }
      },
    });
  }

  return Decoration.set(decos, true);
}

function buildTableDecorations(state: EditorState): DecorationSet {
  if (!state.field(livePreviewEnabled)) return Decoration.none;

  const decorations: Range<Decoration>[] = [];
  syntaxTree(state).iterate({
    enter: (node) => {
      if (node.name !== "Table") return;
      decorations.push(
        tableDecoration(
          state.sliceDoc(node.from, node.to),
          node.from,
          state.readOnly,
        ).range(node.from, node.to),
      );
      return false;
    },
  });
  return Decoration.set(decorations, true);
}

// Block replacements must be supplied directly through the decorations facet;
// CodeMirror rejects block decorations produced by a view plugin.
const tablePreviewDecorations = EditorView.decorations.compute(
  ["doc", "selection", livePreviewEnabled, EditorState.readOnly],
  buildTableDecorations,
);

const livePreviewPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = buildDecorations(view);
    }
    update(update: ViewUpdate) {
      if (
        update.docChanged ||
        update.viewportChanged ||
        update.selectionSet ||
        update.startState.field(livePreviewEnabled) !==
          update.state.field(livePreviewEnabled)
      ) {
        this.decorations = buildDecorations(update.view);
      }
    }
  },
  { decorations: (instance) => instance.decorations },
);

function externalLinkClickExtension(onOpen: (url: string) => void): Extension {
  return EditorView.domEventHandlers({
    mousedown: (event, view) => {
      if (event.button !== 0 || !view.state.field(livePreviewEnabled)) return false;
      const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
      if (pos == null) return false;
      const link = externalLinkAt(view.state, pos);
      if (!link || touches(view.state, link.from, link.to)) return false;

      event.preventDefault();
      onOpen(link.url);
      return true;
    },
  });
}

const livePreviewTheme = EditorView.theme({
  ".cm-list-item-line": {
    paddingLeft: "var(--cm-list-indent)",
  },
  ".cm-list-item-prefix": {
    marginLeft: "calc(-1 * var(--cm-list-indent))",
  },
  ".cm-blockquote-line": {
    borderLeft: "3px solid rgb(var(--zerus-text) / 0.22)",
    paddingLeft: "12px",
  },
  ".cm-codeblock-line": {
    backgroundColor: "rgb(var(--zerus-text) / 0.05)",
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
    fontSize: "0.9em",
    padding: "0 10px",
  },
  ".cm-list-bullet": {
    color: ACCENT,
    fontWeight: "700",
  },
  ".cm-rendered-hr": {
    display: "inline-block",
    width: "100%",
    verticalAlign: "middle",
    borderTop: "1px solid rgb(var(--zerus-text) / 0.2)",
  },
  ".cm-task-checkbox": {
    accentColor: ACCENT,
    width: "15px",
    height: "15px",
    verticalAlign: "middle",
    margin: "0 2px 2px 0",
    cursor: "pointer",
  },
  ".cm-markdown-table-wrapper": {
    boxSizing: "border-box",
    width: "100%",
    // CodeMirror measures block widgets without their CSS margins. Keeping the
    // vertical spacing inside the measured box prevents pointer/selection
    // coordinates below a table from drifting away from the rendered text.
    padding: "20px 0 10px",
    cursor: "text",
  },
  ".cm-markdown-table-card": {
    position: "relative",
    border: "1px solid rgb(var(--zerus-text) / 0.14)",
    borderRadius: "10px",
    backgroundColor: "rgb(var(--zerus-editor-bg))",
    boxShadow: "0 1px 2px rgb(0 0 0 / 0.08)",
  },
  ".cm-markdown-table-scroll": {
    overflowX: "auto",
    borderRadius: "inherit",
  },
  ".cm-markdown-table-toolbar": {
    position: "absolute",
    zIndex: "2",
    top: "-15px",
    right: "8px",
    display: "flex",
    gap: "3px",
    padding: "3px",
    border: "1px solid rgb(var(--zerus-text) / 0.14)",
    borderRadius: "7px",
    backgroundColor: "rgb(var(--zerus-editor-bg))",
    boxShadow: "0 4px 12px rgb(0 0 0 / 0.12)",
    opacity: "0",
    transform: "translateY(2px)",
    pointerEvents: "none",
    transition: "opacity 120ms ease, transform 120ms ease",
  },
  ".cm-markdown-table-wrapper:hover .cm-markdown-table-toolbar, .cm-markdown-table-wrapper:focus-within .cm-markdown-table-toolbar": {
    opacity: "1",
    transform: "translateY(0)",
    pointerEvents: "auto",
  },
  '.cm-markdown-table-wrapper[data-read-only="true"] .cm-markdown-table-toolbar': {
    display: "none",
  },
  ".cm-markdown-table-action": {
    appearance: "none",
    border: "0",
    borderRadius: "5px",
    padding: "4px 8px",
    color: "rgb(var(--zerus-text) / 0.72)",
    backgroundColor: "transparent",
    fontFamily: "inherit",
    fontSize: "11px",
    fontWeight: "600",
    lineHeight: "1.2",
    cursor: "pointer",
  },
  ".cm-markdown-table-action:hover:not(:disabled), .cm-markdown-table-action:focus-visible": {
    color: ACCENT,
    backgroundColor: "rgb(var(--zerus-accent) / 0.1)",
    outline: "none",
  },
  ".cm-markdown-table-action:disabled": {
    opacity: "0.42",
    cursor: "not-allowed",
  },
  ".cm-markdown-table": {
    width: "100%",
    borderCollapse: "collapse",
    fontSize: "0.95em",
    lineHeight: "1.45",
  },
  ".cm-markdown-table th, .cm-markdown-table td": {
    minWidth: "7rem",
    padding: "10px 14px",
    borderRight: "1px solid rgb(var(--zerus-text) / 0.12)",
    borderBottom: "1px solid rgb(var(--zerus-text) / 0.12)",
    textAlign: "left",
    verticalAlign: "top",
    outline: "none",
    cursor: "text",
    transition: "background-color 100ms ease, box-shadow 100ms ease",
  },
  ".cm-markdown-table th": {
    backgroundColor: "rgb(var(--zerus-accent) / 0.09)",
    fontWeight: "650",
    color: "rgb(var(--zerus-text))",
  },
  ".cm-markdown-table tbody tr:nth-child(even) td": {
    backgroundColor: "rgb(var(--zerus-text) / 0.025)",
  },
  ".cm-markdown-table tbody tr:hover td": {
    backgroundColor: "rgb(var(--zerus-accent) / 0.055)",
  },
  ".cm-markdown-table th[contenteditable]:focus, .cm-markdown-table td[contenteditable]:focus": {
    position: "relative",
    backgroundColor: "rgb(var(--zerus-accent) / 0.08)",
    boxShadow: `inset 0 0 0 2px ${ACCENT}`,
  },
  ".cm-markdown-table th.cm-markdown-table-cell-selected, .cm-markdown-table td.cm-markdown-table-cell-selected": {
    backgroundColor: "rgb(var(--zerus-accent) / 0.13) !important",
    backgroundImage: `linear-gradient(${ACCENT}, ${ACCENT}), linear-gradient(${ACCENT}, ${ACCENT}), linear-gradient(${ACCENT}, ${ACCENT}), linear-gradient(${ACCENT}, ${ACCENT})`,
    backgroundPosition: "top, right, bottom, left",
    backgroundRepeat: "no-repeat",
    backgroundSize: "100% var(--cm-table-selection-top, 0), var(--cm-table-selection-right, 0) 100%, 100% var(--cm-table-selection-bottom, 0), var(--cm-table-selection-left, 0) 100%",
    boxShadow: "none",
  },
  ".cm-markdown-table-selection-top": {
    "--cm-table-selection-top": "2px",
  },
  ".cm-markdown-table-selection-right": {
    "--cm-table-selection-right": "2px",
  },
  ".cm-markdown-table-selection-bottom": {
    "--cm-table-selection-bottom": "2px",
  },
  ".cm-markdown-table-selection-left": {
    "--cm-table-selection-left": "2px",
  },
  ".cm-markdown-table tr:last-child td": { borderBottom: "0" },
  ".cm-markdown-table th:last-child, .cm-markdown-table td:last-child": {
    borderRight: "0",
  },
});

/**
 * Bear/Obsidian-style live preview: the document stays plain markdown, but
 * syntax marks are hidden until the cursor enters the construct they belong
 * to. Mod-E toggles raw source mode.
 */
export function livePreviewExtension(
  onOpenExternalLink?: (url: string) => void,
): Extension {
  return [
    livePreviewEnabled,
    keepCursorOutsideClosingMarkup,
    tablePreviewDecorations,
    livePreviewPlugin,
    ...(onOpenExternalLink
      ? [externalLinkClickExtension(onOpenExternalLink)]
      : []),
    livePreviewTheme,
    keymap.of([{ key: "Mod-e", run: toggleLivePreview }]),
  ];
}
