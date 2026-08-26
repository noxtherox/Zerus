const MDX_NAME_START = /[\p{ID_Start}$_]/u;

function backtickRunLength(source: string, from: number): number {
  let to = from;
  while (source[to] === "`") to += 1;
  return to - from;
}

function isEscaped(source: string, at: number): boolean {
  let slashes = 0;
  for (let index = at - 1; index >= 0 && source[index] === "\\"; index -= 1) {
    slashes += 1;
  }
  return slashes % 2 === 1;
}

function canStartMdxTag(character: string | undefined): boolean {
  if (!character || /\s/u.test(character)) return true;
  return MDX_NAME_START.test(character) || "/!?>".includes(character);
}

/**
 * Normalize Markdown constructs that MDX otherwise mistakes for invalid JSX.
 *
 * Common medical and mathematical Markdown such as `K+ <1`, as well as prose
 * containing literal braces, is valid text, but MDX tokenizers can mistake it
 * for JSX or a JavaScript expression and throw before the editor can open the
 * note. CommonMark backslash escapes preserve the visible characters, while
 * HTML break tags are made self-closing. Code spans and fenced code blocks
 * must remain verbatim.
 */
export function prepareMarkdownForMdxEditor(source: string): string {
  let result = "";
  let index = 0;
  let inlineCodeTicks = 0;
  let fence: { marker: "`" | "~"; length: number } | null = null;
  let lineStart = true;

  while (index < source.length) {
    if (lineStart && inlineCodeTicks === 0) {
      const fenceMatch = source.slice(index).match(/^( {0,3})(`{3,}|~{3,})/u);
      if (fenceMatch) {
        const marker = fenceMatch[2][0] as "`" | "~";
        const length = fenceMatch[2].length;
        if (!fence) fence = { marker, length };
        else if (fence.marker === marker && length >= fence.length) fence = null;
        const delimiterLength = fenceMatch[1].length + fenceMatch[2].length;
        result += source.slice(index, index + delimiterLength);
        index += delimiterLength;
        lineStart = false;
        continue;
      }
    }

    const character = source[index];
    if (!fence && character === "`") {
      const ticks = backtickRunLength(source, index);
      if (inlineCodeTicks === 0) inlineCodeTicks = ticks;
      else if (inlineCodeTicks === ticks) inlineCodeTicks = 0;
      result += source.slice(index, index + ticks);
      index += ticks;
      lineStart = false;
      continue;
    }

    if (!fence && inlineCodeTicks === 0 && character === "<") {
      const breakTag = source.slice(index).match(/^<br\s*>/iu);
      if (breakTag) {
        result += "<br />";
        index += breakTag[0].length;
        lineStart = false;
        continue;
      }
    }

    if (
      !fence &&
      inlineCodeTicks === 0 &&
      character === "<" &&
      !isEscaped(source, index) &&
      !canStartMdxTag(source[index + 1])
    ) {
      result += "\\";
    }

    if (
      !fence &&
      inlineCodeTicks === 0 &&
      (character === "{" || character === "}") &&
      !isEscaped(source, index)
    ) {
      result += "\\";
    }

    result += character;
    index += 1;
    lineStart = character === "\n";
  }

  return result;
}
