import { EditorSelection } from "@codemirror/state";
import { Decoration, EditorView, WidgetType } from "@codemirror/view";

export type TableAlignment = "left" | "center" | "right" | null;

export interface MarkdownTableData {
  headers: string[];
  alignments: TableAlignment[];
  rows: string[][];
}

export const MAX_TABLE_COLUMNS = 12;
export const MAX_TABLE_ROWS = 50;

function splitRow(line: string): string[] {
  const cells: string[] = [];
  let cell = "";
  let escaped = false;

  for (const character of line.trim()) {
    if (escaped) {
      cell += character === "|" ? "|" : `\\${character}`;
      escaped = false;
    } else if (character === "\\") {
      escaped = true;
    } else if (character === "|") {
      cells.push(cell.trim());
      cell = "";
    } else {
      cell += character;
    }
  }
  if (escaped) cell += "\\";
  cells.push(cell.trim());

  if (line.trimStart().startsWith("|")) cells.shift();
  if (line.trimEnd().endsWith("|")) cells.pop();
  return cells;
}

function alignmentFor(delimiter: string): TableAlignment {
  const value = delimiter.trim();
  const left = value.startsWith(":");
  const right = value.endsWith(":");
  if (left && right) return "center";
  if (right) return "right";
  if (left) return "left";
  return null;
}

export function parseMarkdownTable(markdown: string): MarkdownTableData | null {
  const lines = markdown.split("\n");
  if (lines.length < 2) return null;

  const headers = splitRow(lines[0]);
  const delimiters = splitRow(lines[1]);
  if (
    headers.length === 0 ||
    delimiters.length !== headers.length ||
    delimiters.some((cell) => !/^:?-{3,}:?$/.test(cell))
  ) {
    return null;
  }

  return {
    headers,
    alignments: delimiters.map(alignmentFor),
    rows: lines.slice(2).map((line) => {
      const cells = splitRow(line).slice(0, headers.length);
      return [...cells, ...Array(Math.max(0, headers.length - cells.length)).fill("")];
    }),
  };
}

function setCellAlignment(cell: HTMLTableCellElement, alignment: TableAlignment) {
  if (alignment) cell.style.textAlign = alignment;
}

function delimiterFor(alignment: TableAlignment): string {
  if (alignment === "left") return ":---";
  if (alignment === "center") return ":---:";
  if (alignment === "right") return "---:";
  return "---";
}

function markdownCell(value: string): string {
  return value.replace(/\r?\n/g, " ").replace(/\|/g, "\\|").trim();
}

export function serializeMarkdownTable(data: MarkdownTableData): string {
  const columns = data.headers.length;
  const row = (cells: string[]) =>
    `| ${Array.from(
      { length: columns },
      (_, index) => markdownCell(cells[index] ?? ""),
    ).join(" | ")} |`;

  return [
    row(data.headers),
    `| ${Array.from(
      { length: columns },
      (_, index) => delimiterFor(data.alignments[index] ?? null),
    ).join(" | ")} |`,
    ...data.rows.map(row),
  ].join("\n");
}

export function appendMarkdownTableRow(
  data: MarkdownTableData,
): MarkdownTableData | null {
  if (data.rows.length >= MAX_TABLE_ROWS) return null;
  return {
    ...data,
    rows: [...data.rows, Array(data.headers.length).fill("")],
  };
}

export function appendMarkdownTableColumn(
  data: MarkdownTableData,
): MarkdownTableData | null {
  if (data.headers.length >= MAX_TABLE_COLUMNS) return null;
  return {
    headers: [...data.headers, `Column ${data.headers.length + 1}`],
    alignments: [...data.alignments, null],
    rows: data.rows.map((row) => [...row, ""]),
  };
}

function tableCells(table: HTMLTableElement): HTMLTableCellElement[] {
  return Array.from(table.querySelectorAll<HTMLTableCellElement>("th, td"));
}

interface TableCellRange {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

function tableCellRange(
  anchorIndex: number,
  focusIndex: number,
  columns: number,
): TableCellRange | null {
  if (columns < 1 || anchorIndex < 0 || focusIndex < 0) return null;
  const anchorRow = Math.floor(anchorIndex / columns);
  const anchorColumn = anchorIndex % columns;
  const focusRow = Math.floor(focusIndex / columns);
  const focusColumn = focusIndex % columns;
  return {
    top: Math.min(anchorRow, focusRow),
    right: Math.max(anchorColumn, focusColumn),
    bottom: Math.max(anchorRow, focusRow),
    left: Math.min(anchorColumn, focusColumn),
  };
}

export function tableCellRangeIndices(
  anchorIndex: number,
  focusIndex: number,
  columns: number,
): number[] {
  const range = tableCellRange(anchorIndex, focusIndex, columns);
  if (!range) return [];
  const indices: number[] = [];
  for (let row = range.top; row <= range.bottom; row += 1) {
    for (let column = range.left; column <= range.right; column += 1) {
      indices.push(row * columns + column);
    }
  }
  return indices;
}

export function serializeTableCellRange(
  values: string[],
  anchorIndex: number,
  focusIndex: number,
  columns: number,
): string {
  const range = tableCellRange(anchorIndex, focusIndex, columns);
  if (!range) return "";
  const rows: string[] = [];
  for (let row = range.top; row <= range.bottom; row += 1) {
    const valuesInRow: string[] = [];
    for (let column = range.left; column <= range.right; column += 1) {
      valuesInRow.push(values[row * columns + column] ?? "");
    }
    rows.push(valuesInRow.join("\t"));
  }
  return rows.join("\n");
}

function tableCellRangeHtml(
  values: string[],
  anchorIndex: number,
  focusIndex: number,
  columns: number,
): string {
  const range = tableCellRange(anchorIndex, focusIndex, columns);
  if (!range) return "";
  const table = document.createElement("table");
  const body = table.createTBody();
  for (let row = range.top; row <= range.bottom; row += 1) {
    const tableRow = body.insertRow();
    for (let column = range.left; column <= range.right; column += 1) {
      const cell = tableRow.insertCell();
      cell.textContent = values[row * columns + column] ?? "";
    }
  }
  return table.outerHTML;
}

function dataFromTable(
  table: HTMLTableElement,
  alignments: TableAlignment[],
): MarkdownTableData {
  const headers = Array.from(table.tHead?.rows[0]?.cells ?? []).map(
    (cell) => cell.textContent ?? "",
  );
  const rows = Array.from(table.tBodies[0]?.rows ?? []).map((row) =>
    Array.from(row.cells).map((cell) => cell.textContent ?? ""),
  );
  return { headers, alignments, rows };
}

function focusCell(cell: HTMLTableCellElement, selectContents = false) {
  cell.focus();
  const selection = window.getSelection();
  if (!selection) return;
  const range = document.createRange();
  range.selectNodeContents(cell);
  if (!selectContents) range.collapse(false);
  selection.removeAllRanges();
  selection.addRange(range);
}

function caretOffset(cell: HTMLTableCellElement): number | null {
  const selection = window.getSelection();
  if (!selection?.rangeCount || !cell.contains(selection.anchorNode)) return null;
  const range = selection.getRangeAt(0).cloneRange();
  range.selectNodeContents(cell);
  range.setEnd(selection.anchorNode!, selection.anchorOffset);
  return range.toString().length;
}

function configureCell(
  cell: HTMLTableCellElement,
  alignment: TableAlignment,
  readOnly: boolean,
) {
  cell.contentEditable = readOnly ? "false" : "plaintext-only";
  cell.spellcheck = true;
  cell.tabIndex = readOnly ? -1 : 0;
  setCellAlignment(cell, alignment);
}

function focusTableCellAfterUpdate(
  view: EditorView,
  sourceFrom: number,
  cellIndex: number,
) {
  requestAnimationFrame(() => {
    const wrapper = view.dom.querySelector<HTMLElement>(
      `.cm-markdown-table-wrapper[data-source-from="${sourceFrom}"]`,
    );
    const table = wrapper?.querySelector<HTMLTableElement>("table");
    const cells = table ? tableCells(table) : [];
    if (cells[cellIndex]) focusCell(cells[cellIndex], true);
  });
}

function replaceTable(
  wrapper: HTMLDivElement,
  view: EditorView,
  data: MarkdownTableData,
  focusIndex: number,
) {
  const from = Number(wrapper.dataset.sourceFrom);
  const to = Number(wrapper.dataset.sourceTo);
  if (!Number.isFinite(from) || !Number.isFinite(to)) return;
  view.dispatch({
    changes: { from, to, insert: serializeMarkdownTable(data) },
    userEvent: "input",
  });
  focusTableCellAfterUpdate(view, from, focusIndex);
}

function createTableToolbar(
  wrapper: HTMLDivElement,
  view: EditorView,
  data: MarkdownTableData,
  readOnly: boolean,
): HTMLDivElement {
  const toolbar = document.createElement("div");
  toolbar.className = "cm-markdown-table-toolbar";
  toolbar.setAttribute("role", "toolbar");
  toolbar.setAttribute("aria-label", "Table actions");

  const addButton = (
    label: string,
    disabled: boolean,
    disabledReason: string,
    onClick: () => void,
  ) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "cm-markdown-table-action";
    button.textContent = `+ ${label}`;
    button.disabled = disabled || readOnly;
    button.title = disabled ? disabledReason : `Add ${label.toLowerCase()}`;
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      onClick();
    });
    toolbar.appendChild(button);
  };

  addButton(
    "Row",
    data.rows.length >= MAX_TABLE_ROWS,
    `Maximum of ${MAX_TABLE_ROWS} body rows reached`,
    () => {
      const table = wrapper.querySelector<HTMLTableElement>("table");
      if (!table) return;
      const current = dataFromTable(table, data.alignments);
      const next = appendMarkdownTableRow(current);
      if (next) {
        replaceTable(wrapper, view, next, data.headers.length + data.rows.length * data.headers.length);
      }
    },
  );
  addButton(
    "Column",
    data.headers.length >= MAX_TABLE_COLUMNS,
    `Maximum of ${MAX_TABLE_COLUMNS} columns reached`,
    () => {
      const table = wrapper.querySelector<HTMLTableElement>("table");
      if (!table) return;
      const current = dataFromTable(table, data.alignments);
      const next = appendMarkdownTableColumn(current);
      if (next) replaceTable(wrapper, view, next, data.headers.length);
    },
  );
  return toolbar;
}

function installTableInteractions(
  wrapper: HTMLDivElement,
  view: EditorView,
  markdownAware: boolean,
) {
  const table = wrapper.querySelector<HTMLTableElement>("table");
  if (!table) return;

  let selectionAnchor: number | null = null;
  let selectionFocus: number | null = null;
  let activePointerId: number | null = null;
  let draggedAcrossCells = false;
  let suppressNextClick = false;

  const columns = () => table.tHead?.rows[0]?.cells.length ?? 1;
  const clearNativeSelection = () => window.getSelection()?.removeAllRanges();
  const renderCellSelection = () => {
    const columnCount = columns();
    const range =
      selectionAnchor == null || selectionFocus == null
        ? null
        : tableCellRange(selectionAnchor, selectionFocus, columnCount);
    const selected = new Set(
      selectionAnchor == null || selectionFocus == null
        ? []
        : tableCellRangeIndices(selectionAnchor, selectionFocus, columnCount),
    );
    tableCells(table).forEach((cell, index) => {
      const isSelected = selected.has(index);
      const row = Math.floor(index / columnCount);
      const column = index % columnCount;
      cell.classList.toggle("cm-markdown-table-cell-selected", isSelected);
      cell.classList.toggle(
        "cm-markdown-table-selection-top",
        isSelected && row === range?.top,
      );
      cell.classList.toggle(
        "cm-markdown-table-selection-right",
        isSelected && column === range?.right,
      );
      cell.classList.toggle(
        "cm-markdown-table-selection-bottom",
        isSelected && row === range?.bottom,
      );
      cell.classList.toggle(
        "cm-markdown-table-selection-left",
        isSelected && column === range?.left,
      );
      if (isSelected) cell.setAttribute("aria-selected", "true");
      else cell.removeAttribute("aria-selected");
    });
  };
  const clearCellSelection = () => {
    selectionAnchor = null;
    selectionFocus = null;
    renderCellSelection();
  };
  const cellAtPoint = (clientX: number, clientY: number) =>
    document
      .elementFromPoint(clientX, clientY)
      ?.closest<HTMLTableCellElement>(".cm-markdown-table th, .cm-markdown-table td") ??
    null;
  const focusWithoutTextSelection = (cell: HTMLTableCellElement) => {
    if (cell.tabIndex >= 0) cell.focus({ preventScroll: true });
    else wrapper.focus({ preventScroll: true });
    clearNativeSelection();
  };

  wrapper.addEventListener("dblclick", (event) => {
    if (
      view.state.readOnly ||
      !markdownAware
    ) {
      return;
    }
    const sourceFrom = Number(wrapper.dataset.sourceFrom);
    const sourceTo = Number(wrapper.dataset.sourceTo);
    if (!Number.isFinite(sourceFrom) || !Number.isFinite(sourceTo)) return;
    event.preventDefault();
    event.stopPropagation();
    view.dispatch({
      selection: EditorSelection.cursor(Math.min(sourceTo, sourceFrom + 1)),
      scrollIntoView: true,
    });
    view.focus();
  });

  wrapper.addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || !(event.target instanceof HTMLTableCellElement)) return;
    const cells = tableCells(table);
    const index = cells.indexOf(event.target);
    if (index < 0) return;

    if (event.shiftKey && selectionAnchor != null) {
      event.preventDefault();
      selectionFocus = index;
      suppressNextClick = true;
      renderCellSelection();
      focusWithoutTextSelection(event.target);
      return;
    }

    clearCellSelection();
    selectionAnchor = index;
    selectionFocus = index;
    activePointerId = event.pointerId;
    draggedAcrossCells = false;
  });

  wrapper.addEventListener("pointermove", (event) => {
    if (activePointerId !== event.pointerId || !(event.buttons & 1)) return;
    const cell = cellAtPoint(event.clientX, event.clientY);
    if (!cell || !table.contains(cell)) return;
    const index = tableCells(table).indexOf(cell);
    if (index < 0 || index === selectionFocus) return;
    event.preventDefault();
    if (!wrapper.hasPointerCapture(event.pointerId)) {
      wrapper.setPointerCapture(event.pointerId);
    }
    selectionFocus = index;
    draggedAcrossCells = selectionFocus !== selectionAnchor;
    renderCellSelection();
    clearNativeSelection();
  });

  const finishPointerSelection = (event: PointerEvent) => {
    if (activePointerId !== event.pointerId) return;
    if (wrapper.hasPointerCapture(event.pointerId)) {
      wrapper.releasePointerCapture(event.pointerId);
    }
    activePointerId = null;
    if (!draggedAcrossCells) {
      // Keep the last clicked cell as the Shift-click anchor without styling it
      // as a range or overriding ordinary single-cell text selection.
      selectionFocus = null;
      renderCellSelection();
      return;
    }
    event.preventDefault();
    suppressNextClick = true;
    const cells = tableCells(table);
    const focusCellIndex = selectionFocus ?? -1;
    if (cells[focusCellIndex]) focusWithoutTextSelection(cells[focusCellIndex]);
  };
  wrapper.addEventListener("pointerup", finishPointerSelection);
  wrapper.addEventListener("pointercancel", finishPointerSelection);

  wrapper.addEventListener("click", (event) => {
    if (!suppressNextClick) return;
    event.preventDefault();
    event.stopPropagation();
    suppressNextClick = false;
  });

  wrapper.addEventListener("copy", (event) => {
    if (
      selectionAnchor == null ||
      selectionFocus == null ||
      selectionAnchor === selectionFocus ||
      !event.clipboardData
    ) {
      return;
    }
    const values = tableCells(table).map((cell) => cell.textContent ?? "");
    event.clipboardData.setData(
      "text/plain",
      serializeTableCellRange(values, selectionAnchor, selectionFocus, columns()),
    );
    event.clipboardData.setData(
      "text/html",
      tableCellRangeHtml(values, selectionAnchor, selectionFocus, columns()),
    );
    event.preventDefault();
  });

  wrapper.addEventListener("input", (event) => {
    if (!(event.target instanceof HTMLTableCellElement)) return;
    const from = Number(wrapper.dataset.sourceFrom);
    const to = Number(wrapper.dataset.sourceTo);
    const alignments = JSON.parse(
      wrapper.dataset.alignments ?? "[]",
    ) as TableAlignment[];
    const markdown = serializeMarkdownTable(dataFromTable(table, alignments));
    if (!Number.isFinite(from) || !Number.isFinite(to)) return;
    if (view.state.sliceDoc(from, to) === markdown) return;
    view.dispatch({
      changes: { from, to, insert: markdown },
      userEvent: "input.type",
    });
  });

  wrapper.addEventListener("keydown", (event) => {
    if (!(event.target instanceof HTMLTableCellElement)) return;
    const cells = tableCells(table);
    const index = cells.indexOf(event.target);
    if (index < 0) return;
    const columnCount = columns();
    let nextIndex: number | null = null;

    if (event.key === "Tab") {
      if (!event.shiftKey && index === cells.length - 1) {
        const alignments = JSON.parse(
          wrapper.dataset.alignments ?? "[]",
        ) as TableAlignment[];
        const next = appendMarkdownTableRow(dataFromTable(table, alignments));
        if (next) {
          event.preventDefault();
          replaceTable(wrapper, view, next, cells.length);
        }
        return;
      }
      nextIndex = (index + (event.shiftKey ? -1 : 1) + cells.length) % cells.length;
    } else if (event.key === "Enter") {
      if (index + columnCount >= cells.length) {
        const alignments = JSON.parse(
          wrapper.dataset.alignments ?? "[]",
        ) as TableAlignment[];
        const next = appendMarkdownTableRow(dataFromTable(table, alignments));
        if (next) {
          event.preventDefault();
          replaceTable(wrapper, view, next, index + columnCount);
        } else {
          // Table cells are deliberately single-line. At the row limit, keep
          // Enter from inserting a browser-generated line break into the cell.
          event.preventDefault();
        }
        return;
      }
      nextIndex = index + columnCount;
    } else if (event.key === "ArrowUp" && index >= columnCount) {
      nextIndex = index - columnCount;
    } else if (event.key === "ArrowDown" && index + columnCount < cells.length) {
      nextIndex = index + columnCount;
    } else if (event.key === "ArrowLeft" && caretOffset(event.target) === 0 && index > 0) {
      nextIndex = index - 1;
    } else if (
      event.key === "ArrowRight" &&
      caretOffset(event.target) === (event.target.textContent?.length ?? 0) &&
      index + 1 < cells.length
    ) {
      nextIndex = index + 1;
    } else if (event.key === "Escape") {
      if (selectionAnchor != null && selectionFocus != null) {
        event.preventDefault();
        clearCellSelection();
        return;
      }
      event.preventDefault();
      const sourceTo = Number(wrapper.dataset.sourceTo);
      view.dispatch({
        selection: EditorSelection.cursor(
          Math.min(view.state.doc.length, sourceTo + 1),
        ),
      });
      view.focus();
      return;
    }

    if (nextIndex == null || nextIndex === index) return;
    event.preventDefault();
    clearCellSelection();
    focusCell(cells[nextIndex]);
  });
}

export class MarkdownTableWidget extends WidgetType {
  constructor(
    private readonly markdown: string,
    private readonly sourcePosition: number,
    private readonly readOnly: boolean,
    private readonly markdownAware: boolean,
  ) {
    super();
  }

  override eq(other: MarkdownTableWidget): boolean {
    return (
      other.markdown === this.markdown &&
      other.sourcePosition === this.sourcePosition &&
      other.readOnly === this.readOnly &&
      other.markdownAware === this.markdownAware
    );
  }

  override toDOM(view: EditorView): HTMLElement {
    const wrapper = document.createElement("div");
    wrapper.className = "cm-markdown-table-wrapper";
    wrapper.tabIndex = -1;
    wrapper.dataset.sourceFrom = String(this.sourcePosition);
    wrapper.dataset.sourceTo = String(this.sourcePosition + this.markdown.length);

    const data = parseMarkdownTable(this.markdown);
    if (!data) return wrapper;
    wrapper.dataset.alignments = JSON.stringify(data.alignments);
    wrapper.dataset.readOnly = String(this.readOnly);

    const table = document.createElement("table");
    table.className = "cm-markdown-table";
    table.setAttribute("aria-label", "Markdown table");

    const head = table.createTHead();
    const headerRow = head.insertRow();
    data.headers.forEach((header, index) => {
      const cell = document.createElement("th");
      cell.scope = "col";
      cell.textContent = header;
      configureCell(cell, data.alignments[index], this.readOnly);
      headerRow.appendChild(cell);
    });

    const body = table.createTBody();
    data.rows.forEach((row) => {
      const tableRow = body.insertRow();
      row.forEach((value, index) => {
        const cell = tableRow.insertCell();
        cell.textContent = value;
        configureCell(cell, data.alignments[index], this.readOnly);
      });
    });

    const scrollArea = document.createElement("div");
    scrollArea.className = "cm-markdown-table-scroll";
    scrollArea.appendChild(table);
    const card = document.createElement("div");
    card.className = "cm-markdown-table-card";
    card.appendChild(scrollArea);
    card.appendChild(createTableToolbar(wrapper, view, data, this.readOnly));
    wrapper.appendChild(card);
    installTableInteractions(wrapper, view, this.markdownAware);
    return wrapper;
  }

  override updateDOM(
    dom: HTMLElement,
    view: EditorView,
    from: this,
  ): boolean {
    if (
      from.readOnly !== this.readOnly ||
      from.markdownAware !== this.markdownAware
    ) {
      return false;
    }
    const wrapper = dom as HTMLDivElement;
    const table = wrapper.querySelector<HTMLTableElement>("table");
    const data = parseMarkdownTable(this.markdown);
    if (!table || !data) return false;
    const cells = tableCells(table);
    const values = [...data.headers, ...data.rows.flat()];
    if (cells.length !== values.length) return false;

    wrapper.dataset.sourceFrom = String(this.sourcePosition);
    wrapper.dataset.sourceTo = String(this.sourcePosition + this.markdown.length);
    wrapper.dataset.alignments = JSON.stringify(data.alignments);
    cells.forEach((cell, index) => {
      if (document.activeElement !== cell && cell.textContent !== values[index]) {
        cell.textContent = values[index];
      }
      configureCell(
        cell,
        data.alignments[index % data.headers.length],
        view.state.readOnly,
      );
    });
    return true;
  }
}

export function tableDecoration(
  markdown: string,
  sourcePosition: number,
  readOnly: boolean,
  markdownAware: boolean,
) {
  return Decoration.replace({
    widget: new MarkdownTableWidget(
      markdown,
      sourcePosition,
      readOnly,
      markdownAware,
    ),
    block: true,
  });
}

const MIN_ROWS = 1;

function clampSize(value: number, minimum: number, maximum: number): number {
  if (!Number.isFinite(value)) return minimum;
  return Math.min(maximum, Math.max(minimum, Math.round(value)));
}

/** Builds a GFM table with named headers and the requested number of body rows. */
export function createMarkdownTable(columnCount: number, rowCount: number): string {
  const columns = clampSize(columnCount, 1, MAX_TABLE_COLUMNS);
  const rows = clampSize(rowCount, MIN_ROWS, MAX_TABLE_ROWS);
  const headers = Array.from(
    { length: columns },
    (_, index) => `Column ${index + 1}`,
  );
  const bodyRow = `| ${Array(columns).fill(" ").join(" | ")} |`;

  return [
    `| ${headers.join(" | ")} |`,
    `| ${headers.map((header) => "-".repeat(Math.max(3, header.length))).join(" | ")} |`,
    ...Array(rows).fill(bodyRow),
  ].join("\n");
}

/** Inserts a table and leaves the text caret on an editable line below it. */
export function insertMarkdownTable(
  view: EditorView,
  columnCount = 3,
  rowCount = 2,
): boolean {
  if (view.state.readOnly) return false;

  const { from, to } = view.state.selection.main;
  const before = view.state.sliceDoc(0, from);
  const after = view.state.sliceDoc(to);
  const leadingBreak = before.length > 0 && !before.endsWith("\n") ? "\n" : "";
  const table = createMarkdownTable(columnCount, rowCount);
  // A GFM table can absorb the next non-pipe line as a body row, so a true
  // blank-line boundary is required before placing the text caret below it.
  const trailingBreak =
    after.length === 0 || after.startsWith("\n") ? "\n\n" : "\n\n\n";
  const insert = `${leadingBreak}${table}${trailingBreak}`;
  const textLineStart = from + leadingBreak.length + table.length + 2;

  view.dispatch({
    changes: { from, to, insert },
    selection: EditorSelection.cursor(textLineStart),
    scrollIntoView: true,
  });
  view.focus();
  return true;
}
