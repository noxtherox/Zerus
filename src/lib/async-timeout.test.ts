import { afterEach, expect, it, vi } from "vitest";
import { withTimeout } from "./async-timeout";

afterEach(() => vi.useRealTimers());

it("stops a stalled read and allows a new attempt", async () => {
  vi.useFakeTimers();
  let finish!: (value: string) => void;
  const pending = new Promise<string>((resolve) => { finish = resolve; });
  const attempt = expect(withTimeout(pending, 30_000, "Retry loading")).rejects.toThrow("Retry loading");
  await vi.advanceTimersByTimeAsync(30_000);
  await attempt;
  finish("Late result");
  await expect(withTimeout(Promise.resolve("Full note"), 30_000, "Retry loading")).resolves.toBe("Full note");
  expect(vi.getTimerCount()).toBe(0);
});
