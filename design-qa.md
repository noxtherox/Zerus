**Comparison Target**

- Source visual truth: `/Users/tiagopereira/.codex/attachments/4d34676a-33c9-424a-a4f8-e361aef946fc/codex-clipboard-db058a53-cd42-456f-8a5f-81f41c30ca7f.png`
- Expanded-card implementation: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/design-qa-task-inline-expanded.png`
- Link-note modal implementation: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/design-qa-task-link-modal.png`
- Final linked state: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/design-qa-task-linked-final.png`
- Combined comparison: `/Users/tiagopereira/Documents/Codex/Zerus-desktop-work/design-qa-task-comparison.png`
- Viewport: 1280 × 720 CSS px, light theme, desktop browser demo, one selected task. A compact desktop pass was also run at 900 × 720 CSS px.
- Source pixels: 1872 × 986. Implementation pixels: 1280 × 720 at device scale factor 1. For the combined evidence, the source was proportionally normalized to 1280 × 674 and vertically padded to 1280 × 720; the implementation remained at its native 1280 × 720 capture.
- State: the source shows the former floating task-details popover. The implementation intentionally replaces that state with the requested inline card expansion, so the comparison checks retained Zerus styling and information density rather than literal popover placement.

**Full-view Comparison Evidence**

- The combined comparison places the supplied task screen and the rendered inline expansion in one image. The task header, creation field, tabs, sidebar treatment, typography, neutral palette, borders, radius, and compact field density remain consistent with the source.
- The expansion stays within the task list width and adds only the height needed for the editable fields. At 900 × 720, the fields reflow to two columns with no horizontal page overflow (`scrollWidth` and `clientWidth` both 900 px).

**Focused Region Comparison Evidence**

- The modal capture is the focused comparison for the new interaction, which has no literal source state. It uses the same dialog, input, select, icon, border, radius, typography, overlay, and muted-color primitives already established by Zerus.
- Fonts and typography: existing system font, task heading hierarchy, 14 px task text, 12 px field labels, and muted supporting copy are preserved. Labels and results remain legible without oversized modal typography.
- Spacing and layout rhythm: the selected card uses a compact four-column desktop grid, consistent 12 px internal gaps, a single divider, and an 8 px control height rhythm. The modal keeps filter controls above a bounded result list.
- Colors and visual tokens: all surfaces, borders, muted text, accent states, destructive text, focus rings, and overlays use existing semantic tokens. No new hard-coded palette was introduced.
- Image quality and asset fidelity: no raster assets are required by this task. All interface glyphs use Zerus's shared Tabler icon layer; no custom SVG, CSS drawing, emoji, or placeholder asset was added.
- Copy and content: “Link a note,” “All types,” “Search notes…,” linked-state badges, empty results, and unlink labels describe the interaction directly. Result rows expose note title, type path, and a short content snippet.

**Findings**

- No actionable P0, P1, or P2 issue remains.

**Open Questions**

- None. The implementation allows multiple linked notes because the existing task model already stores `linkedNoteIds` as a list; each link can be opened or removed independently.

**Implementation Checklist**

- [x] Replace the floating task popover with an inline selected-card expansion.
- [x] Keep title, category, priority, date, and due-date editing inside the card.
- [x] Replace the note dropdown with a “Link a note” button.
- [x] Add a type-filtered, text-searchable note modal.
- [x] Show existing links as openable, removable chips and prevent duplicate links.
- [x] Verify the 1280 px and 900 px desktop layouts without overflow.
- [x] Verify type filtering, text search, linking, modal close, and linked-state rendering.
- [x] Check browser console warnings and errors; none were present.

**Comparison History**

- Pass 1: no P0/P1/P2 findings. The intentional popover-to-inline layout change is the requested product behavior, and the rendered result preserves the source design language without visible breakage. No post-comparison visual fix was required.

**Primary Interactions Tested**

- Opened Tasks, created a sample task, and confirmed its card expanded immediately.
- Opened “Link a note,” searched for `Polaris`, selected `work/projects` from the type dropdown, and confirmed only the matching note remained.
- Linked “Project Polaris” and confirmed the modal closed, the task header showed a link indicator, and the removable linked-note chip appeared.
- Checked the browser console after the complete flow; no warnings or errors were present.

**Follow-up Polish**

- No P3 item is necessary for this scoped change.

final result: passed
