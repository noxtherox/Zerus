/** ASCII punctuation that CommonMark permits after a backslash escape. */
export const MARKDOWN_ESCAPABLE_PUNCTUATION = new Set(
  `!"#$%&'()*+,-./:;<=>?@[\\]^_\`{|}~`,
);

export interface MarkdownEscapeUnit {
  /** The source backslash hidden in Clean mode. */
  escapeFrom: number;
  /** The source character that remains visible. */
  visibleFrom: number;
  /** End of the two-character source unit. */
  to: number;
}

/** Resolve CommonMark escape runs without losing deliberately typed slashes. */
export function markdownEscapeUnits(
  source: string,
  offset = 0,
): MarkdownEscapeUnit[] {
  const units: MarkdownEscapeUnit[] = [];
  for (let index = 0; index < source.length; ) {
    if (source[index] !== "\\") {
      index += 1;
      continue;
    }

    const runFrom = index;
    while (index < source.length && source[index] === "\\") index += 1;
    const runLength = index - runFrom;

    for (let pair = 0; pair + 1 < runLength; pair += 2) {
      const escapeFrom = offset + runFrom + pair;
      units.push({
        escapeFrom,
        visibleFrom: escapeFrom + 1,
        to: escapeFrom + 2,
      });
    }

    if (
      runLength % 2 === 1 &&
      index < source.length &&
      MARKDOWN_ESCAPABLE_PUNCTUATION.has(source[index])
    ) {
      const escapeFrom = offset + index - 1;
      units.push({
        escapeFrom,
        visibleFrom: offset + index,
        to: offset + index + 1,
      });
    }
  }
  return units;
}

/** Return the complete escaped source unit containing a source boundary. */
export function markdownEscapeUnitAt(
  source: string,
  position: number,
): MarkdownEscapeUnit | null {
  return (
    markdownEscapeUnits(source).find(
      (unit) => position >= unit.escapeFrom && position < unit.to,
    ) ?? null
  );
}

/** Decode only Markdown backslash escapes; formatting delimiters stay intact. */
export function decodeMarkdownEscapes(source: string): string {
  const hidden = new Set(
    markdownEscapeUnits(source).map((unit) => unit.escapeFrom),
  );
  let decoded = "";
  for (let index = 0; index < source.length; index += 1) {
    if (!hidden.has(index)) decoded += source[index];
  }
  return decoded;
}

/** Remove protective escapes from a deliberately interpreted source range. */
export function interpretMarkdownSource(source: string): string {
  return decodeMarkdownEscapes(source);
}

/**
 * Temporarily shields escaped visible characters from a Markdown text
 * transform, then restores exactly what Clean mode displays.
 */
export function transformPreservingMarkdownEscapes(
  source: string,
  transform: (protectedSource: string) => string,
): string {
  const units = markdownEscapeUnits(source);
  if (units.length === 0) return transform(source);
  let tokenPrefix = "\uE000zerus-escape-";
  while (source.includes(tokenPrefix)) tokenPrefix += "-";
  const replacements = units.map((unit, index) => ({
    ...unit,
    token: `${tokenPrefix}${index}\uE001`,
    visible: source.slice(unit.visibleFrom, unit.to),
  }));
  let protectedSource = source;
  for (const replacement of [...replacements].reverse()) {
    protectedSource =
      protectedSource.slice(0, replacement.escapeFrom) +
      replacement.token +
      protectedSource.slice(replacement.to);
  }
  let result = transform(protectedSource);
  for (const replacement of replacements) {
    result = result.split(replacement.token).join(replacement.visible);
  }
  return result;
}
