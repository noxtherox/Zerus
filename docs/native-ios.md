# Native SwiftUI iOS app

Repository layout: SwiftUI and Tauri iOS coexist while the native app is evaluated.
The native app owns its sources, icons, configuration and tests; shared iOS
services live in `packages/apple/`. Native builds do not read Tauri configuration
or generated assets. Existing iOS archive/TestFlight commands continue to target
Tauri. See [iOS app coexistence](ios-apps.md) and the
[native development entry point](../native-ios/README.md).

Menu update delivered in **0.3.107/1 on iPhone 18 Pro Max**: Notes now sits above
Library in one navigation stack, so Back returns to folders. The bottom bar is
Notes, Tasks, Ask, Search, New note; compose retains the current tab and uses the
folder being viewed. Three-dot buttons open settings across the workspace, with
Sort and filter, Select notes and Recent actions grouped in a Notes section for
note collections. Selection controls appear in the list only while selecting. The focused menu
and collection-filter UI journeys pass in the isolated iPhone simulator; dark-mode
Notes and Settings screenshots were visually checked. Evidence is in
`artifacts/native-ios/menu-implementation-proof.json`.

**Current delivery: 0.3.107/1 is installed and launch-verified on iPhone 18 Nox.**
The original 483-note workspace reopens with the new menu/navigation controls;
there are no new crash diagnostics. The app container was backed up before the
update. See `artifacts/native-ios/delivery107/delivery-proof.json` for this delivery.
The earlier 0.3.106 iPhone 11 inspection remains recorded below.
The agreed native testing goal is complete, with AI/Drive excluded, accessibility
accepted and physical composing-keyboard verification explicitly deferred. The
combined update includes folder management, custom themes and native in-note Find.
See `batch106-physical-proof.json` and the completion review. Earlier checkpoints
and historical limitations below retain their original evidence.

Current scope update, 8 November: the user accepts the current accessibility
options. Stop accessibility/contrast/VoiceOver work and repeated permission
requests; historical audit results below remain evidence, not goal gates.
Physical keyboard composition remains explicitly deferred. A later device-tool
recovery attempt cleared the app container unexpectedly; known persistent data
was restored and the original 483-note iCloud workspace reopened. Full prior
container contents cannot be certified because no fresh complete inventory was
captured. The user confirms no personal files were stored in that local folder.
A follow-up reconnects the same QA vault and both external QA files through Files;
all191 known Documents files stay byte exact, only access records change, and the
original 483-note workspace is restored. A fresh complete358-file container backup
and inventory are retained. See `restore-access105-proof.json`, the current completion review and
`provider105-incident-and-restoration.json`. Do not use devicectl's
`--remove-existing-content` flag with this app data domain.

A subsequent safe Files rename check verifies physical local-file recovery on105:
the original body/checklist/image remain visible while the path is unavailable,
Retry retains the error, and restoring the filename returns the same editor to
Saved. All191 Documents files and preferences remain byte exact; only the existing
external entry's opened time and two system snapshots change. The original 483-note
workspace is restored. See `rename-recovery105-proof.json`. This is not a cloud
provider-disconnection or interrupted-write pass; no new build is installed.

A separate installed105 physical prewrite interruption check now passes: the
original QA file is unchanged while its private draft contains the new character;
SIGKILL and normal relaunch recover/save that exact draft automatically. The
original note bytes and483-note workspace are restored. Private support files
and diagnostics remain exact; QA history follows its unchanged retention policy.
See `interrupt105-proof.json`. No build, installation or speed benchmark occurs.

`native-ios/` is the standalone SwiftUI iPhone/iPad application. It contains no
React, Tauri, Rust, WKWebView, or JavaScript interface. Editing uses a
TextKit 2 `UITextView` inside SwiftUI, `NSAttributedString`, system selection,
keyboard dictation, Undo/Redo, Dynamic Type, and native formatting controls.
AppKit's macOS `NSTextView` is not an iOS framework; this uses the corresponding
Apple text technology available on iOS.

This is a native testing preview, installed as **Zerus Native** with the bundle
identifier `com.zerus.notes.native`. It coexists with the established Zerus app,
and has its own sandbox, Keychain credentials, and local settings. Choose an
existing folder through Files to work with it; the old app's sandbox is not
implicitly accessible. Both apps can edit a folder that the user explicitly
chooses. Use a copy of a vault when evaluating unfinished parity features.

## Current testing scope

The local folder-catalogue candidate now supports real empty-folder creation and
discovery, nested parents, shared portable icons/emoji, per-saved-vault sibling
order and New note in the selected folder. Its focused storage tests and actual
normal-size UI flow pass. Folder rename also passes 39 focused checks and the
actual native Review/Cancel/Rename/open-note flow. It retains empty directories
and opaque files, updates portable references and shared metadata, and journals
a directory-move receipt for interruption recovery. See
`folder-rename-local-proof.json`. Case-only changes retain the existing spelling.
If files change after the metadata commit, the rename receipt and all files are
kept and further writes stop; restore the reviewed files through Files, then
reopen the vault to finish. There is no native merge/cancel control for this
recovery conflict.

Native folder deletion now reviews the complete folder before moving it to
Recently Deleted. The folder group retains all note/attachment bytes, empty
subfolders and owned shared schemas/icons/views; Restore returns them together.
It is separate from individually deleted notes. The group also offers a reviewed
permanent cleanup with an additional irreversible-action confirmation. Existing
revisions/automatic history remain outside that cleanup. Per-device folder order
and the default note destination reset on deletion and are not automatically
restored. Files or conflicting owned metadata at the original destination prevent
restoration; unrelated settings changes are retained. Interrupted moves use a
pending receipt; changed reviewed files preserve the pending operation and stop
writes until reconnected. Completed folder archives are not read on ordinary note
saves, and unsupported retained records remain preserved with a Trash issue.

The final41 focused checks pass, including before/after proof for the unrelated
identified-note save path, cold move/restore/purge recovery and stale/workspace
isolation. Actual local Delete/Cancel/Restore and the permanent warning (dismissed
without deletion) pass; the note reopens Saved and every vault file is restored
byte exact. See `folder-trash-local-proof.json`. No extra Simulator install was
needed after tests; its installed bundle exactly matches the tested final build.
These changes, custom palettes and native in-note Find are included in106. See `folders-local-proof.json`
and the completion review for the earlier catalogue checkpoint and icon limit.

The current delivery device is **iPhone 18 Nox**, running iOS 27.2. Preview **0.3.107/1**
is installed and opens from the retained signed Release binary. AI and direct
Google Drive integration work are excluded; existing code/account data remain.
The active checklist is [native-ios-parity.md](native-ios-parity.md).

Preview 105 delivers the accumulated saved-vault/Recent/details layouts and
external-file clean retry/native recovery sheet in one phone installation.
Maximum-text physical checks show complete saved-vault location status,
separate Recently opened/Clear, useful writing space and complete first-viewport
document filename/location/41bytes/Preview/Share. Actual Quick Look reads the
expected content. Normal external Chart opens with its original image/checklist;
Save now's clean refresh remains Saved. All 185 QA and both Chart project files
remain byte exact, with no paths/history added or removed; all 59 diagnostics stay
exact. The original 483-note workspace is restored. See
`recovery105-physical-proof.json` and the current completion review for private
access rebasing and exact limits. No provider outage or VoiceOver pass is claimed.

Local normal/maximum recovery-sheet checks verify full errors, reachable actions,
failed retry retaining the sheet, reviewed Reload/Cancel and successful dismissal.
The real clean-retry regression fails before repair and seven owner tests pass
afterward, before the final presentation edit. The final app builds and retains
its own visible interaction proof. Related fixes stay batched; physical composing
keyboard setup is explicitly deferred and no Japanese keyboard was added.

The latest four-screen functional journey completes, but its unfiltered Apple
audit still fails with 36 findings (20 scaling, 11 clipping, five contrast). The existing
helper now retains all 36 issue descriptions while keeping every failure. Each
contrast object provides only a generic SwiftUI node and a nil element, so these
are not resolved by another identical audit. No finding is suppressed. Historical
42finding results and other broad passes keep their original source checkpoints.

The31 identifiable scaling/clipping targets now have a direct normal/maximum
rendering review on the unchanged local candidate:20 visibly enlarge, ten
clipping targets show complete labels and one note snippet is deliberately
limited. The same diagnostic QA vault was reused without note/task/history
writes; no app/test edits, build/install or audit rerun occurred. All10,517 paths
remain and the original two-note Simulator workspace is restored. See
`audit-growth-target-review.md` and `audit-growth-local-proof.json`. The audit
remains failed36; these observations do not prove intermediate-size, contrast
or physical VoiceOver acceptance.

A later read-only physical104 scroll check traverses the483-note native list
forward/back and the existing33,446-byte QA note to its240th paragraph and back
to the heading. Process6070 stays unchanged, with no rebuild/install/relaunch.
Immediate remote blank fling frames recover on subsequent capture without input;
their mirror/renderer origin is unresolved, and every animation frame is not
claimed smooth. All 185 QA files,161 private files and59 diagnostic entries remain
exact. Original483/All/no editor/normal/capture off is restored. See
`scroll104-physical-proof.json`; this is separate from typing/save measurements.

Physical composing-keyboard setup is explicitly deferred by the user on8 November;
no Japanese keyboard was added. The existing QA keyboard note was inspected
without typing, and its original language selection and483-note workspace are
restored. All 185 QA/161 private files and59 diagnostic entries remain exact.
See `input-review104-physical-proof.json`; do not repeat the setup request.

A direct light-mode pixel sample also localizes a low-contrast native Notes
search prompt (about3.11:1). SwiftUI Text styling and scoped UIKit search-controller
styling experiments failed to persist in the visible control and are removed
from production. Runtime inspection confirms the visible field is the navigation item's field,
using secondaryLabelColor. A window-resolving helper also reaches that exact field
but fails to persist styling and is removed. Do not repeat these approaches.
This finding does not identify any generic contrast audit issue.

A subsequent local candidate uses UIKit's public per-field accessibility-contrast
trait instead of rewriting placeholder attributes. Notes and unified Search retain
native query/Clear/dismiss behavior; the stronger Notes prompt survives tab return.
Runtime confirms that field and label use high contrast while the window stays
normal. An approximate light estimate is4.77:1 using resolved foreground plus a
JPEG-mirror background; dark/maximum-size Notes render. This is local evidence,
not a whole-app audit pass or a physical update. The first unset-override getter
assertion was corrected to read resolved traits; its Simulator crash is retained.
The corrected launches stay open. All10518 existing local paths remain, with only
one proven private access-root rebase; normal Main/All is restored. The phone stays
on105. See `contrast-trait-local-proof.json` and the current completion review.

Recent physical checks cover native writing/formatting, software letter and
emoji keys, clipboard Undo/Redo and cold reopening, maximum text size, landscape,
and local PDF/Word/HTML generation with system Quick Look. Opening Paste while
editing now dismisses the software keyboard. All145 selected core owners and30
unique UI journeys pass across retained74–76 results. The final nine-workspace
batch passes9/9 with no failures, skips or runtime warnings. At the retained91
source checkpoint, 40 selected editor/storage checks pass, including the retained
foreground image-refresh overlap regression. The retained broad passes belong
to their original source checkpoints. Controlled large-note bursts preserve
every character and native Undo/Redo, while additional document-size typing
cost remains open. See the [current completion review](native-ios-completion-review.md).
Preview 92 adds a stronger, wrapping Tasks history footer. The unchanged
unfiltered four-screen UI journey completes its functional assertions but still
reports 42 Apple findings; the current footer contrast warning is resolved.
Physical maximum-size footer/Library rendering and exact preservation of all 162
QA files are verified. No global text-size setting is changed.

Preview 93 has 32 passing selected editor/storage checks and a 32,529-case
literal-block parser comparison. Both physical typing fixtures save exactly,
Undo restores them, and all 169 resulting QA files survive cold launch. The
remaining document-size burst cost stays open. Preview 94 fixes Recent-key
migration with six passing search/registry checks and physical recovery of
existing main/QA visits across installation and cold launch.
Preview 95 isolates private task drafts by saved identity when paths are reused.
Nine task/search/registry checks pass, including the extended real-record recovery
regression that fails before repair. Both physical draft lists open; QA access
survives cold launch and all 169 QA files stay exact. Older multi-owner draft
folders remain untouched and unavailable until their ownership is recovered.
Preview 96 scans title lines only until the first matching heading, preserving
Swift character boundaries and filename fallback. Thirty-seven selected app
checks and a 31,173-case comparison pass, including a before-failing Unicode
regression. Corrected physical input and native Undo stay exact; all 168 current
QA files survive cold launch. Baseline/final phone observation ranges overlap,
so title-helper savings do not establish improved whole-editor latency.
Preview 97 reuses unchanged Markdown paragraphs during native typing while
keeping immediate recovery drafts. All 44 selected editor/storage owners pass.
The physical large-note burst takes 19.64–21.84 seconds including remote
input and save observation, versus25.73–27.96 seconds on96. These single-run
bounds do not measure a wait after typing finishes.
Eight native Undo groups restore exact bytes, cold reopening preserves all
168 QA files, and the original workspace is restored. Sustained writing and
remaining accessibility/provider acceptance are still open.
Preview 98 restores full-row interaction for native list choices. All 27 selected
vault/bulk checks pass. Physical common-schema/list-option review and incompatible
choice Cancel preserve files; Blue plus a selected date apply to two QA notes,
survive cold launch and return exactly through reviewed Undo and another cold
launch. Six new history records independently reconstruct; original workspace,
private records and all 58 diagnostic entries are preserved. See the completion
review for the five remaining acceptance areas.
The earlier combined status/recovery batch was delivered in preview103 with one
phone installation. Seven focused editor checks passed together; controlled
Simulator checks covered cancellation and interrupted recovery. Its physical
largest-text document-editor crowding finding led to the104layout repair above.
Those earlier results retain their exact evidence and limits.
Preview102 aligns folder badges with default collection counts and adds useful
empty Library collection recovery. Physical Work/User Stories shows161in both
places; empty Archive returns to Library. Checked note files remain unchanged.
Preview101 gives Library folder names more room at accessibility text sizes by
placing note counts beneath them. Physical folder rendering and navigation pass
on iPhone 11; all183QA files and161support files remain exact. The Library
versus collection note-count discrepancy found here is fixed in preview102.
Preview100 makes the welcome screen scroll and its text/action labels wrap at
accessibility text sizes. On iPhone 11, the largest size now shows the full
heading/subtitle and Saved vaults/Files labels; Files opens the native picker.
Normal launch restores the original 483-note vault. All183QA and161support files
stay byte exact; bookmarks remain intact and no new crash/Jetsam report appears.
This verifies the welcome layout, not actual unavailable-provider recovery.
See the completion review for the exact scope; no new timing campaign or broad
test suite accompanies this small presentation fix.
Preview99 fixes empty collection recovery: Archive and Pinned explain their
empty state and offer Show all notes; an empty library offers New note. The
signed build is installed on iPhone 11, and the physical Archive action returns
to all14QA notes. All183QA files remain unchanged and the original 483-note vault
is restored. No repeated timing runs or new tests were added for this small UI
change; prior checks retain their source checkpoints.
A physical98 follow-up verifies Home/return on the original vault and an edited
QA note after at least30seconds, preserving the same process and exact saved
text. Two native Undo groups and cold launch restore the fixture. All180 prior
QA files,161 support files and58 diagnostics stay exact; three history records
are added. The earlier89 replacement does not reproduce; its cause remains
unknown. See `lifecycle98-physical-proof.json`.
Physical98 also verifies the maximum-size Notes Archive choice and its selected
checkmark on the ownedQA vault. Normal font and original 483-note vault restore
with all183 currentQA files,161 private files and58 diagnostics exact. This does
not rerun or resolve the retained42 Apple findings; see
`accessibility98-physical-proof.json`.
Full VoiceOver, composition/IME and broader provider/long-use
acceptance remain unverified. The historical sections below retain earlier
evidence and limitations; their test counts are not cumulative.

## Build and install

Requires Xcode 27, Xcode command-line tools, an iOS 26+ simulator or device,
XcodeGen (`brew install xcodegen`), and the configured development team and
Apple Development certificate for physical installation. The first build also
fetches pinned Swift Markdown and swift-cmark 0.9.0, plus SwiftSoup 2.14.3,
through SwiftPM. These parse Markdown and clipboard HTML; TextKit 2 remains the
editor. Their license notices are bundled and available in Settings → Open-source
licenses. Settings also shows the installed version and build.

```sh
xcrun devicectl list devices --timeout 5
pnpm ios:native:build --device <physical-iphone-UDID>
pnpm ios:native:install --device <physical-iphone-UDID>

# Unit/storage tests and a real UI create/edit/relaunch/search/task journey
xcrun simctl list devices available
pnpm ios:native:test --simulator <simulator-UDID>
```

The build command generates `native-ios/ZerusNative.xcodeproj`, builds the
**Release** development-signed app, then checks its signature, bundle identity,
and SwiftUI scene manifest. Output:
`artifacts/native-ios/device/Build/Products/Release-iphoneos/ZerusNative.app`.
The install command installs that exact app, then launches it. Enable Developer
Mode on the phone and trust this Mac first. It does not upload to TestFlight,
create an archive, advance the canonical App Store build number, or replace the
existing app. `pnpm ios:new-build` and `pnpm testflight` still refer to the
established Tauri distribution pipeline.

The native app owns its scene lifecycle through SwiftUI `App`/`WindowGroup`.
The existing Tauri app must retain its `TaoSceneDelegate` manifest and runtime
pin. Adding that delegate to the standalone SwiftUI target would be incorrect.

## Included

- Native onboarding, Files folder selection, security-scoped bookmark restore,
  and named on-device vaults accessible through Files. A private saved-vault list
  supports switching, friendly names and registration-only removal. The last
  selected folder migrates automatically; removing a current entry keeps its
  open session but stops automatic reopening after restart. Bookmark resolution
  runs off the UI actor; reopening shows progress or a readable error with a
  retry action. Foreground and protected-data availability retry restoration.
- Native note navigation uses SwiftUI NavigationStack for Back and edge-swipe,
  with Forward and visit history in Note actions → Navigation. Close note returns
  to the originating list, task or search. Each presentation keeps its own
  history; existing note identities follow renames, while unavailable records
  show a placeholder and retained conflict drafts remain accessible. Histories
  are scoped to the current vault activation and end when the presentation closes.
- Reviewed note renaming updates the title and optionally its Markdown file in
  the current folder. Incoming body links, reciprocal relations, task supporting
  notes and automatic history remain connected by the same journal; deliberate
  revision snapshots and attachment files stay independent. Open editors follow
  the renamed file and continue saving. Managed link/file records retain their
  internal names. The review shows the exact destination and never replaces an
  occupied file. Case-only title changes retain the existing filename spelling.
- Native Notes, Tasks, Library, and Ask tabs, with iPhone and iPad layouts,
  system/light/dark appearance, and accessible system controls.
- Dedicated native Search tab across notes, saved links, tasks (including older
  completed tasks), file names/paths and saved AI conversations. Indexing and
  shared event-history reads run off the UI actor. Filters include collection,
  modified date, folder, property/value, archive visibility, task status and
  priority. Recent visits are scoped to each vault; results page in batches of
  80. Open uses the current note/task identity, file results use Quick Look, and
  conversations have a read-only native preview. Ask actions prepare explicit
  context, preserve an existing prompt and require Send. Shared web/mobile chat
  events are searched without claiming ownership or changing files; unsupported
  or incomplete conversations remain protected and show a retry notice. File
  contents beyond Markdown and shared-chat continuation are pending. Registered
  external Markdown is included through its read-only native index.
- Full note text and frontmatter search, title/recent sorting, folder browsing,
  pinned/archive collections, duplication, folder moves, recoverable trash,
  note links, backlinks, attachment import, image paste, and Quick Look file previews.
- Native Library → Files with document notes, file search/sorting, and system
  Quick Look/Share. Add a portable vault copy, connect the original, or keep the
  connection plus a frozen backup. Notes keep the shared `zerus-file-*` metadata
  and `zerus-attachments` records. File cards support locating, replacing, copying
  into the vault and detaching without deleting the note, original or snapshots.
  Settings → File locations shares location names while keeping security-scoped
  folder mappings private to this device and vault. Copy/backup reads are limited
  to 50 MB; previews depend on system format support. Native Google Drive file-location mapping, account/folder browsing and bounded
  document downloads are implemented, with live verification pending the separate
  iOS OAuth client. Direct Drive-vault editing/sync remains pending.
- Library → External notes opens `.md`/`.markdown` files in place or creates a new
  Markdown file through Save to Files. Rich writing, full raw source (including
  YAML), native code/table editing, reload review and private recovery drafts
  preserve original file ownership. Reopening follows saved bookmarks; Stop
  tracking keeps the original and refuses to forget an unresolved draft.
  Explicitly choose the file's project folder to preview relative attachments
  and paste portable image/file resources there. Existing attachments remain
  untouched; new imports use unique filenames. External files are limited to
  10 MB of UTF-8 text; project attachments and clipboard packages to 50 MB.
  Reviewed vault copy/move rebases portable resources and retains interrupted
  move recovery. Unified search includes registered files and kept drafts.
  Migration of the older web external-file registry remains pending.
- Native Export note prepares PDF, editable Word (`.docx`) and self-contained
  HTML files from the current text, with optional visible properties. Review
  warnings, preview the artifact, save a copy directly through the system Files
  picker, or use the share sheet. Canceling the picker keeps the prepared file
  available; saving a copy leaves the original note and preview file intact.
  Export appears first in Note actions; clipboard and attachment commands are
  grouped into their own submenus.
  Local images are embedded; remote images remain labeled without network access.
  Internal metadata stays hidden. Embedded HTML is included as inert text, and
  internal/local file links retain labels with a warning about unbundled targets.
  PDF uses native Core Text pagination, including long table rows; Word contains
  editable headings, lists and tables. Temporary share files expire after two days
  and are cleaned on a subsequent export. Notes under 10 MB and image source bytes
  totaling up to 50 MB are supported, with images resized to at most 2400 pixels.
- Portable rich editing for headings, paragraphs, bold, italic, links, lists,
  quotes, nested lists, native checklist buttons, inline vault images, and
  tappable wiki links. Stable-ID links survive renames; ambiguous links offer a
  note picker, and missing links offer note creation or trash recovery.
  Fenced code has a native preview and a separate monospaced editor with
  language options; Cancel preserves the original, and prose edits preserve
  its exact fence and contents. Tables have native previews and a paged grid
  with cell editing, row/column controls, alignment and column widths, search,
  local undo/redo, linked notes, image previews, and spreadsheet paste. Cells
  use TextKit 2 for direct bold, italic, strikethrough, inline-code and link
  editing, with native undo/redo and an explicit source option. Existing images
  retain their captions and titles. Linked images, unknown inline HTML, shared
  reference-link syntax and user comments stay in source mode. Cells remain one line in the
  Markdown file; unsupported pasted attachments or formatting explain why they
  cannot be saved and can be undone. Done commits active keyboard composition.
  Pasting spreadsheet cells into prose opens the table editor for review.
  Untouched table bytes and the existing width metadata are preserved.
  Remaining unsupported Markdown and unknown comments use a native source
  editor to preserve their syntax. Rich
  prose is normalized to portable Markdown only after an edit; opening a note
  does not rewrite it. Unknown frontmatter is retained verbatim.
- Debounced coordinated saves, atomic writes, exact-byte outside-edit checks,
  and device-local recovery drafts. A conflicting save keeps the draft and
  never overwrites the outside version. Share Markdown to preserve a separate
  copy if a conflict requires manual reconciliation.
  Folder-definition migrations coordinate all affected files together, validate
  expected bytes before writing, and keep a write-ahead record under
  `.zerus/native-transactions/`. Scanning restores an interrupted, uncommitted
  batch before presenting notes. A committed record leaves later edits intact.
  If an interrupted batch conflicts with an outside edit, a native review blocks
  vault editing until it is resolved or another vault is opened. Compare the
  current, original and intended versions of each file, keep current by default,
  and confirm individual choices. Files and the record are checked again before
  applying anything. A recovery copy retains every reviewed version, including
  binary and absent versions; browse, preview and share them through Settings →
  Recovery copies. Confirmed recovery choices resume after process interruption;
  newer outside changes instead require a fresh review. Unknown recovery formats
  stay untouched. Unsaved editor drafts are paused during review and included
  in confirmed recovery copies. They remain available separately after recovery
  and cannot automatically replace a file version the user just chose.
- Native note properties in the information panel: text, URLs, numbers, dates,
  checkboxes and lists. Existing `.zerus/properties.json` definitions inherit
  through folder paths and child definitions override parent definitions.
  Values can be added, edited or removed without rewriting unrelated YAML or
  the note body. Reserved `zerus-*` fields are managed by the app; duplicate
  keys, nested YAML and unsupported property types remain read-only. Original
  metadata is available in a disclosure. **Folder definitions** manages text,
  URL, number, date, checkbox and list schemas. Parent definitions can be edited
  at their owner; child overrides retain their own values. Rename migrates
  applicable note keys, changing a list to single choice retains its first
  selection, and deletion removes values only when no parent definition remains.
  Migration previews identify the scope and confirm value-reducing changes.
  Unknown schema fields survive edits. Relations have dedicated definition
  controls in the same Folder properties panel.
- Native relation value editing opens from the information panel. Search and
  folder restrictions limit new targets; archived notes can be included explicitly.
  Existing links show note titles, with context actions to open related notes.
  Save previews the affected notes and commits both sides through one journaled
  transaction. Stable IDs and shared pair IDs are assigned when needed, existing
  inverse links survive, and hidden inverses stay hidden. Missing references are
  retained until explicitly removed; ambiguous references, duplicate IDs, complex
  values and stale files are protected. Unchanged schema bytes are checked without
  rewriting the schema. **Add relation** creates a folder definition; existing
  relations can be renamed, restricted to a target folder, limited to one or
  multiple notes, hidden on this folder's notes or hidden on related notes.
  Existing links survive narrower constraints. Rename migrates inherited keys
  and rejects collisions with child overrides. Deletion preserves child
  overrides and parent inheritance, removing obsolete reciprocal values together.
  A scrollable review lists affected note files before any definition save;
  Cancel leaves the files unchanged. Hidden definitions remain available in
  Folder properties so they can be revealed again.
- **Move to folder** reviews the new location and relation changes before saving.
  Populated relation definitions travel to folders that lack them; existing
  destination definitions retain ownership. Obsolete inverse values are cleared
  when a destination field changes the pair or becomes an ordinary property.
  Incoming legacy relation references gain stable targets before the move.
  Inverse folder restrictions broaden to the common ancestor when needed to
  keep the moved note eligible; the review explains those shared changes.
  Managed saved-link/file notes can be filed into ordinary folders without
  losing their metadata. Source removal, destination creation and paired/schema
  updates share one recovery journal and reject an occupied destination.
- Settings → **Review legacy relations** finds uncovered fields left by older
  folder moves. A proposal requires matching relation settings/pair identity
  and uniquely resolved eligible targets across the entire adopted folder scope.
  Unsupported definitions, conflicting future settings, unknown/ambiguous targets
  and competing ordinary property definitions are listed for attention without
  changing them. Review and Cancel are available before any repair is saved.
- Native Copy/Cut/Paste preserves editable prose, checklists, wiki links,
  fenced code, tables, and image references. The private clipboard snapshot
  carries original local attachment bytes; paste imports or reuses them under
  `assets/` and rebases references for the destination vault. Code examples and
  image alt text never become additional file-copy requests. Copy publishes
  current Markdown immediately while attachments load, and native paste waits
  for the latest copy to finish. Cut keeps the selection if attachments cannot
  be included, the note changes, or another note replaces the editing context.
  The selection limit is 50 MB including local resources.
- The main Paste action opens a small native sheet with UIKit’s system Paste control and reads its granted item providers. UIKit retains the HTML, companion RTFD and plain representations together; the SwiftUI menu PasteButton delivers only its preferred representation on the tested OS.
  HTML paste preserves supported headings, inline styles, links, nested lists,
  checklists, quotes, code, table captions/cells and images. Embedded image data
  and unambiguous image bytes supplied by companion RTFD representations become
  portable local assets; HTML file URLs are not read. Public web-image sources
  download during this explicit paste using an ephemeral session without cookies
  or account credentials. Four downloads run at once, with a 50 MB shared image
  budget, 30 seconds per request and 60 seconds for the image group. Scripts,
  stylesheets, embedded frames and CSS background resources are not executed or
  fetched. HTML is limited to 10 MB and 100 images; merged/nested tables and
  unavailable/invalid images leave the note unchanged. **Paste plain text** remains
  available. Source/document/selection/read-only/code-setting changes and closing
  the editor cancel or reject a late paste before it can replace newer writing.
- Standard RTF/RTFD styles and image attachments can be pasted from other apps.
  Copies also offer standard rich text when size permits, plus plain Markdown.
  Other apps may receive code/table previews as images through RTFD; choose
  **Copy Markdown** for editable Markdown text. **Paste plain text** matches the
  current editor style; source-mode paste retains the literal text. Markdown
  structures requiring source mode prompt for source editing before insertion.
- Deliberate note revisions through Note actions → Revisions: create, browse,
  preview without editing, promote an earlier version, move individual revisions
  to recoverable Trash, and restore them. Each change presents a native review.
  Earlier versions keep separate copies of file hubs, attachment records, and
  local Markdown/reference/HTML file destinations. The shared revision index
  retains foreign fields; current title and note properties survive promotion.
  Frozen files are published before the note/index in one coordinated, journaled
  change. Stale note/index/asset reviews and duplicate note identities block
  saving. Interrupted web pending records roll forward or back according to
  the actual note; conflicts retain all original data.
- Library → Recently Deleted collects discarded revisions across the vault.
  Preview and restore them, or review permanent removal of discarded versions
  and unused managed files. A second confirmation precedes deletion. Current
  note and surviving revision references protect shared assets, including
  escaped YAML/JSON paths. Unsupported or interrupted records block cleanup;
  changed note/index inventories, exact file bytes and vault activations reject
  stale reviews. Whole-note Trash keeps its versions together. Deleting the
  last active revision offers to move the whole note to recoverable Trash.
  Orphaned revision text can be shared; surviving orphan assets are retained.
  Deleted notes can also be reviewed for permanent removal with their revisions,
  automatic history and unused managed copies. Standalone image/file Trash,
  unindexed orphan-file cleanup and broader large-file performance remain pending.
- Automatic version history through Note actions → Version history. Ordinary
  note saves and coordinated note/property changes capture compatible UTF-16
  deltas, a checkpoint every third generation, and SHA-256 image blobs in the
  shared `.zerus/history/` layout. The note and its history share one journal.
  Native browsing includes timestamps, sources, alternate branches, Keep,
  labels, formatted/source/change previews, vault capture/retention settings,
  reviewed restoration, and twice-confirmed per-note history clearing.
  Restoration retains today's raw Zerus metadata, copies historical images to
  new assets, and keeps displaced current text recoverable even when automatic
  capture is disabled. Corrupt/missing chains or blobs disable affected restores;
  unknown records suppress automatic pruning. Labels retain foreign JSON fields.
  Metadata-only app state changes do not add history. Previously untracked notes
  acquire a stable identity on their first edited save.
- Settings → Version history manages capture and retention for the whole vault.
  Retention reviews include live, trashed and orphaned-note histories and apply
  immediately when confirmed. Kept versions and incomplete/unsupported families
  survive automatic pruning. Reviews list versions, known kept versions,
  unsupported records and unused image files, with a second confirmation before
  permanent deletion. Per-note clear, vault-wide clear and ordinary retention
  pruning collect globally unused history blobs in the same journaled change.
  Surviving histories, current/trashed notes, deliberate revisions, audit and
  recovery records, and local unsaved recovery drafts protect their references.
  Foreign JSON/YAML, escaped paths, percent escapes and base64 recovery content
  are inspected. New or changed files, notes, images, metadata, drafts and vault
  activations invalidate stale cleanup. Unrecognized opaque files and uncertain
  references keep image files protected. Clear removes version records and
  unused blobs; root audit receipts, live assets and other metadata remain.
  External-edit reconciliation and very large history performance remain.
- Native task creation, completion, priority, due dates, categories, lists,
  and supporting note selection. Existing unknown task JSON fields survive.
- Native streaming AI chat with explicit note context, cancellation, per-vault
  conversation history and prompt drafts, share/save-answer actions, ChatGPT sign-in, and
  API configuration using the existing Swift provider code. Credentials stay
  in Keychain. No conversation or note is sent until the user presses Send.
- Native Ask/Review/Edit agent body tools with selected-note, folder or entire-vault
  context, optional single-note writes, exact proposal review, atomic receipts,
  conflict-aware undo, persisted questions and resumable run journals. See
  [Native AI body tools](#native-ai-body-tools) for boundaries and remaining parity.

## Appearance, text size and preview layout

Native code, table and checklist previews respond to UIKit appearance and text
size changes while the note stays open. Code/table images also fit a changed
editor width. The writing surface and read-only revision/history previews share
this behavior. UIKit trait observation uses the system's color-affecting traits
alongside content size, legibility and display scale
([Apple documentation](https://developer.apple.com/documentation/uikit/uitraitchangeobservable-7qoet/registerfortraitchanges%3Awithhandler%3A)).
Only affected attachment images and TextKit layout are refreshed; the editor's
attributed text is retained. A refresh waits while keyboard text is marked and
resumes after commit. Checkbox symbols scale with body text, and touch targets
cover the enlarged glyph with a 44-point minimum. Restoring an Undo/Redo snapshot
uses the editor's current font metrics, preserving its formatting. Markdown
source starts with the current preferred size and uses a scalable monospaced
font. Read-only previews keep their selection through appearance updates and
only replace text when their content, mode or image objects change.

Two hosted UIKit/SwiftUI owners exercise the actual production writing and
read-only bridges. They verify rendered light/dark pixels, larger preview and
checkbox geometry, narrowed layout, full checkbox targets, preserved selection,
exact saved files through Undo/Redo, active marked writing and source-mode size
changes. The live owner uses an actual `NoteSession` and file, then commits the
marked text through the production finish-editing action. This verifies the
composition boundary, not delivery from every language keyboard. All **116 core
checks** pass without failures, skips or runtime warnings in
`NativeAdaptiveEditorFinalCoreVerified.xcresult`. Exported native attachment
images are retained in `adaptive-editor-core-attachments/`.

The final writing, code, revision and table UI journeys pass **4/4** in
`NativeAdaptiveEditorFinalUI.xcresult`, without failures, skips or runtime
warnings. Combined with the separate core result, **120 checks pass**; the other
twenty UI journeys were not all rerun. Nine inspected persisted files retain
the completed checklists, missing-image reference and stable note link; converted
literal code and its neighboring block; table formatting, both image destinations,
web/stable links, widths and last row; and restored revisions 1/2/3 with revision 2
current and the expected milestone bodies. Evidence is in
`adaptive-editor-persisted-files-proof.json`. These are final persisted-file
checks, without a complete before/after UI hash comparison.

The stale preview behavior was reproduced in
`NativeEditorPresentationBefore.xcresult`; read-only selection loss in
`NativeReadOnlyPresentationBefore.xcresult`; fixed-size source text in
`NativeSourceSizingBefore.xcresult`; and a 44-point target smaller than its
57-point accessibility checkbox in `NativeCheckboxTargetBefore.xcresult`.
Large-type table cells remain abbreviated previews; their footer can truncate
at narrow accessibility sizes. Broader VoiceOver, physical appearance/rotation,
language-keyboard delivery, large-document performance and complete small-phone
layout verification remain.

## Image previews

Local inline images load while the formatted note remains usable. The editor
shows **Loading images…**, retries failed reads up to five times, and then shows
an unavailable count and **Retry images**. Returning to the foreground retries
unavailable images without reopening the note. The waits before attempts are
0, 0.5, 1.5, 4 and 8 seconds; actual file-provider coordination can wait longer
than the fourteen seconds of scheduled delays. Remote image URLs are not fetched
and preview loading does not rewrite Markdown.

The reader coordinates the preferred confined file even when it is not yet
local. Apple's coordinated-read API can ask a provider to download a file before
reading it ([Apple documentation](https://developer.apple.com/documentation/foundation/nsfilecoordinator/coordinate%28readingitemat%3Aoptions%3Aerror%3Abyaccessor%3A%29)).
Only a missing-file error permits trying another resource location; access,
provider and size errors cannot silently substitute another folder's image.
Confinement is checked again after coordination, when the provider may have
materialized a file or alias. Bounded reads enforce a 50 MB source limit, and
background decoding creates thumbnails up to 1,400 pixels.

Preview reads use an independent reader so a waiting image download does not
hold the vault mutation actor or block an unrelated task save. The original
security scope remains alive until that read finishes. Cancellation and
workspace/document/request identities prevent late results from appearing in
another editor; an in-flight system coordination may finish after cancellation.
Changing document identity also invalidates the native editor's image rendering.

The current real-file and native writing checks are recorded below. Broader
cold-provider behavior, refreshing an already-loaded image replaced at the same
path, large image collections, physical performance and VoiceOver verification
remain. The phone check used an already-materialized image, without changing
user files or provider state.

## Creating code blocks

**Settings → General → Editor → Code blocks** controls new blocks on this device
and defaults to off, matching the mobile editor. When enabled, use the paragraph
menu, type three backticks with an optional language followed by Return, or paste
fenced code. The native code sheet supports Save, Cancel, language editing and
sharing. Cancel after a typed shortcut keeps the typed marker; undo/redo restores
the insertion and surrounding prose. Quotes, lists, inline code, links, source
mode and uncommitted keyboard composition do not trigger a top-level block.

When creation is off, existing blocks retain their native editor and exact
Markdown. Incoming fenced clipboard fragments remain ordinary text with visible
fences. Their heading, list and table markers are escaped when saved so they stay
literal after reopening. The shared inline renderer preserves straight quotes
and repeated dashes instead of applying typographic substitutions while parsing.
Manual Markdown source editing always preserves its syntax. A prepared
insertion cannot save into a changed document, a read-only note or after creation
is disabled; an asynchronous paste rejects a changed setting instead of silently
changing its interpretation.

Open an existing block and choose **Turn back into text** to replace it with the
current code draft as ordinary native text. Markdown-looking contents, spaces,
line breaks and Unicode remain literal rather than becoming headings, tasks,
links or tables; saving escapes the necessary Markdown characters and uses
character entities for literal code indentation and trailing hard-break spaces.
Literal entity spellings, dollar signs and backslashes survive reopening.
Language and
fence markers are removed. This works with code creation disabled, preserves
neighboring blocks and supports the note editor's Undo/Redo. A changed note,
document, source mode or read-only state rejects the retained sheet and keeps
its draft available for sharing. The action is offered for an existing block;
Cancel leaves a pending new block uninserted.

The real-editor conversion owner saves actual note files containing two
identical code blocks separated by a table. It checks the selected block only,
the current unsaved draft, empty content, Unicode, CRLF, indentation, literal
Markdown/entities, caret placement, exact saved Undo/Redo and reopening. A
retained sheet refuses another document, source mode, changed contents or
read-only editing. All **114 core checks** pass in
`NativeCodeToTextFinalCore.xcresult`, without failures, skips or runtime warnings.
The missing action was reproduced in `NativeCodeToTextBefore.xcresult`;
`NativeCodeToTextOwnerAndUI.xcresult` then exposed an unreachable bottom action
with the keyboard open. Moving it above the text field passes the expanded
code journey in `NativeCodeToTextOwnerAndUIVerified.xcresult` (3/3 with its two
core owners), before the final entity and escaped-backslash repair. The indentation
and entity cases failed before their respective fixes in
`NativeCodeToTextIndentBefore.xcresult` and
`NativeCodeToTextEntitiesBefore.xcresult`.

The final code, clipboard and table UI journeys pass **3/3**, without failures,
skips or runtime warnings, in `NativeCodeToTextFinalUI.xcresult`. Together with
the separate 114-core result this verifies **117 checks** for this candidate;
the other twenty-one UI journeys were not all rerun. The code action stays above
the keyboard, converts the current draft with creation disabled, supports native
Undo/Redo and preserves its source through relaunch. Six inspected saved files
retain the original separate Swift block/prose, converted literal draft and
neighboring Python block, pasted formatting/code/checklists/table widths, and
the edited table's formatting, web link, both image destinations, last row and
escaped stable note link. The toolbar-created table retains mixed-selection
formatting (`code-to-text-persisted-files-proof.json`). This is final persisted
file evidence, without a complete before/after UI hash comparison. Broader
physical mutation, IME, VoiceOver and other source-only constructs remain.

## Writing note links

In formatted note prose, type `@` or `[[` to search titles and paths. Suggestions
show each note's folder and use stable identities where available. Choosing a
note replaces the typed shortcut at the caret. Arrow keys change the selection;
Return chooses it and Escape closes suggestions. **Note actions → Insert note
link** also inserts at the caret or uses selected text as its label, retaining
its mixed bold, italic, strike and inline-code styles. The explicit picker remains
available in Markdown source mode. Selections must stay within one paragraph;
images, tables, code blocks and checklist controls stay intact and show guidance
instead of becoming link text.

**Settings → General → Editor → Note link shortcuts** disables typed suggestions
without disabling the explicit picker. This preference stays on the device.
Email addresses, existing links, inline code, code/table attachments, source mode
and uncommitted keyboard composition do not trigger suggestions. Closing a
suggestion keeps the text literal. Undo and redo preserve the original text and
chosen links; stale selections, workspace changes and replaced note targets
reject insertion.

Ordinary links retain `[[target|Label]]` storage. Labels with brackets, pipes or
mixed formatting use standard Markdown links with the shared `#zerus-note:`
destination. The native and web editors preserve their visible label, supported
inline formatting and single target. Reviewed moves upgrade legacy fragment
destinations to stable identities while retaining label source, other Markdown
bytes and local files.
Choosing a replacement for a missing target preserves these formatted labels too.
Prose and cell previews share inline decoding so formatted labels survive
reopening and source/rich switches. Cell storage keeps a formatted label as one
link, including inline code. CRLF prose and original pasted table bytes remain
intact. Table-cell shortcuts, broader input methods and physical typing verification
remain pending. Legacy filenames containing a pipe need a stable identity before they
can be selected for insertion.

## Collection sorting and filters

Collection and search excerpts show visible Markdown labels, image captions and
table text while keeping code examples literal. Labeled links show their label without the stored target or destination;
reference definitions and table-width comments do not become display text.
Saved links omit their standalone managed address from the excerpt while keeping
addresses within prose or code. This display-only parsing never saves a note;
search continues to index the original Markdown and destinations. Parsed excerpts
use a bounded memory cache keyed by exact file content. HTML-only blocks remain
source-only and do not contribute card excerpts.

Notes, Library folders, Pinned, Archive, Saved links and Files offer a native
**Sort & filter** sheet. Choose recent/oldest update, newest/oldest creation,
or title A–Z/Z–A; pinned notes stay first. Creation sorting uses the actual
filesystem birth date and falls back to the update date when unavailable.
Updated-date filters use today, the last seven local calendar days or the last
thirty. Folder collections include their children; selecting folders in the
filter narrows the result to those exact folders.

Property filters offer presence, one or more stored values, and all/any
combination across properties. Text, number and checkbox values remain distinct.
Date properties offer On, Before, After, inclusive comparisons and Between;
range endpoints can be entered in either order. Property choices are searchable.
Filters apply alongside the collection search and expose active counts and
clear actions. They are local to the open collection and reset on relaunch or
vault change; they do not rewrite notes or shared settings.

Files adds extension selection. Bare files use their own filesystem dates and
can be narrowed by folder, extension or name; add document notes before using
property filters on them. No bare file is presented as having note properties.
Bulk organization is described below; broader physical, accessibility and large-vault verification remains.

## Bulk organization and action history

Notes, Library folders, Pinned, Archive and document notes in Files support
**Select notes**, **Select all**, and a native Actions menu. Search, collection
or filter changes clear the selection. Unfiled saved links and bare files are not bulk
note targets; filed links can be organized with other notes. Review pin/unpin, archive/unarchive or changes to properties and
relations shared by the selected notes. Compatible list choices are intersected
across folders; Add/Remove apply to multiple-value lists and relations. A queued
property change can be removed with **Keep unchanged**.

Review lists the actual note files, before/after metadata, reciprocal relation
updates and skipped notes before Apply. Changes use one recovered, coordinated
transaction with exact-byte checks. An incompatible selected note is listed for
attention; it is not partially edited. Existing bodies, unrelated metadata,
foreign schema fields and document connections are retained. Stable note IDs
are assigned when needed so history can follow later moves.

**Recent actions** offers reviewed undo and redo, including after relaunch.
History is stored in `.zerus/native-bulk-history.json`, in the same transaction
as the note changes. The latest ten actions are shown for up to ninety days; expired records are
pruned when an action or transition is saved.
Undo/redo compares the fields being restored, keeps independent body edits and
later list additions, updates reciprocal relations, restores recorded dangling
references without creating their missing notes, and reports fields changed
later instead of overwriting them. Partial undo can be reviewed again. Property
definitions and stable note IDs remain available after undo. A stale note,
schema, action-history file or vault activation invalidates its prepared review.
Unsupported history formats are preserved and block bulk mutation.

## Parity still pending

The native target is not yet a complete replacement for every mobile feature.
Direct Google Drive vault editing/sync and live OAuth/account verification for
the native file-location browser,
relation-to-ordinary type conversion controls, standalone image/file Trash management,
automatic filename synchronization for arbitrary body/source heading edits, migration of existing web
conversation history, and the remaining agent tools/workflows described below still need native implementations. The
existing app remains the full-featured distribution until parity and physical
verification are complete. Browser previews show the existing React interface;
SwiftUI builds must be tested on an iPhone or in Simulator.

The [migration checklist](native-ios-parity.md) tracks the complete mobile scope
and verification still required before this preview can replace the existing app.
Snapshots for reference-style/HTML attachment
syntax also remain; the current rich clipboard handles supported inline links
and image destinations. Source editing preserves the other syntaxes.

## Current verification — 6 November 2026

The preceding task-draft candidate passes all **97 core checks** and the native
close/relaunch/resume/save/Cancel/discard/relaunch journey together (**98/98**)
in `NativeTaskDraftFinalCoreAndUI.xcresult`. The planning/supporting-note and
draft journeys also pass together in
`NativeTaskDraftRecoveryAndPlanningFinalUI.xcresult`, before only the final
vault-specific presentation identity guard. Actual task JSON and private draft
files confirm that discard removes the draft while retaining the original
saved title (`task-drafts-ui-persisted-proof.json`). The permissive malformed
field behavior was reproduced in `NativeTaskMalformedBefore.xcresult`; the
strict real-file owner now passes. Broader simultaneous-window, composition,
accessibility and physical task interaction verification remains.

The preceding bulk candidate passes all **94 core checks** in
`NativeBulkFinalCore.xcresult`. Its native selection/review-Cancel/pin/exact-action
undo/redo/property-edit/relaunch/property-undo journey passes in
`NativeBulkNavigationUI.xcresult`. Actual note files and action records confirm
that the bodies survive, the final pin remains applied, and the undone property
is absent (`bulk-ui-persisted-proof.json`). Missing-reference undo was first
reproduced in `NativeBulkMissingReferenceBefore.xcresult` and now passes through
the real-file owner. History reviews use native Back; Done only closes history.

The preceding bulk candidate passes all 94 core checks plus both bulk and
collection-filter UI journeys together (96/96) in
`NativeBulkFinalCoreAndUI.xcresult`, before the final missing-reference repair
and history-navigation refinement. The other seventeen UI journeys were not
all rerun for this batch. The preceding collection candidate passes 92 core
checks plus its property/search/clear/sort/folder/open/relaunch UI journey
(93/93) in `NativeCollectionFinalCoreAndUI.xcresult`. Actual note hashes were
unchanged through filtering (`collections-ui-persisted-proof.json`).

The current physical tester is **iPhone 11 Nox**, running iOS 27.2 with
Developer Mode enabled. The preceding adaptive-editor Release candidate (0.3.43/1)
passed actual signature, Keychain entitlement, profile membership, SwiftUI scene
and speech/microphone privacy-string checks. It installed as
`6B981AF8-72EE-4634-B822-B333B626BEA6` and remained open as PID 1900 across a
226.449-second process observation. Its 483-note vault reopened; the first
opening of “Collapse chart legend” displayed native headings, bold prose and
the original chart image, using already-materialized files. No phone notes or
preferences were changed and no AI requests were made. Device Hub keyboard
capture remained off. Both diagnostic inventories contain 27 entries and 22
report files, with no new or changed reports. Evidence is in
`adaptive-editor-installation-proof.json`; the exact app and matching debug
symbols are retained in `adaptive-editor-device-binary/`. Appearance, text size,
width, selection, Undo and marked-writing behavior are verified in hosted UIKit;
physical trait changes, rotation, language keyboards and broader accessibility
interaction remain pending.

The preceding code-conversion candidate (0.3.42/1) installed as `5123AC9E` and
remained open as PID 1871 across 131.876 seconds, with the same 483-note vault
and formatted chart/image. Its exact app, symbols and proof remain in
`code-to-text-device-binary/` and `code-to-text-installation-proof.json`.

The preceding image-loading candidate (0.3.41/1) remained open as PID 1866
across 171.815 seconds. On its first opening of “Collapse chart legend,” native
text and the chart were visible by 4.358 seconds after the tap. That is an
observed upper bound including navigation/capture, using a materialized image;
no physical cold-provider timing is claimed. Its exact app, symbols and proof
remain in `image-provider-device-binary/` and
`image-provider-installation-proof.json`.

The preceding code-creation/literal-text candidate (0.3.40/1) showed a chart
placeholder until the note was reopened. That observation motivated the image
loading changes below. Its evidence remains in
`code-literal-installation-proof.json` and `code-literal-device-binary/`.

The preceding settings candidate (0.3.39/1) verified that General fits the
physical iPhone 11 with code creation off, note-link shortcuts on and the original
date/default-folder preferences unchanged. Its proof and exact app/symbols remain
in `code-preference-installation-proof.json` and `code-preference-device-binary/`.

The preceding permanent-note-cleanup candidate's physical evidence remains in
`note-trash-light-installation-proof.json` and `note-trash-light-device-binary/`.
Its existing trashed-note review appeared within 5.209 seconds of the tap
(an observed upper bound, not an exact preparation benchmark), and Cancel kept
the note in Recently Deleted. The earlier 0.3.36 CPU warning is retained and
explained under Permanent note cleanup below.

The preceding readable-preview candidate's physical evidence remains in
`readable-preview-installation-proof.json` and
`readable-preview-final-device-binary/`. That candidate verified twenty Chart
search results with readable excerpts, query retention after keyboard dismissal,
and native headings, bold prose and the original image in “Collapse chart legend.”

The preceding inline-preservation candidate's physical evidence remains in
`inline-preservation-installation-proof.json` and
`inline-preservation-final-device-binary/`.

The preceding caret/suggestion and General/keyboard candidate evidence remains
in `links-final-installation-proof.json` and
`general-final-installation-proof.json`. Those earlier phone checks also verified
the link picker/Cancel and General layout with the original preferences.

The preceding dictation/readiness candidate's evidence remains in
`voice-ready-installation-proof.json` and `voice-ready-device-binary/`. The user
chose to test spoken dictation later; recognition, model downloads and capture
interruption/route handling remain pending. The collection-performance evidence
remains in `collections-cpu-installation-proof.json` and
`collections-cpu-device-binary/`.

The preceding native-agent candidate installed as `47D1FD59` and remained open as
PID 1486. Its formatted “Collapse chart legend” note and local image loaded, but
it produced a CPU warning: matching saved debug symbols identified repeated
NotesView sorting and frontmatter parsing inside sort comparisons on the UI thread.
That evidence motivated the collection changes described below. Its evidence is
retained in `agent-installation-proof.json` and `agent-verified-device-binary/`.
Native AI controls and permissions also loaded on the preceding candidate. The
current phone shows a user-configured model; no live-provider request was performed
by the agent. No phone notes were edited or sent to AI.
Earlier physical checks in this guide refer to the previous iPhone 18 Pro Max tester.

The preceding tester-switch candidate passes all 91 core checks in
`NativeIPhone11NavigationCore.xcresult`, including duplicate-ID rejection and
retained-draft/navigation lifecycle protection. The navigation candidate before
only the missing/ambiguous-note feedback and duplicate-ID case passed all 91
core checks plus the extended rename, native Back/Forward and Close UI journey
(92/92) in `NativeNavigationFinalCoreAndUI.xcresult`. History remains per
presentation; durable navigation, cursor and scroll restoration and broader
physical input checks remain pending.

The native suite includes **116 core checks** and twenty-four automated native
UI journeys (**140 unique checks**). The current adaptive-editor core suite
passes **116/116**, with no failures, skips or runtime warnings, in
`NativeAdaptiveEditorFinalCoreVerified.xcresult`. The hosted appearance and
selection owners are described above. Its writing, code, revision and table UI
journeys pass 4/4 in `NativeAdaptiveEditorFinalUI.xcresult`, giving **120 passing
checks across the two results**, with no runtime warnings. The other twenty UI
journeys were not all rerun.

The preceding code-conversion suite passed its 114 core checks in
`NativeCodeToTextFinalCore.xcresult`. Its final
code, clipboard and table UI journeys also pass 3/3 in
`NativeCodeToTextFinalUI.xcresult`, giving **117 passing checks across the two
results**, with zero runtime warnings. The other twenty-one UI journeys were
not all rerun for this candidate.

The preceding image-loading batch passes its 113 core checks plus the expanded
writing journey together: **114/114**, with no
failures, skips or runtime warnings, in
`NativeImageProviderFinalCoreAndUI.xcresult`. The other twenty-three UI journeys
were not all rerun for this batch. The writing journey verifies unavailable-image
feedback and Retry images while the editor and completed checklist remain
available. Its final note and created link files retain the expected prose,
checklists, stable link and original missing-image reference
(`image-provider-persisted-files-proof.json`). These are final persisted-file
checks, without a complete before/after UI hash comparison.

Four real-file owners cover a delayed image appearing inside the same hosted
production editor without note changes, a preferred image materializing during
coordination before another folder's fallback, saving an unrelated task while
an image provider waits, and rejecting an outside symlink introduced during
coordination. The preferred-file check also rejects a file above 50 MB without
substituting the fallback. The first three reproduced their failures before
their fixes in `NativeImageRetryBefore.xcresult`,
`NativeProviderImageReadBefore.xcresult` and
`NativeImageWorkerBlockingBefore.xcresult`. These use actual files and Foundation
file presenters; they do not establish behavior for every cloud provider.

The preceding code-creation/literal-text batch passes its 109 core checks plus
the code-editor and clipboard journeys together:
**111/111**, with no failures, skips or runtime warnings, in
`NativeCodePreferenceLiteralVerifiedCoreAndUI.xcresult`. The other twenty-two UI
journeys were not all rerun. The preceding General/clipboard rerun passes 2/2 in
`NativeCodePreferenceSettingsClipboardUI.xcresult`, before only the final literal
text preservation repair. General scrolls to vault creation when many saved
vaults exist, and the clipboard journey closes active Notes search before
returning to Settings.

The real-editor owner verifies exact saved files for existing-block editing with
creation off, typed/toolbar admission, stale document/settings protection and
incoming native/plain fenced paste. `NativeDisabledCodeLiteralBefore.xcresult`
first reproduced headings/tables being reinterpreted after reopening disabled
code examples. Escaping ordinary block markers and disabling parser typographic
substitutions now retain the literal heading/list/table text, quotes and dashes.
The expanded native UI journey verifies the setting across relaunch, existing
block editing when off, typed creation and real keyboard undo/redo. Actual saved
code and clipboard fixtures retain surrounding prose, literal code, both created
blocks, checklists and table widths after relaunch
(`code-literal-persisted-files-proof.json`). These are final persisted-file checks;
no complete before/after UI file-hash comparison is claimed.

The preceding cleanup batch passes its 108 core
checks plus the expanded Recently Deleted journey together: **109/109**, with
no failures, skips or runtime warnings, in
`NativeWholeNoteTrashLightFinalCoreAndUI.xcresult`. The other twenty-three UI
journeys were not all rerun for this batch. Four real-file cleanup checks cover
exact deletion boundaries, retained shared/external/recovery assets, stale
inventories and vault activations, cancellation, and unreadable unrelated
metadata. The navigation owner reproduces an external Trash move followed by
restore and immediately opens/saves actual revisions through the restored editor.
The expanded UI journey restores notes/revisions, cancels cleanup, confirms
permanent deletion of its synthetic note, relaunches and reopens the surviving
note's two revisions. Actual persisted Markdown, index and automatic-history
files confirm the final state (`note-trash-light-persisted-files-proof.json`).

The preceding readable-preview batch passed 104 core checks plus collection
filtering and search/relaunch journeys together (**106/106**) in
`NativeReadablePreviewsFinalCoreAndUI.xcresult`, with no failures, skips or runtime
warnings. The scan owner first reproduced exposed link destinations and altered
code, then a malformed saved-link address that hid its prose; all now retain
readable text and unchanged files. Original destinations remain searchable.
Actual saved search and collection files retain their Markdown, destinations,
properties and body text (`readable-preview-persisted-files-proof.json`). The
collection journey explicitly chooses Inbox for its fixtures, leaving the saved
per-vault default intact.

The preceding inline-preservation batch reruns all core checks plus the expanded
writing, clipboard and table journeys:
**107/107 pass**, with no failures, skips or runtime warnings, in
`NativeInlinePreservationCoreAndUI.xcresult`. The other twenty-one UI journeys
were not all rerun for this batch. Actual saved files retain the selected label's
bold subset after subsequent writing, source/rich switches and relaunch, correct
target identities, unchanged target bodies, literal disabled shortcuts and the
restored preference (`inline-preservation-prose-persisted-proof.json`). Table
and clipboard note files retain formatting, literal code, linked image
references, widths, rows and surrounding prose
(`inline-preservation-table-clipboard-proof.json`).

The real-editor owner now exercises mixed bold/code selected aliases, actual
saved bytes and undo/redo, plus refusal of attachment and cross-paragraph
selections without changing the view or publishing a save. The cell/GFM owner
checks one target and visible styles for mixed and standalone inline-code labels.
A source/rich round-trip owner first reproduced lost typography inside link
labels; prose and cells now share inline decoding. A full-byte paste check also
protects original CRLF prose/table content and inserted paragraph boundaries.
The earlier green UI batch's persistence check missed the style loss; its actual
file evidence is retained in `selected-link-persistence-loss-before.json`.
The strengthened UI assertions and current saved-file evidence cover that loss.

The current web suite passes **670 checks**, with one opt-in live-provider
evaluation skipped because its evaluation configuration is absent
(`inline-preservation-web-proof.json`). The existing Markdown owner includes
native table links with inline-code labels. Direct Device Hub Down/Return input
was verified on the preceding editor source; the automated journey uses the
visible iOS Return key because the named XCTest Return event did not reach the
app in its captured trace. Broader physical typing remains pending.

The preceding General/keyboard batch passes all 102 core checks plus General,
denied-dictation and search UI journeys (105/105), with no failures, skips or
runtime warnings, in `NativeGeneralFinalCoreAndUI.xcresult`. Its actual two-vault
date/default-folder evidence remains in `general-preferences-persisted-proof.json`.
The preceding voice batch retained three invalid-frame warnings; the General
keyboard changes remove those warnings in its exercised flows. The exact rename
candidate passes all 89 core checks and its review/Cancel/commit/continued-edit/
relaunch/incoming-link journey together (90/90) in
`NativeRenameFinalCoreAndUI.xcresult`.

The preceding saved-vault batch passes all 86 core checks
and its create/switch/rename/Cancel/remove/relaunch UI journey together (87/87)
in `NativeVaultRegistryFinalCoreAndUI.xcresult`. Actual files in both local
folders retain their separate notes after removal and relaunch. Only the final
location subtitle wording changed after that run; the exact signed device
binary shows the readable iCloud Drive location. The other fifteen UI journeys
were not all rerun for this batch. The preceding cell-composition candidate passes all 84 core
checks in `NativeCellsFinalCore.xcresult`; its expanded table journey passes in
`NativeCellsPreservationVerified.xcresult`. The final image-path regression also
passes in `NativeCellNormalizedImagePaths.xcresult`. The preceding broad cell run
passed 87/87 core/table/export/clipboard checks in
`NativeCellsFinalCoreAndUI.xcresult`, before the linked-image admission guard and
normalized image lookup were added. The other twelve UI journeys passed on
earlier candidates and have not all been rerun on this one. Actual Simulator
files confirm formatted cell text, both linked-image destinations, column
widths, note links, remaining rows and surrounding prose survive saving.

The current signed cell candidate F7EA6F1C is installed and launched as PID
1358 from its exact executable. Physical launch, note rendering and device
report checks are recorded in `cells-installation-proof.json`. Editing cells was
exercised on disposable Simulator notes; no physical user-note edits were made.
The preceding direct-save export candidate 54CDEB4E was also physically verified
with the 483-note library and export form. Its exact hash and file-save evidence
remain in `export-files-installation-proof.json` and `export-files-copy-proof.json`.

The preceding search candidate B6A6681F is physically verified: PID 1304 matched
its installed executable, the native app opened the 483-note All notes view,
Search and its filter sheet loaded, and Collapse chart legend rendered formatted
prose and its image. No user-note mutation or provider send was confirmed. Both
recursive device report inventories were identical at 410 entries. The newer
file-library candidate 7A158E99 also passed physical launch verification as PID
1308, with Files and an existing document card loaded and 410 unchanged reports.
Its exact executable hash is recorded in `files-installation-proof.json`.

The preceding native suite included 49 core checks and nine automated native UI
journeys (58 unique checks). The revision Trash candidate passed all 49 core
checks and its new Recently Deleted UI journey. The preceding revision candidate
passed its then-current core suite and the main notes/tasks and revision UI
journeys; the other eight UI journeys have not all been rerun on this candidate.
The earlier full regression passed all 40 core checks and six UI journeys. The relation journey then passed with all 40 core
checks after fixing focus and the Save control during review preparation.
Earlier verification milestones follow. The schema migration and journal recovery changes
passed all 21 core checks; the schema UI journey passed after the final
presentation and asynchronous-completion checks. The saved-vault retry change
passed all 22 core checks and the main notes/relaunch/task UI journey. The
simulator journeys used a stable dark
theme. A real UIKit clipboard regression verifies spreadsheet paste takes
priority over an accompanying image, and source paste retains the plain text.
The editor checks cover literal code and exact fence preservation, including
Windows line endings, embedded Markdown, longer fences, and unfinished blocks.
The native UI journeys cover code editing, Cancel/Save, toolbar code creation,
straight quotes, the caret when switching to source, note creation, toolbar
checklists, Return/exit, relaunch/search, image formatting, checkbox toggling,
missing-note creation, navigation, task capture, Library, and Ask. Actual
simulator vault files are inspected for saved code, checkbox states, paragraph
boundaries, and stable-ID note links. The table journey also verifies paging,
cell edits with literal pipes, column insertion/undo, native toolbar creation,
and missing-note creation from a cell. Inspection of the actual vault files
confirmed all 22 fixture rows, column settings, escaped cell content, unchanged
surrounding prose, and the escaped stable-ID link stored inside the table.
The clipboard journey verifies copying a whole formatted note, pasting into
another note, undo/redo, and reopening the persisted code/table blocks. Native
file-boundary checks cover exact original image/PDF bytes across vaults,
percent-encoded file names, image alt text and code literals, changed assets,
unsupported clipboard versions, and incomplete resource payloads. Cut/paste
checks also cover changed note contexts, unavailable files, newer copy intents,
and pasting while a copy is still preparing its attachments.

Property checks read real inherited definitions and save through `NoteSession`
to actual vault files. They cover parent/child overrides, hidden relations,
typed values, quoted punctuation in lists, block-list replacement, case-insensitive
keys, duplicate/complex YAML refusal, comments, CRLF and `...` closing fences.
The real UI journey covers text Save/Cancel, the actual native switch control,
multiple list choices, removal, relaunch and reopening. Inspection of the final
saved file confirmed `Ready: true`, two separate list choices including a comma,
the removed value’s absence, and the unchanged note body. Visual inspection
confirmed neutral property labels, readable secondary values and the checked
indicator. The first UI iteration exposed an unstable presentation from a List
section; the property sheet now belongs to the inspector’s navigation container.

Schema verification exercises actual multi-file writes, preflight conflicts,
prepared/committed recovery records, and preservation of outside edits. The
definition migration checks cover parent rename and single-choice conversion,
child overrides, deletion with inheritance fallback, target-key collisions,
stale schemas, unrelated unsupported schema data, and unknown definition fields.
The native UI journey creates a shared list, selects two values, renames its key,
converts it to one choice with confirmation, relaunches, and deletes the
definition and value. Inspection of the final Simulator files confirmed the
original body, removal of both old/new property keys and definition, and no
pending transaction records. Stacked panels have distinct accessibility
identifiers, and completion assertions wait for the changed UI state.

The current Release candidate includes native properties, folder definitions,
startup feedback, file-provider path validation, native recovery review, relation
value/definition editing, relation-aware folder moves and reviewed legacy repair. It
passed signature/profile verification, installed and launched on the iPhone 18
Pro Max running iOS 27.0.1,
and reopened the saved cloud vault with 485 notes visible. The path regression
previously rejected a valid aliased root when its recovery directory did not
exist. Validation now resolves the nearest existing ancestor before appending
missing components, retains the scoped URL for IO, and blocks outside or broken
symlinks. Directory scanning supports an aliased selected root. A real-file
regression demonstrated the original rejection before the fix; multi-file
commit and journal recovery also run through an aliased root.

Recovery checks use real files to reject stale note bytes and changed journal
bytes before any version is replaced or copy is created. They exercise all
three choices, binary-file removal, preservation of original/current/intended
bytes, and vault activation after resolution. An independently persisted version-2
record simulates termination after only one confirmed choice was written;
scanning finishes the other choice while retaining later outside changes for
review. Unknown protocols remain intact. A delayed-draft regression failed
before the repair because flushing replaced the confirmed file version. It now
passes: ordinary IO is suspended during a pending recovery, sessions pause their
autosaves, and confirmed recovery copies retain the unsaved draft separately.
All 24 then-existing core checks and the main create/edit/relaunch/search/task UI
journey passed with the recovery changes.

A native Simulator interaction reviewed original text, selected an original
version for one file while keeping another current, canceled without changing
files, then confirmed and reopened the vault. Inspection of the actual files
and recovery JSON confirmed the selected results and retained alternatives.
Settings navigation opened the saved recovery copy and its individual versions;
a separate Simulator display fixture verified the retained-draft preview. No
recovery fixture was placed in the physical cloud vault.

Successive process checks matched the exact installed app and found it still
running beyond launch. Device reports remained unchanged (134 before and after,
with no new crash or Jetsam report). Physical verification used the existing
cloud vault without adding test fixtures or changing its note contents. The
startup screen and reopened notes list were captured for visual inspection. A
read-only physical interaction opened “Collapse chart legend,” the note from
the reported source-mode screenshot, and confirmed native heading/bold rendering
and the inline chart image. Its information panel displayed the inherited
properties and original modification date.

The relation candidate passed all 27 core checks and both the main workspace and
property UI journeys. Three new real-file checks cover reciprocal linking and
unlinking, inverse collisions and occupied values, hidden inverses, folder
restrictions, stable IDs, unknown references, child overrides, and stale note,
schema and identity-set rejection. They also check unchanged schema bytes and
modification dates when the schema is only a transaction read dependency.
A native Simulator journey selected a folder-restricted target, included archived
notes, canceled a save preview without writing, confirmed linking, relaunched and
reopened the selection, then unlinked. Inspection of both actual fixture notes
confirmed matching pair IDs and reciprocal stable references after linking,
exact original note bytes after unlinking, and no pending transaction journal.

The exact signed relation candidate launched on the physical iPhone; repeated
process checks matched its installed executable. It reopened the 485-note cloud
vault and rendered the reported note's formatted text and inline chart image.
The native Epic picker loaded targets from Work/Epics and was canceled; the
information panel retained the original modification date and empty relation.
No fixture or relation change was saved in the physical cloud vault. Device
reports remained at 134 before and after this interaction, with no new crash or
Jetsam report. This check preceded the relation-definition candidate below.

Relation-definition checks use real files to create a child override, migrate
its reciprocal values to a distinct pair, remove it with parent fallback, and
delete a parent while retaining child overrides and their edges. Other checks
rename CRLF property keys, retain multiple existing targets after narrowing a
definition, propagate inverse visibility, preserve unknown schema metadata and
reject child-name collisions and outside file/schema changes before any write.
All 30 core checks passed. The existing list-definition creation, rename,
single-choice conversion, relaunch and deletion UI journey passed, as did the
new relation-definition journey: review/Cancel, create, search/select/save a
target, rename, relaunch and delete. Inspection of both saved Simulator notes
confirmed retained bodies and removal of both old/new relation keys; the final
schema contained neither definition and no pending transaction remained.
The journey exposed a system search overlay that hid Save and covered the
result row. A fixed native search field below the navigation bar now retains
the actions and dismisses the keyboard on selection; the full journey passes
with that repair. A separate review regression failed before the fix for
uppercase `.MD` names and now passes, so those changed files appear in review.
The final signed candidate installed and launched on the physical iPhone. It
reopened the 485-note cloud vault, and successive process checks matched the
exact installation. Physical navigation opened Folder definitions and the
existing Epic relation editor, showing Work/Epics, multiple-note selection and
both visibility controls. The inspection was canceled without saving; the note
retained its original 3 November modification date and empty relation values.
No fixtures were added to the physical vault. The crash-report directory stayed
at 134 entries before and after, with no new crash or Jetsam report.

Relation maintenance passed all 33 core checks and the expanded native relation
journey: create/review/Cancel/search/link/rename, review/Cancel a folder move,
confirm a new folder, relaunch, reopen the carried relation, and delete its
copied definition. Inspection of actual Simulator files confirmed the original
source path was absent, both bodies survived, paired values were cleared on
deletion, the original inverse definition remained and no journal was pending.
Managed saved-link filing, occupied destinations, exact CRLF preservation,
incoming legacy paths, scope-wide stale-file checks, unsupported definitions and
conflicting unknown settings are covered at the real file boundary. The managed
source and inference regressions failed before their repairs and pass afterward.

A separate Simulator interaction opened Settings → Review legacy relations,
reviewed the inferred definition and inverse-scope change, and canceled with
the schema and all four fixture files byte-identical. Confirming then saved
stable reciprocal targets while retaining the existing inverse, hidden flag,
unknown metadata and both bodies. The unresolved fixture stayed unchanged and
remained listed for attention. Fixture data was confined to Simulator.
The final vault-switch guard also passed all 33 core checks and the main
create/edit/relaunch/search/task journey. Cross-scene and all asynchronous
mutation paths still need the broader multi-vault verification in the checklist.

The signed maintenance build installed and launched on the iPhone, reopened the
485-note cloud vault, and remained running in successive process checks matching
its exact installed executable. A physical interaction opened a move preview
for “Collapse chart legend” and canceled it; no move or repair was applied to
the physical vault. The final destination-list cleanup was also installed and
checked on the phone: internal managed folders are excluded and progress is
shown while a move prepares. The note still opened in Work/User Stories with
native formatted text and its chart image. Device crash reports stayed at 134
before and after the final candidate, with no new crash or Jetsam report.
These checks do not establish full feature parity or replace the remaining
physical interaction and accessibility checks in the migration checklist.


Folder moves now compose relation maintenance with exact-range body-link updates.
Inline Markdown destinations, reference definitions, table links and HTML URL
attributes are rebased to the same existing vault files. Incoming Markdown note
paths follow the new location, including links in trashed notes using their
original logical folder. Unambiguous legacy body wiki links receive stable IDs
while retaining their labels and table escaping. Attachments stay in place;
no image or PDF bytes are copied or rewritten. Markdown file links also open the
native note editor when their target is a vault note.

All inspected note files are checked again at confirmation. Resource resolution
is checked under file coordination before any note writes, including changes
from root fallback to a newly created note-local file. Read dependencies use
reading intents and do not inflate recovery records with unchanged note bodies.
Missing outgoing files and ambiguous active wiki links stop preparation with a
readable explanation. Code, escaped examples, comments, literal HTML, image alt
text, labels, captions, reference titles, CRLF and table spacing are preserved.
Foundation source positions are converted from UTF-8 line/column coordinates
because its direct NSRange conversion can shorten a whole run to one code point.

Three real-file move checks cover exact source preservation, portable incoming
and outgoing destinations, literal percent escapes, root/local file collisions,
reference and HTML destinations, unchanged attachment bytes, trashed-note bases,
ambiguous/missing targets and stale review dependencies. The initial move tests
failed before the file-aware planner; the literal-label regression also failed
before the source-range repair. CSS resources, embedded wiki-file syntax and
heading-fragment navigation still need explicit handling; these checks do not
establish support for every source-only Markdown extension.


The move-resource candidate passed all 36 core checks. The main native
create/edit/relaunch/search/task journey passed. The expanded relation
review/Cancel/create/search/link/rename/move/relaunch/delete journey passed on a
fresh Simulator. An earlier run exposed that Create a folder could be buried
below a growing folder list; the controls now precede that list. A separate
accumulated-fixture run lost an offscreen schema-management control before
reaching the move. Clean-Simulator proof avoids treating that fixture-dependent
failure as evidence that the later move had passed.

A separate Simulator fixture verified standard Markdown links open the native
note editor. After confirming a folder move and relaunching, an updated incoming
Markdown path opened the moved note, its note-relative image rendered, and its
rebased text attachment opened in Quick Look with the original contents.
Inspection of the actual files confirmed the exact expected source and incoming
link edits, unchanged foreign YAML/project/image/file bytes, the old note path
absent and no pending journal. All fixtures stayed inside Simulator.

The signed candidate reopened the physical 485-note cloud vault and rendered
“Collapse chart legend” with headings, bold text and the chart image. The initial
file-aware preparation spent too long probing unrelated cloud resources; it now
checks only the moved note's assets and incoming Markdown-file destinations in
other notes. A read-only CLI export profiled all 627 available archived/current
notes at about 1.15 seconds of Markdown parsing on this Mac; the temporary raw
export was then removed. The optimized physical move review completed and was
canceled without saving. Successive checks matched the installed executable,
and crash-report listings stayed at 134 entries with no new reports. The final
review label uses “Changes” because it can include body links as well as
relations. Physical move confirmation, large-cloud performance and broader
accessibility remain part of the outstanding migration verification.

The final label-only polish compiled, passed signature/profile verification,
installed and launched on the iPhone. Its exact executable matched the new
installation; the saved vault and formatted chart note reopened, and the final
crash listing still contained 134 reports with no additions. The functional
move checks precede only that wording change.


### Workspace switching and native chat history

Every activation receives a runtime workspace identity, including reopening the
same folder. Retained notes, task editors, schema reviews, imports and delayed
callbacks cannot target a later activation. Already-started file operations
retain their original coordinated worker and security-scoped access. Editor
saves now let all callers await the in-flight save and flush later edits before
returning. Three real-file checks cover identical paths/IDs across roots, a
coordinated create held during a switch, and a flush while an earlier save is
held. These checks reproduced the prior failures before the changes.

Native conversations and unsent prompts are stored separately for each full
vault URL under Application Support/NativeChats. Starting a new conversation
keeps a recoverable history entry; previous conversations can be reopened or
shared. An earlier unscoped native conversation requires explicit restoration
into the chosen vault. Unreadable history and prompt files stay preserved.
Windows viewing the same vault observe one live chat model. This transitional
local format does not yet import the web app's vault conversations or provide a
stable registry across root moves/app-container migration. Attachments and live
provider verification remain pending. No provider request was sent in this check.

The chat file-boundary check covers same-named folders at different full paths,
explicit legacy restoration, shared-window state, stale writers, unknown
formats, and prompt persistence. Manual Simulator interaction also verified
archive/reopen, context selection and switching from A to an empty B conversation
with no inherited selection. The B-only unsent prompt survived process restart
and appeared in the native field; its actual UTF-8 file bytes also matched. All
temporary legacy-history fixtures were restored.
On iPad Simulator the Settings action opened another workspace scene; two scene
sessions were retained. All windows intentionally share the active vault.
Broader simultaneous-window editing and switching checks remain.

Evidence: NativeWorkspaceIsolationFullRegression.xcresult records 40 core and
six passing UI journeys plus the initial relation review failure.
NativeWorkspaceIsolationReviewAndDraft.xcresult records the subsequent 40 core
checks and passing relation journey. The signed final candidate passed profile
and signature verification and was installed at installation 98C2550B on the
physical iPhone. Launch PID 1205 matched that exact executable. It reopened the
485-note cloud vault and displayed the formatted chart note. Crash-list and
process evidence is in artifacts/native-ios/workspace-final-*.json.

The final before/after recursive crash listings each contained 404 entries with
no new or changed reports. The installed process remained PID 1205 through the
chart-note check. The native previous-conversations sheet also opened on the
physical phone without changing user notes or sending any provider request.


### Deliberate revisions

The revision UI journey creates a note, cancels a review, creates revision 2,
edits its body, previews and promotes revision 1 into revision 3, trashes the
current version, verifies fallback, restores it and reopens after process
relaunch. NativeRevisionsFinalVerification.xcresult passed the 44 then-existing
core checks and both this journey and the main note/search/task journey.
Subsequent metadata and workspace checks add a fifth revision storage test:
JSON numeric attachment ownership must remain unsupported, and a quoted YAML
string must not mark an original file as managed. Both coercions were reproduced
before the strict fixes.
NativeRevisionsRecoveryAndWorkspace.xcresult passed all 45 core checks, including
both interrupted-web-commit recovery branches and rejecting a retained review
after A→B→A. NativeRevisionsOwnershipAndCommitFinal.xcresult verifies all 45
core checks after the strict ownership fixes and publishing snapshots before the live note
and revision index. These storage changes follow the passing UI run; they do
not change its controls.

The asset checks use real files and inspect exact bytes in independent old and
current snapshots, including PDF/image/attachment records, foreign JSON/YAML,
CRLF source, HTML and reference-style destinations. They also mutate asset and
index bytes after review to prove no partial note change can occur. Source
analysis now uses the pinned Swift Markdown tree, reconciling cmark inline
positions against paragraph bounds when leading reference definitions were
removed. Foundation remains responsible for rich display. The older folder-move
literal/Unicode/asset-binding checks pass with the same source analysis.

A separate Simulator-only fixture created two revisions with independent text
and image copies. Quick Look opened revision 1’s frozen text attachment with
its original content. Saved-file hashes and the two independent directories
are recorded in revision-files-ui-proof.json; the screenshot is
revision-frozen-attachment-quicklook.png under artifacts/native-ios.
The iPhone candidate reopened the cloud vault, loaded its revision list, and
showed a formatted read-only current revision without changing the user’s note.
The app’s broader native migration remains incomplete.

The final signed revision candidate (including strict ownership handling and
asset-first commit order) passed signature/profile checks, installed at
installation 25CDF991 and reopened the 485-note cloud vault. Its running process
matched that exact installation. Before/after recursive crash listings each
contained 406 entries with no additions or changed reports. The earlier signed
revision candidate also loaded the cloud note’s revision list and read-only
formatted preview without saving. The final UI file inspection confirms
revisions 1/2/3, current revision 2, restored revision 3, and separate preserved
bodies in revision-ui-persisted-proof.json.


### Revision Trash and whole-note recovery

NativeRevisionTrashCoreAndUI.xcresult passes all 49 core checks and the new
Recently Deleted journey: create two versions, discard one, inspect and cancel
permanent cleanup, restore the discarded version, then trash and restore a
whole note with its sole version. Actual saved Markdown and index bytes confirm
both versions survive, revision 2 stays current, and the restored sole-version
note retains its body without creating an unnecessary index. The proof is
revision-trash-ui-persisted-proof.json under artifacts/native-ios.

Four real-file checks exercise permanent revision cleanup, foreign JSON retention,
protection of incoming relative links and current/orphan assets, whole-note
revision grouping, late notes/index/pending/unsupported records, and stale vault
activation reviews after A→B→A. The first cleanup run exposed escaped YAML paths
that were not recognized as live file references. Decoding semantic metadata
before reference checks fixed it; the regression now verifies current managed
file bytes and orphaned current files survive. Physical user notes are never
permanently cleaned during verification. That earlier revision-cleanup UI check stopped before confirmation; the isolated
real-file fixtures verify deletion and reopening.

The preceding revision-only Trash candidate installed at AB6F88B8-4A99-4B47-B784-44234988FC04
and remained running as PID 1239 from that exact installation. The iPhone
reopened its saved 485-note vault. Library → Recently Deleted showed existing
trashed notes, Restore controls, and the empty discarded-revision state. No
user notes were changed. Before/after recursive device report listings both
contained 406 entries with no new or changed crash/Jetsam reports. Evidence is
revision-trash-device-proof.json and revision-trash-{processes,crashes-before,
crashes-after}.json under artifacts/native-ios.


### Permanent note cleanup

Library → Recently Deleted offers **Delete permanently** for one note and
**Review all deleted notes** for the current Trash. The review lists the notes,
deliberate revisions, automatic versions and unused managed file copies. Cancel
keeps everything restorable; a separate confirmation commits the reviewed
removal. The native transaction also removes the selected notes’ revision indexes
and automatic history, including their unused history images. Shared files and
files referenced by surviving notes, history, revisions or recovery metadata are
kept. External original connections, ordinary inline assets, existing recovery
copies and organization/AI action history are outside this cleanup; the review
explains those boundaries. Unrelated orphan history images remain for the
separate history cleanup. Invalid/shared identities, unsupported or pending
revision records, changed notes/metadata/assets and a different vault activation
reject the review before any deletion.

Preparation can be canceled without opening a stale review afterward. A per-note
review inspects history images named by the selected notes, and skips unrelated
version reconstruction. Note-only cleanup reads its own automatic records and
inventories paths without decoding unrelated metadata; removing managed files
still requires full surviving-reference analysis. An owner check proves that
unreadable unrelated metadata does not prevent note-only cleanup and remains
unchanged. The first physical candidate (0.3.36) produced a CPU warning while
scanning every vault history blob before filtering it. The retained
`note-trash-preparation-cpu-before.ips` and matching dSYM identify that path.
The final 0.3.38 review appeared within 5.209 seconds on the same existing trashed
note, and cancellation preserved it. Its physical timing, exact signed binary
and unchanged diagnostic inventories are recorded in
`note-trash-light-installation-proof.json`. This does not establish global
history-cleanup or large managed-file performance.

The file worker rechecks exact reviewed bytes and note/history/metadata inventories
inside coordinated writes. New revision files also invalidate the review. A
committed cleanup retires every path alias of a deleted editor and clears queued
external-history capture for those identities. Standalone image/file Trash and
unindexed orphan assets still require native management.

### Automatic history

The history writer and reader use the shared web schema: UTF-16 delta offsets,
SHA-256 content hashes, a checkpoint every third generation, source/origin IDs,
parent branches, kept flags, labels and image blobs. The four real-file history
checks passed in NativeHistoryCoreVerified.xcresult alongside all 49 earlier
core checks. Fixtures include web-created Unicode deltas, broken parents,
foreign record fields, independently frozen image bytes, disabled capture,
settings, pruning, Keep, stale permanent deletion, and A→B→A review rejection.
Later checks add duplicate record identities and restoration at a one-family
retention boundary.

NativeHistoryRetentionOwnerBaseline.xcresult demonstrated that restoring exactly
at a checkpoint boundary with a one-family limit lost the displaced current text.
The writer now retains that version's dependency chain during restore and can
upgrade coordinated read dependencies into reviewed history deletions.
NativeHistoryRetentionFixedCoreAndUI.xcresult passes all 53 core checks and both
the automatic-history and deliberate-revision UI journeys. Final verification
following preview and duplicate-identity presentation changes is recorded below.

The history journey creates and edits an actual note, marks a version Keep,
labels it, inspects source and changes, cancels a restore review, restores it,
relaunches, and cancels permanent clear review. UI clear is never executed
against user notes. Permanent deletion is verified only in temporary real-file
fixtures. Earlier screenshots are in artifacts/native-ios/history-ui-attachments.
Historical Markdown images open from their frozen blobs and are restored into
new assets; live image bytes remain untouched. At that milestone, blob garbage
collection and vault-wide history clearing were pending, and retention settings
applied on later saves. The subsequent vault-wide management work below adds
reviewed immediate pruning and shared-blob collection.


Independent inspection of the first UI fixture found its label persisted but
Keep remained false. NativeHistoryKeepUIBaselineSequential.xcresult reproduces
that touch interaction failure by reopening and asserting the retention choice.
The compact switch was replaced with a labeled pin button with a 44-point
minimum height and explicit accessibility state. The metadata review now shows
both the proposed label and Keep choice. The strengthened journey checks the
state immediately and after review/reopening. history-ui-persisted-proof.json
independently verifies the saved `kept: true`, label, restored current note,
recoverable displaced text, every content hash, and every UTF-16 delta from the
actual Simulator vault. Earlier UI passes alone did not establish the Keep
interaction. NativeHistoryFinalCoreAndUI.xcresult's notes/tasks run was affected
by an overlapping Simulator session and is not used as passing evidence.


NativeHistoryKeepFinalCoreAndUI.xcresult passes all 53 core checks and the two
final native UI journeys (automatic history and notes/relaunch/tasks). The
corrected signed app installed at 94C4806E-BF3D-4FB3-AEB2-7ED5DFF612D0 and ran as
PID 1256 from that exact executable. It reopened the saved 485-note cloud vault,
rendered the chart note normally, and loaded four existing Desktop/External
history entries with checkpoint and incomplete indicators. A desktop-created
checkpoint opened in the formatted native read-only preview. No history change
or note edit was confirmed on the physical device. Both recursive report
inventories contained the same 406 entries with no changed or new crash/Jetsam
reports. Evidence is in history-device-proof.json, history-keep-processes.json,
history-crashes-before.json and history-keep-crashes-after.json. Final UI
screenshots are in history-final-ui-attachments.


### Vault-wide history management

The shared history decoder and checkpoint-family retention policy now serve both
ordinary saves and vault-wide reviews, including orphaned and trashed notes.
Blob validation is cached within each decoded history rather than rereading the
same image for every version. Settings includes a native Version history screen
with counts, capture/retention controls, unused-image cleanup and vault-wide
clear. Per-note settings and clearing use the same coordinated owners. Settings
reviews without deletions do not remove unrelated unused images. Any actual
version/file deletion requires another confirmation in the native UI.

NativeHistoryManagementStorageFinal.xcresult passes 57 core checks. Four new
real-file checks cover immediate cross-note/orphan/Trash pruning, kept/shared/
live/revision/recovery/audit images, opaque/unsupported data, clearing, stale
files and vault reactivation. Later extensions also cover per-note clear while
another history shares its image, complete vault clearing with live references,
and protection of unsaved local recovery drafts. A new draft created after a
review invalidates it before deletion. A no-op cleanup validates dependencies
without writing an empty recovery journal. NativeHistoryManagementDraftsAndUI
records those extended core checks and the native journeys.

The first Settings UI run tapped the label area of a system switch and left its
value unchanged. Manual inspection confirmed that tapping the switch thumb
changes the pending choice. The automated journey now targets the thumb inside
the observed switch element; no preference is written until the review is
confirmed. The journey cancels deletion at the second confirmation. Permanent
storage operations run only against isolated temporary test fixtures, never the
physical user's vault.


NativeHistoryManagementDraftsAndUI.xcresult passes all 57 core checks and both
history UI journeys. NativeHistoryManagementKeptDeltaFinal.xcresult subsequently
passes all 57 core checks with the additional kept-delta fixture: pruning keeps
the unkept parent checkpoint needed to reconstruct the kept delta. Complete
clearing frees only unused blobs, while per-note clearing retains an image used
by another history. history-management-ui-persisted-proof.json verifies the
actual Simulator note remains intact, its two versions remain, all 50 vault
records survive canceled clearing, and capture is enabled with unlimited
retention after relaunch. Final screenshots are in history-management-ui-attachments.

The signed candidate installed at D16F43B8-ECA7-4160-B15E-A15908A6FF0F. iOS denied
its launch because the phone was locked; unlock was requested. No new physical
launch or crash-report verification is claimed yet. Installation details and
the executable hash are in history-management-installation-proof.json.


### Changes made in other editors

While the app is active, the shared vault refreshes every 20 seconds, as well as
on returning to the foreground and on pull-to-refresh. A successful scan records
observed Markdown changes as shared-format `external` history. Notes without an
identity receive one in the same coordinated transaction; their external body
and foreign frontmatter remain intact. Existing matching history tips are
reused, and unique note identities follow moves. Ambiguous identities suspend
capture rather than joining unrelated histories.

A cold launch can compare the current file with its newest readable persisted
version. Edits made between scans cannot be reconstructed individually. A failed
capture retains its observed baseline for retry and shows a warning in history;
it still displays the latest external file. Disabling capture or explicitly
clearing history cancels queued captures. Local dirty drafts remain on the
device and require resolution before replacing an externally changed file.
Clean open editors follow unique moved notes, including their recovery-draft
location. Results from a scan superseded by a save or vault switch are ignored.

Image recovery uses frozen historical blobs. If an earlier image was never
captured, its version is incomplete and cannot be restored; its preview does
not substitute the current image. Large-cloud-vault scan performance and broader
multi-window interaction remain to be evaluated.


`NativeExternalHistoryCoreAndUI.xcresult` records 64 passing core checks and the
two history UI journeys. `NativeExternalHistoryFinalVerifiedCore.xcresult`
passes all 64 core checks after repairing an unavailable-image preview regression.
The new storage scenarios use actual file writes to model outside editors,
including legacy/foreign YAML, reverts, renamed/duplicate identities, cold
launch, disabled capture, failed-history retry after a native save, explicit
clear, frozen/missing images and dirty draft preservation. A real coordinated
read held across a vault switch verifies that the old scan cannot publish or
capture into the new workspace. The missing-image assertion failed before its
owner repair; the final run verifies that a preview cannot use the current
image when the historical image is unavailable.


The live Simulator refresh check opened `External refresh QA.md`, changed only
that isolated fixture on disk while its editor remained open, and observed the
new bold text and list without navigation or typing. Native history showed an
External delta and baseline checkpoint; the formatted baseline contained the
original text. Current Markdown and exactly two records remained intact after
another polling interval. `external-history-ui-proof.json` records the actual
saved bytes and entries. No restore was confirmed.

The final signed build installed as
7403C156-A3EE-41CD-A49C-B9FDE77265E6. Launch was denied with CoreDevice 10002 /
FBSOpenApplicationErrorDomain 7 because the physical iPhone was locked. Its
signature/profile checks and executable hash are recorded in
`external-history-installation-proof.json`. Physical launch/process/crash-report
verification remains pending; no new physical stability claim is made.


### Native saved links

Library → Saved links provides a searchable native collection, recent/title
sorting, archive visibility and an Add action. A saved address opens in the
system browser only when explicitly selected. Creating an existing normalized
address reopens its existing note. The editor shows the address in a separate
native card; editing it preserves the title, notes, foreign YAML, code and
reference definitions. Unsafe or duplicate addresses are rejected. Full-note
Markdown/rich copies include the canonical address, while selection copies
contain only the selected text.

Unfiled links live in the shared managed directory and are excluded from All
notes and normal folder lists. Filing uses the existing move review, creates a
readable unique filename and retains link metadata, so the note remains in both
its folder and Saved links. Link creation, editing, filing, recoverable Trash
and restore keep `.zerus/links.json` and Markdown files in one coordinated
journal. Reviews retain the exact index bytes and reject outside changes.
Unsupported index containers block mutation without replacing their data;
unfamiliar array entries are preserved. Trashed managed links are discoverable
for restoration, and malformed managed-note metadata remains visible as a
preserved note rather than disappearing from the interface.

The new UI journey exposed two issues before installation: autolinks were
mistaken for HTML and forced source mode, and URL reinsertion changed the
visible text's trailing newlines during typing. Source detection now uses the
Markdown parser for HTML nodes, and URL transport preserves the editable buffer
exactly. Actual HTML remains in source mode. Storage checks include LF/CRLF,
partial text without a trailing newline, empty/headingless notes, foreign index
entries, duplicates, stale reviews and A→B→A form isolation.


`NativeSavedLinksFinalCoreAndUI.xcresult` passes all 69 core checks and the new
native journey. Five saved-link owner checks cover storage, shared-index
lifecycle and stale reviews, live-buffer invariants, workspace isolation and
actual Markdown/RTF clipboard contents. The existing rich-text owner additionally
checks native autolinks and lossless HTML fallback. An intermediate clipboard
test over-fulfilled a shared expectation; its new full-note case now has its own
completion tracking and passes independently without changing production behavior.

Screenshots in `saved-links-final-ui-attachments` were visually inspected. The
actual final file is `Bookmarks f35ecb/Native link f35ecb.md`; it retains both
identities, the updated canonical URL once, and intact personal notes. Its old
managed file and index entry are absent, while unrelated index entries remain.
`saved-links-ui-persisted-proof.json` records those saved bytes after relaunch.

The exact signed candidate installed as
5A423B98-B697-4EF3-804F-9376096A6431. Its executable hash, SDK, signature/profile
checks and physical pending status are in `saved-links-installation-proof.json`.
Launch was denied with CoreDevice 10002 / FBSOpenApplicationErrorDomain 7 because
the iPhone was locked. The existing unlock request remains pending.


### Native task planning

Tasks now supports scheduled dates separately from deadlines, quick scheduling,
list creation/renaming/removal, a renamed default list, categories and reviewed
category removal. Removing a list returns its tasks to the default list without
removing the tasks or supporting notes. Sorting includes creation/completion
recency and title order; filters include list, category and priority. Today
follows the scheduled date. Completed tasks use the shared seven-day local
calendar cutoff, with an explicit option to show older tasks. A foreground
minute timeline keeps day-based views current.

Supporting notes open in a native editor above the task; closing the note
returns to its task details. Unavailable note references remain unless explicitly
unlinked. Task deletion requires confirmation and leaves supporting notes
intact. The task title has an explicit keyboard-dismiss control, and Quick
Schedule has a full-width tap area.

All task mutations share one per-vault write queue and read the latest file.
Forms carry their original field values: edits to different fields merge, while
conflicting edits are rejected with the draft still open. Completion timestamps
are retained when another field changes. Explicit reload reads current storage,
not just cached tasks; draft sharing is available before discarding local input.
List/category removal reviews check affected membership again before writing.
Foreign envelope, list and task fields and unsupported task records remain
preserved. Migration from the legacy task array persists its derived categories
in the shared object format so the web client retains them too.


`NativeTaskPlanningFinalCore.xcresult` passes all 73 checks, including four new
planning owners and the extended task-save owner. The final run uses the other
already-booted Simulator and a separate build directory while Xcode collects
verbose diagnostics on the QA Simulator. It additionally verifies that an actual
migrated task file contains its categories for the web client. The test schema
and runtime data are isolated synthetic fixtures.

`NativeTaskPlanningReloadCoreAndUI.xcresult` passes the existing note/task UI
journey; its planning journey revealed the narrow menu hit area. After that
repair, the planning journey passed in
`NativeTaskPlanningFullRowCoreAndUI.xcresult`. Its suites completed successfully
at 19:58:39 UTC; Xcode's `simctl diagnose --timeout=600` postprocessing finished and the result bundle reports 74 passing tests. Final
screenshots are exported in `task-planning-final-ui-attachments`. No new native
crash report appeared in the Mac's diagnostic-report directory during that run.
The earlier test-only clipboard expectation crash is from 19:30 and is unrelated
to this task-planning run.

`task-planning-ui-persisted-proof.json` verifies the actual task after relaunch:
scheduled 6 November, due 5 November, high priority, its custom list and category,
completion timestamp, and one intact supporting note. The note was opened and
closed through the native task workflow. The exact signed candidate installed
as AF39C935-33CE-47EC-9DEA-923D5DED7EEC; its hash, SDK and physical pending status
are in `task-planning-installation-proof.json`. iOS denied launch because the
phone is locked, and crash-report retrieval timed out. The existing unlock
request remains pending.


## Unified search verification

`NativeSearchVisibleFiltersCoreAndUI.xcresult` completed with 77 passing checks:
all 76 core tests plus the native search journey. After strengthening the
identical-path/ID vault-isolation fixture and folder/date/short-word cases,
`NativeSearchFinalCore.xcresult` passes all 76 core checks again. Tests exercise
actual vault files and the background model: title/body/diacritic/fuzzy ranking,
typed scalar/list property filters, archived and trashed notes, unsaved drafts,
older completed tasks, files, links, pagination and scoped recent visits. Shared
chat fixtures cover owner-generation conflicts, amendments, archive/restore,
tombstones, unknown lifecycle events and private-history isolation. Unavailable
or linked chat data leaves ordinary search usable and preserves original files.

The UI journey creates a note and task, finds both from a body term, opens the
native editor, filters Tasks, opens and cancels task editing, resets filters,
prepares explicit AI note context while retaining the existing prompt, and
relaunches to verify recent visits. Xcode's method selector requires the trailing
`()` for this individual UI test. The first UI passes exposed an unfocused test
field, missing prompt-keyboard dismissal and Filters hidden by iOS's active
search navigation. The final flow includes a native keyboard Done control and a
filter row that remains available while typing. Actual isolated Simulator files
confirm intact note prose/task fields, persisted prompt/recent visits and no
messages sent. See `search-ui-persisted-proof.json` and
`search-final-ui-attachments/` under `artifacts/native-ios/`.

The Release app passed the native platform/toolchain preflight, signature and
physical-device provisioning checks. Installation initially failed with a
transient remote-device connection error; refreshing details and retrying the
same signed binary installed it as B6A6681F-FFD4-44A0-9630-189B366691EC.
`search-installation-proof.json` records the exact executable hash. After the
user unlocked the phone, the same candidate launched as PID 1304 and remained
open. Native Search and its filter sheet loaded; Collapse chart legend rendered
formatted prose and its image. Recursive report inventories remained identical
at 410 entries. No user-note edit or provider send was performed.

Search still needs broader large-vault, VoiceOver, Dynamic Type and iPad
interaction checks. It indexes file names/paths rather than extracting file
contents. External connections and continuation/migration of shared chats
remain with their respective parity work. Preparing a search context does not
send a prompt or claim ownership of shared conversations.


## Native document files verification

Library → Files now uses the shared file-note frontmatter and attachment records.
Document notes can keep a managed vault copy, connect an original, or connect it
and keep an independent backup. Notes and copied bytes are committed together
through the existing recovered transaction. Replacement assigns a new connection
identity while retaining the note identity and old snapshots; detachment removes
only the connection fields. Fresh note, location and source bytes are checked at
confirmation. The external file lease grants a coordinated read only; all writes
remain confined to the selected vault. Copy/backup has a 50 MB limit.

File locations keep portable shared IDs/names in `.zerus/file-locations.json`.
Each device maps those IDs to Files folders privately; usage includes Trash and
blocks removal until the connection is no longer referenced. Foreign records
and fields survive renaming; unsupported formats remain protected. File/folder
bookmarks retain their scope through Quick Look, sharing and copying. Root
bookmarks recover private file mappings after a uniquely identified vault folder
moves. Broader durable vault identity across copies/container migrations remains
separate from the saved-vault switching list: AI histories still use their existing root-scoped storage.

Four owner-level real-file checks cover copying and byte preservation, external
connections and independent snapshots, stable note/new connection identities,
private-vault separation and folder relocation, location names and foreign JSON,
Trash usage, stale reviews, mapped-folder symlink escapes, external-read versus
write confinement, and A→B→A rejection. Clipboard checks also cover frozen backup
URIs and primary Markdown documents: their actual bytes travel in the native
fragment, the copied destination is portable, and Markdown document resources
remain opaque hidden attachments rather than newly indexed ordinary notes.
The two regression extensions failed before their production clipboard repair.
Generic document embedding in other apps' RTFD, HTML-only clipboard import and
reference/HTML attachment snapshots remain pending.

`NativeFilesFinalCoreAndUI.xcresult` passes 80 core checks and both the main
create/edit/relaunch/task and rich clipboard/undo/relaunch UI journeys: 82/82.
The separate preceding clipboard core bundle passes 80/80. A manual native
Simulator journey used disposable source documents: preview → Add notes → Save
created a portable file note, its typed prose persisted, and a second document
kept an original connection plus a frozen backup. Changing the source then
previewing both showed updated original text and unchanged backup text. Native
File locations added a shared name and mapped a folder through the system picker.
A later replacement kept the same note and backup; canceling detach retained
exact note bytes, and confirmed detachment kept the body, snapshot and both source
files. `files-ui-persisted-proof.json` records final note content, paths and backup
hashes. These mutations were confined to Simulator fixtures.

The Release build passed platform/toolchain initialization, signature/profile and
SwiftUI scene verification. It installed as 7A158E99-7372-427E-9471-06816D9CC14B on
the iPhone 18 Pro Max, launched and remained open as PID 1308 from that exact
executable. The physical cloud vault showed 483 All notes; Files listed existing
shared document notes, and an existing presentation's file card explained that
its desktop-only connection needs locating on this device. No user note or
mapping was changed. Before/after recursive reports were identical at 410 entries.
`files-installation-proof.json` records the executable hash and process evidence.
Editable external Markdown connections, direct Drive access and broader file
format, cloud performance, iPad and accessibility verification remain pending.


## Native note export verification

Note actions → Export note prepares PDF, Word and self-contained HTML from the
current note text, including unsaved text, without changing the note. Properties
can be excluded; internal frontmatter and non-rendering HTML comments (including
table-width metadata) stay hidden. Wiki links become human-readable labels only
in actual prose; fenced/indented code and escaped examples retain their literal
text. Large ordered-list starts remain intact. File and internal-note links,
missing/remote images, unsupported property values and inert HTML have explicit
warnings where their target or appearance cannot be included completely.

PDF uses Core Text and UIKit's native PDF renderer: A4 pages, selectable text,
working web-link annotations, headings and formatting, images, code, lists and measured
native table cells. Text and oversized table rows continue across page breaks;
short table headers repeat. DOCX writes standard OOXML with editable headings,
numbered/bullet lists, tables, hyperlinks and PNG image parts. A stored ZIP writer
uses standard CRCs and package relationships; no web runtime or office process
is needed. HTML escapes content, embeds local PNG images and applies a restrictive
content policy. Active HTML is shown as inert text; it cannot execute or fetch
remote assets. Quick Look previews all three formats before system sharing.

Exports run from a vault-bound snapshot. Image reads are coordinated, path
confined and security scoped; asynchronous results cannot cross A→B→A
activations. Export limits are 10 MB of note text and 50 MB of source images, resized
to a maximum of 2400 pixels. Generated filenames preserve complete Unicode
characters within 180 UTF-8 bytes. Share files are stored outside the vault in an
app-private temporary cache; files over two days old are cleaned on a later
export. Canceling preparation rejects the late result and cleans its artifact.

Three owner-level checks inspect actual generated files using platform PDF/XML
parsers and an independent zlib-backed ZIP reader. They cover editable structures,
embedded image bytes, property exclusion, unsaved text, unchanged vault files,
unsafe links, unavailable/escaping/remote images, long Unicode filenames and old
vault provenance. The pagination fixture contains 40 long paragraphs and 180
unique table-cell markers over 14 pages; every marker survives exactly once
across line wraps. Independent Python ZIP CRC/XML validation and Apple Word
import/Quick Look also succeed, and rendered pages were visually inspected.
The large-counter, literal-code and hidden-comment extensions each failed before
their corresponding production repairs. The Unicode filename case also failed
before the UTF-8 byte limit was added.

The native UI journey creates a disposable note, prepares each format, opens and
closes all three system previews, and relaunches to verify intact note text. Its
expanded Save to Files journey dismisses the system picker without saving, then
saves PDF, Word and HTML copies. Actual destination files match their app-private
prepared originals byte for byte and retain those hashes after relaunch; the
source Markdown also remains intact. `export-files-copy-proof.json` records
paths, sizes and hashes. All 83 core checks and the expanded export and clipboard
journeys pass together (85/85). The final property-setting rerun also
passes; it taps the actual nested system switch and verifies the off value,
then previews and saves HTML. The earlier broad-row tap did not reliably change
the setting. Format changes now wait for their selected value before preparation.

Export is first in Note actions; clipboard and attachment commands have their
own submenus. Direct saving uses SwiftUI's native `fileExporter` with conditional
file representations for the selected format. Each representation supplies the
actual sanitized filename. The UI journey caught an empty preferred-filename
exception before that handoff was corrected. It uses the sheet-dismiss gesture
to cancel: this Simulator exposes a generic “Cancel” accessibility element over
the Files options menu, which does not dismiss the picker. No test-only
production hooks are used. The generated cache files remain available for
preview and sharing after a destination copy is saved.

The preceding export build installed as 54CDEB4E and remained open as PID 1341. Device
Hub showed the 483-note library, the formatted chart note and its local image,
and the native export form with format and property controls. The form was
closed without preparing or sharing user content. Before/after report
inventories stayed identical at 410 entries, with no new crash or Jetsam report.
`export-files-installation-proof.json` records the executable hash and physical
launch evidence. Earlier export proof remains in `exports-installation-proof.json`.
Actual file saving and the three system previews were exercised on disposable
Simulator notes; physical export generation/sharing, broader multilingual/layout,
very large image collections and exported-document accessibility checks remain.

## Native rich table-cell verification

Table cells use a dedicated TextKit 2 editing surface within the SwiftUI cell
form. Bold, italic, strikethrough, inline code and web/note links are available
through the keyboard toolbar. Mixed selections apply one consistent style;
Return dismisses the keyboard, and Done commits marked keyboard text before
publishing the cell value. Cell and table undo/redo remain separate. Switching
between rich and source presentation clears the cell's presentation-specific
undo stack. Column alignment and width controls remain available.

Untouched cells keep their original source. Ordinary images retain their exact
markup, including distinct captions/titles for repeated image URLs; encoded
asset keys also resolve filenames containing spaces. Linked images remain in
source mode to preserve both their image and destination URLs. Shared
reference-link syntax, unsupported HTML and user comments also stay in source.
Pasted paragraph breaks, unknown attachments and unsupported underline formatting
produce a recoverable explanation and block Done until corrected or undone.

Portable formatting uses Markdown where its delimiter rules permit it and
balanced, attribute-free `strong`/`em`/`s` tags for arbitrary adjacent style
boundaries. Native previews and PDF/Word/HTML exports interpret those safe inline
tags; other HTML stays protected or inert. The existing editor preparation
accepts the generated tags unchanged. A GFM-to-HTML/XML check covers all 64
adjacent bold/italic/strike combinations, literal backticks and wiki examples,
Unicode image positions, repeated image captions, link titles, asset lookup and
unsupported paste protection. Newly constructed tables also emit their initial
column-width metadata; existing table bytes and marker spacing stay preserved.

The expanded native UI journey composes bold text, literal inline code and a web
link; edits a linked image in source mode; retains column widths, other rows and
surrounding prose; exercises paging/table undo and linked-note creation; and
applies Bold to a mixed selection in a new toolbar-created table. Actual saved
files are inspected in `cells-ui-persisted-proof.json`. The mixed-selection and
linked-image admission cases failed before their respective production fixes.
The final cursor-position correction belongs to the UI test: it explicitly
selects the field before replacing its contents. The image-key case also failed
with a placeholder image before normalized asset lookup was added.

The exporter owner fixture now contains adjacent safe HTML styles in a table.
Actual HTML elements and Word run properties retain those styles, and the
selectable PDF text contains no literal formatting tags. Both pages of the
updated rich PDF fixture were rendered and visually inspected in
`artifacts/native-ios/cells-export-visual/`. Broader physical cell editing,
multilingual keyboard/VoiceOver coverage, late cloud-image refresh and very large
cell performance remain to be verified.

## Saved vaults on this device

Library → Vaults (also available in Settings) remembers folders opened through
Files and offers named local vault creation. Each local vault has its own folder
under Zerus Native/Vaults in Files. The existing on-device Zerus folder and the
last saved Files bookmark remain compatible; a successful first reopening adds
that folder to the list automatically.

Switching flushes current note saves, refuses to leave unresolved drafts, and
keeps the current workspace if the next folder is unavailable. Each successful
activation renews its bookmark. Saved entries are ordered by their last opening;
a friendly name changes only the list, never the folder or its Markdown files.
Selecting an alias of an already registered folder retains its registration.

“Remove from list” has a Cancel/Remove review and never deletes vault contents,
attachments, revisions, history or private connection records. Removing the
currently open entry leaves its session and drafts open, but prevents automatic
reopening on the next launch. Add it again from Files when needed.

The list and bookmarks stay in private app preferences under a versioned native
registry. Unknown formats remain byte-for-byte intact with a readable warning;
manual Files access remains available. This list does not migrate separate AI
history storage across arbitrary root moves or merge independently copied
vaults. Broader file-provider relocation, simultaneous-window and VoiceOver
verification remain in the parity checklist.


Saved-vault verification on 5 November: the final signed build installed as
2608D5A3-F1A2-4B23-9066-C45527200033 and remained open as PID 1363. The existing
483-note vault reopened, and Library → Vaults displayed its migrated current
entry with the readable iCloud Drive subtitle. No physical user-note edits or
vault changes were performed. Both crash-report inventories matched exactly at
411 entries. `vaults-installation-proof.json` records the executable hash,
preflight/signature/profile/scene checks and exact process; the separate
`vaults-persisted-ui-proof.json` records the synthetic Simulator note bytes.


## Reviewed note renaming

Open a note’s action menu → Rename note. Enter a title, choose whether to rename
its Markdown file, then review the exact destination and affected notes before
confirming. Cancel preserves the review’s original files. The native editor
stays open after confirmation and continues saving to the new path.

The same transaction maintains supported incoming wiki/Markdown/HTML links,
reciprocal relation values, saved task path references and automatic title
history. Existing labels, foreign YAML, body bytes outside the title/link edits,
attachment files and deliberate revision snapshots remain intact. Stale task
bytes, added/renamed notes, outside edits and occupied destinations reject the
review before note files change. Unknown task-link formats require keeping the
filename or resolving their representation first.

Titles support one line up to 250 characters. Suggested filenames replace
unsupported cross-platform characters, avoid hidden/reserved names and stay
within a conservative UTF-8 length. The review shows the actual spelling;
case-only title changes retain the existing file spelling. Managed saved-link
and document records keep their internal paths. Direct source/body heading
changes update the displayed title while retaining the current filename.
This is the supported native behavior: ordinary writing keeps paths stable;
use Rename when the filename should change, with its destination and dependent
references reviewed together. It differs from web mobile's automatic filename
synchronization.

Three owner-level checks exercise actual transactions, metadata/link/task byte
preservation, independent revision assets and automatic history, stale-task
refusal, protected literal examples, managed paths, filename collisions,
portable names, Unicode separators and a retained editor’s next save. The new
native UI journey verifies Cancel, commit, editing after rename, relaunch and an
incoming legacy wiki link. Actual saved source/incoming bytes and the absence of
the old path are recorded in `rename-persisted-ui-proof.json`.

The final signed candidate installed as
E847D3AB-8167-4DA8-8C16-615C9D4E0EF1 and remained open as PID 1368. The physical
483-note vault reopened; its chart note rendered formatted text and its image.
The native Rename form loaded the original title/path with Review enabled, then
was canceled without typing or saving a rename. Both device report inventories
matched exactly at 411 entries. `rename-installation-proof.json` records the
exact executable hash, signature/profile/scene verification and running process.
Broader physical mutation, provider, keyboard/accessibility and simultaneous
window checks remain.


## Task drafts on this iPhone

Tasks → Drafts collects unfinished new tasks and changes to existing tasks.
Every field edit is kept immediately in private application storage, separate
from the shared `.zerus/tasks.json`. Close, swipe dismissal, backgrounding and
restart retain the draft. Save writes the task to the vault; Discard draft has
an explicit confirmation and leaves the shared task unchanged. Share draft
includes the complete recoverable values and original baseline as JSON.

Opening a saved task resumes its newest draft. Stored drafts open in a full-screen
editor, with draft status and recovery actions beside the title. Drafts also lists other retained
versions, including tasks that have since disappeared from the shared file.
Independent outside changes rebase into recovered forms; conflicting values
remain protected by the fresh-file task writer. If saving fails, the form can
reload after a reviewed discard, or stage and save a separate new task. A
persisted copy identity recognizes a shared write interrupted before private
cleanup, preventing a repeated recovery action from creating another copy.

Two windows changing the same stored draft keep separate versions. Stale
cleanup and discard cannot remove a newer version. Draft storage follows a
saved vault registration when its folder moves and recognizes the same folder
when reopened after removing its registration. Other vaults keep separate
private draft collections. These drafts do not sync across devices. Future or
malformed draft records are preserved for sharing; inaccessible draft storage
shows a warning so an open task can still be saved or shared explicitly.

Known task fields with unsupported JSON types remain protected in the shared
file. Reused identities with a different creation timestamp and newly assigned
lists/categories removed since the form opened reject the save. Existing
foreign JSON and unchanged legacy string values stay intact. Broader physical
multi-window, keyboard composition, accessibility and cloud-folder relocation
verification remains in the migration checklist.


## Native AI body tools

Ask is read-only. Review stages exact Markdown proposals and saves after native
approval. Edit may save requested changes to one ordinary note; multi-note
batches wait for review. The shared provider managers supply structured tool calls
and streaming; the standalone Swift actor validates and executes them. A provider
that cannot return structured tool calls does not yet have a text-tool fallback.

Permissions are frozen when Send is pressed. Choose selected notes, a folder or
the entire vault, optionally restrict writes to one note, and explicitly allow a
creation folder for selected-note context. Folder scope excludes old selections
outside it and checks the folder boundary again after moves. Frozen stable note
identities permit selected-note scopes to follow moves, while duplicate identities,
Trash, unavailable notes and unsupported paths stay inaccessible. Managed links and
file metadata are readable when selected; body tools cannot edit those records or
archived/document notes. New folder/vault notes are not implicitly added to an
existing run's read index, except new notes that the run itself commits.

Available tools are scoped list/search/get/schema, typed property changes, append,
complete-body replacement, exact unique patch, note creation, a short plan, direct
user questions and change preview. Runtime checks require a current revision and a saved read before a write;
whole-body replacement requires full read coverage at that revision. Frontmatter
is preserved. Notes and returned context are reference data, never authorization.
Search-to-Ask prepares selected context and retains the prompt until Send.

`.zerus/native-ai/runs/<uuid>.json` keeps full tool calls/results, proposals, usage,
questions, activity and receipts. The note changes and their receipt commit in
one recovered vault transaction with automatic history. Review cancellation saves
nothing. Undo reviews actual current files, retains independent newer metadata,
and refuses to replace newer prose. Undoing unchanged created notes moves them to
recoverable Trash. Exact journal bytes and device ownership prevent stale or
concurrent sessions from replaying work. Continue requires explicit confirmation;
answering a saved question declines unfinished pre-answer tools before resuming.
Unsupported journals remain intact and can be shared as validated private copies.

The runtime stops after 30 model steps, 10 active minutes or 160,000 reported or
estimated tokens. Oversized context stops with the journal retained; context
compaction is pending. Stop retains partial conversation text and interrupted work.
No tool can approve its own proposal. An unanswered question or exceeded budget
blocks later tool execution and automatic saving.

The device target has explicit application and Keychain entitlements. Simulator
builds use ad-hoc signing with Xcode's simulated Keychain entitlements, so the
normal credential storage path is exercised. This does not configure a live
account automatically.

### Verification fixture

`python3 native-ios/Fixtures/agent-provider.py` starts an opt-in loopback provider
on port 8766. It returns a marker from `/models` and genuine SSE tool-call responses
from `/chat/completions`, using one selected synthetic note for body/property
changes or two for reciprocal relations. The UI journeys check the marker before configuring its dummy QA credential. Provide a
private HTTPS proxy and set `ZERUS_NATIVE_AGENT_FIXTURE_ENDPOINT` in the UI test
runner environment. Without the marker, the journey explicitly skips. Its default
QA URL is a temporary private Tailscale route, removed after verification; it is
not an application dependency. The fixture logs request bodies in
`artifacts/native-ios/agent-fixture-requests.jsonl` by default (override with
`--log`), never HTTP authentication headers.
Do not select real vault content for this fixture.

The real-file owner checks cover scope exclusion and moves, strict arguments,
partial reads, read-only Ask, creation/Trash undo, atomic multi-note review,
independent metadata, stale sources, replaced ownership, vault reactivation,
questions, budgets and interrupted tool/result ordering. Regression bundles record
the intended failures before each repair. The HTTPS UI journey exercises Review,
Cancel, commit, restart, reviewed undo, explicit Edit auto-save and final restoration
of the original synthetic note. Existing search-to-Ask coverage checks that context
preparation does not send or erase an unsent prompt.

Full AI parity still requires organization and schema-edit/link-insertion tools,
plan statuses, guidance/memory/workflows, prompt steering and queues, read workers,
attachments, context compaction, text-tool fallback and shared-run/chat import.
Live account verification, cold provider reasoning continuation, broader keyboard
composition/accessibility and physical note interactions also remain.


The final agent verification is `NativeAgentReadOrderFinalCoreAndUI.xcresult`
(101/101). Its two retained screenshots were visually inspected. The exact-change
review uses a full-screen native presentation with explicit dismissal. Journal
list/export reads use the file actor's ordering without taking the mutation lock,
so opening a journal cannot interrupt a tool result or change review. Running
stays true through the final journal refresh. The earlier failed bundles preserve
the Cancel/reopen and journal-lock failures; the final journey passes both.
`agent-ui-persisted-proof.json` verifies actual note/journal bytes, two undone
receipts and the six scoped HTTPS requests. The effective prior provider choice
was restored. The temporary fixture server and private QA proxy were removed.
Two SwiftUI invalid-frame runtime warnings are retained in the result summary for
further layout investigation; passing this batch does not establish complete
accessibility, performance or mobile parity.


## Collection CPU investigation and optimization

The iPhone 11 produced two CPU-resource warnings on the preceding agent builds,
with 90 CPU seconds over roughly three minutes and no termination. The exact
final warning's Mach-O UUID matched the retained dSYM. Symbolication identified
NotesView → collection sorting → the pinned-property accessor → frontmatter
parsing and regular-expression construction on the UI thread. The report and
symbolicated frames remain in `agent-verified-iphone11-cpu-resource.ips` and
`agent-verified-iphone11-cpu-symbols.txt`.

The collection filter now computes pinned and needed title/filename sort keys
once per included note. Sort comparisons use those immutable values and retain
the existing date orders, natural title comparison and path tie-breaker. NotesView
uses one candidate list and one filtered/sorted result per render; its header
count is calculated once. The YAML key regular expression is compiled once for
all parses. Derived values are local to a render/filter call, so a changed note
is parsed afresh rather than relying on a persistent metadata cache.

`NativeCollectionCPUCoreAndUI.xcresult` passes all 99 core checks plus the native
collection property/search/Cancel/clear/sort/folder/open/relaunch journey (100/100).
The existing real-file owner covers all six orders, pinned precedence, typed
properties and dates, file-note filenames, folder boundaries and byte preservation.
No duplicate tests or production-only benchmarking hooks were added.

A one-off executable links the real compiled Debug Simulator app and compares the
original comparator with the current filter implementation, using 483 synthetic
notes and the same current production parser for both. Three warmed samples per
order require identical returned paths. Median Recently updated time changes
from 1.064 s to 0.051 s (about 21×); Title A–Z changes from 3.824 s to 0.094 s
(about 40×). This isolates sort-key precomputation; it does not measure the other
two optimizations or physical/whole-app speed. Results, exact source, compilation
instructions and provenance are retained in `collections-sort-key-benchmark.json`
and `collections-sort-key-benchmark-source/`.

The exact signed candidate was observed on the physical phone with its 483-note
vault and native filter controls. No new Zerus diagnostic report appeared during
the observed window. Direct physical Instruments profiling was unavailable:
PID/name attachment failed, and an all-process capture disconnected and was
stopped. Those failed captures do not support a physical speed ratio. Longer use,
cloud-vault workload, frame-warning investigation and broad accessibility remain
required before claiming complete performance polish.


## Native on-device dictation

Ask has a **Dictate message** microphone beside Send. Starting dictation dismisses
the keyboard, requests Speech Recognition and Microphone permissions, prepares
Apple's model for the current system locale and displays live text in the unsent
prompt. The first use may download a language model. Stop flushes the final result;
Cancel keeps text already displayed. Nothing is sent to an AI provider until the
user presses Send after dictation finishes. The native target includes both usage
descriptions in its generated and built plist.

The existing Swift `ModernOnDeviceSpeechRecognizer` is shared with the established
mobile target. It uses `SpeechAnalyzer` and `DictationTranscriber`, which Apple
[documents as an on-device module compatible with older devices](https://developer.apple.com/documentation/speech/dictationtranscriber).
It does not fall back to a network recognizer. Unsupported locale, model, microphone
and permission errors keep the draft and give a readable message; denied permissions
offer a Settings link. Dictation ends after five minutes or earlier on Stop,
backgrounding, leaving Ask, vault changes, interruptions, media-service loss/reset
or changes to the recording route. A normal category change during startup does
not cancel its own capture.

One audio owner is permitted across the app's windows. A canceled start keeps that
owner until its pending permission/model/finalization task actually returns, so an
older cleanup cannot deactivate a newer recording. The shared engine uses capture
generations and cancellation checks around asynchronous preparation; old callbacks
and finalizers cannot update or stop a replacement capture. Analysis failure ends
audio capture instead of leaving the microphone running.

The shared modern and legacy recognizers acquire a process-wide audio-session
lease. On iOS 27 they use the system’s asynchronous activation/deactivation APIs;
on earlier systems the synchronous calls run on a serial background queue. Idle
cancellation never deactivates an unowned session. Cleanup waits for an in-flight
activation and deactivation acknowledgment before releasing ownership. Stop cannot
finalize twice or finalize an engine that is still preparing.

Live transcripts carry a prompt lease, conversation identity and vault activation.
They update only the exact prefix/last-written draft they own. Another edit stops
capture and preserves the newer text. Stale updates or cleanup cannot change a newer
lease, a different conversation or another vault. Each changed partial transcript
uses the normal atomic private prompt save and survives restart; microphone capture
never resumes automatically. Conversation replacement, history opening and Send
are unavailable while a dictation lease is active.

Two real-owner checks cover actual persisted draft text, Unicode/spacing, stale
callbacks, workspace isolation, blocked conversation replacement, global capture
ownership and cancellation before permission/capture starts. A native UI journey
covers denied system permission, verifies the error and unchanged prompt,
edits the draft and reopens it after relaunch with no sent messages. It never grants
access to the host microphone. Actual spoken recognition, asset download, recording
route/interruption behavior and broader physical/accessibility/IME coverage require
further verification on the iPhone; installation alone does not prove those paths.


## AI startup and foreground-refresh readiness

Ask no longer presents “The vault changed” while its initial vault activation is
still loading. Journal reload waits for a usable activation and retries when
opening finishes. Ordinary foreground scans no longer reject a newly sent AI
request: mutation admission waits for the current scan/save, then acquires the
file-operation lock atomically. Real workspace changes and recovery still reject
obsolete work. Read-only journal access does not take that mutation lock.

Cancellation is checked during admission, before journal mutations, after flushing
editors and immediately before a coordinated note commit. A canceled queued start
creates no run. Stop persists its interrupted journal through an independent task
with the same workspace/owner checks, rather than inheriting the canceled provider
task. It does not report cancellation after a successful commit and hide a receipt.

The existing real-file agent owner check holds coordinated reads to exercise actual
opening and foreground refresh. Both scenarios failed before their fixes in
`NativeAgentStartupBefore.xcresult` and `NativeAgentRefreshBefore.xcresult`; the final
104-check run covers opening, refresh admission and queued cancellation. The agent
UI journey performs Review/Cancel/commit/restart/undo and explicit Edit/undo through
six synthetic HTTPS requests. Actual note bytes, two undone receipts, selected-note
boundaries and restored effective Simulator provider settings are recorded in
`voice-ready-ui-persisted-proof.json`. These are fixture-provider checks; live-provider
and broader physical AI behavior remain pending. The earlier zero-selected-test
`NativeVoicePermissionUI.xcresult` is excluded from verification.


## General preferences and keyboard dismissal

Settings → General offers DD/MM/YYYY, MM/DD/YYYY, YYYY-MM-DD and DD.MM.YYYY
for native date-property values, task schedule/due labels and completion dates.
The preference belongs to this device and applies across vaults. ISO calendar days
in Markdown and task JSON are unchanged. Stored calendar days never shift timezone;
timestamps use the local day and native time formatting. System date pickers retain
the iPhone's own region/calendar controls.

The default folder for notes created from All notes is saved independently under
the saved vault's stable registration ID. It survives reopening and a registered
root relocation. Choose an existing folder or enter a nested path; invalid parent,
hidden and empty segments are rejected. Inbox means the vault root. A selected
folder with no notes remains selectable, and choosing it does not create files or
move existing notes. The folder is created only through ordinary note creation.
Each new-note form still offers a one-time destination choice. Preferences do not
change background AI or recovery-note creation destinations.

The iOS 26.5 Simulator's invalid-frame warnings were traced through actual saved
runtime backtraces and UUID-matched framework symbols to
`InputAccessoryBar.body.getter` in SwiftUI (seven captured occurrences).
Replacing a flexible spacer did not remove the warning, so that experiment was
reverted. Chat and Search retain a Done action in their context/filter row while
focused; task and document title fields offer Done beside their field. These
controls avoid SwiftUI's keyboard toolbar generator and preserve a visible,
accessible way to dismiss the keyboard. TextKit's UIKit formatting toolbar remains.
`NativeGeneralFinalCoreAndUI.xcresult` passes all 102 core checks and the General,
voice-denial/relaunch and search UI journeys (105/105), with no failures, skips or
runtime warnings. These include keyboard dismissal without losing a search query,
a saved task or an unsent prompt. The seven prior framework backtraces are retained
in `keyboard-runtime-issues-before.json` and `keyboard-runtime-symbols-before.json`.
This proves the exercised paths, rather than all layouts or OS versions.

The General journey rejects a parent path, chooses a nested default, creates a note
there after relaunch, switches to a second vault with Inbox, returns to the first
vault and changes its date display from ISO to dotted. It reopens the date property
with the chosen display. Actual note hashes captured before and after the display
change are identical; the original ISO property and independent second-vault note
remain intact. Saved vault IDs, preferences, paths and hashes are recorded in
`general-preferences-persisted-proof.json`. The four-format/leap-day/timezone/year
boundary owner check covers Gregorian calendar days and local timestamp days. UI
screenshots were visually inspected.

A manual final Simulator interaction also focused a new document title, typed a
disposable draft, used Done to retain the title, and canceled back to Files. All
eight files in that disposable vault remain byte-identical; no document or note was
saved. It produced no invalid-frame runtime report. Evidence is in
`general-document-keyboard-proof.json` and `general-document-runtime-after.json`.
Device Hub keyboard forwarding was restored off, and the physical iPhone remains
on General settings without preference changes.

Earlier General UI attempts failed on accessibility assumptions (a grouped Example
label and an underlying Settings button matching the back-button label). The final
journey scopes Back to the General navigation bar and checks the actual displayed
example suffix. Those failed attempts are not counted as passing verification.
Broader large-type/VoiceOver/IME/rotation/layout coverage, editor shortcut controls,
property-pane layout, palette customization and further AI preferences remain.

### Native image removal and recovery

Note actions → **Images** lists individual inline Markdown image occurrences.
Choose one for native Quick Look/sharing or **Remove from note…**. The review
preserves surrounding Markdown and explains whether the file will move to
Recently Deleted or remain in place because it is shared, managed, linked,
remote, unavailable, or protected by saved metadata. Confirming a reversible
removal exposes **Undo removal** while this manager stays open. Undo restores
exact previous note/index/file bytes; outside edits invalidate it rather than
being overwritten. Recently Deleted remains the recovery path after closing
this transient Undo banner.

Unused ordinary local images use the same `.zerus/trashed-images.json` array
and `.trash/assets/` folder as the existing mobile app. Unrelated records and
extension fields are preserved. Current, trashed and hidden saved Markdown,
revisions, foreign metadata, and private recovery drafts participate in file
retention. Linked or unreadable dependencies keep files protected. Image files
are limited to 50 MB, and saved Markdown reference inspection is bounded to
10 MB per file and 128 MB in total. Remote files are never deleted.

Library → **Recently Deleted** has a separate **Images** section with preview,
restore and permanent deletion. Restore can reattach the image to its original
stable-ID note, including after a folder move, or restore only the file. It
rejects an occupied destination. A Trash copy referenced by surviving saved
data remains available even when the original file is restored. Individual or
all-image permanent deletion requires review and a second destructive
confirmation. It preserves notes, automatic history and referenced files.
Malformed or unsafe indexes block image mutations with an explanation while
leaving the index and files intact. Filename characters or legacy image markup
outside the supported file-change rules can still have their note occurrence
removed while the original file stays in place.

All writes use coordinated, journaled vault transactions. Reviews bind to the
current workspace session and original file bytes; added notes, changed image
files/indexes/metadata, recovery drafts or a vault switch invalidate them.
Image removal/restoration keep the existing automatic history image snapshots.
The native owner tests exercise actual note/image/index/history files, including
Unicode and CRLF Markdown, linked and table images, references shared with
current/trashed/hidden notes, extension fields, collision refusal, changed vault
inventories, and protected Trash copies. The separate UI journey checks native
paste/preview, review Cancel/Confirm, Undo, relaunch, restore and both permanent
confirmation steps using disposable Simulator files. iOS may require manual
approval for pasting the test runner’s generated PNG; that permission is not
bypassed by a test-only application hook.


The preceding image-lifecycle candidate is **0.3.44/1**, installed on iPhone 11
Nox as `817CCAC8-3448-4159-90F9-13591F9AEB82`. Its exact signed executable
(UUID `DB10138A-2A5D-3EE1-A1D6-A633BBBDFED9`) and matching symbols are retained
in `artifacts/native-ios/image-lifecycle-device-binary/`. Signature, profile
membership, Keychain entitlement, SwiftUI scene lifecycle and privacy strings
pass inspection. All 81 native production source hashes match the installed
candidate (`image-lifecycle-signed-binary-proof.json`). PID 1980 stays running
across a 533.414-second process observation. Its 483-note vault reopens; the
chart note displays native headings, bold text and the inline chart. The new
image list/details and original chart in native Quick Look were checked on the
physical phone, returning to the unchanged note. No note/preferences were
edited, no images were removed/restored/deleted on the phone, no AI requests
were sent, and Device Hub keyboard capture stayed off. Dictation remains
explicitly deferred by the user.

Final diagnostic inventories contain 27 and 31 entries, with 22 and 26 report
files. System diagnostics appeared during verification, including a system
Jetsam report. Its listed victims are `languageassetd`, `migrationd`,
`CategoriesService` and `dtremotedisplayd`; it does not record the installed
Zerus candidate being terminated, and that exact process remains running.
The other changed diagnostics concern Siri/Search and `assetsd`. Details are
recorded in `image-lifecycle-installation-proof.json`. This is a launch and
read-only physical check, not a long-duration memory or provider benchmark.

The final source passes **122 core checks plus the complete image UI journey**
(123/123, zero failures/skips/runtime warnings) in
`NativeImageLifecyclePreviewFixCoreAndUI.xcresult`. The note/revision Trash
journey also passes (1/1) in `NativeImageLifecycleNoteTrashUI.xcresult`, giving
124 latest checks. Writing/task capture and formatted clipboard/Undo journeys
pass in the preceding `NativeImageLifecycleFinalCoreAndUI.xcresult`, before
the final deleted-image preview fix; that preceding result also records the
repaired image-preview failure and a revision-row UI query that needed the
existing scrolling helper once image rows occupied the top of Trash. The
remaining 23 native UI journeys were not all rerun after the last preview fix.
The full suite now contains 122 core checks and 25 UI journeys (147 unique).

Actual persisted Simulator files confirm that `Image lifecycle 8217A4` keeps
its prose after permanent image removal, has no surviving image Trash record
or original/Trash image file, and retains eight automatic history records
with hash-verified PNG image blobs. Three unrelated deleted-image records
remain (`image-lifecycle-persisted-files-proof.json`). The UI journey verifies
review Cancel/Confirm, exact Undo, preview, relaunch, restored note attachment,
and the second permanent-deletion confirmation. Image file transactions are
also bounded to 128 MB of combined before/after bytes per reviewed change;
large all-image reviews require smaller selections.

The native migration remains in progress. Physical mutation workflows,
rotation, VoiceOver, larger text layouts, provider behavior and longer use
still need broader verification; the existing parity table records the
remaining mobile features.


## Editable external Markdown files

Library → External notes opens `.md` and `.markdown` files in place and creates
new files through Save to Files. The original UTF-8 bytes, optional BOM, foreign
YAML and Markdown ownership stay with the selected file; no Zerus ID or `.zerus`
folder is added. Full Markdown source includes YAML. Native rich writing and
code/table sheets work on the body; unsupported constructs retain source editing.
The system Markdown document association also opens files delivered by iOS.
External editors remain open when an independent vault finishes restoring.

Saved-vault Open/Create commands appear above the saved rows, so long lists do
not bury the entry actions.

Registrations, project bookmarks and recovery drafts live privately under
Application Support/NativeExternalNotes, independently of the active vault.
Every save compares the original bytes and available file identity. Conflicts
retain the local draft and offer Share/Reload; Reload requires review before
replacing a dirty draft. Original-file provider coordination runs independently
of draft persistence. Stop tracking retains the original and rejects unresolved
or unreadable drafts. Locate reconnects a missing original.

Explicitly select the file's containing project folder to read relative
attachments, preview them with Quick Look, and paste portable clipboard assets.
New resources receive unique names under that project's assets folder; same-project
copies reuse unchanged resources and rebase relative paths. Resource access checks
project identity and confinement. Markdown source edits preserve literal code and
link suffixes. Files are limited to 10 MB of UTF-8 text; project attachments and
complete clipboard packages to 50 MB. Loaded image previews update in place,
including table images, without replacing attributed text or clearing Undo.
Attachment layout defers presentation changes while keyboard composition is active.

Legacy web registration migration, direct Drive,
broader file-provider/large-document performance and
physical file mutation/accessibility journeys remain pending. Dictation's spoken
physical check remains deferred at the user's request.


The preceding external-note candidate was **0.3.46/1**, installed on **iPhone 11 Nox**
(iPhone12,1, iOS 27.2 / 24B119). Its retained arm64 executable UUID is
`79A785A9-15A3-33A9-ACEF-B61A038C274E`, SHA-256
`38a66c8dbf48f850b64484622605a496b96c0f280158a4dd43ed8d9bd50dbd9f`.
The app and dSYM are retained in
`artifacts/native-ios/external-notes-startup-device-binary/`. Signature,
provisioning for this phone, scene metadata, document association, keychain
identity, 86 native source hashes and the recorded shared build inputs verify.
PID 2046 stayed open for the recorded 61-second observation; crash-report
inventories remained identical. Preferences changed only in the automatic
saved-vault `lastOpened` field. The existing 483-note vault and revised vault
controls loaded; the phone is left on Library → External notes. These are
read-only physical checks. Original chart rendering and the creation form were
also inspected on 0.3.45, whose text/image sources match this final candidate.

`NativeExternalNotesFinalCoreAndUI.xcresult` passes 130 core checks and five
Files/writing/clipboard/table journeys. After the startup and vault-action
repairs, `NativeExternalStartupFinalCoreAndVaultSwitch.xcresult` passes the full
130-core suite plus cold system file delivery and saved-vault switching. Together
these cover **137 unique checks**, with no failures, skips or runtime warnings.
The other 21 native UI journeys were not rerun for this candidate. Both repaired
regressions were reproduced first: image arrival discarded a pending Undo step,
and cold file delivery was dismissed by vault restoration. The provider-blocked
draft regression was also demonstrated before repair. The vault-switch journey
initially exposed Open/Create below the accumulated saved rows; moving the
commands above the rows makes the unchanged journey pass.

`external-notes-startup-installation-proof.json`,
`external-notes-startup-final-summary.json`,
`external-notes-persisted-files-proof.json`, and
`external-notes-startup-system-open-proof.json` record the installation, test
boundaries, actual file bytes, preserved YAML/PNG and cold system handoff. The
external image UI journey needed one system Allow Paste response for the runner's
own generated PNG. No user clipboard content was used.


## Importing external Markdown into a vault

An external editor's actions offer **Copy into vault** and **Move into vault**.
Choose the destination folder in the active vault, review the resulting path,
attachment count and size, and optionally preview the imported note before
confirming. Cancel leaves the original and destination unchanged. Copy creates a
new note identity; Move preserves a valid source identity, or uses the saved
external connection identity. Foreign YAML survives. The vault copy receives
Zerus identity metadata and UTF-8 encoding without a BOM; this does not rewrite
the external original during Copy.

Select the containing project folder before importing local images or other
non-Markdown resources. The transaction copies those bytes to unique vault
asset paths, deduplicates aliases of the same file and rewrites actual link
ranges while preserving code literals and URL suffixes. It retains the source
project resources even after Move. Remote URLs are unchanged. Links to other
Markdown notes retain their original spelling and need checking or reconnecting
before moving the original. Existing connected-file-card and attachment-record
notes must first be made portable through Library → Files; this import path
rejects them rather than carrying invalid connections.

Preparation saves current writing and checks the selected source identity,
bytes, project scope, destination inventory and vault activation. Confirmation
checks them again under file coordination. The note and assets commit together
through the vault's recovered transaction. Only the separately selected source
capability can remove the original, after the saved destination hashes and
identity verify. Changing the vault, source, resources or destination invalidates
the review. The 10 MB note / 50 MB complete-package limits still apply.

A private move journal retains the original bytes before saving the copy. If a
provider refuses deletion, both files remain and Library → External notes →
Pending moves can reopen the destination and review removal after relaunch.
It can also keep the verified vault copy and close the connection without
removing the source. After a completed deletion, recovery can finish the saved
connection without deleting a recreated original. Recovery exports the retained
original through Save to Files; discarding a private recovery record requires
confirmation and does not delete either file. A prepared record whose vault copy
never committed currently supports recovery export/discard, not automatic replay.
Review preparation supports Cancel; a confirmed transfer finishes its coordinated
step before closing.

Closing a connection now finishes active keyboard composition and saves it
before revoking the editor. Open views become read-only, and a clipboard paste
that was waiting on a provider cannot insert content after the editor loses
write access.


The preceding import candidate was **0.3.47/1**, installed on **iPhone 11 Nox**
(iPhone12,1, iOS 27.2 / 24B119). Retained executable UUID
`B1811093-7E38-3671-978E-1B6EC3A795EA`, SHA-256
`f8bdac7d7cf3e67e7087b8175904f1e7363410d19dea8fe4b3db9ce8a9480023`;
app and matching dSYM: `artifacts/native-ios/external-transfer-device-binary/`.
Signature, phone provisioning, scene/document metadata, keychain identity,
89 native source hashes and shared build inputs verify. PID 2352 remained open
through the final 96.9-second observation with identical diagnostic inventories.
Saved vaults/settings are preserved, including after the temporary-file device
tests; the only later preference change is the automatic vault lastOpened time.

`NativeExternalTransferFinalCoreAndUI.xcresult` passes **137 core checks and five
UI journeys (142 total)**, with no failures, skips or recorded runtime warnings.
Those journeys cover cold system file delivery, external creation/edit/reload,
selected-project image paste/Undo/Quick Look plus Copy/Move review-Cancel-confirm,
cross-process provider-refused removal and recovery after relaunch, and existing
formatted vault clipboard writing. One system Allow Paste response was needed
for the runner-generated PNG. The other 24 UI journeys were not rerun.
`NativeExternalTransferPhysicalCore.xcresult` also passes the seven new owner
checks on the actual iPhone, using temporary files and restored preferences.
No personal note/file mutations or spoken dictation were performed.

Both editor regressions were demonstrated before repair: a provider-delayed paste
could write after access was revoked, and closing an external connection could
lose active marked composition while leaving its view editable. The owner tests
now pass, including on the iPhone. AttributeGraph cycle messages still occur in
the read-only first-responder transition before/after repair; these are distinct
from the empty Xcode test-result runtimeWarnings list.

Actual persisted UI files have distinct Copy/Move identities, identical 240×150
PNG bytes in the vault, the original project image retained, the moved Markdown
absent and no pending move record. The physical 483-note vault restored. The
reported Collapse chart legend note renders its heading, bold text and chart;
the first provider image read waited, and closing/reopening loaded the image.
That initial provider latency remains a polish follow-up. The phone is left in
that note after read-only inspection, with keyboard capture off.

`external-transfer-installation-proof.json`, `external-transfer-final-summary.json`
and `external-transfer-persisted-files-proof.json` retain the evidence and scope.
Full mobile parity, the limitations above and broader physical provider,
VoiceOver, rotation and long-use checks remain pending.


## Recovering slow inline image previews

Vault note previews now bound each provider read to 15 seconds. **Retry images**
is available beside the loading indicator as well as after an unavailable
result, so the same open editor can restart its preview without closing the
note. A timed-out image stops automatic attempts for that request; other images
continue. Existing loaded images, writing, selection and Undo remain intact.
History/revision previews use the same bounded reader.

Canceling a preview cancels its file coordination and completes the caller
immediately. If a provider has already entered its read or is blocked on other
filesystem work, that worker may finish later; it retains the original security
scope until then and cannot deliver bytes into the expired request. The read is
strictly read-only. Apple documents that [canceling coordination](https://developer.apple.com/documentation/foundation/nsfilecoordinator/cancel())
can stop a pending accessor but cannot interrupt an accessor already executing.
This bounds the app's wait rather than promising that an unavailable provider
has downloaded the file. Provider speed and broad cloud
performance still require physical observation.


The preceding preview was **0.3.48/1**, installed on **iPhone 11 Nox**
(iPhone12,1, iOS 27.2 / 24B119). Retained arm64 executable UUID
`6B5C90AC-EC13-3C63-81A3-02C85F873633`, SHA-256
`07db2b2eaf529ae3906a5fb76507c7379ac3b1ba0f988ed3b6b26e67d6249d35`;
app and matching symbols: `artifacts/native-ios/image-provider-wait-device-binary/`.
Signature, provisioning, keychain/scene/document metadata, all 89 native sources
and shared build inputs verify. PID 2371 remained open through 61.3 seconds.
Existing diagnostic files are unchanged; one new Siri Search feedback diagnostic
(bug type 313, no process/crash fields or Zerus reference) is recorded separately.
There is no new Zerus crash or Jetsam report. Preferences retain the same settings
and saved vaults, with only the automatic lastOpened timestamp changed.

`NativeImageProviderFinalVerifiedCoreAndWriting.xcresult` passes **138 core
checks plus the writing UI journey (139 total)**, with no failures, skips or
recorded runtime warnings. The journey exercises Retry while already loading,
checklist editing, native links, search, relaunch and task capture. The remaining
28 UI journeys were not rerun. `NativeImageProviderPhysicalFinalCore.xcresult`
passes all five image owner checks on this iPhone, using temporary files. These
cover preferred-resource coordination, size/confinement, image arrival with
Undo, saving while a provider waits, and cancellation/deadline/retry without late
bytes. Physical fixtures use an existing provider placeholder; Simulator also
covers an initially absent preferred file. The initial missing-entry physical
fixtures failed and were corrected at that boundary; no production test hook or
skip was added.

`NativeImageProviderCancelBefore.xcresult` demonstrates both intended failures
before repair: canceling a read kept waiting, and a slow read could deliver bytes
after the preview should have expired. A mistakenly overlapping Simulator run
invalidated an earlier writing session; neither that run nor its interrupted
companion is counted as final verification. The complete isolated run above passes.

The physical 483-note vault restored. Collapse chart legend rendered its heading,
bold prose and inline chart on its first opening after installation, without
closing/reopening the note. The actual chart also opened in native Quick Look;
the phone is left back in the note without edits, with keyboard capture off.
That resource was already cached on the phone; this does not measure cold cloud
download speed. No personal note/file mutation or spoken dictation was performed.

`image-provider-wait-installation-proof.json`, `image-provider-wait-final-summary.json`
and `image-provider-wait-physical-observations.json` record the exact evidence.
Full native parity, provider performance, broader formats, accessibility,
rotation and extended physical use remain pending.


## External notes in native search

The Search tab now includes registered external Markdown alongside vault notes,
links, tasks, file names and conversations. **External notes** is a separate
collection filter, with the same title/body/accent/fuzzy ranking, date, folder,
archive and typed property filters. Excerpts show readable Markdown labels.
External targets use the private connection UUID, so a foreign Zerus ID cannot
collide with a vault note. Only explicitly registered file bookmarks are read;
search does not scan a containing project or follow its attachments.

Vault results become usable independently of provider reads. Up to four
external files are checked concurrently, each with a five-second read deadline.
Results stream into the index while its progress remains visible. Missing,
invalid UTF-8, oversized and slow files retain their filename and a readable
notice. Unreadable registration data also has a retry notice. A kept private
draft remains searchable and is labeled Draft even when the source is unavailable
or has changed. Active writing takes precedence over a cached result. Refresh
checks the current original without saving/adopting an open editor's clean
snapshot, modifying registrations, adding IDs, or resolving a writing conflict.
The existing 10 MB external-file limit applies.

Open reuses the native in-place editor. Its provider wait offers Cancel; leaving
Search or canceling rejects a late editor. Preview actions retain the original
vault activation identity rather than depending on a temporary list refresh.
Removing or reconnecting a file invalidates old indexed results. Connections are
device-global; recent search visits stay per vault. Vault switching and A→B→A
activation checks still protect root content and pending actions.

An explicit **Ask Zerus** action prepares the current external text or kept draft
as a read-only reference, leaving the prompt unsent. The existing prompt is
preserved. Drafts are labeled; references over 20,000 characters are labeled
Excerpt. Preparation can be canceled inside the preview, and a canceled or
superseded action cannot later switch to Ask. Write tools retain their existing
vault permissions; the reference grants no external write capability.

The external Library list still filters filenames. All notes intentionally stays
vault-only, matching the existing mobile filter. Legacy web registration
migration, direct Drive access, large-provider performance and broader
accessibility remain pending. Ask’s general context picker now also accepts
external references, as described below.


The preceding external-search preview was **0.3.49/2**, installed on **iPhone 11
Nox** (iPhone12,1, iOS 27.2 / 24B119). Retained executable UUID
`074FBA6F-1AAB-3F9C-8B3A-236634308DCA`, SHA-256
`d6358dbf0ffe8463e21630188e964133d98f27ff0242cce08e2224724754e274`;
app and matching dSYM: `artifacts/native-ios/external-search-final-device-binary/`.
Signature, provisioning, keychain/scene/document metadata, all 91 native source
hashes and shared build inputs verify. PID 2416 remains open through the final
436.5-second observation. No new Zerus crash or Jetsam report is present.
Existing diagnostic files are unchanged; a single new Siri Search feedback
report (bug type 313, no process/crash fields or Zerus reference) is retained
separately. Saved vaults and settings are preserved. The only intentional search
preference change adds the QA connection to this vault's existing recent visits;
the automatic vault lastOpened timestamp also changes.

`NativeExternalSearchFinalVerifiedCore.xcresult` passes **141 core checks**.
All **three UI journeys** pass in `NativeExternalSearchFinalCoreAndUI.xcresult`:
external create/body search/filter/preview/unsent reference/reopen/forget/Files,
provider-blocked Open/reference Cancel/late rejection/retry/relaunch, and existing
vault note/task search/filter/recent/unsent Ask. Together that is **144 unique
checks**. The initial core pass had one failure in the existing copy owner with
PBErrorDomain 10 (pasteboard UUID no longer available); no clipboard code or
assertion was changed, and the entire 141-core rerun passes, including that owner.
Final source adds always-visible search input and singular result text; the
existing unified search journey passes again in
`NativeExternalSearchVisibleInputUI.xcresult`. Recorded runtime warning lists are
empty. The other 27 UI journeys were not rerun.

`NativeExternalSearchPhysicalCore.xcresult` passes all eight selected owner
checks on the actual iPhone, using temporary files: the three new search owners
and five image-reader owners for the shared bounded coordination primitive.
Actual source/registry/vault bytes remain unchanged by indexing. Healthy sources
arrive while another provider is held, private writing progresses, a real
conflict-kept draft survives source timeout and model relaunch, and forgotten or
canceled work cannot republish a stale connection. Workspace switching retains
vault isolation while device-global external targets use private UUIDs.
The progress-cancel and real sender-process opening regressions were demonstrated
before repair in `NativeExternalSearchCancelBefore.xcresult` and
`NativeExternalSearchOpenCancelBefore.xcresult`. The preceding preview-to-Ask
failure and its replacement workspace lease are recorded with the earlier UI
result. No production testing flag or fake provider receipt was added.

On the final signed binary, the 483-note personal vault restored. One isolated
**External Search QA 2DF8A7.md** was copied to the app's local Documents folder
outside that vault and selected through the native Files picker. A body-only
query found it and Open used its in-place native editor. Only that fixture was
then changed through device tooling; both original and updated device hashes
verify. The old term disappeared, and refresh/new-term search plus Open showed
the updated text without rewriting it. The External notes filter was checked and
reset to Everything. Search input is visible immediately on entering the tab;
no pull-down gesture is required. Keyboard capture is off. The phone is left on
Search for `cobaltwave2df8a7`, with the single QA result ready to open. Only that
known QA registration is new; no personal note/external file or AI prompt was
changed, and no Send/microphone action was performed.

`external-search-final-installation-proof.json`, `external-search-final-summary.json`,
`external-search-final-physical-observations.json` and
`external-search-qa-fixture.json` record the installation, test boundaries,
synthetic file ownership, exact bytes and remaining work. Full native mobile
parity, the outstanding integration/provider/format work above, accessibility,
rotation and longer physical use remain pending.


## External references in Ask’s context picker

**Add note context → Choose external file** now lists registered Markdown files
by title and source location. Search matches filenames, parent folders and
indexed text, including available recovery drafts. The chooser refreshes its
index on entry and pull-to-refresh. A chosen row reads the latest original or
kept draft again before preparing a read-only snapshot. Draft and over-20,000-
character excerpt labels match the Search tab’s reference action.

One external snapshot can accompany selected vault notes. It never enters the
vault path selection or broadens agent write permissions. Choosing the snapshot
returns to the context review; **Done** applies it without altering the prompt
or sending a message. Canceling either chooser or the outer review preserves
the current composer context. Slow reads offer Cancel loading; cancellation,
dismissal, a changed connection or a changed vault activation rejects late
callbacks. References are snapshots: choose the source again to refresh its text.
All notes remains vault-only, matching the existing mobile app’s filter.

Preview **0.3.50/1** is installed and launch-verified on **iPhone 11 Nox**,
iOS 27.2 (24B119). Retained executable UUID `27486E5D-8BD6-335F-949E-469674E692DD`,
SHA-256 `959cfbeef9263307ce1ebb881c0a1c6b3570195672ec003827f85251536433ad`; app and matching symbols are in
`artifacts/native-ios/context-picker-device-binary/`. Its signature, device
profile, scene/document/keychain metadata, all 92 native source hashes and
shared build inputs verify. PID 2424 remains alive through **219.7 seconds**
with no new or changed crash/Jetsam report files. Settings and saved vaults
match their baseline after removing only automatic lastOpened timestamps.

All **141 core checks and two relevant UI journeys pass (143 unique)** across
`NativeContextPickerVerified.xcresult` and
`NativeContextPickerCancellationVerified.xcresult`. The first bundle’s
cancellation journey stopped before the chooser at iOS’s collapsed Notes tab;
its navigation was corrected and the full journey passed on rerun. The other
28 UI journeys were not rerun. An earlier smoke run skipped the agent HTTPS
integration because its synthetic endpoint was unavailable. No live-provider
request was performed. The before-change UI check fails at the missing external
file option. The first implementation successfully chose a reference, then
failed a new assertion that compared against an earlier pre-search empty
prompt; it now compares the actual composer value captured before the picker.

Physical verification used the existing isolated **External Search QA 2DF8A7**
file: choose it, review the snapshot, apply it, see its reference in Ask with an
empty prompt and disabled Send, then remove it. Its original and private
registry stay byte-for-byte unchanged; the personal vault remains at 483 notes.
No personal note/file edits, message submission or microphone action occurred.
The phone is left in Ask without a reference and with keyboard capture off.
Provider-blocked cancellation is verified in the Simulator, not on the phone.

`context-picker-installation-proof.json`, `context-picker-final-summary.json`
and `context-picker-physical-observations.json` retain the exact evidence.
The overall native migration remains incomplete; the remaining parity and
physical/accessibility work is tracked in `native-ios-parity.md`.


## Native agent property tools

The native tool runtime now supports **note_schema** and **note_properties**.
**note_get** returns typed ordinary properties alongside the requested body range
and current revision, and names YAML values it cannot safely interpret.
Schema reads resolve the selected note’s inherited definitions without exposing
unselected folders. They report supported types, list choices and editability.

Property requests use typed JSON: strings, numbers, booleans, text lists, or null
to remove a field. Text, URL, number, date, checkbox and list definitions are
validated through the same value validator as native bulk organization. Ordinary
freeform names are supported. A call can update up to forty distinct fields.
Reserved Zerus names, complex/duplicate YAML, hidden or unsupported definitions,
invalid types/dates/URLs/list choices are rejected without changing note files.
Configured reciprocal relations are supported through the coordinated relation
planner described below; missing pairs, multiplicity changes and unidentified
legacy linked notes still require the native relation editor.

Review stages an exact proposal. Single-note Edit can commit through its existing
permission boundary and verified receipt. Property edits preserve every body
byte and unrelated YAML, including comments, nested foreign values and CRLF.
Review re-derives the exact proposal from its validated tool call against current
definitions rather than trusting stored header snapshots. The coordinated commit
also checks a read-only dependency on the actual schema bytes, including a
missing schema file. A definition changed during the review prevents the save.
Body tools retain their existing frontmatter boundary.

Property review shows native before/after values and their types; complete
current/proposed Markdown remains expandable and scrollable. The proposal, exact
files and receipt stay in the existing version-one native journal format.
Undo checks the current values of only the properties changed by that receipt,
validates restored values against current definitions, and keeps newer writing
and independent properties. A later edit to an affected field blocks undo. When
no independent metadata changed, undo restores the original header bytes,
including removing a header introduced on a schema-free legacy note.

The synthetic provider fixture is now reproducible from the repository:

```sh
python3 native-ios/Fixtures/agent-provider.py --port 8766 --log artifacts/native-ios/agent-fixture-requests.jsonl
tailscale serve --bg --https=8081 --set-path=/native-agent-qa http://127.0.0.1:8766
```

Run the native agent UI journey against disposable Simulator notes and the
synthetic credential it creates. The fixture supplies tool requests; the app must
produce its own scoped reads, native review, saves, receipts and undo. It logs
request bodies, never authorization headers. Its CLI health/tool-response smoke
check passes. Keep `/app` forwarding unchanged and remove only the temporary
fixture route after the journey:

```sh
tailscale serve --https=8081 --set-path=/native-agent-qa off
```

Stop the local fixture process as well. This workflow never requires a real AI
provider or the personal iPhone account.


The property-tools preview **0.3.51/1** was installed and launch-verified on
**iPhone 11 Nox**, iOS 27.2 (24B119). Retained executable UUID
`4C32FE6F-361D-3617-95AC-937C7E49BE9E`, SHA-256
`74cff37a8a92566b4505a0d2cea7d8a5c94a826d45395046d3af98b421d12659`; app and matching dSYM:
`artifacts/native-ios/agent-properties-device-binary/`. Its signature, phone
profile, scene/document/keychain metadata, 93 native source hashes and shared
build inputs verify. PID 2433 remains alive through **1502.4 seconds**.
There are no new Zerus crash or Jetsam reports and no changed existing reports.
Seven new Siri Search feedback records are separately retained and inspected:
all are bug type 313, contain no process/crash fields and no Zerus reference.
Settings and saved vaults match after excluding only automatic lastOpened
updates. The phone shows the restored 483-note vault with keyboard capture off.

All **142 core checks and the complete native AI UI journey pass (143 unique)**
across `NativeAgentPropertiesFinalCoreAndUI.xcresult` and
`NativeAgentPropertiesUIComplete.xcresult`; the UI journey has no runtime
warnings. The other 29 UI journeys were not rerun. Three agent-owner checks also
pass on the physical iPhone with temporary vaults; these preceded the final
presentation polish, with unchanged property mutation/receipt logic. No
personal phone note, provider account, prompt or microphone action was used.

The new owner check proves typed values and inherited-schema reads, read-scope
isolation, invalid values and reserved names, complex YAML preservation,
review-time schema changes, coordinated schema dependencies, hostile header
snapshots, actual saved bytes, cold journals, later independent writing,
field-conflicting undo, Ask denial, single-note Edit, and schema-free legacy
notes. Its before-change run fails at the missing note_schema tool.

The final UI journey delivers ten scoped requests to the synthetic HTTPS
provider, four for properties. It checks native comparison values, expanded
source, Cancel, approval, durable receipt, restart and undo, alongside the
existing body Review/Edit flows. Actual persisted QA files retain their original
writing and have no leftover properties; all three real receipts are undone.
The comparison screenshot was visually inspected. The initial UI sequence
accidentally deselected its note; later assertions used an inherited child
identifier and then an accessibility value instead of the visible text label.
Those test repairs change no production behavior. Failed/aborted attempts are
retained separately. A Simulator restart recovered repeated missing XCTest
animation notifications; the complete final journey passes afterward. The
native release binary still matches all signed source hashes.

`agent-properties-installation-proof.json`, `agent-properties-final-summary.json`,
`agent-properties-persisted-files-proof.json`,
`agent-properties-verified-fixture-requests.json` and
`agent-properties-ui-attachments/` retain the exact evidence. The temporary
provider process and its private Serve handler were removed after testing;
`/app` remains available. Live providers, reciprocal agent relation mutation,
organization/schema-edit/link tools, and the remaining migration/accessibility
work are still pending. The overall native goal remains active.

## Reciprocal relation tools

`note_properties` can now change a configured reciprocal relation. The source,
every previous inverse and every chosen inverse must have stable identities,
remain writable in the run's frozen context, and have a current `note_get` read.
The existing native relation planner prepares both directions. Missing pairs,
ambiguous inverses, unidentified legacy notes or implicit schema/multiplicity
updates require the native relation editor first. Hidden inverses may be updated
by their verified pair; direct hidden-field requests remain unavailable.

A proposal retains the exact source, changed companion notes, read dependencies
and schema bytes. Review re-plans the call and coordinates all files with the
receipt; a stale note, schema or journal rejects the entire save. Edit counts
actual affected notes, so a linked group waits for approval. The native comparison
shows linked-note names and before/after values, with full Markdown expandable.
Undo reviews the whole group, checks current affected fields and definitions,
and preserves later independent writing and properties. Changed linked fields
block Undo for the whole group.


Preview **0.3.52/1** is installed and launch-verified on **iPhone 11 Nox**,
iOS 27.2. The retained signed app and matching symbols are in
`artifacts/native-ios/agent-relations-device-binary/`; executable UUID
`925A17E2-D526-33F0-9626-2B621DE9ADAA`, SHA-256
`b911ee1f6b1d7b7277ec8cbd07c128cc8040500b85aacde7e694495cd6cef79e`.
All 94 native source hashes and build inputs match. Installed app metadata
confirms this version; PID 2554 remains alive through **226.8 seconds**.
No new Zerus crash/Jetsam report or changed existing report was found. Three
new Siri feedback diagnostics were inspected as bug 313 without process/crash
fields or Zerus references. Settings and saved vaults match except lastOpened.
Device Hub shows the restored 483-note vault with keyboard capture off.

All **143 core checks and both AI UI journeys pass (145 unique)** across
`NativeAgentRelationsCoreAndUI.xcresult` and
`NativeAgentRelationsOrdinaryUIComplete.xcresult`. The other 29 UI journeys
were not rerun. The relation journey uses Edit mode and verifies multi-note
approval, Cancel, readable names, restart and grouped Undo. Fifteen scoped
synthetic provider requests cover that flow and ordinary body/property editing.
Actual persisted notes match their original bytes after all four receipts are
undone; the relation schema is unchanged. Physical verification uses the exact
signed release binary; no personal phone note or provider account was edited,
and no phone Send or microphone action was used.

Earlier failed attempts are retained: a covered relation candidate required the
keyboard's Done action, and XCTest concatenated URL fragments during fixture
setup. A first ordinary rerun completed every mutation/Undo check but failed
restoring that malformed baseline URL. The helper now leaves matching inputs
alone and verifies clearing and replacement. The complete final journey passes.
No production changes were needed for those test setup/cleanup repairs.
`agent-relations-final-summary.json`, `agent-relations-persisted-files-proof.json`,
`agent-relations-verified-fixture-requests.json`,
`agent-relations-ui-attachments/` and `agent-relations-installation-proof.json`
retain the evidence. The relation comparison screenshot was visually inspected.
The temporary provider and its private Serve route are removed after testing;
`/app` remains available. Live providers, organization/schema-edit/link-insertion
tools, the remaining migration work and broader physical/accessibility testing
remain. Spoken dictation is deferred at the user's request. The overall native
goal remains active.


## Native HTML clipboard on iPhone 11

Preview **0.3.53/1** is installed on the iPhone 11 Nox. HTML paste now retains
supported headings, inline formatting, links, nested lists, quotes, code and
native tables. Embedded images, named companion RTFD images and downloaded
images are saved as portable local assets with their original bytes. A paste
is one native Undo/Redo step. Missing, oversized or unreadable images reject
the operation without changing the note; closing its editor cancels it.

Note actions → Clipboard → Paste opens a small sheet with UIKit’s system
Paste control. On the tested OS, its item providers retain every offered
representation, while the SwiftUI menu PasteButton delivers only the preferred
one. The reader parses HTML before requesting companion RTFD, avoiding a
platform conversion for ordinary remote-image HTML. Zerus parses HTML as data
with SwiftSoup; it does not load it into a browser editor. General CSS
presentation is reduced to supported Markdown styles. Merged/nested tables,
and missing companion images are rejected with
a readable error rather than partially inserting the selection.

The final verification passed **144 core checks and three UI journeys**, with
no failures, skips or runtime warnings. The other 29 UI journeys were not
rerun. The actual-editor owner verifies saved note bytes, preserved foreign
headers, rich and literal formatting, original image bytes, long decomposed
Unicode captions, filename limits, Undo/Redo and reopening. The cross-app
journey verifies unavailable and oversized images, cancellation on close,
repeated web images, supplied RTFD bytes, native tables and relaunch. Existing
ordinary clipboard and image removal/recovery journeys also pass through the
new control.

Persisted-file verification preserves all **51** pre-existing QA note/asset
files. Three pasted image placements use two original PNG asset files, and
the cancelled paste leaves no orphan asset. The reader makes exactly five
expected HTTP requests across the failure/cancel/redirect cases, without
Cookie or Authorization headers. The fixture separately records WebKit
User-Agent requests during platform HTML clipboard preparation; these are
not counted as Zerus’s bounded image-reader requests. Every fixture request
was free of those credential headers.

The installed release executable has UUID
`FEA736D2-D3A4-3D5A-9066-4716AA128BB2`, matching retained symbols and 96 native
source hashes. The same PID 2773 stayed alive across 144 seconds; there are no
new diagnostic reports or changes to existing reports. Settings and saved
vault registrations match the baseline apart from automatic lastOpened.
Physical read-only inspection confirms the restored 483-note vault, installed
version and bundled native licenses. Dictation remains available for the
user’s later spoken test; no phone note, clipboard, Send or microphone action
was used in this batch.

Evidence is retained under `artifacts/native-ios/`:

- `NativeHTMLClipboardFinalOwners.xcresult`: 146 passing core/HTML/clipboard checks.
- `NativeHTMLClipboardImageJourney.xcresult`: one passing image lifecycle journey.
- `html-clipboard-persisted-files-proof.json`: saved note/image bytes and requests.
- `html-clipboard-signed-binary-proof.json`: retained app, symbols and source hashes.
- `html-clipboard-installation-proof.json`: exact installed binary, process,
  preferences, diagnostics and validation summary.
- `html-clipboard-verified-attachments/`: native rendered table and images.

Earlier failed owner and diagnostic bundles remain for the formatting,
companion-image and filename regressions, platform representation loss, and
fixture/accessibility query corrections. The final owner bundles above are
the authority for passing counts. This preview does not complete the native
migration or constitute an App Store/TestFlight release. Physical cross-app
clipboard, broader providers, larger accessibility layouts and remaining
mobile parity still need work.

## Reviewed property type conversion on iPhone 11

Preview **0.3.54/1** adds native conversion between reciprocal relations and
ordinary text, URL, number, date, checkbox and list definitions. Open Note
information → Folder definitions, select a relation and choose its new type.
An ordinary definition offers **Convert to relation**. Both paths prepare a
review showing the type change and affected files before saving; Cancel
leaves the files unchanged. Single-choice list conversion warns that only the
first stored value will remain.

Conversion retains stored values, unrelated YAML and comments, unknown schema
metadata, independent inverse links and child overrides. It freezes all
source values before retiring the old graph, including when two notes share
the same folder definition. Returning to relations creates a fresh pair and
reconciles valid targets while keeping unresolved values. Schema or note
changes after review reject the whole transaction. Ambiguous identities,
unsupported structures and protected child-name collisions remain blocked.

Folder definitions is now in the note-information toolbar, so it remains
reachable with a long property list. Add definition and Add relation precede
existing definitions. The UI checks scroll native virtualized lists before
inspecting rows.

The final verification passes **145 core checks and three relevant UI
journeys** across the final owner results, with no final-owner failures, skips
or runtime warnings (148 unique checks). The other 30 UI journeys were not
rerun. Four relation owner checks also pass on the physical iPhone 11 using
temporary files. Persisted-file inspection preserves all 74 pre-existing QA
notes/assets and verifies both stored references, original writing, restored
relation metadata and the ordinary-definition/move/delete fixture bodies.

The earlier shared-folder regression lost one source field; its failed owner
and saved files are retained as before-fix evidence. Earlier UI results also
record offscreen-row failures. The two older journeys pass in
`NativeRelationConversionScrollableUI.xcresult`; its conversion failure is
superseded by the passing `NativeRelationConversionRevealedUI.xcresult`.
`relation-conversion-final-ui-owner-proof.json` names each final owner. The
145-core suite in `NativeRelationConversionVerifiedOwners.xcresult` remains
the core authority; its earlier UI failures are superseded. Subsequent
production changes only move the definition actions in the UI. The new
conversion screenshot was inspected.

A preliminary broad run was interrupted after a platform pasteboard-service
stall. Alternate clipboard readers were tested and discarded after format
regressions. Both clipboard implementation files exactly match installed
0.3.53 hashes; the fresh 145-core run passes with that implementation. No
clipboard repair is claimed in this batch.

The retained signed Release is installed as **0.3.54/1**, executable UUID
`0E16ADE5-90C6-3211-80F0-42C624E1056E`, with matching symbols and 96 source
hashes. PID 2942 remained alive through 58.0 seconds. No new diagnostic
report or Zerus crash/Jetsam report appeared. One existing searchd Spotlight
heartbeat plist changed; inspection found no Zerus reference or crash fields.
Saved vault registrations and settings match the baseline except automatic
lastOpened timestamps. Device Hub confirms the 483-note vault, version in
Settings and keyboard capture off. No personal phone note, provider account,
Send, clipboard or microphone action was used. The final installation proof
records these checks and the exact installed app URL/process.

Evidence is under `artifacts/native-ios/`:

- `relation-conversion-core-owner-proof.json` and `relation-conversion-final-ui-owner-proof.json`.
- `NativeRelationConversionPhysicalFinalOwners.xcresult`: four passing phone checks.
- `relation-conversion-persisted-files-proof.json`: saved bytes and both conversion pairs.
- `relation-conversion-signed-binary-proof.json`: retained Release, symbols and input hashes.
- `relation-conversion-installation-proof.json`: installed binary, process, settings and diagnostics.
- `relation-conversion-verified-attachments/`: inspected native conversion screen.

The native migration remains active. Direct Drive browsing/sync still needs
its native integration and a separate iOS OAuth client for
`com.zerus.notes.native`; see `docs/google-drive-ios.md`. Broader physical
mutation, cross-app clipboard, provider, accessibility/layout/rotation and
remaining mobile parity work are pending. Spoken dictation is deferred at
the user's request. This is a development preview, not an App Store or
TestFlight release.

## Native Google Drive file locations

Preview **0.3.55/1** adds a SwiftUI account/folder browser under Settings → File
locations → Google Drive. Each shared location also offers **Choose Google
Drive folder**. The developer must first configure the separate iOS OAuth
client for `com.zerus.notes.native` using the `--native` configuration command
in `docs/google-drive-ios.md`. An unconfigured build explains the missing
setup and disables sign-in. The system authentication session uses a window
from the presenting scene; tokens stay in the existing native Keychain manager.

Mappings store account/folder identifiers privately on this device. Shared
notes retain their original location ID and relative document path. Opening
an existing connected document freshly resolves every path component, rejects
duplicate names, shortcuts and Google-native documents, then rechecks its
version and the complete observed ancestor chain before exposing downloaded
bytes. A changed account, mapping, workspace or cancelled read rejects late
results. A fresh access request restores saved account status automatically.

Downloads are limited to ordinary files up to 50 MB, with bounded metadata
pages and response streaming even when Content-Length is absent or wrong.
The card shows progress and Cancel. Temporary snapshots use file protection
and remain alive through native Quick Look, sharing and portable copying.
The share controller retains a snapshot until the system's completion or
cancellation callback, including when its originating view closes. Released
snapshots are removed. Temporary downloads cannot become original connections
to disposable local files. Choosing Files instead replaces the Drive mapping;
disconnecting a mapping or account leaves shared notes and Drive originals.

The existing native Google authorization manager is reused without a web
editor. Existing Tauri requests retain their original unbounded-response path;
the new native reader explicitly requests its bounds. The configuration tool
keeps the two app bundles separate and preserves unrelated callback schemes
and scene settings through Xcode generation.

Direct Drive-vault editing/sync remains migration work. A native file-location
mapping does not open a Drive folder as a native vault. The separate OAuth
client has not yet been supplied, so live sign-in, consent, account expiry,
reconnect and actual Drive network reads remain unverified. The native goal
remains active; spoken dictation is still deferred at the user's request.

The final **NativeDriveFilesFinalOwners.xcresult** passes all **148 core checks
and the new native Drive journey** (149 unique checks), with no failures,
skips or XCTest runtime warnings. **NativeDriveFilesPhysicalOwners.xcresult**
passes the seven focused Drive/Files checks on iPhone 11 iOS 27.2, using
isolated temporary files. The other 33 UI journeys were not rerun. Existing
web Drive-backend regression coverage also passes 22 checks. A temporary
configuration project proves that native OAuth configuration survives
XcodeGen, retains other schemes/scene keys and leaves Tauri untouched;
default Tauri configuration leaves native files untouched. The real
repository's OAuth configuration was not changed.

File verification preserves all 81 earlier QA note/asset bytes, and every
file in the 342-file final baseline except the intentionally extended
`.zerus/file-locations.json`. The actual installed Simulator app is verified
as unconfigured 0.3.55, matching the setup UI. The three retained native setup
screens were inspected. Earlier failed bundles retain the alert-identifier,
combined-label, virtualized-row and controller-lifetime test corrections;
the final owner bundles above are the passing authority.

The exact retained signed Release **0.3.55/1** is installed on iPhone 11 Nox,
executable UUID `421C2632-4339-32CB-BD46-6C567E8B315E`, with matching symbols,
98 native source hashes and verified shared build inputs. PID 2957 remains
alive through 251.8 seconds. No new or changed diagnostic report appears.
Saved vaults and settings match the baseline except automatic lastOpened.
Read-only Device Hub inspection confirms the restored 483-note vault,
installed version and Drive setup fitting the phone with Done visible.
No personal note, account connection, mapping, Send, clipboard or microphone
action was committed. The live Drive sign-in/read path remains pending.

The Mac ran low on disk during verification. Six inactive generated compiler
and index directories were removed; source, vault files, signed apps/symbols,
all result bundles and verification records were retained. The browser preview
was refreshed on loopback port 8081 with `/app/`, and both loopback and the
private Tailscale `/app` route return HTTP 200. No public Funnel was enabled.

Evidence is under `artifacts/native-ios/`:

- `drive-files-final-owners-summary.json`, `drive-files-physical-owners-summary.json` and their `.xcresult` bundles.
- `drive-files-persisted-ui-proof.json`: prior note/asset preservation and actual installed configuration.
- `drive-files-configuration-proof.json`: executable configuration-tool/XcodeGen checks in a temporary project.
- `drive-files-signed-binary-proof.json` and `drive-files-device-binary/`: exact Release, symbols and input hashes.
- `drive-files-installation-proof.json`: installed process, settings, diagnostics and scoped validation.
- `drive-files-verified-attachments/`: inspected native screenshots.
- `drive-files-generated-cache-cleanup.json`: bounded generated-cache cleanup.

This is a development preview, not an App Store/TestFlight release. The full
native migration remains active.

## Native Drive vault working copies

Preview **0.3.56/1** adds **Open Google Drive vault** to welcome and saved-vault
settings. The native account/folder picker prepares a private ordinary-file
working copy and retains its account/folder association in the saved-vault list.
Completed caches reopen offline. Local saves and queued synchronization have
separate status; Settings offers manual sync, account reconnection and explicit
per-file conflict review. Cancelled opening retains the current Files vault.

A private ledger outside the vault records observed Drive versions, content
hashes and preallocated creation IDs. Incoming changes use the native coordinated
file transaction while preserving foreign bytes, headers, JSON, assets and
Drive dates. Updates/trash use conditional version locks; moves retain Drive
file IDs. Lost acknowledgements reconcile identity and bytes before retry.
Metadata-only remote changes do not create false body conflicts. Conflict choices
recheck the reviewed local bytes and remote metadata before applying anything.
Remote writes remain per-file; there is no atomic multi-file Drive transaction.

Bounds are 25 MB per upload, 50 MB per downloaded file, 256 MB incoming changed
bytes per sync, 100,000 entries and 64 levels. Duplicate/equivalent paths stop
opening. Shortcuts are not followed and Google-native documents are not
materialized. Duplicate-name repair, queued-create recovery after remote
relocation/replacement, damaged saved-registry recovery, unsupported-item
collisions and large-cloud behavior need further work. Live OAuth, consent,
reconnect/expiry and actual Drive version-lock behavior remain unverified: the
separate public iOS client for `com.zerus.notes.native` is still absent.

`NativeDriveVaultFinalOwners.xcresult` passes **152 core + two UI checks (154
unique)** with zero failures, skips or XCTest runtime warnings. The UI journeys
cover unconfigured Drive navigation/Cancel and saved-vault create/switch/rename/
remove/relaunch; the other 32 UI journeys were not rerun. All 267 pre-existing
ordinary QA note/asset files remain byte-identical, with four new synthetic
lifecycle files. The Personal QA vault also retains its 81 previously verified
notes/assets; only the synthetic location registry changes.
`NativeDriveVaultPhysicalOwners.xcresult` passes all **11 focused checks** on
iPhone 11 using temporary fixtures, with no failures/skips/runtime warnings.
These checks use the actual native vault/session and HTTP boundaries; they do
not establish live Google account behavior.

Retained failed-before-fix results demonstrate Drive ID replacement on moves,
hidden revision IDs interfering with live-note matching, cancelled opening
changing selection, download-time timestamps, and false metadata-only conflicts.
The final owners pass after those repairs. They are retained respectively as
`NativeDriveVaultBeforeMove.xcresult`,
`NativeDriveVaultRevisionIdentityBefore.xcresult`,
`NativeDriveVaultCancelledOpenBefore.xcresult`,
`NativeDriveVaultDatesBefore.xcresult` and
`NativeDriveVaultMetadataBefore.xcresult`.

QA artifact correction: an earlier helper accidentally overwrote the raw
0.3.55 `drive-files-qa-before.json` baseline. That filename now records the
incident honestly; the original raw baseline was not reconstructed. The earlier
installation proof/results remain, and 0.3.56 uses its own
`drive-vault-qa-before.json`. No vault data was affected by the filename error.

The exact retained signed Release **0.3.56/1** is installed on iPhone 11 Nox,
UUID **4034842A-F04A-3BD4-855C-E11D4100B558**, executable SHA-256
`4d91b5e99953bd0abf69896fab6ff274f8d5e03825ee06b265ba087be885e445`.
PID **2979** remains alive for **94.2 seconds** through final capture. The
profile/device, signature, matching dSYM, 101 source files and shared build inputs
are verified. No new or changed diagnostic reports appeared. Settings and saved
vaults match their baseline except automatic lastOpened updates. The vault
restores 483 notes; read-only inspection confirms version, current iCloud vault,
the Drive-vault action and its setup/Done fitting the phone. No account, mapping,
personal-note, Send, clipboard or microphone action was committed. Keyboard
capture is off. Spoken dictation remains deferred at the user's request.

Evidence is retained under `artifacts/native-ios/` in
`drive-vault-installation-proof.json`, `drive-vault-signed-binary-proof.json`,
`drive-vault-device-binary/`, `drive-vault-final-summary.json`,
`drive-vault-persisted-ui-proof.json`, `drive-vault-all-vaults-proof.json` and
`drive-vault-physical-observations.json`, with the named result bundles above.
The web preview responds through loopback and the private Tailscale Serve route;
it remains the existing web interface, not proof of native behavior. No public
exposure change, App Store upload or release was performed. The native migration
remains active with the limitations above.

## Interrupted Drive uploads with continued writing

Preview **0.3.57/1** repairs a false conflict after Google Drive accepted a file
but the upload response was lost and local writing continued. The private sync
ledger now records the sent file identity and content hash before create/update.
A later sync recognizes exactly those accepted bytes, advances only the baseline,
and uploads the newer local draft under the observed version lock. Removing a
new file before retry trashes its accepted Drive identity rather than downloading
and resurrecting it. A remote identity with different bytes still requires
review. Accepted conflict choices clear obsolete pending records. Older ledgers
without the optional sent-hash map continue to open.

The existing recovery owner now exercises actual local files, durable backend
reopening, continued writing after lost create/update responses, removal before
retry, and independently changed remote content requiring review. Its pre-fix
failure is retained in **NativeDriveSentBytesBefore.xcresult**: the continued
create draft incorrectly raised NativeDriveConflictRequired. The focused
repair batch passes 11 checks. **NativeDriveSentBytesFinalCore.xcresult** passes
all **152 core checks**, without failures, skips or XCTest runtime warnings.
No UI flow changed; the 34 UI journeys were not rerun. All 271 retained ordinary
QA note/asset file hashes match the preceding preview; no new ordinary QA files
were created by this core-only batch. Live OAuth/consent/reconnect/expiry and
real Drive version locks remain pending the separate native client.

**NativeDriveSentBytesPhysicalOwners.xcresult** passes all **11 focused checks**
on the iPhone 11 with temporary fixtures, zero failures/skips/runtime warnings.
The exact retained signed Release **0.3.57/1** is installed on that phone,
UUID **9232EE88-0594-3ADC-80FA-3846F0F22376**, SHA-256
`3f4626003f7fd87401da3cbe72c338de11083d89e5b57da49eaf2edf12defbcd`.
PID **2987** remains alive for **72.0 seconds** through final capture, with no
new or changed diagnostic reports. The signature/profile/device, matching dSYM,
101 native source hashes and shared build inputs are verified. Only the native
Drive vault backend source changed from 0.3.56, alongside its existing recovery
test and preview version/project. Settings and saved vaults match their baseline
except automatic lastOpened updates. Read-only inspection confirms the restored
483-note vault and Settings version 0.3.57 (1), with Done visible. No account,
mapping, personal-note, Send, clipboard or microphone action was committed;
keyboard capture is off and spoken dictation remains deferred.

Evidence: `drive-sent-bytes-installation-proof.json`,
`drive-sent-bytes-signed-binary-proof.json`, `drive-sent-bytes-device-binary/`,
`drive-sent-bytes-final-summary.json`, `drive-sent-bytes-persisted-vault-proof.json`,
`drive-sent-bytes-source-change-proof.json`, `drive-sent-bytes-test-plan.md`,
`drive-sent-bytes-physical-observations.json`, and the named result bundles under
`artifacts/native-ios/`. The private web preview was refreshed on loopback 8081
with `/app/` base and verified through Tailscale Serve; no public exposure was
changed. The broader native migration and the previously listed Drive recovery,
provider, physical editing and accessibility work remain in progress. No release,
archive, TestFlight upload, commit or PR was requested or created.

## Reviewed Drive note and history snapshots

Preview **0.3.58/1** repairs conflict application when a note and an existing
history record change independently on both devices. The reviewed Drive files
now enter the native coordinated transaction with exact-byte preservation,
including foreign JSON/CRLF resources, rather than deriving automatic history
again and colliding with the selected history record. Supported native local
saves have already captured their drafts; the repair preserves other existing
history resources. Choosing Drive also restores its modified/creation dates,
with an expected-hash guard so a newer local write keeps its own metadata.

The new primary owner uses actual native note/history saves, simultaneous note
and history-metadata conflicts, explicit Drive choices, retained local draft
reconstruction and a fresh offline backend reopen. It adds no test-only production
entry point. **NativeDriveConflictSnapshotBefore.xcresult** fails with “History
files conflict with another prepared change.” After exact-byte application was
repaired, **NativeDriveConflictDatesBefore.xcresult** passes content/history
checks and fails only the offline modified-date assertion: replacement time
instead of the reviewed server date. The final repair restores those dates.
Live OAuth/consent/reconnect/expiry and actual Drive version-lock verification
still require the separate public native client.

**NativeDriveConflictSnapshotFinalCore.xcresult** passes all **153 core checks**,
with no failures, skips or XCTest runtime warnings. The 34 UI journeys were not
rerun for this backend-only change. **NativeDriveConflictSnapshotPhysicalOwners.xcresult**
also passes the **12 focused checks** on the iPhone 11 with temporary fixtures,
including the new graph/history/date owner, with zero failures/skips/runtime
warnings. All 271 retained ordinary QA note/asset hashes remain unchanged.
Regenerable inactive Tauri macOS build-script output and fingerprints were
removed to free build space, with no Cargo/Rust compilation active; signed apps,
symbols, archives, result bundles, source and vault data were retained. This is
recorded in `drive-conflict-generated-cache-cleanup.json`.

The exact retained signed Release **0.3.58/1** is installed on iPhone 11 Nox,
UUID **CCA22897-49F9-3DC3-9CF9-D7ED9C41682A**, SHA-256
`b0e5e2f9e0f298ce50eeb1d7aa1b46ed8ce49c29870281294b48031b82852485`.
PID **3003** remains alive for **58.4 seconds** through final capture. The
signature/profile/device, matching dSYM, 101 native source hashes and shared
build inputs are verified. No new Zerus crash/Jetsam report or changed prior
report appeared. One new **Apple IMDPersistenceAgent** diagnostic (bug type 308,
EXC_GUARD, lightweight corpse) reports an Apple iconservices icon-cache-path
fault. Its system executable/bundle identity is verified and the retained report
contains no Zerus reference; it is recorded separately rather than omitted.
Settings and saved vaults match baseline except automatic lastOpened updates.
Read-only inspection confirms 483 restored notes and Settings version 0.3.58 (1).
No physical account, mapping, personal-note, Send, clipboard or microphone action
was committed. Keyboard capture is off; spoken dictation remains deferred.

Evidence under `artifacts/native-ios/` includes
`drive-conflict-snapshot-installation-proof.json`,
`drive-conflict-snapshot-signed-binary-proof.json`,
`drive-conflict-snapshot-device-binary/`,
`drive-conflict-snapshot-final-summary.json`,
`drive-conflict-snapshot-persisted-vault-proof.json`,
`drive-conflict-snapshot-source-change-proof.json`,
`drive-conflict-snapshot-test-plan.md`,
`drive-conflict-snapshot-other-diagnostics.json` and the named result bundles.
The web server was refreshed on loopback 8081 with `/app/` base; both it and the
private Tailscale Serve route respond successfully. No public exposure changed.
The native goal remains active with the previously listed Drive recovery,
provider, physical editing and accessibility work. No archive, TestFlight upload,
release, commit or PR was requested or created.

## Restoring private Drive vault access

Preview **0.3.59/1** restores a completed private working copy’s account/folder
association from its sync record when the saved-vault registry is missing,
unreadable, newer than supported, or has an older saved row without Drive fields.
Startup bookmarks, saved-vault selection and direct cache-folder opening use the
same restoration path. Recovered caches keep Drive sync status and offline native
writing; missing saved lists can be rebuilt. Unreadable/newer original registry
bytes remain unchanged and the list warning stays visible. The Drive folder name
is used when no saved friendly name is available.

Only this app’s private cache roots confer the association. Selection fields,
state version, baseline/pending records and account/folder directory hash must
validate. A copied state.json in an ordinary Files folder is ignored. Incomplete,
malformed, differently bound or redirected private records refuse activation
rather than silently becoming Files vaults, while retaining original files and
records. Existing dirty-draft and vault-generation guards still apply across the
additional asynchronous lookup. Saved-list removal now explains choosing the
same Drive folder again; ordinary Files removal keeps its existing guidance.

The primary owner uses unique real application-support cache identities, actual
bookmarks/preferences, native note saves and production restore/open entry points.
It covers missing/malformed/future registries, older saved rows, direct opening,
offline writing, exact original registry preservation, ordinary copied records,
bad/misbound private records and an outside symlink. No production test override
is added. **NativeDriveCacheRestoreBefore.xcresult** fails at the intended boundary:
Drive selection is nil, the name becomes Vault and queued sync state is absent;
damaged private records also fall through to Files. The first focused cache,
Drive and ordinary saved-vault batch passes after repair. Live Google consent,
reconnect/expiry and actual Drive version locks remain unverified without the
separate public native client.

**NativeDriveCacheRestoreFinalOwners.xcresult** passes **154 core + two UI checks
(156 unique)**, with zero failures, skips or XCTest runtime warnings. The Drive
setup/navigation/relaunch and saved-vault create/switch/rename/Cancel/remove/
relaunch journeys pass together. Other 32 UI journeys were not rerun.
**NativeDriveCacheRestorePhysicalOwners.xcresult** passes **15 focused checks**
on the iPhone 11, using isolated fixtures including actual private cache paths
and the ordinary saved-vault owners; no failures/skips/runtime warnings.
All 271 preceding ordinary QA note/asset hashes remain exact, with four new
synthetic lifecycle files and verified separate personal/project writing. The
new shared location **Drive location E19612** persists in the actual active QA
vault `Vaults/Personal E78DF2/.zerus/file-locations.json`; the earlier Personal
2B21DA vault also retains its 81 verified note/assets and captured shared bytes.
The unconfigured Drive UI commits no account/provider operation.

The exact retained signed Release **0.3.59/1** is installed on iPhone 11 Nox,
UUID **592553AC-73B0-3184-A138-CD2F9A7AB827**, SHA-256
`7090525f0f8d727fb0cbfff45f3d5638aede941d5d6ac24656c651a19d31842f`.
PID **3042** remains alive for **72.5 seconds** through final capture, with no
new or changed device diagnostics. Signature/profile/device, matching dSYM,
101 native source hashes and shared inputs are verified. Settings and saved
vaults match baseline except automatic lastOpened updates. Read-only inspection
confirms 483 restored notes and Settings version 0.3.59 (1), with Done visible.
No physical account, mapping, personal-note, Send, clipboard or microphone action
was committed. Keyboard capture remains off; spoken dictation stays deferred.

Evidence under `artifacts/native-ios/` includes
`drive-cache-restore-installation-proof.json`,
`drive-cache-restore-signed-binary-proof.json`, `drive-cache-restore-device-binary/`,
`drive-cache-restore-final-summary.json`, `drive-cache-restore-persisted-vault-proof.json`,
`drive-cache-restore-persisted-ui-proof.json`, `drive-cache-restore-source-change-proof.json`,
`drive-cache-restore-test-plan.md` and the named result bundles. Only regenerable
inactive Tauri iOS build-script outputs/fingerprints were removed for build
space; signed binaries, symbols, archives, result bundles, source and vault data
were retained (`drive-cache-generated-cache-cleanup.json`). The web server was
refreshed on loopback 8081 with `/app/` base, and both it and private Tailscale
Serve respond successfully; no public exposure changed. The full native goal
remains active. Damaged/incomplete private sync baselines are preserved/refused,
not automatically reconstructed; other remaining Drive/provider/physical editing
and accessibility work is tracked above. No archive, TestFlight upload, release,
commit or PR was requested or created.

## Native note outline and heading links

Preview **0.3.60/1** adds **Note actions → On this note**, a native outline of
Markdown document headings. Choosing a heading closes the sheet before selecting
and revealing it. The same TextKit 2 path follows local fragments, cross-note
Wiki headings and relative Markdown file fragments, including links opened from
native table cells. Existing exact note names take priority over a possible
heading suffix. Property/relation values retain their previous exact-target
semantics; only note-body links opt into heading resolution.

Headings use readable Unicode slugs with numbered duplicate suffixes, or their
exact displayed heading title. URI fragments are decoded once. Fenced examples
are excluded; ATX and Setext source ranges retain UTF-16/UTF-8 position accuracy,
including CRLF, accents and emoji variation selectors. The outline uses Wiki
link captions when a heading contains a note link. Source-mode jumps select the
original Markdown heading without its trailing newline. Missing headings explain
how to choose a current heading, without opening Files or changing the note.

Cross-note requests bind to the current visit/workspace and wait for native
layout, while Back/Forward and normal note saves retain their ownership guards.
TextKit 2 relocates and lays out its viewport at the requested text location
before positioning the scroll view. This avoids clamping a source-mode jump
against an obsolete content-height estimate after changing editor modes.
Surrounding text remains visible where the end of the document permits. Navigation does not open a
keyboard, write note content or clear existing Undo. Native move/rename rewriting
retains the section suffix when stabilizing a title link, and keeps the label.

The real text bridge owner covers duplicate Unicode headings, fenced examples,
source/Setext/CRLF ranges, visible source geometry, missing headings, unchanged
original bytes and Undo of a genuine edit made before navigation. The navigation
owner covers exact names containing #, relative file headings, current-visit
requests, save-before-navigation and rejection of late callbacks/workspace changes.
The existing rename owner covers the preserved section suffix in actual saved
files. The UI journey follows a deep cross-note link, opens the outline, changes
source mode, uses Back/Forward and reopens the saved note; its screenshots are
inspected as well as the status result.

Retained development results: `NativeHeadingNavigationBefore.xcresult` shows the
old local-link delegation and missing selection/scroll; `NativeHeadingNavigationOwners.xcresult`
shows correct selection but missing viewport layout; `NativeHeadingRenameBefore.xcresult`
shows dropped section suffixes; `NativeHeadingLifecycleOwners.xcresult` shows
trailing CRLF selection and a heading stranded at the bottom edge. Earlier focused/polished green runs were superseded after inspecting their
source screenshots: selection assertions included offscreen text and missed
an incorrect viewport. The strengthened UI owner recognizes actual screenshot
pixels using Vision and failed at its Deep section assertion before the viewport
repair. Its console is retained as `heading-visible-source-baseline.log`; its
result bundle is incomplete because Xcode diagnostics exhausted storage and
were interrupted. Subsequent runs disable automatic simulator sysdiagnose,
retaining ordinary XCTest results, console logs and screenshots.

`NativeHeadingVisibleSourceOwners.xcresult` passes the real bridge owner and
strengthened UI journey (2 checks), with the inspected rich deep heading,
rich first heading and source deep heading all visible without a keyboard.
`NativeHeadingReleaseOwners.xcresult` passes all 156 core checks. These results
have zero failures, skips or XCTest runtime warnings. The existing rename screen
journey passes separately in `NativeHeadingRenameReleaseOwners.xcresult`; nine
focused core checks also pass on the physical iPhone 11 in
`NativeHeadingReleasePhysicalOwners.xcresult`. Together this covers 156 core
checks plus two relevant UI journeys (158 unique native checks, 168 completed
executions including overlaps and physical repeats). The other 33 UI journeys
were not rerun.

The retained signed Release **0.3.60/1**, UUID
**E05CFA70-780C-3C84-9356-FFBE50891881**, is installed on **iPhone 11 Nox,
iOS 27.2**, with matching symbols, verified device profile/signature and 102
native source hashes plus shared build inputs. PID 3081 stayed alive through
**157.3 seconds** with no new or changed diagnostics. Settings and saved vault
registrations match except automatic lastOpened timestamps. The screen still
shows 483 restored notes. Read-only inspection of “Collapse chart legend” confirms
native heading/bold/image/list rendering and outline navigation to Acceptance
Criteria in both rich text and source; the phone is left in rich text. No note,
account, mapping, clipboard, microphone or Send mutation was performed there.
All 289 preceding ordinary simulator QA note/asset hashes remain exact; four new
synthetic heading/rename files have their independently expected bodies, stable
IDs and labels. See `heading-navigation-installation-proof.json`,
`heading-navigation-persisted-vault-proof.json` and the retained
`heading-navigation-device-binary` app/symbols.

The outline currently includes document-level Markdown headings, not headings
nested inside lists/quotes or HTML-only heading blocks. Native readable Unicode
slugs need not match every external renderer. Very large documents/headings,
broader IME/accessibility/rotation/long-use checks, live OAuth/Drive, remaining
native parity and provider verification remain. The user deferred spoken
dictation; the full native goal remains active.


## Native open-note session restoration

Preview **0.3.61/1** adds a device-private saved view for vault notes. Leaving a
note open and relaunching restores its current visit, Back/Forward branch,
return tab, editor mode, selection and visible reading position. A native text
location plus a relative line offset survives TextKit’s changing layout
estimates; absolute scroll pixels are not used as the durable anchor. The body
hash and mode must still match before positions apply. Restored notes do not
open a keyboard, including a note containing only its title.

The private `zerus.native.note.resume` preference stores at most 100 visits for
each saved-vault registration, with stable note IDs and legacy content hashes.
It contains no note bodies or external file-access authority. Unique identities
follow moved/renamed files. A missing, trashed, replaced or ambiguous current
note is refused, while unavailable older visits are omitted with an explanation.
Legacy files must retain their exact original bytes to be resumed without an ID;
reading/restoring them does not itself inject metadata. A new active view owns
its record, so late callbacks from an older window or vault activation cannot
replace or clear it. Explicit Close note keeps that view closed next launch.

Successful iOS Files handoffs supersede the prior saved vault view even when
onOpenURL delivery wins the startup race. Independent external-file editors are
not automatically reopened by this vault-session record. Unknown/newer,
malformed, escaping, oversized or otherwise unreadable records remain intact;
they do not grant file access or stop ordinary note selection.

The real app relaunch owner first failed before implementation because its open
source note disappeared. It then verifies Forward, a deep reading position,
source-mode restoration recognized in actual screenshot pixels and explicit
Close. The existing cold file-handoff owner now begins with a real open vault
note; it failed when the superseded vault editor returned after another launch.
The storage owner checks fresh activations, renamed stable IDs, duplicate/missing
current targets, legacy bytes, a bounded history, invalid records and old-owner
rejection. A separate hosted TextKit owner checks the same text’s actual screen
position/selection in fresh views, plus body/mode mismatch refusal and no editing
or keyboard activity. See `session-restoration-test-plan.md` and the associated
native result bundles in `artifacts/native-ios` for current validation status.
Physical delivery is recorded below.


The full `NativeSessionRestorationFinalOwners.xcresult` run passes **159 core
checks and four UI journeys (163 unique)** without failures, skips or XCTest
runtime warnings. A final small change coalesces repeated unreadable-view alerts:
its canonical storage owner fails before repair in `NativeSessionWarningBefore`
and passes afterward in `NativeSessionWarningOwners`. The only production delta
after the full run is that warning policy in `NativeNoteNavigation.swift`; input
hashes and the exact delta are retained. All **12 focused physical checks** pass
on the final sources in `NativeSessionPhysicalOwners.xcresult`. This totals 176
authoritative passing executions including repeats; the other 32 UI journeys
were not rerun. All 298 preceding ordinary simulator QA note/asset hashes remain
exact. Seven new ordinary files have their independently expected heading,
resume, superseded-view or rename/reference content; the UI explicitly closes
or supersedes every saved view and leaves no queued resume record.

The exact retained signed **0.3.61/1**, UUID **E1D314CB-2146-38A3-BBF0-96F3191E4632**,
is installed on **iPhone 11 Nox, iOS 27.2**, with matching symbols, verified
signature/profile and 103 native source hashes plus shared build inputs. Initial
PID 3212 was observed for 55.3 seconds; source-restored PID 3220 for 55.2
seconds; final rich-restored PID 3229 for 137.0 seconds. Read-only inspection of
“Collapse chart legend” confirms the same Acceptance Criteria section returns
in both modes, with the native chart image/list present after rich relaunch.
The phone is left in rich text with no keyboard. The collection still shows 483
notes. Settings and saved vault registrations match exactly except lastOpened;
the newly validated private resume record is the expected additional preference.
No personal note edit, account/mapping, clipboard, microphone or Send action was
performed.

Two combined CoreDevice terminate-and-launch attempts returned error 10004 with
no process to inspect. A monitored retry stayed alive despite the console
monitor’s 30-second timeout; subsequent source and fresh rich launches succeeded.
The final rich launch followed an authoritative absent-process check and omitted
the combined terminate option. All errors/inspections are retained; no new Zerus
crash or Jetsam report appeared. The only two new device reports were Siri search
feedback, bug 313, with no Zerus reference or process/crash fields. See
`session-restoration-installation-proof.json`, `session-restoration-visual-proof.json`,
`session-restoration-persisted-vault-proof.json` and the retained
`session-restoration-device-binary` app/symbols.

Full native parity remains active. Independent external editors and task/chat
presentations, broader simultaneous-window, large-provider/long-document,
VoiceOver/IME/rotation/long-use and live-provider verification remain outside
this completed vault-note session implementation. Spoken dictation remains
explicitly deferred; native public iOS OAuth configuration is still absent.

### Native Files and Photos in Ask — preview 0.3.62

Ask's Attach menu uses the system Files and Photos pickers. It accepts readable
PDFs, UTF-8/UTF-16 text-based files and images. Selections become private frozen
copies: the original file stays unchanged, and each conversation shows its own
attachment cards with native previews and a Use in message action. Unsent cards
survive process relaunch alongside the existing prompt draft; removing an unsent
card does not remove an input retained by a sent conversation. Preview opens a
separate temporary copy. Imports show progress, support cancellation and discard
late results after leaving their workspace.

Files are limited to 50 MiB each and 100 MiB of combined source/extracted-text
processing per selection. Up to four images are sent per request, including any
retained recent conversation images. ImageIO applies orientation, downsamples to
1024 pixels, flattens transparency onto white and creates JPEGs of at most 3 MiB
without the source's location metadata. PDFKit extracts readable PDF text; locked,
empty and scanned PDFs without readable text are refused. Text remains in private
storage; large documents contribute explicitly labelled, bounded excerpts selected
for the current question. Reuse a document in a new message to prepare excerpts
for another question. Earlier images omitted by the four-image budget are named
as omitted, so the provider must not claim to see them.

Ask, Review and Edit use the same frozen inputs. Images reach the configured API
or ChatGPT Responses adapter as real JPEG pixels. The selected model must support
image input. Files are reference data and grant no additional note permissions.
Run journals contain descriptors, never arbitrary source paths or base64 pixels;
private run grants bind snapshots to the run and conversation before loading an
image. Missing, replaced or tampered snapshots fail with a recovery message.
Unknown draft formats are preserved, with sharing and an explicit recovery-copy
reset available. These records currently share the native chat storage limitation
around vault-root/container moves; this is not a web-history migration.

The Files/Photos UI and synthetic transport checks use the dedicated **Zerus
Native Move QA** simulator. To recreate inputs after installing the native app:

```sh
python3 native-ios/Fixtures/prepare-chat-attachments.py --simulator 9A0184A7-2BD1-43B6-9CBB-532270F9DD5C --proof artifacts/native-ios/chat-attachments-fixture.json
python3 native-ios/Fixtures/chat-attachment-provider.py --port 8769 --log artifacts/native-ios/chat-attachments-provider-requests.jsonl --proof artifacts/native-ios/chat-attachments-provider-verification.jsonl
```

The attachment journey uses the private `/native-attachment-qa` HTTPS route to
that loopback fixture. Its request log excludes authorization headers and must
only contain synthetic inputs. The ordinary agent fixture also accepts text/image
content arrays when a prior synthetic conversation contains photos. This fixture
supplies tool calls; it still cannot fabricate the app's reads, reviews, receipts
or undo. Live personal-provider and OAuth verification remain separate.

Validation for 0.3.62 is retained in `artifacts/native-ios/` under
`chat-attachments-installation-proof.json`, `chat-attachments-transport-proof.json`
and `chat-attachments-final-summary.json`. The final outcomes cover 163 core
checks and four UI journeys (167 distinct checks), plus four repeats on the
physical iPhone 11. The large owner bundle passed all core checks and both
existing AI journeys; its Files launcher selected Ask before the restored note
appeared. Only the UI launcher wait and per-import card selector changed before
the passing Files repeat. A compile-only selector typo was corrected in that
repeat. The installed 106 production sources match every passing run; all 169
original suite inputs match except that one explicitly recorded UI test file.
There are no final skips or runtime warnings; the other 34 UI journeys were not
rerun. All 413 preceding ordinary QA files retain their hashes. Three newly
created synthetic AI notes are recorded separately.

The synthetic API received three actual requests, one per mode. Independent
inspection matched the JPEG bytes to the private grant/manifest/run, decoded
1024 × 683 pixels, checked the expected red/blue colors and found the document
marker. Cold reopen and historical image reuse are exercised. Original Files
and photo fixtures retain their hashes. This verifies transport with the local
fixture, not a live model's vision quality or account authentication.

The exact retained signed app and matching dSYM are in
`artifacts/native-ios/chat-attachments-device-binary/`, executable UUID
`450A0B67-E3E6-31F5-BB1D-DC02DDC46EDE`, SHA256
`d7c3cfe2562cefa1dfe6be3b4b46aed19a72b4cf7795c93e1df3f9a093965c33`.
CoreDevice installed it and launched PID 3281, observed alive after 137.4s. No
new Zerus crash or Jetsam report appeared; one new Siri feedback bug-313 record
has no Zerus reference or process/crash fields. Phone preferences and saved vault
registrations are preserved apart from lastOpened and the saved note-view record
cleared by explicitly closing the restored chart note. The native Attach menu
and system Files sheet were checked and cancelled, leaving an empty unsent
composer. No personal note, provider Send, clipboard or microphone interaction
was performed. Spoken dictation remains deferred by the user.

The native test wrapper now defaults to `-collect-test-diagnostics never` to
avoid automatic sysdiagnose disk growth. Temporary synthetic provider servers
and their private Serve routes were removed after verification. The frontend
was restarted on loopback 8081 with `/app/`; both loopback and private Tailscale
Serve return 200 at the documented preview. No Funnel was enabled. This native
preview does not advance the canonical Tauri/App Store version, create an
archive or upload to TestFlight. The broader native migration remains active.

### Saved-vault chat continuity — preview 0.3.63

Native conversations, prompt drafts, archives, frozen attachments and private run
inputs now follow the saved vault identity. Moving its folder or installing an
app update that changes the iOS data-container UUID no longer sends Ask to an
empty path-derived directory. An unambiguous older hash folder is adopted in
place: its existing bytes and filenames remain intact, including unknown files.
A small device-private `vault.json` binds that whole folder to the saved vault;
it records current canonical/literal roots and an app-owned Documents-relative
identity. Obsolete absolute roots are removed rather than accumulating across
updates or identifying a different library later placed at the old path.

UUID letter casing is normalized. Registered identities take precedence over
path names. Same-vault windows and moved paths share one live conversation;
a changed/missing registration cannot reuse an obsolete cached path blindly.
Search reads the same bound history. Existing unknown metadata fields survive
updates. Ambiguous, newer, malformed or linked bindings remain preserved and
block Ask with a retry message; they are not silently merged or overwritten.
Raw old hash folders whose original identity was never recorded cannot always
be assigned safely; their recovery UI and web-history migration remain open.

Validation is retained under `artifacts/native-ios/chat-continuity-*`. The original
root-move owner failed on absent messages, drafts, archives and inputs before the
repair. Further identity owners failed on valid UUID casing, a foreign UUID and
a reused former path before their respective fixes. Final167 core checks pass.
The saved-vault and note-session UI journeys pass before those last two
identity-hardening source changes. The final Files lifecycle and real install
journeys pass on hardened production sources, yielding171 distinct checks across
the owner bundles. Other35 UI journeys were not rerun. All 416 preceding ordinary
QA files retain their hashes; new synthetic session/vault files are recorded
separately. Earlier Files selectors confused background restored cards with the
system picker; the corrected helper uses Files cells and per-import UUIDs.
A retry with an already-equal prompt now dismisses the keyboard only if present.

The dedicated QA install fixture performs a real `simctl install`, not a rewrite
of app records. In the final run a normal install changed the data container from
`57BFC12E-79E9-4BA5-9A38-BE928BB9DE0F` to
`CDC63127-56F2-47DC-95DB-256BE7B74995`. All 6,506 tracked document, application-support
and preference files kept their hashes before the app relaunched. The app itself
then refreshed the root binding; its saved-vault ID, exact unsent prompt and three
frozen attachments reopen and preview correctly. Every snapshot digest matches
and the original Files document is unchanged. The optional explicit relocation
fallback in the fixture was **not used**. No host bookmark/chat rewriting, live
provider Send or speech input was involved. `chat-continuity-final-container-proof.json`
and the host receipt record this distinction. The update image is a QA-only
ad hoc 0.3.63/2 copy; the signed physical preview remains 0.3.63/1.

Thirteen owner repeats pass on the iPhone 11. An automated cancellation-before-
capture case emits one pre-existing AVAudioSession main-thread deactivation
performance warning from the shared speech recognizer; this remains an explicit
next fix, not a zero-warning claim. No speech was captured and no permission was
requested. The user's actual spoken test remains deferred. One deliberately
failing simulator case aborted before its defer restored QA selection; its
preference restoration now uses XCTest teardown, and the original QA vault was
reopened through the app UI. The failed private test records remain preserved.
The physical test run preserved the phone's preferences exactly.

The retained signed app and dSYM are in
`artifacts/native-ios/chat-continuity-device-binary/`. Its executable UUID is
`CED76B7C-DD4F-39E2-A04C-FF7C85178014`, SHA256
`80f05bddfc95d3a080475999c11968c14d4cb40f9fa421e146523804ed2a24cf`.
CoreDevice installed and launched PID 3316, observed alive after 518.9 seconds. No new
Zerus crash/Jetsam report appeared; an unrelated Siri feedback bug313 record was
inspected. The collection still shows 483 notes. The chart note opens as formatted
rich text with bold writing and its chart, with Saved status and no keyboard.
It was closed without editing; Ask is left open with an empty unsent composer.
Other settings and saved-vault registrations are preserved except lastOpened
and the saved view cleared by explicit chart open/Close.

The installation proof binds all 107 native sources, shared build inputs and the
exact binary. The final test-only helper delta is recorded separately, along
with the two earlier UI source deltas and audio warning. Temporary QA server and
Serve route were removed. The frontend was restarted on loopback 8081 with
`ZERUS_PREVIEW_BASE=/app/`; both it and the private Tailscale `/app` route return 200.
No Funnel, canonical Tauri version change, archive or TestFlight upload occurred.
The full native migration and broader parity/long-use/accessibility work continue.

### Asynchronous speech cleanup — preview 0.3.64

The shared modern and legacy speech recognizers now use an owned, serialized
audio session. Idle cancellation no longer deactivates the system audio session.
iOS 27 uses asynchronous activation/deactivation; the older-system fallback
runs on a serial background queue. Cancellation drains an in-flight activation
and system deactivation before ownership is released. Repeated Stop or Stop
during preparation cannot start a competing finalization. The native controller
and existing Tauri bridge await the actual recognizer cleanup.

The existing cancellation-before-capture owner retains its real pre-fix warning
in the 0.3.63 evidence. On the final 0.3.64 sources, all 167 native core checks
and the same physical iPhone 11 owner pass with no failures, skips or runtime
warnings. Physical-test preferences match their baseline exactly. Actual speech
capture and permission approval were not attempted; the user's dictation test
remains deferred. Older-iOS runtime behavior and active-capture cancellation,
interruption/route changes and model downloads still need physical verification.

Actual modern/legacy/shared audio files type-check for an iOS 17 simulator target,
and all mobile-vault Swift sources type-check against actual compiled SwiftRs,
Tauri and ChatGPTCore modules. Existing unrelated dependency/bridge compiler
warnings are retained. This is a compile check, not an older-OS or Tauri launch
claim. Other native UI journeys were not rerun for this cleanup-only change.

The signed 0.3.64/1 app and matching dSYM are retained in
`artifacts/native-ios/audio-session-device-binary/`. Executable UUID:
`FF1B34E8-6B26-35BB-A106-D885CD713808`; SHA256:
`93139a56ef782bdca87b3bdec8251f71f0f523581b3663ddfff17c79ae2d2daf`. CoreDevice installed and normally
launched PID 3356, observed alive after 63.9 seconds. No new crash or Jetsam
report appeared. The 483-note collection restored; Ask was opened with an empty,
unsent composer, preserved Review mode and model, no keyboard and no capture.
Preferences are unchanged except automatic vault lastOpened. No note, clipboard,
permission or Send action occurred.

`audio-session-installation-proof.json` binds all 107 native sources, shared
speech/build inputs, signature/profile/scene/keychain checks, exact binary and
physical observations. The source/test fingerprints remained unchanged during
compilation and checks. The frontend was refreshed with `ZERUS_PREVIEW_BASE=/app/`
on loopback port 8081; frontend and private Tailscale `/app` both return HTTP 200.
No Funnel, canonical Tauri version change, archive, upload, PR or commit occurred.
README feature/setup claims were reviewed and remain applicable. The broader
native migration and parity work remain active.

### Vault instructions and editable memory — preview 0.3.65

Ask → AI settings → AI instructions and memory, and Settings → AI instructions
and memory, open a native editor. Save commits the pair together; Done closes a
clean form. Cancel offers explicit Keep editing and Discard changes. Reload saved
version confirms before discarding a draft. Share this draft can export unsaved
writing. Changing the active vault retires the old editor and retained callbacks
cannot save into another vault.

The target reads and writes the existing `.zerus/ai/instructions.md` and
`.zerus/ai/memory.md` files, preserving unchanged file bytes. UTF-16 limits match
the existing mobile editor (12,000/8,000). Reads coordinate both files, bound
allocation, loop through partial file reads, verify observed size and reject invalid UTF-8, oversized data, non-files and links. Missing
files mean empty guidance, without creating files merely by opening the editor.
Exact-byte compare-and-swap protects both files, and the normal recoverable vault
transaction commits the pair. A stale save preserves the current files and the
unsaved editor text for sharing or an explicit reload.

Every new native AI run reads and freezes guidance in its durable journal.
Resume keeps that exact snapshot, including after app restart and later edits in
the other app. Legacy runs without guidance stay compatible and never silently
acquire current instructions. Instructions can guide style and process but cannot
override the current objective/mode/scope; memory is reference data. Runtime note
permissions remain enforced independently. Invalid guidance blocks a new run
instead of silently dropping configured text. Conservative fallback input usage
now includes the actual system prompt bytes.

The final combined result `NativeGuidanceVerifiedCoreAndUI.xcresult` passes
170 core checks and the complete native guidance journey, with zero failures,
skips or runtime warnings. The three guidance owners also pass on iPhone 11 in
`NativeGuidanceFinalPhysical.xcresult`. The pre-change missing-instructions
regression, UI-query failures, compact-popover problem and initial disk-full
linker failure remain retained. The final valid edit reaches the real Ask-mode
permission guard; exact-limit Unicode files round-trip without truncation.

The signed 0.3.65/1 app and matching dSYM are retained in
`artifacts/native-ios/guidance-device-binary/`. UUID:
`31987BED-6678-37F4-B287-69494A1B46EB`; SHA256:
`22049a9c35d1c0e603101ec569d2353efb5f32f75d4d51d0f48ef399039506a5`. PID3365 stayed open through
212.8 seconds with no new crash or Jetsam reports. The physical form displays
both empty guidance fields, their counters, disabled Save, Share draft and Reload.
It was closed without editing; the 483-note collection restored and Ask remains
empty/unsent with no keyboard. Phone preferences match except lastOpened.
No personal note, instruction, memory, clipboard, microphone or Send mutation.

`guidance-installation-proof.json` binds all109 native sources and shared inputs,
the exact signed executable, tests and physical observations. The actual QA files
contain the final saved instruction/memory pair; the second vault has no guidance
files. All6706 other existing QA files match their baseline and none are missing.
One private original-vault chat binding changed during repeated simulator
installations; its resulting ID/roots were inspected, but exact prior bytes were
not retained. This exception is explicit in `guidance-qa-files-proof.json`.
The QA simulator remains in its isolated Guidance A test vault; original QA vault
registration and ordinary note/asset files are kept. Device Hub is back on the
iPhone 11. Inactive index/module/build caches were pruned to resolve low disk;
test results, signed apps, symbols, logs and proof records were retained.

README was reviewed and updated. Frontend and private Tailscale `/app` return200
after refresh on loopback8081 with `ZERUS_PREVIEW_BASE=/app/`. No Funnel,
canonical Tauri version change, archive, TestFlight, PR or commit. Live-provider
instruction following, workflows (budget controls arrived in preview 0.3.66), remaining native AI tools, old-history
recovery/migration and broader accessibility/physical/long-use work remain.
Spoken dictation stays deferred at the user's request. The full goal remains active.


### Native AI limits — preview 0.3.66

Open **Ask → AI settings → AI limits**, or the matching Settings entry, to
configure the current vault's model steps, output allowance, input context,
active minutes, total token allowance and reasoning effort. Save, Keep editing,
Discard changes, Reload and Use defaults are native controls. The shared file is
`.zerus/ai/settings.json`; other settings and unknown fields are retained.
Malformed, oversized or linked metadata blocks new runs while keeping its bytes.
An unchanged save does not rewrite the file, and stale editors cannot overwrite
another writer. Each new journal freezes its limits. Continuing an older run
retains its original limits; journals without saved limits use the earlier
defaults. Changing settings never grants extra note permissions.

Defaults are 30 steps, 8,192 output tokens, 48,000 input tokens, 10 active minutes,
160,000 total tokens and Medium effort. Allowed ranges match the web app:
2–100 steps, 1,024–32,768 output, 4,096–200,000 input, 1–30 minutes and
8,000–1,000,000 total tokens; effort is Low, Medium or High.

The Swift counter uses the bundled o200k_base vocabulary, without JavaScript on
the phone. Requests count their actual text, tools and frozen context, add a
20% allowance plus an image allowance, and reserve output within the remaining
run budget. This remains an estimate for models using other vocabularies or
provider-specific framing. API requests receive the output cap; the reused
ChatGPT subscription connection supports an approximate output target. Reasoning
effort is forwarded by the reused ChatGPT subscription and OpenRouter bridges;
other compatible endpoints receive no unsupported reasoning parameter.
Provider-reported usage takes precedence when returned. The reproducible vocabulary generator is
`node scripts/native-tokenizer.mjs`; provenance and MIT notices ship in the app.

An issued request is journaled before dispatch and consumes a model step even
if stopped or interrupted. A final response replaces its allocation with actual
reported or locally counted usage. Without a final report, Stop or explicit
recovery retains the reserved input/output estimate once and records why.
An active-time deadline cancels a held provider request. Review waiting time is
excluded; saved proposals and receipts remain available after limits are reached.
The run screen shows the frozen allowance and any unfinished reservation.

Verification passes **175 core checks, three native UI journeys and five physical
limits owners**: 178 distinct checks / 183 passing executions, with zero failures,
skips or XCTest runtime warnings in the authoritative passing results. The UI
checks cover instructions/memory, limits with three actual private HTTPS fixture
requests and a held one-minute request, and the existing review/edit/property/
relaunch/Undo flow. The other 38 UI journeys were not rerun. Retained earlier failures
include a disk-full build/conversation save, a combined/offscreen accessibility
query, a Stop assertion before final journal persistence and one missed Apply
tap after reopening review; the affected checks passed on their final runs.

Signed **0.3.66/1**, UUID `F3447018-4143-333F-A061-B1FB2775410B`, is installed on
**iPhone 11 Nox**. PID3425 stayed alive for 954.8 seconds from that exact executable;
the crash/Jetsam inventory did not change. The 483-note vault loaded. Both halves
of the limits form fit at the inspected size; defaults and disabled Save were
read without editing. Ask remains empty/unsent, Review and the previous model
remain selected, and other preferences/vault registrations are preserved.
Only automatic lastOpened changed. Native sources113, shared inputs, bundled
counter/manifest/notices, signature/profile and matching symbols are bound by
`artifacts/native-ios/limits-installation-proof.json`. The retained app and dSYM
are in `artifacts/native-ios/limits-device-binary/`.

The final interrupted journal retains step1, 1,632 estimated input tokens and
2,048 output tokens after64.0 active seconds, clears its reservation and explains
the estimate. All three actual fixture packets carry the2,048 output cap;
Low effort stays frozen, and the generic endpoint receives no unsupported
reasoning parameter. Late output is absent. The counter and manifest reproduce
exactly from the pinned upstream data. Before-fix budget, interrupted-accounting
and nested-foreign-field regressions are retained alongside final evidence.

All7,082 other pre-existing QA files match their baseline, with no removal and
all ordinary notes/assets unchanged. One private chat binding changed only its
roots; its original bytes are retained. The90 original registry identities,
folders and logical locations remain, with one automatic container-path refresh
recorded precisely. The QA provider is restored and temporary fixture routes
are removed; private /app remains verified through frontend and proxy.

Live-provider accounting, broader model vocabulary calibration, long-use,
VoiceOver and large-type checks remain. Spoken dictation is deferred by the user.
The full native migration remains active; this is a test preview, with workflows,
broader AI tools, old-history migration and live OAuth/Drive/provider work still
tracked in the parity checklist. No App Store archive/upload or release occurred.


### Reusable workflows — preview 0.3.67

Open **Ask → AI settings → Workflows**, or **Settings → AI → Workflows**.
Choose General notes task, Clean up meeting notes, Synthesize related notes,
Review duplicate notes or Review this week. The built-in names, identifiers and
instructions match the existing app. The selected row is exposed as selected
for accessibility. Save shows Saved in the toolbar; Cancel offers Keep editing
or Discard selection. A saved workflow affects future requests in this vault.

Custom workflows use ordinary UTF-8 Markdown in `.zerus/ai/workflows/`.
New custom workflow creates a draft with a heading; Save creates its file.
The first `#` heading supplies its displayed name. Edit changes the Markdown,
including that heading, while retaining its file path. Make a custom copy opens
an editable draft of a built-in workflow. Editors offer Save, Share this draft,
Keep editing, Discard draft and Reload saved workflow. Saving the file and
saving the browser's selection are separate, explicit actions. Unchanged saves
retain original file bytes and dates; stale drafts, changed previews and stale
selection saves are rejected. Vault activation checks protect retained editors.

Selection uses the existing `workflow` key in `.zerus/ai/settings.json`.
Other AI settings and unknown JSON fields are retained. Each new run freezes the
selected workflow's identifier, title and instructions in its journal, and the
run screen exposes that saved version. Resuming retains the frozen text after
workflow or settings edits. Older journals acquire no workflow silently.
Workflow preferences cannot expand note scope, change the chosen mode or grant
new actions. The current request and runtime permissions remain authoritative.

The request uses up to 12,000 UTF-16 units of custom instructions without splitting
a surrogate pair. Original longer files remain intact; an edited draft must fit
the displayed limit before saving. Metadata reads are bounded at 256 KB and require
ordinary readable UTF-8 files inside the vault. Missing, malformed or linked
selected files block a new run with an explanation; the picker offers General or
another available choice. It lists up to 30 custom workflows, inspects up to 512
folder entries and eight nesting levels, and opens a saved custom selection
separately when outside that list. Listing and file errors remain visible.

Final verification passes **178 core checks, two UI journeys and three physical
workflow owners**: 180 distinct checks / 183 passing executions, with zero failures,
skips or XCTest runtime warnings in the authoritative passing results. The UI
journeys cover the complete workflow flow plus existing review/edit/property/
relaunch/Undo behavior. The other 40 UI journeys were not rerun. Two actual private
HTTPS requests receive the built-in and custom instructions. Saved custom text
matches the file exactly, the earlier run retains Meeting after selection changes,
and a second vault remains General without creating workflow metadata.

The physical checks exposed a real catalog omission: coordination could return
`/private/var` for a `/var` or aliased root. Enumeration now compares canonical
confined paths and retains ordinary relative workflow IDs. The real-file owner
also uses an aliased root in Simulator; it and all three owners pass on iPhone 11.
Retained before-fix results cover ignored shared selection, unrelated nested
journal-field loss and the physical catalog failure. Optional journal fields
are now retired only in the objects that own them. Selection saves return their
exact committed snapshot, avoiding a fallible folder refresh after committing.
Earlier setup/query/async-dismissal failures are retained separately from the
final passing results; the native source is unchanged across the final checks
and signed installation.

Signed **0.3.67/1**, UUID `AA972E05-CC4F-38B3-8ECD-BAF95B84EA38`, is installed on
**iPhone 11 Nox**. PID 3469 remained alive for 676.9 seconds from that exact
executable, with no new crash/Jetsam report. The 483-note collection and workflow
list loaded. General remained selected, all four built-ins and New custom workflow
fit the inspected phone layout, and Save was disabled. The form was closed
without changes; Ask remains empty and unsent, with Review and its prior model.
Phone preferences match the pre-test snapshot exactly after the tests; normal
launch changes only the saved vault's lastOpened value.

`artifacts/native-ios/workflows-installation-proof.json` binds all 115 native
sources/shared inputs, the signature/profile/scene/keychain checks, matching
symbols and bundled vocabulary/manifest/notices. The exact signed app and dSYM
are retained in `artifacts/native-ios/workflows-device-binary/`.

All 7,538 other pre-existing QA files match their baseline, with no removals;
ordinary notes, assets and draft bodies are unchanged. Two private descriptors
changed: a chat binding refreshed its container path, and a task-draft binding
added an alias for a second registration of the same owned folder. Original
bytes and field differences are retained. All 103 original registry identities,
folders and logical locations remain. A duplicate default Zerus registration
appeared during verification; its original is retained and neither identity was
rewritten or merged. This remains a registry-migration issue to resolve before
claiming full parity. The QA provider is restored, temporary fixture routes are
removed, and the private web preview responds through both frontend and proxy.

Live-provider instruction following, broader available AI tools, shared-run and
older-history migration, live OAuth/Drive and full accessibility/long-use parity
remain. Spoken dictation stays deferred by the user. The full migration remains
active; this native preview is installed separately from the existing app.

### Saved folder identity — preview 0.3.68

Reopening a folder in Files now resolves saved bookmarks off the UI actor before
registering it. A working bookmark identifies the folder even when its stored
last-opened path names an older app container. The existing vault ID, list name,
foreign metadata and private history namespace remain attached to that folder.
A different folder reusing its former path receives a separate identity.

If multiple registrations identify the folder, choose the intended entry in
Saved vaults. Opening the folder directly leaves the registry unchanged and
explains this choice. Existing duplicates are preserved separately; no identity
or history merge is performed. Relaunch retains the explicitly selected entry,
even when multiple entries contain the same bookmark. Unavailable bookmarks and
older or ambiguous history formats still need separate access/recovery work.

Validation passed 179 core checks, the saved-vault create/switch/rename/remove/
relaunch UI journey, and the regression on the physical iPhone 11: 181 passing
executions, 180 distinct checks, no failures, skips or XCTest runtime warnings.
Before-fix results reproduce duplicate registration and incorrect reuse of an
old path. Phone preferences are identical before/after the physical owner test.
The earlier 7,540-file QA baseline retains all note, asset and draft contents;
its two previously recorded binding changes remain limited to the documented
container/alias metadata. No further task-draft alias was added. Historical
registrations remain, including two temporary registrations left by existing
image lifecycle tests; no host-side registry cleanup was performed.

Signed 0.3.68/1 is retained with symbols in
`artifacts/native-ios/vault-identity-device-binary/`. Its installation, exact
binary, final process, diagnostic and source evidence is recorded in
`artifacts/native-ios/vault-identity-installation-proof.json`. The full native
migration remains active. Spoken dictation stays deferred by the user.

### Live ChatGPT verification on iPhone 11 — preview 0.3.68

The installed signed preview now has an actual end-to-end check with the existing
ChatGPT account and the model displayed as `gpt-6.1-sol`, using the native
`codex://chatgpt` connection. Three manual journeys made seven model requests
in a new local **Native Connection QA 1107** vault. Its only ordinary note was
the app-generated welcome note; guidance, memory, workflows and attachments were
empty. No personal note context was sent.

Ask returned the requested synthetic response. Review used `note_get`,
`note_patch` and `preview_changes`; Cancel kept the original file unchanged.
Approval saved exactly one phrase replacement and a verified receipt. After
restarting the app, the same receipt restored the original bytes. Edit used
`note_get` and `note_patch`, saved a second exact phrase change automatically,
and produced its own receipt. Reviewed Undo restored the original bytes again.
All six conversation messages and three run journals remain in the QA vault.

The original iCloud vault is selected again with the same saved ID and 483
notes. Ask is empty and unsent, Review and the model display are retained, and
keyboard capture is off. All other saved preferences match the before snapshot;
the registry adds the clearly named QA vault and updates last-opened timestamps.
The QA welcome note is unchanged after both Undos. Diagnostic inventory is
unchanged. This is the same signed 0.3.68/1 binary, without rebuilding or adding
automated-test counts. Evidence and the executable/source checks are in
`artifacts/native-ios/live-connection-proof.json` and its retained verifier.

This checks generation and body tools for the already-connected account. New
sign-in, account switching, catalogs/revocation, other providers, attachments,
broader tools/plans/steering/workers and long-use/accessibility parity still
need their own verification. Spoken dictation remains deferred by the user.

### Structured AI plans — preview 0.3.70

Open Ask → AI runs → a run to see its plan. Steps retain their order and show
Pending, In progress or Complete with text, distinct symbols and accessibility
labels. Multi-step requests can update these states as work progresses; a plan
is not required for every answer. Plan progress is reported by AI. A completed
step never approves a note change or replaces a verified save receipt.

The native `update_plan` tool now accepts the existing app's objects containing
`text` and `status` (`pending`, `running`, `complete`), with up to 20 steps of
300 characters. Blank steps and unknown states are rejected. The journal keeps
stable step identities and foreign fields as statuses change, including UUID
spelling from other clients, and retains progress through pause and relaunch.

Older native journals and pending string-based plan calls remain readable.
Their text is shown without inventing completion states. If an older client
changes plan text while retaining newer metadata, stale states are hidden.
Unsupported future plan states leave the original journal intact in Needs
attention. This extends native journals; it does not migrate the separate
shared/older agent-history format. Ask stays read-only, and the displayed plan
cannot expand a run's frozen note permissions.

A response that stops with unfinished tracked steps leaves the run **Plan
unfinished**, with progress available for continuation. A completed ChatGPT
agent response may end without prose after using tools; that no longer creates
an Interrupted error. Ordinary text chat still rejects an empty answer, and
failed or incomplete provider responses remain errors. This was reproduced
with the existing account on iPhone 11 before repair and at the shared SSE
completion boundary. The shared package's 11 checks pass after repair.

Signed **0.3.70/1** is installed and launch-verified on iPhone 11 Nox. Eleven
shared ChatGPT checks and sixteen native agent checks on the phone pass. The
preceding plan-only source snapshot passed all 180 core checks plus its
physical primary owner; that full suite and automated UI journeys were not
rerun after the completion repair.

The live Ask check made two requests with the existing ChatGPT account in
**Native Connection QA 1107**, with zero readable/writable notes and no
creation scope, instructions, memory or attachments. It saved Read/complete,
Draft/running and Check/pending, then completed with an empty assistant
response. The app showed **Plan unfinished** and its explanatory fallback,
without a new Interrupted error. All preexisting QA note/history/journal files
and the six-message conversation prefix remain intact. The earlier failed run
is retained separately and unchanged.

The original iCloud vault and its 483 notes are selected again. Ask is empty
and unsent in Review; keyboard capture is off. Other preferences match the
starting snapshot; only last-opened timestamps and the QA vault's local
installation-container bookmark/location refreshed. The same signed process
was observed across 162.7 seconds, and diagnostic inventory is exactly
unchanged. Evidence: `artifacts/native-ios/plans-completion-proof.json` and
`plans-completion-proof-verifier.py`. The full migration goal remains active;
spoken dictation remains deferred by the user.


### ChatGPT continuation after restart — preview 0.3.71

Native runs keep ChatGPT response items in device-private Application Support
storage before executing their tool calls. This preserves encrypted reasoning,
assistant message phases and function-call items when the app restarts. The
vault journal still contains the visible conversation, scoped tool calls,
proposals and receipts; account credentials remain in Keychain.

Continuation data is bound to the ChatGPT account, model, stable native run
identity and its exact visible conversation. Another account, model or run
cannot borrow it. It is written atomically with iOS file protection, excluded
from device backup, and removed for that account when disconnecting. Switching
accounts leaves each account's data separate. New conversations keep their
existing journals and continuation data available.

A copied journal on another phone, a run created before this preview, or a
cache removed by disconnect/app-data deletion may lack its original ChatGPT
tool state. Continuing then stops locally with a clear explanation and keeps
the journal, proposals and receipts. Start a new request to use a different
account/model or unavailable state. Unreadable and future-format data are
preserved. Large responses are rejected rather than silently truncated.

Waiting questions and **Answer and continue** now appear first in the run
screen, ahead of a long plan and its details. The existing scope confirmation
still applies. Broader steering/follow-ups, worker/tool parity, shared older
history and other provider/account flows remain separate work.

Signed **0.3.71/1** is installed on iPhone 11 Nox. Eleven shared ChatGPT
checks and sixteen native agent checks passed. The latter include reopening a
real run journal and verifying its stable continuation identity and budgets.
After those logic checks, the waiting-question layout changed; the final
Release build and manual phone journey verify that layout. The full core and
automated UI suites were not rerun for this preview.

One live synthetic Ask run in **Native Connection QA 1107** used four requests
with the existing ChatGPT account/model `gpt-6.1-sol`. It saved three plan
states and a Yes/No question, then waited. The exact signed app was terminated
and relaunched: process 3540 became 3543, and both private response files
survived byte for byte. The question and **Answer and continue** were visible
first on iPhone 11. Answering Yes after the scope confirmation continued the
same run, retained its step identities and usage, completed every plan step,
and returned “Native restart works.” Four private response files match the
actual journal prefixes and run/model namespace. The live provider returned
function calls and a final-answer message phase, without reasoning items;
encrypted-reasoning replay is covered by the real-file protocol fixture.

The run had zero readable/writable notes, no creation permission, guidance or
attachments, and produced no note proposals or receipts. All eleven
preexisting QA note/history/journal files are byte-identical. The ten-message
conversation prefix is retained in fourteen final messages. The original
483-note iCloud vault and empty Review composer/model are restored, keyboard
capture is off, and the microphone was never invoked. Other preferences are
unchanged; registry changes are last-opened times and the QA vault's local
installation-container bookmark/location refresh. Diagnostic inventory is
exactly unchanged, and the restarted process remained present across 216.6
seconds of observation. Evidence: `artifacts/native-ios/continuation-proof.json`
and its retained verifier.

Preview 0.3.72 below addresses reply positioning and transcript-prefix hashing.
The full migration remains active and spoken dictation deferred.

### Conversation positioning and continuation preparation — preview 0.3.72

Conversations open at their latest reply, including after a cold restart.
Answer actions retain their place while generation finishes. Scrolling back
pauses following; **Latest message** returns to the end. Native scroll geometry
also detects indirect scrolling that does not report a touch phase. Keyboard
and content reflow do not count as scrolling into older history. Selectable
messages use measured rows to avoid the lazy-layout loop reproduced when a
keyboard opened over a long conversation.

ChatGPT continuation preparation hashes each normalized message once and
snapshots the running hash for assistant turns. Existing v1 filenames and request
bytes remain compatible. An optimized local benchmark with 100 cached responses,
201 messages, 401 input items and four synthetic image payloads measured mean
preparation of 212 ms before and 31 ms after over three runs on this Mac. Both
versions produced exactly the same 1,148,972-byte request. This is not an iPhone
timing measurement.

Signed **0.3.72/3** is installed on **iPhone 11 Nox**, iOS 27.2, with executable
UUID **A7E9CB55-2D04-3B5E-AE5C-0B657905E2A2**. The exact retained binary passed
physical initial positioning, indirect scroll-away/Latest message, and cold
restart from older history. Its final reply and Share/Save actions remain above
the composer. The restarted process remained present across 87.5 seconds of
observation, with the same 56-record diagnostic inventory.

The final native UI owner passed the long-prompt keyboard/picker sequence,
reopening, return to latest, and body/property Review, Cancel, commit, restart
and Undo journey. Eleven shared protocol checks passed. All 180 core checks
passed before the final chat-layout changes; six search/registry owners then
passed after extending test preference cleanup, preserving the full preference
domain. Sources, test snapshots and result bundles identify these boundaries
in `artifacts/native-ios/reply-proof.json` and its verifier.

All 12 preexisting physical QA files, conversation content and four v1 cache
files survive byte for byte. Only the QA conversation's private vault binding
rebased to the new installation container. The original 483-note iCloud vault,
empty unsent Review composer, model and other app preferences are restored.
The simulator retains all 8,534 baseline files and original 114 registrations,
plus the intentionally created **Native Reply QA 1107** registration. Temporary
provider serving is removed and the original private Serve configuration restored.

No new live provider request was made after this upgrade. Live continuation
from the older run still needs a new physical request; this preview verifies
v1 compatibility through file preservation, protocol replay and the identical
benchmark request. Very large conversation rendering, broader VoiceOver and
streaming interaction, iPad/long-use checks, Google OAuth and remaining native
AI/provider parity remain. The full migration is unfinished; dictation is still
deferred at the user's request.

### Revised migration scope — 7 November 2026

The user excluded AI and Google Drive integration from the remaining migration
goal. Retain existing implementations and account data; do not treat AI/provider,
Ask dictation, Google OAuth or Drive sync parity as acceptance requirements.
Continue native writing, Files/iCloud vault access, navigation, properties and
relations, tasks/search/organization, file handling/exports, recovery and physical
layout/accessibility/stability verification on iPhone 11. Distribution through
the App Store remains separate.

The uninstalled preview73 AI Markdown experiment is deferred in
`artifacts/native-ios/ai-markdown-deferred/`. It passed 181 native core checks,
but the formatted-image UI check and the existing AI interaction journey failed;
it is not an accepted or installed candidate. The active source was restored
byte-exact to the signed 0.3.72/3 build inputs, which remains installed on the
phone. Temporary AI fixture serving was removed and the original private Serve
configuration restored. The Saved registry migration checklist entry was stale;
the concrete duplicate-prevention repair and its validation are already recorded
under preview0.3.68 above. Existing historical duplicates remain separate.

### Native workspace acceptance on iPhone 11 — 7 November 2026

The same signed **0.3.72/3** binary now has a physical writing/table/restart
check. In the separate local QA vault, native controls typed two paragraphs,
applied bold and italic, exercised Undo/Redo, inserted a table, changed a header,
and bolded a typed table value through the rich cell editor. The actual file
contains portable Markdown, including the formatted table cell. A cold restart
reopened the rich note and table with byte-identical saved Markdown. The restarted
process remained present across 82.3 seconds. The 56 diagnostic paths were
unchanged, with no new crash or Jetsam entry; only the system Spotlight heartbeat
file and its parent directory had updated metadata.

All 12 preexisting physical QA files, 40 private conversation files and four
continuation files remain byte-identical. Additions are confined to the new
synthetic note and its ten automatic-history records. The original iCloud vault
shows 483 notes again; it is selected with the test note closed and keyboard
capture off. Preferences are unchanged except normal saved-vault lastOpened
values. No new AI request, OAuth action or microphone permission was invoked.
`artifacts/native-ios/workspace-physical-proof.json` and its verifier bind these
observations to the retained signed app, symbols, actual files and current
production inputs. No new binary was built or installed for this acceptance pass.

Three saved-vault owners and six native UI journeys pass across
`NativeWorkspaceAcceptance.xcresult` and `NativeWorkspaceWritingFinal.xcresult`:
folder identity, legacy restore, unavailable access, heading navigation, open-note
and reading-position restoration, writing/search/task capture, formatted
clipboard/Undo, table editing/paging/linked-note creation, and saved-vault
create/switch/rename/remove/relaunch. The initial writing owner completed its
native steps but ended with an unrelated empty-AI-screen assertion. That excluded
three-line tail was removed; the complete native writing journey then passed.
The production snapshot is unchanged between results. There are nine distinct
passing checks, no skips or XCTest runtime warnings in these results; the full
native UI suite has not been rerun as one final acceptance pass.

All 8,982 original simulator files remain: 8,981 are byte-identical and one
private vault binding has only a verified container-root rebase. All 115 original
registrations remain, plus two intentional QA registrations. Original vault and
other preferences, including the prior fixture selection, are restored. See
`workspace-sim-preservation-proof.json`; no note, asset or private draft body was
rewritten for cleanup. Temporary serving is removed, and both private web preview
routes respond successfully.

The goal remains active. Basic physical writing and rich table entry are now
verified; software/language keyboards and IME, physical cross-app paste, broader
VoiceOver/Dynamic Type/rotation, provider reconnection and large-vault/long-use
checks still need acceptance work. AI and Google Drive remain excluded.

### Readable table footers at accessibility sizes — preview 0.3.73

Native table previews now measure and wrap their footer at the selected Dynamic
Type size. The previous single-line space clipped the column count and **Tap to
edit** hint at the largest accessibility size in a narrow editor. The new layout
keeps that font size and gives the complete caption enough height. Table source,
column widths and cell content are unchanged.

The existing hosted production-editor owner now reads actual rendered pixels.
With the final assertion, the original source fails because the column count and
edit hint are missing. The repaired source passes, including the owner's existing
appearance/width, actual-file, selection, Undo/Redo and marked-writing checks.
The read-only selection owner, portable cell-formatting owner and complete native
table editing/paging/link-creation/relaunch journey also pass: **four checks, no
failures, skips or XCTest runtime warnings** in `NativeTableFooterVerified.xcresult`.
Before/after PNGs and input snapshots are retained under `artifacts/native-ios/`.
This is focused regression coverage; the complete UI suite was not rerun.

Signed **0.3.73/1**, UUID **8819598D-F4C6-3CF1-B1B4-C9E4A8947B6C**, is installed
on **iPhone 11 Nox**, iOS 27.2. The retained app/dSYM, profile, signature,
resources and source/build inputs are verified. The exact installed process
remained present for **314.7 seconds**, with the same diagnostic inventory. The
existing rich QA note shows its complete default-size footer; its native table
editor opens with the original formatting, and Cancel closes without saving.
Largest-text/narrow-width readability is verified by the hosted production
editor on Simulator; the physical inspection used the phone's existing text size.

All 23 preexisting physical QA files and four continuation files are byte-exact.
Of 40 private conversation files, only the QA vault's path binding rebased to the
new installation container; its other fields and all conversation content remain
unchanged. Original vault and preference values are restored, apart from normal
lastOpened/path metadata and equivalent key ordering in the empty note-resume
JSON. The phone shows the original 483-note iCloud vault with the note closed and
keyboard capture off. No AI, Google Drive or microphone flow was invoked.

The simulator retains all 9,260 baseline files: 9,258 are byte-identical and two
private bindings have verified container-root changes only. All 117 registrations
remain; original vault and other preferences are restored. Cleanup restored only
the original byte ordering of an equivalent empty note-resume value while the
Simulator was shut down. No note or draft was rewritten. The private Serve
configuration is unchanged and both web preview routes respond successfully.
See `table-footer-proof.json` and `table-footer-proof-verifier.py` for evidence.

The wider native goal remains active, with AI and Google Drive excluded.
Broader VoiceOver, software/language keyboards and IME, physical cross-app paste,
file-provider recovery, large-vault and long-use acceptance remain.

### Freshly typed formatting and clipboard text — preview 0.3.74

A physical iPhone acceptance check found that selecting and bolding freshly
typed text could save `**N****ative...**`. Copying and pasting that selection
then displayed literal stars. UIKit had split the initial character and later
writing into different attribute runs even though their inline formatting was
the same.

The Markdown serializer now combines adjacent ordinary text runs with matching
inline formatting and destination before adding delimiters. Display metadata
does not create another pair of bold/italic/code/strike markers. Image, code
block and decoration boundaries remain distinct, as do changes in style or
link destination. Existing saved notes are not rewritten during installation.

The primary regression uses the hosted production editor, types the initial
character separately, applies native bold, copies the actual selection and
pastes it into a new paragraph. It checks actual saved Markdown, the portable
clipboard fragment, one-step Undo/Redo, and reopened visible text and formatting.
`NativeClipboardRunsCleanBaseline.xcresult` fails five assertions for the
observed literal-marker defect; `NativeClipboardRunsVerified.xcresult` passes
the same check after repair. The earlier baseline result also contains a
host clipboard-permission setup interruption and is not the clean regression
record.

The earlier broad acceptance run was intentionally canceled after 144 core
checks and one UI journey passed, when the separate physical check found this
defect. Its canceled UI test is not a product failure or a complete acceptance
pass. The repaired source passes all 145 selected non-integration core checks;
the 30 UI journeys are still running. AI and Google Drive remain excluded from
this goal.

Signed **0.3.74/1**, UUID **EEE64ADA-8089-3BC6-ACC1-3DF31354703A**, is installed
and opened on iPhone 11 Nox. A fresh synthetic note repeats the real
keyboard/select/bold/Copy/Paste sequence. Both paragraphs retain bold without
literal stars. Actual saved-file snapshots verify Undo removes the pasted
paragraph and Redo restores identical bytes. A cold process restart reopens
both correctly formatted paragraphs. The original 483-note iCloud vault is
restored, note closed and keyboard capture off.

All 31 pre-update QA files survive unchanged; the new note and its six history
records are the only added vault files. All 40 private conversation files are
retained, with only the local QA binding rebased to the new app container;
all four cache files are byte-identical. Preference values are unchanged apart
from verified saved-vault reopening metadata. The same process remains open
for 155.4 seconds of subsequent observation, with the diagnostic inventory
exactly unchanged at 56 entries. See `clipboard-runs-physical-proof.json` and
its verifier, signed-binary proof, and retained screenshot
`clipboard-runs-physical-reopened.jpg`.

Physical Safari paste is still unverified: the phone could not resolve the
private synthetic fixture address. The failed fixture tab was closed. No
network settings were changed. Software/language keyboards, IME, full
VoiceOver, broader provider and long-use acceptance still need verification.

The same signed preview also passes a physical maximum-text-size inspection.
Device Hub’s Text Size slider starts at 4, reaches maximum 11, and is restored
to 4 afterward; Location stays None. Native search finds the existing synthetic
writing note by title. Its rich editor updates live, keyboard document-end
navigation reveals the table, and the complete row/column count and Tap to
edit footer remain visible over two lines. The native table sheet shows full
cell text and paging controls. Cancel changes no files. All38 QA files,40
private files and4cache files remain byte-identical across this inspection.
The only new preference is one recently opened QA note ID; existing recent
data is retained. Empty resume state differs only in JSON key ordering, and
the registry differs only in last-opened dates. The same physical process is
stable for518.3seconds with the same56 diagnostic entries. Original text size,
iCloud vault, closed-note state and keyboard capture are restored. See
`physical-text-size-proof.json`, its verifier and retained screenshots. This
manual acceptance adds no automated test count.

### Physical Safari clipboard acceptance — signed preview 0.3.74

The phone’s private-fixture DNS remained unavailable. A separate manual check
used the actual public Example Domain page in Safari. Selecting and copying
its body on the phone, then Note actions → Clipboard → Paste → UIKit Paste
control in a fresh native QA note, preserves its six language paragraphs and
original link as1423bytes of ordinary Markdown. Arabic, Chinese and Cyrillic
characters are retained. One Undo restores the original empty note byte for
byte; Redo restores the complete pasted bytes. A cold process restart reopens
the rendered writing and link. The first terminate-existing device launch
returned CoreDevice10004; a subsequent plain launch succeeds with a new PID
and no new diagnostic report. The post-restart process is stable for284.2seconds.

All82 existing QA/private/cache files survive unchanged; only the new Safari
QA note and its four history records are added. Preferences differ only in
saved-vault last-opened metadata and empty resume JSON ordering. The original
483-note iCloud vault, closed-note state, original text size and disabled
keyboard capture are restored. Only the Example Domain test tab is closed.
See `physical-safari-proof.json` and its verifier and screenshots. This manual
acceptance adds no automated test count. Physical remote/companion image
clipboard and broader source apps remain separate verification.

The broad automated acceptance run has151passes (145core and6UI),5UI
failures and1canceled UI journey, with no XCTest runtime warnings. General’s
second vault dialog is canceled by XCTest’s own interruption handler; the image
journey misses its source menu and leaves a note presented, after which
subsequent journeys cannot reach their expected starting screens. These
failures are under investigation; a complete acceptance pass is not claimed.

### Current native acceptance follow-up — preview 0.3.74

The General, image recovery, note-link, relation-conversion and session owners
now pass after UI-test setup/readiness repairs. Note-link selection explicitly
uses document-end and Shift–Command–Up; relation search submits before tapping
its result, keeping the software keyboard from covering that result. The native
production inputs remain identical to the installed signed build. Across
retained current-build results there are 145 core and 11 distinct UI passes;
19 workspace journeys are running separately. Earlier failed attempts remain
as diagnostic evidence and are not counted as passes.

The same physical process also passed landscape inspection of the editor,
native note-list touch scrolling/search, existing rich note and table preview,
and native table sheet. Cancel preserved all 87 existing QA/private/cache files;
only one empty software-keyboard QA note was added. Portrait, the original
483-note vault, closed-note state and disabled keyboard capture were restored.
The diagnostic inventory is unchanged. See physical-landscape-proof.json and
its verifier/screenshots. Device Hub keeps hardware-keyboard mode active even
with capture off, so physical onscreen typing, accented-key entry and IME remain
pending; the empty QA note is preparation only. No new automated test count.

### Bulk-review navigation and clipboard layout — preview 0.3.75

Returning from an Undo review cleared the optional plan that the navigation
destination depended on. The first review opened, but reopening it after Back
could leave the user on Recent actions. Each review route now carries its own
immutable plan; Back and completed changes remove the route without removing
a destination's data during its navigation transition. Stored action records,
review checks and note transaction semantics are unchanged.

The existing complete bulk UI journey reproduces the failure on preview74
after explicitly waiting for the first review to close. It passes on preview75,
including reopened review, Undo/Redo, property change and saved history after
relaunch. Both existing real-file bulk owners also pass: three checks, zero
failures, skips or XCTest runtime warnings in NativeBulkReview75.xcresult.
The code-editor owner separately passes on unchanged74 after repairing its
offscreen-note lookup to use native search; all formatting, conversion,
Undo/Redo and saved-source checks remain.

The iPhone 11's settled240-point paste sheet clipped its help sentence. The
paste sheet now wraps that text, allows scrolling, and offers medium/large
system sizes. Physical before/after inspection is pending installation of75;
physical-paste-caption-before.jpg records the original clipping. Version75's
signed device build is in progress. AI and Google Drive remain excluded.

Signed0.3.75/1 (UUID0049E054-3473-3D96-9A3C-CC2557E73783) is installed
on iPhone 11. Actual onscreen keys and the native emoji picker entered bold
Cafe ❤️ in the existing synthetic keyboard note. One Undo restores its original
empty bytes; Redo restores identical formatted bytes. Cold restart reopens the
rich text correctly, with87.2seconds of subsequent stable process observation
and the same56 diagnostic entries. All43 other QA files remain exact; only
that intended note and seven new history records change. Private files and
cache are retained, with only the local QA binding rebased after installation.
Foundation bookmark metadata confirms the same named Documents vault path in
the new app container. Original483-note vault and closed-note state are restored.
See polish75-software-proof.json and its verifier. No new automated test count.

The default paste help sentence now wraps fully. Testing with the software
keyboard exposed a separate issue: the note retains first responder beneath
the paste sheet, leaving its keyboard over the content. Preview76 now finishes
editing before opening that sheet and is undergoing focused clipboard and
properties UI verification. Device Hub currently disables its physical text-size
and VoiceOver controls, so the maximum-size caption recheck remains pending;
no phone text-size or location setting changed. Onscreen Latin and emoji input
are verified; accented press-and-hold, composition/IME and full VoiceOver remain.

### Preview 0.3.76 physical paste-sheet acceptance

The retained signed release app is installed on iPhone 11 Nox (iOS 27.2),
UUID E262B56F-7E76-36AA-8F82-B194D14E5A44. With the actual native software
keyboard visible in the synthetic QA note, Note actions → Clipboard → Paste
dismisses both keyboard and accessory before showing the sheet. Its complete
help and enabled UIKit Paste control remain visible. Cancel returns to the
unchanged note; all51 existing QA files remain byte-identical. The check does
not perform a paste. The original 483-note iCloud vault is restored with no
open note, portrait orientation and Capture Keyboard off.

Forty private files remain (39 exact, only the QA binding roots rebased to
the new app container), four continuation-cache files stay exact, preferences
retain original values apart from vault visit/container metadata, and the same
56 diagnostic entries remain. The same release process is observed for183.3
seconds. See polish76-paste-physical-proof.json and its verifier. Three real
editor clipboard owners plus the HTML cross-app and properties UI journeys
pass together:5/5, no failures, skips or runtime warnings. The retained
acceptance inventory now contains145 core and21 unique UI passes; nine
workspace journeys are still running. AI/Google Drive remain excluded.

### Preview 0.3.76 physical export generation

The exact installed release app generated PDF, editable Word and self-contained
HTML from the existing synthetic writing note. All three opened in native
system Quick Look with prose, bold, italic and the two-column table visible.
Copied device artifacts pass PDFKit page/text validation, Word ZIP CRC/XML
formatting/table validation and HTML structure/style checks; internal Zerus
metadata is absent. No external sharing or physical Save to Files is claimed
by this check. The existing Simulator export journey covers Save to Files.

All51 QA vault files,40 private files and4 continuation-cache files remain
byte-identical to the preceding76 checkpoint. Only vault visit metadata changes;
the original 483-note iCloud vault, empty resume, portrait and Capture Keyboard
off are restored. Device diagnostics remain identical and the same signed
process survives606.9seconds. See polish76-export-physical-proof.json and the
retained device-generated artifacts under polish76-exports-all-device/.

### Non-integration functional acceptance complete for preview 0.3.76

The final workspace batch passes all nine journeys: deliberate revisions, table
editing, task planning, Recently Deleted, reviewed renaming, saved links, saved
vaults, task drafts and vault-history settings. Combined with retained passing
runs, the selected scope is145 core owners plus30 unique UI journeys (175
unique checks). AI/Drive owners and the two mixed AI handoffs are excluded.
Historical failed attempts and intentional cancellations remain as diagnostic
evidence and do not count as passes. The three production files changed since
74 are UI routes/presentation/actions, with their affected owners rerun; see
acceptance-74-to76-input-delta.json and acceptance-current76-passing-inventory.json.

The Simulator returns through the native UI to My thoughts C8FC2D with its two
original notes and no open note. All9,270 original files remain:9,268 byte-exact,
the external registry's original24 serialized entries exact with only three QA
connections appended, and one private binding changed only to the restored
vault's new app-container URL. All117 original registrations and original
preference values are retained, apart from that bookmark/location and visit
metadata; five new QA registrations, two QA default folders and two QA search
entries remain. Foundation validates both stored bookmark paths. See
acceptance-sim-final76-preservation.json and verify-sim76-preservation.py.

Apple Accessibility Inspector selected the physical iPhone app with all seven
audit options enabled, but returned no result before its app target reset. This
is inconclusive, not an accessibility pass. The physical process, diagnostic
inventory and preferences remain unchanged afterward. Full VoiceOver, IME and
broader provider/long-use acceptance remain open; the overall goal stays active.


### Accessibility polish — preview 0.3.77

The native bulk-action controls now have 44-point minimum touch targets, and
secondary text in Notes, Tasks, Library and the editor has stronger adaptive
contrast. Date/filter/draft labels can wrap vertically. The decorative Library
icon no longer contributes an unreadable accessibility label.

The existing bulk review/Cancel/Pin/Undo/Redo/property/relaunch journey passes
with no runtime warnings. A production SwiftUI rendering check at 414-point
width recognizes both words of “Select notes” at small, normal and maximum
accessibility text sizes and measures the actual glyph growth. It does not
establish accessibility coverage for every screen.

Unfiltered Apple accessibility audits reached Notes, the rich editor, Tasks and
Library. The readability iteration reduced findings from 50 to 34 before the
final header-color adjustment. Remaining font/clipping/contrast findings are
retained for classification; some reported contrast failures contradict the
captured pixels. No audit issues were filtered out and no all-clear is claimed.
The physical automated audit stopped at iOS’s UI Automation authorization prompt
before any test actions ran. Device automation and VoiceOver approval remain
pending; manual device checks continue without changing those settings.

Signed Release **0.3.77/1**, UUID **6929D306-AA5D-364D-91C3-A0DC4F3FF3FC**,
is installed and launched on iPhone 11 Nox. The actual enlarged history target
opens from a tap below the visible icon; Notes, Library and Tasks are inspected
in the installed binary. The original 483-note iCloud vault stays selected.
All 51 QA files, 40 private history files and four continuation files match their
pre-install bytes. The Simulator returns to its original two-note vault with
all 9,270 original files retained; see acceptance-sim-final77-preservation.json.
Full VoiceOver, language-keyboard/IME, broader provider/long-use acceptance and
the already-loaded same-path image refresh gap remain open. AI and Google Drive
remain excluded from this goal.


### Open-note image refresh — preview 0.3.78

An already-loaded local image now refreshes inside the open note when a vault
scan detects changed resource modification/creation dates or paths. Note/task
writes alone retain the resource version. Each successful preview is bound to
that version; canceled or superseded reads cannot publish. The previous image
stays visible while a provider supplies its replacement. Failed refreshes offer
Retry images and identify the retained preview as unable to refresh.

The existing real-editor owner first fails on the stale cached image, then
passes with a replacement of a different aspect ratio, the same live editor,
unchanged selection and exact Markdown/properties, and intact Undo/Redo. A real
file presenter holds the replacement read to verify that the old preview stays
visible before release. All14 selected image-loading/lifecycle/presentation
checks pass without skips or XCTest runtime warnings. The same hosted-editor
owner passes on **iPhone 11 Nox, iOS 27.2** in2.275 seconds, using an isolated
temporary vault and no UI automation or provider-account permissions.

Signed Release **0.3.78/1**, UUID **9DE0B70B-5575-38C9-9D30-F364B4AE5450**,
is installed and launched from the retained verified app. The original 483-note
iCloud vault stays selected. All51 QA files,40 existing private files and four
continuation files retain their exact bytes; the physical unit test adds one
unregistered temporary-vault identity binding, with no conversation content.
The original saved registrations and preferences are retained apart from visit
time. All9,270 original Simulator files remain with the previously verified QA
registry additions and container-path rebase; its original two-note vault is
restored. See image-refresh78-{red,green,owners,physical}-summary.json,
polish78-signed-binary-proof.json and acceptance-sim-final78-preservation.json.

This verifies the metadata-driven local-resource refresh contract. Providers
that replace bytes while preserving all scanned metadata need a reopened note;
large/cold-provider and long-use behavior, full VoiceOver, language-keyboard/IME
and the remaining platform audit findings still need acceptance. AI and Google
Drive remain excluded from this goal.


### Notes density and readable bulk selection — preview 0.3.79

The Notes intro, collection picker and controls share one clear native section
with compact inter-section spacing and smaller vertical row insets. Text sizes
and minimum button targets are retained. The first note moves147 pixels higher
in the fixed Simulator projection, and the installed iPhone shows two full notes
where the previous layout showed roughly one.

At accessibility text sizes, selected-count, Select all and Clear stack
vertically. Previously those three columns split words into fragments. The
existing rendered-text owner reproduces that failure before repair, then checks
inactive/selected states at small, normal and maximum sizes: every label is
recognized, Clear stays unbroken, normal glyphs grow and every required word
grows substantially at maximum size. OCR locates the words; actual foreground
pixel rows measure glyph height, avoiding approximate OCR line-box noise. The
owner passes on Simulator and physical iPhone 11 without XCTest runtime warnings.
Read-only select/Select all/Clear/Done and Pinned/All notes interactions pass in
the actual Simulator interface. Its original Large text size is restored.

Retained signed Release **0.3.79/1**, UUID
**0FD438D7-3B07-366C-9233-88026451C7A6**, is installed and opens the original
483-note iCloud vault. All51 QA files,41 existing private files and four
continuation files remain byte-identical. All9,270 original Simulator files are
retained with the already-verified registry additions/container-path rebase,
and the original two-note vault is restored. See bulk-selected79-{red,ink,physical}-summary.json,
notes-spacing79-* screenshots and acceptance-sim-final79-preservation.json.
This is focused layout/readability verification, not a complete accessibility
pass. Remaining platform-audit findings, VoiceOver, language keyboards/IME and
broader provider/long-use acceptance remain open; AI and Google Drive are excluded.


### Visible keyboard dismissal and native predictions — preview 0.3.80

iOS 27 automatically placed both Dismiss keyboard and Redo inside the editor
formatting toolbar’s overflow on the414-point iPhone 11. Dismiss now uses
UIKit’s high visibility priority, guarded for iOS 27. It remains directly visible
above the software keyboard; UIKit retains Undo and Redo in its native overflow.
The older-OS toolbar behavior is unchanged. This is a presentation-only change.

Retained signed Release **0.3.80/1**, UUID
`DA44A379-4B23-3ED1-AE81-1A52E6FB0614`, is installed on iPhone 11 Nox.
Actual onscreen typing on its existing Portuguese/English keyboard and selecting
the native **açaí** prediction produced the correct saved Unicode text while
retaining the original bold Cafe/heart formatting. The direct Dismiss button
closes both keyboard and accessory. Reopening writing and using native Undo
restores the original QA note byte-for-byte; Redo restores the exact prediction,
and final Undo restores the original again. The original English/Portuguese
keyboard selection is restored. No software keyboard was added or configured.

The original 483-note vault is selected again with no note open, portrait and
keyboard capture off. All51 pre-existing QA files are unchanged; five automatic
revision snapshots were generated for that QA note. The private41 files are
retained, with only the QA vault’s installation-container root rebased; the four
continuation files are exact. Saved preferences retain both registrations and
original values, apart from visit times and the QA bookmark/location rebase.
The same56 diagnostic paths remain with no new crash or Jetsam report.
See `keyboard80-physical-proof.json` and the retained screenshots/file checkpoints.

This is physical keyboard/prediction evidence, not a full marked-text IME or
VoiceOver acceptance pass. Existing accessibility findings, broader provider
and long-use checks remain open. AI and Google Drive remain excluded. No new
automated test or broad-suite pass is claimed for this small toolbar change.


### Readable collection and task choices — preview 0.3.81

The standard segmented Picker retained small labels even when the rest of
Notes and Tasks used maximum accessibility text sizes. Both selectors now use
SwiftUI’s native inline Picker at accessibility sizes, with full-size choices
and native selected checkmarks. Standard sizes retain their segmented controls.
The existing binding, choices and filtering behavior are unchanged.

Actual Simulator inspection at maximum text size verifies all three Notes
choices, Pinned selection changing the collection from two notes to one, and
restoring All notes/two notes. The task selector’s Today/All selected traits
and checkmarks follow taps, then Today is restored. Normal text size restores
the compact selectors. The original two-note vault remains selected without
opening or editing a note. All9,917 captured files remain,9,916 byte-identical;
only its private vault identity binding rebases to the new installation
container. All122 existing registrations and original preferences are retained
apart from that vault’s bookmark/location and visit metadata.

The Library’s six collection labels, including Saved links and Recently
Deleted, grow and wrap completely at maximum size and remain reachable by
native scrolling. Three retained77 audit crops also measure readable dominant
text/background pixel contrast: folder6.95:1, Saved6.89:1 and Archive21:1.
These measurements apply to those crops, not the complete current screen.
No platform finding is filtered, suppressed or claimed to pass from this alone.
See `accessibility81-finding-delivery-review.json`, the retained screenshots
and `accessibility81-retained-contrast-pixels.json`.

Retained signed Release **0.3.81/1**, UUID
`66D02C81-FFA6-3C79-84CC-1E3AC4C53055`, is installed on iPhone 11.
The new selectors’ physical maximum-size delivery and full VoiceOver remain
pending; this batch does not claim a complete accessibility pass. Simulator
iOS26.5 still misplaces navigation/search chrome after some live text-size
changes; cold reopening restores normal layout. The original size is restored.
AI and Google Drive remain outside this goal, and no new automated test count
or broad-suite rerun is claimed for the Picker presentation change.


### Bounded external project-image reads — preview 0.3.82

External project-image thumbnails previously awaited a detached coordinated
read even after their caller was canceled. A provider holding that read could
keep the preview waiting indefinitely; an expired read could deliver a late
bitmap after the provider was released. These previews now use the same
15-second bounded coordinated reader as vault images, check cancellation
before decoding and reject late completion. The worker retains its project
capability until the underlying read finishes. Existing folder identity,
confinement, regular-file and50MB limits remain. Ordinary copy/import data
reads keep their existing behavior.

The existing provider owner now covers the actual vault-read and external
thumbnail entry points using one real-file fixture and a held NSFilePresenter.
External cancellation/deadline/late-output assertions fail on81; the repaired
owner passes, including decoding the expected40×20 bitmap on retry and exact
original note/image bytes. All seven selected image/project checks pass in
Simulator with no failures, skips or XCTest runtime warnings. The same primary
provider owner passes on physical iPhone 11/iOS 27.2, without UI Automation
permissions, alongside actual UIKit/NSFileCoordinator execution. No new test
count or full-suite rerun is claimed.

Retained signed Release **0.3.82/1**, UUID
`4C531017-3F57-3881-B3B7-47B80208E759`, is installed and opens the original
483-note vault. All56 QA files,41 private files and four continuation files
remain byte-identical through the physical test and installation. Original
preferences and both registrations remain, apart from the original vault’s
visit time. The same56 diagnostic entries remain without a new crash/Jetsam
report. Simulator preservation retains all9,270 original files, the exact
original external-registry prefix and117 original registrations/preferences;
its original two-note vault and normal text size are restored.

See `external-images82-{red,green2,physical}-summary.json` and
`polish82-physical-proof.json`. This repairs provider waits in image previews.
At82, external image refresh still cleared cached previews while reading and
did not follow periodic same-path replacements automatically. Preview83 below
addresses that separate image-presentation gap. Broader provider, marked-keyboard, VoiceOver
and long-use acceptance remains open. AI and Google Drive remain excluded.


### External image refresh without losing previews — preview 0.3.83

The external editor now checks mapped project-image metadata after successful
external-session refreshes, including the existing20-second foreground loop.
It reloads changed or missing images in the same open TextKit editor and keeps
the previous preview visible while provider reads complete or fail. Unchanged
modification/creation dates and byte count retain the cached bitmap without
another coordinated byte read. Explicit Refresh images and foreground refresh
force a read when a provider preserves that metadata. Metadata lookups and
image-byte reads both use the bounded preview reader; root identity, file-size
and path confinement remain.

Image caches are bound to the external presentation and selected project.
Only successful current reads receive updated cache tags; canceled, replaced
project/presentation and closed-session callbacks cannot publish a late image.
Retry image previews remains available after failures, with a44-point minimum
target. This does not write Markdown, properties or project metadata.

A new primary external-editor owner uses the actual production SwiftUI screen,
external session/store/project mapping, UIKit window and TextKit editor. It
fails on82 because refresh never requests/delivers a replaced same-path image.
On83, unchanged metadata causes no coordinated byte read; a held replacement
keeps the640×320 preview and selection, then becomes320×640 in the same editor.
Checkbox Undo/Redo preserves exact BOM, foreign YAML and note/image bytes, with
no vault metadata introduced into the external project. This owner passes on
Simulator and physical iPhone 11/iOS 27.2. All14 selected image, project-capability
and external-session checks pass with no failures, skips or XCTest runtime
warnings. No complete-suite or full accessibility pass is claimed.

Retained signed Release **0.3.83/1**, UUID
`5A002637-CA80-3984-A5E8-6268CAC91310`, is installed and opens the original
483-note vault. All56 QA files,41 private files and four continuation files
remain byte-identical through the hosted physical check and installation.
Both original saved registrations/preferences remain, apart from the original
vault’s visit time; the same56 diagnostics remain without a new crash/Jetsam
report. The original Simulator two-note vault and normal text size are restored.
See `external-refresh83-{red,green,owners,physical}-summary.json` and
`polish83-physical-proof.json`. AI and Google Drive remain excluded. Full
VoiceOver, remaining accessibility, broader composition and longer-use
acceptance remain open.


## Physical task acceptance on preview 0.3.83

The retained signed iPhone 11 app completes a real QA task journey: a new private
draft survives Close and a cold launch without creating a vault task file. Its
recovered form accepts High priority, tomorrow’s quick schedule and an existing
supporting note. Save creates the single task and clears its draft. Completion
survives another cold launch with exact stored bytes; marking incomplete retires
the completion timestamp. Opening the supporting note returns to the same task.

All 56 pre-existing QA files stay exact. Only `.zerus/tasks.json` is added, with
one clearly named test task, **Native task acceptance 1107**, retained in the QA
vault for inspection. Forty private files and all four continuation files stay
exact; the remaining QA identity descriptor only follows its current app
container, with the same vault ID and document-relative identity. Other private
task drafts are unchanged. The original 483-note vault, Notes/All, portrait and
Capture Keyboard off are restored. No new crash or Jetsam report appears. The
receipt is `artifacts/native-ios/acceptance83-task-physical-proof.json`; this is
manual physical interaction, not authorization of physical UI Automation.

The task header’s singular wording repair is prepared in source after this
check. Its Swift syntax parse passes, but the changed source is not compiled or
installed yet: the Mac has less than 1 GB free after removing only generated
native build caches. Signed apps, dSYMs and `.xcresult` bundles are retained.
The phone still runs signed 0.3.83/1; its observed “1 tasks ahead” wording remains
until a later build is installed. Neither native nor canonical iOS build numbers
were changed. Other completion-review acceptance remains open.

## Physical Save to Files acceptance on preview 0.3.83

On iPhone 11, the retained signed app saves PDF, editable Word and HTML copies
of **Native writing QA 1107** through the system Files picker into **On My
iPhone / Zerus Native / QA1107**, outside either vault. All three saved files
equal the prepared artifacts byte for byte and remain exact after a cold
launch. Word passes ZIP CRC and XML/content/table/bold/italic checks; HTML
retains its UTF-8 document, prose, table and inline formatting. The PDF check
here verifies byte equality and its header; the earlier physical Quick Look
and PDFKit inspection remains the rendering evidence.

Cancelling the initial save picker returns cleanly without a saved
confirmation. The native HTML Share popover shows the expected title/type and
is dismissed without choosing a recipient or app. No file is sent. A remote
typing truncation also leaves an empty local test folder, **Native Expor**;
the actual exports are in the separately verified **QA1107** folder.

All 57 QA vault files, 41 private files, four continuation files and 100 task
draft files remain exact against their respective checkpoints. Preferences
change only the two vault visit times. The original 483-note vault, Notes/All,
portrait and Capture Keyboard off are restored. The same 56 diagnostic paths
remain; only the existing Spotlight heartbeat and directory metadata change,
with no new crash or Jetsam paths. Before the intentional cold launch, the
same process is observed over 1,248.4 seconds with interactive task/export work.
This does not establish all-day operation. See
`artifacts/native-ios/acceptance83-exportfiles-physical-proof.json`.

The task-header source repair remains unbuilt; the installed app is still
0.3.83/1. Recovery from an unavailable supported Files/iCloud location and the
other completion-review acceptance remain open. AI and Google Drive remain
excluded.

## Physical properties and reciprocal relations on preview 0.3.83

The signed iPhone 11 app completes a mutation journey in **Native Connection
QA 1107**. A new text property, **QA Status: Ready**, persists in frontmatter
without changing body bytes. Cancelling a staged edit leaves the saved file
exact. Confirmed removal removes only that property line.

Creating **QA Links** opens the folder-definition review: six notes in scope,
zero note files changed. Cancel leaves all 58 current QA files exact. A second
review and Save adds only `.zerus/properties.json`. Native search selects
**Native Safari QA 1107** from **Native writing QA 1107**; the paired-link
confirmation names the two affected notes. Saving writes reciprocal stable-ID
references and one relation pair ID. All 62 QA files remain exact across a cold
launch, and the related note visibly shows the inverse property.

Unlinking through that inverse picker and confirming the paired update returns
both note files byte for byte to their original state. All 64 resulting QA
files remain exact after another cold launch. The final vault retains all 57
pre-existing files unchanged, plus the empty QA relation definition and six
new history records. All 41 private files, four continuation files and 100 task
draft files remain exact. Only the two saved-vault visit times change in
preferences. The original 483-note vault, Notes/All, portrait and Capture
Keyboard off are restored; all 56 device diagnostic entries remain exact.

See `artifacts/native-ios/acceptance83-properties-physical-proof.json` and its
snapshot verifier. This is physical text-property and single reciprocal
relation acceptance. It does not establish all property types, constraints,
schema migrations, bulk actions or history restoration. No new binary was
built; the task-header repair still awaits disk space. AI and Google Drive
remain excluded.

## Physical bulk and automatic-history recovery on preview 0.3.83

On the signed iPhone 11 app, two QA notes are selected for Pin. The review
names exactly those two files; Cancel leaves all 64 QA files unchanged. Apply
adds `zerus-pinned: true` to only those notes and creates one durable bulk
action record. All 65 files remain exact after a cold launch. Recent actions
Undo restores all 64 original files byte for byte and marks both fields
unapplied. Redo reproduces every applied file, including the action record,
exactly. Final Undo and another cold launch reproduce the first undone state.
The retained record is **Pin notes · 2 notes · Undone**.

A separate note, **Native history QA 1107**, is created through the app and
given two saved bodies, **Version one.** and **Version two.** Its formatted
history preview shows the first body; Changes correctly shows the replacement
of two with one. Restore review Cancel preserves all 70 current QA files.
Confirmed Restore returns the exact Version one file, including its stable ID.
The preserved Version two entry can then be restored, returning the exact
second file. All 72 resulting QA files remain exact after a cold launch, and
the live native editor renders Version two. All six new checkpoint/delta
records independently reconstruct and match their stored SHA-256 hashes.
No history clearing or permanent cleanup is performed.

At the end, all 64 pre-existing QA files, 41 private files, four continuation
files and 100 task drafts remain exact. Only the new history QA note, its six
history records and the undone bulk action record are added. The original
483-note vault, Notes/All, portrait and Capture Keyboard off are restored.
The first preference snapshot still contained the previous active QA vault;
after a normal Home/background flush, the saved active registration correctly
names the original vault. The resume value remains semantically empty with
JSON key order reserialized. Both registrations and other preferences remain
intact apart from their visit times. All 56 diagnostic entries remain exact.
See `artifacts/native-ios/acceptance83-bulk-history-physical-proof.json` and its
snapshot verifier. This verifies physical Pin/undo/redo and automatic text
history; deliberate revision milestones, frozen-image restoration and broader
bulk property/relation cases remain separate acceptance. The pending header
repair is still unbuilt because of low disk space. AI and Google Drive remain
excluded.

## Physical deliberate text revisions on preview 0.3.83

The existing **Native history QA 1107** note completes the deliberate milestone
flow on iPhone 11. Create review Cancel leaves all 72 QA files exact. Confirmed
Create freezes Version two in revision 1 and starts revision 2, adding only the
revision index and live commit-token line. A live native edit changes the body
to Version three; the earlier read-only milestone still shows Version two.

Make current review Cancel leaves all 76 current QA files exact. Confirmed
promotion creates revision 3 with Version two and freezes the live Version
three bytes in revision 2, retaining its identity and timestamp. The original
revision 1 record stays exact. The live note and index commit token match.
All 77 resulting QA files remain exact after a cold launch; the list still
marks revision 3 Current, and revision 2 visibly retains Version three in its
read-only preview.

The final QA note body equals its starting body; only the revision transaction
token line is added. All other 71 pre-existing QA files, 41 private files, four
continuation files and 100 task drafts remain exact. The only added files are
the revision index and four automatic history records for this QA note. All
ten history records for the note independently reconstruct with valid hashes.
Both registrations/preferences are preserved apart from vault visit times;
the restored original active registration is checked after normal backgrounding.
The original 483-note vault, Notes/All, portrait and Capture Keyboard off are
restored. All 56 diagnostic entries remain exact. See
`artifacts/native-ios/acceptance83-revisions-physical-proof.json`.

This checks text milestone creation/editing/promotion and preservation through
restart. It does not establish physical frozen-image restoration, revision
Trash or permanent cleanup. No original user note is opened or edited. AI and
Google Drive remain excluded.


## Preview 84: task wording and physical delivery

Signed Release **0.3.84/1** is installed on **iPhone 11 Nox**, iOS 27.2.
The actual task screen now says **“1 task ahead. Make a little progress.”**;
other counts retain the plural. Only that static header and native version
files differ from the sealed preview-83 build inputs. No new trivial wording
test was added: Release compilation and the actual rendered phone screen
verify this change. The preceding 147 consolidated core checks belong to 83
and were not rerun as a new 84 count.

The retained executable has UUID **DED06BC4-074D-3CC1-8126-CF7190288DB4** and
SHA-256 `6da4cfc61a3a153413fe19a79c43dc260c950f7a32d4203abea783f8c47c8511`.
Actual app metadata, SwiftUI scene manifest, signature, provisioning for this
phone and all 220 frozen source/build inputs are verified. The build retains
four known compiler warning lines, including two deprecated TextKit delegate
types; this is not a warning-free-build claim.

All 77 QA files, 40 private files, four continuation files and 100 task-draft
files equal the fresh pre-install checkpoint. The remaining private file keeps
its QA identity and documents-relative root while following the new app
container. Foundation's stored bookmark path, saved location and private
binding agree on that exact folder. Both saved registrations remain, the
original 483-note iCloud vault is restored and persisted after normal
backgrounding, and all other preferences remain exact. No original user note
was opened or edited. All 56 device diagnostic entries are unchanged, with no
new crash or Jetsam path. The same installed process is observed across 209.6
seconds, including normal background/resume; this is a bounded launch check.
Evidence: `polish84-physical-proof.json`, `polish84-task-header.jpg`,
`polish84-physical-restored.jpg` and the retained signed app/dSYM.

The earlier storage blocker was resolved for this build without deleting
evidence. Public APFS clonefile copy-on-write sharing of 105 byte-identical
completed-result payloads recovered 2.36 GiB. Every planned payload hash was
reverified; copies remain independently writable and retain their paths and
checked metadata. Ten files whose metadata could not be preserved were left
unchanged. See `result-storage-dedup-receipt.json`. No archive, IPA, TestFlight
upload, canonical App Store version change or public release was made.
AI and Google Drive remain outside this goal.


## Physical frozen-image revisions on preview 84

On 8 November, signed **0.3.84/1** passes a physical native Files-image import
and deliberate revision recovery journey on iPhone 11. A new synthetic note in
Native Connection QA 1107 receives an exact PNG through **Attach → Attach a
file**. The resulting Markdown and imported PNG are copied from the device and
verified; all 77 existing QA files remain exact. The initial remote hardware
punctuation mapping produced malformed synthetic source and the Mac clipboard
paste did not transfer. The fixture was corrected through native prose editing
and the Files importer, so no successful hardware-Markdown or clipboard claim
is inferred from that setup.

New revision review Cancel leaves all 85 files exact. Create makes two distinct
blue image copies for the earlier and current revisions. Controlled outside
replacement changes only the current QA image to orange; all other 88 files
remain exact. Reopening the note shows orange, while earlier revision 1's
read-only preview still shows blue. Promotion review Cancel changes no file.
Make current preserves orange in revision 2 and creates revision 3 with the
exact original blue PNG. All 92 final QA files survive a cold launch exactly;
current blue and read-only newer orange previews are both inspected afterward.

All 77 prior QA files, 41 private files, four continuation files and 100 task
drafts remain exact; the original 483-note vault and its persisted active ID
are restored. Only the two vault visit times change in preferences. All 56
diagnostics are exact, with no new crash or Jetsam path. See
`acceptance84-images-physical-proof.json` and its source checkpoints. No
permanent cleanup, revision Trash or automatic-history image restore was
exercised. AI and Google Drive remain excluded.

The check exposes an open preview-84 refresh defect: the already-loaded current
revision image remains stale after outside replacement and foreground resume;
closing/reopening reads the correct bytes. Revision assets intentionally do
not appear in the ordinary Files metadata inventory. In preview 84, the production active
scene callback retried only unavailable images. The following preview-85 repair covers
that foreground boundary; frozen-copy recovery and live presentation have
separate evidence.


## Preview 85: loaded image refresh without reopening the note

Signed Release **0.3.85/1** is installed and verified on iPhone 11 Nox, iOS 27.2.
Current-revision assets deliberately stay outside the ordinary Files metadata
inventory. Preview 84 therefore left an already loaded image stale after an
outside replacement, including foreground resume. Preview 85 invalidates cached
image versions on foreground or explicit retry while retaining old bitmaps
until successful replacement. **Note actions → Refresh images** provides the
same recovery for notes with local images, without closing or rewriting them.

The existing production image-loading owner now creates a real revision,
changes only its current image file and verifies the unchanged ordinary Files
inventory. Its actual inactive-scene callback runs before foregrounding; a real
coordinated provider hold observes whether the editor requests replacement
bytes. The valid unchanged84 baseline fails because no read occurs and old
pixels remain. Identical test bytes pass after the presentation repair, keeping
the old bitmap during the read, the same TextKit view, selection, exact Markdown
and checkbox Undo/Redo. This extends the canonical owner rather than adding a
duplicate test or production-only testing seam. Initial setup/compile attempts
are retained separately and are not counted as valid product regressions.

All **14 focused image-loading, revision and editor-presentation checks pass**
with no failures, skips or XCTest runtime warnings. Simulator haptic and
AttributeGraph console messages remain. The preceding 147-check consolidated preview-83
run was not repeated as a new current total. See
`image-refresh85-regression-proof.json`, `NativeImageForeground85Baseline.xcresult`,
`NativeImageForeground85Fixed.xcresult` and `NativeImageForeground85Focused.xcresult`.

The actual signed iPhone app loads the blue current QA image, then a controlled
outside replacement changes only that synthetic PNG. The new native action
shows orange in the same open note and leaves all 92files unchanged. Restoring
only the original PNG and using actual Home followed by normal launch refreshes
the same open note to blue. All 92 final QA files equal their pre-install bytes,
including earlier blue and retained newer orange revision copies. This proves
ordinary vault/current-revision image refresh; external-file metadata-preserved
refresh remains a separate pending physical interaction.

All 40 other private files, four continuation files and 100 task drafts remain exact.
The QA private binding retains its identity and documents-relative root while
following iOS's new container; Foundation bookmark data and saved location
identify that exact folder. Both saved registrations and the original 483-note
vault are restored and persisted after normal backgrounding. Only vault visit
times, the QA bookmark/location and empty-resume JSON key order change; every
other preference remains exact. All 56 diagnostic entries remain exact, with no
new crash/Jetsam path. The same process remains across 231.1 seconds, including
Home/resume, which is a bounded observation. See `polish85-physical-proof.json`.

Retained executable UUID: **4E4D3E88-6753-3B99-8A15-E322C0CA6D02**. SHA-256:
`e2403977f48f1447cd5e0496e9ec0979388d5f4c77704894374a763eacedb16d`.
Actual Info.plist version 0.3.85/1, SwiftUI scenes, strict signature, matching symbols,
provisioning for this phone and 220 frozen inputs are verified. The existing
Team profile permits its wildcard namespace; the actual signed application
identifier is verified as `TX9RYY52XR.com.zerus.notes.native`. Three known
compiler warning lines remain in the Release compile. The canonical App Store
configuration is untouched; no archive, IPA, TestFlight upload or public release
was made. AI and Google Drive remain excluded.

The correct 9A Simulator returns to its original two-note workspace and Home.
All 2,201 pre-existing Documents files remain exact, all 122 registrations remain,
and the original private binding differs only in its verified container UUID.
All other app records/preferences remain intact; ten new unit-fixture binding
records are retained. Eight old OS SplashBoard cache images are replaced by
OS-generated snapshots during app reinstall/backgrounding. Those system cache
changes are explicitly accounted for, not reported as lost app data or an
all-files-identical claim. See `image-refresh85-sim-preservation-proof.json`.

### Physical automatic image-history acceptance (preview 85)

The iPhone 11 now verifies older blue-image preview, restore review Cancel,
confirmed older text/image restoration, recovery of the newer orange-image
checkpoint, and cold-launch persistence. Each restore creates an independent
managed image file. All 92 earlier QA files and 41 private / 4 continuation /
100 task-draft files remain exact, as do all 56 diagnostic entries. The original
483-note vault is restored. See `acceptance85-history-images-physical-proof.json`
and the completion review for bounded scope; this adds no build or automated
test count.

### Physical external-image manual and foreground refresh (preview 85)

A new local external QA project verifies native Refresh images and actual
Home/default resume with already-loaded previews. Copy-back hashes confirm
blue/orange replacement bytes; device-reported size, modification date,
permissions and ownership remain exact. Creation date is not exposed by the
CLI and is not claimed verified. Markdown/BOM/foreign YAML and all 103 prior QA
files stay exact. The only support change adds the QA file/project mapping;
160 other support files and preferences stay exact. No new crash/Jetsam path
appears. See `external-refresh85-physical-proof.json` for the bounded evidence.

### Stable bulk-property sheets and physical Number delivery (preview 86)

Bulk action/history presentation now belongs to the stable screen selection
owner in Notes, collections and Files. Nested property input and review survive
scrolling-list updates and keyboard changes. This repairs an actual iPhone 11
failure that discarded staged numeric values. The existing unfiltered bulk UI
journey fails before the repair and passes with identical test bytes afterward;
six focused bulk-storage/isolation checks pass too.

Signed 0.3.86/1 is installed and opened on iPhone 11. In the existing QA vault,
empty definition-name Save is rejected. A Number definition accepts `42.5`;
`forty` reaches a review with two finite-number issues, zero changes and disabled
Apply. Cancel preserves all 103 files exactly. Valid Apply changes only the two
selected note headers and persists after cold launch. Reviewed Undo restores
both notes exactly and persists after another cold launch. Four new history
records independently reconstruct with valid hashes; all old images and old
history records remain exact. The action record is retained as Undone.

All 161 support files remain; only the QA identity binding's container root
changes, agreeing with its bookmark and saved location. Both registrations,
all other preferences, all 56 diagnostics and the original 483-note active vault
are preserved. Retained app/dSYM UUID: 3A1FF24E-4E0C-36E0-B0DE-8527051B133E.
Actual signature, provisioning, Info.plist and 220 frozen inputs are checked.
See `bulk-properties86-physical-proof.json` and the separate explicit Simulator
preservation receipt `bulk-properties86-simulator-preservation.json`.

This closes the representative Number journey, not all typed-schema, IME,
VoiceOver, provider-recovery or long-use acceptance. AI and Google Drive remain
excluded, and no App Store archive/upload was made.

### Larger-note checkpoint and CPU investigation (preview 86)

A separate prepared 33,446-byte, 240-paragraph synthetic QA note opens in the
rich editor and its native action menu; its file remains exact after restart.
A large hardware-input call times out before delivery completes. The recovery
draft is retained and explicitly saved after restart, but that attempt is not
a successful large-note typing or latency benchmark. The phone records a CPU
resource event (90 seconds CPU over 102 seconds, no termination). Matching
release symbols include native key/change callbacks and repeated Markdown
source/table checks. Root cause remains under investigation. All 107 old QA
files and 161 private support files remain exact, both registrations are kept,
and the original 483-note vault is restored. See `large-note86-checkpoint.json`.

### Prose table-scan optimization and larger-note editing (preview 87)

The table scanner now checks for a pipe byte before constructing lines, and
rejects ineligible header lines before splitting cells. Table syntax and
preservation rules are unchanged. A repeatable optimized Mac benchmark of the
33KB prose fixture drops from about 34ms to 0.086ms per scan; prose with one
literal pipe drops from about 34ms to 1.09ms. Those timings measure the scanner,
not whole-editor or physical-device latency. No tests or production testing
seams were added. Eleven existing rich-text, table, code, cell, image and link
checks pass without failures, skips or XCTest runtime warnings.

Signed **0.3.87/1** is installed and opened on iPhone 11. Its retained app/dSYM
UUID is **D19519C9-40DC-3EB2-A948-C90A0958C23F**. A 41-byte native edit in the
33,446-byte QA note saves completely. Native Undo restores the exact fixture,
Redo restores the exact insertion, and final Undo persists through cold launch.
The initial space and subsequent text are separate native Undo groups; both
are exercised. All 111 prior QA files return exactly, with eleven new history
records independently reconstructed and hash-checked across the comparison.
All 161 private support files remain; only the QA identity binding rebases its
container root. Bookmarks, registrations and the original 483-note vault are
preserved. The 57 diagnostic paths remain, with only existing Spotlight-owned
metadata changes. No new crash, Jetsam or CPU-resource report appears during
this bounded check. See `typing87-physical-proof.json`.

The prior rapid-input CPU event remains relevant. Comparable sustained input,
actual larger-note scrolling and broader history responsiveness still require
acceptance; this scanner optimization does not claim all typing performance is
resolved. Source and all 220 signed inputs are frozen in the retained proof.


## Native preview 89: bounded writing delivery, remaining stress findings

Signed 0.3.89/1 is installed and opens on iPhone 11 Nox. Per-editor analysis
caches the current body's source classification and image references, and the
unsupported-syntax regex is skipped when its required literal markers are
absent. Image scope and refresh-generation safeguards remain. Thirty-nine
existing editor/storage checks pass; all 220 signed inputs match the retained
app and symbols. No tests were added or changed in this optimization batch.

In the 33,446-byte physical QA note, a paced 69-character insertion, native
Undo/Redo/final Undo and cold reopening preserve exact text. All 141 resulting
QA files survive restart. Other note bodies and images remain exact; old
unkept target history is pruned according to the existing default ten-checkpoint-
family policy, with the earlier records retained in backups. The original
483-note vault and both registrations are restored. All 58 diagnostic entries
remain unchanged. See `typing89-physical-proof.json`.

Rapid 858-character input still lags: the complete exact file is observed at
48.8 seconds, after the 23.7-second observation still shows the original.
These are observation bounds, not exact latency figures. Touch flings reach
the final paragraph and return to the heading, but an immediate blank frame
at the end settles on the next observation; it remains a polish finding.
Backgrounding through Device Hub's Home control results in process replacement
without a new crash/Jetsam report, while foreground launch preserves the PID.
Its cause is unresolved. This preview does not claim final sustained-input,
blank-free scrolling or same-process lifecycle acceptance. AI and Google Drive
remain outside this goal; no App Store archive or upload was made.


## Native preview 90: measured analysis and foreground-image repair

Signed 0.3.90/1 is installed and opens on iPhone 11 Nox. Current-body analysis
uses a faster literal comparison and necessary-marker prechecks; the original
syntax classifier still decides source mode. Foreground return now starts a
fresh image-load generation even when another provider read is pending. The
previous bitmap stays visible until replacement, with stale-generation guards
retained. A new real-editor test fails before this repair and passes unchanged
after it; all 40 selected current editor/storage checks pass. No warning-free
console or comprehensive 147-check pass is claimed for this source.

Identical 858-character physical bursts save every character in a short control
and a 33KB note. With matched observations, the short file is incomplete at
14.55 seconds and exact at 16.76; the large file is incomplete at 32.09 and exact
at 34.31. These are bounds including remote input, not exact latency values.
The document-size cost remains open. Native Undo/Redo/final Undo preserves the
large original and exact insertion; Undo restores the short control too. All
152 QA files survive cold launch unchanged. All shared old QA paths, other notes
and images remain exact. Forty new history rows reconstruct with valid hashes;
thirty old unkept large-note records are pruned by default retention and retained
in backups. The original 483-note vault, both registrations and other preferences
are restored. All 161 support files remain, with only the verified QA binding
container root changed, and all 58 diagnostics stay exact. See
`typing90-physical-proof.json` and the current completion review.


## Native preview 91: physical-profile parsing fast paths

Signed **0.3.91/1** is installed and opens on iPhone 11 Nox. A Time Profiler recording
of the actual signed 90 app identifies image-reference parsing during image-free
writing. Matching app symbols are retained; library-mapping/unnamed-frame limits
are recorded in `profile90-phone-analysis.json`. Preview 91 skips full image
parsing without a literal exclamation mark and fence scanning without triple
fence markers. Every syntax candidate retains the original parser. All 40 selected
existing editor/storage checks pass; no tests are added or changed. A separate
Mac diagnostic matches 4,048 original/candidate image/fence cases exactly.

Both 858-character physical bursts save exactly. The short control is incomplete
at 15.87s and exact at 18.09s; the 33KB note is incomplete at 28.90s and exact at 31.13s.
These are observation bounds including remote input, not exact latency or a
statistical benchmark. The gap between first complete-file observations is
about 13.0s versus 17.5s on 90; rapid-burst acceptance remains open. Native nine-group
Undo restores both originals exactly. All 162 resulting QA files survive cold
launch unchanged, with the large rich note visibly Saved after reopening.

All shared QA paths/other note bodies/assets are byte-exact. Nineteen new history
rows reconstruct with valid hashes; nine old unkept large-note records are
pruned by exact default retention and remain backed up. All 161 support files
remain, with only the verified QA identity-binding container root changed.
Both registrations/bookmarks and original other preferences are preserved;
one new QA Recently opened control-note entry is retained. All 58 diagnostic
paths remain, with two existing Spotlight metadata updates and no new crash,
Jetsam or CPU-resource report. Original 483-note Zerus/All/no open note/keyboard
capture off is restored. See `typing91-physical-proof.json` and the current
completion review. No preview-91 background-survival claim, App Store upload or release
commit is made.


## Native preview 92: Tasks footer contrast and current accessibility evidence

Signed **0.3.92/1** is installed and opens on iPhone 11 Nox. Only
`NativeTasksView.swift` changes from 91: the completed-history footer uses
`.footnote`, `Accent.secondaryText` and vertical wrapping. Actual captured light
pixels improve contrast from 2.67:1 to 6.84:1. Its contrast warning disappears from
the unchanged unfiltered Notes/editor/Tasks/Library journey. The test remains
failed on 42 Apple findings (25 partial Dynamic Type,12 clipping,5 contrast), all
at the existing audit helper. Functional assertions complete and runtime
warnings are empty. A fresh clipping finding replaces the removed footer
warning in the total; this is not a full accessibility pass. Full result bundles,
target indexes and attachment crops remain under `artifacts/native-ios/`.

Per-process maximum font arguments verify full native collection/task choices
in Simulator. Physical iPhone maximum text shows wrapped date/vault summary,
Tasks Today-to-All selection, the complete four-line footer, and readable
Library title/Recently Deleted/Inbox/New folder. Physical inline Notes choices
and Tasks Completed selection remain pending. Device Hub drags jump between
positions and briefly capture blank frames that settle correctly; those frames
alone do not establish a product defect. No global OS text-size or VoiceOver
setting changes. Normal launch without arguments restores the default font.

The exact retained signed app and dSYM have UUID
`3E4C89B4-1BF6-32AB-A5FE-29EC5E82CAB9`; all 220 build inputs remain exact.
All 162 physical QA files remain byte-exact,160 of 161 support files remain exact
with only the verified QA identity-root update, both registrations survive,
other preferences are exact and all 58 diagnostics entries remain raw exact.
No new crash/Jetsam/CPU report appears; normal-launch/final PID 5233 agrees.
The original 483-note vault/All/no open note/Capture off is visibly restored.
See `accessibility92-physical-proof.json`.

Simulator preservation covers 12500→12526 paths: all old documents and 123
registrations survive, with two new isolated audit QA vaults (22 files), four
paired private identity bindings and four replacement OS snapshots. Fourteen
new history rows independently reconstruct with valid hashes. Only the old
active identity root and preference registry/bookmark/empty-resume JSON order
change; original active vault is restored. See `accessibility92-sim-preservation.json`.
The preceding 40 editor/storage checks and 4,048-case parser diagnostic belong to
91 and are not relabeled as a current comprehensive 92 pass. Remaining work is
tracked in the completion review; AI and direct Google Drive remain excluded.


## Native preview 93: ordinary-prose literal-marker fast path

Signed **0.3.93/1** is installed and opens on iPhone 11 Nox. The retained app
and dSYM share UUID `3A6D03B6-AD1F-3134-ABF8-EC51884B8230`; all 220 signed
build inputs are verified. Only `NativeTextEditor.swift` changes from 92,
besides the native preview version: an ASCII-letter first byte cannot match
either anchored literal-block pattern, so those prose lines return unchanged
before trimming/scanning. Other inputs retain the original parser.

The physical 90 profile attributes 1.312 inclusive sampled CPU seconds to that
helper in the controlled typing window. A compiled Mac diagnostic matches the
exact candidate with the baseline over 32,529 cases, including all ASCII lead
bytes, combining characters, Unicode newlines, markers, tables, indentation,
multiline/random strings and the actual 484-line fixture. Five alternating
300-repetition helper trials change 172–181ms to 4.95–5.40ms; these are helper
timings, not physical editor latency. All 32 selected existing rich editing,
clipboard/code conversion, storage/Undo, note-link and live marked-writing
checks pass with no failures, skips or XCTest runtime warnings. No tests were
added or changed. Broader retained counts stay at their original checkpoints.

Matched physical 858-character inputs save exactly. Large-note completion is
observed between 27.45 and 29.67 seconds; short control between 14.21 and 16.40
seconds. Their 13.27-second first-complete observation gap leaves the known
document-size overhead open. Both native nine-group Undo operations restore
the original bytes. All 169 resulting QA files survive cold launch unchanged.
Nineteen new history rows independently reconstruct with valid hashes; nine
large-note and three short-note old unkept rows are pruned exactly by default
ten-checkpoint-family retention and remain in backups. Other shared files,
notes and assets stay byte-exact.

All 161 private support files remain, with only the verified QA identity-root
update; both registrations survive. Original other preferences remain exact,
with one new QA Recently opened control-note entry under the new root key.
The first post-restore preference copy catches the prior active ID while vault
activation is in progress; the separately retained settled copy confirms the
original active vault. All 58 diagnostic entries remain unchanged, no new
crash/Jetsam/CPU report appears, and cold/final PID 5240 agrees. Original
483-note vault/All/no open note/Capture off is visibly restored. All 254
physical/Simulator bookmark metadata paths agree with recorded locations.
See `typing93-physical-proof.json`.

Simulator preservation verifies 12,526→12,549 paths, all old documents and
125 registrations, original active vault and other preferences exact. Only
the original identity root rebases; new files are four paired test scratch
bindings, one exact recovery draft, fourteen OS pasteboards and four replacement
OS snapshots. See `literal-analysis93-sim-preservation.json`.

The new Recent key exposes a remaining local-vault recovery issue: search uses
the absolute root URL as its preference identity. The existing stable vault
identity must own these visits across app-container rebases, while preserving
cross-vault isolation. This remains in the completion review alongside typing,
accessibility and the other finite physical acceptance items. No App Store
archive, upload, commit or pull request was made. AI and Google Drive stay excluded.


## Native preview 94: Recently opened survives saved-vault relocation

Signed **0.3.94/1** is installed and opens on iPhone 11 Nox. Retained app/dSYM
UUID is `37FF3F79-1EAA-3DFC-80CB-A7E94C1913BA`; all 220 build inputs, signatures,
actual Info.plist/SwiftUI lifecycle and intended-device provisioning are verified.

Recently opened now belongs to the persistent saved-vault ID rather than a hash
of its changing absolute root URL. Current/canonical/previous registered aliases
migrate in order, deduplicate to the existing 50-entry limit, and retire only
known unambiguous source keys after saving. A valid destination remains
authoritative on retry, including an empty list after Clear; retry also retires
leftover known source keys. Unknown/ambiguous older keys are preserved without
guessing their owner. Unregistered-root fallback remains. VaultStore's existing
previous-root record is generalized for this production caller; AI/integration
behavior is unchanged and outside the goal.

Six selected real search/saved-vault owners pass with no failures, skips or
XCTest runtime warnings. One new primary regression exercises legacy merging,
second relocation/model recreation, Clear, interrupted migration, reused paths
with matching IDs, ambiguity and unchanged note bytes. Its initial version fails
four intended assertions on 93. The extended retry case exposes a remaining
single reused-path failure; the final extended bytes pass after its owner repair.
All results remain: `NativeRecent94Before`, `NativeRecent94After`,
`NativeRecent94RetryBefore` and `NativeRecent94Final` xcresult bundles. Broader
editor counts remain at their own source checkpoints.

Actual iPhone UI preserves both original main-vault visits and the QA control
visit in order. The QA Recent list restores after cold launch. Official preference
copies verify the two saved-ID arrays, retirement of exactly two known path keys,
and unchanged unclaimed keys/other values. No physical note edit or Clear is
performed. All 169 QA files remain byte-exact through install/open/migration/cold;
161 support files remain with only the verified QA identity-root update, both
registrations survive, all 58 diagnostics entries are unchanged, and no new
crash/Jetsam/CPU report appears. Cold/final PID 5283 agrees; 254 bookmark metadata
paths match their locations. Original 483-note vault/All/no open note/Capture off
is visibly restored. See `recents94-physical-proof.json`.

Simulator preservation covers 12,549→12,605 paths, all old documents/125 saved
registrations and other preferences, with original active vault restored. New
scratch bindings/drafts and OS snapshots are classified in
`recents94-sim-preservation.json`; task-draft descriptors with multiple IDs in
reused-path fixtures require a separate record-isolation check, not a preservation
pass relabeled as isolation.

The first Release attempt failed for disk space at symbol generation and was
not installed. Lossless transparent filesystem compression retains diagnostic/DWARF paths
and bytes, plus DWARF dates/permissions and symbol UUIDs, recovering about
2.9 GB. Final preflight/Release/sign/install succeed; no retained result/app/symbol
or source is deleted. The completion review tracks remaining writing,
accessibility and physical acceptance work. AI/Google Drive remain excluded;
no archive, upload, commit or pull request is made.

### Native appearance and Find

Appearance includes independent seven-colour light/dark palettes,11 presets,
native colour pickers, saved themes with reviewed replacement/delete/Undo, and
reset to the original native colours. Settings stay on this device.

Note actions → Find in note (also Command-F) searches current note text, full
code blocks and table cells. Results show context and reveal a temporary highlight
in the editor without changing the note. A code/table result selects its block;
open the block for full editing. Source mode searches its literal displayed source.
External Markdown files use the same Find control. No OCR or attached-file content
search is implied. These additions are included in106 on iPhone 11.
