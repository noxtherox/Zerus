export interface InlineMarkupEdit {
  insert: string;
  selectionFrom: number;
  selectionTo: number;
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
