import { afterEach, expect, it, vi } from "vitest";
import { createEditNotifications } from "./edit-notifications";

afterEach(() => vi.useRealTimers());

it("coalesces a typing burst and publishes the freshest state", () => {
  vi.useFakeTimers();
  let draft = "";
  const notify = vi.fn(() => draft);
  const updates = createEditNotifications(notify);
  for (const text of ["a", "ab", "abc"]) {
    draft = text;
    updates.schedule();
    vi.advanceTimersByTime(30);
  }
  expect(draft).toBe("abc");
  expect(notify).not.toHaveBeenCalled();
  vi.advanceTimersByTime(100);
  expect(notify).toHaveReturnedWith("abc");
  expect(notify).toHaveBeenCalledTimes(1);
  vi.runAllTimers();
  expect(notify).toHaveBeenCalledTimes(1);
});

it("does not starve surrounding UI during continuous typing", () => {
  vi.useFakeTimers();
  const notify = vi.fn();
  const updates = createEditNotifications(notify);
  for (let index = 0; index < 5; index++) {
    updates.schedule();
    vi.advanceTimersByTime(50);
  }
  expect(notify).toHaveBeenCalledTimes(1);
});

it("publishes other actions immediately and cancels pending edit notifications", () => {
  vi.useFakeTimers();
  const notify = vi.fn();
  const updates = createEditNotifications(notify);
  updates.schedule();
  updates.flush();
  expect(notify).toHaveBeenCalledTimes(1);
  vi.runAllTimers();
  expect(notify).toHaveBeenCalledTimes(1);
});
