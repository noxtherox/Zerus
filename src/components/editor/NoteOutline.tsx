import { useEffect, useState } from "react";

interface Heading {
  element: HTMLElement;
  text: string;
  level: number;
}

/** Read rendered headings so formatting, duplicate titles and editor recovery stay in sync. */
export function NoteOutline({ container, onNavigate }: { container: HTMLDivElement | null; onNavigate: () => void }) {
  const [headings, setHeadings] = useState<Heading[]>([]);
  const [active, setActive] = useState(0);

  useEffect(() => {
    if (!container) return;
    let entries: Heading[] = [];
    let frame = 0;
    let layoutTimer: ReturnType<typeof setTimeout> | undefined;
    let needsScan = false;
    const updateActive = () => {
      const scroller = container.querySelector(".mdxeditor-root-contenteditable");
      if (!scroller) return;
      const top = scroller.getBoundingClientRect().top + 48;
      let current = 0;
      entries.forEach(({ element }, index) => {
        if (element.getBoundingClientRect().top <= top) current = index;
      });
      setActive(current);
    };
    const scan = () => {
      const next = Array.from(container.querySelectorAll<HTMLElement>(
        ".zerus-mdx-content h1, .zerus-mdx-content h2, .zerus-mdx-content h3, .zerus-mdx-content h4, .zerus-mdx-content h5, .zerus-mdx-content h6",
      )).map((element) => ({
        element,
        text: element.textContent?.trim() || "Untitled heading",
        level: Number(element.tagName.slice(1)),
      }));
      if (next.length !== entries.length || next.some((heading, index) =>
        heading.element !== entries[index].element || heading.text !== entries[index].text || heading.level !== entries[index].level,
      )) {
        entries = next;
        setHeadings(next);
      }
    };
    const schedule = (headingsChanged = false) => {
      needsScan ||= headingsChanged;
      if (!frame) frame = requestAnimationFrame(() => {
        frame = 0;
        if (needsScan) scan();
        needsScan = false;
        updateActive();
      });
    };
    const headingSelector = "h1, h2, h3, h4, h5, h6";
    const touchesHeading = (node: Node) => {
      const element = node instanceof Element ? node : node.parentElement;
      return !!element && (!!element.closest(headingSelector) || !!element.querySelector(headingSelector));
    };
    const observer = new MutationObserver((records) => {
      // Ignore mutations in the outline itself, toolbar and floating dialogs.
      const edits = records.filter(({ target, addedNodes, removedNodes }) => {
        const element = target instanceof Element ? target : target.parentElement;
        return !!element?.closest(".zerus-mdx-content") ||
          [...addedNodes, ...removedNodes].some((node) => node instanceof Element &&
            (node.matches(".zerus-mdx-content") || !!node.querySelector(".zerus-mdx-content")));
      });
      if (!edits.length) return;
      if (edits.some(({ target, addedNodes, removedNodes }) =>
        (target instanceof Element ? target : target.parentElement)?.closest(headingSelector) ||
        [...addedNodes, ...removedNodes].some(touchesHeading),
      )) schedule(true);
      else {
        // Ordinary prose can move headings, but measuring them can wait until
        // a typing pause. Scrolling always refreshes the active heading.
        clearTimeout(layoutTimer);
        layoutTimer = setTimeout(() => schedule(), 100);
      }
    });
    observer.observe(container, { childList: true, subtree: true, characterData: true });
    const scheduleLayout = () => schedule();
    const resize = new ResizeObserver(scheduleLayout);
    resize.observe(container);
    container.addEventListener("scroll", scheduleLayout, true);
    container.addEventListener("load", scheduleLayout, true);
    scan();
    updateActive();
    return () => {
      observer.disconnect();
      resize.disconnect();
      cancelAnimationFrame(frame);
      clearTimeout(layoutTimer);
      container.removeEventListener("scroll", scheduleLayout, true);
      container.removeEventListener("load", scheduleLayout, true);
    };
  }, [container]);

  if (!headings.length) return null;
  const baseLevel = Math.min(...headings.map((heading) => heading.level));
  return (
    <nav aria-label="Note headings" className="zerus-outline-panel shrink-0 border-t border-border/60">
      <h2 className="px-4 py-3 text-xs font-semibold uppercase tracking-wider text-muted-foreground">Outline</h2>
      <div className="zerus-outline-list">
        {headings.map((heading, index) => (
          <button key={index} type="button" title={heading.text}
            aria-current={index === active ? "location" : undefined}
            style={{ paddingLeft: 12 + (heading.level - baseLevel) * 12 }}
            onClick={() => {
              onNavigate();
              // Let an expanded properties panel reveal the editor before measuring.
              requestAnimationFrame(() => {
                const scroller = container?.querySelector(".mdxeditor-root-contenteditable");
                if (!scroller || !heading.element.isConnected) return;
                scroller.scrollTo({
                  top: scroller.scrollTop + heading.element.getBoundingClientRect().top - scroller.getBoundingClientRect().top - 24,
                  behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth",
                });
                setActive(index);
              });
            }}
          >{heading.text}</button>
        ))}
      </div>
    </nav>
  );
}
