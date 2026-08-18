import { describe, expect, it } from "vitest";
import { mobileNoteSwipeAction } from "./mobile-gestures";

describe("mobileNoteSwipeAction", () => {
  it("opens properties on a right-to-left swipe from a note", () => {
    expect(
      mobileNoteSwipeAction({ x: 320, y: 200 }, { x: 180, y: 205 }, false),
    ).toBe("open-properties");
  });

  it("closes properties before navigating back on a left-to-right swipe", () => {
    expect(
      mobileNoteSwipeAction({ x: 40, y: 200 }, { x: 180, y: 205 }, true),
    ).toBe("close-properties");
  });

  it("navigates back only when properties are already closed", () => {
    expect(
      mobileNoteSwipeAction({ x: 40, y: 200 }, { x: 180, y: 205 }, false),
    ).toBe("back");
  });

  it("ignores short and primarily vertical gestures", () => {
    expect(
      mobileNoteSwipeAction({ x: 100, y: 100 }, { x: 160, y: 105 }, false),
    ).toBeNull();
    expect(
      mobileNoteSwipeAction({ x: 100, y: 100 }, { x: 190, y: 240 }, false),
    ).toBeNull();
  });
});
