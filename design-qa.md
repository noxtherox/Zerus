# Design QA: relation add-link action

- Source visual truth: `/Users/tiagopereira/.codex/attachments/835a47b1-d2a3-42e7-86f7-7c6e4b138094/codex-clipboard-8498e7bb-4a8a-4e3b-bec0-75de05136e2e.png`
- Implementation screenshot: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/design-qa-relation-link-button.png`
- Focused implementation crop: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/design-qa-implementation-crop.png`
- Viewport: 1280 × 720 CSS px, device scale factor 1
- Source pixels: 610 × 726 at approximately 2× density; normalized comparison: 305 × 363
- Implementation pixels: 1280 × 720; focused comparison crop: 287 × 365
- State: light theme, empty `User Stories` relation, add-link action hovered with tooltip visible

## Full-view comparison evidence

The implementation preserves the existing right-panel hierarchy and places the relation action at the right edge of its relation-group header. The former `+ Link` row is absent. The relation group continues to share the Relations & Backlinks card area.

## Focused comparison evidence

The normalized source and focused implementation crop were opened together. The implemented empty relation group shows `No User Stories linked`, a standalone plus icon aligned to the header's right edge, and the tooltip `Add a link to User Stories`. Existing relations remain cards beneath their group labels.

## Required fidelity surfaces

- Fonts and typography: Existing Zerus typography and hierarchy are preserved; the empty state uses the established muted small-text treatment.
- Spacing and layout rhythm: The plus action is aligned with the relation heading and the empty state occupies the former link-row position without adding card chrome.
- Colors and visual tokens: Existing accent, foreground, muted, hover, and tooltip tokens are used in both light and dark themes.
- Image quality and asset fidelity: No raster assets are required; the plus action uses the project's existing icon library.
- Copy and content: Tooltip and empty-state copy match the requested type-specific wording.

## Interaction verification

- Hovering the plus action displays the type-specific tooltip.
- Clicking the plus action opens the existing note-search picker.
- The empty-state copy remains visible until a relation is selected.
- Browser console errors: none.

## Findings

No actionable P0, P1, or P2 differences remain for the requested component change.

## Comparison history

- Initial implementation comparison: passed. The requested action placement, empty state, tooltip, and picker behavior were all present; no corrective iteration was required.

## Follow-up polish

No P3 follow-ups identified.

final result: passed
