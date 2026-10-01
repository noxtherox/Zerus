import { useCallback, useEffect, useRef, type MouseEvent } from "react";

const TAP_INTERVAL_MS = 350;
const TAP_DISTANCE_PX = 24;

/** Preserve the current workspace while distinguishing a click from a triple tap. */
export function useNoteActivation(
  onOpen: (id: string) => void,
  onOpenInNewTab: (id: string) => void,
  resetKey: string,
) {
  const sequence = useRef<{
    id: string;
    count: number;
    time: number;
    x: number;
    y: number;
  } | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const cancel = useCallback(() => {
    if (timer.current !== null) clearTimeout(timer.current);
    timer.current = null;
    sequence.current = null;
  }, []);

  useEffect(() => cancel, [cancel, resetKey]);

  const activate = (event: MouseEvent, id: string) => {
    if (event.defaultPrevented || event.button !== 0) return;
    if (event.detail === 0) {
      cancel();
      onOpen(id);
      return;
    }

    const previous = sequence.current;
    const repeated =
      previous?.id === id &&
      event.timeStamp - previous.time <= TAP_INTERVAL_MS &&
      Math.hypot(event.clientX - previous.x, event.clientY - previous.y) <=
        TAP_DISTANCE_PX;
    const count = repeated ? previous.count + 1 : 1;
    cancel();
    if (count === 3) {
      event.preventDefault();
      onOpenInNewTab(id);
      return;
    }

    sequence.current = {
      id,
      count,
      time: event.timeStamp,
      x: event.clientX,
      y: event.clientY,
    };
    timer.current = setTimeout(() => {
      cancel();
      onOpen(id);
    }, TAP_INTERVAL_MS);
  };

  return { activate, cancel };
}
