import type { EditorView } from "@codemirror/view";

interface ImageRange {
  from: number;
  to: number;
}

/** Confirms an async image action still targets the same editor source range. */
export function imageEditIsCurrent(
  currentView: EditorView | null,
  expectedView: EditorView,
  range: ImageRange,
  markdown: string,
): boolean {
  return (
    currentView === expectedView &&
    range.from >= 0 &&
    range.to <= expectedView.state.doc.length &&
    expectedView.state.sliceDoc(range.from, range.to) === markdown
  );
}
