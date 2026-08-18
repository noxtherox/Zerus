import { describe, expect, it } from "vitest";
import {
  createNavigationHistory,
  goBackInNavigationHistory,
  goForwardInNavigationHistory,
  pushNavigationHistory,
} from "./navigation-history";

const equals = (left: string, right: string) => left === right;

describe("navigation history", () => {
  it("moves backward and forward through visited entries", () => {
    let history = createNavigationHistory("folder");
    history = pushNavigationHistory(history, "note-a", equals);
    history = pushNavigationHistory(history, "note-b", equals);

    history = goBackInNavigationHistory(history);
    expect(history).toEqual({
      back: ["folder"],
      current: "note-a",
      forward: ["note-b"],
    });

    history = goForwardInNavigationHistory(history);
    expect(history).toEqual({
      back: ["folder", "note-a"],
      current: "note-b",
      forward: [],
    });
  });

  it("clears forward history after navigating from a previous entry", () => {
    let history = createNavigationHistory("folder");
    history = pushNavigationHistory(history, "note-a", equals);
    history = pushNavigationHistory(history, "note-b", equals);
    history = goBackInNavigationHistory(history);
    history = pushNavigationHistory(history, "note-c", equals);

    expect(history.current).toBe("note-c");
    expect(history.forward).toEqual([]);
    expect(goForwardInNavigationHistory(history)).toBe(history);
  });

  it("ignores duplicate entries and bounds the back stack", () => {
    let history = createNavigationHistory("folder");
    history = pushNavigationHistory(history, "folder", equals, 2);
    history = pushNavigationHistory(history, "note-a", equals, 2);
    history = pushNavigationHistory(history, "note-b", equals, 2);
    history = pushNavigationHistory(history, "note-c", equals, 2);

    expect(history.back).toEqual(["note-a", "note-b"]);
  });
});
