/** Match a note shortcut immediately before the caret, without matching emails. */
export function matchNoteLinkTrigger(text: string) {
  const match = /(?:^|[\s(])(@([^@[\]\n]{0,100}))$|(?:^|[^[])(\[\[([^[\]\n]{0,100}))$/.exec(text);
  if (!match) return null;
  const replaceableString = match[1] ?? match[3];
  return {
    leadOffset: text.length - replaceableString.length,
    matchingString: match[2] ?? match[4],
    replaceableString,
  };
}
