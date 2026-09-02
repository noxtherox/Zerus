**Comparison target**

- Source visual truth: `/Users/tiagopereira/.codex/attachments/e1e82197-ebf1-4c67-8e2f-7312a576d00d/codex-clipboard-ecaf6ac3-3405-4b3a-bcf7-f0f4d5d1a658.png`
- Browser-rendered implementation: `/Users/tiagopereira/Documents/Codex/Zerus-remote/implementation-image-controls.png`
- Focused implementation capture: `/Users/tiagopereira/Documents/Codex/Zerus-remote/implementation-image-controls-focused.png`
- Side-by-side focused comparison: `/Users/tiagopereira/Documents/Codex/Zerus-remote/design-qa-controls-comparison.png`
- Viewport: 1280 × 720 CSS px, desktop, dark theme.
- Pixels and density: source 523 × 478 px; implementation 1280 × 720 px; focused implementation 578 × 578 px. The focused comparison crops a 120 × 90 px control region from each source and scales both equally to 480 × 360 px for inspection. Density differences were normalized by equal output dimensions.
- State: editable embedded image, selected/clicked state for visual comparison; idle and hover states checked separately.

**Findings**

- No actionable P0/P1/P2 differences. The source's delete and settings controls remain visually unchanged in the selected state.
- Idle state: the image toolbar has `visibility: hidden`, `opacity: 0`, and `pointer-events: none`.
- Hover state: the image toolbar has `visibility: visible`, `opacity: 1`, and `pointer-events: auto`.
- Clicked/selected state: the toolbar remains visible after the pointer leaves the image.
- Keyboard accessibility: `:focus-within` also reveals the toolbar.
- Fonts and typography: unchanged; this interaction-only patch adds no text or typography changes.
- Spacing and layout rhythm: unchanged; the existing toolbar size, position, padding, and image layout are preserved.
- Colors and visual tokens: unchanged; existing editor toolbar tokens remain in use.
- Image quality and asset fidelity: unchanged; no source image rendering, crop, compression, or masking changes were introduced.
- Copy and content: unchanged; existing button labels and tooltips are preserved.

**Full-view comparison evidence**

The full implementation screenshot confirms the editor layout and selected-image state render without overflow or displaced controls. The source screenshot is an interaction reference rather than a complete screen target, so surrounding note content intentionally differs.

**Focused region comparison evidence**

The side-by-side control crop confirms the same trash/settings toolbar remains anchored to the image's top-right corner when selected. The pink callout belongs only to the user's annotation and is not reproduced.

**Primary interactions tested**

- Deselected image: controls hidden.
- Pointer hover: controls visible.
- Image click followed by pointer exit: controls remain visible.
- Browser console: no warnings or errors.

**Comparison history**

- Initial pass: no P0/P1/P2 visual differences. No corrective visual iteration was required.

**Implementation Checklist**

- [x] Hide controls in the idle state.
- [x] Reveal controls on hover.
- [x] Reveal controls for keyboard focus.
- [x] Keep controls visible for a clicked/selected image.
- [x] Preserve the existing toolbar appearance and actions.

**Follow-up Polish**

- None required.

final result: passed
