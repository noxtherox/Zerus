# Design QA — compact bulk actions

- Source visual truth: `/Users/tiagopereira/.codex/attachments/7df0fb99-88e8-4b34-9d33-aaf494b396df/codex-clipboard-ddc59679-983f-4ef4-9958-20061ce3667c.png`
- Browser implementation capture: `/Users/tiagopereira/Documents/Codex/Zerus-remote/artifacts/bulk-actions-menu-implementation.jpg`
- Combined comparison: `/Users/tiagopereira/Documents/Codex/Zerus-remote/artifacts/bulk-actions-visual-comparison.png`
- Viewport: 1280 × 720 CSS px, device scale factor 1
- Source pixels: 739 × 129 at 1×
- Implementation pixels: 1280 × 720 at 1×; focused note-list crop is 240 × 345
- State: dark theme, All Notes regular list, Select mode active, one note selected, Actions menu open

## Full-view comparison evidence

The browser capture verifies the requested layout in the real application shell. At the normal narrow note-list width, the selection toolbar stays on one line with the selected count, Actions trigger, and clear control all visible. The list and search/filter controls remain usable below it.

## Focused comparison evidence

The combined comparison shows the supplied before-state above the focused implementation crop. The former row of seven independent controls is replaced by one compact Actions trigger. Its menu contains Select all, Archive, Unarchive, Pin, Unpin, Properties, and Recent actions. The Select button uses the existing theme accent for its border, fill, text, and ring only while selection mode is active.

## Required fidelity surfaces

- Fonts and typography: existing app font, weights, sizes, and compact labels are preserved.
- Spacing and layout rhythm: toolbar height and horizontal padding remain aligned with the list header; no horizontal overflow or clipped control is visible.
- Colors and visual tokens: the Select and Actions controls use `zerus-accent` opacity variants and therefore track the active theme.
- Image quality and asset fidelity: no raster assets were introduced into the UI; existing Tabler icons remain sharp and consistent.
- Copy and content: all prior bulk-action labels are retained under Actions, with “Recent bulk actions” shortened to “Recent actions” in the menu.

## Interaction verification

- Select mode toggles on and displays its accent-highlighted active state.
- Selecting a note reveals the compact toolbar.
- Actions opens and exposes every grouped command.
- Archive opens the existing one-note confirmation dialog; Cancel closes it without mutating data.
- Browser console errors and warnings: none.
- Frontend `/app`: HTTP 200.
- Tailscale Serve `/app`: HTTP 200.

## Findings

No actionable P0, P1, or P2 issues remain.

## Comparison history

- Initial supplied state: individual bulk-action buttons overflow the practical width of the regular notes list, and Select has weak visual separation.
- Fix: consolidated commands into an Actions dropdown and added active-only theme-accent styling to Select in the regular list and type workspace.
- Post-fix evidence: combined comparison and browser interaction checks above show the compact toolbar and complete menu at the real narrow width.

## Follow-up polish

No required P3 follow-up.

final result: passed
