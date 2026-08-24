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
  Prec,
  type Range,
  StateEffect,
  StateField,
} from "@codemirror/state";
import { syntaxTree } from "@codemirror/language";
import { WIKILINK_REGEX } from "@/lib/note-utils";
import { normalizeExternalUrl } from "@/lib/external-links";
import type { EditorMode } from "@/lib/note-preferences";
import { tableDecoration } from "./markdown-table";
import { escapedMarkdownBoundaryFrom } from "./editing-mechanics";
import { markdownEscapeUnits } from "@/lib/markdown-escapes";

const ACCENT = "rgb(var(--zerus-accent))";

// The editor uses a proportional UI font, where a space is roughly 0.25em
// wide. Markdown still needs four literal spaces per nesting level, but its
// visual step should be more distinct than those narrow spaces alone.
const PROPORTIONAL_SPACE_WIDTH_EM = 0.25;
const LIST_NESTING_STEP_EM = 1;
const FIRST_NESTING_OFFSET_EM = 1.1;

function listMarkerIndentEm(marker: string, isTaskItem: boolean): number {
  return isTaskItem
    ? 1.35
    : /^[-*+]$/.test(marker)
      ? 0.8
      : Math.max(1.1, marker.replace(/\D/g, "").length * 0.55 + 0.55);
}

const setModeEffect = StateEffect.define<EditorMode>();

const INLINE_MARKS: Record<string, string> = {
  Emphasis: "EmphasisMark",
  StrongEmphasis: "EmphasisMark",
  InlineCode: "CodeMark",
  Strikethrough: "StrikethroughMark",
  Link: "LinkMark",
};

const EXPLICIT_LINK_REGEX = /https?:\/\/[^\s<>{}[\]"]+/giu;
const INLINE_TAG_REGEX = /(?:^|(?<=\s))(?:\\)?#[\p{L}\p{N}][\p{L}\p{N}/_-]*/gu;

export interface ExternalLinkMatch {
  url: string;
  from: number;
  to: number;
  urlFrom: number;
  urlTo: number;
  labelFrom: number;
  labelTo: number;
  kind: "markdown" | "bare";
}

export interface AutoformatCancellation {
  escapeAt: number[];
  cursor: number;
}

export function listItemIndentEm(
  leadingWhitespace: number,
  marker: string,
  isTaskItem: boolean,
): number {
  const nestingLevel = leadingWhitespace / 4;
  const firstNestingOffset = nestingLevel > 0 ? FIRST_NESTING_OFFSET_EM : 0;
  return (
    firstNestingOffset +
    nestingLevel * LIST_NESTING_STEP_EM +
    listMarkerIndentEm(marker, isTaskItem)
  );
}

export function listItemPrefixOffsetEm(
  leadingWhitespace: number,
  marker: string,
  isTaskItem: boolean,
): number {
  return (
    leadingWhitespace * PROPORTIONAL_SPACE_WIDTH_EM +
    listMarkerIndentEm(marker, isTaskItem)
  );
}

function trimLinkPunctuation(value: string): string {
  return value.replace(/[.,!?;:]+$/g, "");
}

/** Editor links must declare the web protocol instead of guessing from text. */
function normalizeEditorUrl(value: string): string | null {
  const trimmed = value.trim().replace(/^<|>$/g, "");
  return /^https?:\/\//i.test(trimmed) ? normalizeExternalUrl(trimmed) : null;
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

/**
 * Finds a just-completed Markdown pattern that Backspace may turn back into
 * literal text. Callers track recency; this function only describes the edit.
 */
export function autoformatCancellationAt(
  state: EditorState,
): AutoformatCancellation | null {
  const selection = state.selection.main;
  if (!selection.empty) return null;
  const cursor = selection.head;
  const line = state.doc.lineAt(cursor);
  if (cursor === line.to) {
    const patterns: Array<{
      expression: RegExp;
      escapeOffset: (match: RegExpMatchArray) => number;
    }> = [
      { expression: /^(\s*)#{1,6} $/, escapeOffset: (match) => match[1].length },
      { expression: /^(\s*)[-+*] $/, escapeOffset: (match) => match[1].length },
      { expression: /^(\s*)[-+*] \[[ xX]\] $/, escapeOffset: (match) => match[1].length },
      { expression: /^(\s*)> $/, escapeOffset: (match) => match[1].length },
      {
        expression: /^(\s*)(\d+)\. $/,
        escapeOffset: (match) => match[1].length + match[2].length,
      },
    ];
    for (const pattern of patterns) {
      const match = line.text.match(pattern.expression);
      if (match) {
        return {
          escapeAt: [line.from + pattern.escapeOffset(match)],
          cursor,
        };
      }
    }
  }

  for (const bias of [-1, 1] as const) {
    let node = syntaxTree(state).resolveInner(cursor, bias);
    for (; node; node = node.parent) {
      if (node.to !== cursor) continue;
      const markName = INLINE_MARKS[node.name];
      if (!markName) continue;
      const openingMark = node.getChildren(markName)[0];
      if (!openingMark) continue;
      return {
        escapeAt: Array.from(
          { length: openingMark.to - openingMark.from },
          (_, index) => openingMark.from + index,
        ),
        cursor,
      };
    }
  }
  return null;
}

/** Resolve a rendered Markdown link or a pasted web address at a document position. */
export function externalLinkAt(
  state: EditorState,
  pos: number,
): ExternalLinkMatch | null {
  // An image's URL is a source path for its preview, not a link to follow.
  // Check the complete ancestry before inspecting individual URL nodes: when
  // the pointer is over the destination, resolveInner starts at the URL child
  // and would otherwise treat a relative image path as a bare web domain.
  for (const bias of [-1, 1] as const) {
    for (
      let node = syntaxTree(state).resolveInner(pos, bias);
      node;
      node = node.parent
    ) {
      if (node.name === "Image") return null;
    }
  }

  for (const bias of [-1, 1] as const) {
    let node = syntaxTree(state).resolveInner(pos, bias);
    for (; node; node = node.parent) {
      if (node.name === "Link") {
        const urlNode = node.getChild("URL");
        const url =
          urlNode &&
          normalizeEditorUrl(state.sliceDoc(urlNode.from, urlNode.to));
        if (url) {
          const marks = node.getChildren("LinkMark");
          const openingMark = marks[0];
          const closingLabelMark = marks[1];
          if (!openingMark || !closingLabelMark || !urlNode) return null;
          return {
            url,
            from: node.from,
            to: node.to,
            urlFrom: urlNode.from,
            urlTo: urlNode.to,
            labelFrom: openingMark.to,
            labelTo: closingLabelMark.from,
            kind: "markdown",
          };
        }
      }
      if (node.name === "URL") {
        const url = normalizeEditorUrl(state.sliceDoc(node.from, node.to));
        if (url) {
          return {
            url,
            from: node.from,
            to: node.to,
            urlFrom: node.from,
            urlTo: node.to,
            labelFrom: node.from,
            labelTo: node.to,
            kind: "bare",
          };
        }
      }
    }
  }

  const line = state.doc.lineAt(pos);
  if (isTitleHeadingLine(state, line.from, line.text)) return null;
  for (const match of line.text.matchAll(EXPLICIT_LINK_REGEX)) {
    const raw = trimLinkPunctuation(match[0]);
    const from = line.from + (match.index ?? 0);
    const to = from + raw.length;
    if (pos < from || pos > to) continue;
    const url = normalizeEditorUrl(raw);
    if (url) {
      return {
        url,
        from,
        to,
        urlFrom: from,
        urlTo: to,
        labelFrom: from,
        labelTo: to,
        kind: "bare",
      };
    }
  }
  return null;
}

/** Current editor presentation. Clean is the default; Mod-E toggles modes. */
export const editorPresentationMode = StateField.define<EditorMode>({
  create: () => "clean",
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setModeEffect)) value = effect.value;
    }
    return value;
  },
});

export function setEditorPresentationMode(
  view: EditorView,
  mode: EditorMode,
): boolean {
  view.dispatch({
    effects: setModeEffect.of(mode),
  });
  return true;
}

export function toggleEditorPresentationMode(view: EditorView): EditorMode {
  const next =
    view.state.field(editorPresentationMode) === "clean"
      ? "markdown-aware"
      : "clean";
  setEditorPresentationMode(view, next);
  return next;
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
        if (node.name === "Link") {
          const url = node.getChild("URL");
          if (!url || !normalizeEditorUrl(state.sliceDoc(url.from, url.to))) {
            continue;
          }
        }

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

/** Keep a clean-mode caret out of the source-only side of a hidden escape. */
export function moveCursorBeforeEscapedMarkdownSymbol(
  state: EditorState,
  selection: EditorSelection,
): EditorSelection {
  let changed = false;
  const ranges = selection.ranges.map((range) => {
    if (!range.empty) return range;
    const from = escapedMarkdownBoundaryFrom(state, range.head);
    if (from == null) return range;
    changed = true;
    return EditorSelection.cursor(from, range.assoc);
  });
  return changed
    ? EditorSelection.create(ranges, selection.mainIndex)
    : selection;
}

/** Skip source-only escape positions while preserving visual arrow movement. */
function moveCursorAcrossEscapedMarkdownSymbol(
  state: EditorState,
  previous: EditorSelection,
  selection: EditorSelection,
): EditorSelection {
  let changed = false;
  const ranges = selection.ranges.map((range, index) => {
    const previousHead = previous.ranges[index]?.head ?? previous.main.head;
    if (range.head === previousHead) return range;

    let target = range.head;
    if (target > previousHead) {
      while (escapedMarkdownBoundaryFrom(state, target) != null) target += 1;
    } else {
      for (;;) {
        const escapeFrom = escapedMarkdownBoundaryFrom(state, target);
        if (escapeFrom == null) break;
        target = escapeFrom;
      }
    }

    if (target === range.head) return range;
    changed = true;
    return EditorSelection.range(range.anchor, target, range.assoc);
  });
  return changed
    ? EditorSelection.create(ranges, selection.mainIndex)
    : selection;
}

const keepCursorOutsideInlineMarkup = EditorState.transactionFilter.of(
  (transaction) => {
    if (
      !transaction.selection ||
      transaction.docChanged ||
      transaction.startState.field(editorPresentationMode) !== "clean"
    ) {
      return transaction;
    }

    const previous = transaction.startState.selection.main;
    const next = transaction.newSelection.main;
    const keyboardCaretMove =
      transaction.isUserEvent("select") &&
      !transaction.isUserEvent("select.pointer") &&
      previous.head !== next.head;

    // Hidden formatting marks are atomic, so keyboard movement normally stays
    // untouched. A literal symbol's hidden escape is different: landing
    // between `\` and `*` has no visual position and makes an arrow key appear
    // stuck. Skip that source-only boundary in the direction of travel.
    if (keyboardCaretMove) {
      const acrossEscape = moveCursorAcrossEscapedMarkdownSymbol(
        transaction.state,
        transaction.startState.selection,
        transaction.newSelection,
      );
      return acrossEscape === transaction.newSelection
        ? transaction
        : [transaction, { selection: acrossEscape, sequential: true }];
    }

    const beforeEscape = moveCursorBeforeEscapedMarkdownSymbol(
      transaction.state,
      transaction.newSelection,
    );
    const beforeOpening = moveCursorBeforeOpeningMarkup(
      transaction.state,
      beforeEscape,
    );
    const outside = moveCursorPastClosingMarkup(
      transaction.state,
      beforeOpening,
    );
    return outside === transaction.newSelection
      ? transaction
      : [transaction, { selection: outside, sequential: true }];
  },
);

/** Find the complete hidden opening syntax immediately before a caret. */
export function openingInlineMarkupFrom(
  state: EditorState,
  cursor: number,
): number | null {
  const openings: Array<{ from: number; to: number }> = [];
  const visited = new Set<string>();

  for (const bias of [-1, 1] as const) {
    for (
      let node = syntaxTree(state).resolveInner(cursor, bias);
      node;
      node = node.parent
    ) {
      const markName = INLINE_MARKS[node.name];
      if (!markName) continue;
      const marks = node.getChildren(markName);
      const opening = marks[0];
      const closing = marks[marks.length - 1];
      if (!opening || !closing || opening === closing) continue;
      const key = `${opening.from}:${opening.to}`;
      if (visited.has(key)) continue;
      visited.add(key);
      openings.push({ from: opening.from, to: opening.to });
    }
  }

  // A caret at the visual left edge of a replacement can map anywhere inside
  // a multi-character opening mark (not just immediately after it). Normalize
  // that platform-dependent position first. Nested markup can then have
  // adjacent opening marks, as in `***text***`, so walk across all of them.
  let from = openings
    .filter((opening) => opening.from < cursor && cursor <= opening.to)
    .reduce((earliest, opening) => Math.min(earliest, opening.from), cursor);
  for (;;) {
    const adjacent = openings.filter((opening) => opening.to === from);
    if (!adjacent.length) break;
    from = Math.min(...adjacent.map((opening) => opening.from));
  }
  return from === cursor ? null : from;
}

/** Move a visual left-edge caret before all hidden opening delimiters. */
export function moveCursorBeforeOpeningMarkup(
  state: EditorState,
  selection: EditorSelection,
): EditorSelection {
  let changed = false;
  const ranges = selection.ranges.map((range) => {
    if (!range.empty) return range;
    const from = openingInlineMarkupFrom(state, range.head);
    if (from == null) return range;
    changed = true;
    return EditorSelection.cursor(from, range.assoc);
  });
  return changed
    ? EditorSelection.create(ranges, selection.mainIndex)
    : selection;
}

export interface InlineMarkupBoundary {
  from: number;
  to: number;
  kind: string;
  side: "opening" | "closing";
}

/** Finds a complete inline construct at either hidden visual boundary. */
export function inlineMarkupBoundaryAt(
  state: EditorState,
  cursor: number,
): InlineMarkupBoundary | null {
  const candidates: Array<{ from: number; to: number; kind: string }> = [];
  const visited = new Set<string>();
  for (const bias of [-1, 1] as const) {
    for (
      let node = syntaxTree(state).resolveInner(cursor, bias);
      node;
      node = node.parent
    ) {
      const markName = INLINE_MARKS[node.name];
      if (!markName) continue;
      const marks = node.getChildren(markName);
      if (marks.length < 2 || marks[0] === marks[marks.length - 1]) continue;
      const key = `${node.from}:${node.to}`;
      if (visited.has(key)) continue;
      visited.add(key);
      candidates.push({ from: node.from, to: node.to, kind: node.name });
    }
  }

  const openingFrom = openingInlineMarkupFrom(state, cursor);
  if (openingFrom != null) {
    const opening = candidates
      .filter((candidate) => candidate.from === openingFrom)
      .sort((a, b) => b.to - a.to)[0];
    if (opening) return { ...opening, side: "opening" };
  }

  const closing = candidates
    .filter((candidate) => candidate.to === cursor)
    .sort((a, b) => a.from - b.from)[0];
  return closing ? { ...closing, side: "closing" } : null;
}

/**
 * At a line-start left edge, delete the preceding newline without entering the
 * hidden opening syntax. At the right edge, remove the complete inline
 * formatting construct atomically.
 */
export function handleInlineMarkupBoundaryBackspace(
  view: EditorView,
): boolean {
  if (view.state.field(editorPresentationMode) !== "clean") return false;
  const selection = view.state.selection.main;
  if (!selection.empty) return false;

  const boundary = inlineMarkupBoundaryAt(view.state, selection.head);
  if (!boundary) return false;
  if (boundary.side === "opening") {
    const line = view.state.doc.lineAt(boundary.from);
    const sourceBeforeMarkup = view.state.sliceDoc(line.from, boundary.from);
    if (/^\\*#$/.test(sourceBeforeMarkup)) {
      const escapedHashFrom = escapedMarkdownBoundaryFrom(
        view.state,
        boundary.from - 1,
      );
      const deleteFrom = escapedHashFrom ?? boundary.from - 1;
      view.dispatch({
        changes: { from: deleteFrom, to: boundary.from },
        selection: EditorSelection.cursor(deleteFrom),
        scrollIntoView: true,
        userEvent: "delete.backward",
      });
      return true;
    }
    if (boundary.from !== line.from) {
      view.dispatch({
        changes: { from: boundary.from - 1, to: boundary.from },
        selection: EditorSelection.cursor(boundary.from - 1),
        scrollIntoView: true,
        userEvent: "delete.backward",
      });
      return true;
    }
    if (line.number === 1) return true;
    view.dispatch({
      changes: { from: line.from - 1, to: line.from },
      selection: EditorSelection.cursor(line.from - 1),
      scrollIntoView: true,
      userEvent: "delete.backward",
    });
    return true;
  }

  if (boundary.kind === "Link") {
    const node = syntaxTree(view.state).resolveInner(boundary.from, 1);
    let link = node;
    while (link && link.name !== "Link") link = link.parent;
    const marks = link?.getChildren("LinkMark") ?? [];
    const labelFrom = marks[0]?.to;
    const labelTo = marks[1]?.from;
    if (labelFrom == null || labelTo == null) return true;
    const label = view.state.sliceDoc(labelFrom, labelTo);
    view.dispatch({
      changes: { from: boundary.from, to: boundary.to, insert: label },
      selection: EditorSelection.cursor(boundary.from + label.length),
      scrollIntoView: true,
      userEvent: "delete.backward",
    });
    return true;
  }

  const markerName = INLINE_MARKS[boundary.kind];
  if (!markerName) return true;
  const markers: Array<{ from: number; to: number }> = [];
  syntaxTree(view.state).iterate({
    from: boundary.from,
    to: boundary.to,
    enter: (node) => {
      if (node.name === markerName) {
        markers.push({ from: node.from, to: node.to });
      }
    },
  });
  if (!markers.length) return true;
  const changes = view.state.changes(
    markers.map((marker) => ({ from: marker.from, to: marker.to })),
  );
  view.dispatch({
    changes,
    selection: EditorSelection.cursor(changes.mapPos(selection.head, -1)),
    scrollIntoView: true,
    userEvent: "delete.backward",
  });
  return true;
}

/** Delete selected visible characters together with their hidden source escapes. */
export function deleteCleanSelection(
  view: EditorView,
  direction: "backward" | "forward",
): boolean {
  if (view.state.field(editorPresentationMode) !== "clean") return false;
  const selected = view.state.selection.ranges.filter((range) => !range.empty);
  if (selected.length === 0) return false;
  const units = markdownEscapeUnits(view.state.doc.toString());
  const changes = selected.map((range) => {
    const hidden = units
      .filter(
        (unit) =>
          unit.visibleFrom >= range.from && unit.visibleFrom < range.to,
      )
      .map((unit) => unit.escapeFrom);
    return {
      from: hidden.length ? Math.min(range.from, ...hidden) : range.from,
      to: range.to,
    };
  });
  const changeSet = view.state.changes(changes);
  view.dispatch({
    changes: changeSet,
    selection: EditorSelection.create(
      view.state.selection.ranges.map((range) =>
        EditorSelection.cursor(changeSet.mapPos(range.from, -1)),
      ),
      view.state.selection.mainIndex,
    ),
    scrollIntoView: true,
    userEvent: `delete.${direction}`,
  });
  return true;
}

/** Insert a newline before hidden syntax instead of splitting it. */
export function handleInlineMarkupBoundaryEnter(view: EditorView): boolean {
  if (view.state.field(editorPresentationMode) !== "clean") return false;
  const selection = view.state.selection.main;
  if (!selection.empty) return false;

  const escapeFrom = escapedMarkdownBoundaryFrom(
    view.state,
    selection.head,
  );
  if (escapeFrom != null) {
    view.dispatch({
      changes: { from: escapeFrom, insert: "\n" },
      selection: EditorSelection.cursor(escapeFrom + 1),
      scrollIntoView: true,
      userEvent: "input",
    });
    return true;
  }

  const boundary = inlineMarkupBoundaryAt(view.state, selection.head);
  if (!boundary || boundary.side !== "opening") return false;
  view.dispatch({
    changes: { from: boundary.from, insert: "\n" },
    selection: EditorSelection.cursor(boundary.from + 1),
    scrollIntoView: true,
    userEvent: "input",
  });
  return true;
}

/** Insert whitespace after hidden closing syntax so formatting stays valid. */
export function handleInlineMarkupBoundarySpace(view: EditorView): boolean {
  if (view.state.field(editorPresentationMode) !== "clean") return false;
  const selection = view.state.selection.main;
  if (!selection.empty) return false;

  // A caret at the visual left edge of a literal Markdown symbol can resolve
  // between its hidden escape and the symbol (`\\|*`). Insert before the
  // complete pair so Space indents the visible symbol instead of splitting the
  // escape and exposing its backslash.
  const escapeFrom = escapedMarkdownBoundaryFrom(
    view.state,
    selection.head,
  );
  if (escapeFrom != null) {
    view.dispatch({
      changes: { from: escapeFrom, insert: " " },
      selection: EditorSelection.cursor(escapeFrom + 1),
      scrollIntoView: true,
      userEvent: "input.type",
    });
    return true;
  }

  const outside = moveCursorPastClosingMarkup(
    view.state,
    view.state.selection,
  );
  if (outside === view.state.selection) return false;

  const insertAt = outside.main.head;
  view.dispatch({
    changes: { from: insertAt, insert: " " },
    selection: EditorSelection.cursor(insertAt + 1),
    scrollIntoView: true,
    userEvent: "input.type",
  });
  return true;
}

/** True when any selection range touches [from, to], including boundaries. */
function touches(state: EditorState, from: number, to: number): boolean {
  return state.selection.ranges.some(
    (range) => range.from <= to && range.to >= from,
  );
}

/** A one-line opening fence remains literal until Enter confirms it. */
export function isConfirmedFencedCode(
  state: EditorState,
  from: number,
  to: number,
): boolean {
  return state.doc.lineAt(from).number !== state.doc.lineAt(Math.max(from, to - 1)).number;
}

/** Markdown-aware mode exposes a table's source while its range is active. */
export function shouldRenderTablePreview(
  state: EditorState,
  from: number,
  to: number,
): boolean {
  return (
    state.field(editorPresentationMode) === "clean" ||
    !touches(state, from, to)
  );
}

/** Structural Markdown remains visible until Space confirms the transform. */
export function isSpaceConfirmedStructuralMark(
  state: EditorState,
  markTo: number,
): boolean {
  return state.sliceDoc(markTo, markTo + 1) === " ";
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
  const { state } = view;
  const clean = state.field(editorPresentationMode) === "clean";
  const decos: Range<Decoration>[] = [];
  const decoratedListLines = new Set<number>();

  const hide = (from: number, to: number) => {
    if (from < to) {
      decos.push(Decoration.replace({ atomic: true }).range(from, to));
    }
  };
  /** Hides [from, to] plus one trailing space, if present. */
  const hideWithSpace = (from: number, to: number) => {
    hide(from, to + (state.sliceDoc(to, to + 1) === " " ? 1 : 0));
  };

  if (clean) {
    // Decode CommonMark escape runs by parity. Hiding every slash in a run
    // loses deliberately typed backslashes and makes deletion/copy disagree
    // with what Clean mode displays.
    const scannedLines = new Set<string>();
    for (const range of view.visibleRanges) {
      const lineFrom = state.doc.lineAt(range.from).from;
      const lineTo = state.doc.lineAt(range.to).to;
      const key = `${lineFrom}:${lineTo}`;
      if (scannedLines.has(key)) continue;
      scannedLines.add(key);
      for (const unit of markdownEscapeUnits(
        state.sliceDoc(lineFrom, lineTo),
        lineFrom,
      )) {
        hide(unit.escapeFrom, unit.escapeFrom + 1);
      }
    }
  }

  for (const { from, to } of view.visibleRanges) {
    for (const match of state.sliceDoc(from, to).matchAll(EXPLICIT_LINK_REGEX)) {
      const raw = trimLinkPunctuation(match[0]);
      const start = from + (match.index ?? 0);
      const line = state.doc.lineAt(start);
      if (isTitleHeadingLine(state, line.from, line.text)) continue;
      if (!raw || !normalizeEditorUrl(raw)) continue;
      decos.push(
        Decoration.mark({
          class: "cm-external-link",
          attributes: { title: "Open in browser" },
        }).range(start, start + raw.length),
      );
    }

    if (clean) {
      const visibleSource = state.sliceDoc(from, to);
      for (const match of visibleSource.matchAll(INLINE_TAG_REGEX)) {
        const start = from + (match.index ?? 0);
        const hashFrom = start + (match[0].startsWith("\\") ? 1 : 0);
        hide(hashFrom, hashFrom + 1);
      }
    }

    // [[wikilinks]]: hide the brackets, keep the title (styled elsewhere).
    const regex = new RegExp(WIKILINK_REGEX.source, "g");
    for (const match of state.sliceDoc(from, to).matchAll(regex)) {
      const start = from + (match.index ?? 0);
      const end = start + match[0].length;
      if (!clean && touches(state, start, end)) continue;
      const titleOffset = match[0].indexOf(match[1]);
      for (let index = 0; index < titleOffset; index += 1) {
        if (match[0][index] === "[") hide(start + index, start + index + 1);
      }
      hide(end - 2, end);
    }

    syntaxTree(state).iterate({
      from,
      to,
      enter: (node) => {
        const name = node.name;

        if (/^ATXHeading[1-6]$/.test(name)) {
          const level = Number(name.slice(-1));
          decos.push(
            Decoration.line({ class: `cm-heading-line-${level}` }).range(
              state.doc.lineAt(node.from).from,
            ),
          );
          // Reveal on the whole line: `#` governs the whole heading.
          if (!clean && touches(state, node.from, node.to)) return;
          const mark = node.node.getChild("HeaderMark");
          if (mark && isSpaceConfirmedStructuralMark(state, mark.to)) {
            hideWithSpace(mark.from, mark.to);
          }
          return;
        }

        switch (name) {
          case "Emphasis":
          case "StrongEmphasis": {
            if (!clean && touches(state, node.from, node.to)) return;
            for (const mark of node.node.getChildren("EmphasisMark")) {
              hide(mark.from, mark.to);
            }
            return;
          }
          case "InlineCode": {
            if (!clean && touches(state, node.from, node.to)) return;
            for (const mark of node.node.getChildren("CodeMark")) {
              hide(mark.from, mark.to);
            }
            return;
          }
          case "Strikethrough": {
            if (!clean && touches(state, node.from, node.to)) return;
            for (const mark of node.node.getChildren("StrikethroughMark")) {
              hide(mark.from, mark.to);
            }
            return;
          }
          case "Link": {
            // Only true `[text](url)` links; bare `[ref]` (e.g. inside
            // wikilinks) has no URL child and is left alone.
            const url = node.node.getChild("URL");
            if (
              !url ||
              !normalizeEditorUrl(state.sliceDoc(url.from, url.to))
            ) {
              return;
            }
            const marks = node.node.getChildren("LinkMark");
            if (marks.length < 2) return false;
            if (!clean && touches(state, node.from, node.to)) return false;
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
            if (!clean && touches(state, line.from, line.to)) return false;
            if (
              !state.sliceDoc(line.from, node.from).trim() &&
              !state.sliceDoc(node.to, line.to).trim()
            ) {
              // The block widget is the complete visual representation of a
              // standalone image. Collapse its otherwise-empty source line so
              // it does not leave a full text row above the preview.
              decos.push(
                Decoration.line({ class: "cm-image-source-line" }).range(
                  line.from,
                ),
              );
            }
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
            if (!isSpaceConfirmedStructuralMark(state, node.to)) return;
            if (!clean && touches(state, line.from, line.to)) return;
            hideWithSpace(node.from, node.to);
            return;
          }
          case "ListMark": {
            if (!isSpaceConfirmedStructuralMark(state, node.to)) return;
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
              const prefixOffset = listItemPrefixOffsetEm(
                leadingWhitespace,
                marker,
                isTaskItem,
              );

              decos.push(
                Decoration.line({
                  class: "cm-list-item-line",
                  attributes: {
                    style: `--cm-list-indent: ${indent}em; --cm-list-prefix-offset: ${prefixOffset}em`,
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
              if (!clean && touches(state, node.from, node.to)) return;
              hideWithSpace(node.from, node.to);
              return;
            }
            const text = state.sliceDoc(node.from, node.to);
            if (!/^[-*+]$/.test(text)) return;
            if (!clean && touches(state, node.from, node.to)) return;
            decos.push(
              Decoration.replace({ widget: new BulletWidget(), atomic: true }).range(
                node.from,
                node.to,
              ),
            );
            return;
          }
          case "TaskMarker": {
            if (!clean && touches(state, node.from, node.to)) return;
            const checked = /x/i.test(state.sliceDoc(node.from, node.to));
            decos.push(
              Decoration.replace({
                widget: new CheckboxWidget(checked),
                atomic: true,
              }).range(
                node.from,
                node.to,
              ),
            );
            return;
          }
          case "HorizontalRule": {
            const line = state.doc.lineAt(node.from);
            if (!clean && touches(state, line.from, line.to)) return;
            decos.push(
              Decoration.replace({ widget: new HrWidget(), atomic: true }).range(
                node.from,
                node.to,
              ),
            );
            return;
          }
          case "FencedCode": {
            if (!isConfirmedFencedCode(state, node.from, node.to)) return;
            const firstLine = state.doc.lineAt(node.from);
            const lastLine = state.doc.lineAt(Math.max(node.from, node.to - 1));
            for (let pos = node.from; pos <= node.to; ) {
              const line = state.doc.lineAt(pos);
              const positionClass =
                line.number === firstLine.number
                  ? " cm-codeblock-first"
                  : line.number === lastLine.number
                    ? " cm-codeblock-last"
                    : "";
              decos.push(
                Decoration.line({
                  class: `cm-codeblock-line${positionClass}`,
                }).range(line.from),
              );
              pos = line.to + 1;
            }
            if (!clean && touches(state, node.from, node.to)) return;
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
  const decorations: Range<Decoration>[] = [];
  const markdownAware =
    state.field(editorPresentationMode) === "markdown-aware";
  syntaxTree(state).iterate({
    enter: (node) => {
      if (node.name !== "Table") return;
      if (!shouldRenderTablePreview(state, node.from, node.to)) return false;
      decorations.push(
        tableDecoration(
          state.sliceDoc(node.from, node.to),
          node.from,
          state.readOnly,
          markdownAware,
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
  ["doc", "selection", editorPresentationMode, EditorState.readOnly],
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
        update.startState.field(editorPresentationMode) !==
          update.state.field(editorPresentationMode)
      ) {
        this.decorations = buildDecorations(update.view);
      }
    }
  },
  { decorations: (instance) => instance.decorations },
);

const reversibleAutoformatPlugin = ViewPlugin.fromClass(
  class {
    recent: AutoformatCancellation | null = null;

    update(update: ViewUpdate) {
      if (update.docChanged) {
        const wasTyped = update.transactions.some((transaction) =>
          transaction.isUserEvent("input"),
        );
        this.recent =
          wasTyped && update.state.field(editorPresentationMode) === "clean"
            ? autoformatCancellationAt(update.state)
            : null;
        return;
      }

      if (
        update.selectionSet ||
        update.startState.field(editorPresentationMode) !==
          update.state.field(editorPresentationMode)
      ) {
        this.recent = null;
      }
    }
  },
);

/** Restore the Markdown characters consumed by the latest clean-mode transform. */
export function cancelRecentAutoformat(
  view: EditorView,
  markdownTypingEnabled = true,
): boolean {
  if (!markdownTypingEnabled) return false;
  if (view.state.field(editorPresentationMode) !== "clean") return false;
  const cancellation = view.plugin(reversibleAutoformatPlugin)?.recent;
  if (
    !cancellation ||
    !view.state.selection.main.empty ||
    view.state.selection.main.head !== cancellation.cursor
  ) {
    return false;
  }

  const changes = view.state.changes(
    cancellation.escapeAt.map((from) => ({ from, insert: "\\" })),
  );
  view.dispatch({
    changes,
    selection: EditorSelection.cursor(changes.mapPos(cancellation.cursor, 1)),
    userEvent: "input.escapeMarkdown",
  });
  return true;
}

const livePreviewAtomicRanges = EditorView.atomicRanges.of((view) => {
  const decorations = view.plugin(livePreviewPlugin)?.decorations;
  if (!decorations) return Decoration.none;
  const ranges: Range<Decoration>[] = [];
  decorations.between(0, view.state.doc.length, (from, to, value) => {
    if (value.spec.atomic) ranges.push(value.range(from, to));
  });
  return Decoration.set(ranges, true);
});

interface ExternalLinkInteractionOptions {
  onOpen: (url: string) => void;
  initialMode?: EditorMode;
  markdownTypingEnabled?: () => boolean;
  onModeChange?: (mode: EditorMode) => void;
  onSelect?: (
    link: ExternalLinkMatch,
    anchor: { element: HTMLElement },
  ) => void;
  onDismiss?: () => void;
}

export function shouldOpenExternalLink(
  event: Pick<MouseEvent, "button" | "metaKey" | "ctrlKey" | "detail">,
): boolean {
  return (
    event.button === 0 &&
    (event.metaKey || event.ctrlKey || event.detail >= 2)
  );
}

function externalLinkClickExtension(
  options: ExternalLinkInteractionOptions,
): Extension {
  return EditorView.domEventHandlers({
    mousedown: (event, view) => {
      if (event.button !== 0) return false;
      const pos = view.posAtCoords({ x: event.clientX, y: event.clientY });
      if (pos == null) {
        options.onDismiss?.();
        return false;
      }
      const link = externalLinkAt(view.state, pos);
      if (!link) {
        options.onDismiss?.();
        return false;
      }

      if (shouldOpenExternalLink(event)) {
        event.preventDefault();
        options.onDismiss?.();
        options.onOpen(link.url);
        return true;
      }

      const element =
        event.target instanceof Element
          ? event.target.closest<HTMLElement>(".cm-external-link")
          : null;
      if (element) options.onSelect?.(link, { element });
      return false;
    },
  });
}

const livePreviewTheme = EditorView.theme({
  ".cm-heading-line-1": {
    fontSize: "1.55em",
    fontWeight: "700",
    lineHeight: "1.3",
  },
  ".cm-heading-line-2": {
    fontSize: "1.3em",
    fontWeight: "700",
    lineHeight: "1.4",
  },
  ".cm-heading-line-3": {
    fontSize: "1.15em",
    fontWeight: "600",
    lineHeight: "1.45",
  },
  ".cm-heading-line-4, .cm-heading-line-5, .cm-heading-line-6": {
    fontWeight: "600",
  },
  ".cm-list-item-line": {
    paddingLeft: "var(--cm-list-indent)",
  },
  ".cm-list-item-prefix": {
    marginLeft: "calc(-1 * var(--cm-list-prefix-offset))",
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
  ".cm-codeblock-first": {
    paddingTop: "8px",
    borderRadius: "8px 8px 0 0",
  },
  ".cm-codeblock-last": {
    paddingBottom: "8px",
    borderRadius: "0 0 8px 8px",
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
 * The document always stays plain Markdown. Clean mode keeps completed syntax
 * hidden; Markdown-aware mode reveals the construct around the cursor. Mod-E
 * switches between the two presentations without replacing the editor.
 */
export function livePreviewExtension(
  externalLinks?: ((url: string) => void) | ExternalLinkInteractionOptions,
): Extension {
  const externalLinkOptions =
    typeof externalLinks === "function"
      ? { onOpen: externalLinks }
      : externalLinks;
  return [
    editorPresentationMode.init(
      () => externalLinkOptions?.initialMode ?? "clean",
    ),
    keepCursorOutsideInlineMarkup,
    tablePreviewDecorations,
    livePreviewPlugin,
    reversibleAutoformatPlugin,
    livePreviewAtomicRanges,
    ...(externalLinkOptions
      ? [externalLinkClickExtension(externalLinkOptions)]
      : []),
    livePreviewTheme,
    Prec.highest(
      keymap.of([
        {
          key: "Space",
          run: handleInlineMarkupBoundarySpace,
        },
        {
          key: "Enter",
          run: handleInlineMarkupBoundaryEnter,
        },
        {
          key: "Backspace",
          run: (view) =>
            deleteCleanSelection(view, "backward") ||
            handleInlineMarkupBoundaryBackspace(view) ||
            cancelRecentAutoformat(
              view,
              externalLinkOptions?.markdownTypingEnabled?.() ?? true,
            ),
        },
        {
          key: "Delete",
          run: (view) => deleteCleanSelection(view, "forward"),
        },
        {
          key: "Mod-e",
          run: (view) => {
            const mode = toggleEditorPresentationMode(view);
            externalLinkOptions?.onModeChange?.(mode);
            return true;
          },
        },
      ]),
    ),
  ];
}
