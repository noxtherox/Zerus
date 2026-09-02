# Design QA: editor toolbar responsiveness

- Source visual truth: `/Users/tiagopereira/.codex/attachments/530e4ad4-70d2-4bf6-80fc-cce7bd1883d3/codex-clipboard-6ab65718-0c4a-4417-8d8a-0931b1f25a7f.png`
- Implementation screenshots: `/Users/tiagopereira/Documents/Codex/Zerus-remote/implementation-toolbar-1866x426.jpg` and `/Users/tiagopereira/Documents/Codex/Zerus-remote/implementation-toolbar-1000x700.jpg`
- Viewports: 1866 × 426 CSS px and 1000 × 700 CSS px
- Pixel dimensions: source 1864 × 426; implementation 1866 × 426 and 1000 × 700
- Density normalization: source and implementation were reviewed at 1×; the two-pixel source-width difference is immaterial to the focused toolbar comparison.
- State: dark theme, editable note, code block selected, code-language control visible, and Find in note expanded.

## Full-view comparison evidence

The source and the 1866 × 426 implementation capture were opened together. The source shows an empty code-language field, a visible tooltip obscuring the header, an oversized language-label/select region, and a horizontal scrollbar beneath the toolbar. The implementation shows the same editor state with a compact `Plain text` selector, the search field contained at the right edge, and no horizontal scrollbar. The implementation includes open navigation/list panes, so overall editor width differs; the toolbar region is the fidelity target for this change.

At 1866 × 426, the toolbar measured `clientWidth = 1248`, `scrollWidth = 1248`, and `overflow-x = clip`. At 1000 × 700 it measured `clientWidth = 668`, `scrollWidth = 668`, and wrapped to two rows while the search input remained visible.

## Focused region comparison evidence

The toolbar required a focused comparison because its labels and controls are too small to assess from the full app frame alone. The compact language selector keeps its accessible name while removing the visible multi-line label; the Find control remains complete with query, count, navigation, and close actions. Opening the language selector displayed 17 named options, including Plain text, JavaScript, TypeScript, Python, SQL, and YAML.

## Required fidelity surfaces

- Fonts and typography: existing app type, weights, sizes, and control text were preserved. The hidden language label remains available to assistive technology, and `Plain text` supplies useful visible context.
- Spacing and layout rhythm: the code-language control is reduced to 154 px, the right-side actions are grouped, and the toolbar wraps only when needed. No horizontal overflow remains at either checked viewport.
- Colors and visual tokens: existing Zerus background, border, foreground, hover, and accent tokens are unchanged.
- Image quality and asset fidelity: no raster imagery or custom icon assets are involved in this toolbar state; existing icon components were preserved.
- Copy and content: the previously empty selector now has clear language names. Existing Find labels and counts are unchanged.

## Comparison history

1. Initial findings:
   - P1: the code-language dropdown contained no items, so the control could not complete its purpose.
   - P2: expanding Find in note increased the toolbar's intrinsic width and exposed a full-width horizontal scrollbar.
2. Fixes made:
   - Added a curated set of 17 code-block languages with `Plain text` as the empty-language choice.
   - Compacted the code-language UI while retaining its accessible label.
   - Grouped search and trailing actions, enabled clean wrapping, and clipped horizontal overflow.
3. Post-fix evidence:
   - The language list opened and exposed all 17 options.
   - Toolbar `scrollWidth` equaled `clientWidth` at both tested viewports.
   - Find in note remained visible and functional in both single-row and wrapped layouts.

## Findings

No actionable P0, P1, or P2 findings remain in the targeted toolbar states.

## Open questions

None.

## Implementation checklist

- [x] Populate the code-language dropdown.
- [x] Give the empty code-block state a useful label.
- [x] Remove toolbar horizontal scrolling.
- [x] Verify search expansion at wide and narrow desktop sizes.
- [x] Check the browser console and production build.

## Follow-up polish

No P3 follow-up is required for this focused change.

final result: passed
