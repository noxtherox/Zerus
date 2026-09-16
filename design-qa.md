# Saved Views Design QA

- Source visual truth: `/Users/tiagopereira/.codex/generated_images/01a0967c-83a7-76f1-bdd9-447bea675157/exec-fd961c82-b6ce-474d-98f6-71b6690b3936.png`
- Implementation: `http://127.0.0.1:8080/app`
- Implementation screenshot path: unavailable; the implementation was captured and inspected in the Codex in-app browser, but that capture was not exposed as a filesystem artifact.
- Source pixels: 1404 × 1120.
- Implementation capture: 1280 × 720 browser viewport at device scale factor 1.
- Density normalization: visual regions were inspected at their native browser/source scales; no persisted image pair was available for normalized compositing.
- State: dark theme, `work` type, Gallery mode, View dropdown open, one active saved view named `Active epics`.

## Full-view comparison evidence

The source and implementation were each opened and inspected. The implementation preserves the existing Zerus dropdown structure, places `SAVED VIEWS` after the five layout rows, aligns a compact plus action to the section heading, uses a bookmark icon for the saved row, and shows the purple active check. The menu remains compact and retains `Hide subfolder notes` and `Saved for this type` below the new section.

The required combined source/implementation comparison could not be completed. The Codex in-app browser rejected the comparison document under its URL security policy and explicitly prohibited alternate-browser or indirect workarounds.

## Focused region comparison evidence

The View dropdown was inspected at readable scale in both images. Typography, spacing, icon sizing, dividers, palette, and copy are directionally faithful, but a single combined comparison artifact could not be produced, so precise overlay-level verification is unavailable.

## Required fidelity surfaces

- Fonts and typography: existing Zerus type tokens and menu sizes are reused; section label casing, tracking, row weights, truncation, and hierarchy visually align with the source.
- Spacing and layout rhythm: the implementation uses the existing menu row rhythm with a 256 px dropdown, compact saved-view header, lightweight divider, and 40 px saved-view row.
- Colors and visual tokens: existing popover, muted foreground, accent, ring, border, and emerald status tokens are reused; no new hard-coded palette was introduced.
- Image quality and asset fidelity: no raster assets are required by this component. Icons come from Zerus's existing Tabler icon adapter; no handcrafted SVG, CSS art, or placeholders were added.
- Copy and content: `Saved views`, `Save current view`, saved-view names, empty guidance, and the naming-dialog explanation match the intended feature semantics.

## Functional verification

- Opened the View dropdown and verified the empty saved-view state.
- Opened the save dialog from the plus button.
- Verified the save action is disabled for an empty name.
- Saved `Active epics` and verified it appeared with an active check.
- Changed from Gallery to Kanban, reopened the menu, and verified the preset was no longer marked active.
- Selected `Active epics` and verified Gallery mode was restored.
- Reloaded the app and verified `Active epics` remained available and active.
- Checked browser console warning/error logs: none.
- Frontend route: HTTP 200.
- Tailscale Serve `/app` route: HTTP 200.

## Findings

- No P0, P1, or P2 functional or separately visible UI issues were found.
- Blocking verification gap: the required combined visual comparison artifact is unavailable because the selected browser blocked the comparison surface.

## Comparison history

- Initial implementation: no actionable P0/P1/P2 issues found during separate source and implementation inspection.
- No visual fixes were required before the blocked combined-comparison step.

## Implementation checklist

- [x] Preserve existing layout switching and per-type auto-save.
- [x] Add an inline Saved views section and compact plus action.
- [x] Add naming, validation, persistence, active-state matching, and restore behavior.
- [x] Verify primary interactions and browser console.
- [ ] Complete a combined source/implementation comparison when the in-app browser permits the comparison surface.

## Follow-up polish

- P3: consider a small management affordance for renaming or deleting saved views in a later iteration.

final result: blocked

## Linked note preview and Link dialog — 2026-09-15

Scope: compact linked-note preview and Vault note / Web URL picker only. This review does not change the earlier Saved Views verdict.

Source: `/Users/tiagopereira/.codex/generated_images/01a0a054-9aa3-7811-99ee-0023452c6b2e/exec-c84b3bd0-5e87-4ebe-abdc-50a5e8e43ef2.png`, with the user's requested centering beneath the clicked link.

Compared source and implementation together in one browser tool output. The source is an enlarged mock; the implementation uses actual editor density at 1280 × 720, sample vault content, and the existing theme. Comparison is scoped to the popover: document icon, compact title/action row, one-line excerpt, restrained border, and centered placement. The source's surrounding invented navigation is outside scope. No P0/P1/P2 visual differences remain. Edit/copy/remove controls remain available on hover or keyboard focus and on touch devices.

Browser checks passed: clicking a note link preserves the current note; Open note navigates; vault search finds a destination; selected words survive insertion; Web URL insertion uses the display label; last-used Web URL persists after reload; editing an existing note link selects Vault note; Escape and outside-click dismissal work. A double-cancel error and a missing Lexical editor context in the click handler were fixed and retested on a freshly loaded page, with no new console errors.

Validation: 19 focused tests, TypeScript, targeted ESLint, and frontend production build with bundle verification passed. Both frontend and private Serve `/app` routes returned HTTP 200. Desktop native and iOS device behavior were not exercised.

Linked-note scope final result: passed.

## Type-view filter pill placement — 2026-09-16

- Source visual truth: `/Users/tiagopereira/.codex/attachments/768b02ec-dbb5-4703-ad92-2ab9a59c2d80/codex-clipboard-01b5d2e2-4da8-4a76-8b56-77b6b89c3ab4.png` (697 × 921 px).
- Implementation: `https://mac-mini-m4-nox.ibex-oratrice.ts.net/app`.
- Implementation screenshot: captured and inspected inline in the Codex in-app browser; the browser did not expose a filesystem path for the capture.
- Viewport: 1280 × 720 CSS px at device scale factor 2; the browser capture was normalized to the visible 1280 × 720 viewport.
- State: dark theme, `work` type, Kanban view, `Updated: Last 30 days` active, Sort & filter popover open.

### Comparison evidence

The focused toolbar region was compared against the annotated source. The active pill now precedes `Search this view…`, followed by the fixed-width `Sort & filter` control. Browser measurements confirmed the pill at x=665 px, search at x=834 px, and sort at x=1049 px. Removing and restoring the filter left the sort control at the same x position and 132 px width.

A separate full-view comparison was not needed because the requested change is limited to toolbar child order and control stability; the surrounding type view remains unchanged.

### Required fidelity surfaces

- Fonts and typography: existing Zerus pill, input, and button typography is unchanged.
- Spacing and layout rhythm: the pill uses the existing 8 px toolbar gap and sits immediately left of search; the sort control no longer shifts between inactive and active states.
- Colors and visual tokens: existing secondary badge, surface, border, muted text, and accent tokens are reused.
- Image quality and asset fidelity: no image assets were added or changed; existing library icons are preserved.
- Copy and content: filter labels, search placeholder, sort label, badge count, and remove-button accessible label are unchanged.

### Functional verification

- Added and removed the Last 30 days filter in the rendered app.
- Confirmed the pill appears to the left of search.
- Confirmed the sort control remains at the same measured position and width with and without an active filter.
- Confirmed the filter popover, clear action, and removable pill remain operable.
- Browser console warnings/errors: none.
- Frontend `/app`: HTTP 200.
- Tailscale Serve `/app`: HTTP 200.
- TypeScript, ESLint, and all 553 tests passed.

### Findings

- No actionable P0, P1, or P2 differences remain in the requested toolbar region.

### Comparison history

- Initial pass: pill order matched the request, but the sort button shifted by 2 px when its active variant appeared.
- Fix: assigned the sort trigger a stable 132 px width while preserving the full-width sidebar override.
- Post-fix evidence: inactive and active sort-trigger measurements both reported x=1048.664 px and width=132 px.

final result: passed
