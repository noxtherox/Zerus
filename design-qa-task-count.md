# Design QA — Tasks sidebar count

- Source visual truth: `/Users/tiagopereira/.codex/attachments/c355f6ee-0fd9-45d0-8d5d-b81d287db879/codex-clipboard-a228cb66-9669-4ac5-af89-c062c1f7d528.png`
- Browser-rendered implementation: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/design-qa-task-count-full.jpg`
- Focused implementation crop: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/design-qa-task-count-implementation.png`
- Side-by-side focused comparison: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/design-qa-task-count-comparison.png`
- Viewport: 1227 × 720 CSS px in the Codex in-app browser.
- Pixels and density: source crop 343 × 248; implementation full view 1227 × 720; focused implementation crop 342 × 248 because the browser JPEG's 4:2:0 chroma alignment trims the requested odd width by one pixel. Device scale factor 1; no density rescaling.
- State: Zerus dark theme, All Notes selected, browser demo vault with four notes and one task.

## Full-view comparison evidence

The full browser capture shows the new task total in the expanded navigation sidebar, aligned to the same right edge as the All Notes and Trash totals. The Tasks row remains clickable and the count remains visible in both inactive and active states. The browser demo omits desktop-only External Notes, Files, and Links rows, so those source-only rows were excluded from fidelity judgment.

## Focused region comparison evidence

The equal-height side-by-side comparison keeps the relevant top navigation region legible. The implementation adds the requested `1` to the Tasks row using the same size, muted color, tabular numerals, vertical alignment, and right-aligned placement as the existing All Notes total. The one-pixel crop-width difference is outside the task row and does not affect alignment judgment.

## Required fidelity surfaces

- Fonts and typography: the task total inherits the existing sidebar count treatment (`text-xs` and tabular numerals), matching note totals without introducing a new font, weight, line height, or wrapping behavior.
- Spacing and layout rhythm: row height, icon-label gap, horizontal padding, rounded active surface, and count alignment are unchanged. The new total occupies the existing optional count slot.
- Colors and visual tokens: the total uses the established muted sidebar foreground opacity and remains legible in the verified dark theme.
- Image quality and asset fidelity: no new image assets were introduced. Existing logo and library icons remain unchanged.
- Copy and content: all labels are unchanged; the only intentional addition is the live numeric total on Tasks.

## Findings

No actionable P0, P1, or P2 issues.

## Primary interactions and console

- Confirmed the sidebar exposes `Tasks 1` as one accessible button.
- Opened Tasks and confirmed the button's active state while the count remained visible.
- Confirmed the All Tasks view showed the same single task represented by the sidebar total.
- Browser console warnings/errors: none.

## Comparison history

- Initial comparison: no P0/P1/P2 mismatch was found. The source's absent Tasks number is the explicit requested change; the implementation's added total matches the existing note-count visual treatment.

## Follow-up polish

- P3: the browser capture retains a transient focus outline on All Notes after interaction; this is an accessibility state, not a persistent design mismatch.

final result: passed
