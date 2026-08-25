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
 * Shield literal less-than signs that MDX mistakes for the start of JSX.
 *
 * Common medical and mathematical Markdown such as `K+ <1` is valid text,
 * but the MDX JSX tokenizer throws before the editor can open the note. A
 * CommonMark backslash escape preserves the visible character and makes the
 * source unambiguous. Code spans and fenced code blocks must remain verbatim.
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

    if (
      !fence &&
      inlineCodeTicks === 0 &&
      character === "<" &&
      !isEscaped(source, index) &&
      !canStartMdxTag(source[index + 1])
    ) {
      result += "\\";
    }

    result += character;
    index += 1;
    lineStart = character === "\n";
  }

  return result;
}
