export const ATTACHMENT_MENU_ACTION_WIDTH = 48;

export function attachmentIdFromHref(href: string): string | null {
  return href.match(/^zerus-attachment:([a-zA-Z0-9-]+)$/)?.[1] ?? null;
}

export function attachmentClickAction(
  anchorRight: number,
  clientX: number,
): "open" | "menu" {
  return clientX >= anchorRight - ATTACHMENT_MENU_ACTION_WIDTH
    ? "menu"
    : "open";
}
