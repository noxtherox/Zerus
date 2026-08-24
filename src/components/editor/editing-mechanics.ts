import { insertNewlineContinueMarkupCommand } from "@codemirror/lang-markdown";
import { syntaxTree } from "@codemirror/language";
import {
  EditorSelection,
  EditorState,
  type Text,
  type Extension,
  type StateCommand,
  Prec,
} from "@codemirror/state";
import { EditorView, keymap, type KeyBinding } from "@codemirror/view";
import { IMAGE_MD_REGEX } from "@/lib/note-utils";
import {
  markdownEscapeUnits,
  type MarkdownEscapeUnit,
} from "@/lib/markdown-escapes";

function escapeUnitsNear(
  state: EditorState,
  position: number,
): MarkdownEscapeUnit[] {
  const bounded = Math.max(0, Math.min(position, state.doc.length));
  const line = state.doc.lineAt(bounded);
  return markdownEscapeUnits(line.text, line.from);
}

/**
 * Returns the hidden escape immediately before a visible literal Markdown
 * symbol. Both positions occupy the same visual boundary in clean mode.
 */
export function escapedMarkdownBoundaryFrom(
  state: EditorState,
  cursor: number,
): number | null {
  return (
    escapeUnitsNear(state, cursor).find(
      (unit) => unit.visibleFrom === cursor,
    )?.escapeFrom ?? null
  );
}

function escapedUnitBefore(
  state: EditorState,
  cursor: number,
): MarkdownEscapeUnit | null {
  return (
    escapeUnitsNear(state, cursor).find((unit) => unit.to === cursor) ?? null
  );
}

function escapedUnitAtBoundary(
  state: EditorState,
  cursor: number,
): MarkdownEscapeUnit | null {
  return (
    escapeUnitsNear(state, cursor).find(
      (unit) => unit.escapeFrom === cursor || unit.visibleFrom === cursor,
    ) ?? null
  );
}

const continueMarkdownMarkup = insertNewlineContinueMarkupCommand({
  nonTightLists: false,
});

function fencedCodeOpening(line: string) {
  return line.match(/^(\s*)(`{3,}|~{3,})([^\r\n]*)$/);
}

/** Confirm a newly typed code fence and create its matching closing fence. */
export const openFencedCodeBlock: StateCommand = ({ state, dispatch }) => {
  const selection = state.selection.main;
  if (!selection.empty) return false;
  const line = state.doc.lineAt(selection.head);
  if (selection.head !== line.to) return false;
  const opening = fencedCodeOpening(line.text);
  if (!opening) return false;

  const markerFrom = line.from + opening[1].length;
  let node = syntaxTree(state).resolveInner(markerFrom, 1);
  while (node && node.name !== "FencedCode") node = node.parent;
  if (!node) return false;
  const marks = node.getChildren("CodeMark");
  // A closing fence has a second CodeMark. Only expand the opening line.
  if (marks.length !== 1 || marks[0].from !== markerFrom) return false;

  const indent = opening[1];
  const closing = `${indent}${opening[2]}`;
  dispatch(
    state.update({
      changes: {
        from: selection.head,
        insert: `\n${indent}\n${closing}`,
      },
      selection: { anchor: selection.head + 1 + indent.length },
      scrollIntoView: true,
      userEvent: "input",
    }),
  );
  return true;
};

/** Backspace on the first empty code line returns to the literal opening fence. */
export const exitEmptyFencedCodeBlock: StateCommand = ({ state, dispatch }) => {
  const selection = state.selection.main;
  if (!selection.empty) return false;
  const line = state.doc.lineAt(selection.head);
  if (
    selection.head !== line.to ||
    line.number <= 1 ||
    line.number >= state.doc.lines
  ) {
    return false;
  }

  const previous = state.doc.line(line.number - 1);
  const next = state.doc.line(line.number + 1);
  const opening = fencedCodeOpening(previous.text);
  if (
    !opening ||
    line.text !== opening[1] ||
    next.text !== `${opening[1]}${opening[2]}`
  ) {
    return false;
  }

  dispatch(
    state.update({
      changes: { from: previous.to, to: next.to },
      selection: { anchor: previous.to },
      scrollIntoView: true,
      userEvent: "delete.backward",
    }),
  );
  return true;
};

/** Delete a visible escaped Markdown symbol together with its hidden escape. */
export const deleteEscapedMarkdownSymbolBackward: StateCommand = ({
  state,
  dispatch,
}) => {
  const selection = state.selection.main;
  if (!selection.empty) return false;

  const cursor = selection.head;
  const unit = escapedUnitBefore(state, cursor);
  if (!unit) return false;

  dispatch(
    state.update({
      changes: { from: unit.escapeFrom, to: unit.to },
      selection: { anchor: unit.escapeFrom },
      scrollIntoView: true,
      userEvent: "delete.backward",
    }),
  );
  return true;
};

/**
 * Backspace from the ambiguous position after a hidden escape must operate on
 * the preceding visible character, not silently remove the escape itself.
 */
export const deleteBeforeEscapedMarkdownSymbolBackward: StateCommand = ({
  state,
  dispatch,
}) => {
  const selection = state.selection.main;
  if (!selection.empty) return false;

  const boundary = escapedMarkdownBoundaryFrom(state, selection.head);
  if (boundary == null) return false;

  const line = state.doc.lineAt(boundary);
  if (boundary === line.from) {
    if (line.number === 1) return true;
    dispatch(
      state.update({
        changes: { from: boundary - 1, to: boundary },
        selection: { anchor: boundary - 1 },
        scrollIntoView: true,
        userEvent: "delete.backward",
      }),
    );
    return true;
  }

  const previousUnit = escapedUnitBefore(state, boundary);
  const deleteFrom = previousUnit?.escapeFrom ?? boundary - 1;
  dispatch(
    state.update({
      changes: { from: deleteFrom, to: boundary },
      selection: { anchor: deleteFrom },
      scrollIntoView: true,
      userEvent: "delete.backward",
    }),
  );
  return true;
};

/** Delete a literal escaped symbol from either source position before it. */
export const deleteEscapedMarkdownSymbolForward: StateCommand = ({
  state,
  dispatch,
}) => {
  const selection = state.selection.main;
  if (!selection.empty) return false;

  const cursor = selection.head;
  const unit = escapedUnitAtBoundary(state, cursor);
  if (!unit) return false;

  dispatch(
    state.update({
      changes: { from: unit.escapeFrom, to: unit.to },
      selection: { anchor: unit.escapeFrom },
      scrollIntoView: true,
      userEvent: "delete.forward",
    }),
  );
  return true;
};

/**
 * Delete a former heading's `#` directly when the caret sits after it.
 *
 * Removing the space from `# Hello` reparses the line as `#Hello`; with inline
 * formatting it can instead become `#**Hello**`. In WKWebView, a following
 * native Backspace can race the decoration change at that boundary and feed
 * stale styled DOM back into CodeMirror. A state-level edit keeps the document
 * and the surviving inline formatting authoritative during that transition.
 */
export const deleteInlineTagMarkerBackward: StateCommand = ({
  state,
  dispatch,
}) => {
  const selection = state.selection.main;
  if (!selection.empty) return false;

  const cursor = selection.head;
  const line = state.doc.lineAt(cursor);
  const formattedFormerHeading = line.text.match(
    /^(\\*)#(?=(?:\*\*[^\r\n]+\*\*|__[^\r\n]+__))/u,
  );
  if (formattedFormerHeading) {
    const hashFrom = line.from + formattedFormerHeading[1].length;
    const hashTo = hashFrom + 1;
    const escapedHash = escapeUnitsNear(state, hashFrom).find(
      (unit) => unit.visibleFrom === hashFrom,
    );
    const hashDeleteFrom = escapedHash?.escapeFrom ?? hashFrom;
    // The hidden opening `**`/`__` occupies the same visual boundary as the
    // position immediately after `#`. CodeMirror may resolve that caret to any
    // of these three source positions, especially after a decoration update.
    if (cursor >= hashTo && cursor <= hashTo + 2) {
      dispatch(
        state.update({
          changes: { from: hashDeleteFrom, to: hashTo },
          selection: { anchor: hashDeleteFrom },
          scrollIntoView: true,
          userEvent: "delete.backward",
        }),
      );
      return true;
    }
  }

  const marker = cursor - 1;
  const escapedMarker = escapedUnitBefore(state, cursor);
  const deleteFrom =
    escapedMarker?.visibleFrom === marker
      ? escapedMarker.escapeFrom
      : marker;
  const hasEscapePrefix = deleteFrom < marker;
  const textAfterMarker = state.sliceDoc(cursor, line.to);
  const startsInlineTag = /^[\p{L}\p{N}][\p{L}\p{N}/_-]*/u.test(
    textAfterMarker,
  );
  const startsFormattedText = /^(?:\*\*[^\r\n]+\*\*|__[^\r\n]+__)/u.test(
    textAfterMarker,
  );
  if (
    marker < line.from ||
    state.sliceDoc(marker, cursor) !== "#" ||
    (!hasEscapePrefix && !startsInlineTag && !startsFormattedText)
  ) {
    return false;
  }

  // Inline tags only start at the beginning of a line or after whitespace.
  // A visible literal marker carries an escape immediately before it; remove
  // the complete escape prefix with the marker so none becomes visible.
  if (
    deleteFrom > line.from &&
    !/\s/u.test(state.sliceDoc(deleteFrom - 1, deleteFrom))
  ) {
    return false;
  }

  dispatch(
    state.update({
      changes: { from: deleteFrom, to: cursor },
      selection: { anchor: deleteFrom },
      scrollIntoView: true,
      userEvent: "delete.backward",
    }),
  );
  return true;
};

function standaloneImage(text: string): RegExpMatchArray | null {
  const matches = [...text.matchAll(IMAGE_MD_REGEX)];
  if (matches.length !== 1) return null;
  const image = matches[0];
  const from = image.index ?? 0;
  const to = from + image[0].length;
  return text.slice(0, from).trim() || text.slice(to).trim() ? null : image;
}

/** Delete a standalone image from the caret visually positioned after it. */
export const deleteImageBackward: StateCommand = ({ state, dispatch }) => {
  const selection = state.selection.main;
  if (!selection.empty) return false;

  const line = state.doc.lineAt(selection.head);
  if (selection.head === line.to && standaloneImage(line.text)) {
    dispatch(
      state.update({
        changes: { from: line.from, to: line.to },
        selection: { anchor: line.from },
        scrollIntoView: true,
        userEvent: "delete.backward",
      }),
    );
    return true;
  }

  if (selection.head !== line.from || line.number <= 1) return false;

  const previous = state.doc.line(line.number - 1);
  if (!standaloneImage(previous.text)) return false;

  dispatch(
    state.update({
      // Include the line break so the content below the preview does not move
      // onto the image's hidden Markdown line before the image is removed.
      changes: { from: previous.from, to: line.from },
      selection: { anchor: previous.from },
      scrollIntoView: true,
      userEvent: "delete.backward",
    }),
  );
  return true;
};

/** Exit one quote level when Enter is pressed on an empty quoted line. */
export const exitEmptyBlockquote: StateCommand = ({ state, dispatch }) => {
  const selection = state.selection.main;
  if (!selection.empty) return false;
  const line = state.doc.lineAt(selection.head);
  if (selection.head !== line.to || !/^\s*(?:>\s*)+$/.test(line.text)) {
    return false;
  }

  const lastMarker = line.text.lastIndexOf(">");
  if (lastMarker < 0) return false;
  dispatch(
    state.update({
      changes: {
        from: line.from + lastMarker,
        to: line.to,
      },
      selection: { anchor: line.from + lastMarker },
      scrollIntoView: true,
      userEvent: "input",
    }),
  );
  return true;
};

/** Continue non-empty Markdown structures and exit empty ones immediately. */
export const continueOrExitMarkdown: StateCommand = (target) =>
  openFencedCodeBlock(target) ||
  exitEmptyBlockquote(target) ||
  continueMarkdownMarkup(target);

const markdownEditingKeymap: readonly KeyBinding[] = [
  { key: "Enter", run: (view) => continueOrExitMarkdown(view) },
  {
    key: "Backspace",
    run: (view) =>
      deleteImageBackward(view) ||
      deleteBeforeEscapedMarkdownSymbolBackward(view) ||
      deleteEscapedMarkdownSymbolBackward(view) ||
      deleteInlineTagMarkerBackward(view) ||
      exitEmptyFencedCodeBlock(view),
  },
  { key: "Delete", run: (view) => deleteEscapedMarkdownSymbolForward(view) },
];

const removeFormerHeadingEscapeResidue = EditorState.transactionFilter.of(
  (transaction) => {
    if (!transaction.docChanged || !transaction.isUserEvent("delete.backward")) {
      return transaction;
    }

    const oldCursor = transaction.startState.selection.main.head;
    const oldLine = transaction.startState.doc.lineAt(oldCursor);
    const oldEscapedHeading = oldLine.text.match(
      /^(\\+)#(?=(?:\*\*[^\r\n]+\*\*|__[^\r\n]+__))/u,
    );
    if (!oldEscapedHeading || oldEscapedHeading[1].length % 2 === 0) {
      return transaction;
    }

    const newCursor = transaction.newSelection.main.head;
    const newLine = transaction.newDoc.lineAt(newCursor);
    const residue = newLine.text.match(
      /^(\\+)(?=(?:\*\*[^\r\n]+\*\*|__[^\r\n]+__))/u,
    );
    if (!residue) return transaction;

    // Only the final slash escaped the deleted `#`; preceding pairs encode
    // real, separately editable backslashes.
    const residueFrom = newLine.from + residue[1].length - 1;
    const residueTo = residueFrom + 1;
    return [
      transaction,
      {
        changes: { from: residueFrom, to: residueTo },
        selection: EditorSelection.cursor(
          Math.max(newLine.from, newCursor - 1),
        ),
        sequential: true,
      },
    ];
  },
);

export const markdownEditingMechanics: Extension = [
  removeFormerHeadingEscapeResidue,
  Prec.highest(keymap.of(markdownEditingKeymap)),
];

function typedCharacterNeedsEscape(
  document: Text,
  position: number,
  character: string,
): boolean {
  if (
    character === "\\" ||
    character === "`" ||
    character === "[" ||
    character === "<"
  ) {
    return true;
  }

  if (character === "*" || character === "_" || character === "~") {
    const line = document.lineAt(position);
    const prefix = document.sliceString(line.from, position);
    const token = prefix.slice(prefix.search(/\S*$/u));
    // Backslashes inside a bare URL change the address. The URL itself remains
    // clickable even though Markdown typing is disabled.
    if (/^https?:\/\/[^\s]*$/iu.test(token)) return false;
    return true;
  }

  if (character === "|") return true;

  if (character === "!") {
    const previous =
      position > 0 ? document.sliceString(position - 1, position) : "";
    return previous === "" || /\s/.test(previous);
  }

  if (character === "-" || character === "=") {
    const line = document.lineAt(position);
    const prefix = document.sliceString(line.from, position + 1);
    const previousLineHasText =
      line.number > 1 && document.line(line.number - 1).text.trim().length > 0;
    if (
      previousLineHasText &&
      (character === "=" ? /^\s*=+$/u : /^\s*-+$/u).test(prefix)
    ) {
      return true;
    }
    if (character === "-" && /^\s*-{3,}$/u.test(prefix)) return true;
  }

  if (character !== "#") return false;

  const line = document.lineAt(position);
  return position === line.from || /\s$/u.test(document.sliceString(line.from, position));
}

function confirmedStructuralMarkerFrom(
  document: Text,
  spacePosition: number,
): number | null {
  const line = document.lineAt(spacePosition);
  const prefix = document.sliceString(line.from, spacePosition);
  const match = prefix.match(/^(\s*)([-+>]|\d+[.)])$/u);
  if (!match) return null;
  return line.from + match[1].length + match[2].length - 1;
}

/**
 * Locates escapes needed to keep newly typed punctuation literal without
 * rewriting ordinary URL, filename, decimal, or prose punctuation.
 */
export function typedMarkdownEscapePositions(
  document: Text,
  insertedFrom: number,
  insertedTo: number,
): number[] {
  const positions: number[] = [];
  for (let position = insertedFrom; position < insertedTo; position += 1) {
    const character = document.sliceString(position, position + 1);
    if (typedCharacterNeedsEscape(document, position, character)) {
      if (
        (character === "-" || character === "=") &&
        positions.some(
          (escapedPosition) =>
            escapedPosition >= document.lineAt(position).from,
        )
      ) {
        continue;
      }
      positions.push(position);
      continue;
    }
    if (character === " ") {
      const markerFrom = confirmedStructuralMarkerFrom(document, position);
      if (markerFrom != null) positions.push(markerFrom);
    }
  }
  return positions;
}

/**
 * Keep manually typed Markdown punctuation literal while allowing toolbar commands,
 * keyboard shortcuts, paste, and programmatic edits to insert real Markdown.
 */
export function literalMarkdownSymbolTyping(
  markdownTypingEnabled: () => boolean,
): Extension {
  return EditorState.transactionFilter.of((transaction) => {
    if (
      markdownTypingEnabled() ||
      !transaction.docChanged ||
      !transaction.isUserEvent("input.type")
    ) {
      return transaction;
    }

    const escapeAt = new Set<number>();
    const removeEscapeAt = new Set<number>();
    transaction.changes.iterChanges(
      (_fromA, _toA, fromB, toB) => {
        const inserted = transaction.newDoc.sliceString(fromB, toB);
        // `#tag` and `[[wikilink]]` are Zerus navigation structures, not
        // Markdown formatting. The first punctuation character is protected
        // until the next keystroke proves the user's intent, then its escape is
        // removed in the same history event.
        if (/^[\p{L}\p{N}]/u.test(inserted) && fromB >= 2) {
          const before = transaction.newDoc.sliceString(fromB - 2, fromB);
          if (before === "\\#") removeEscapeAt.add(fromB - 2);
        }
        if (inserted.startsWith("[") && fromB >= 2) {
          const before = transaction.newDoc.sliceString(fromB - 2, fromB);
          if (before === "\\[") {
            removeEscapeAt.add(fromB - 2);
            escapeAt.delete(fromB);
          }
        }
        for (const position of typedMarkdownEscapePositions(
          transaction.newDoc,
          fromB,
          toB,
        )) {
          escapeAt.add(position);
        }
        if (inserted === "[" && removeEscapeAt.has(fromB - 2)) {
          escapeAt.delete(fromB);
        }
      },
    );
    for (const position of [...escapeAt]) {
      const character = transaction.newDoc.sliceString(position, position + 1);
      if (
        character === "#" &&
        /[\p{L}\p{N}]/u.test(
          transaction.newDoc.sliceString(position + 1, position + 2),
        )
      ) {
        escapeAt.delete(position);
      }
      if (
        character === "[" &&
        ((position > 0 &&
          transaction.newDoc.sliceString(position - 1, position) === "[") ||
          transaction.newDoc.sliceString(position + 1, position + 2) === "[")
      ) {
        escapeAt.delete(position);
      }
    }
    if (escapeAt.size === 0 && removeEscapeAt.size === 0) return transaction;

    return [
      transaction,
      {
        changes: [
          ...[...removeEscapeAt].map((from) => ({ from, to: from + 1 })),
          ...[...escapeAt]
            .filter((from) => !removeEscapeAt.has(from))
            .map((from) => ({ from, insert: "\\" })),
        ].sort((a, b) => a.from - b.from),
        sequential: true,
        userEvent: "input.escapeMarkdown",
      },
    ];
  });
}
