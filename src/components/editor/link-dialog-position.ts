import { useLayoutEffect, useRef } from "react";
import { useCellValues, usePublisher } from "@mdxeditor/gurx";
import {
  activeEditor$,
  addComposerChild$,
  getNodeRectangle,
  linkDialogState$,
  realmPlugin,
} from "@mdxeditor/editor";

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

    // MDXEditor's collapsed selection rectangle has zero width at the start
    // of the text. Anchor existing-link dialogs to the whole link instead.
    // Use its helper to preserve offsets inside fixed containing blocks.
    const rectangle = getNodeRectangle(editor, state.linkNodeKey);
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
