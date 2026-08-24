import { describe, expect, it } from "vitest";
import { editorPopoverPosition } from "./popover-position";

const rect = (left: number, top: number, width: number) => ({
  left,
  top,
  width,
});

describe("editor popover positioning", () => {
  const wrapper = rect(100, 40, 800);

  it("places the popover directly above its target", () => {
    expect(editorPopoverPosition(wrapper, rect(132, 400, 500), 300).top).toBe(
      304,
    );
  });

  it("moves with its target instead of staying fixed in the viewport", () => {
    expect(editorPopoverPosition(wrapper, rect(132, 250, 500), 300).top).toBe(
      154,
    );
  });

  it("can center the popover above its target", () => {
    expect(
      editorPopoverPosition(wrapper, rect(200, 400, 500), 300, "center"),
    ).toMatchObject({ left: 135, top: 304, width: 430 });
  });

  it("keeps a centered popover inside the editor", () => {
    expect(
      editorPopoverPosition(wrapper, rect(100, 400, 100), 300, "center").left,
    ).toBe(12);
    expect(
      editorPopoverPosition(wrapper, rect(850, 400, 100), 300, "center").left,
    ).toBe(358);
  });

  it("supports the narrower minimum width used by link popovers", () => {
    expect(editorPopoverPosition(rect(0, 0, 300), rect(20, 100, 40), 280)).toEqual({
      left: 12,
      top: 44,
      width: 276,
    });
  });

  it("opens below targets near the top edge", () => {
    expect(
      editorPopoverPosition(
        { left: 0, top: 100, width: 500, height: 600 },
        { left: 20, top: 104, width: 80, height: 24, bottom: 128 },
        300,
      ).top,
    ).toBe(36);
  });

  it("never grows wider than a narrow editor", () => {
    expect(
      editorPopoverPosition(rect(0, 0, 180), rect(20, 100, 40), 300),
    ).toMatchObject({ left: 12, width: 156 });
  });
});
