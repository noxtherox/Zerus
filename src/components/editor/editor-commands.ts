import {
  type ChangeSpec,
  EditorSelection,
} from "@codemirror/state";
import type { EditorView } from "@codemirror/view";
import {
  interpretMarkdownSource,
  markdownEscapeUnits,
} from "@/lib/markdown-escapes";
import {
  enclosingInlineMarkup,
  inlineMarkupEdit,
} from "./inline-markup";

/** Turn the selected literal Markdown source into deliberate formatting. */
export function interpretSelectionAsMarkdown(view: EditorView): boolean {
  const ranges = view.state.selection.ranges;
  if (ranges.every((range) => range.empty)) return false;

  const source = view.state.doc.toString();
  const units = markdownEscapeUnits(source);
  const edits = ranges.filter((range) => !range.empty).map((range) => {
    const leadingUnit = units.find((unit) => unit.visibleFrom === range.from);
    const from = leadingUnit?.escapeFrom ?? range.from;
    return {
      from,
      to: range.to,
      insert: interpretMarkdownSource(view.state.sliceDoc(from, range.to)),
    };
  });
  const changes = view.state.changes(edits);
  view.dispatch({
    changes,
    selection: EditorSelection.create(
      ranges.map((range) =>
        EditorSelection.range(
          changes.mapPos(range.anchor, -1),
          changes.mapPos(range.head, 1),
        ),
      ),
      view.state.selection.mainIndex,
    ),
    userEvent: "input.interpretMarkdown",
  });
  view.focus();
  return true;
}

export function toggleInlineMarkup(
  view: EditorView,
  marker: string,
  placeholder: string,
) {
  const { from, to, anchor, head } = view.state.selection.main;
  const enclosingMarkup = enclosingInlineMarkup(view.state, from, to, marker);
  if (enclosingMarkup) {
    const changes = view.state.changes([
      { from: enclosingMarkup.openingFrom, to: enclosingMarkup.openingTo },
      { from: enclosingMarkup.closingFrom, to: enclosingMarkup.closingTo },
    ]);
    view.dispatch({
      changes,
      selection: EditorSelection.range(
        changes.mapPos(anchor, 1),
        changes.mapPos(head, 1),
      ),
    });
    view.focus();
    return;
  }

  const selectedText = view.state.sliceDoc(from, to);
  const edit = inlineMarkupEdit(selectedText, marker, placeholder);
  const selectionAnchor =
    from + (anchor <= head ? edit.selectionFrom : edit.selectionTo);
  const selectionHead =
    from + (anchor <= head ? edit.selectionTo : edit.selectionFrom);
  view.dispatch({
    changes: { from, to, insert: edit.insert },
    selection: EditorSelection.range(selectionAnchor, selectionHead),
  });
  view.focus();
}

function dispatchLineChanges(
  view: EditorView,
  changes: ChangeSpec,
  anchor: number,
  head: number,
) {
  const changeSet = view.state.changes(changes);
  view.dispatch({
    changes: changeSet,
    selection: EditorSelection.range(
      changeSet.mapPos(anchor, 1),
      changeSet.mapPos(head, 1),
    ),
  });
  view.focus();
}

export function toggleLinePrefix(
  view: EditorView,
  prefix: string | ((index: number) => string),
  prefixPattern: RegExp,
) {
  const { anchor, head, from, to } = view.state.selection.main;
  const firstLine = view.state.doc.lineAt(from);
  const lastPosition =
    to > from && view.state.doc.lineAt(to).from === to ? to - 1 : to;
  const lastLine = view.state.doc.lineAt(lastPosition);
  const lines = [];

  for (
    let lineNumber = firstLine.number;
    lineNumber <= lastLine.number;
    lineNumber += 1
  ) {
    lines.push(view.state.doc.line(lineNumber));
  }

  const shouldRemovePrefix = lines.every((line) =>
    prefixPattern.test(line.text),
  );
  const changes = lines.map((line, index) => {
    if (shouldRemovePrefix) {
      const match = line.text.match(prefixPattern);
      return {
        from: line.from,
        to: line.from + (match?.[0].length ?? 0),
        insert: "",
      };
    }
    return {
      from: line.from,
      insert: typeof prefix === "function" ? prefix(index) : prefix,
    };
  });

  dispatchLineChanges(view, changes, anchor, head);
}

export function setHeadingLevel(view: EditorView, level: 1 | 2 | 3) {
  const { anchor, head, from, to } = view.state.selection.main;
  const firstLine = view.state.doc.lineAt(from);
  const lastPosition =
    to > from && view.state.doc.lineAt(to).from === to ? to - 1 : to;
  const lastLine = view.state.doc.lineAt(lastPosition);
  const lines = [];
  const prefix = `${"#".repeat(level)} `;
  const headingPattern = /^#{1,6}\s/;

  for (
    let lineNumber = firstLine.number;
    lineNumber <= lastLine.number;
    lineNumber += 1
  ) {
    lines.push(view.state.doc.line(lineNumber));
  }

  const shouldRemoveHeading = lines.every((line) =>
    line.text.startsWith(prefix),
  );
  const changes = lines.map((line) => {
    const existingHeading = line.text.match(headingPattern);
    return {
      from: line.from,
      to: line.from + (existingHeading?.[0].length ?? 0),
      insert: shouldRemoveHeading ? "" : prefix,
    };
  });

  dispatchLineChanges(view, changes, anchor, head);
}
