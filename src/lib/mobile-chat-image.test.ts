import { describe, expect, it } from "vitest";
import { constrainedImageSize, questionReferencesImage } from "./mobile-chat-image";

describe("mobile chat image preparation", () => {
  it("bounds the longest edge without enlarging small images", () => {
    expect(constrainedImageSize(4_032, 3_024)).toEqual({ width: 1_024, height: 768 });
    expect(constrainedImageSize(320, 480)).toEqual({ width: 320, height: 480 });
  });

  it("detects explicit image follow-up questions", () => {
    expect(questionReferencesImage("Can you read the screenshot again?")).toBe(true);
    expect(questionReferencesImage("O que diz esta imagem?")).toBe(true);
    expect(questionReferencesImage("Can you explain that again?")).toBe(false);
  });

  it("rejects invalid source dimensions", () => {
    expect(() => constrainedImageSize(0, 120)).toThrow("invalid dimensions");
  });
});
