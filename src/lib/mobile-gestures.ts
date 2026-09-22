export type HorizontalSwipeDirection = "left" | "right" | null;

const NOTE_HEADER_COLLAPSE_DISTANCE = 72;
const EDGE_SWIPE_WIDTH = 28;

interface SwipePoint {
  x: number;
  y: number;
}

const MOBILE_NOTE_SWIPE_BLOCKED_SELECTOR =
  "input, textarea, select, button, [data-mobile-swipe-ignore]";

/**
 * Keeps note-level navigation gestures away from controls without excluding the
 * contenteditable editor itself. Horizontal swipes in the note body should be
 * available for navigation while vertical movement remains native scrolling.
 */
export function blocksMobileNoteSwipe(target: Element): boolean {
  return Boolean(target.closest(MOBILE_NOTE_SWIPE_BLOCKED_SELECTOR));
}

export function startsAtSwipeEdge(x: number, viewportWidth: number, direction: "left" | "right" = "right"): boolean {
  return direction === "right"
    ? x <= EDGE_SWIPE_WIDTH
    : x >= viewportWidth - EDGE_SWIPE_WIDTH;
}

/**
 * Recognises an intentional horizontal swipe while rejecting ordinary vertical
 * scrolling and small taps. Kept separate from React so the gesture thresholds
 * can be tested without a browser.
 */
export function horizontalSwipeDirection(
  start: SwipePoint,
  end: SwipePoint,
): HorizontalSwipeDirection {
  const deltaX = end.x - start.x;
  const deltaY = end.y - start.y;

  if (Math.abs(deltaX) < 64) return null;
  if (Math.abs(deltaX) < Math.abs(deltaY) * 1.25) return null;

  return deltaX < 0 ? "left" : "right";
}

export function noteHeaderCollapseProgress(
  scrollTop: number,
  collapseDistance = NOTE_HEADER_COLLAPSE_DISTANCE,
): number {
  return Math.min(1, Math.max(0, scrollTop / Math.max(1, collapseDistance)));
}

export function shouldDismissBottomSheet(
  distance: number,
  durationMs: number,
  sheetHeight: number,
): boolean {
  const dismissDistance = Math.min(120, Math.max(72, sheetHeight * 0.18));
  const velocity = distance / Math.max(durationMs, 1);
  return distance >= dismissDistance || (distance >= 32 && velocity >= 0.65);
}
