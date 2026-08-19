**Source visual truth**

- `/Users/tiagopereira/.codex/attachments/bf223f73-0832-4577-bda7-0716b19594d5/codex-clipboard-28133d0a-28d1-4e5d-92ae-0db9daa4be87.png`
- 710 × 820 pixels, representing the Configure AI chat dialog with its provider menu open.

**Rendered implementation**

- `/Users/tiagopereira/Documents/Codex/Zerus-remote/design-qa-implementation.png`
- Combined comparison: `/Users/tiagopereira/Documents/Codex/Zerus-remote/design-qa-comparison.png`
- Browser viewport: 710 × 820 CSS pixels at 1× density; implementation capture: 710 × 820 pixels.
- State: Nightshade theme, Configure AI chat open, provider menu open, OpenAI (ChatGPT) selected.

**Findings**

- No actionable P0, P1, or P2 differences.
- Typography: the dialog title, labels, helper copy, controls, weights, and hierarchy match the existing component and source treatment. The revised provider labels remain legible without wrapping.
- Spacing and layout: dialog width, padding, field heights, gaps, radii, footer alignment, and vertical rhythm match. The provider menu is intentionally taller because it now contains four choices instead of two.
- Colors and tokens: the implementation uses Zerus's Nightshade theme tokens; dialog, popover, borders, selected row, muted copy, and warning treatment are consistent with the source.
- Image quality and assets: no product imagery or non-standard image assets occur in this dialog. Existing library icons are retained and render sharply.
- Copy and content: the description now accurately names OpenAI and Claude. OpenAI (ChatGPT), Anthropic (Claude), OpenRouter, and OpenAI-compatible API are all visible in the menu.

**Focused region comparison**

- The provider menu and the fields immediately below it were examined in the side-by-side comparison. The selected checkmark, row padding, menu border, API-key helper text, model control, favourites row, warning, and footer preserve the source component's visual treatment.
- Selecting Anthropic was also tested: the fixed endpoint changed to `https://api.anthropic.com/v1` and the default model changed to `claude-sonnet-5`.

**Interaction and diagnostics**

- Tested opening the provider menu and selecting Anthropic (Claude).
- Verified the OpenAI and Anthropic fixed endpoints and provider-specific model defaults in the rendered DOM.
- Checked browser console warnings and errors: none.

**Comparison history**

- The first capture used uninitialized theme tokens in the isolated QA harness. This was a capture-normalization issue rather than a product finding; the harness was switched to the product's Nightshade preset and recaptured before comparison.
- The normalized comparison found no P0/P1/P2 issues, so no product visual-fix iteration was required.

**Implementation checklist**

- [x] Restore first-class OpenAI (ChatGPT) option.
- [x] Add first-class Anthropic (Claude) option.
- [x] Preserve OpenRouter and custom OpenAI-compatible options.
- [x] Verify provider switching, endpoints, model defaults, and native API contracts.
- [x] Verify typography, spacing, tokens, assets, copy, and console state.

final result: passed
