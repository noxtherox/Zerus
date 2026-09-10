import { expect, it } from "vitest";
import { nativeFileDropPoint } from "./native-file-drop";

it("keeps Retina Mac drops at their logical chat position", () => {
  expect(nativeFileDropPoint({ x: 1100, y: 600 }, 2, "MacIntel")).toEqual({ x: 1100, y: 600 });
});

it("converts physical Windows coordinates on scaled displays", () => {
  expect(nativeFileDropPoint({ x: 2200, y: 1200 }, 2, "Win32")).toEqual({ x: 1100, y: 600 });
  expect(nativeFileDropPoint({ x: 1100, y: 600 }, 1, "Win32")).toEqual({ x: 1100, y: 600 });
});
