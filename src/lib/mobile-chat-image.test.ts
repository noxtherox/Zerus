import { describe, expect, it } from "vitest";
import {
  constrainedImageSize,
  imageFilesFromClipboard,
  questionReferencesImage,
} from "./mobile-chat-image";

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

  it("extracts only image files from clipboard items", () => {
    const image = { name: "pasted-image.png", type: "image/png" } as File;
    const text = { name: "notes.txt", type: "text/plain" } as File;

    expect(imageFilesFromClipboard([
      { kind: "string", type: "text/plain", getAsFile: () => null },
      { kind: "file", type: "text/plain", getAsFile: () => text },
      { kind: "file", type: "image/png", getAsFile: () => image },
      { kind: "file", type: "image/jpeg", getAsFile: () => null },
    ])).toEqual([image]);
  });
});
