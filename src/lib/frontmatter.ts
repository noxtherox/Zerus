/**
 * Minimal YAML frontmatter support for note properties. Handles the flat
 * subset Obsidian uses for properties — scalar strings, numbers, booleans,
 * and string lists (dash or inline). Lines it doesn't understand (nested
 * mappings, comments) are preserved verbatim so foreign frontmatter survives
 * round-trips.
 */

export type PropertyValue = string | number | boolean | string[];

type FmNode =
  | { kind: "prop"; key: string; value: PropertyValue }
  | { kind: "raw"; text: string };

const KEY_LINE = /^([A-Za-z0-9_][A-Za-z0-9_ .-]*?)\s*:\s?(.*)$/;
const DASH_ITEM = /^\s+-\s+(.*)$/;

/** Splits content into the frontmatter block (inner text) and the body. */
export function splitFrontmatter(content: string): {
  raw: string | null;
  body: string;
} {
  const prefix = /^\uFEFF*/.exec(content)![0];
  const opening = /^\uFEFF*---\r?\n/.exec(content);
  if (!opening) return { raw: null, body: content.slice(prefix.length) };
  // Only scan the header; property reads must not split/copy the entire body.
  const closing = /\n(?:---|\.\.\.)[^\S\n]*(?:\n|$)/g;
  closing.lastIndex = opening[0].length - 1;
  const match = closing.exec(content);
  if (match) {
    return {
      raw: content.slice(opening[0].length, Math.max(opening[0].length, match.index)),
      body: content.slice(match.index + match[0].length),
    };
  }
  // unterminated --- fence: treat everything as body
  return { raw: null, body: content.slice(prefix.length) };
}

/** Note content without its frontmatter block. */
export function noteBody(content: string): string {
  return splitFrontmatter(content).body;
}

function stripQuotes(value: string): string {
  if (
    value.length >= 2 &&
    ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'")))
  ) {
    const inner = value.slice(1, -1);
    if (value.startsWith('"')) {
      try {
        return JSON.parse(value) as string;
      } catch {
        return inner;
      }
    }
    return inner.replace(/''/g, "'");
  }
  return value;
}

function parseScalar(value: string): PropertyValue {
  const trimmed = value.trim();
  if (
    trimmed.startsWith('"') ||
    trimmed.startsWith("'")
  ) {
    return stripQuotes(trimmed);
  }
  if (/^(true|false)$/i.test(trimmed)) return trimmed.toLowerCase() === "true";
  if (/^-?\d+(\.\d+)?$/.test(trimmed)) return Number(trimmed);
  return trimmed;
}

/** Flat YAML string lists, including JSON strings emitted by the Apple clients. */
function parseInlineList(value: string): string[] | null {
  const tokens: string[] = [];
  let token = "";
  let quote: string | null = null;
  let escaped = false;
  for (let index = 1; index < value.length - 1; index++) {
    const char = value[index];
    if (quote) {
      token += char;
      if (quote === '"' && escaped) { escaped = false; continue; }
      if (quote === '"' && char === "\\") { escaped = true; continue; }
      if (char === quote) {
        if (quote === "'" && value[index + 1] === "'") { token += "'"; index++; }
        else quote = null;
      }
    } else if ((char === '"' || char === "'") && token.trim() === "") {
      quote = char; token += char;
    } else if (char === ",") {
      tokens.push(token); token = "";
    } else if ("[]{}".includes(char)) {
      // Preserve nested structures as opaque YAML rather than flattening their contents.
      return null;
    } else token += char;
  }
  if (quote !== null) return null;
  tokens.push(token);
  if (tokens.length === 1 && token.trim() === "") return [];
  const items: string[] = [];
  for (let index = 0; index < tokens.length; index++) {
    const raw = tokens[index].trim();
    if (!raw) {
      if (index === tokens.length - 1) continue; // YAML permits a trailing comma.
      return null;
    }
    if (raw.startsWith('"')) {
      try {
        const decoded: unknown = JSON.parse(raw);
        if (typeof decoded !== "string") return null;
        items.push(decoded);
      } catch { return null; }
    } else if (raw.startsWith("'")) {
      if (!/^'(?:[^']|'')*'$/.test(raw)) return null;
      items.push(stripQuotes(raw));
    } else items.push(raw);
  }
  return items;
}

function parseNodes(raw: string | null): FmNode[] {
  if (raw === null) return [];
  const lines = raw.split("\n").map((line) => line.replace(/\r$/, ""));
  const nodes: FmNode[] = [];
  for (let i = 0; i < lines.length; i++) {
    const match = lines[i].match(KEY_LINE);
    if (!match) {
      nodes.push({ kind: "raw", text: lines[i] });
      continue;
    }
    const [, key, rest] = match;
    if (rest.trim() === "") {
      // possibly a dash list on the following lines
      const items: string[] = [];
      let j = i + 1;
      while (j < lines.length) {
        const item = lines[j].match(DASH_ITEM);
        if (!item) break;
        items.push(stripQuotes(item[1].trim()));
        j++;
      }
      if (items.length > 0) {
        nodes.push({ kind: "prop", key, value: items });
        i = j - 1;
      } else {
        nodes.push({ kind: "prop", key, value: "" });
      }
      continue;
    }
    const trimmed = rest.trim();
    if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
      const items = parseInlineList(trimmed);
      nodes.push(items === null ? { kind: "raw", text: lines[i] } : { kind: "prop", key, value: items });
      continue;
    }
    nodes.push({ kind: "prop", key, value: parseScalar(trimmed) });
  }
  return nodes;
}

function quoteIfNeeded(value: string): string {
  const needsQuote =
    value !== value.trim() ||
    /^(true|false|null|~)$/i.test(value) ||
    /^-?\d+(\.\d+)?$/.test(value) ||
    /[:#'"[\]{}|>&*!%@`,]/.test(value) ||
    value.startsWith("- ");
  return needsQuote ? JSON.stringify(value) : value;
}

function serializeNode(node: FmNode): string {
  if (node.kind === "raw") return node.text;
  const { key, value } = node;
  if (Array.isArray(value)) {
    if (value.length === 0) return `${key}: []`;
    return `${key}:\n${value.map((item) => `  - ${quoteIfNeeded(item)}`).join("\n")}`;
  }
  if (typeof value === "boolean" || typeof value === "number") {
    return `${key}: ${value}`;
  }
  if (value === "") return `${key}:`;
  return `${key}: ${quoteIfNeeded(value)}`;
}

function compose(nodes: FmNode[], body: string): string {
  if (nodes.length === 0) return body;
  return `---\n${nodes.map(serializeNode).join("\n")}\n---\n${body}`;
}

/** All parseable frontmatter properties of a note. */
export function getNoteProperties(
  content: string,
): Record<string, PropertyValue> {
  const { raw } = splitFrontmatter(content);
  const props: Record<string, PropertyValue> = {};
  for (const node of parseNodes(raw)) {
    if (node.kind === "prop") props[node.key] = node.value;
  }
  return props;
}

function sameKey(a: string, b: string): boolean {
  return a.toLowerCase() === b.toLowerCase();
}

/** Sets (or with `null`, removes) a frontmatter property, returning new content. */
export function setContentProperty(
  content: string,
  key: string,
  value: PropertyValue | null,
): string {
  const { raw, body } = splitFrontmatter(content);
  let nodes = parseNodes(raw);
  const idx = nodes.findIndex(
    (node) => node.kind === "prop" && sameKey(node.key, key),
  );
  if (value === null) {
    if (idx < 0) return content;
    nodes = nodes.filter((_, i) => i !== idx);
  } else if (idx >= 0) {
    const existing = nodes[idx] as Extract<FmNode, { kind: "prop" }>;
    nodes[idx] = { kind: "prop", key: existing.key, value };
  } else {
    nodes.push({ kind: "prop", key, value });
  }
  return /^\uFEFF*/.exec(content)![0] + compose(nodes, body);
}

/** Renames a frontmatter key, keeping its value. No-op if the key is absent. */
export function renameContentProperty(
  content: string,
  from: string,
  to: string,
): string {
  const { raw, body } = splitFrontmatter(content);
  const nodes = parseNodes(raw);
  const idx = nodes.findIndex(
    (node) => node.kind === "prop" && sameKey(node.key, from),
  );
  if (idx < 0) return content;
  const existing = nodes[idx] as Extract<FmNode, { kind: "prop" }>;
  nodes[idx] = { kind: "prop", key: to, value: existing.value };
  return /^\uFEFF*/.exec(content)![0] + compose(nodes, body);
}

/** Replaces the body while preserving the existing frontmatter block. */
export function withBody(content: string, body: string): string {
  const { raw, body: previous } = splitFrontmatter(content);
  if (body === previous) return content;
  if (raw === null) return /^\uFEFF*/.exec(content)![0] + body;
  const header = content.slice(0, content.length - previous.length);
  const newline = /^\uFEFF*---\r\n/.test(content) ? "\r\n" : "\n";
  return header + (header.endsWith("\n") ? "" : newline) + body;
}
