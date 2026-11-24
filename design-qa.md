# Native iOS navigation and Library QA

final result: passed

The X images are interaction references. The latest written requests govern the
Library order, removal of branding, folder alignment and the separate search
control. Existing Zerus themes and app content are retained.

## Final behavior

- All notes, External notes, Files and Saved links come first in Library.
- Folders follow. The icon-only New folder action sits beside the Folders
  heading; flat folders have no unused disclosure gutter. Icons, flexible names,
  right-aligned monospaced counts and action menus use consistent columns.
- Archive, Recently Deleted and Vaults are last. The Library Pinned entry and the
  Zerus title/icon/tagline block are removed. The Notes Pinned picker remains.
- Notes, folder collections, Files and Saved links use a native search field
  with an independent Sort and filter button on its right. The button opens the
  existing collection panel; Settings retains access to the same controls.
- Drawer swipes and scrolling dismissal/reveal of bottom navigation remain.

## Visual evidence

Reference directory:
`/Users/tiagopereira/.t3/userdata/attachments/`

- X drawer: `c611d9da-aa0a-4311-95c9-418f3c010406-636a7a6e-418d-4d99-b9f2-d19206f05056.png`, 433 × 843 px.
- X navigation hidden: `c611d9da-aa0a-4311-95c9-418f3c010406-17d81a67-38d8-41af-a8cb-cff35d181791.png`, 529 × 832 px.
- X navigation visible: `c611d9da-aa0a-4311-95c9-418f3c010406-1332e93e-7813-4050-bacc-0c8352cc55d4.png`, 545 × 843 px.
- Folder refinement reference: `c611d9da-aa0a-4311-95c9-418f3c010406-d775cd0d-6572-4ffc-8d89-402892add40f.png`, 359 × 573 px.

Final native captures are in `artifacts/native-ios/drawer/`:
`library-top-final.png`, `library-bottom-final.png`, `search-controls.png`,
`sort-filter-panel.png`, `navigation-hidden-final.png` and
`navigation-returned-final.png`. All are 440 × 956 px, captured at 1× from a
440 × 956 point iPhone simulator. CSS sizing does not apply to this native app.

Opened and inspected full-view comparison boards: `drawer-comparison.png`,
`hidden-comparison.png` and `returned-comparison.png`. Each is 1760 × 1912 px,
containing two 440 × 956 point panels at 2×. Source bezel crops were
(50,49,340,749), (94,49,352,747) and (115,54,352,747), normalized to panel size.
Small source aspect-ratio differences are not treated as design defects.

Focused folder comparison: `folder-alignment-comparison.png`, 1436 × 1146 px.
The source is beside the native crop (0,368,359,573), both 359 × 573 point panels
at 2×. The native fixture contains additional folders; the comparison concerns
columns, wrapping and the header creation action, not matching fixture names.
The final footer was separately inspected in `library-bottom-final.png`.

## Findings and iteration history

- Earlier folder-first placement was superseded by the user's explicit request
  for the four collections first and archive/trash/vault management last.
- P2 in the initial search-row implementation: the page title was obscured.
  Evidence: `search-controls-initial.png`. Fixed with an inset background that
  respects safe-area edges and a compact navigation title. Post-fix evidence:
  `search-controls.png` visibly shows Notes above the independent search row.
- P1 accessibility/integration regression in the initial standalone text field:
  it was exposed as an ordinary text field rather than native search. Replaced
  it with UISearchBar, retaining native clearing, keyboard and search role.
  The final accessibility snapshot reports Search and the UI journey finds and
  types into the search field successfully.
- No remaining actionable P0/P1/P2 findings in the inspected states.

## Required fidelity surfaces

- Typography: existing native body fonts and weights remain; folder names use
  available width and wrap for accessibility sizes. Counts use monospaced digits.
- Layout: aligned folder columns, 44-point creation/action targets, independent
  search/filter controls and visible page titles. The 360-point drawer leaves
  an 80-point strip of shifted main content at the checked viewport.
- Colors: existing sidebar, card, text and accent tokens remain. The checked
  dark theme keeps counts, controls and placeholders readable.
- Images/icons: native SF Symbols remain sharp. No new raster assets are needed;
  X avatars, branding and feed artwork are outside the requested scope.
- Copy/content: the Library labels and order match the latest requests. Branding
  is absent from Library; the accessible New folder label remains on its icon.

## Verification and limits

The final `NativeMenuJourneyTests` UI journey passed with 0 failures in 180.805
seconds. It covers drawer swipes, tab preservation, collection settings,
creation from the folder header, composing in that folder, native search
input/clearing and opening Sort and filter directly from the adjacent button.
Retained result: `artifacts/native-ios/library-search-final.xcresult`.

Manual final checks confirmed: typing Welcome filters the list to the matching
note; opening Sort and filter dismisses the keyboard; the footer Vaults action
opens its manager; bottom navigation hides on downward scrolling and returns
on upward scrolling. Native builds, signature verification and configuration
boundary verification passed. The private frontend and Tailscale /app routes
both returned HTTP 200.

The final signed app was installed successfully on the connected iPhone 11 as
`com.zerus.notes.native`. The Device panel does not expose physical phones for
interactive automation, so physical launch and gesture verification remain
pending. Simulator verification does not claim physical verification.

Implementation checklist: all requested navigation, Library, folder and search
changes are complete. No blocking visual findings remain.

## 2026-11-11: Google Drive vault choices removed

The latest request removes Drive **vault** options throughout both iOS
interfaces. Welcome/setup, saved-vault choices and vault settings no longer
expose a Google Drive vault opener, sync action or reconnect action. Saved
Drive-backed vault rows are filtered from the native chooser without modifying
the registry. Both native and mobile folder pickers now serve linked-file
locations only; the obsolete mobile vault duplicate-review screen was removed.

Existing connection records, notes, working copies and recovery drafts remain.
Legacy file-conflict review is retained only for an existing conflict. Drive
linked-file location mapping remains a separate feature.

Inspected final native evidence:
`artifacts/native-ios/drawer/vaults-files-only.png` (440 × 956 px at 1×).
It shows Open a vault in Files, Create a vault on this iPhone and the local saved
vault; no Drive vault choice is present. The existing native layout, semantic
colors, icons and typography are unchanged. No new P0/P1/P2 findings.

Validation passed:

- Six existing NativeDriveVaultTests (working-copy/recovery compatibility).
- NativeDriveFolderJourneyTests (file-location flow and Files-only vault menu),
  0 failures in 124.876 seconds.
- Result: `artifacts/native-ios/remove-drive-vaults.xcresult`.
- TypeScript checks, targeted React lint and the production frontend bundle build.
- Native configuration check, signed device build and signature verification.
- Both frontend and private Tailscale /app routes returned HTTP 200.

The updated signed native app was installed on the connected iPhone 11.
Physical interactive verification remains pending as described above.
