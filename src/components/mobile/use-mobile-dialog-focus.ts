import { useEffect, useRef, type RefObject } from "react";

/** Keyboard containment for the gesture-driven sheets that cannot use a portal. */
export function useMobileDialogFocus<T extends HTMLElement>(
  container: RefObject<T | null>,
  onClose: () => void,
  enabled = true,
) {
  const close = useRef(onClose);
  close.current = onClose;

  useEffect(() => {
    const panel = container.current;
    if (!enabled || !panel) return;
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const controls = () => Array.from(panel.querySelectorAll<HTMLElement>(
      'button:not(:disabled), a[href], input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex="0"]',
    )).filter(element => element.getClientRects().length && !element.closest('[inert], [aria-hidden="true"]'));
    const frame = requestAnimationFrame(() => controls()[0]?.focus({ preventScroll: true }));
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !event.defaultPrevented) {
        event.preventDefault();
        event.stopPropagation();
        close.current();
      }
      if (event.key !== "Tab") return;
      const items = controls();
      const first = items[0];
      const last = items.at(-1);
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last?.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first?.focus();
      }
    };
    panel.addEventListener("keydown", onKeyDown);
    return () => {
      cancelAnimationFrame(frame);
      panel.removeEventListener("keydown", onKeyDown);
      if (previous?.isConnected && !previous.closest("[inert]")) previous.focus({ preventScroll: true });
    };
  }, [container, enabled]);
}
