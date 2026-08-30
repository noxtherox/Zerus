# Property visibility control design QA

- Source visual truth: `/Users/tiagopereira/.t3/userdata/attachments/e9a27a41-ef37-457a-89fa-4190bf006962-e0b0bd34-e7b0-4925-a060-3328bf23a4b8.png`
- Implementation screenshot: `/Users/tiagopereira/Documents/Codex/Zerus-remote/artifacts/design-qa/property-visibility-implementation.png`
- Focused implementation crop: `/Users/tiagopereira/Documents/Codex/Zerus-remote/artifacts/design-qa/property-visibility-focused.png`
- Route: `https://mac-mini-m4-nox.ibex-oratrice.ts.net/app`
- State: dark theme, `inbox` type selected, Sort & filter open, all property visibility controls unselected
- Viewport: 1280 × 800 CSS px at device scale factor 1
- Source pixels: 418 × 612
- Implementation pixels: 1280 × 800; focused crop: 340 × 500
- Density normalization: both captures were inspected at native 1× density. The focused crop isolates the same Sort & filter region as the source; exact outer crop sizes differ because the source is a partial screenshot.

## Full-view comparison evidence

The implementation preserves the desktop three-column workspace and opens the Sort & filter panel from the note-list toolbar. The panel remains within the note-list column without clipping or covering persistent controls.

## Focused comparison evidence

The source and focused implementation capture were opened together. Typography, dark tokens, separators, field heights, corner radii, dropdown styling, and vertical rhythm remain consistent with the source. The intended difference is present on every property row: the existing property label is followed by an eye-off control, followed by the unchanged filter dropdown. The demo contains three properties instead of the longer source list, which is expected data variation rather than design drift.

## Required fidelity surfaces

- Fonts and typography: existing app font family, weights, sizes, line heights, and truncation are unchanged and match the reference hierarchy.
- Spacing and layout rhythm: property rows retain their height and dropdown width; the label, 28 px eye control, and dropdown are aligned in a stable three-column grid.
- Colors and visual tokens: existing background, border, muted foreground, focus, and accent tokens are reused.
- Image quality and asset fidelity: no raster imagery is involved. The eye states use the app's existing Tabler icon library and render sharply.
- Copy and content: property names and “Don’t filter” copy are unchanged. Accessible labels switch between “Show … property” and “Hide … property.”

## Primary interactions tested

- Opened Sort & filter for the `inbox` type.
- Confirmed all three controls render in label → eye → dropdown order using browser geometry.
- Turned Owner, Priority, and Status visibility off through the UI.
- Reloaded the application, reopened `inbox` and Sort & filter, and confirmed all three remained unselected.
- Confirmed no property pills render while all controls are unselected.
- Browser snapshot reported no console-error diagnostics.

## Findings

No actionable P0, P1, or P2 differences remain.

## Comparison history

- Initial implementation check: the demo retained the prior session's three selected property controls. This was expected persistence, not a code default failure.
- Action: cleared all three controls through the UI and reloaded the application.
- Post-fix evidence: Owner, Priority, and Status each report `aria-pressed="false"` with “Show … property” labels, and no pills are rendered.

## Follow-up polish

No P3 follow-ups identified for this scoped change.

final result: passed
