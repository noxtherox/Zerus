import {
  getNoteProperties,
  setContentProperty,
  type PropertyValue,
} from "@/lib/frontmatter";
import { normalizeExternalUrl } from "@/lib/external-links";
import type { Note } from "@/lib/note-utils";

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

/** Keep the saved URL directly beneath the editable first-line note title. */
export function withLinkMarkdown(body: string, url: string): string {
  if (body.includes(url)) return body;
  const lines = body.split("\n");
  const titleIndex = lines.findIndex((line) => line.trim().length > 0);
  if (titleIndex < 0) return `${linkMarkdown(url)}\n`;
  const title = lines.slice(0, titleIndex + 1).join("\n");
  const remainder = lines
    .slice(titleIndex + 1)
    .join("\n")
    .replace(/^\n+/, "")
    .replace(/\n+$/, "");
  return `${title}\n\n${linkMarkdown(url)}${remainder ? `\n\n${remainder}` : ""}\n`;
}
