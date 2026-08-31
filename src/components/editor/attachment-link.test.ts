import { describe, expect, it } from "vitest";
import {
  ATTACHMENT_MENU_ACTION_WIDTH,
  attachmentClickAction,
  attachmentIdFromHref,
} from "./attachment-link";

describe("attachment links", () => {
  it("recognizes only Zerus attachment references", () => {
    expect(attachmentIdFromHref("zerus-attachment:attachment-1")).toBe(
      "attachment-1",
    );
    expect(attachmentIdFromHref("https://example.com")).toBeNull();
    expect(attachmentIdFromHref("zerus-attachment:")).toBeNull();
  });

  it("uses the trailing card action to open the attachment menu", () => {
    const right = 400;
    expect(
      attachmentClickAction(right, right - ATTACHMENT_MENU_ACTION_WIDTH - 1),
    ).toBe("open");
    expect(
      attachmentClickAction(right, right - ATTACHMENT_MENU_ACTION_WIDTH),
    ).toBe("menu");
  });
});
