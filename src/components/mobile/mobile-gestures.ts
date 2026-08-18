const MOBILE_SWIPE_DISTANCE = 72;

export type MobileNoteSwipeAction =
  | "open-properties"
  | "close-properties"
  | "back"
  | null;

export function mobileNoteSwipeAction(
  start: { x: number; y: number },
  end: { x: number; y: number },
  propertiesOpen: boolean,
): MobileNoteSwipeAction {
  const deltaX = end.x - start.x;
  const deltaY = end.y - start.y;

  if (
    Math.abs(deltaX) < MOBILE_SWIPE_DISTANCE ||
    Math.abs(deltaX) <= Math.abs(deltaY)
  ) {
    return null;
  }

  if (deltaX < 0) return propertiesOpen ? null : "open-properties";
  return propertiesOpen ? "close-properties" : "back";
}
