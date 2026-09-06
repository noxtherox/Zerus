# Tables in Zerus

Tables remain standard GFM Markdown. The integration uses MDXEditor's public realm plugin, import/export visitors, and Lexical composer APIs. There is no note migration or separate table database.

## Editing

- Insert table lets you choose 2–20 rows (including the header) and 1–12 columns.
- Select a cell to show Table actions: insert/delete rows and columns, align a column, or delete the table. On narrow screens these actions appear in a bottom panel.
- Tab and Shift+Tab navigate cells. Enter moves to the same column in the next row, adding a row at the end. Escape closes an expanded table or exits an inline table.
- Expand table keeps the existing editor and selection. Closing restores the note's scroll position.
- The first row is always the Markdown header. Merged cells and custom cell backgrounds are disabled. Column widths are presentation only and are not saved in Markdown.
- Spreadsheet TSV paste supports rectangular ranges, empty cells, quoted tabs, and escaped quotes. Multiline spreadsheet cells become single-line text separated by spaces, matching GFM's inline cell model.

## Large tables

Tables above 500 cells or 50,000 characters of text use a compact block. These are provisional, conservative thresholds shared by desktop and mobile, not measured iPhone limits. Markdown import chooses this representation before creating editable cell nodes. Native tables that grow past the limit are converted during Lexical transforms. Large TSV paste merges into the existing table data before mounting cells.

Open table shows at most 20 data rows and eight columns, plus a repeating header: at most 168 cells. Both dimensions have pagination. Select a cell to edit its inline Markdown, or view its complete source in read-only mode. Long preview text is shortened at 4,000 characters; the stored cell is complete. Images appear as labels in this view to avoid loading hundreds of image resources.

Edits, structural changes, and deletion participate in the note's undo/redo history. Editing surrounding text exports the complete table, including rows that were never opened. Copy Markdown copies the complete table. Native clipboard HTML uses one preformatted Markdown block for an oversized table rather than constructing thousands of HTML cells.

Markdown column padding is disabled, so one long cell does not multiply whitespace across every row. The full Markdown parse and serialization still run for the note; pagination bounds the editor/DOM work, not the total size of a note in memory.

If Markdown processing or a React editor error occurs, the note opens in a source recovery textarea with Retry formatted editor. This cannot catch an iOS WebView process termination.

## Verification

Run `pnpm exec vitest run src/components/editor`, `pnpm typecheck`, and `pnpm build`. The frontend build is a verification step, not an iOS or desktop package build.

With `pnpm dev`, open `/scripts/table-smoke.html` for a development-only harness with small and 10,000-cell fixtures, save/reload, read-only, recovery, and theme controls. It is not a production entry point.

Browser checks performed on 2026-09-06:

- Desktop table rendering, rich inline content, row insertion, and column alignment export.
- A 390-pixel viewport stays 390 pixels wide while the table scrolls internally.
- Opening 10,000 cells mounts one compact block; its viewer mounts 168 cells.
- Large-cell editing, undo, redo, and Markdown reload retain the final cell.
- A 10,000-cell TSV paste into a small table preserves untouched cells and following text. One desktop browser run took approximately 50 ms through the next paint; this is not an iPhone measurement.
- Growing a 500-cell inline table by one row converts it to the compact representation without losing the last cell.
- Row/column pagination, expanded mode, source recovery, and read-only inspection.

Before calling the reported mobile crash resolved, validate the user's failing note on a physical iPhone. Profile memory and input latency while opening, scrolling, typing, opening the keyboard, pasting, and repeatedly switching notes. Also check long links/images and multiple tables in one note. The current browser checks do not establish an iPhone memory ceiling or prove the absence of a WebView termination.

## Native simulator follow-up (2026-09-06)

Built and launched the native development app on the iPhone 17 Pro simulator running iOS 26.5. Used a new local simulator vault with a synthetic 1,000-row × 10-column note. The note opened without a crash; editing its first data cell saved to the actual Markdown file, with the final cell and following paragraph intact. Simulator Safari also opened and edited the 10,000-cell harness.

This check exposed two native layout issues, now corrected: the table dialog overlapped the status bar, and the software keyboard could cover the cell input. The dialog now respects safe-area insets and VisualViewport height/offset. On narrow screens, selecting a cell temporarily replaces the grid with the focused cell form; the input and Save button stay visible above the keyboard.

These simulator checks supplement the browser tests; physical iPhone memory profiling remains outstanding.
