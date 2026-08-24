import { syntaxTree } from "@codemirror/language";
import type { EditorState } from "@codemirror/state";

export interface InlineMarkupEdit {
  insert: string;
  selectionFrom: number;
  selectionTo: number;
}

export interface EnclosingInlineMarkup {
  openingFrom: number;
  openingTo: number;
  closingFrom: number;
  closingTo: number;
}

const inlineNodeForMarker: Record<string, string> = {
  "**": "StrongEmphasis",
  "*": "Emphasis",
  _: "Emphasis",
  "~~": "Strikethrough",
  "`": "InlineCode",
};

const markNodeForMarker: Record<string, string> = {
  "**": "EmphasisMark",
  "*": "EmphasisMark",
  _: "EmphasisMark",
  "~~": "StrikethroughMark",
  "`": "CodeMark",
};

/** Finds parsed inline formatting that fully contains the current selection. */
export function enclosingInlineMarkup(
  state: EditorState,
  from: number,
  to: number,
  marker: string,
): EnclosingInlineMarkup | null {
  const inlineNode = inlineNodeForMarker[marker];
  const markNode = markNodeForMarker[marker];
  if (!inlineNode || !markNode) return null;

  let best: EnclosingInlineMarkup | null = null;
  let bestLength = Number.POSITIVE_INFINITY;
  const visited = new Set<string>();

  for (const position of new Set([from, to])) {
    for (const bias of [-1, 1] as const) {
      for (
        let node = syntaxTree(state).resolveInner(position, bias);
        node;
        node = node.parent
      ) {
        if (node.name !== inlineNode || node.from > from || node.to < to) {
          continue;
        }
        const key = `${node.from}:${node.to}`;
        if (visited.has(key)) continue;
        visited.add(key);

        const marks = node.getChildren(markNode);
        const opening = marks[0];
        const closing = marks[marks.length - 1];
        if (
          !opening ||
          !closing ||
          opening === closing ||
          state.sliceDoc(opening.from, opening.to) !== marker ||
          state.sliceDoc(closing.from, closing.to) !== marker
        ) {
          continue;
        }

        const length = node.to - node.from;
        if (length < bestLength) {
          bestLength = length;
          best = {
            openingFrom: opening.from,
            openingTo: opening.to,
            closingFrom: closing.from,
            closingTo: closing.to,
          };
        }
      }
    }
  }

  return best;
}

const leadingWhitespacePattern = /^[\t ]*/;
const trailingWhitespacePattern = /\s*$/;
const blockPrefixPattern =
  /^(?:(?:>[\t ]*)+)?(?:(?:#{1,6}|[-+*]|\d+[.)])[\t ]+(?:\[[ xX]\][\t ]+)?)?/;

/**
 * Builds an inline Markdown edit while leaving line endings, surrounding
 * whitespace, and a leading block marker outside the inline delimiters.
 */
export function inlineMarkupEdit(
  selectedText: string,
  marker: string,
  placeholder: string,
): InlineMarkupEdit {
  if (!selectedText) {
    return {
      insert: `${marker}${placeholder}${marker}`,
      selectionFrom: marker.length,
      selectionTo: marker.length + placeholder.length,
    };
  }

  const leadingWhitespace = selectedText.match(leadingWhitespacePattern)?.[0] ?? "";
  const afterLeadingWhitespace = selectedText.slice(leadingWhitespace.length);
  const trailingWhitespace = afterLeadingWhitespace.match(trailingWhitespacePattern)?.[0] ?? "";
  const withoutWhitespace = afterLeadingWhitespace.slice(
    0,
    afterLeadingWhitespace.length - trailingWhitespace.length,
  );
  const blockPrefix = withoutWhitespace.match(blockPrefixPattern)?.[0] ?? "";
  const content = withoutWhitespace.slice(blockPrefix.length);
  const preservedPrefix = leadingWhitespace + blockPrefix;
  const hasMarkup =
    content.startsWith(marker) &&
    content.endsWith(marker) &&
    content.length >= marker.length * 2;

  if (hasMarkup) {
    const unwrappedContent = content.slice(marker.length, -marker.length);
    return {
      insert: `${preservedPrefix}${unwrappedContent}${trailingWhitespace}`,
      selectionFrom: preservedPrefix.length,
      selectionTo: preservedPrefix.length + unwrappedContent.length,
    };
  }

  return {
    insert: `${preservedPrefix}${marker}${content}${marker}${trailingWhitespace}`,
    selectionFrom: preservedPrefix.length + marker.length,
    selectionTo: preservedPrefix.length + marker.length + content.length,
  };
}
