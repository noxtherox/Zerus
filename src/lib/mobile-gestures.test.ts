import { describe, expect, it } from "vitest";
import {
  horizontalSwipeDirection,
  noteHeaderCollapseProgress,
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
  it("tracks the opening 88 pixels of note scrolling", () => {
    expect(noteHeaderCollapseProgress(0)).toBe(0);
    expect(noteHeaderCollapseProgress(44)).toBe(0.5);
    expect(noteHeaderCollapseProgress(88)).toBe(1);
  });

  it("clamps overscroll in either direction", () => {
    expect(noteHeaderCollapseProgress(-20)).toBe(0);
    expect(noteHeaderCollapseProgress(240)).toBe(1);
  });
});
