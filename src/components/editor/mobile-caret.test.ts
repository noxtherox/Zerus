import { describe, expect, it } from "vitest";
import { mobileCaretLayout } from "./mobile-caret";

describe("mobile cursor visibility", () => {
  const scroller = { top: 240, bottom: 850 };
  it("adds enough scroll space and reveals a cursor covered by the keyboard", () => {
    expect(mobileCaretLayout(scroller, { offsetTop: 0, height: 500 }, { top: 700, bottom: 724 }))
      .toEqual({ padding: 350, scroll: 248 });
  });
  it("accounts for iOS viewport panning without counting it twice", () => {
    expect(mobileCaretLayout(scroller, { offsetTop: 100, height: 500 }, { top: 590, bottom: 614 }))
      .toEqual({ padding: 250, scroll: 38 });
  });
  it("does not move an already visible cursor", () => {
    expect(mobileCaretLayout(scroller, { offsetTop: 0, height: 500 }, { top: 300, bottom: 324 }).scroll).toBe(0);
  });
  it("reveals the cursor when moving back above the editor", () => {
    expect(mobileCaretLayout(scroller, { offsetTop: 0, height: 500 }, { top: 210, bottom: 234 }).scroll).toBe(-46);
  });
  it("removes extra space when the keyboard closes or the webview already resized", () => {
    expect(mobileCaretLayout(scroller, { offsetTop: 0, height: 900 }).padding).toBe(0);
    expect(mobileCaretLayout({ top: 240, bottom: 500 }, { offsetTop: 0, height: 500 }).padding).toBe(0);
  });
});
