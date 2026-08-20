**Comparison Target**

- Source visual truth: `/Users/tiagopereira/.codex/attachments/102dbc25-c99c-4ec2-bdec-f0c4a66c1662/codex-clipboard-71f710c6-559f-4598-8326-c149e0c583fd.png`
- Implementation screenshot: `/Users/tiagopereira/Documents/Codex/Zerus-remote/design-qa-clipboard-paste.jpg`
- Viewport: implementation capture 1199 × 768 CSS px at device scale 1. Source capture 577 × 494 px with unknown CSS size and density.
- State: desktop note editor with the AI panel open. The source is a dark-theme crop with AI enabled. The implementation evidence is a light-theme full-window capture from the local Tauri desktop build with AI disabled because the temporary QA vault has no provider credential.

**Findings**

- [P1] Live pasted-image preview state could not be captured
  Location: AI chat composer in `src/components/ai/AiPanel.tsx`.
  Evidence: the implementation desktop build rendered the correct composer, but its textarea and attachment control were disabled by the temporary vault's missing AI provider credential. The source does not include a pasted-image preview state to compare against.
  Impact: code and unit tests verify clipboard extraction, but this QA pass cannot visually prove the end-to-end paste interaction and removable thumbnail state.
  Fix: repeat the desktop interaction check in a vault with AI already configured, paste an image into the composer, and capture the resulting preview.

**Required Fidelity Surfaces**

- Fonts and typography: unchanged by this implementation; the desktop capture retains the existing composer typography.
- Spacing and layout rhythm: unchanged; paste reuses the existing attachment-preview row and composer spacing.
- Colors and visual tokens: unchanged; no new color or token was introduced. Theme differences between evidence images were not treated as regressions.
- Image quality and asset fidelity: pasted files use the existing image preparation pipeline, which constrains dimensions, converts to JPEG, and uses the existing preview treatment. Live visual output was not capturable in this QA environment.
- Copy and content: unchanged; no new user-facing copy was introduced.

**Open Questions**

- None about implementation. A configured local AI provider is required only to complete the blocked live interaction capture.

**Implementation Checklist**

- [x] Extract image files from clipboard items while ignoring text and non-image files.
- [x] Route pasted images through the existing resize, compression, preview, removal, persistence, and send pipeline.
- [x] Preserve normal text paste when no image is present.
- [x] Preserve the existing four-image message limit.
- [x] Pass all automated tests, type-checking, and targeted linting.
- [ ] Capture a live pasted-image thumbnail in an AI-enabled desktop vault.

**Full-view Comparison Evidence**

- The implementation desktop capture confirms the AI panel and composer retain the existing layout. Because theme, crop, and enabled state differ, it is not suitable for pixel-level fidelity claims.

**Focused Region Comparison Evidence**

- Blocked: the required pasted-image preview region could not be produced while the temporary QA composer was disabled.

**Comparison History**

- Initial pass: implementation built and desktop composer rendered. Live paste verification remained blocked by the disabled composer; no visual fixes were made or claimed.

**Primary Interactions Tested**

- Opened the local Tauri desktop build, selected a note, and opened the AI panel.
- Automated coverage verified clipboard image filtering and the existing attachment-related test suite.
- Live paste and remove were not tested because the temporary QA composer was disabled.

**Follow-up Polish**

- None identified.

final result: blocked

---

# Folder-only view toggle — 2026-08-19

**Comparison Target**

- Source visual truth: `/Users/tiagopereira/.codex/attachments/502fde28-24e2-44c9-95b2-2c088a64939d/codex-clipboard-229971b1-ef70-4859-a261-6f3e3895fd10.png`
- Implementation screenshot: `/Users/tiagopereira/Documents/Codex/Zerus-remote/design-qa-folder-toggle-enabled.png`
- Side-by-side comparison: `/Users/tiagopereira/Documents/Codex/Zerus-remote/design-qa-folder-toggle-comparison.png`
- Viewport and density: source 822 × 587 px; implementation 822 × 585 CSS px at device scale 1. The implementation was normalized to 822 × 587 only for the side-by-side canvas.
- State: desktop List view with the view menu open and the `Hide subfolder notes` slider enabled. The source uses the app's dark theme; the browser demo uses its current light theme.

**Findings**

- No actionable P0/P1/P2 differences remain. The new row follows the existing menu's icon, type, spacing, and separator patterns, while the slider clearly communicates its on/off state without crowding or clipping the 822 px viewport.

**Required Fidelity Surfaces**

- Fonts and typography: existing menu typography, weights, truncation, and capitalization are preserved.
- Spacing and layout rhythm: the new row matches the 40 px view rows and retains separators above the saved-state footer.
- Colors and visual tokens: the row uses existing foreground, muted-icon, hover, border, and accent tokens. The light/dark difference is the active demo theme, not a component-level drift.
- Image quality and asset fidelity: no raster assets were introduced. The folder glyph comes from the app's shared Tabler icon set, and the slider reuses the existing Radix-based Switch component.
- Copy and content: the control uses the user-specified text exactly: `Hide subfolder notes`.

**Full-view Comparison Evidence**

- The combined comparison shows the menu in the same viewport and open state. Its anchor, width, row alignment, hierarchy, and footer remain consistent with the source after adding the folder-only control.

**Focused Region Comparison Evidence**

- A separate crop was not needed: at 822 px wide, both menus and their row-level details are fully legible in the side-by-side comparison.

**Primary Interactions Tested**

- Enabled `Hide subfolder notes` from List and confirmed child-folder notes disappeared.
- Reopened the menu and confirmed the switch state was `checked`.
- Switched to Gallery and confirmed the same folder scope applied there.
- Disabled the option and confirmed child-folder notes returned.
- Re-enabled the option for the final capture.
- Checked the browser console after the interaction sequence; no errors or warnings were present.
- Ran the full Vitest suite (232 tests), TypeScript type-checking, and targeted ESLint checks.

**Comparison History**

- Initial revision: the full-size slider caused the label to wrap at the matched 822 px viewport (P2).
- Fix: reduced the slider to a compact existing-component variant, tightened the row gap, and kept the exact label on one line.
- Post-fix evidence: `design-qa-folder-toggle-enabled.png` and the combined comparison show the label and slider fully visible on one line with no crowding.

**Follow-up Polish**

- None identified.

final result: passed

---

# Sort & filter menu — 2026-08-20

**Comparison Target**

- Source visual truth: `/Users/tiagopereira/.codex/attachments/c06ff9dd-b173-48b8-8f6b-ae5846aebd22/codex-clipboard-0561b282-787b-45a1-a525-6bed6db8bbde.png`
- Initial implementation screenshot: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/design-qa-sort-filter.png`
- Final implementation screenshot: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/design-qa-sort-filter-final.png`
- Side-by-side comparison: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/design-qa-sort-filter-comparison.png`
- Viewport and density: source 591 × 713 px with unknown CSS density; implementation 1000 × 760 CSS px at device scale 1. Both were normalized to 713 px high for the 1530 × 713 comparison canvas.
- State: filter popover open in a desktop notes view. The source is the dark structured Table view; the implementation is the light browser-demo List view, which exercises the same shared component with a narrower trigger container and a smaller demo property set.

**Findings**

- No actionable P0/P1/P2 differences remain. The shared control now reads `Sort & filter`, the menu preserves the existing filter hierarchy, and the new sort section is positioned before filters so the information architecture reads naturally.

**Required Fidelity Surfaces**

- Fonts and typography: existing app font, weights, 12–14 px hierarchy, line height, and menu truncation behavior are preserved. The trigger label remains readable in both wide and narrow placements.
- Spacing and layout rhythm: the source menu width, section padding, separators, radii, and control heights are retained. The sort section follows the same 12 px section padding and 32 px control height as property filters.
- Colors and visual tokens: the implementation uses the existing background, border, muted foreground, accent, hover, and focus tokens. Light/dark differences in the comparison are theme state rather than component drift.
- Image quality and asset fidelity: no raster assets were added. Filter, sort, and chevron glyphs use the app's existing Tabler icon system and remain sharp at the target sizes.
- Copy and content: `Filter notes` becomes `Sort & filter`; `Clear all` becomes the more precise `Clear filters`. Sort choices are `Recently updated`, `Least recently updated`, `Title: A–Z`, and `Title: Z–A`. Created-date choices were intentionally omitted because the note model has no reliable created timestamp.

**Full-view Comparison Evidence**

- The combined comparison confirms that the original filter sections remain visually intact and that the added sort section uses the same density and alignment. The wider structured-view trigger remains inline with search and New; the browser-demo evidence additionally verifies the shared component's narrower sidebar placement.

**Focused Region Comparison Evidence**

- A separate crop was not required: both menus are fully legible at the normalized 713 px comparison height, including their icons, labels, 32 px controls, separators, and switch alignment.

**Comparison History**

- Initial pass (P2): the labeled trigger shared the old two-column sidebar row with search and reduced the search input to an unusable sliver.
- Fix: the narrow Note List placement now stacks the full-width search field and full-width combined trigger, while the wide Type view keeps the requested inline control.
- Post-fix evidence: `design-qa-sort-filter-final.png` shows both controls at useful widths with no clipping, overlap, or hidden persistent controls.

**Primary Interactions Tested**

- Opened and closed the combined popover through its accessible `Sort and filter notes` trigger.
- Selected `Title: A–Z` and confirmed the visible notes reordered from update time to alphabetical title order.
- Confirmed the popover still exposes archive, updated-date, type, and property-filter controls.
- Checked browser console errors after the interaction sequence; none were present.
- Verified sorting behavior with automated tests, including ascending update order and pinned-note precedence.

**Follow-up Polish**

- None identified.

final result: passed

---

# Collapsed subfolder selection pattern — 2026-08-19

**Comparison Target**

- Source visual truth: `/Users/tiagopereira/.codex/attachments/e8f4092e-97fd-470f-8599-c27717b0c9d7/codex-clipboard-308ba1f5-255f-4d49-95f3-a4a90788b3e3.png`
- Implementation screenshot: `/Users/tiagopereira/Documents/Codex/Zerus-remote/design-qa-collapsed-subfolder-pattern.png`
- Focused side-by-side comparison: `/Users/tiagopereira/Documents/Codex/Zerus-remote/design-qa-collapsed-subfolder-pattern-comparison.png`
- Viewport and density: source 1316 × 864 px with unknown CSS density; implementation 1280 × 720 CSS px at device scale 1. The focused comparison normalizes both 48 px collapsed rails to 144 × 720 px for inspection.
- State: the source shows a selected top-level folder with its direct children using the established 135° stripe pattern. The implementation shows `work / projects` selected in collapsed mode: the parent retains that 135° hierarchy pattern and the selected subfolder uses a distinct 45° pattern plus an inset active ring.

**Findings**

- No actionable P0/P1/P2 differences remain. The selected nested folder is visibly distinct from both its patterned parent and its unselected sibling, while the 48 px rail width, icon centering, spacing, and existing top-level behavior remain unchanged.

**Required Fidelity Surfaces**

- Fonts and typography: no type is rendered inside the collapsed folder controls; accessible folder names remain available through labels and tooltips.
- Spacing and layout rhythm: existing 32 × 32 controls, 2 px vertical gap, centered icons, rail width, separators, and footer placement are unchanged.
- Colors and visual tokens: both patterns derive from `--zerus-sidebar-fg`; the nested state uses the same foreground family with a slightly stronger 24% stripe and 42% inset ring for active-state contrast.
- Image quality and asset fidelity: no image assets or icons changed. Existing configured folder icons remain centered and sharp.
- Copy and content: folder labels and tooltip paths are unchanged; the selected nested control retains `aria-current="page"` and its parent retains `aria-expanded="true"`.

**Full-view Comparison Evidence**

- The implementation capture confirms the sidebar remains aligned with the note-list and workspace panels, with no clipping, width shift, or footer displacement.

**Focused Region Comparison Evidence**

- The combined rail crop shows the source's established diagonal treatment beside the implementation. The parent uses 135° stripes and the selected nested folder uses 45° stripes with an inset outline, making the hierarchy readable without adding labels or widening the rail.

**Primary Interactions Tested**

- Expanded `work`, selected `projects`, then collapsed the navigation sidebar.
- Confirmed `work`, `work / meetings`, and `work / projects` remain visible in collapsed mode.
- Confirmed the selected subfolder exposes `aria-current="page"`, its parent exposes `aria-expanded="true"`, and the two controls compute different stripe angles.
- Checked the browser console after the interaction; no errors or warnings were present.
- Ran targeted ESLint, TypeScript type-checking, the full Vitest suite (247 tests), and the production build.

**Comparison History**

- Initial state: nested selections reused the solid active fill, so only the surrounding hierarchy carried a pattern.
- Fix: introduced an opposite-angle active pattern for selected paths deeper than the top level, retaining the inset active ring and the existing top-level treatment.
- Post-fix evidence: the focused comparison and computed styles confirm a 135° contextual parent pattern and a 45° selected-subfolder pattern.

**Follow-up Polish**

- None identified.

final result: passed

---

# Collapsed, progressively loaded type tree — 2026-08-19

**Comparison Target**

- Source visual truth: `/Users/tiagopereira/.codex/attachments/cf172faa-4117-4a3f-add8-68b8ffe11a00/codex-clipboard-45a60d36-a608-474a-acdc-3461e13b711e.png`
- Implementation screenshot: `/Users/tiagopereira/Documents/Codex/Zerus-remote/design-qa-type-lazy-loading-control.png`
- Side-by-side comparison: `/Users/tiagopereira/Documents/Codex/Zerus-remote/design-qa-type-lazy-loading-comparison.png`
- Viewport and density: source 811 × 879 px; implementation 811 × 879 CSS px at device scale 1. No density normalization was needed.
- State: the source shows the existing dark desktop type tree with several folders expanded. The implementation uses the requested initial collapsed state and a 34-root test tree after the final four rows loaded automatically near the bottom of the sidebar scroll. The browser demo uses its existing light content theme; the sidebar retains the same dark token treatment.

**Findings**

- No actionable P0/P1/P2 differences remain. Folder rows, indentation, icons, truncation, hover affordance, and the fixed settings/trash footer retain the existing sidebar treatment. Progressive loading no longer requires or leaves behind a manual control.

**Required Fidelity Surfaces**

- Fonts and typography: existing sidebar type sizes, weights, line heights, truncation, and uppercase section label are unchanged; the new loading row uses the existing small muted-text hierarchy.
- Spacing and layout rhythm: existing type-row height and indentation are preserved. The loading control follows the same row padding and does not displace the fixed footer.
- Colors and visual tokens: the implementation reuses `zerus-sidebar-fg` opacity and hover tokens; no new palette values were introduced.
- Image quality and asset fidelity: no raster assets were added. Folder and chevron glyphs continue to come from the app's existing icon system.
- Copy and content: automatic loading uses a transient `Loading more…` status only while undisplayed rows remain; no permanent control copy competes with folder names.

**Full-view Comparison Evidence**

- The side-by-side comparison shows that the existing three-column structure and sidebar visual language remain intact. Differences in expanded/collapsed state are intentional requirements, and differences in panel proportions/content theme come from the browser demo's current saved layout rather than this change.

**Focused Region Comparison Evidence**

- The implementation capture is scrolled to the bottom of the type region after automatic loading. All remaining roots are present, the loading sentinel is gone, and the fixed footer remains unclipped.

**Comparison History**

- Initial pass: the first implementation used a manual `Show more (4 remaining)` control, which wrapped across three lines in the narrow browser-demo sidebar (P2).
- First fix: shortened the manual label to `+4 more` and added a descriptive accessibility label.
- Final interaction refinement: replaced the manual control with a scroll sentinel that preloads the next 30 rows within 120 px of the sidebar bottom.
- Post-fix evidence: `design-qa-type-lazy-loading-control.png` and the combined comparison show all remaining roots loaded with no lingering control or footer crowding.

**Primary Interactions Tested**

- Reloaded the app and confirmed child types were absent until explicitly expanded.
- Expanded `personal` and confirmed `reading` appeared, then collapsed it and confirmed `reading` disappeared.
- Confirmed a 34-root tree initially rendered 30 rows with four remaining.
- Scrolled the sidebar and confirmed all four remaining roots appeared automatically and the sentinel disappeared.
- Searched for `Reading list` while its `personal/reading` type remained collapsed and confirmed the note still appeared.
- Confirmed expansion buttons expose descriptive accessible names.
- Browser console had no feature-related errors. Existing type-creation dialogs emitted their pre-existing missing-description warning while generating QA fixtures.
- Ran the full Vitest suite (246 tests), TypeScript type-checking, targeted ESLint checks, and the production build.

**Follow-up Polish**

- None identified.

final result: passed
