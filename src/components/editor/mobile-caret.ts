/** The editor can extend behind the keyboard in WKWebView, even with 100dvh. */
export function mobileCaretLayout(
  scroller: { top: number; bottom: number },
  viewport: { offsetTop: number; height: number },
  caret?: { top: number; bottom: number },
) {
  const top = Math.max(scroller.top, viewport.offsetTop) + 16;
  const bottom = Math.min(scroller.bottom, viewport.offsetTop + viewport.height) - 24;
  const padding = Math.max(0, scroller.bottom - viewport.offsetTop - viewport.height);
  const scroll = !caret || bottom <= top ? 0
    : caret.bottom > bottom ? caret.bottom - bottom
    : caret.top < top ? caret.top - top : 0;
  return { padding, scroll };
}

export function keepMobileCaretVisible(wrapper: HTMLElement) {
  if (!wrapper.closest(".mobile-note-editor")) return;
  const viewport = window.visualViewport;
  let frame = 0;
  const update = () => {
    frame = 0;
    const scroller = wrapper.querySelector<HTMLElement>(".mdxeditor-root-contenteditable");
    if (!scroller) return;
    const bounds = scroller.getBoundingClientRect();
    const visible = viewport ?? { offsetTop: 0, height: window.innerHeight };
    const { padding } = mobileCaretLayout(bounds, visible);
    wrapper.style.setProperty("--mobile-keyboard-overlap", `${padding}px`);

    const selection = window.getSelection();
    if (!selection?.isCollapsed || !selection.rangeCount ||
        !scroller.contains(selection.anchorNode) || !scroller.contains(document.activeElement)) return;
    const range = selection.getRangeAt(0);
    let caret = range.getClientRects()[0];
    // WebKit can return no collapsed range rect for a new empty paragraph.
    // Measure its line box without inserting a marker into Lexical's DOM.
    if (!caret || !caret.height) {
      const node = selection.anchorNode;
      const element = node?.nodeType === Node.ELEMENT_NODE ? node as Element : node?.parentElement;
      if (element && !element.textContent) caret = element.getBoundingClientRect();
    }
    if (!caret?.height) return;
    const { scroll } = mobileCaretLayout(bounds, visible, caret);
    if (scroll) scroller.scrollTop += scroll;
  };
  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(update);
  };
  wrapper.addEventListener("input", schedule);
  wrapper.addEventListener("focusin", schedule);
  document.addEventListener("selectionchange", schedule);
  viewport?.addEventListener("resize", schedule);
  viewport?.addEventListener("scroll", schedule);
  window.addEventListener("resize", schedule);
  const observer = new ResizeObserver(schedule);
  observer.observe(wrapper);
  schedule();
  return () => {
    cancelAnimationFrame(frame);
    observer.disconnect();
    wrapper.removeEventListener("input", schedule);
    wrapper.removeEventListener("focusin", schedule);
    document.removeEventListener("selectionchange", schedule);
    viewport?.removeEventListener("resize", schedule);
    viewport?.removeEventListener("scroll", schedule);
    window.removeEventListener("resize", schedule);
    wrapper.style.removeProperty("--mobile-keyboard-overlap");
  };
}
