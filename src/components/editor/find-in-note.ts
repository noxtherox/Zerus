import { type EditorState, type Extension } from "@codemirror/state";
import {
  EditorView,
  keymap,
  type Panel,
  ViewPlugin,
  type ViewUpdate,
} from "@codemirror/view";
import { redo, undo } from "@codemirror/commands";
import {
  closeSearchPanel,
  findNext,
  findPrevious,
  getSearchQuery,
  openSearchPanel,
  replaceAll,
  replaceNext,
  search,
  SearchQuery,
  searchKeymap,
  searchPanelOpen,
  setSearchQuery,
} from "@codemirror/search";

function createButton(label: string, content: string, onClick: () => void) {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = content;
  button.title = label;
  button.setAttribute("aria-label", label);
  button.addEventListener("click", onClick);
  return button;
}

export function searchMatchSummary(
  state: EditorState,
  query: SearchQuery,
): { current: number | null; total: number; label: string } {
  if (!query.valid) return { current: null, total: 0, label: "0 matches" };

  const selection = state.selection.main;
  const cursor = query.getCursor(state);
  let total = 0;
  let current: number | null = null;

  for (let next = cursor.next(); !next.done; next = cursor.next()) {
    total += 1;
    if (next.value.from === selection.from && next.value.to === selection.to) {
      current = total;
    }
  }

  const label =
    current == null
      ? `${total} ${total === 1 ? "match" : "matches"}`
      : `${current} of ${total}`;
  return { current, total, label };
}

function createFindPanel(view: EditorView): Panel {
  const dom = document.createElement("div");
  dom.className = "cm-find-in-note";
  dom.setAttribute("role", "search");
  dom.setAttribute("aria-label", "Find in note");

  const input = document.createElement("input");
  input.type = "search";
  input.value = getSearchQuery(view.state).search;
  input.placeholder = "Find in note";
  input.setAttribute("aria-label", "Find in note");
  input.setAttribute("main-field", "true");
  input.name = "find";
  input.autocomplete = "off";
  input.spellcheck = false;

  const matchCount = document.createElement("span");
  matchCount.className = "cm-find-match-count";
  matchCount.setAttribute("role", "status");
  matchCount.setAttribute("aria-live", "polite");
  const updateMatchCount = () => {
    matchCount.textContent = searchMatchSummary(
      view.state,
      getSearchQuery(view.state),
    ).label;
  };
  updateMatchCount();

  const replaceInput = document.createElement("input");
  replaceInput.type = "text";
  replaceInput.value = getSearchQuery(view.state).replace;
  replaceInput.placeholder = "Replace with";
  replaceInput.setAttribute("aria-label", "Replace with");
  replaceInput.name = "replace";
  replaceInput.autocomplete = "off";
  replaceInput.spellcheck = false;

  const updateQuery = () => {
    const current = getSearchQuery(view.state);
    view.dispatch({
      effects: setSearchQuery.of(
        new SearchQuery({
          search: input.value,
          replace: replaceInput.value,
          caseSensitive: current.caseSensitive,
          literal: current.literal,
          regexp: current.regexp,
          wholeWord: current.wholeWord,
        }),
      ),
    });
  };

  input.addEventListener("input", updateQuery);
  replaceInput.addEventListener("input", updateQuery);
  dom.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      if (event.shiftKey) findPrevious(view);
      else findNext(view);
    } else if (event.key === "Escape") {
      event.preventDefault();
      closeSearchPanel(view);
    } else if (
      event.key.toLowerCase() === "f" &&
      (event.metaKey || event.ctrlKey)
    ) {
      event.preventDefault();
      input.focus();
      input.select();
    } else if (
      event.key.toLowerCase() === "z" &&
      (event.metaKey || event.ctrlKey)
    ) {
      event.preventDefault();
      if (event.shiftKey) redo(view);
      else undo(view);
    }
  });

  dom.append(
    input,
    matchCount,
    createButton("Previous match", "↑", () => findPrevious(view)),
    createButton("Next match", "↓", () => findNext(view)),
    replaceInput,
    createButton("Replace", "Replace", () => replaceNext(view)),
    createButton("Replace all", "Replace all", () => replaceAll(view)),
    createButton("Close find", "×", () => closeSearchPanel(view)),
  );

  return {
    dom,
    mount: () => {
      input.focus();
      input.select();
    },
    update: (update: ViewUpdate) => {
      const query = getSearchQuery(update.state).search;
      if (query !== input.value) input.value = query;
      const replacement = getSearchQuery(update.state).replace;
      if (replacement !== replaceInput.value) replaceInput.value = replacement;
      updateMatchCount();
    },
  };
}

export function literalMatchRanges(text: string, query: string) {
  if (!query) return [];
  const ranges: Array<{ from: number; to: number }> = [];
  const searchableText = text.toLocaleLowerCase();
  const searchableQuery = query.toLocaleLowerCase();
  let from = 0;

  while (from <= searchableText.length - searchableQuery.length) {
    const matchFrom = searchableText.indexOf(searchableQuery, from);
    if (matchFrom < 0) break;
    ranges.push({ from: matchFrom, to: matchFrom + query.length });
    from = matchFrom + Math.max(1, query.length);
  }

  return ranges;
}

function highlightTableCell(cell: HTMLTableCellElement, query: string) {
  if (document.activeElement === cell) return;
  const text = cell.textContent ?? "";
  const ranges = literalMatchRanges(text, query);
  if (!cell.querySelector("mark") && ranges.length === 0) return;

  cell.replaceChildren();
  let position = 0;
  for (const range of ranges) {
    if (range.from > position) {
      cell.append(document.createTextNode(text.slice(position, range.from)));
    }
    const mark = document.createElement("mark");
    mark.className = "cm-rendered-table-search-match";
    mark.textContent = text.slice(range.from, range.to);
    cell.append(mark);
    position = range.to;
  }
  if (position < text.length) {
    cell.append(document.createTextNode(text.slice(position)));
  }
}

function highlightRenderedTables(view: EditorView) {
  const query = searchPanelOpen(view.state)
    ? getSearchQuery(view.state).search
    : "";
  view.dom
    .querySelectorAll<HTMLTableCellElement>(
      ".cm-markdown-table th, .cm-markdown-table td",
    )
    .forEach((cell) => highlightTableCell(cell, query));
}

const renderedTableSearchHighlights = ViewPlugin.fromClass(
  class {
    private frame: number | null = null;
    private readonly handleFocusIn = (event: FocusEvent) => {
      const cell =
        event.target instanceof Element
          ? event.target.closest<HTMLTableCellElement>(
              ".cm-markdown-table th, .cm-markdown-table td",
            )
          : null;
      if (cell) highlightTableCell(cell, "");
    };
    private readonly handleFocusOut = () => this.schedule();

    constructor(private readonly view: EditorView) {
      view.dom.addEventListener("focusin", this.handleFocusIn);
      view.dom.addEventListener("focusout", this.handleFocusOut);
      this.schedule();
    }

    update() {
      this.schedule();
    }

    schedule() {
      if (this.frame != null) cancelAnimationFrame(this.frame);
      this.frame = requestAnimationFrame(() => {
        this.frame = null;
        highlightRenderedTables(this.view);
      });
    }

    destroy() {
      if (this.frame != null) cancelAnimationFrame(this.frame);
      this.view.dom.removeEventListener("focusin", this.handleFocusIn);
      this.view.dom.removeEventListener("focusout", this.handleFocusOut);
    }
  },
);

const findPanelTheme = EditorView.baseTheme({
  ".cm-panels-top": {
    borderBottom: "1px solid rgb(var(--grim-text) / 0.12)",
  },
  ".cm-find-in-note": {
    display: "flex",
    flexWrap: "wrap",
    alignItems: "center",
    gap: "6px",
    padding: "7px 12px",
    backgroundColor: "rgb(var(--grim-editor-bg))",
    color: "rgb(var(--grim-text))",
  },
  ".cm-find-in-note input": {
    minWidth: "120px",
    flex: "1 1 220px",
    border: "1px solid rgb(var(--grim-text) / 0.16)",
    borderRadius: "6px",
    padding: "4px 8px",
    backgroundColor: "rgb(var(--grim-text) / 0.05)",
    color: "inherit",
    outline: "none",
  },
  ".cm-find-in-note input:focus": {
    borderColor: "rgb(var(--grim-accent) / 0.7)",
    boxShadow: "0 0 0 2px rgb(var(--grim-accent) / 0.12)",
  },
  ".cm-find-match-count": {
    minWidth: "58px",
    color: "rgb(var(--grim-text) / 0.58)",
    fontSize: "12px",
    fontVariantNumeric: "tabular-nums",
    textAlign: "center",
    whiteSpace: "nowrap",
  },
  ".cm-find-in-note button": {
    border: "0",
    borderRadius: "6px",
    width: "28px",
    height: "28px",
    padding: "0",
    backgroundColor: "transparent",
    color: "rgb(var(--grim-text) / 0.7)",
    cursor: "pointer",
  },
  ".cm-find-in-note button[aria-label='Replace'], .cm-find-in-note button[aria-label='Replace all']": {
    width: "auto",
    padding: "0 9px",
  },
  ".cm-find-in-note button:hover": {
    backgroundColor: "rgb(var(--grim-text) / 0.08)",
    color: "rgb(var(--grim-text))",
  },
  ".cm-searchMatch": {
    backgroundColor: "rgb(var(--grim-accent) / 0.22)",
    borderRadius: "2px",
  },
  ".cm-searchMatch.cm-searchMatch-selected": {
    backgroundColor: "rgb(var(--grim-accent) / 0.42)",
  },
  ".cm-rendered-table-search-match": {
    borderRadius: "2px",
    backgroundColor: "rgb(var(--grim-accent) / 0.34)",
    color: "inherit",
    pointerEvents: "none",
  },
});

export const findInNoteExtension: Extension = [
  search({ top: true, createPanel: createFindPanel }),
  keymap.of(searchKeymap),
  renderedTableSearchHighlights,
  findPanelTheme,
];

export function openFindInNote(view: EditorView) {
  return openSearchPanel(view);
}
