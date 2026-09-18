# Design QA — inline gallery selection toolbar

- Source visual truth: `/Users/tiagopereira/.codex/attachments/7027ae27-57dc-4aec-b6a4-f98e11434add/codex-clipboard-c72f4eb2-6011-45af-a77c-b1ed6b760daf.png`
- Browser implementation capture: `/Users/tiagopereira/Documents/Codex/Zerus-remote/artifacts/selection-toolbar-inline-implementation.png`
- Preview URL: `https://mac-mini-m4-nox.ibex-oratrice.ts.net/app`
- Viewport: 1280 × 720 CSS px at device scale factor 2
- Source pixels: 1616 × 217; supplied crop includes browser chrome and the relevant app toolbar region
- Implementation pixels: 2560 × 1440; browser-rendered full viewport
- State: dark theme, work type, Gallery view, No grouping, Select mode active, three notes selected

## Full-view comparison evidence

The supplied source shows the view toolbar followed by a separate selection row, which pushes the gallery downward. The browser capture shows the intended revised composition: Auto-saved, the selected count, Actions, and clear selection all share the existing Gallery/Group by toolbar. The gallery begins at the same vertical position in selection and non-selection states.

## Focused comparison evidence

A separate crop was not needed because the toolbar labels, borders, selected cards, and row boundaries are clearly readable in both the source crop and the full-size implementation capture. The implementation preserves the source control order and styling while moving the selection controls into the highlighted toolbar region.

## Required fidelity surfaces

- Fonts and typography: the existing application font, weights, sizes, line heights, and compact control labels are unchanged.
- Spacing and layout rhythm: the extra 44px selection row is removed; the existing toolbar height and gallery start position remain stable when selection begins or ends.
- Colors and visual tokens: existing surface, border, muted text, emerald auto-save, and accent selection tokens are preserved.
- Image quality and asset fidelity: no new raster or generated assets are used; the existing icon set remains unchanged and sharp.
- Copy and content: selected count, Actions, Auto-saved, Gallery, Group by, and No grouping remain visible and unchanged.

## Interaction verification

- Entered Select mode and selected three gallery notes.
- Confirmed the selected count updates in-place without adding a row.
- Opened Actions and verified Select all, Archive, Unarchive, Pin, Unpin, Properties, and Recent actions are available.
- Pressed Escape and confirmed selection clears and the inline controls disappear without shifting the gallery.
- Browser console errors: none.
- Frontend `/app`: HTTP 200.
- Tailscale Serve `/app`: HTTP 200.

## Findings

No actionable P0, P1, or P2 differences remain for the requested change.

## Comparison history

- Source issue: selection status and actions occupy a conditional row below the view toolbar, shifting the gallery vertically.
- Fix: added an inline presentation for the shared bulk-actions toolbar and mounted it inside the type-view toolbar.
- Post-fix evidence: the browser capture shows three selected cards while all selection controls remain in the existing toolbar; the gallery does not move.

## Follow-up polish

No required P3 follow-up.

final result: passed
