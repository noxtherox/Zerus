import { describe, expect, it } from "vitest";
import {
  horizontalSwipeDirection,
  noteHeaderCollapseProgress,
  shouldDismissBottomSheet,
} from "./mobile-gestures";

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

describe("noteHeaderCollapseProgress", () => {
  it("tracks the toolbar transition across the opening 72 pixels of note scrolling", () => {
    expect(noteHeaderCollapseProgress(0)).toBe(0);
    expect(noteHeaderCollapseProgress(36)).toBe(0.5);
    expect(noteHeaderCollapseProgress(72)).toBe(1);
  });

  it("clamps overscroll in either direction", () => {
    expect(noteHeaderCollapseProgress(-20)).toBe(0);
    expect(noteHeaderCollapseProgress(240)).toBe(1);
  });

  it("supports a shorter range for compact mobile headers", () => {
    expect(noteHeaderCollapseProgress(28, 56)).toBe(0.5);
    expect(noteHeaderCollapseProgress(56, 56)).toBe(1);
  });
});

describe("shouldDismissBottomSheet", () => {
  it("dismisses for a deliberate downward drag", () => {
    expect(shouldDismissBottomSheet(110, 500, 600)).toBe(true);
  });

  it("dismisses a shorter fast flick", () => {
    expect(shouldDismissBottomSheet(40, 50, 600)).toBe(true);
  });

  it("keeps the sheet open after a short slow drag", () => {
    expect(shouldDismissBottomSheet(40, 500, 600)).toBe(false);
  });
});
