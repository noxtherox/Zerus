import {
  getNoteProperties,
  setContentProperty,
  type PropertyValue,
} from "@/lib/frontmatter";
import { normalizeExternalUrl } from "@/lib/external-links";
import type { Note } from "@/lib/note-utils";
import type { Link, Paragraph, Root } from "mdast";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import { unified } from "unified";

export const LINK_HUB_KEYS = {
  id: "zerus-link-id",
  url: "zerus-link-url",
} as const;

export interface LinkHubReference {
  id: string;
  url: string;
}

function scalarString(value: PropertyValue | undefined): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed || undefined;
}

export function getLinkHubReference(
  noteOrContent: Note | string,
): LinkHubReference | null {
  const content =
    typeof noteOrContent === "string" ? noteOrContent : noteOrContent.content;
  const properties = getNoteProperties(content);
  const id = scalarString(properties[LINK_HUB_KEYS.id]);
  const rawUrl = scalarString(properties[LINK_HUB_KEYS.url]);
  const url = rawUrl ? normalizeExternalUrl(rawUrl) : null;
  return id && url ? { id, url } : null;
}

export function setLinkHubReference(
  content: string,
  reference: LinkHubReference,
): string {
  let next = setContentProperty(content, LINK_HUB_KEYS.id, reference.id);
  next = setContentProperty(next, LINK_HUB_KEYS.url, reference.url);
  return next;
}

export function removeLinkHubReference(content: string): string {
  let next = setContentProperty(content, LINK_HUB_KEYS.id, null);
  next = setContentProperty(next, LINK_HUB_KEYS.url, null);
  return next;
}

export function linkDisplayName(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./i, "") || url;
  } catch {
    return url;
  }
}

/** Markdown body shown beneath a saved link's editable note title. */
export function linkMarkdown(url: string): string {
  return `<${url}>`;
}

const linkBodyParser = unified().use(remarkParse).use(remarkGfm);

function standaloneLinkRanges(body: string, url: string): { start: number; end: number }[] {
  const root = linkBodyParser.parse(body) as Root;
  return root.children.flatMap((node) => {
    if (node.type !== "paragraph") return [];
    const paragraph = node as Paragraph;
    if (paragraph.children.length !== 1 || paragraph.children[0].type !== "link") return [];
    const link = paragraph.children[0] as Link;
    const start = paragraph.position?.start.offset;
    const end = paragraph.position?.end.offset;
    return normalizeExternalUrl(link.url) === url && start !== undefined && end !== undefined
      ? [{ start, end }]
      : [];
  });
}

function removeLinkRanges(
  body: string,
  ranges: { start: number; end: number }[],
): string {
  let result = body;
  for (const range of ranges.reverse()) {
    let start = range.start;
    let end = range.end;
    let followingNewlines = 0;
    while (followingNewlines < 2 && result[end] === "\n") {
      end += 1;
      followingNewlines += 1;
    }
    if (followingNewlines === 0) {
      let precedingNewlines = 0;
      while (precedingNewlines < 2 && start > 0 && result[start - 1] === "\n") {
        start -= 1;
        precedingNewlines += 1;
      }
    }
    result = result.slice(0, start) + result.slice(end);
  }
  return result;
}

/** Hide the managed URL from the editable title and notes surface. */
export function withoutLinkMarkdown(body: string, url: string): string {
  const normalizedUrl = normalizeExternalUrl(url) ?? url;
  return removeLinkRanges(body, standaloneLinkRanges(body, normalizedUrl));
}

/** Keep the saved URL directly beneath the editable first-line note title. */
export function withLinkMarkdown(body: string, url: string): string {
  const normalizedUrl = normalizeExternalUrl(url) ?? url;
  const matches = standaloneLinkRanges(body, normalizedUrl);
  // Preserve a single link byte-for-byte. MDXEditor serializes CommonMark
  // autolinks as ordinary Markdown links, and rewriting that valid result while
  // the user types makes React reload the editor and destroys its selection.
  if (matches.length === 1) return body;
  if (matches.length > 1) {
    return removeLinkRanges(body, matches.slice(1));
  }

  const lines = body.split("\n");
  const titleIndex = lines.findIndex((line) => line.trim().length > 0);
  if (titleIndex < 0) return `${linkMarkdown(normalizedUrl)}\n`;
  const title = lines.slice(0, titleIndex + 1).join("\n");
  const remainder = lines
    .slice(titleIndex + 1)
    .join("\n")
    .replace(/^\n+/, "")
    .replace(/\n+$/, "");
  return `${title}\n\n${linkMarkdown(normalizedUrl)}${remainder ? `\n\n${remainder}` : ""}\n`;
}
