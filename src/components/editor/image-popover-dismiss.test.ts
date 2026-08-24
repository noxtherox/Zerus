import { describe, expect, it } from "vitest";
import { shouldDismissImagePopover } from "./image-popover-dismiss";

describe("image popover outside-pointer dismissal", () => {
  it("keeps the popover open for interactions inside the toolbar", () => {
    const popover = new EventTarget();
    const toolbarButton = new EventTarget();

    expect(
      shouldDismissImagePopover([toolbarButton, popover], popover, null),
    ).toBe(false);
  });

  it("keeps the popover open for interactions inside the selected image", () => {
    const selectedImage = new EventTarget();
    const imageElement = new EventTarget();

    expect(
      shouldDismissImagePopover(
        [imageElement, selectedImage],
        null,
        selectedImage,
      ),
    ).toBe(false);
  });

  it("dismisses the popover everywhere else", () => {
    const popover = new EventTarget();
    const selectedImage = new EventTarget();
    const outsideTarget = new EventTarget();

    expect(
      shouldDismissImagePopover(
        [outsideTarget],
        popover,
        selectedImage,
      ),
    ).toBe(true);
  });
});
