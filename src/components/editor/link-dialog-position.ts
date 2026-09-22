import { useLayoutEffect, useRef } from "react";
import { useCellValues, usePublisher } from "@mdxeditor/gurx";
import {
  activeEditor$,
  addComposerChild$,
  linkDialogState$,
  realmPlugin,
} from "@mdxeditor/editor";
import type { LexicalEditor } from "lexical";

type LinkRectangle = { top: number; left: number; width: number; height: number };

const CONTAINING_BLOCK_PROPERTIES = [
  "transform",
  "perspective",
  "filter",
  "backdrop-filter",
  "contain",
  "container-type",
];
const CONTAINING_BLOCK_VALUES = ["layout", "paint", "strict", "content"];

function fixedContainingBlock(element: HTMLElement | null): HTMLElement | null {
  for (let current = element?.parentElement ?? null; current; current = current.parentElement) {
    const style = window.getComputedStyle(current);
    const willChange = style.willChange.split(",").map((value) => value.trim());
    if (
      style.transform !== "none" ||
      style.perspective !== "none" ||
      style.filter !== "none" ||
      style.backdropFilter !== "none" ||
      CONTAINING_BLOCK_VALUES.includes(style.contain) ||
      style.containerType !== "normal" ||
      style.contentVisibility === "auto" ||
      willChange.some((property) => CONTAINING_BLOCK_PROPERTIES.includes(property))
    ) return current;
  }
  return null;
}

function roundedRectangle(rectangle: DOMRect | LinkRectangle): LinkRectangle {
  return {
    top: Math.round(rectangle.top),
    left: Math.round(rectangle.left),
    width: Math.round(rectangle.width),
    height: Math.round(rectangle.height),
  };
}

/** Return the node rectangle in viewport coordinates for a body-level portal. */
export function getViewportNodeRectangle(
  editor: LexicalEditor,
  nodeKey: string,
): LinkRectangle | null {
  const element = editor.getElementByKey(nodeKey);
  return element ? roundedRectangle(element.getBoundingClientRect()) : null;
}

/** Convert MDXEditor's containing-block-relative selection rectangle. */
export function getViewportSelectionRectangle(
  editor: LexicalEditor | null,
  rectangle: LinkRectangle,
): LinkRectangle {
  const container = fixedContainingBlock(editor?.getRootElement() ?? null);
  if (!container) return rectangle;
  const containerRectangle = container.getBoundingClientRect();
  return {
    top: Math.round(rectangle.top + containerRectangle.top),
    left: Math.round(rectangle.left + containerRectangle.left),
    width: Math.round(rectangle.width),
    height: Math.round(rectangle.height),
  };
}

function LinkDialogPosition() {
  const [editor, state] = useCellValues(activeEditor$, linkDialogState$);
  const publishState = usePublisher(linkDialogState$);
  const dialogActive = useRef(false);
  const lastScroll = useRef<
    Array<{ element: HTMLElement; left: number; top: number }>
  >([]);
  const scrollCommitTimer = useRef(0);
  const restorationFrame = useRef(0);

  dialogActive.current = state.type !== "inactive";

  useLayoutEffect(() => {
    const editorRoot = editor?.getRootElement();
    if (!editorRoot) return;
    const ancestors: HTMLElement[] = [];
    for (
      let element: HTMLElement | null = editorRoot;
      element;
      element = element.parentElement
    ) {
      ancestors.push(element);
    }
    const captureScroll = () =>
      ancestors.map((element) => ({
        element,
        left: element.scrollLeft,
        top: element.scrollTop,
      }));
    const recordStableScroll = () => {
      if (dialogActive.current) return;
      const snapshot = captureScroll();
      window.clearTimeout(scrollCommitTimer.current);
      scrollCommitTimer.current = window.setTimeout(() => {
        if (!dialogActive.current) lastScroll.current = snapshot;
      }, 80);
    };
    const captureLinkActivation = (event: Event) => {
      const target = event.target;
      if (
        !dialogActive.current &&
        target instanceof Element &&
        target.closest("a")
      ) {
        window.clearTimeout(scrollCommitTimer.current);
        lastScroll.current = captureScroll();
      }
    };
    lastScroll.current = captureScroll();
    for (const element of ancestors) {
      element.addEventListener("scroll", recordStableScroll, { passive: true });
    }
    editorRoot.addEventListener("pointerdown", captureLinkActivation, true);
    editorRoot.addEventListener("mousedown", captureLinkActivation, true);
    editorRoot.addEventListener("click", captureLinkActivation, true);
    return () => {
      window.clearTimeout(scrollCommitTimer.current);
      editorRoot.removeEventListener("pointerdown", captureLinkActivation, true);
      editorRoot.removeEventListener("mousedown", captureLinkActivation, true);
      editorRoot.removeEventListener("click", captureLinkActivation, true);
      for (const element of ancestors) {
        element.removeEventListener("scroll", recordStableScroll);
      }
    };
  }, [editor]);

  useLayoutEffect(() => {
    if (!editor || state.type === "inactive") return;
    window.clearTimeout(scrollCommitTimer.current);
    const startedAt = performance.now();
    cancelAnimationFrame(restorationFrame.current);
    const restore = () => {
      for (const { element, left, top } of lastScroll.current) {
        element.scrollLeft = left;
        element.scrollTop = top;
      }
      if (performance.now() - startedAt < 150) {
        restorationFrame.current = requestAnimationFrame(restore);
      }
    };
    restorationFrame.current = requestAnimationFrame(restore);
    return () => cancelAnimationFrame(restorationFrame.current);
  }, [editor, state.type]);

  useLayoutEffect(() => {
    if (!editor || state.type === "inactive" || !state.linkNodeKey) return;

    // MDXEditor's rectangle is relative to the nearest fixed containing block.
    // Our dialog is portaled to the body, so use the link's viewport rectangle.
    const rectangle = getViewportNodeRectangle(editor, state.linkNodeKey);
    if (!rectangle) return;
    const previous = state.rectangle;
    if (
      rectangle.top !== previous.top ||
      rectangle.left !== previous.left ||
      rectangle.width !== previous.width ||
      rectangle.height !== previous.height
    ) {
      publishState({ ...state, rectangle });
    }
  }, [editor, state, publishState]);

  return null;
}

export const linkDialogPositionPlugin = realmPlugin({
  init(realm) {
    realm.pub(addComposerChild$, LinkDialogPosition);
  },
});
