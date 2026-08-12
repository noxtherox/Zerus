import { describe, expect, it } from "vitest";
import { horizontalSwipeDirection } from "./mobile-gestures";

describe("horizontalSwipeDirection", () => {
  it("recognises swipes in both directions", () => {
    expect(horizontalSwipeDirection({ x: 20, y: 100 }, { x: 100, y: 104 })).toBe("right");
    expect(horizontalSwipeDirection({ x: 180, y: 100 }, { x: 100, y: 96 })).toBe("left");
  });

  it("ignores short movements and vertical scrolling", () => {
    expect(horizontalSwipeDirection({ x: 20, y: 100 }, { x: 70, y: 101 })).toBeNull();
    expect(horizontalSwipeDirection({ x: 20, y: 100 }, { x: 90, y: 180 })).toBeNull();
  });
});
