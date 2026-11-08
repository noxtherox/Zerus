# Native iOS completion review

## Current delivery — iPhone 18, preview 107

**0.3.107/1** is installed and launch-verified on **iPhone 18 Pro Max / iOS 27.2**.
This delivery consolidates the standalone SwiftUI app, shared Apple services and
latest Library/Notes/menu update. The existing 483-note workspace reopens and the
same process stays running, with no new crash diagnostics. A complete app-container
backup precedes installation; both private support files remain byte exact. The
existing vault registry refreshes, and system dyld/snapshot caches change. External
vault files were not edited during the check.

The signed Release binary, symbols, source hashes, screenshot, backups and detailed
proof are retained in `artifacts/native-ios/delivery107/`. Type checking, targeted
lint, the frontend build, 670 web tests and 11 shared Swift tests pass; one optional
web test is skipped. The seven focused Markdown link tests pass after a lint-only
regex correction. Existing native menu/collection Simulator results apply to
matching source hashes; a new broad native test campaign was not run.

The previous finite scope acceptance and its exclusions remain as recorded below.

## Previous completion checkpoint — iPhone 11, preview 106

Reviewed 8 November 2026 against installed **0.3.106/1**, iPhone 11 Nox / iOS 27.2.
The agreed native testing goal is **complete**. AI and Google Drive integration work
are excluded; existing code/account data remain. App Store and desktop releases
are separate from this native device-testing goal.

The user accepts the current accessibility options (8 November). Stop further
accessibility/contrast/VoiceOver work and permission requests for this goal.
Historical audit failures and unverified VoiceOver remain documented facts, not
additional acceptance gates. The keyboard-composition check stays deferred.

## Previous delivery105

Zerus Native uses SwiftUI with UIKit/TextKit 2, with no web editor. Its established
scope includes Files/iCloud vaults, rich/source writing, images, clipboard,
tables, links, properties/relations, tasks, search, organization, external files,
exports, revisions and automatic history/recovery. See [the guide](native-ios.md)
and [parity checklist](native-ios-parity.md). Feature presence alone does not
establish full acceptance.

Preview 105 delivers five accumulated production-source changes together:

- Full-width saved-vault summaries at accessibility sizes.
- Separate Recently opened/Clear layout.
- Document/recovery controls before metadata in expanded Note details.
- Clean external-file retry actually reads the file before clearing access errors.
- Compact external-file attention entry and a native scrolling recovery sheet;
  full error, Share, Retry and reviewed Reload remain accessible without consuming
  the editor viewport. Status stacks at accessibility sizes.

One signed Release build and one phone installation deliver this batch. All five
toolchain/device preflights pass before the native version advance. Actual
Info.plist, native scene lifecycle, strict signatures, intended-device provisioning,
profile expiry and all 220 frozen inputs verify. App/symbol UUID is
**17ECD71C-D81F-31FB-906C-768E1986BC77**. Only the two native project/version files
differ from the final locally rendered candidate. Canonical Tauri/App Store
configuration is unchanged. No archive, IPA, upload, release commit or PR was made.

## Physical evidence and limits

The exact105 binary opens on the physical iPhone. Maximum-text process6293
switches from the original 483-note vault to the existing15-note QA vault.
The saved QA row shows the complete On this device status; its title extends
above the retained scrolled viewport, so this is not proof of the full maximum
row/title/menu. The local normal/maximum proof covers those remaining elements.
Recently opened wraps into two readable lines with Clear below; Clear is not invoked.

The existing batch QA note opens with useful writing space. Note details now
starts with the full Milestone preview.txt name, Linked inside the vault,
41bytes, Preview document and Share controls, all in its first viewport at the
largest text size. Actual Quick Look displays the expected41-byte text.
This completes the previously pending physical maximum-size document-card check.

After explicit termination and a separate no-argument launch, normal process6309
opens the existing external Chart.md with heading, body, unchecked checklist and
blue original image. Save now uses the clean refresh path and remains Saved.
No note text, checklist, image or attachment is changed. This is an available-file
check, not a physical provider-outage or recovery-sheet-failure journey.

The original 483-note Zerus vault, All, no editor, normal text and Capture off are
restored. All 185 QA files and both external Chart project files are byte exact,
with no paths/history added or removed. Of161 private files,159 are byte exact;
the QA identity descriptor has a verified root-only byte replacement and the
existing Chart registration refreshes its access root/bookmark/opened time.
Other external entry/fields remain exact. Both vault registrations remain, with
only QA access rebase and visited timestamps. Recent moves the already-visited
owned batch fixture to the front, preserving other visits in order. All other
preferences are exact, including empty resume data and no font override.
All 59 diagnostic entries are raw exact; no new crash/Jetsam/CPU report appears.
See `recovery105-physical-proof.json` and retained screenshots/binary.

A drag on the Create vault row opened an empty dialog; it was cancelled without
text entry/creation. A later drag from the heading reached the saved rows. Fast
remote scrolls can show immediate blank frames; the next capture without input
renders the content. The same transient behavior is documented in104; its
mirror/renderer origin remains unresolved. Do not repeat an unchanged scroll drill.

## Local verification

The real external-session regression fails twice before repair: retry hides the
unavailable error and never loads returned external edits. All seven existing
external-note owner cases, including the new primary regression, pass afterward
with no runtime warnings. They cover recovery/conflicts/both writers, held-provider
local drafts, rename, BOM/foreign metadata and unsupported-file preservation.
See `ExternalRetryBefore.xcresult` and `ExternalRetryAfter.xcresult`.

Those seven tests precede the presentation-only recovery-sheet edit. The final
candidate builds and has direct normal/maximum Simulator interaction proof:
complete error and reachable actions, missing retry keeping the sheet open,
Reload's discard confirmation and Cancel, Done dismissal, available-again message
and explicit retry dismissal. Periodic refresh first notices the returned file;
that initial return is not attributed to the later button tap. No draft is
shared/discarded. One owned QA file/tracking entry is added; all previous local
files are retained, with independently verified registry addition/root rebasing.
See `external-retry-ui-local-proof.json`.

The auxiliary layout proof covers full saved names/locations/current state,
management menus and real switching, Recent layout, file-first details with
retained metadata after scrolling, and actual Quick Look. Earlier editor,
clipboard, recovery, properties/export and broad journeys keep their original
source checkpoints. No new broad-suite pass is claimed.

## Local candidate after105

A scoped public UIKit accessibility-contrast override now applies to the native
Notes, Tasks and unified Search fields. It preserves native search behavior and
semantic colors. The corrected Debug candidate builds and stays open; Notes and
unified Search return the expected query result, clear and dismiss correctly,
and the Notes placeholder retains its stronger appearance after tab switching.
Tasks has no fixture tasks in this workspace, so no Tasks-query pass is claimed.
Dark and largest-text Notes render, and normal/light/Main two notes/All/no editor
with Capture off is restored. Runtime inspection confirms the visible Notes field
and placeholder label resolve high contrast while the window remains normal.
A runtime-foreground/JPEG-background estimate is about4.77:1 in that light state;
it is approximate and does not establish an Apple audit pass or identify any of
the five nil-element findings.

The first candidate crashed in the Simulator because it read an unset override.
The corrected guard reads resolved traitCollection before assigning the override;
the corrected normal, dark, maximum-size and restored launches stay open without
a new Zerus crash report. The initial crash is retained. All220 final inputs and
the entire signed installed Simulator bundle match. All10518 existing local paths
remain,10517 files are byte exact, and the one private descriptor has an independently
verified access-root-only rebase. External registrations and all preferences
except the existing main vault's access rebase/time remain unchanged. No note or
history is added. See `contrast-trait-local-proof.json` and its retained captures.
No new tests, unchanged audits, save benchmarks, phone install or version advance
accompany this presentation change. The physical phone remains on105.

## Physical recovery attempt and restoration

A later check reused installed105, without a build or installation. An official
`devicectl copy to` with a nested destination and `--remove-existing-content true`
cleared the entire app data container rather than only the named QA directory.
The recovery sheet displayed its complete registration error and kept that error
on Retry, but this is **not valid proof of supported-provider outage recovery**.
The original QA source was restored; further testing stopped. Never use that flag
against this app data domain. A future disruptive device check requires a fresh
complete container backup and inventory, not only selected directories.

The app was terminated before restoration. Fresh backups restore all185 QA-vault
files,161 Application Support files and raw saved preferences exactly. The retained
QA source/image, historical external search fixture and three saved exports also
restore:191 known Documents files. A fresh complete pre-incident Documents/Library
inventory was not captured, so unknown additional files cannot be certified.
Caches/tmp were cleared; the known empty Native Expor QA folder is absent.
No existing iCloud source was targeted by this app-container operation.

After a separate normal launch, the original 483-note iCloud vault/All/no editor/
normal text/Capture off is visible. All185 QA and161 support files still match;
only visited vault timestamps change in preferences. All59 diagnostics are raw
exact, with no new crash/Jetsam. No product source, test, version or installation
changes accompany this attempt. See `provider105-incident-and-restoration.json`.

## Restoration follow-up

The user confirms there were **no personal files** in On My iPhone → Zerus Native
besides the generated test files. A fresh complete current-container backup now
retains358 files plus a hash inventory. This does not retroactively recover a
missing pre-incident inventory; the known empty QA directory and cleared temporary
caches keep the limits stated above.

Restoring bytes did not restore the old filesystem identities: the two external
QA bookmarks and saved QA-folder bookmark needed renewal. Through the existing
native Locate original file and Files folder controls, the same two external IDs
and same QA vault ID are reconnected. Chart reopens Saved with the blue image;
the external search fixture opens Saved with its expected body token. The QA vault
opens with15 notes, then the original 483-note iCloud workspace/All/no editor/normal
text/Capture off is restored. No note, image or checklist is edited.

Final full-container copy retains all358 current paths:356 files are byte exact.
All191 Documents files are exact. Only external access metadata and vault access/
visit preferences change;160 other support files and every other preference stay
exact. Both saved vaults and both external identities remain. All59 diagnostics
remain raw exact, and the same restored process remains open. No build, install,
version, test, audit or accessibility change accompanies this restoration.
See `restore-access105-proof.json`. This is access restoration, not a new
physical provider-outage pass. The goal remains active.

## Physical local-file recovery

A complete358-file backup and inventory precedes this check and exactly matches
the restored container above. In Apple's Files app, only the owned Chart.md is
temporarily renamed ChartPending.md. Read-back confirms both project files retain
their bytes. The existing native editor keeps its full body, unchecked checklist
and blue image, shows Needs attention, and opens the complete moved-file message.
Retry loading keeps that message while the original path is unavailable.

Files restores the original Chart.md name. Both project files are byte exact.
Foreground refresh first changes the sheet to The file is available again;
explicit Retry then dismisses it to the same Saved editor. This verifies physical
local-file unavailability and return, not a cloud-provider disconnection or an
interrupted write. No draft is edited, shared or discarded.

The original 483-note All workspace/no editor/normal text/Capture off is restored.
All358 previous paths remain:357 files are byte exact, including all191 Documents
files and preferences. The existing Chart registration changes only its opened
timestamp; two system SplashBoard snapshots are added. All59 diagnostic entries
remain raw exact, process6395 is unchanged, and all220 local source inputs match
their checkpoint. No build, install, version, test or accessibility work occurs.
See `rename-recovery105-proof.json` and its complete before/after inventories.

## Physical interruption recovery

Installed105 now passes an actual prewrite interruption on iPhone 11. In the
existing empty input QA note, a single R is entered. SIGSTOP holds the process;
full read-back proves the canonical note still equals its original bytes while
the owned private draft contains exactly the original plus R. SIGKILL ends6395.
A separate normal launch6486 restores the same editor, automatically saves those
exact draft bytes, retires the draft and shows Saved without a save-button tap.
The QA character is then removed through the native editor and its original
file bytes are verified. Original483/All/no editor/normal/Capture off is restored.

The initial direct tool-round-trip pause arrived after a completed write and is
not prewrite evidence. A bounded input-marker/signal helper reaches the intended
window without changing the product. Earlier debugger setup crashed Mac LLDB;
the subsequent connection was detached and exited before any note input. The
successful case uses no debugger or production hook and changes no app binary.

All161 private support files and all source notes/assets/exports retain their
bytes. Four new QA history records reconstruct exactly; normal retention prunes
one older three-record QA family, independently matching the unchanged default
ten-checkpoint policy. All29 surviving records reconstruct with valid hashes.
Only vault visit timestamps and the already-owned Recent order change in
preferences; four system Metal cache files appear. All59 device diagnostics
remain raw exact. No tests, build, install, version or accessibility work occurs.
See `interrupt105-proof.json` and complete before/held/cold/restored captures.

## Mobile-baseline audit and local folder catalogue

Reviewing actual mobile actions, rather than only historical acceptance notes,
finds implementation gaps: Library folder rename/delete, custom appearance
palettes/presets/saved themes, and the explicit in-note Find entry point. These
are within the original non-AI/non-Drive scope and remain required work.
The relevant baseline is MobileZerus TypeActionSheet/NoteActionSheet and
MobileThemeSettings; installed105 Library/Settings do not provide them.

The first folder batch is implemented locally, without a phone update. Native
scanning retains empty directories and parents. New folder creates an actual
empty directory rather than a placeholder note; hidden/assets/outside-link paths
are refused. Library supplies per-saved-vault sibling ordering, shared
`.zerus/type-icons.json` icons, emoji/default controls and Add subfolder. A native
symbol catalogue writes portable Tabler identifiers; other saved identifiers
remain intact with a folder fallback and explicit picker description. Folder
collections now offer New note with the selected folder already chosen.

The first focused storage run passes37 checks (three new folder cases,26 vault,
three registry and five saved-link cases). The final path-guard checkpoint passes
the three folder cases again, with no failures/skips. A later collection-compose
presentation edit builds and has direct UI proof; these results are not a new
whole-suite pass. Existing UITextItemInteraction deprecation warnings remain.

Actual normal-size Simulator interaction creates Catalog QA1108/Empty with both
counts0, saves/renders Briefcase, opens the empty child and creates Catalog note
in that exact folder. The new editor shows Saved. Move down places Inbox before
the QA subtree. The original two-note simulator workspace/All/no editor/normal/
Capture off is restored. All12985 prior paths except four system snapshots remain;
12978 files are byte exact, with two independently verified descriptor root-only
rebases and expected preference changes. Only the owned note/icon files are added;
no prior notes/history change. All 127 saved registrations remain. All223 final
inputs and the entire installed Simulator bundle match, strict signatures pass.
See `folders-local-proof.json`, the focused results and retained UI captures.

Folder rename is now implemented locally. The native form reviews the complete
source/destination, file/folder counts and affected notes before confirmation.
Coordinated transactions update note links, legacy relation/supporting-note
references, vault attachment paths, schemas, shared icons and saved views while
preserving foreign fields. The full directory move retains empty directories,
opaque/binary files and hidden foreign content. A durable receipt commits with
the note/metadata edits; cold recovery completes the move before allowing writes.
Changed reviewed files, destination collisions, ambiguous links and symlinks are
refused. Case-only changes keep their original spelling.

All39 focused checks pass: four new rename owners, three catalogue, three move
resource, three relation-maintenance and26 vault cases. Real filesystem cases
include cold recovery before/after the directory move, changed-file recovery
refusal, stale reviews and workspace/session isolation. The actual Simulator
flow reviews then cancels without changing source/icon bytes or creating the
destination; a second review renames the owned folder, retains Briefcase/order,
and opens Catalog note as Saved at the new path. Its bytes remain exact. The
original Main2/All/no editor/normal/Capture off state is restored.

Full13020-file before/after inventories prove13011 old files byte exact. The
owned note moves byte exact; only its shared icon key changes in the vault.
The other differences are two verified private access-root rebases, the expected
visited bookmarks/times and folder-order prefix, and four system snapshots.
All 127 registrations and every other preference remain intact; no history is
added or changed. See `folder-rename-local-proof.json` and retained captures.
All226 inputs are frozen. Two review-copy strings were polished after the39-test
and actual UI checkpoint; a separate final build passes, without another install.

Recovery limit: if files change after the metadata commit, the receipt/files are
preserved and writes stop. Restore the reviewed files through Files and reopen
to finish; no native conflict merge/cancel control is provided. This is not a
claim of universal provider conflict recovery.

## Local recoverable folder deletion

Folder deletion now has a native content review and moves the complete folder
into a recoverable group in Recently Deleted. Every note/attachment byte and empty
directory is retained; shared schemas, icons and saved views are archived and
restored together. Existing ordinary note Trash is separate and preserved.
Restoration refuses occupied destinations or conflicting owned settings while
retaining unrelated metadata updates. Device-private folder order/defaults reset
on deletion and are not restored automatically. Restoring the group returns all
its content together rather than restoring its notes individually.

The group has separate permanent-cleanup review and an additional irreversible
action confirmation. Only the reviewed archived directory/settings are consumed;
active copies and other revisions/automatic history remain. Changed remaining
files stop partial-cleanup recovery without deleting the outside edit. A pending
directory receipt commits alongside metadata in the existing transaction journal.
Completed archives are read by the Trash UI, not ordinary save recovery. Unknown
retained record versions are preserved and shown as Trash issues without blocking
unrelated active-note saves. Changed files after a confirmed move still preserve
the pending record and suspend writes until reviewed files are reconnected.

The initial focused run passes41 checks. A new primary-owner extension proves the
retained-record save bug before the repair at the actual identified-note write
boundary; an initial legacy-note case bypassed that path and did not prove it.
The final repaired checkpoint passes all41 again (four folder-trash, four rename,
three catalogue, four note-trash and26 vault checks), with no failures, skips or
runtime warnings. The two existing text-item deprecation warnings remain. A
refactor visibility compile error was corrected before the final result; mutable
capture warnings from the early candidate are absent from the final build.

The tested Simulator app already exactly matches the final build and strict
signatures pass, so there is no additional install before normal launch. Actual
UI review/cancel keeps the source and icon bytes exact with no archive created.
After deletion, a read-only filesystem check proves the source absent, stored
note byte exact and pending receipt finished. Recently Deleted displays the
folder group. The permanent review/warning is inspected and dismissed without
confirming deletion. Restore removes the group, and its note reopens Saved at the
original path. Main2/All/no editor/normal/Capture off is restored.

Mirror drags and a wheel action did not reveal the lower Library folder rows.
The existing QA Inbox Move down menu brought the owned folder into the first
visible row; no further scrolling campaign or app layout workaround was added.
One initial cleanup tap had no visible effect; fresh settled positions then open
the review normally. Neither event is claimed as a passing scroll check.

Full13102-file before/after inventories have identical paths:13100 files byte
exact, with only one independently verified QA private descriptor root rebase and
preferences changed. Every Documents note/asset/metadata/history file is exact;
no history or other file is added/removed. All 127 saved registrations remain.
Only visited access/times/current bookmark and the expected QA folder-order
removal change preferences. The order is now Inbox only; other preferences remain
exact. No pending/group record survives successful restoration. All229 final
inputs and the installed Simulator bundle match the final tested checkpoint.
See `folder-trash-local-proof.json` and retained UI captures/inventories.

The iPhone remains on105. Custom palettes and Find must be completed and verified
before the next accumulated device delivery; no immediate version106 or additional
accessibility work accompanies this local work.

## Scope decisions and final acceptance

| Area | Final status |
| --- | --- |
| Folder management | Implemented/tested locally and delivered in106 on iPhone 11. Native folder menu inspected; no personal folder mutation. |
| Custom appearance | Implemented locally: independent seven-colour palettes,11 presets, native pickers, saved themes/replacement/delete/Undo/reset. Five final appearance owners and visible native flow pass. Delivered in106; physical screen inspected without changing settings. Current accessibility options remain accepted. |
| In-note Find | Implemented in vault/external note actions with Command-F, contextual case/diacritic search, full code/cell content, stale-result refusal and visible temporary highlight. Local real-editor/UI proof and physical Find/result/highlight pass on106. |
| Final delivery | Complete: finite scope reconciled;235 frozen inputs, one signed106 Release build/install, physical launch/feature inspection and data/diagnostic verification pass. |
| Accessibility | Accepted by the user with the current options. No more accessibility checks or changes for this goal. Historical unfiltered audit remains36 findings; no conformance/VoiceOver pass is claimed. |
| Contrast | Current options accepted. The scoped local trait candidate remains retained, uninstalled; no further contrast work or audit required for this goal. Historical nil-element findings remain documented. |
| Files/provider recovery | Physical local-file rename/unavailability, failed retry, return and successful recovery pass on installed105; all source bytes are preserved. Cloud-provider disconnection remains unverified. The earlier device-tool incident is not provider evidence. |
| Lifecycle | Physical98 Home/return and installed105 prewrite SIGSTOP/SIGKILL/cold recovery pass with exact bytes. Original workspace and QA note are restored, diagnostics unchanged. Earlier89 process replacement remains unexplained; its cause is not inferred from this pass. |
| Marked text | Physical commit/cancellation/Undo beyond Portuguese/English prediction is explicitly deferred by the user: Leave this check pending. No Japanese keyboard was added. Separate real UIKit marked-text/presentation evidence remains; do not repeat setup requests or call physical IME passed. |

No further typing/save timing campaign is authorized. Historical observations
include remote typing/file observation and do not measure a post-typing save wait.
No repeated identical audit can localize the five nil-element reports. Standing
physical UI Automation permission is unanswered and is not assumed. Do not request
VoiceOver permission again after the user's accessibility acceptance. Supported
format limits remain: advanced unsupported Markdown/CSS stays intact through
source editing; heading edits preserve filenames, while Rename reviews references.
Every third-party extension/provider is not a finite acceptance gate.

The previous review is archived as `completion-review-through104.md` under
artifacts, alongside earlier source checkpoints and reviews.

## Local native custom appearance

Custom appearance now provides independent seven-colour light/dark palettes,
eleven established mobile presets, native colour pickers, named saved themes,
reviewed replacement, deletion with Undo and reset to existing native defaults.
Settings remain device-private; invalid/foreign saved data are retained. Native
UIKit/TextKit colours, links and code/table previews use the same window palette
as SwiftUI and presented sheets without replacing writing or its Undo state.

The preceding complete owner batch passes33 cases. The final five appearance
owners pass after a real sheet regression: the sheet retained default RGB while
the root used the custom palette. The regression fails before and passes after
window-level trait delivery. The earlier seven-role raster itself passed and is
not a reproduced failure. Visible native interaction confirms live presets and
sheet controls, a picker change to#5C5C5C, saved-theme application/delete/Undo and
reset. All existing Documents bytes remain exact; only independently verified
Main access rebasing/timestamps and XCTest/system private files differ. All 127
saved vaults and every other preference remain, with no theme keys after cleanup.
See `appearance-local-proof.json`,233 frozen inputs and the retained results.

These changes are local, with no phone version/install change. Find within the
current note, final scope review and one accumulated iPhone 11 update remain.

## Final local scope reconciliation

The finite non-AI/non-Drive mobile scope is implemented: native runtime/writing,
Files/iCloud vaults, supported rich/source Markdown, clipboard, images/tables/links,
properties/relations, tasks, organization/folder actions, search/Find, external
files, exports, revisions/history and recovery. The8 November action audit gaps
are now filled. Folder actions retain their39/41 owner results and actual local
flows; appearance retains its final 5 and full native picker/saved-theme flow.
Find's 10 selected owners pass, and its final primary real-editor owner passes
after visual polish. Actual Find opens from note actions, returns contextual
results and visibly highlights Capture in the unchanged Saved note. All existing
Simulator Documents remain byte exact, with no Documents added/removed.

The supported limits remain intentional: advanced unsupported Markdown uses the
native source editor; code/table Find results reveal the block token, with full
matching context in the results; no OCR/attached-file search is claimed. Symbols
use a curated native catalogue plus emoji, retaining other clients' stored IDs.
Historical broad parity clauses do not add every provider/extension as a gate.
Accessibility is accepted and physical IME explicitly deferred; AI and direct
Drive work remain excluded. No new latency or accessibility campaign is required.

The only completion step now is combined physical delivery and launch/feature
inspection on iPhone 11. All 235 local inputs are frozen in
`find-local-final-inputs.json`; `find-local-proof.json` retains exact verification.
A complete 365-file physical app-container backup and hash inventory precede the
update. Platform verification, selected Xcode27.0/27A266a, device tooling and
generic-device build settings pass before advancing the native preview version.
No Tauri/App Store version, archive, IPA, upload or release commit is requested.

## Combined physical delivery 106 — completed

One signed Release build and one iPhone 11 installation deliver the full pending
native batch. The 235 frozen inputs match, with only the two native version/project
files differing from the verified local candidate. Actual installed app metadata
is 0.3.106/1; strict signature, intended-phone provisioning,2027-11-06 expiry,
SwiftUI scene manifest and matching app/dSYM UUID
B4E5D51D-8EB2-3330-9F9E-698395A28879 verify. The exact binary and symbols are retained.
No Tauri/App Store number, archive, IPA, upload, commit or PR changes.

Physical process 6765 opens the original 483-note iCloud vault. The user's reported
Collapse chart legend note renders native heading/bold text, its actual chart image
and Acceptance Criteria without a source banner. Find legend returns 10 contextual
results; choosing a body match closes the sheet and visibly highlights legend while
Saved remains. No writing is entered. Appearance follows existing System/Dark and
shows its preview/presets; folder actions include order/icon/rename/delete/subfolder.
Phone theme/folder mutations are not repeated; their complete local owner/UI proofs
remain. Original483/All/no editor/normal text/Capture off is restored.

The complete 365-file pre-install backup is compared with 368 post-check files. All
192 Documents files and161 private Application Support files are byte exact, with
no note/asset/history/export additions or removals. Only the existing Main vault's
lastOpened changes semantically in preferences; empty resume JSON differs only by
key order. Every other preference and both registrations remain. System dyld/Metal
caches and SplashBoard snapshots change. All59 diagnostic records remain raw exact,
with no new crash/Jetsam report; process 6765 survives the complete inspection. Main
iCloud files are outside the app-container comparison and were searched/read only.
See `batch106-physical-proof.json` and retained binary/results/captures/inventories.

The finite agreed native-testing scope is complete. The explicit exclusions,
accepted accessibility state, deferred physical composition and documented source/
icon/Find limits remain as stated. Broader historical parity clauses are not new
gates, and App Store distribution is a separate task.
