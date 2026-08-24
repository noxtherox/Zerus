# List indentation design QA

- Source visual truth: `/Users/tiagopereira/.codex/attachments/a1f66779-9fee-4a81-8ecd-9d2f0c8c866a/codex-clipboard-f0e12c55-f5ef-488a-8a42-0fd9013d8e8c.png`
- Browser-rendered implementation: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/artifacts/list-indentation-final-full.png`
- Focused implementation crop: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/artifacts/list-indentation-implementation.png`
- Side-by-side comparison: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/artifacts/list-indentation-comparison.png`
- Browser viewport: 1280 × 720 CSS px
- Source pixels: 204 × 178
- Implementation full-view pixels: 1280 × 720
- Focused implementation pixels: 204 × 178
- Density normalization: the browser reported `devicePixelRatio: 2`, while its screenshot API returned CSS-pixel-sized output. The focused implementation was cropped from that output at the source's exact 204 × 178 pixel size; no resampling was used.
- State: dark theme, four root bullets, one first-level nested bullet, one blank second-level nested bullet, editor focused with the caret after the final marker.

## Findings

No actionable P0, P1, or P2 differences remain.

- Fonts and typography: the implementation retains the product's existing 15 px system UI font, weight, line height, and antialiasing. Text hierarchy and wrapping are unchanged by this fix.
- Spacing and layout rhythm: the first nested bullet is now 20.44 CSS px to the right of the root bullet, making it immediately distinct. Later nesting remains an even 15.94 CSS px per level. The focused comparison confirms the requested stronger first step without changing root-list alignment.
- Colors and visual tokens: background, text, accent bullet, and caret colors continue to use the existing Zerus theme tokens and match the supplied state.
- Image quality and asset fidelity: the target contains no raster assets or non-standard icons. Browser rendering is sharp at the captured density.
- Copy and content: the implementation uses the same list copy and blank final bullet as the source reference.
- Interaction: Shift+Tab moved the final bullet and caret left in the same update; Tab moved both back immediately. The final state had one CodeMirror overlay caret at x=621.91, after the bullet, while the native caret was transparent. No console errors were present.

## Full-view comparison evidence

`artifacts/list-indentation-final-full.png` confirms that the adjusted list rhythm sits correctly within the existing editor and does not disturb the toolbar, note title, sidebars, or surrounding layout.

## Focused comparison evidence

`artifacts/list-indentation-comparison.png` places the supplied 204 × 178 reference and an equal-size browser crop side by side. The list typography, vertical rhythm, colors, content, and focused caret state are directly readable at this size, so no additional focused region was needed.

## Comparison history

1. Initial pass: the first revision made nesting more visible but left the first visual step at about 15.94 CSS px, still too close to the later levels for the requested emphasis. Classified P2.
2. Fix: changed the layout to apply a dedicated first-nesting offset while keeping later nesting increments stable.
3. Post-fix evidence: the final browser measurement is 20.44 CSS px for the first nested step and 15.94 CSS px thereafter. The final side-by-side comparison shows the first level clearly, and the Tab cycle leaves the caret immediately after the bullet.

## Open Questions

None.

## Implementation Checklist

- [x] Increase the first nested-list offset.
- [x] Keep later nested levels evenly spaced.
- [x] Replace the transient native caret with CodeMirror's synchronized overlay caret.
- [x] Verify Tab and Shift+Tab in the browser.
- [x] Run tests, typecheck, lint, and visual comparison.

## Follow-up Polish

None required for this change.

final result: passed
