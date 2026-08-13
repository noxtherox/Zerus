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

export function linkDisplayName(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./i, "") || url;
  } catch {
    return url;
  }
}
