/** Bounded line diff; long replacements keep distinct removed/added blocks. */
export function noteUnifiedDiff(
  before: string,
  after: string,
  path: string,
): string {
  const a = before.split("\n"),
    b = after.split("\n");
  let prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] === b[prefix])
    prefix++;
  let suffix = 0;
  while (
    suffix < a.length - prefix &&
    suffix < b.length - prefix &&
    a[a.length - 1 - suffix] === b[b.length - 1 - suffix]
  )
    suffix++;
  if (prefix === a.length && prefix === b.length) return "No text changes.";
  const start = Math.max(0, prefix - 3);
  const endA = Math.min(a.length, a.length - suffix + 3);
  const endB = Math.min(b.length, b.length - suffix + 3);
  return [
    `--- ${path}`,
    `+++ ${path}`,
    `@@ -${start + 1},${endA - start} +${start + 1},${endB - start} @@`,
    ...a.slice(start, prefix).map((line) => ` ${line}`),
    ...a.slice(prefix, a.length - suffix).map((line) => `-${line}`),
    ...b.slice(prefix, b.length - suffix).map((line) => `+${line}`),
    ...b.slice(b.length - suffix, endB).map((line) => ` ${line}`),
  ].join("\n");
}
