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
