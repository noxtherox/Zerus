# Design QA — saved mobile note type accent

**Source visual truth**

- Bug-report screenshot: `/Users/tiagopereira/.codex/attachments/7ee131b3-06dd-42bf-8f56-30602690eb40/codex-clipboard-35c423ab-f14b-4084-932c-1a8be5d4633a.png`
- Source pixels: 942 × 514. The screenshot documents the incorrect fixed coral type label; it is not the desired palette.

**Implementation evidence**

- Browser-rendered screenshot: `/Users/tiagopereira/Documents/Codex/Zerus-remote/artifacts/design-qa/mobile-saved-note-themed-accent.png`
- Focused side-by-side comparison: `/Users/tiagopereira/Documents/Codex/Zerus-remote/artifacts/design-qa/mobile-saved-note-type-accent-comparison.png`
- Browser viewport: 1280 × 720 CSS px, devicePixelRatio 2. The app surface measured 393 × 852 CSS px; the full screenshot was normalized by the browser to 1280 × 720 pixels.
- Focused comparison normalization: each header crop was scaled to 500 × 150 pixels and placed side by side. The left side is the reported fixed coral; the right side is the corrected active Nightshade accent.
- State: System appearance resolving to dark Nightshade, existing saved Inbox note open.

**Findings**

- No actionable P0/P1/P2 findings remain for the reported issue.
- Colors and visual tokens: both the expanded type label/icon and compact-on-scroll type label resolve through `text-zerus-accent`. Browser-computed color for both is `rgb(167, 139, 250)`, matching the active `--zerus-accent: 167 139 250` token instead of the former fixed `#df5149`.
- Fonts and typography: unchanged from the existing saved-note design.
- Spacing and layout rhythm: unchanged; only the color source changed.
- Image quality and asset fidelity: no raster assets are involved; the existing icon remains vector and inherits `currentColor` from the themed label.
- Copy and content: unchanged.

**Interaction and runtime checks**

- Opened an existing saved note from All Notes and inspected the rendered expanded and compact header elements.
- Browser console checked: no errors. A historical Vite reconnect message corresponded to refreshing the development server.
- Frontend build and TypeScript checks passed.

**Comparison history**

1. Reported state: expanded and compact saved-note type labels used `text-[#df5149]`, so the visible label stayed coral under Nightshade.
2. Fix: replaced both fixed classes with `text-zerus-accent`; the folder icon inherits the same token through `currentColor`.
3. Post-fix evidence: browser-computed styles for both header variants are `rgb(167, 139, 250)`, and the focused comparison shows the visible saved-note label using the Nightshade accent.

**Follow-up polish**

- None for this scoped correction.

final result: passed
