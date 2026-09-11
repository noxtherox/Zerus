export type HorizontalSwipeDirection = "left" | "right" | null;

const NOTE_HEADER_COLLAPSE_DISTANCE = 72;

interface SwipePoint {
  x: number;
  y: number;
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
