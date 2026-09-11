# Design QA: mobile note collapsing header

- Source visual truth: `/Users/tiagopereira/.codex/generated_images/01a091d3-ab24-7d70-bcbb-880c63b465c5/exec-74264385-4d44-49fa-8a31-1db37ae504e3.png`
- Implementation screenshot: `/Users/tiagopereira/Documents/Codex/Zerus-remote/artifacts/design-qa/mobile-note-collapsed.png`
- Side-by-side comparison: `/Users/tiagopereira/Documents/Codex/Zerus-remote/artifacts/design-qa/mobile-note-collapse-comparison.png`
- Browser-rendered implementation: `http://localhost:8081/mobile` in the Codex in-app browser
- Viewport: 390 × 844 CSS px at device scale factor 1
- Pixel dimensions: source 853 × 1844; implementation 390 × 844
- Density normalization: the source was resized to 390 × 844 with a high-quality Lanczos filter before comparison; the implementation was captured at 390 × 844 pixels.
- State: dark theme, existing note, editor scrolled beyond the 88px collapse range, compact header fully visible.

## Full-view comparison evidence

The normalized source and implementation were placed side by side in the comparison image. Both use a compact dark header with an understated back control, coral uppercase type label, centered one-line note title, trailing ellipsis, hairline divider, and a body-first reading layout. The implementation retains Zerus's existing denser Markdown typography and real note content rather than copying the mock's demonstration copy. The browser preview also includes Zerus's existing simulated status and home-indicator chrome; these are runtime-owned and intentionally excluded from app-content fidelity judgments.

## Focused region comparison evidence

The header is clearly readable at full-view scale in the side-by-side comparison, so a separate crop was not needed. The source and implementation align on the two-line information hierarchy, centered title stack, restrained coral accent, dark translucent surface, and minimal icon treatment. The implementation keeps the 44px touch targets already used by Zerus while visually removing their circular fills as the collapse progresses.

## Required fidelity surfaces

- Fonts and typography: the existing Zerus system font is preserved. The compact type label is 10px semibold uppercase with 0.13em tracking, and the title is 14px medium with tight tracking and single-line truncation. Body typography remains the app's existing readable 16px scale.
- Spacing and layout rhythm: the compact header is 60px to preserve existing touch targets, versus roughly 56px in the mock. Its 44px/1fr/44px grid prevents controls from crowding the title. The large metadata/title region contracts continuously while body top padding reduces from 20px to 8px.
- Colors and visual tokens: the existing `#1c1d1e` surface, `#f5f3ef` primary text, `#df5149` accent, muted metadata, translucent header background, and 7% white divider match the chosen direction.
- Image quality and asset fidelity: this screen contains no raster imagery. Existing icon components are preserved; no placeholder, custom SVG, CSS drawing, or generated asset substitution was introduced.
- Copy and content: the implementation uses the current note type and title dynamically and correctly truncates long values. Body content remains the user's real Markdown note.

## Comparison history

1. Initial P2 finding: the absolutely positioned compact title stack used intrinsic width, so long titles could drift toward the right edge and crowd the action control.
2. Fix made: both header states now fill and clip to the center grid track, with truncation applied inside that bounded region.
3. Post-fix evidence: the 390 × 844 browser capture shows `INBOX` and `Welcome to Zerus` centered between the back and ellipsis controls with no overlap or horizontal overflow.

## Findings

No actionable P0, P1, or P2 differences remain. The 4px header-height difference is an intentional implementation constraint that preserves the app's existing 44px mobile touch targets.

## Primary interactions tested

- Opened a note from the mobile note list.
- Scrolled down through the editor and verified the full compact `type + title` state.
- Scrolled back to the top and verified the large title and original type row return.
- Verified the title region is hidden from assistive technology and made inert once fully collapsed.
- Checked browser warnings and errors; none were present.

## Implementation checklist

- [x] Drive collapse progress directly from editor scroll position.
- [x] Crossfade the original type row into the compact type/title stack.
- [x] Collapse and fade the large metadata/title region to reclaim reading space.
- [x] Reverse the transition when scrolling upward.
- [x] Bound and truncate long header content.
- [x] Preserve accessible controls and hidden-state semantics.
- [x] Verify at the 390 × 844 mobile viewport.

## Follow-up polish

No P3 follow-up is required for this focused change.

final result: passed
