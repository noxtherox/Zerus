import { getNoteProperties, setContentProperty } from "@/lib/frontmatter";

/** Reserved frontmatter owned by Zerus rather than user property schemas. */
export const ZERUS_METADATA_KEYS = {
  id: "zerus-id",
  pinned: "zerus-pinned",
  archived: "zerus-archived",
} as const;

/**
 * All `zerus-*` keys are reserved so future metadata remains hidden and
 * cannot accidentally become an editable user property.
 */
export function isReservedZerusProperty(key: string): boolean {
  return key.trim().toLowerCase().startsWith("zerus-");
}

/** Removes all app-owned frontmatter while preserving user properties and body. */
export function stripZerusMetadata(content: string): string {
  let next = content;
  for (const key of Object.keys(getNoteProperties(content))) {
    if (isReservedZerusProperty(key)) {
      next = setContentProperty(next, key, null);
    }
  }
  return next;
}

export function readZerusMetadata(content: string) {
  const properties = getNoteProperties(content);
  const id = properties[ZERUS_METADATA_KEYS.id];
  return {
    id: typeof id === "string" && id.length > 0 ? id : null,
    pinned: properties[ZERUS_METADATA_KEYS.pinned] === true,
    archived: properties[ZERUS_METADATA_KEYS.archived] === true,
  };
}

export function setZerusState(
  content: string,
  state: { id?: string; pinned?: boolean; archived?: boolean },
): string {
  let next = content;
  if (state.id !== undefined) {
    next = setContentProperty(next, ZERUS_METADATA_KEYS.id, state.id);
  }
  if (state.archived === true) {
    next = setContentProperty(next, ZERUS_METADATA_KEYS.pinned, null);
  } else if (state.pinned !== undefined) {
    next = setContentProperty(
      next,
      ZERUS_METADATA_KEYS.pinned,
      state.pinned ? true : null,
    );
  }
  if (state.archived !== undefined) {
    next = setContentProperty(
      next,
      ZERUS_METADATA_KEYS.archived,
      state.archived ? true : null,
    );
  }
  return next;
}
