export type HorizontalSwipeDirection = "left" | "right" | null;

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
