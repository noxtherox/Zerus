import { type Extension } from "@codemirror/state";
import {
  EditorView,
  keymap,
  type Panel,
  type ViewUpdate,
} from "@codemirror/view";
import {
  closeSearchPanel,
  findNext,
  findPrevious,
  getSearchQuery,
  openSearchPanel,
  search,
  SearchQuery,
  searchKeymap,
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
  input.autocomplete = "off";
  input.spellcheck = false;

  const updateQuery = () => {
    view.dispatch({
      effects: setSearchQuery.of(new SearchQuery({ search: input.value })),
    });
  };

  input.addEventListener("input", updateQuery);
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
    }
  });

  dom.append(
    input,
    createButton("Previous match", "↑", () => findPrevious(view)),
    createButton("Next match", "↓", () => findNext(view)),
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
    },
  };
}

const findPanelTheme = EditorView.baseTheme({
  ".cm-panels-top": {
    borderBottom: "1px solid rgb(var(--grim-text) / 0.12)",
  },
  ".cm-find-in-note": {
    display: "flex",
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
});

export const findInNoteExtension: Extension = [
  search({ top: true, createPanel: createFindPanel }),
  keymap.of(searchKeymap),
  findPanelTheme,
];

export function openFindInNote(view: EditorView) {
  return openSearchPanel(view);
}
