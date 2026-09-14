import { describe, expect, it, vi } from "vitest";
import { handleMiddleMouseDown } from "./middle-click";

describe("handleMiddleMouseDown", () => {
  it("runs the action and prevents native handling for the middle button", () => {
    const preventDefault = vi.fn();
    const action = vi.fn();

    handleMiddleMouseDown({ button: 1, preventDefault }, action);

    expect(preventDefault).toHaveBeenCalledOnce();
    expect(action).toHaveBeenCalledOnce();
  });

  it("ignores other mouse buttons", () => {
    const preventDefault = vi.fn();
    const action = vi.fn();

    handleMiddleMouseDown({ button: 0, preventDefault }, action);

    expect(preventDefault).not.toHaveBeenCalled();
    expect(action).not.toHaveBeenCalled();
  });
});
