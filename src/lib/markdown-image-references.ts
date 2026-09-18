import { fromMarkdown } from "mdast-util-from-markdown";

export interface MarkdownImageReference {
  path: string;
  start: number;
  end: number;
}

interface PositionedNode {
  type: string;
  url?: string;
  identifier?: string;
  children?: PositionedNode[];
  position?: {
    start: { offset?: number };
    end: { offset?: number };
  };
}

function destinationSpan(
  content: string,
  node: PositionedNode,
): Pick<MarkdownImageReference, "start" | "end"> | null {
  const nodeStart = node.position?.start.offset;
  const nodeEnd = node.position?.end.offset;
  if (nodeStart === undefined || nodeEnd === undefined) return null;
  const source = content.slice(nodeStart, nodeEnd);
  let cursor = 0;

  if (node.type === "image") {
    cursor = source.indexOf("](");
    if (cursor < 0) return null;
    cursor += 2;
  } else if (node.type === "definition") {
    cursor = source.indexOf(":");
    if (cursor < 0) return null;
    cursor += 1;
  } else {
    return null;
  }

  while (/\s/.test(source[cursor] ?? "")) cursor += 1;
  const wrapped = source[cursor] === "<";
  if (wrapped) cursor += 1;
  const start = cursor;
  let depth = 0;
  let escaped = false;
  while (cursor < source.length) {
    const character = source[cursor];
    if (escaped) {
      escaped = false;
      cursor += 1;
      continue;
    }
    if (character === "\\") {
      escaped = true;
      cursor += 1;
      continue;
    }
    if (wrapped) {
      if (character === ">") break;
    } else {
      if (character === "(") depth += 1;
      else if (character === ")") {
        if (depth === 0) break;
        depth -= 1;
      } else if (/\s/.test(character) && depth === 0) {
        break;
      }
    }
    cursor += 1;
  }
  if (cursor === start) return null;
  return { start: nodeStart + start, end: nodeStart + cursor };
}

/** Returns the editable URL spans for inline and reference-style Markdown images. */
export function markdownImageReferences(content: string): MarkdownImageReference[] {
  const root = fromMarkdown(content) as PositionedNode;
  const images: PositionedNode[] = [];
  const definitions: PositionedNode[] = [];
  const referencedDefinitions = new Set<string>();

  const visit = (node: PositionedNode) => {
    if (node.type === "image") images.push(node);
    if (node.type === "imageReference" && node.identifier) {
      referencedDefinitions.add(node.identifier.toLowerCase());
    }
    if (node.type === "definition") definitions.push(node);
    node.children?.forEach(visit);
  };
  visit(root);

  return [...images, ...definitions.filter((node) =>
    node.identifier && referencedDefinitions.has(node.identifier.toLowerCase()),
  )]
    .flatMap((node) => {
      if (!node.url) return [];
      const span = destinationSpan(content, node);
      return span ? [{ path: node.url, ...span }] : [];
    })
    .sort((left, right) => left.start - right.start);
}

export function replaceMarkdownImageReferences(
  content: string,
  replacements: ReadonlyMap<number, string>,
  references = markdownImageReferences(content),
): string {
  let next = content;
  for (const reference of [...references].sort((left, right) => right.start - left.start)) {
    const replacement = replacements.get(reference.start);
    if (replacement !== undefined) {
      next = `${next.slice(0, reference.start)}${replacement}${next.slice(reference.end)}`;
    }
  }
  return next;
}
