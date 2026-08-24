export interface EditorPopoverPosition {
  left: number;
  top: number;
  width: number;
}

interface RectLike {
  left: number;
  top: number;
  width: number;
  height?: number;
  bottom?: number;
}

const POPOVER_HEIGHT = 48;
const POPOVER_GAP = 8;
const HORIZONTAL_PADDING = 12;

/** Positions an editor popover near its target while keeping it in the editor. */
export function editorPopoverPosition(
  wrapper: RectLike,
  target: RectLike,
  minimumWidth: number,
  align: "start" | "center" = "start",
): EditorPopoverPosition {
  const availableWidth = Math.max(0, wrapper.width - HORIZONTAL_PADDING * 2);
  const width =
    availableWidth >= minimumWidth
      ? Math.min(430, availableWidth)
      : availableWidth;
  const targetLeft = target.left - wrapper.left;
  const alignedLeft =
    align === "center"
      ? targetLeft + target.width / 2 - width / 2
      : targetLeft;

  const above = target.top - wrapper.top - POPOVER_HEIGHT - POPOVER_GAP;
  const targetBottom =
    target.bottom ?? target.top + (target.height ?? 0);
  const below = targetBottom - wrapper.top + POPOVER_GAP;
  const preferredTop = above >= POPOVER_GAP ? above : below;
  const top =
    wrapper.height == null
      ? Math.max(POPOVER_GAP, preferredTop)
      : Math.min(
          Math.max(POPOVER_GAP, preferredTop),
          Math.max(POPOVER_GAP, wrapper.height - POPOVER_HEIGHT - POPOVER_GAP),
        );

  return {
    left: Math.min(
      Math.max(HORIZONTAL_PADDING, alignedLeft),
      Math.max(HORIZONTAL_PADDING, wrapper.width - width - HORIZONTAL_PADDING),
    ),
    top,
    width,
  };
}
