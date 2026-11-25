# Native macOS app

This **native SwiftUI macOS application is the production macOS app**. It replaced
the Tauri desktop app on macOS and ships as **Zerus** under `com.zerus.notes`
(Apple Silicon, macOS 26+). Preview builds used `com.zerus.notes.macos.native`
("Zerus Native"); `MacIdentityMigration` copies their preferences on first launch,
and private Application Support/Caches folders keep their "Zerus Native" names.
Releases are published with `pnpm macos:release` (see the README). AI parity
remains deferred. The history below records the migration. Development and Computer Use checks use internal app builds.
Create a DMG only when needed for packaged-app QA; the user does not need to
retest intermediate builds. Deliver the final DMG after acceptance. Current
non-AI performance and installed evidence is recorded in
[native-macos-non-ai-acceptance.md](native-macos-non-ai-acceptance.md).

## Current acceptance and candidate

The current theme-correction build is **0.3.85/build126**, requiring Apple
Silicon and macOS 26+. It fixes custom palettes opening against the system mode
instead of Zerus's explicit Light/Dark setting and makes the inspector use the
theme surface. Loading a preset or saved palette also selects its matching
Light/Dark appearance, so native title bars, search fields and controls follow
the palette. Sheets and popovers explicitly follow the app appearance too.
All three appearance checks pass; the inactive-palette baseline failed twice,
and the additional native-chrome baseline failed six assertions before repair. The final
12 appearance/presentation tests pass. The signed build126 was visually checked
with Paper and Midnight across the title bar, native search fields, sidebar,
list, editor, inspector and nested colour settings; Midnight persists after
restart and the isolated test note stays byte-exact. Its DMG is notarized,
stapled and Gatekeeper accepted, and the private download hash matches. The previous build125 baseline passed 303 non-AI
checks; that complete suite has not been repeated for this targeted correction.
The later iOS-only edits are not part of the Mac target. AI remains deferred;
Windows and direct Google Drive are excluded by the user's current scope.

Features493 accepts installed Settings appearance/pane controls, CLI
Install/Update/Cancel/export, registration and metadata Apply, nonempty relation
repair Review/Cancel/Apply, exact readback and restart. Features494 accepts
Kanban card/column, folder and tab pointer delivery, actual 600-point edge
resize, full folders hide/restore, overflow scrolling, and Portuguese dead-key
Save/Undo/Redo/reopen. No rebuild was needed for those checks.

Features485–486 verifies Developer ID signing/notarization and a real signed
Sparkle update download/install/save veto/relaunch. Features492 verifies the
existing notarized DMG's mount/copy/install/Save/Undo/Redo/restart path. Features495
rechecks the exact unchanged package, installed app signatures, notarization
tickets and Gatekeeper. No public release has been published.

VoiceOver QA and microphone dictation are explicitly excluded from this goal by
the user. Neither is claimed as verified, and no OS input setting was changed.
The existing verified candidate/package can be reused for final handoff.
See `artifacts/native-macos/features493/permission-recovery.json`,
`features494/verification.json` and `features495/current-package-verification.json`.

## Historical implementation and QA checkpoints

The following checkpoints retain their original state; use the current summary
and acceptance ledger above for resolved blockers and active scope.

Latest implementation (features450): committed folder-rename recovery now
preserves local tabs/pins, folder context/query, default note folder and folder
ordering before clearing its durable receipt. Recovered startup skips stale
cached paths. The extended existing owner reproduces ten old-code failures;
three final affected owners pass. Installed real committed interruption on 180
legacy notes now retains the pinned active note, renamed folder tab and query,
with exact note/control/metadata bytes and healthy restart. No version/DMG;
iOS behavior is unchanged. The previous 292-check aggregate predates this repair;
the features451 current aggregate is running. Evidence:
`artifacts/native-macos/features450/verification.json`.

Latest installed verification (features448): a real 180-note folder rename is
interrupted with its transaction uncommitted and a verified partial write set
(24 intended, 158 original). Startup recovery restores all 182 vault files
byte-for-byte, leaves the original folder, clears pending journals/receipts and
opens a recovered note normally. Process identity is verified before stopping
and killing only the owned QA app. Recovery exits normally. No fabricated
journal, source/test/build/version or DMG change. Later committed-receipt,
provider and purge phases remain separate. Evidence:
`artifacts/native-macos/features448/verification.json`.

Latest installed verification (features447): real iCloud Drive upload,
cloud-only note materialization, native edit/save/re-upload and a second
cloud-only reopen pass with exact BOM/CRLF/frontmatter and control-note bytes.
Cloud-only state is independently confirmed before each app launch; the initial
probe's stale URL-resource cache is recorded separately. Both app runs exit
normally. No product/test/build/version/DMG changes. Account/network disconnect,
other-device conflict and active-transaction interruption remain separate.
Evidence: `artifacts/native-macos/features447/verification.json`.

Latest installed verification (features442): a private draft survives SIGKILL
while cached startup cannot finish because the owned root is unavailable. The
exact checkpoint and QA process identity are verified first. Relaunch recovers
the draft as unsaved without changing the canonical file; explicit Save writes
exact BOM/CRLF/header bytes and removes the recovery checkpoints. Normal reopen
has no stale recovery prompt and all vault files are exact. No source/test/build
or DMG change. Active coordinated-transaction interruption and actual cloud
provider behavior remain separate. Evidence:
`artifacts/native-macos/features442/verification.json`.

Latest installed verification (features441): warm cached startup survives an
unreadable Markdown file and temporary local root-access failure. Valid notes
remain usable, failed writes keep private drafts, and automatic recovery plus
explicit Retry after repair/access restoration preserve saved and unsaved text.
Reconnected Save and healthy reopen retain exact BOM/CRLF/header bytes; all vault
files remain exact across restart and original permissions are restored. No
source/test/build or DMG change. Actual cloud-provider reconnect and forced
process interruption remain open. Evidence:
`artifacts/native-macos/features441/verification.json`.

Latest installed verification (features440): local two-window outside edits and
retained-note recovery pass on the unchanged features439 app. Clean editors adopt
outside text; a private retained edit stays protected while the peer saves newer
work; export is byte-exact before adopting the peer version. Both windows follow
an outside rename by stable identity. Normal relaunch opens the renamed note,
with all vault files and private export exact. No new source/test/build or DMG.
Cloud-provider reconnect, interrupted startup and broader simultaneous writes
remain open. Evidence: `artifacts/native-macos/features440/verification.json`.

Latest implementation (features439): raw text-file previews reject invalid
UTF-8 without creating an editable empty document. Coordinated saves preserve
BOM, creation/access metadata and unchanged bytes, while refusing an outside
edit and keeping the local draft visible. Three final affected checks pass;
baselines reproduce ten persistence failures and the disabled-TextEditor UI gap.
Installed raw-file preview, exact BOM/CRLF/attribute save, stale refusal and fresh
reopen checks pass. The later features444 complete gate includes this repair and passes all 292 enabled non-AI checks.
No DMG, version or iOS change. Evidence:
`artifacts/native-macos/features439/verification.json`.

Latest integrated verification (features444): all 292 enabled non-AI checks
pass across five fresh processes with exact identifier coverage, no skips or
duplicates and unchanged source/compiled/configuration inputs. All six OCR checks
pass on the first attempt. The same thirteen AI classes remain deferred. This
snapshot includes the features439 preview repair. It does not establish the
remaining installed/manual or release acceptance. Evidence:
`artifacts/native-macos/features444/complete-non-ai-coverage.json`.

Editor backlog reconciliation (features445): current passing owners cover the
historical marker/range, interleaved ownership, partial card and structured-paste
repairs. A fresh pinned-web probe still rejects reference links/images, matching
native Source fallback; seven list/quote/rule controls import successfully. Do
not treat the old generic marker/range/paste wording as a demonstrated missing
implementation. Physical input/accessibility and specifically identified new
contract failures remain separate. Evidence:
`artifacts/native-macos/features445/verification.json`.

Latest implementation (features437): successful note moves and external
copy/move operations suggest icons for newly created destination levels, retain
all existing overrides, and preserve unrelated raw metadata. External import now
accepts a new folder path. All 22 affected owners pass; the baseline reproduces
five missing-suggestion assertions. Installed note-move and external-copy checks
pass with exact original note/external-file bytes and targeted icon-token
insertions. No DMG, version or iOS change. The later features438 aggregate
passes all 291 enabled non-AI checks, including this change. Evidence: `artifacts/native-macos/features437/verification.json`.

Latest implementation (features436): folder rename, recoverable Trash and
Restore preserve exact UTF-8 metadata keys and unrelated value tokens across
properties, icons, active views and saved views. Restore retains unrelated
settings added after Trash and refuses conflicting current folder settings.
Sensitive receipts use version 2, which older clients refuse; ordinary receipts
remain version 1. The owner reproduces 32 baseline failures, all 59 workspace
checks pass, and three final lifecycle checks pass after numeric-comparison
hardening. Installed optimized-app checks cover rename, Trash, Restore, Gallery,
named views, icons and restart, with exact original note/attachment bytes. No
DMG or version change. The later features438 aggregate passes all 291 enabled
non-AI checks, including this change.
See `artifacts/native-macos/features436/verification.json`.

Latest implementation (features435): shared folder icons now render in the
sidebar, folder tabs and move/document folder selectors. The native picker
includes the complete offline desktop Tabler catalog (5,130 icons), search,
pagination, emoji and reset, with desktop concept suggestions for new folders.
Shared icon writes patch only the selected JSON token, retain exact UTF-8 keys
and unrelated source bytes, and refuse stale reviews/ambiguous selected keys.
Unicode-equivalent keys and leading-BOM foreign strings survive real installed
saves/resets. Peer and raw startup-cache updates are covered. Installed selection/Cancel/Undo/stale/reload/
reset/emoji/suggestion/restart checks pass with exact original note bytes. The
complete current non-AI gate passes 289 checks with exact coverage and unchanged
code/config/resources; its six OCR checks needed a generated-cache retry and
the initial Vision failure remains recorded. No DMG or version change. The iOS
source branch is unchanged. Features437 supplies suggestions for folders first created by moves/imports;
features436 supplies folder-lifecycle raw metadata proof.

Latest workflow verification (features434): all five web-format named view
presets apply in the installed native app with exact shared configuration.
Native Gallery/Calendar copies read back through the current web normalizer with
equal settings; filters, grouping, columns, dates and restart were verified.
Original note/schema bytes remain exact. No product/test changes, new build or
DMG. Live cross-client UI/provider transport is still pending.

Latest feature verification (features433): sequential numbered-list display now
preserves existing Markdown marker spelling through edits, Return, checkbox
changes and Undo. All 132 editor owners pass. Installed isolated-vault checks
pass with exact original BOM/CRLF/foreign-field bytes after Undo and exact
restart readback. The final complete non-AI gate passes all 288 checks across
five fresh processes, with no skips/duplicates and unchanged tested inputs. The
first failed gate attempt and the tab-close fixture synchronization repair are
retained in the evidence. No DMG or version change. See the current acceptance checklist for remaining workflows.

Current status (2026-11-23): the user accepts performance for now and requests
feature completeness; AI remains deferred. The signed internal app includes the
features418 attachment Undo and local-file preview repairs. Features417 and
features419 add installed link and multipage export/print evidence. No new DMG.
The earlier features422 aggregate passed all 283 enabled checks across
five fresh processes with exact coverage, no skips/duplicates and unchanged
inputs. A copied test-configuration path error was corrected; temporary diagnostic
logging was removed and all original source/test hashes and assertions retained.
The earlier features421 failures remain recorded; their precise intermittent
Vision cause is not proven solely by the configuration repair. See the current
acceptance ledger; the following historical entries are not current gate claims.

Core installed navigation now has bounded acceptance for collection/note layout,
sidebar restoration, retained Undo/Redo, tab menu actions, history and independent
windows with guarded close/reopen. Navigation394 repairs actual middle-click tab
close (including pinned tabs) and nearest-neighbour selection after active close.
Four focused checks and installed coordinate-based close/reopen checks pass.
Pointer tab reorder and overflow scrolling delivery remain unverified. The current
complete green aggregate is features422, including the new navigation and
attachment transport checks. No new DMG or version change.

The delivery checklist now names the 25 non-AI workflow rows and distinguishes
known gaps, bounded proof and unverified routes in the acceptance record. The
previous four headings were categories, not four small remaining tasks.
Performance393 removes repeated exact-body admission parsing when reopening recent
tabs. Focused controls, all 281 configured non-AI checks across five fresh
processes, and native outside-edit/mode readback pass. Exact coverage and frozen
inputs are verified; broader responsiveness and final delivery remain unaccepted.
The prior monolithic OCR host failure is separate from this complete coverage.

Resources392 recovered QA disk headroom by sharing byte-identical completed test
data with independent APFS clones, preserving result bytes and readable bundles.
No product change or DMG. The original six OCR checks passed in a focused process,
but the complete unchanged non-AI run remains non-green: 278 of 281 passed, with
three workspace OCR checks failing after missing Vision E5 resource messages.
This does not establish an interface speed improvement or a disk-space root cause.
See the acceptance record for exact preservation checks and limits.

Rules391 fixes caret Return at the leading edge of unowned root/root-quote
dividers, so new text appears above the rule. It also removes a redundant CRLF
blank from the dash-rule safeguard. The final owner, frozen 275 non-AI/non-OCR
checks and optimized native exact save/caret/Undo/Redo checks pass. Compact
list-owned Return and broader parity remain open; resources392 records the later
focused OCR success and combined-run failure. No new DMG,
version, iOS or AI change.

Board390 diagnoses the remaining pointer-drop acceptance gap without changing
production. A fresh native board stays unchanged after card/header drags; isolated
SwiftUI controls also fail to complete, while a raw AppKit first-gesture control
reads the payload at the correct target. This does not establish which delivery
layer is at fault. Kanban pointer acceptance remains open; no speculative API
replacement or new production build was made.

Performance389 adds guarded local-row export for ordinary independent quote
prose, including the first edit after opening a note. Original/candidate behavior
controls, the frozen 275 non-AI/non-OCR checks and native exact save, composition
and Undo/Redo checks pass. Matched long-note keyboard sampling shows substantially
less export work for this workload. Contextual/multiline export, broader UI
responsiveness and full acceptance remain open. No new DMG or version change.

Performance388 reuses the original parser mapping within quoted-divider Return,
removing a repeated unchanged-note pass while retaining transformed ownership
checks. The focused/frozen 275 non-AI/non-OCR checks and native exact save,
receiving-caret and Undo/Redo checks pass. One matched long-note capture shows
lower keyboard-path work; overall responsiveness is still under verification.
No new DMG or version change.

Rules387 carries child-list quote ownership through divider splits and places
the after-divider caret in the first parser-resolved child. Child-owned quotes
and existing inline formatting remain intact. The focused/frozen 275 non-AI checks
and native source/Undo/Redo checks pass; compact/empty children, broader variants,
performance and full acceptance remain open. No new DMG or version change.

Rules386 extends that divider caret split to nested direct quote levels and
retains distinct following paragraph boundaries. Its focused/frozen 275 non-AI
checks and installed Rich-text save/Undo/Redo checks pass. The pinned reference
export merges two following paragraphs; native deliberately preserves them.
Compact heads, quoted child-list variants and broader acceptance remain open.

Rules385 adds ordinary nonempty-item caret Return immediately before/after a
one-level inner-quoted divider. Focused and 275 non-AI/non-OCR checks pass;
installed saves and Undo/Redo retain expected ownership and complete file bytes.
Compact/deeper quotes, broader container behavior and full acceptance remain open.
Board384 also makes unchanged card-column menu choices a no-op. No new DMG.

Performance382 extends guarded row reuse to ordinary quoted list heads and
same-depth unowned blank quote rows. Exact native saves, Undo/Redo and composed
accents pass, along with behavior controls and the frozen 275 non-AI/non-OCR gate.
Matched keyboard-stack observations are lower for both verified quoted workloads.
Inherited inner-quote roles and contextual bodies retain fallback; overall
responsiveness and full parity remain open. No new DMG was made.

Performance381 extends guarded source-row reuse to ordinary nonempty nested list
heads with fixed space indentation. Native exact saves, Undo/Redo and Portuguese
composed input pass; the existing repeated-edit owner and frozen 275 non-AI/non-OCR
checks pass too. Matched sampled keyboard work is much lower for the verified
ASCII/Unicode workloads. Quotes, contextual bodies and unsupported boundaries
retain full fallback; overall responsiveness and full parity remain open.
No new DMG was made.

Performance380 replaces a growing Unicode export's NSString-based blank-tail
check with a UTF-8 scan of the final row. Equivalence controls, the frozen 275
non-AI/non-OCR checks and native exact save/Undo/Redo checks pass. Sampled Unicode
work is lower, while the ASCII control is slightly higher; this is not a general
latency claim. Full nested exports and broader responsiveness remain open.
No new DMG was made.

Migration379 verifies untouched legacy files through native startup/navigation,
programmatic invocation of the actual metadata owner, real CLI get/doctor and
installed native readback. Bodies, paths and foreign bytes are preserved through
reviewed preparation. The installed Settings entry point and companion startup
normalization remain open; see the acceptance ledger. No new build was made.

The fidelity378 internal build preserves original source boundaries after quoted
headings and fenced code. Editing either side no longer adds a redundant blank
line that survives Undo. Exact native save/Undo/Redo checks and the frozen 275
non-AI/non-OCR gate pass. No parser pass, version or DMG change was added.

The performance377 internal build keeps sparse export tracking through AppKit's
provisional marked-text edits. Final row/structure checks and full fallback remain
in place. Native acute/tilde input, exact save/Undo/Redo and nested composition
fallback pass; hosted composition controls and frozen 275 non-AI/non-OCR checks
pass. The matched CPU observations and limits are in the acceptance ledger.
Broader IME and overall responsiveness remain open. No new DMG was made.

The performance376 internal build extends fresh source mapping to nonempty
canonical top-level list heads using the existing reuse policy. Native exact
save/Undo/Redo and nested fallback checks pass, together with the frozen 275
non-AI/non-OCR checks. Contextual and marked-text costs, overall performance and
full parity remain open. No new DMG was made.

The performance375 internal build retains source-range mappings for eligible
root prose/headings in mixed notes, avoiding their first-edit full export. Exact
native save/Undo/Redo checks pass, and matched CPU observations are recorded in
the non-AI acceptance ledger. Contextual and unmapped edits retain full export;
this is not overall responsiveness acceptance. No new DMG was made.

The performance373 internal build uses viewport-driven inspector sections.
Optimized installed checks preserve first/last outline navigation, saved edits,
Undo, tab switches and the fully hideable folder sidebar on an owned long-note
fixture. Matched sampled CPU work fell for outline expansion; this is not an
input-to-display latency or overall responsiveness claim. Verification and
limitations are in the non-AI acceptance record. No new DMG was made.

The rules372 internal build retains selected dividers on Return and preserves
item/root roles and receiving formatting in the verified workflows. The original
production baseline, focused owner and frozen 275-check non-AI/non-OCR gate pass
as expected; optimized native keyboard selection, exact saves, Undo and restored
reopening checks pass. Inner-quote caret, compact/quote-role transitions and
root-EOF anchor comparison remain open, together with overall performance.

The rules371 internal build repairs caret Return before/after a divider in a
nonempty flat item, preserving nested/outer-quote ownership through the existing
item split transaction. Original-source baseline, focused editor and 275-check
non-AI/non-OCR gates pass as expected; installed exact save, Undo and reopening
checks pass. Selected-divider Return is extended in rules372; inner-quote caret and compact
Return remain open.

The rules370 internal build supports mapped list-owned horizontal rules, including
compact and quoted bodies, with checked editing, composition and clipboard
ownership. Four focused owners and 275 non-AI/non-OCR checks pass; installed
edit/format/accented-input/deletion/Undo checks preserve the owned fixture bytes.
Exact web Return-key parity remains open. No new DMG was made.

The excerpts367 internal build avoids rescanning shared immutable note buffers
when comparing excerpt requests, retaining exact-byte fallback. Installed checks
verify late reference labels, same-length outside edits and same-path cross-vault
excerpt isolation. Its 275 non-AI/non-OCR checks pass; six Vision-dependent gates
and overall responsiveness remain open. No new DMG was made.

Current internal source admits mapped item-owned headings/quotes and supported
quoted-list/card combinations, including compact heading heads. Checked tabbed
list prefixes and shared-line marker chains retain untouched source spelling;
mapped code/table combinations also stay rich. Mapped unquoted compact task
leaves display native checkboxes while preserving original source. Mapped
quoted compact tasks also stay rich: exact tree matches take priority over the
missing-checkbox adapter. Other unsupported task shapes remain Source. Shapes whose
native rows/cards cannot preserve parsed ownership remain Source. Compact empty-head
filling retains native word-level Undo when the complete proposed graph stays
unchanged. Gallery now shares one native alternate-click surface instead of mounting one
per card; controlled installed captures show reduced navigation CPU while full
performance acceptance remains open. Saved-version loading now notifies only the
inspector revisions section, avoiding recovery-only workspace publications.
The last passing combined non-AI gate reports 280 tests (navigation349); signed
native revision browsing, error recovery and exact edit/Undo checks pass.
Navigation350 reuses the existing exact-byte parsed metadata cache for collection
fields and values; native outside-edit freshness and sidebar checks pass.
Verification351 runs all 280 unchanged non-AI checks across four fresh processes
and verifies exact test identifiers with no omissions or duplicates. The
monolithic test-host Vision/E5 limitation remains documented. Navigation353 reuses folder schema definitions within each collection inventory, with an absent-schema fast path. Its final 280-test fresh-process gate passes, and the signed internal app adopts and releases an externally added schema field without changing original fixture bytes. Performance354 records complete fresh root source/native mappings during rendering, avoiding full cache initialization on the first eligible body edit. Its final 280-test non-AI gate and signed native save/Undo/Redo checks pass; scoped keyboard CPU samples support avoided work, while complex first edits and general displayed responsiveness remain open. Render355 shares raw-source parsing with card discovery, keeps separate normalized rendering when reference bytes differ, and skips impossible owned/code discovery for root prose while retaining raw table scanning. Its 280-test non-AI gate and signed fresh-editor open/edit/Undo checks pass; cold startup, theme/layout and broader loading acceptance remain open. Input306 verifies bounded current Release keyboard,
composition, table/code, Find and underline workflows. Drag330 verifies real
board card and column payloads with a follow-up target click, plus history and
reopening; drag-only automation and Settings automation remain open. Export352 verifies actual native PDF/Word/HTML save and cancellation workflows, PDF visual layout, Word package structure and HTML content, with original note/image bytes preserved. See the acceptance record above.

Earlier undo264 non-AI checks passed 271 tests; its native Release QA verified compact accent
input, outer-row expansion, empty-chain ownership and reopening. Filling a canonical
empty outer row now keeps whole-word native Undo/Redo after checking the complete
item graph. This is internal build125
evidence, not a new DMG or full parity claim. See the acceptance record above.

Tasks now share a filtered/sorted result per Mac view update, and the shared task
query prepares timestamps outside its comparator. Performance273 passes 272
non-AI Mac tests, five iOS task-planning tests and 144 baseline ordering/filter
comparisons. Signed Release task search, sorting, list totals and Complete/Reopen
are verified on an owned 120-task fixture; shared iOS behavior has a simulator
preview. These are bounded task-path improvements, not general responsiveness
acceptance. No version or DMG changed.

PDF previews now retain Find, page and unlocked-document state when switching
between expanded document and notes layouts. PDF275 passes the 272-test non-AI
gate and signed native checks with ordinary/encrypted two-page documents. The
source PDFs and notes stay unchanged; explicit reload still starts fresh reader
state. The experimental hosted test harness was removed, so regression evidence
is the actual native before/after workflow, not a new XCTest. See the acceptance
record for limits.

Anchored calendars and collection filters now leave popover window sizing to
AppKit while retaining interface zoom. The current popover272 non-AI gate passes
272 tests; signed Release QA verifies task calendar selection and nested date
filtering. This supersedes task270's unresolved calendar presentation result.
The CLI settings screen still closes the Computer Use helper's native pipe after
a fresh permissions retry. Broader performance and workflow acceptance remains
open; see the acceptance record.

## Native sidebar preference (2026-11-18)

Keep the ability to hide the entire left folder sidebar in the SwiftUI app.
The user explicitly prefers this native behavior even though the React/Tauri
client does not offer it. The toolbar's “Show or hide folders” control remains
available when the sidebar is hidden so it can be restored. At narrow widths
the same control opens the Library drawer. This is an intentional native design
choice to preserve during parity work, not a requirement to change React/Tauri.

Preview 125 test-build notes: **0.3.85 build 125**, an ad-hoc, non-notarized arm64
DMG for macOS 26+. Typing after item indentation now undoes independently. Heading copy/Cut retains complete block roles and mixed selections keep their selected descendants; complete heading-containing exports also provide semantic HTML. Typed block-looking prefixes retain their literal inner-block text.

Preview122 also retains partial-heading Cut consistency and text-only structured
paste repairs in the guarded rich core. Pasted paragraph/list bodies retain the
receiving item-owned heading/quote and its existing children, including explicit
bold text. CLI setup uses a lighter shared device/inode identity check that
avoids extended-attribute reads. These changes passed 260 scoped desktop tests;
all 13 AI/chat test classes remain deferred. The earlier AI-inclusive attempt
was interrupted and is not counted as a clean full-suite pass.

Preview123 begins the responsiveness work requested after Preview122. Filtered
collections are reused until their inputs change, and Mac note reads reuse a
bounded parsed-metadata cache keyed by exact UTF-8 bytes. Unchanged inventory
refreshes avoid replacing published arrays; canonical-equivalent byte changes
still refresh correctly. The final scoped desktop gate passes 262 tests,
excluding thirteen deferred AI/chat classes. Release measurements and broader
real-vault acceptance must be read from the separate performance handoff record.
Quoted-paragraph paste also joins text inside guarded item-owned headings/quotes
while retaining explicit inline breaks and bold formatting. Public Source
admission remains unchanged.

Preview124 moves table/code discovery out of the per-keystroke toolbar update.
The native popup builds current table/code choices from one parsed document
when opened, and refuses a stale source selection. Filtered
collections are reused until their inputs change, and Mac note reads reuse a
bounded parsed-metadata cache keyed by exact UTF-8 bytes. Unchanged inventory
refreshes avoid replacing published arrays; canonical-equivalent byte changes
still refresh correctly. The final scoped desktop gate passes 263 tests,
excluding thirteen deferred AI/chat classes. Release measurements and broader
real-vault acceptance must be read from the separate performance handoff record.
Quoted-paragraph paste also joins text inside guarded item-owned headings/quotes
while retaining explicit inline breaks and bold formatting. Public Source
admission remains unchanged.

Preview122 repairs workspace content obscured by the title/toolbar in Preview121.
A divider keeps the scaled workspace inside the native usable content area,
including the folder menu, collection header, editor tabs and inspector.
The final native window regression covers 80%, 100% and 150% canvas zoom; the
scoped desktop gate passes 261 tests with thirteen AI/chat classes excluded.
Pre-package native QA on a separate Debug copy verified note panes, full sidebar
hide/restore, Tasks, External Notes, narrower and zoomed windows, and quit/reopen
without changing either synthetic note. This is bounded layout evidence,
not full desktop or installed clipboard/IME acceptance.

The guarded inner-block core now preserves item ownership through block formatting, compound quote commands, empty quotes and Return. Public list-owned heading/quote admission remains in Source while other interactions are completed.

Quote Backspace now merges text into a preceding text block while retaining later quoted paragraphs, headings, lists and cards. Empty prose/heading predecessors are removed; empty bullet/numbered items receive the text. Caret inline style and prior Undo history are retained.

Final-body Cut preserves the editing role, original source ending, clipboard selection and Undo/Redo. Leading nonempty quote Backspace removes one nearest wrapper while preserving child blocks, and reopening restores caret typing style. Other quote boundaries and public list-container rich admission remain pending.

Empty-block Backspace is one Undo step, works at document start,
and preserves the remaining quote paragraphs. Deleting the final body with the
keyboard retains its
editing role without adding a source newline. The guarded inner-container core
also preserves heading/quote roles during Backspace wrapper removal and merges;
caret-only boundary navigation adds no Undo edit. Item-owned headings/quotes still
open in Source until the other structural and clipboard commands are verified.

Empty final headings, quotes and explicit blank paragraphs now
retain an editable native row without adding a source newline. Cmd-End, refill,
source/reopen and Undo/Redo are covered by hosted editor tests. The guarded rich
core also preserves item-owned heading/quote roles through Return and selected
Return, but those shapes still open in editable Source until the remaining
structural and clipboard commands are verified. AI work is unchanged and deferred;
full desktop parity and installed/IME acceptance remain pending.

Retained agent runs can review/import bounded existing web journals
from the selected owned conversation, including active history, frozen images,
plans, questions, cumulative usage, proposals and individual receipts. Import
sends no provider request and applies no note proposal. Original parent/worker
sources stay unchanged and receive exact archive copies. Imported proposals
require explicit review; existing partial receipts are retained. Continuation is
one-way into a Mac-only format that older clients refuse. Oversized active
history now uses durable, budgeted context summaries across Stop/Resume, with
exact message archives, call/result grouping and retained image pixels. Summary
requests reserve an estimated final-response allowance and require fresh reads
before later edits. Provider thinking remains device-private. Large proposals and
receipts and oversized active messages now use exact, hash-verified payload files
committed with the manifest, with a 128 MB expanded-journal bound and Mac-only
formats 5/6. Indexed imports use format 7 and a source-status transaction: deleted
runs cannot resume if their journals reappear, and a reviewed re-import receives
fresh run/input identities while older archives stay unchanged. Wider legacy
identity/scope/lifecycle acceptance and installed handoff
remain pending; this is not complete web-run or desktop parity.

Owned conversations now expire after 30 days in Trash during idle history refresh,
with shared tombstones and associated web/native journal removal in a recoverable
transaction. Unsent drafts, active work and unsupported data defer cleanup.
Private agent inputs and retained archives/payloads stay intact.
Connected document previews now show their resolved path and size, offer Finder
reveal, and refresh on app activation while retaining unchanged preview identity.

Valid colour edits, presets and named-palette loads now apply
immediately, matching the desktop colour-preview workflow. Partial hex input
stays intact while typing and resets on blur. Separate palette slots, current
peer preferences and future colour roles are preserved. Progressive note lists,
warm startup and the entirely hideable folders sidebar remain included.

This preview also includes the measured card-restyling filter for ordinary
input and reuse of completed list-card admission serialization. Root-paragraph
export reuse, Continue Writing below non-final cards and structured-paste spacing
repairs remain. Cold displayed-editor load, broader incremental export and
installed input/IME acceptance are still open. The folders sidebar remains fully
hideable with its restore control available. Release-host probes and offscreen
fixtures are not installed UI acceptance.

Supported list-owned fenced/indented code and tables retain native rich editing,
including inline-first, nested, quoted and mixed-card shapes. Admission checks
the original parser's item-parent/card-owner tree against native context
identities and model contents, plus exact untouched source reuse. Unsupported
item containers, HTML and unresolved ownership retain editable Source. Table and
code sheets retain their surrounding-ownership checks. Partial tables retain the
grid; portable image literals in code and checked partial-card paste remain.
Composed input keeps provisional text out of autosave. The Undo repair touches
the shared Apple engine; iOS compilation is checked without advancing its build.
Simulator visual verification remains pending after the earlier canceled Device
panel session. The matching packaging receipt records artifact verification and
checksums; installed UI acceptance is recorded separately.

It retains empty HTML wrappers/leaves, checked list/quote block paste, rich editing
for paragraphs after child lists, receiving-role inline paste and whole-row
boundaries, descendant-preserving list commands, item-aware Return, numbered
checklists, checked Backspace/deletion/Cut, independent paragraph export, heading
fidelity and plain/native/HTML multiline inline paste. The folders sidebar remains
fully hideable with its restore control available. Per-vault new-note folders,
numeric date inputs/calendars, CLI/skill setup and PDF password unlocking remain.

Unsupported containers still use editable Source mode. Native/source separator
spacing reconciliation and mixed selection formatting of quote-owned cards remains part of the broader
container-command acceptance work.
Larger arbitrary ranges, installed HTML
clipboard/cross-client acceptance, ordinal/display reconciliation, incremental
serialization and installed keyboard/IME acceptance remain pending. Full desktop
parity remains the acceptance criterion. Packaging checksums and status are
recorded in the matching artifact receipt and handoff notes below.

## Installation and requirements

- Apple Silicon Mac running macOS 26 or newer.
- Drag **Zerus Native.app** to Applications from the DMG.
- It uses `com.zerus.notes.macos.native`, separate from the installed production
  app. It does not replace that app or change its preferences.
- Choose a **copy of your vault for migration testing**. The app writes ordinary
  Markdown and shared `.zerus/` metadata; there is no conversion/import step.
- The app remembers recent folders with security-scoped bookmarks on this Mac
  and restores per-vault tabs, filters, folder expansion and inspector state.
  Sandboxed distribution and cross-machine session portability remain pending.
- A device-local snapshot in `~/Library/Caches/Zerus Native/Startup/` can restore
  notes, files, folders, schema, view settings and tasks while a fresh inventory
  runs. It stores complete UTF-8 note contents, including BOMs and line endings;
  it never enables editing from a list snippet. It is disposable and bounded to
  128 MiB of note data / 192 MiB encoded data. Unknown root identity, replacement
  directories, corrupt data and oversize vaults use a cold scan. Transaction
  recovery still runs before activation. An unavailable root cannot be opened
  from its former path alone. The banner identifies cached state until refresh
  succeeds; errors keep drafts and cached contents available with Retry.
- Editing saves automatically after a short pause; Command-S saves explicitly.
  Failed saves retain a private recovery draft in
  `~/Library/Application Support/Zerus Native/Drafts/`.
- Native rich text currently handles basic headings, emphasis, links, lists,
  checkboxes, marked nested lists/quotes, quoted headings, multiline quoted
  paragraphs, editable fenced/top-level indented code, native table cells and local inline images.
  Paragraphs after child lists retain their owning item in native rich editing.
  Supported list-owned and quote-owned code/tables stay native after original-tree
  admission checks. Other unsupported containers and HTML use editable Markdown
  source.
  This fallback preserves content; it does **not** complete rich-editor parity.

## Development and packaging

The target includes the existing platform-independent vault sources directly
from `native-ios/Sources/`. No iOS source is copied or modified by the build.
Small Mac adapters currently duplicate portable types embedded in iOS UI files;
these should move into a shared Apple package as the migration progresses.
Native build/test commands also use Rust/Cargo to stage the existing desktop CLI
and shared skill into Resources/CLI. For a direct XcodeGen/Xcode invocation, run
`node scripts/native-macos-cli.mjs stage` first; generated CLI assets are ignored
by Git. The SwiftUI app remains the native interface; the CLI is a separate helper.

```sh
pnpm macos:native:build
pnpm macos:native:test
pnpm macos:native:dmg
```

`macos:native:dmg` builds Release, signs with the configured Zerus Developer
ID, packages the DMG, submits it to Apple, requires Accepted notarization, staples
the ticket and checks Gatekeeper. It uses the existing `APPLE_API_ISSUER`,
`APPLE_API_KEY`, `APPLE_API_KEY_PATH` configuration (or the documented Apple ID
alternative). `pnpm macos:native:dmg --local` builds an ad-hoc local DMG without notarization.
Use this route for intermediate testing; reserve notarization for substantial
milestones. The native version/build come from `native-macos/project.yml`.
Packaging does not increment them automatically or change iOS versions.

Artifacts live under `artifacts/native-macos/`. The native target configuration
is checked against the packaged app before creating a DMG: bundle identity,
version/build, executable name, macOS platform, minimum macOS version, arm64
architecture and signing channel must match. Successful packaging writes
`artifact-<build>-local.json` (or the non-local equivalent) with the actual
executable and DMG SHA-256 values. A local receipt says notarization was not
submitted; installed UI verification is explicitly separate. A stale receipt is
removed before replacing a DMG.

The native target configuration
is `native-macos/project.yml`, generated with XcodeGen. Native updates use the
Sparkle channel in `native-macos/update-channel.json`, not the Tauri updater feed.

## Navigation storage and historical performance verification

The internal app restores archived inactive per-vault navigation only when a
current preference is absent. Tabs, pins, collection state and inspector state
were verified through installed recovery; bookmarks and vault bytes remain
unchanged. See [the offline archive procedure](native-macos-navigation-archive.md).
This does not change the packaged Preview125 or create a new DMG.

Startup248 uses directory stat metadata for startup identity instead of the
full Foundation attribute lookup, avoiding unnecessary extended-attribute reads.
Three existing startup/navigation owners pass. Signed Debug QA verifies inactive
pinned-tab moves and Back navigation with unchanged note bytes. The owned
Documents fixture opens through the normal picker and restores after relaunch;
the earlier environment-only launch lacked the picker folder grant. This is
functional evidence, not Release timing or full acceptance. See
`artifacts/native-macos/startup248/verification.json`. No new DMG/version bump.

The performance254/256/navigation257 internal app added lazy immutable note-part
caching, bounded local heading export, and explicit List scroll-to-top on scope
changes. Its non-AI gate passed 270 tests; the current gate is recorded above. Installed
large-note heading typing, exact Save and single Undo pass on signed Release,
with bounded CPU captures retained in `artifacts/native-macos/performance258/`.
These captures do not establish input latency or complete responsiveness/parity.
The CLI tools sheet still triggers a Computer Use helper crash; main-window QA
works after restarting only the QA app. No new DMG or version bump was made.

Performance246 retains per-inventory cached sidebar folder counts, including
all ordinary-note descendants under the same prefix rules. The actual API
matches 56 controls and invalidates on inventory mutation. Three navigation and
folder owners pass; installed create/outside-move checks update the displayed
counts correctly. Folder-switch CPU captures still show substantial layout
work and are not input-latency evidence. The latest app receipt and evidence are
`artifacts/native-macos/performance246/app-receipt.json` and
`artifacts/native-macos/performance246/verification.json`.

Navigation247 repaired inactive tabs following unique external note moves,
including source-path reuse and atomic swaps, with draft/conflict/ambiguity guards.
Its current workspace owner covers pins, Back/Forward and reopen behavior.
Startup248 additionally verifies a moved pinned inactive tab while another note
stays active, then opens the moved note and returns with Back; original note bytes
are retained. Its signed Release app also restores those tabs. See
`artifacts/native-macos/startup248/verification.json`; broader navigation and
provider acceptance remain separate.

A test build hit disk exhaustion, then passed on identical frozen source after
verified storage recovery. Historical internal QA app snapshots are now in
lossless ZIP archives with per-file hashes and restoration instructions in
`artifacts/native-macos/archived-qa-apps/README.md`; a representative restored app
passes byte/mode comparison and strict nested signing checks. Current apps,
DMGs, result bundles and OS model caches remain intact. No new DMG/version bump
or permanent Vision repair is claimed.

Performance245 retains a macOS-only preview optimization: source without a
literal `[[` opener bypasses the source-link inventory, while full preview and
search text remain unchanged. The non-Mac selected implementation matches the
baseline exactly. Ninety-six differential cases and the existing search owner
pass; two installed candidate captures save the same bytes as the baseline and
single Undo restores all original bytes. CPU samples show less preview work,
with cache warmth and key-pacing caveats; they do not establish input latency.
Its historical installed receipt and evidence are in
`artifacts/native-macos/performance245/app-receipt.json` and
`artifacts/native-macos/performance245/verification.json`. No DMG/version bump
was made. Final combined acceptance remains open.

Performance243 retains an equivalent macOS-only literal CRLF scan in the
frontmatter parser. Forty-five differential cases match, all 13 focused owners
pass, and installed large-note saves match the baseline with byte-exact Undo.
The non-macOS implementation is unchanged. CPU profiles show less repeated
frontmatter work on the owned large note, but differing key pacing and cache
warmth preclude general latency claims. Its historical installed receipt is
`artifacts/native-macos/performance243/frontmatter-app-receipt.json`.

The historical performance243 combined scoped non-AI gate ran 269 tests with five unexpected errors preceded
by Vision/E5 diagnostics. It is not a passing final gate. No assertions or
exclusions were weakened. External-note/move fixture cleanup was subsequently repaired in fixture244.
Five remaining owners pass, and the earlier move suite passes; the image-paste
attempt was interrupted in XCTest warning symbolication and is not a pass.
Preference comparison found no external-fixture leaks, and the entire original
preference domain was restored. See
`artifacts/native-macos/fixture244/verification.json`.

Performance242 rejected and reverted two List-pagination experiments. Its
installed profiles identify layout and row-update work for further optimization.
Regenerable build caches were removed after critically low disk space was found;
test evidence and release artifacts were preserved. See
`artifacts/native-macos/performance243/verification.json` for current evidence
and limits. Broader performance, IME, accessibility, cross-client and final
delivery acceptance remain open. No new DMG or version bump was made.

## Current work priority

The user has deferred AI chat/agent work for a later review and accepted the
performance work. Continue concrete non-AI feature gaps, installed workflow
acceptance, cross-client compatibility and release readiness. Keep the wholly
hideable folders sidebar and exclusive special-collection/note presentation.
Use internal QA applications; make another DMG only when needed for verification
or the final handoff. Existing AI implementations stay in the app; their open
acceptance items below remain recorded rather than counted as completed.

## Native update channel (development)

The SwiftUI Mac app uses pinned Sparkle 2.10.1, independently of the Tauri
JSON update feed and its key. The app menu exposes **Check for Updates…**.
An internal build with no native feed/key reports that updates are unavailable;
it does not report that the app is up to date.

Build configuration accepts `ZERUS_NATIVE_UPDATE_FEED_URL` (an HTTPS XML
appcast URL) and `ZERUS_NATIVE_UPDATE_PUBLIC_KEY` (the canonical base64 encoding
of the native channel's 32-byte Ed25519 public key). Supply both or neither for
internal builds. Non-local DMG packaging defaults to the approved public
`native-macos/update-channel.json` when neither variable is set. An explicit
partial override is refused rather than mixed with that profile. Inspect the
resolved production settings with `pnpm macos:native:channel`; it performs no
build, resource staging, signing or upload. Do not
reuse the Tauri feed or substitute `latest.json`. The validated bundled feed is
returned by the updater delegate, so a defaults-based feed override is not used.
Private signing keys do not belong in these variables or in the repository.

The app requires signed appcasts and archive verification before extraction;
automatic installation is disabled. The packager signs Sparkle's Autoupdate,
Updater.app and both XPC helpers before the framework, CLI and parent app.
Artifact verification checks the pinned framework version and each helper's
signature/channel/team. Features485 accepts a private configured Developer ID
candidate, including Apple notarization, the bundled CLI and Sparkle helpers,
ticket validation, Gatekeeper assessment and a controlled launch. Production
update download/install/relaunch and final delivery remain pending.

The approved production feed is
`https://github.com/noxtherox/Zerus/releases/download/native-macos/native-macos.xml`,
with native ZIPs under the same `native-macos` release asset directory. Its
separate signing account is `zerus-native`; only the public key is in the
profile. This channel/tag has not been published. Internal Preview125 builds
remain unconfigured. Keychain signing capability is verified after the user's
OS authorization. Hosting and Developer ID/notarized update delivery,
and broader multiwindow/provider interruption must be verified before accepting
production updates. The repeatable signed ZIP/appcast preparation and verification
commands below are implemented and exercised with disposable local QA keys. Updates314 verified signed HTTPS download/install/
relaunch and tampered-feed/archive rejection. Updates315 verified that open note
dialogs and failed-save/outside-edit conflicts cancel updater quit, and that a
resolved draft is saved before update relaunch. Both used disposable local QA
keys and the internal app; neither establishes Developer ID/notarized production
acceptance. An older native build without
Sparkle needs one manual installation of an updater-enabled build. The Tauri
macOS app cannot update into Sparkle on its own; install the first native DMG
manually. It replaces `Zerus.app` in Applications under the same identity.


### Preparing native update artifacts

`pnpm macos:native:appcast` prepares or verifies a single native release. It does
not build an app/DMG, advance a version, generate a signing key, change the input
app, or upload anything. The app must already contain its approved native
`SUFeedURL` and `SUPublicEDKey`; environment values do not override a built app.
The approved separate Keychain signing account is `zerus-native`. To inspect
its **public** key without creating/replacing it:

```sh
artifacts/native-macos/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account zerus-native -p
```

The private signing key must match the public key used when building the app.
Keep it in Keychain; do not use the Tauri key or place private key material in the
vault/repository. CI may instead pass `--key-file /protected/native-key.txt` for
an owner-only private seed file. Account and file options are mutually exclusive;
verification never needs either.

After `pnpm macos:native:dmg` has produced the configured, Developer ID
signed and notarized app, use the approved native GitHub download directory.
The commands below prepare and verify local files only:

```sh
pnpm macos:native:appcast prepare \
  --app artifacts/native-macos/dmg-staging/Zerus.app \
  --output artifacts/native-macos/native-update-release \
  --download-prefix 'https://github.com/noxtherox/Zerus/releases/download/native-macos/' \
  --account zerus-native

pnpm macos:native:appcast verify \
  --app artifacts/native-macos/dmg-staging/Zerus.app \
  --output artifacts/native-macos/native-update-release \
  --download-prefix 'https://github.com/noxtherox/Zerus/releases/download/native-macos/'
```

Preparation requires a **new output directory** under an existing parent and an
HTTPS directory URL ending in `/`, without credentials, query or fragment. It
copies and verifies the app, fetches/staples and validates its notarization
ticket, checks Gatekeeper, and uses the pinned Sparkle generator to create a ZIP
and signed XML feed. The XML filename comes from the bundled feed URL. Deltas
and release-history pruning are disabled for this one-release output.

Verification checks the feed's embedded Ed25519 signature and exact UTF-8 signed
length, version/build/minimum macOS/arm64 metadata, enclosure URL and byte length,
and archive signature against the app's bundled public key. It extracts only
after signature verification, checks bundle paths and all existing native
artifact/signature rules, and matches the archived executable and sealed resource
manifest to the verified input app. Production verification also requires the
archived app's valid stapled ticket and Gatekeeper assessment. Bounds are 4 MiB
for the single-release feed and 512 MiB for its ZIP.

Success produces only the ZIP, XML and `native-update-receipt.json`, with hashes,
verified app identity/signatures, channel coordinates and `published: false`.
Failed preparation never produces an accepted receipt and never overwrites an
existing output/feed. Publish the ZIP at its recorded enclosure URL and the exact
signed XML at the app's bundled feed URL only after the release is approved;
editing XML afterward invalidates its signature. Hosting/publication and actual
production download/install/relaunch remain separate acceptance steps.

`--local` accepts configured **ad-hoc QA** apps and labels the receipt `local-qa`;
it skips notarization and cannot serve as production delivery evidence. Local
acceptance uses disposable keys outside the repository and removes their private
material afterward. The installed QA app is unchanged.

Run `node --test scripts/native-macos-appcast.test.mjs` for signed-feed protocol
checks. Full command acceptance with pinned Sparkle, independently signed
alternate-app refusal, tamper/channel/key/mode checks and final public-only
verification is recorded in `artifacts/native-macos/features459/`.

## Zoomed split-pane input (acceptance347)

Non-AI native split panes now keep their AppKit boundary unscaled and zoom their
contents within each pane. This repairs missed pointer focus in collection,
Tasks and External Notes search at non-default interface zoom. All offered zoom
choices have hosted pointer/typing coverage; installed 150% search, nested saved-link
notes, Undo and exposed pane resizing controls also pass. Saved zoom and fixture
bytes are restored. The 280-test non-AI gate passes. Direct drag transport, broader
responsiveness and full interaction acceptance remain open. No new DMG was built.

## Feature parity acceptance tracker

“Native implementation” below means code exists, not that complete parity has
been established. This table is a historical feature inventory; its acceptance
clauses are superseded where the current [non-AI acceptance ledger](native-macos-non-ai-acceptance.md)
records later evidence. AI remains deferred and performance is accepted. Do not
treat an older generic range/paste, migration, or performance clause as a newly
missing feature without checking the current owner and installed evidence.

| Desktop workflow | Current native state | Remaining acceptance work |
| --- | --- | --- |
| Approved light design | SwiftUI folders/list/editor/inspector, system symbols; fully hideable folder sidebar; compact notes/list navigation, drawers and 600-point minimum width; Library dismisses on expansion while preserving current hide/show state (compact364 installed check) | Broader compact/physical-minimum-width acceptance, Settings native-pipe blocker, zoom selection, visual/accessibility acceptance and pane resizing polish |
| Local vault browsing | Coordinated file actor/parsers; complete device-local warm snapshots with background reconciliation and retry; timed and activation refresh; filename-first fresh recovery matching avoids URL construction for unrelated private drafts during note activation (performance399); clean external rename following, retained-text export and private note-recovery browser | Large-vault/cache cost and provider startup acceptance, sandboxed bookmark acceptance |
| Basic rich text | Native horizontal rules in root prose and quotes; AppKit text system; Underline toolbar/⌘U with balanced inline-format import and portable export; original paragraph tokens; typed heading/list/checklist and inline shortcuts; list continuation; clickable checkboxes; inline traits retained on block changes; marked nested lists/quotes, subtree indentation and quote headings; multiline quoted paragraphs with nested depth, lazy continuations, cross-line styles and hard breaks | Other unsupported containers, uncommon list-card prefix/selection cases, mixed quote-card formatting, complex shortcut cases, complete paste/style fidelity, IME/dictation, extensive fixtures and accessibility acceptance |
| Tables and fenced code | Fenced code edits inline with basic language-aware colours, fence preservation, native Undo/Redo and exit-to-prose; native table cells support typing, multiline text, Tab navigation and row creation; table/code sheets preserve Undo; features415 accepts installed mixed list-owned sheet/inline edits, cell Tab/ShiftTab/new row/multiline input, code Return/exit and Rich reopen with independent GFM structure | Compact/quoted rule-card Return cases (rules397 repairs the empty quoted child), larger/adversarial selection/layout, physical IME/VoiceOver and provider-failure acceptance |
| Images and attachments | Import files, local image display; HTML/RTFD and PNG/TIFF clipboard images with portable assets; native image size/address/alt/title editing, expand and occurrence removal with undo; safe sized HTML and legacy width rendering; reviewed manager removal and Trash restore | Complete copy/cut/provider and lifecycle acceptance, external-image full-size/provider and multiwindow acceptance |
| Links | Stable-ID links render and navigate; cursor picker with undo/redo; typed `@`/`[[` suggestions and explicit creation; missing bare-title creation dialog; local/stable/relative heading navigation and clickable outline; read-only hover/context-menu previews | Nested/multiline style fidelity, complete keyboard/IME/VoiceOver, large-vault, preview lifecycle and multiwindow acceptance |
| Properties | Native typed forms, inherited schemas, reviewed definition create/edit/rename/removal, literal choice rows and paired visibility controls; properties401/402 accept installed typed validation/saves and reviewed definition create/type change/rename/removal, child overrides, Cancel/stale protection and reopen/CLI readback | Provider/unavailable-files, large-vault and broader keyboard/accessibility acceptance remain cross-cutting gates; relation repair is separate |
| Relations/backlinks | Shared mutation engine, backlinks and paired-relation picker; reviewed legacy repair with note diffs and unresolved cases; relations403 verifies installed paired add/remove, atomic stale refusal, unresolved retention, definition rename/inverse hiding and restart persistence | Installed repair screen remains behind Settings tooling failure; paired bulk Undo/later edits, provider and broader input/accessibility acceptance remain |
| List and filtering | Progressively extended regular note list; search, sort/date/archive controls; typed property/date-range and all/any filters; shared folder-filter persistence; named saved views; subtype controls and per-vault restoration; features411 accepts named Table view recall across navigation/mode changes and restart | Files-hub/alternate-view large inventories, complete cross-workflow/keyboard/accessibility acceptance and large-vault/provider acceptance remain |
| Gallery/Kanban/Table/Calendar | Typed table cells; property grouping; relation-aware/collapsible Gallery groups, viewport-driven progressive card loading with complete search/selection, and image covers shared by Gallery/Kanban; Kanban typed/scoped card and column drops with reviewed property moves and saved order (board72 after Preview 65); installed two-card menu review/Cancel, durable Undo/Redo and stale-review refresh preserving later edits, column controls and reload (board398); property calendar and Undated; shared layout fields in views.json; features411 accepts installed Gallery covers/group collapse/property visibility, Calendar date edit/clear/Undated/crowded-day/month controls, typed Table values and restart | Provider acceptance, real Kanban pointer routing/keyboard/accessibility, compact column layout and broader collection input/accessibility |
| Bulk changes | Typed bulk properties and paired relations with reviewed undo/redo; reviewed bulk note moves with numbered collisions, skipped/failed results, resource/link rebasing and tab/history remapping; durable reviewed move Undo/Redo; features414 accepts collision-safe moves, exact Cancel/resource rebasing, stale refusal, Undo/Redo preserving later unrelated edits/additions and restart with current-graph validation | Overlapping edits to receipt-written files/shared settings, broader selection/input/accessibility and provider interruption |
| Navigation | Live accessible sidebar selection and selection-mode state; persistent note/folder/global tabs with device-local Pin/Unpin, path remapping and guarded inline/middle close; nearest-neighbour active-close selection; menu reorder, back/forward, guarded window close and New Window; installed core-navigation/reopen proof in navigation394; Find in Note menu/shortcut dispatch repaired and installed checked | Pointer tab reordering and horizontal-overflow scrolling delivery, broader keyboard/VoiceOver and cross-workflow acceptance |
| Tasks | Shared JSON engine; list/category administration; All/Today/Completed planning, sorting and filters; native date controls; supporting-note picker; private durable drafts with recovery/export/discard/reload/copy; directory-bound Mac draft recovery through ordinary vault-folder moves with replacement-copy isolation (tasks363); failed saves retain open forms | Keyboard workflows, already-moved path-only/cross-volume/provider draft recovery, and full cross-client acceptance |
| Trash | Note/revision/folder trash browser, reviewed folder recovery and purge controls; features408 accepts note/revision Trash and restoration; features409 accepts folder resource/empty-directory/settings restoration, occupied-destination refusal and preservation of later unrelated settings | Actual permanent-deletion/purge Apply, provider/interrupted operations and broader accessibility acceptance |
| Revisions/history | Shared engines; independent revision/history reads; browser, parent line diff and restore comparison; frozen resource previews; Keep/labels; per-vault retention and reviewed cleanup with Mac draft protection | Permanent-deletion UI acceptance, installed image paging/provider/large-history/accessibility acceptance |
| Files/external notes | Saved original-file connections, rich/full-source editing, recovery/export, outside-edit protection and chosen-project image preview/copy/paste; reviewed portable copies/moves into vault folders and pending-move recovery; file hubs with copy/original/backup, previews, resolved path/size, Finder reveal, activation refresh, replacement, locating and detachment; shared location administration and private local-folder mappings; features409 accepts create/rename/map/disconnect/reconnect, per-file Locate/folder fallback and restart persistence; Locate now immediately refreshes the visible document | Files-based iOS/macOS interoperability, complete import/move/provider acceptance, resource editing, multiwindow/window-close/provider interruption and full acceptance |
| PDF/HTML | PDFKit navigation/zoom and secure password unlocking; NFKD/whitespace search with original-text highlights and cancellable page work (pdf362), including installed encrypted-preview navigation/relocking; HTML Only link/Safe/Full modes, content-bound origin approval, isolated WebKit rendering and native downloads; features413 accepts installed 30-page search/navigation/Unicode highlights and encrypted relock, HTML modes/download Cancel/Save/status, restart and changed-file renewal | Very large/complex documents, broader keyboard/accessibility/provider failure, live-origin/interrupted downloads and office Quick Look |
| Saved links | Shared creation/update engine; URL editing; opt-in live pages with split resizing, expansion and URL-bound remembered mode; features410 accepts installed URL Cancel/invalid/duplicate refusal, change with protected annotations/identity/bytes, approval reset and both page modes across restart | Large inventories, cross-client/provider and broader keyboard/accessibility acceptance |
| Exports | Shared HTML/DOCX serializer; Mac PDF/print path; current-draft export snapshot with PDF/Word/HTML choices, visible-properties policy, progress and warning feedback; resource-aware paginated native printing with pre-print warnings; bounded source-image decoding with retained labels and size warnings | Broader pagination/image/table, print, provider and accessibility acceptance; export352 verifies current native save/cancel/options, PDF visual layout, Word package structure and HTML content on representative generated files |
| Global search | Ranked/typo-tolerant notes, tasks, saved links, shared AI conversations, PDF/text file contents and external Markdown; excerpts, collection/date/archive/folder/property/task filters; recent results; selected-result preview and keyboard selection; Ask/context handoff; PDF/text/image file context; features412 accepts installed five-source results/opening, filter combinations, content preview, paging, keyboard selection, missing-local-external recovery and recent-history restart/clear | Live provider interruption/reconnect, broader filter/physical input/accessibility and multiwindow acceptance; AI context deferred |
| AI chat | Shared append-only vault conversations, global search and direct opening, compatible HTTPS text/vision APIs, native Anthropic Messages, ChatGPT account/model controls and shared Responses transport; shared provider profiles, favorites and cancellable model discovery, Stop/Retry, note snapshots, image and PDF/text pickers, clipboard images/files and dropped batches, document context selection and text preview/export, saved image previews, private unsent-attachment recovery, ownership transfer, rename/archive/Trash/restore, owner-only 30-day Trash expiry, private prompt/reply recovery, reply export/save as note and Keychain key | Live ChatGPT authorization/plan acceptance, other provider-specific flows, provider/drag lifecycle acceptance and full workflow acceptance; large-history/retention acceptance remains; separate private unused-attachment cleanup would be an extension |
| AI agents | Native provider adapters and conversation/run bridge; frozen limits, guidance, workflows and defaults; scoped native/text calls; eighteen tool classes delivered in Preview 64, including organization with review/Undo and bounded independent analysis; peer/draft/receipt guards; reviewed one-way web-run imports and durable budgeted active-history compaction | Large payload/catalog cost and provider interruption, wider legacy/scope/lifecycle migration acceptance, other-device takeover, complete scope/settings/provider workflows and installed/IME/live-provider acceptance remain |
| Dictation | Native text system available; the existing desktop chat has no dedicated recording flow (its speech plugin reports iOS-only) | Real macOS system dictation/IME acceptance; a dedicated chat microphone would be new scope |
| Settings/appearance | Light/dark/system; persistent note-link shortcut and code-block creation controls; live seven-role colour pickers/hex fields with partial-input handling, separate light/dark palettes, 11 built-in presets and locally saved/updateable named palettes; development writing-width/column-alignment controls, shared properties-pane ordering/collapse/reset and whole-interface zoom | Complete theme/editor/pane and CLI setup workflow acceptance; installed UI and multiwindow/system-switch acceptance |
| CLI and external agent setup | Development CLI 0.3.1/skill 4 resources; native reviewed install/reinstall, per-entry status and skill export; reviewed vault registration and metadata preparation; desktop-compatible Codex/Claude/Hermes paths | Legacy out-of-file pin/archive migration, installed UI and helper notarization acceptance |
| Packaging | Separate native app and signed/notarized DMG pipeline; development native Sparkle update menu, channel validation and nested signing | Developer ID/helper notarization, production native feed/key, download/install/relaunch and save-conflict acceptance; older builds need a manual updater-enabled installation |
| Apple cross-client compatibility | Existing web/CLI format-owner checks remain reference evidence; compatibility395 passes two-way shared-format writes plus installed native readback for notes, typed properties/relations, tasks, views, history/revisions and frozen images | User scope is iOS and macOS only. Live Apple-client/provider transport, Files location mappings, saved links and companion/private-preference migration remain; Windows and a separate web UI are not acceptance or delivery gates; no web BOM/header-byte preservation claim |

## Verification evidence

Focused native tests cover unedited rich-text Markdown preservation, a localized
paragraph edit, formatting persistence, foreign YAML preservation, and rejecting
an outside edit through the real file actor. These tests do not establish full
editor compatibility or desktop feature parity. Test output and UI evidence are
retained in `artifacts/native-macos/`.

## First delivered test build — 16 November 2026

`Zerus-Native-0.3.34-preview-arm64.dmg` is Developer ID signed, Apple notarized
(Accepted), stapled and Gatekeeper accepted. The app extracted from the DMG also
passed Gatekeeper and was launched successfully from an isolated install-check
folder. The exact DMG SHA-256 is
`97dd1a1917ba882639f1596612b2aed0e67906c7f5eccd81104e2fb7db013893`.

Four focused native tests passed. Manual checks on an owned disposable vault
covered the light layout, editing/saving a checklist line while preserving the
rest of the file, heading syntax, Command-B formatting, folder relation schema
creation, reviewing and saving paired links to two notes, and launching the
packaged release app. These are milestone checks, not full feature-parity signoff.
Evidence is in `artifacts/native-macos/delivery.json`, `test.log`,
`notarization.json`, `release.log`, and `native-preview.png`.

## Intermediate build 2 — 16 November 2026

This batch uses a non-notarized local DMG. It adds persistent typed collection
tabs, per-vault filters and folder expansion, reviewed folder rename/delete/restore,
bulk typed properties and reciprocal relations, and reviewed organization undo/redo.
Reviewed plans carry a workspace activation identity so reopening the same folder
cannot accidentally authorize an old plan.

Twelve Mac tests passed, including real-file folder recovery, session restoration,
Trash visibility, stale-plan rejection and relation undo/redo. Five focused shared
iOS tests passed. A two-note relation batch was applied and undone in the iOS
Simulator; the original reciprocal links were confirmed in both Markdown files.
New bulk receipts record transaction-boundary values; legacy receipts retain the
conservative guard against overwriting later edits. Regression baselines reproduced
the prior Trash and reciprocal-relation failures before the fixes.

Evidence: `test-build2.log`, `ios-shared-tests.log`,
`ios-bulk-undo-verified.png`, `trash-regression-baseline.log`, and
`bulk-regression-baseline.log` under `artifacts/native-macos/`.
These checks do not establish full desktop parity.

## Intermediate build 3 — collection layouts

Folder layouts now read and update `.zerus/views.json` using the existing desktop
mode names, visible property names, grouping/date field and lowercase column-order
keys. Other folders, filter payloads and unknown fields are preserved. Imported
shared filters are not yet applied by the native collection filter controls; that
mapping and named saved views remain open acceptance work. Global collection
layout choices remain device-local.

Table cells open typed property controls without navigating away from the
collection. An editor carries its note snapshot and workspace identity, rejecting
outside changes. Relations use their paired editor. Kanban single-note changes
use the shared organization history; multi-note drops receive a review. Calendar
uses local calendar dates, month navigation, Undated and day detail sheets.

Fifteen Mac tests pass, covering imported layout restoration and unknown-field
preservation, table edits and stale-file rejection, typed board/date writes with
undo, and the earlier migration checks. A failing baseline demonstrated the
collection-tab restoration regression before its repair. Evidence is in
`collections-tests.log` and `collections-restore-baseline.log`. Manual table
editing and an initial single-note Kanban drag/drop were verified in a disposable
vault; repeated drag/drop checks were inconsistent and remain pending. The visible
card menu provides column moves with a review for selected notes. screenshots
are `collection-table.png` and `collection-kanban.png`. Calendar drag-and-drop
was evaluated and excluded from this build; the existing desktop calendar does
not provide it. Dates are edited through typed controls.

Calendar month navigation, day details and changing a note’s Due date from
December 15 to December 16 were verified in the native UI and Markdown file.
Evidence: `collection-calendar.png` and `collection-calendar-date-edit.png`.

The visible Kanban card menu was used to move two selected notes to Planned,
review both paths and apply. Both Markdown files contain `Status: "Planned"`.
`collection-kanban-review.png` and `collection-kanban-final.png` record this check.
The ad-hoc build 3 DMG passed checksum verification; its extracted app passed
signature verification and launched successfully. See `delivery-build3.json`.

## Intermediate build 4 — shared filters and named views

Folder filters now import and update the current desktop’s wire format: typed
string/number/boolean accepted values, legacy single-value keys, date comparisons
and ranges, all/any matching, sorting, modified-date range and archive inclusion.
Global collection filters remain device-local. Folder/extension restrictions are
not part of the portable folder-view format. Incomplete filter inputs remain local
until completed. Queued filter writes retain their original owner when navigating.

The Views menu reads `.zerus/saved-views.json` and saves/applies named presets.
Saving an existing name preserves its ID. Management supports rename and reviewed
delete; operations reject a record changed by another client. Applying a preset
updates the active view without touching notes. Unknown configuration and record
metadata is retained, including metadata added to a preset since its last use.

Seventeen Mac tests and 26 existing web filter/view tests pass. A failing baseline
reproduced loss of newly added preset-only metadata before its repair. Native UI
checks covered applying a desktop preset (two planned notes in Table), saving a
new preset, rename, delete confirmation/application, and resetting imported filters
back to all five folder notes. Test vaults are disposable copies under artifacts.
Evidence: `saved-views-tests.log`, `web-view-contract-tests.log`,
`preset-metadata-baseline.log`, `saved-view-applied.png`, `saved-view-manager.png`.

This batch remains an ad-hoc, non-notarized test build; full desktop parity and
reliable Kanban dragging are still pending.

The actual native-created preset and active filter reset were accepted unchanged
by the current desktop TypeScript normalizers (`native-web-view-roundtrip.log`).
The exact build 4 DMG passed checksum verification; its extracted app passed
signature verification, launched, and applied the Planned table preset to show
the expected two notes. See `delivery-build4.json` and `native-preview-build4.png`.

## Intermediate build 5 — task management

The Tasks workspace now exposes the shared list/category engine, including default
list rename, list create/rename/delete and category add/remove. Removal reviews
capture affected task IDs so an outside assignment invalidates an old review.
Removing a list returns its tasks to the default list; removing a category clears
that field. Task bodies, linked notes and foreign JSON fields are preserved.

All/Today/Completed views, sort, category/priority/search filters, older completed
tasks and completion/reopening use the existing task query and date rules. Today
uses the scheduled day rather than the deadline. Native date controls edit the
schedule and optional deadline independently. The supporting-note picker searches
notes and filters folders, preserves unresolved tokens until explicitly unlinked,
and opens a linked note after a successful task save.

Task forms carry a workspace activation identity. Task changes are queued and
metadata refresh cannot replace a newer task result. A failed save keeps the form
and draft values open. Durable task draft recovery and full task acceptance remain
in scope. Eighteen Mac tests and nine existing web task tests pass; Mac integration
checks cover queued edits, collection changes, note-link serialization, foreign
record preservation and rejection of stale task/list forms after reopening a vault.
Evidence: `task-management-tests.log`, `web-task-contract-tests.log`, `tasks-today.png`.

Native UI checks also covered conflict handling (outside title retained, draft
left open), list/category creation and assignment, linking a note and opening it
after save, reviewed removal returning the task to General, category clearing,
and completion/reopening. Existing unresolved links survived every action.
Evidence: `task-draft-conflict.png`, `task-collections-created.png`,
`task-note-picker.png`, `task-supporting-note-open.png`,
`task-list-removal-review.png`.

The desktop task parser accepted the actual native-written JSON, including all
three supporting links. Reviewed list/category removal and completion/reopening
retained foreign envelope/list/task metadata. All eight ordinary Markdown files
remain byte-identical to the copied source vault. See
`native-web-task-roundtrip.log`.

The ad-hoc build 5 DMG passed checksum verification. Its extracted app passed
signature verification, launched, and restored the task workspace with saved
supporting-note links. See `delivery-build5.json` and `native-preview-build5.png`.
No new notarization was submitted.


## Intermediate build 6 — saved links and PDFs

Saved-link notes now have Edit URL, Copy URL, Open in browser and an optional live
page above their annotations. The native split resizes vertically and supports
page expansion. The preview opt-in stays on this Mac, scoped to the vault, link
identity and exact saved address. Editing the address disables automatic loading
of the new page. Live pages use a nonpersistent WebKit data store; navigation is
limited to HTTP(S), and media capture is denied. A loading failure exposes an
Open in browser fallback. HTML file previews remain separate.

The URL form first saves the note, captures its current content and vault
activation, and uses the shared transactional URL update engine. A changed note
or stale vault activation blocks the form; errors leave its entered URL open.
The shared engine retains annotations, foreign frontmatter and link identity.

PDF previews now offer asynchronous PDFKit text search, match counts, previous/
next match, optional case matching, page entry/navigation and zoom/Fit. A text
layer is required; OCR is not included. Password-protected PDF handling and
normalization edge cases remain in the acceptance tracker. File preview no
longer loads a second full copy of PDFs/images into its text-editor state.

Twenty Mac tests pass, including URL changes through the Mac editor lifecycle and
real-PDF search replacement, case matching, match navigation across pages and
invalid page entry. Native UI checks verified the live page/notes split,
expansion, URL changes resetting opt-in, and three PDF matches across two pages.
Evidence: `links-pdf-tests.log`, `saved-link-split.png`, `pdf-search-page-two.png`.
This is an intermediate ad-hoc build; no notarization is requested.


## Intermediate build 7 — native editor input

The rich editor now recognizes typed headings, bullets, numbered lists and
checklists. Return continues a list (increments numbers and resets checked items
to unchecked); Return on an empty item exits the list. Heading Return starts an
ordinary paragraph. Inline bold, italic, combined emphasis, code and Markdown
links convert as their closing syntax is typed. Parsing uses UTF-8 source positions
mapped to native text ranges, including Unicode. Complex nested shortcut sequences
and multiline formatting still need acceptance work.

Paragraph formatting now displays list/checkbox markers and retains inline bold,
italic, code and links while converting between headings, lists and paragraphs.
Checkbox glyphs can be clicked; Edit > Toggle Checklist Item provides a menu action
for the current item. Original tokens remain on untouched paragraphs. Actual HTML
continues to use source fallback; CommonMark autolinks no longer force source mode.
Tables, fenced code and other previously documented structures still use source.

Undo snapshots now copy the attributed content rather than retaining the text
view's live storage. Each editor owns its undo manager, and loading another
source or mode clears the prior history. Teardown removes retained undo actions.
These boundaries prevent an older editor state from being replayed into a newly
loaded document. Typed transforms avoid marked text; IME/dictation acceptance is
still pending.

Twenty-six Mac tests cover the prior contracts plus real NSTextView input,
continuation/exit, visible markers, formatting retention, typed shortcuts,
Unicode, checkbox toggling, undo/redo and document-load undo isolation. The new
regressions fail against the earlier implementation; removing the load-history
reset also fails the lifecycle regression. Evidence: `editor7-regression-baseline.log`,
`editor7-undo-lifecycle-baseline.log`, and `editor7-final-tests.log`.

Native UI checks typed bold, created and continued a checklist, exited to a plain
paragraph, clicked a checkbox and used Command-Z/Shift-Command-Z to undo/redo it.
Unicode paste and saving preserved Café and 日本語; a saved-link note opened in rich
text. Evidence: `editor-native-input.png` and the QA editor vault. This remains an
intermediate local build, without a new notarization submission.

The serializer now separates a newly edited plain paragraph from a preceding
list/quote, so CommonMark does not absorb it as a lazy continuation. Imported
unchanged paragraphs keep their original tokens. Edited literal heading/list
markers remain escaped. The list-exit test parses the result as CommonMark and
requires a separate paragraph block, rather than checking only the native view.
The pre-fix failures are retained in `editor7-list-exit-baseline.log` and
`editor7-literal-marker-baseline.log`. Rich editor identity also includes the
vault activation so the same filename in another vault cannot reuse its view.

Commands now observe the focused scene's workspace object, so their enabled state
updates after asynchronous vault loading and note selection. The packaged app's
Edit > Toggle Checklist Item changed the intended item; native undo/redo and Save
then worked. The extracted build 7 app passed signature and launch checks. The
desktop frontmatter parser and remark/GFM accepted its actual written note as a
heading, Unicode/bold paragraph, two checklist items and a separate paragraph;
all eight earlier ordinary notes remain byte-identical. Nine existing web Markdown
tests also pass. Evidence: `native-web-editor-roundtrip.log`,
`editor7-web-markdown-tests.log`, `native-preview-build7.png`, `delivery-build7.json`.


## Intermediate build 8 — connected originals and document notes

External Notes now registers explicitly selected Markdown originals in this Mac’s
Application Support, reopens saved connections, locates moved files, creates new
Markdown files and stops tracking without deleting the original. The native editor
supports rich text and full-file source (including frontmatter). Command-S targets
the external session while it is open. Local recovery drafts precede original-file
writes; original bytes and file identity are checked by the shared coordinated
storage service. UTF-8 BOM and frontmatter line endings are retained, and no Zerus
ID or vault sidecar is inserted into an external original. Editing is limited to
UTF-8 Markdown below 10 MB.

Outside edits block saving and retain the draft. The connection list can show and
export recovery text independently of the original. Reload requires a discard
review, reads the original first and persists a clean checkpoint before replacing
the visible draft. Done and application quit checkpoint the current session.
File-provider interruption, abrupt window-close behavior and multiwindow recovery
conflicts still require full acceptance; this preview does not claim those cases
complete. Exported drafts can always be connected as separate Markdown files.

Document notes now use the shared `zerus-file-*` metadata and frozen attachment
records. Add a document to Files or link one to an existing note; choose a portable
vault copy, an original connection or an original plus frozen backup. Copies and
backups have a 50 MB limit. Notes can live in ordinary folders and remain visible
in Files; filed saved links likewise remain visible in Links. Original connections
and folder mappings are private to this Mac. Missing files can be located without
rewriting the shared binding.

Documents preview above their editable annotations in a native resizable split,
with expansion, replacement and reviewed detachment. PDF previews retain their
search/page/zoom controls; images and HTML use native adapters, and other document
types use Quick Look. Office-format visual acceptance remains pending. Backup
links open the frozen vault attachment. Detaching keeps annotations, original
files, existing copies and backups. Folder-mapping administration and the external
note import/move UI remain in scope.

Thirty-one Mac tests pass, including original-file save/restart, BOM/CRLF/header
preservation, queued edits, outside-change/recovery handling, unavailable-original
reload protection, copy/original/backup storage, frozen byte preservation,
detachment, duplicate binding checks and stale vault review rejection. Regression
checks for filed Links/Files collections and source-mode heading/paragraph commands
fail against the earlier behavior. Evidence: `files8-regression-baseline.log` and
`files8-final-tests.log`.

Native UI checks connected and edited an original, blocked an outside conflict,
reopened its draft, exported recovery text while the original was unavailable,
and reviewed reload. Document checks created a vault copy in Ideas, edited its
annotations, replaced the binding with original plus backup, opened the backup
from the note and detached while retaining the note and files. Evidence:
`external-conflict-draft.png`, `external-unavailable-recovery.png`,
`file-hub-pdf-notes.png` and `QA Connections Vault`. No new notarization is submitted.

Cross-client verification exposed an older desktop flow-list parser that split
quoted JSON attachment records on their internal commas. The desktop reader now
handles quoted commas/escapes and preserves unsupported nested structures. The
shared Apple writer emits block lists when an item contains commas, preserving
comments on a separate line. This makes newly written structured records readable
by the existing desktop reader as well. Reader regressions fail before the fix;
63 focused web tests pass after it. The shared property save/preservation test also
passes on iOS Simulator, with the canonical iOS build number unchanged (57).

The final build 8 DMG and extracted app pass checksum/signature checks and launch.
The extracted app relinked an existing detached note and wrote a fresh backup with
the compatible block-list format. Both current and unmodified older desktop
readers accepted the resulting two backup records. All nine pre-existing ordinary
Markdown notes remain byte-identical. The shared iOS change was built, installed
and exercised in the visible Simulator; editing a comma-containing list value
retained its comment, foreign YAML and body. Its saved bytes are also accepted by
the older desktop reader. The iOS version/build record was not advanced and no
archive/export/upload was run. Evidence: `connections8-codec-final-mac-tests.log`,
`connections8-compatibility-tests.log`, `native-web-connections-roundtrip.log`,
`shared-codec-ios-final-test.log`, `shared-codec-ios-preview.png`,
`native-preview-build8.png`, `delivery-build8.json`.


## Intermediate build 9 — shared file locations

Files > Locations now adds and renames shared location names while preserving
foreign JSON fields and records. Each Mac chooses its own local folder, scoped
to its vault identity. New original connections within a mapped folder store a
location ID and relative path. Remapping or disconnecting changes device-private
bookmarks; it does not rewrite shared notes, definitions or original files.
Existing device-only connections retain their binding; replace their document
to adopt a newly configured location. Native Google Drive mapping controls remain
pending; this screen chooses folders available through Finder.

Connected notes, including Trash, prevent removal of their location. An explicitly
located individual file keeps precedence over a folder mapping until Document
actions > Use folder mapping again is chosen. Open previews refresh after mapping
changes. Reviews are bound to the originating vault and stale location names are
rejected. Copied vaults do not inherit private access from their source.

Thirty-three native tests pass. Added boundary checks cover mapping/override
precedence, disconnecting, shared-byte preservation, foreign JSON preservation,
Trash references, stale reviews and copied-vault isolation. Manual native checks
created a location, mapped Alpha, connected its PDF, remapped to Beta and observed
the open preview change to the Beta document. Shared note and definition bytes
remained exact during remapping. Renaming retained the ID, relative path and
private mapping; removal is visibly disabled while used. Desktop parsers accept
the native-written location and note metadata. Evidence: `locations9-tests.log`,
`native-locations-build9.png`, `native-web-locations-roundtrip.log`. This remains
an ad-hoc intermediate DMG; full feature parity and provider acceptance are pending.


## Intermediate build 10 — task draft recovery

Unfinished task changes now use the existing Apple draft store and session engine.
The Tasks header opens a private Drafts list. Closing an editor keeps changes
without saving them into `.zerus/tasks.json`; reopening the app recovers new tasks
and edits. Recovery preserves scheduling, priority, list/category, completion and
supporting-note values. Draft files live under this Mac’s Application Support
`NativeTaskDrafts/` and are associated with the selected vault root. Mac saved-vault
identity across folder moves remains pending; copied roots have separate drafts.

Task editors expose JSON export and reviewed discard, reload and save-as-new.
Conflicting outside edits leave the shared task and local draft intact. Reload
reads the latest task before discarding the draft. Copy intent is recorded before
the shared write so recovery can recognize an already saved copy. Concurrent draft
changes are retained separately rather than overwritten. Unreadable draft files
remain available through Reveal in Finder. Deletion clears the editor’s draft and
closing afterward does not recreate it. Draft-access errors warn before closing.

Thirty-four native tests pass. A workspace-level lifecycle check exercises actual
private files across workspace reconstruction, shared-byte isolation, conflict
protection, saving a separate task and deletion cleanup. Native UI checks typed
and closed an unfinished task, restarted the app, recovered its title and high
priority, saved it and observed an empty Drafts list. A second unfinished task was
explicitly discarded without adding a shared task. The shared file remained byte
exact before Save; desktop parsers accept the recovered task after Save. Evidence:
`taskdraft10-tests.log`, `taskdraft10-recovered.png`,
`native-web-taskdraft-roundtrip.log`. This is an intermediate, non-notarized build.


## Intermediate build 11 — cross-workspace search

Command-F now searches notes, saved links, tasks, vault filenames and explicitly
connected external Markdown with the existing Apple ranking/filter engine.
Search folds case and accents, tolerates longer-word typos, indexes full note
source and metadata, and shows readable excerpts. Local note drafts are indexed
without saving. Archive inclusion is explicit and Trash is excluded.

The native sheet exposes collection, modification date, folder, property/value,
task status and priority filters, progressive result loading, and device-private
per-root recent results with Clear. Notes reopen by unambiguous stable ID after
renames. Stale vault results and ambiguous IDs are rejected. Task results open
the existing task editor, filenames open leased native previews, and connected
Markdown opens its original editor. External loading is bounded to four concurrent
reads with the shared provider timeout; local results remain usable while it runs.
Unavailable originals retain searchable recovery drafts and show access warnings.

This does not yet include AI conversations, Ask/context actions, binary document
text extraction or complete large-vault/provider acceptance. Saved vault identity
across folder moves remains part of the broader Mac migration. Search creates no
shared index and does not alter the indexed originals.

Thirty-six native tests pass. New Mac boundary checks cover ranked/accent/typo
matches, all five connected collections, metadata/task filters, unsaved note
indexing without writes, unavailable-original drafts, stable-ID rename navigation,
ambiguous/stale result rejection and unindexed file paths. Native UI checks found
five collections with one query, opened a task, a text file, an external original,
a saved link and a regular note, and verified archive opt-in and typo tolerance.
Evidence: `search11-tests.log`, `native-search-build11.png`, `QA Search Vault`.
This remains an intermediate, non-notarized DMG; full desktop parity is pending.


## Intermediate build 12 — portable native paste

The Mac text view now routes paste through Markdown conversion and coordinated
resource import. It accepts the shared Zerus clipboard fragment, HTML, RTF, RTFD,
PNG/TIFF images and plain text. HTML uses the existing Apple parser, including
embedded images and companion RTFD attachments. Images become ordinary vault
assets with portable Markdown references. HTML images may load from their copied
addresses; scripts, frames and stylesheets are not executed. The existing parser
limits HTML to 10 MB and total imported content/resources to 50 MB.

Paste and Match Style keeps text literal. Source mode prefers plain clipboard
text. Supported rich blocks and inline formatting appear natively; pasted tables,
code and unsupported structures switch to editable source. A paste is one undo
operation, including transitions between rich and source modes. Imported assets
remain after Undo so Redo can restore their references. Normal image maintenance
acceptance remains pending; Undo does not silently delete resource files.

External notes retain their header when paste or Undo/Redo changes editor modes.
Image imports into external originals require a project-attachment destination
and currently report that limitation while leaving the original unchanged.
Unsupported/missing resource data is likewise rejected rather than saving an
attachment placeholder. Preparing paste disables text editing, shows progress
and supports Esc cancellation. Note/selection changes reject a stale insertion.

Forty-one native tests pass. Clipboard boundary checks exercise actual HTML and
RTFD data, private pasteboard transport, PNG transport, companion attachments,
byte-preserving assets, literal text, image failure without a vault, one-step
Undo/Redo and external-header preservation across source fallback. Full RTF
paragraph-style fidelity, copy/cut resource packaging, provider-interruption and
large clipboard acceptance remain pending. Evidence: `paste12-final-tests.log`.

Native UI verification pasted an HTML heading, bold/italic prose, link, list and
embedded repo-owned PNG into a vault note. One Undo removed the entire insertion;
Redo restored it and its image. Saved source retains the note’s foreign YAML and
untouched Markdown spelling. The external-note UI pasted a table, changed to full
source, undid back to rich text, then redid and saved. Undo restored the original
file byte-for-byte, including UTF-8 BOM and CRLF YAML; Redo kept that header while
saving the table. Evidence: `native-paste-build12.png`,
`paste12-external-source.png`, `native-web-paste-roundtrip.log`.


## Intermediate build 13 — resource-aware copy and cut

Native Copy/Cut now captures a Markdown selection with the shared Zerus fragment
format, vault-relative resource identities and embedded file bytes. Pasting within
the same vault reuses an unchanged resource; another vault receives independent
assets. Standard RTF/RTFD representations carry text formatting and image
attachments for other native apps, with Zerus-only attributes removed. Plain text
and Markdown representations remain available. Mid-paragraph selections do not
copy a surrounding heading/list block token.

Cut removes text only after all selected resource bytes are available and the
clipboard write succeeds. Missing attachments, note/selection changes, newer
copy requests and intervening clipboard changes reject the operation without
cutting. A cut is one undo operation; source files stay available for Undo and
other notes. External-note local resources still need the planned project-file
connection path; selecting ordinary text remains supported. Clipboard preparation
uses the existing progress and Esc cancellation UI.

Repeated cross-vault copy/paste exposed unbounded generated filename growth.
New imports remove repeated generated UUID prefixes and bound the decomposed
Unicode filename while preserving its extension. The regression fails with an
actual filesystem filename-too-long error before the fix and passes afterward.
Ten alternating vault copies retain the original image bytes and Markdown label.

Forty-five native tests pass. AppKit clipboard boundary checks cover cut/image
Undo, independent target-vault assets, PNG/raster validity in standard RTFD,
missing-resource rejection with an unchanged clipboard, and inline selection
formatting. Tests restore the system clipboard without logging its contents.
Evidence: `copy13-final-tests.log`, `copy13-name-regression-baseline.log`,
`copy13-rtfd-format-check.log`. Full provider and large-selection acceptance
remain pending; this is another non-notarized intermediate build.

Native UI verification copied a complete formatted note and image, selected an
independent vault through the folder picker, and pasted into a note with its own
YAML identity. The destination receives a separate asset with exact source image
bytes. The source note remains byte-identical. Cut then Undo restores the complete
destination note, including its image reference and original target header.
Evidence: `native-copy-build13.png`, `native-web-copy-roundtrip.log`.


## Intermediate build 14 — reviewed image removal and recovery

Attachments > Manage images lists Markdown image occurrences in the current note.
Each offers a scoped native preview and a removal review naming affected notes
and local files. Removal changes only that occurrence. The existing Apple engine
checks saved notes, revisions, history, hidden Markdown and recovery metadata
before collecting a local file. Shared, managed, linked, remote or unavailable
files stay in place. Eligible unused files move to Recently Deleted.

The manager and Recently Deleted > Images preview and restore image files, with
optional reattachment to the original stable-ID note. Permanent-deletion reviews
require an explicit acknowledgement and revalidate retained references. Permanent
delete was not exercised in the native UI for this milestone. Full purge/provider
acceptance remains pending. The last removal has a reviewed Undo in the current
window, retained when closing/reopening the manager; it resets on vault switching
or app restart. Undo rejects later note/image changes instead of overwriting them.

Reviews carry their originating workspace identity. The Mac adapter saves the
current draft before preparing an inventory and blocks dirty or stale reviews.
Successful changes refresh the note editor and metadata. Other-window private
drafts, interrupted providers and broader lifecycle acceptance remain in scope.

Forty-seven native tests pass, including draft flush before review, shared
occurrence protection, editor reconciliation after Undo, recoverable file moves,
restore with reattachment, outside-change rejection and stale-vault rejection.
Native UI checks removed an unused image to Recently Deleted, previewed and
restored it, removed one shared occurrence while retaining its other note and
exact file bytes, then closed/reopened the manager and reviewed Undo. Undo restored
the note exactly to its pre-removal bytes. Image action accessibility labels now
identify their occurrence. Evidence: `images14-tests.log`,
`image14-removal-review.png`, `image14-shared-review.png`,
`native-web-images-roundtrip.log`. This remains an intermediate, non-notarized DMG.


## Intermediate build 15 — reviewed bulk note moves

Select multiple notes and choose Actions > Move to folder… to choose an existing
folder, the vault root, or a new nested path. The review lists source/destination
paths, adds numbered filenames when a destination exists, and explains skipped
notes, including missing resources and retained recovery drafts. No file moves
until confirmation. Each move uses the shared coordinated relation/resource
engine; earlier successes remain saved if a later move is blocked. Results list
moved, skipped and blocked notes, with skipped/blocked selections retained.
Bulk-move Undo was not implemented in build 15; preview 52 adds reviewed Undo.

Accepted moves preserve stable IDs, paired relations, foreign frontmatter,
relative images, incoming Markdown/wiki links, and creation dates for both moved
notes and notes rewritten to update links. Tabs and back/forward history remap
to the destination. Native link navigation now resolves relative URLs from the
current note, including percent-escaped filenames. The single-note move path
also uses resource-aware planning and retains original creation dates.

Reviews reject changed note bytes, shared settings/link records, resource
bindings, new recovery drafts, and another vault activation. This is a sequence
of coordinated per-note moves, not an all-or-nothing batch. Full provider,
mid-batch interruption, large-vault and multiwindow acceptance remains pending.
Creation-date retention failures are reported separately after a successful move.

Fifty-one native tests pass. Four workspace-boundary tests cover linked moves,
resources, identities, foreign metadata, dates, tab/history navigation, numbered
collisions, skipped notes, outside changes, recovery drafts and stale reviews.
Pre-fix regressions demonstrate broken single-note resource paths/incoming
links, reset creation dates, and relative links that failed to navigate.
Manual checks moved two linked notes to an existing folder with a filename
collision, skipped a missing-image note, and displayed the moved image and
paired relation. Final packaged launch and relative-link checks are recorded in
the delivery manifest after verification.


## Intermediate build 16 — reviewed revisions and automatic history

The inspector opens a dedicated Revisions & history browser. It lists every
available active revision or automatic version, previews saved text read-only,
and supports Markdown with full properties. Revision creation, promotion and
moving a revision to Trash now prepare an explicit review rather than writing
immediately. Current and resulting notes appear side by side; confirming applies
the exact reviewed plan. Canceling leaves vault note/index/resource files alone.

Saved revision document and attachment buttons preview their independent files.
The review renders planned images directly from saved bytes before destination
files exist and can preview staged resources in disposable temporary copies.
Buttons distinguish files for the result from backups of the current revision.
Automatic-history restore uses its saved image blobs rather than the current
original image. It restores historical text and user properties while preserving
current Zerus identity/file metadata. Revision promotion keeps today's title and
other properties. These different semantics are explained before confirmation.

The Mac boundary flushes the active draft before loading recovery and rejects
retained recovery drafts, changed workspace activations and concurrent recovery,
image or move operations. The shared transaction rejects later note, revision
index and resource changes; rejected reviews remain open with their error.
Automatic history preserves the current text when enabled. History keep/label,
retention/cleanup settings and isolated access when one index is incomplete remain
pending; the browser currently loads both indices together. Full provider,
multiwindow, large-history and accessibility acceptance is also pending.

Fifty-four native tests pass. Three Mac boundary tests exercise read-only plan
preparation, staged file previews and image rendering, saved-file independence,
current-title and foreign-property preservation, outside index/resource/note
changes, old workspace activations and automatic image/history restoration.
Manual UI checks on a disposable vault canceled a new-revision review, confirmed
creation, changed the live original image and HTML, previewed the unchanged saved
HTML, reviewed promotion, rejected an intervening outside edit without changing
its bytes, refreshed and promoted, then reviewed and restored automatic history.
Evidence includes `recovery16-tests-final.log`, `recovery16-saved-file.png`,
`recovery16-review.png` and the QA Recovery Vault under `artifacts/native-macos/`.
This remains an intermediate, non-notarized test channel.


## Intermediate build 17 — history labels, retention and maintenance

Automatic versions can be labeled and marked Keep in the native browser. The
metadata write uses the shared records and rejects stale note/history snapshots.
A kept version remains protected from automatic pruning, along with its required
checkpoint lineage. The label and Keep state survive refresh and reopen.

History settings are available from the browser and the vault window’s Settings.
They show saved/kept/image counts, automatic capture, a 1–100 checkpoint limit or
Unlimited, reviewed unused-image cleanup, and reviewed clearing for the current
note or all notes. Retention changes show immediate removals before applying.
Deletion reviews name records, identify kept and unsupported records, list unused
blobs and protected-data warnings, and require a separate final confirmation.
Current notes, deliberate revisions and still-used resources remain protected.
Final permanent deletion was exercised by disposable-vault API tests, not by the
native UI in this milestone; UI checks canceled its final confirmation.

Mac note, connected-file and task drafts are included in the history engine’s
recovery-reference inventory under a macOS-only platform branch. This protects
image blobs during ordinary autosave pruning as well as explicit maintenance.
Changed private drafts invalidate a reviewed cleanup. The Mac review also names
the number of image files protected by those private drafts without exposing
draft contents or their private filesystem paths.

Fifty-six native tests pass. Added Mac boundary checks cover label/Keep writes,
kept lineage under a reduced limit, foreign settings preservation, disabled and
unlimited capture, read-only review preparation, private draft-only blob
protection, stale private drafts and stale workspace activations. An autosave
regression demonstrably deleted a draft-only blob before the shared-path fix;
the same workflow now retains it through nine saves at a one-checkpoint limit.
Evidence: `history17-auto-prune-regression-baseline.log`,
`history17-tests-shared-final.log`, `history17-labels.png`, and
`history17-retention-review.png` under `artifacts/native-macos/`.
Manual UI checks persisted a kept label, reviewed lower retention with zero kept
removals, saved Unlimited without deletion, inspected unused/all-history cleanup
and canceled final deletion. Full multiwindow/provider/large-history acceptance
and a parent/version line diff remain pending.

The shared service also built successfully for the existing iOS Simulator
identity/version 0.3.107/57. That binary was installed without removing vault
storage, launched through the Device panel, and left on Version history with its
11 versions visible. The iOS branch retains its existing draft-store behavior;
Mac-only directories are excluded. No build-number advance, archive or upload
was performed. Evidence: `history17-ios-build.log` and
`history17-ios-simulator.png`.


## Intermediate build 18 — parent comparisons and isolated recovery reads

The automatic-history browser compares each version with its actual parent.
It shows old/new line numbers, added/removed markers and colors, counts, and
changed spans within adjacent replacement lines. Internal Zerus properties are
hidden by default and can be shown. An initial version compares with an empty
note; a missing, ambiguous or incomplete parent is reported rather than compared
with an invented baseline.

Comparison work runs outside the main UI task and is canceled when inputs
change. Common prefixes/suffixes remain visible in large notes with localized
changes. A bounded line-matching table handles the changed region; a broad region
falls back to explicit removed/added blocks and says so. The diff is read-only
and preserves the underlying saved Markdown and resource files.

Revision and history reads now have independent snapshots and error messages.
A damaged revision index no longer hides automatic history or prevents a valid
history restore. A broken history configuration no longer hides readable
revision previews. Writes still honor the shared transaction and history-capture
guards; isolation does not bypass an unsupported capture configuration. Original
unsupported index/settings bytes are kept unchanged. The note itself must remain
unchanged while both channels load. The inspector exposes channel-specific errors.

Fifty-nine native tests pass. The damaged-index regression fails on the previous
loader, then verifies automatic restore while retaining the exact broken index
and revision preview while unsupported history settings remain untouched. New
comparison boundary tests cover empty notes, repeated/blank lines, Unicode
highlights, source reconstruction and line-number alignment, large localized and
broad changes, and cancellation without a partial result.
Manual UI checks displayed parent diffs while a revision error remained visible,
changed selected versions, restored automatic history with the damaged revision
index still present, and previewed a revision with unsupported history settings.
The owned QA metadata was then restored. Evidence includes
`recovery18-index-regression-baseline.log`, `recovery18-tests-final.log`,
`recovery18-parent-diff.png` and `recovery18-independent-preview.png` under
`artifacts/native-macos/`. This remains an intermediate non-notarized build;
full cross-workflow, provider, large-history and accessibility acceptance is pending.

The extracted app additionally showed the explicit missing-parent state and an
initial version compared with an empty note (11 added, zero removed). Its test
checkpoint metadata was restored afterward. The browser keeps its list at full
height when a preview is unavailable and automatically selects a version when
switching channels.

## Preview 19 — persistent native AI conversations

The native chat sheet now uses the existing `.zerus/chats/<id>/` descriptor and
append-only event contract. Conversations created by the desktop app are readable,
including source snapshots and interrupted replies. This Mac can explicitly take
ownership, rename, archive, move to recoverable Trash, and restore a conversation.
Unsupported, incomplete, linked or oversized records remain untouched and are
reported separately from healthy conversations. The native preview does not purge
chat Trash or apply automatic retention.

Compatible HTTPS chat-completions providers support incremental SSE text,
Unicode, separate reasoning storage, Stop and Retry. Retry updates the interrupted
assistant message within its existing turn. Timed checkpoints and the final save
retain partial replies. Stopping finishes its durable checkpoint outside the
canceled network task. Vault switching and application shutdown stop requests and
wait for persistence. If another device changes ownership during a reply, the
foreign events remain intact and device-private recovery retains the unsaved text.
Successive failed runs retain separate exportable recovery entries.

Each outgoing message explicitly selects up to eight notes, below 1 MB combined,
and stores their text snapshots with the question. Unsent prompts and failed
reply recovery stay under `~/Library/Application Support/Zerus Native/Drafts/Chat/`.
Connection settings keep the provider key in its endpoint-specific Keychain entry;
credentials are not stored in portable chat records. Redirects are rejected.
Replies can be copied or saved as Markdown notes. Existing file/image inputs are
preserved, and continuing those conversations is blocked until native attachment
support is available rather than silently dropping their inputs.

Sixty-six native tests pass. Storage tests exercise event folding, ownership,
stale snapshots, tombstones, unknown data preservation and shared message updates.
Transport and controller tests use synthetic URLProtocol responses without real
provider credentials or network charges; they verify Unicode streaming, request
context, durable stop/retry and private recovery after ownership conflicts. The
stop regression demonstrably fails before the cancellation fix. Manual native UI
checks covered desktop-created history, ownership transfer, rename, archive and
restore, context selection, unsent prompt recovery and saving a reply as a note.
The production desktop reader accepts the resulting native events; original
foreign events remain byte-for-byte unchanged. Evidence is in
`chats19-tests-final.log`, `chats19-cancel-regression-baseline.log`,
`chats19-web-roundtrip.log` and `native-chat-build19.png` under
`artifacts/native-macos/`.

This intermediate DMG is ad-hoc signed and not notarized. Live-provider acceptance,
provider-specific APIs and account login, attachments, tools/agents, conversation
search, large-vault performance and accessibility acceptance remain pending.
Full feature parity is still in progress.

## Preview 20 — global conversation search

Global search now includes saved shared AI conversation titles and user/assistant
message text. The AI conversations collection filter, date filter, excerpts,
ranked matching and recent-result tracking use the existing native search engine.
Archived conversations require Include archived; chats in Trash and tombstoned
chats are excluded. Unsupported history produces a warning while other searchable
collections remain available. Indexing does not claim ownership, run retention,
rewrite chat events, read provider credentials or contact a provider.

Opening a result loads the current shared transcript in the native chat sheet,
including its device-private unsent prompt. Foreign-owned conversations stay
read-only. The navigation boundary checks the workspace identity and revalidates
the selected conversation so stale results cannot open a newly trashed chat or
navigate into another vault. Closing chat returns to the search query. Browsing
saved chat no longer automatically presents connection settings when no model is
configured; Connection remains available for sending.

Sixty-seven native tests pass, including the search-to-conversation boundary:
active/archive/Trash filtering, damaged-history isolation, unchanged foreign event
bytes, read-only opening, and stale-vault/newly-trashed result rejection. Manual
native UI verification searched a question within a desktop-created conversation,
opened its complete transcript and recovered prompt, and returned to search.
Evidence is in `chat-search20-tests.log` and `native-chat-search20.png` under
`artifacts/native-macos/`. This local preview remains non-notarized. Ask/context
search actions, binary content extraction, large-vault performance, provider and
full feature-parity acceptance remain in progress.

## Preview 21 — native chat image attachments

The native chat picker now accepts up to four images per message. ImageIO applies
orientation, limits the longest edge to 1024 pixels, flattens transparency onto
white and creates a JPEG without copying the source metadata. Imported originals
remain unchanged. Prepared JPEGs are limited to 3 MB each; source files are limited
to 50 MB. Image-only messages use “Describe the attached images.” as their prompt.

Unsent selections are kept privately per conversation beside the chat draft, with
SHA-256 checks and immutable JPEG files published before their metadata. Closing
and reopening chat recovers the selected images. Removing a selection changes its
private references; unused private JPEG cleanup remains pending, so those local
cache files can remain after removal or sending. Sending commits the selected
images and question together through the existing vault transaction engine.
The portable metadata and `.zerus/chats/<id>/assets/<image-id>.jpg` layout match the
existing desktop format. Saved messages show image thumbnails with a larger native
preview. No image is sent merely by picking or previewing it.

Compatible chat-completions APIs receive user content as text and JPEG data-URL
parts. The configured model must support vision. Text-only requests retain their
previous format. The native request includes at most 16 MB of image bytes and has
a 24 MB encoded-body limit when images are present; text-only requests remain
limited to 2 MB. Retry reloads the saved portable JPEG instead of depending on the
original imported file. Missing, linked, malformed or out-of-conversation image
references fail before a provider request. Document inputs remain preserved and
blocked until native document support is connected.

Seventy native tests pass. New coverage verifies normalization, source retention,
JPEG metadata removal, transactional attachment storage, missing/linked/escaping
resource refusal, unsent-image recovery, image-only prompts, the actual multimodal
HTTP payload, durable Stop and Retry after the source image is removed. Synthetic
URLProtocol responses avoid live credentials and provider charges. The image draft
regression caught Foundation's unsupported atomic/withoutOverwriting option pair;
the final path publishes an immutable completed file without replacing a name.
An additional regression reproduced Stop being lost when preparation state was
published. Preparation now retains its original cancellation identity, and a
question committed during Stop reconciles its private prompt before cancellation
returns, preventing a duplicate unsent question on reopening. No provider request
starts after that cancellation. Evidence is in
`chat-images21-prepare-stop-baseline.log` and the final test log.
Manual native UI checks imported a QA screenshot, recovered its unsent selection,
opened an existing desktop image conversation and previewed its saved JPEG, then
transferred ownership and renamed it. The production desktop reader accepts those
native events and every original event and JPEG remains byte-for-byte unchanged.
Evidence is in `chat-images21-tests-final.log`,
`chat-images21-private-write-regression.log`, `chat-images21-web-roundtrip.log` and
`chat-images21-preview.png` under `artifacts/native-macos/`.

This remains a local, non-notarized preview. Live vision-provider acceptance,
image paste/drop, private unused-image cleanup, document attachments, provider
account login, agents/tools and full feature parity remain in progress.

## Preview 22 — native document attachments and context

Native chat now accepts PDF and text-based files, matching the existing shared
`documents: [{ name, text }]` message format. PDFKit extracts page text; UTF-8,
UTF-8 BOM and UTF-16 BOM inputs retain their decoded text. The originals are read
through coordinated, scoped access and remain unchanged. Binary/invalid/empty
inputs are refused. Locked PDFs require unlocking, and scanned PDFs need OCR
before attachment. Each input and extracted snapshot is limited to 50 MB; batches
use a 100 MB processing budget and the preview accepts up to 100 documents.

Unsent extracted snapshots persist privately with immutable UTF-8 files and
SHA-256 checks, alongside per-conversation prompt/image recovery. Closing chat or
removing the original file does not discard a prepared attachment. Sending stores
the full extracted text in the portable user message. Document-only messages get
a default summary prompt. Saved and unsent snapshots have native text previews
and full-text export. Previews show at most 80,000 characters and label longer
snapshots; exporting retains the complete text. Private unused attachment cleanup
remains pending, so local cache files can remain after sending or removal.

Provider requests include full document context when it fits; otherwise the
native selector ranks overlapping excerpts by the current question and labels
them as incomplete, untrusted reference material. It never claims exhaustive
coverage. The Connection sheet exposes the model context window (default 32,768;
4,096–2,000,000), with a conservative UTF-8 byte estimate and reserves for output,
images and framing. This is not the web tokenizer and does not guarantee identical
excerpts or exact token counts for every provider. If no excerpt fits, the request
is blocked with instructions to start a new chat or review capacity. Stop cancels
document context processing before a provider request starts. Existing text-only
and vision request limits still apply.

Portable records can now reach 256 MB to accommodate escaped document snapshots;
conversation event history has a 512 MB loading/writing limit. The existing
20,000-event limit remains. Larger or unsupported history is preserved and
reported. Extraction, shared message-input decoding and context selection run
off the UI thread. Full maximum-size, large-history, provider and memory-pressure
acceptance remains pending.

Seventy-three native tests pass. New owner-boundary coverage verifies UTF-8/UTF-16
and PDF extraction, source preservation, invalid/binary/empty/scanned and oversized
input refusal, a portable document beyond the old 4 MB record limit, relevant
late-document excerpts and full short-file context, no-room errors, private draft
recovery, document-only prompts, actual provider payloads and Stop/Retry after
removing the import source. Provider responses are synthetic; no live key or paid
API request was used. Manual native checks imported a two-page PDF, previewed and
exported both pages, reopened its unsent selection, displayed a desktop-written
snapshot and transferred/renamed that conversation. The production desktop reader
and document context builder accept the native events and complete extracted
snapshot; every original event and PDF byte is unchanged. Evidence is in
`chat-documents22-tests-final.log`, `chat-documents22-web-roundtrip.log`,
`chat-documents22-text-preview.png` and `native-chat-documents22.png` under
`artifacts/native-macos/`.

This remains a local, non-notarized preview. Account/provider login, agents/tools,
image/file paste/drop, private unused-attachment cleanup and full feature-parity
acceptance remain in progress.

## Preview 23 — native ChatGPT account connection

Connection now offers API key and ChatGPT account modes. The native account pane
provides system-browser sign-in, reconnect/add/select account, eligible model
discovery and selection, sign-out and cancellation. It reuses the existing Apple
`ChatGPTManager` and `ZerusChatGPTCore`, with a conditional AppKit presentation
anchor; the iOS UIKit anchor and default configuration remain intact. The account
flow follows OpenAI’s [open-source Sign in with ChatGPT reference](https://developers.openai.com/siwc/token-sharing-open-source/sign-in).
Actual browser authorization, consent, plan permissions and live model inference
still need acceptance on a real account; the UI and synthetic transport tests do
not establish that live sign-in is complete.

Mac account credentials use the separate Keychain service
`com.zerus.notes.macos.native.chatgpt`. Existing API-key preferences and portable
chat events retain their format. ChatGPT requests use the shared Responses
protocol, including note/document reference context and images, while private
continuations stay scoped to account/model/conversation. The Mac HTTP session is
ephemeral, has no cookie/cache storage and rejects redirects. Account tokens do
not enter vault events; question text, document snapshots and images do not enter
the credential record. A separate native account connection is required; this
preview does not migrate another app’s saved sign-in.

Each turn captures its selected account/model before saving its question and
revalidates them before the provider request. Active replies block account/model
changes. A regression reproduced a retired restored model being silently replaced
during catalog discovery. The corrected route discovers eligible models, publishes
any changed default for review, and refuses that turn before inference rather
than silently sending it to the replacement. The saved question and interrupted
reply remain available for an explicit retry. Stop/Retry use the same durable
conversation checkpoint and private recovery paths as compatible API requests.
Tool requests remain blocked until the native agent/tool workflow is connected.

Seventy-seven native tests and eleven shared protocol tests pass. Isolated Keychain
fixtures and intercepted HTTP responses verify Responses streaming, Stop/Retry,
image and document input, credential/content separation, model/account pinning,
refresh-token rotation, sign-out/revocation and expired-grant handling. Synthetic
credentials never reach the network and no live account or paid request was used.
The model-pinning regression fails on the previous route before the repair.
A packaged-build check also exposed a synchronous legacy Keychain read blocking
the main thread. Mac credential access now runs on a serial background worker;
passive status reads suppress authorization UI and time out without deleting or
resetting existing credentials. Opening settings no longer creates an empty
registration. That regression fails before the repair and passes afterward.
Connection saves capture their settings before awaiting Keychain and cancel
when dismissed; late credential reads cannot start an abandoned chat request.
Manual Mac UI checks verified both connection modes and refusal to save account
mode without connecting; the sign-in button was not used for a real account.
The shared change also builds and installs in the iOS Simulator, which remains
open on AI connection in the Device panel. Its canonical 0.3.107/build 57 record
was preserved; no archive, export or upload was triggered.

Evidence is in `chatgpt23-keychain-final-tests.log`, `chatgpt23-core-final-tests.log`,
`chatgpt23-passive-registration-baseline.log`, `chatgpt23-packaged-sample.txt`,
`chatgpt23-model-pinning-baseline.log`, `chatgpt23-ios-keychain-build.log`,
`chatgpt23-ios-simulator.png` and `native-chatgpt-build23.png` under
`artifacts/native-macos/`. This remains a local, non-notarized preview. Full parity,
live account/provider acceptance, other provider integrations, native tools/agents,
attachment paste/drop and unused private-attachment cleanup remain in progress.

## Preview 24 — chat clipboard and dropped attachments

The AppKit message composer accepts copied image pixels and Finder file paste;
the chat sheet accepts dropped image, PDF and text files. Ordinary text and web
addresses remain prompt text. Multiple representations of one clipboard image
produce one attachment, and file URLs take priority over redundant image data.
The picker, clipboard and drop paths share preparation, limits and durable
private selection storage. A mixed batch commits images and documents together;
failed preparation, invalid documents or a stale private draft cannot publish
only part of the selection. Importing never starts an AI request.

Image files use coordinated background reads; PDF/text retain their existing
extraction path. A batch remains limited to four images, 100 documents and a
100 MB source-processing budget, with the existing per-file and extracted-text
limits. Sources are read without modification. Cancellation on view departure,
provider timeouts and a workspace/conversation epoch check prevent late imports
from attaching to a different conversation. Cross-provider interruption and
physical drag acceptance still need broader testing.

AppKit initially treated a pasted image as an invisible text attachment and
disabled the Paste menu for an image-only clipboard. The composer now advertises
its supported paste types and routes AppKit selection reads into attachment
preparation. The regression fails on the initial implementation and passes after
the repair; the prompt remains unchanged while the image is attached separately.

Eighty native tests pass. Manual UI checks verified Finder mixed-file paste,
Preview image-pixel paste without replacing the prompt, multiline text, and
reopening unsent selections. Item-provider loading is covered by real Foundation
providers in the tests; physical dragging and provider interruption still need
broader acceptance. No provider inference or authentication was started.

Verification evidence lives under `artifacts/native-macos/`:
`chat-input24-tests-final.log`, `chat-input24-paste-baseline.log`,
`chat-input24-web-compat.log`, `local-build24-final.log`,
`native-chat-input24.png` and `delivery-build24.json`. Live provider inference,
full AI workflow parity and unused private attachment cleanup remain pending.
This is a local, non-notarized Apple Silicon preview.

## Preview 25 — search previews and Ask AI context

Search now selects results for an adjacent preview. Up/down chooses a result,
Return or the Open action opens it, and Ask AI carries the query into a locally
prepared question. The selected result can be excluded explicitly. Returning
from chat preserves the search query and filters. Previews show at most 16,000
characters and identify that display limit; it is not a limit on prepared source
snapshots.

Ask rechecks the source identity: moved vault notes follow a unique stable ID;
ambiguous or trashed notes are refused. Tasks and shared conversations are read
again, newly trashed conversations are refused, and external Markdown can use a
complete kept recovery draft when its original is unavailable. File results use
the existing coordinated image/PDF/text preparation and limits. Unsupported,
locked or unreadable files show an error rather than sharing only their filename.
Conversation references include message text, labeled as such; their images and
document attachments are not recursively imported.

The handoff merges the query into an existing new-question draft, preserving its
images/documents and the separate draft of the previously selected conversation.
It commits that local state once, with compare-before-write protection. Note
context is now stored per private conversation draft, including an explicit empty
selection. Closing/reopening chat therefore cannot silently substitute the open
note for the chosen search result. Preview 25 stored draft context by vault path; preview 26 adds identity-based
resolution and review of older selections.
Nothing is sent until Send is pressed.

Eighty-three native tests cover the handoff, both draft recoveries, exact context,
source revalidation, complete file/external snapshots and unchanged portable
events/source bytes. Native UI checks cover the searched note differing from the
open note, appending the query, retained attachments and reopening the same context.
A manual accessibility check exposed a cached previous-result announcement; the
preview now changes its view identity with its selected source/content so AppKit
rebuilds that accessible content. Broader VoiceOver and keyboard acceptance remain
in progress.

Evidence under `artifacts/native-macos/` includes
`search-context25-tests-final.log`, `search-context25-accessibility-baseline.txt`,
`search-context25-accessibility-final.txt`, `search-context25-web-compat.log`,
`local-build25-final.log`, `native-search-context25.png`,
`native-search-handoff25.png` and `delivery-build25.json`.
This remains a local, non-notarized Apple Silicon preview. Live provider/account
acceptance, native agents/tools and full feature parity are still pending.

## Preview 26 — durable note-context identities

Private note context now retains stable note IDs as well as current paths.
Opening chat and preparing Send read a fresh vault snapshot. A unique ID follows
an outside rename, even when a different note now occupies its old filename.
Missing, trashed or duplicate identities block context preparation and retain the
question, selected images/documents and original reference for review.

Notes without IDs use a content fingerprint. An unchanged note can follow a
unique matching rename; changed legacy content requires explicit selection again.
Older preview-25 path-only selections require a one-time review in Context,
rather than binding automatically to whatever currently occupies that path. An
explicit empty context stays empty. The picker reads fresh notes, shows their
paths, and stages changes until Confirm selection; unavailable or ambiguous
references are not preselected as replacements.

Source preparation preserves a live unsaved editor draft only when its original
baseline belongs to the selected identity. It does not apply a scan over the open
editor or force a note save. This keeps an original draft from being attached to
a new note at its old path. The provider receives the immutable prepared source
snapshot, with the existing context limits and portable source metadata.
Credential waits use a captured endpoint/model, and a changed question,
conversation, attachments or context cancels that pending send before inference.
Retry also verifies that its selected conversation/reply did not change while
credentials were being read.

Eighty-five native tests pass. The path-only baseline demonstrably chose the
replacement note; the corrected resolver chooses the original ID and unsaved
source text, persists its renamed path, and rejects missing/duplicate identities.
Coverage also exercises old private-draft migration, unchanged/changed id-less
notes, explicit empty selections and refusal to use another vault’s snapshot.
Original source bytes and portable events remain unchanged by context review.

Evidence under `artifacts/native-macos/` includes
`chat-context26-path-baseline.log`, `chat-context26-tests-final.log`,
`chat-context26-web-compat.log`, `native-chat-context26.png`,
`local-build26-final.log` and `delivery-build26.json`.
This remains a local, non-notarized preview. Full editor/search/provider and
multiwindow acceptance, native agents/tools and full feature parity remain open.


## Preview 27 — note links while writing

The editor’s Link button now replaces the current selection or inserts at the
caret, with native undo/redo. In rich mode, typing `@` or `[[` offers up to eight
matching note titles/paths. Arrow keys move through results, Return/Tab inserts,
and Escape dismisses without taking typing focus. Email addresses, inline code,
existing links and marked-text composition do not trigger completion. Source
mode retains the manual picker; external-file editors can choose existing notes.

Create in the picker writes a stable-ID note in the source note’s physical
folder (or Inbox), inserts its link, and keeps the source editor open. It reuses
a unique matching title, refuses filename collisions, and checks the originating
vault and editor state across the write. Following a missing bare-title link
instead offers an explicit Create and open dialog. Missing IDs, paths and heading
references remain unavailable; hover previews and heading navigation are pending.

Plain edited note links save as shared wikilinks. A production web backlink scan
initially missed the rich editor’s fragment-link output; the regression now
requires the portable plain-link format. Styled labels retain fragment links,
whose broader cross-client indexing acceptance remains open. Unchanged paragraph
tokens, including underscore emphasis, remain preserved.

Eighty-eight native tests cover caret replacement after Unicode, undo/redo,
stale selections, both typed triggers, email/code exclusions, creation without
navigation, collisions and old-vault rejection. Both the append-at-end baseline
and the fragment-only plain-link baseline fail for their intended reasons.
Manual native checks cover typing suggestions, creation without leaving the
source, missing-link confirmation, saved-link navigation and dismissal focus.

Evidence under `artifacts/native-macos/` includes
`note-links27-append-baseline.log`, `note-links27-interop-baseline.log`,
`note-links27-tests-final.log`, `note-links27-web-compat.log`,
`native-note-links27-installed.png`, `local-build27-final.log` and
`delivery-build27.json`. This is an ad-hoc, non-notarized Apple Silicon preview.
Full feature parity remains in progress in the tracker above.


## Preview 28 — heading navigation and linked-note previews

Following a stable-ID/title link with a heading suffix now opens the note and
reveals that section. Relative Markdown file links retain their decoded fragment;
local `#fragment` links navigate the editor’s live text, including an external
note editor. Local navigation does not save or change the document. The native
Outline is clickable, follows Markdown headings rather than lines inside fenced
examples, and gives duplicate headings unique slug identities. Rich text and
source map the same heading to their own text coordinates. A request is consumed
once, scoped to its document, and cannot reset later caret movement. Missing
headings open the target note with a clear message and leave the outline available.

Hovering a link offers a read-only snapshot of its target, with title, path,
bounded body excerpt and explicit Open note. Preview linked note is also available
in the native context menu. A heading link previews from its section. Stable IDs,
relative files and local headings resolve consistently; ambiguous/missing notes
do not bind to a different title match. Current unsaved vault text is included.
Previewing performs no file write, attachment read, external URL open or provider
request. The overlay stays in the editor window and does not take typing focus;
editing, navigation, dismissal or leaving the link/preview closes it.

Ninety-two native tests cover delayed-preview focus/dismissal, Unicode/CRLF coordinates, duplicate headings,
fenced-code exclusion, one-time/document-scoped navigation, unchanged text and
undo history, live local drafts without forced writes, stable/relative fragments,
missing headings and preview identity/ambiguity. A fragment-dropping baseline
fails at the workspace navigation boundary. Native UI checks exercise a long
note, both duplicate sections, relative links, missing-heading messaging, preview
content and explicit opening. Duplicate outline entries carry distinct accessible
identities and their heading level/slug. Pointer-only event delivery remains part
of broader native acceptance; the explicit context-menu preview is visually
verified, and the delayed hover presenter is exercised against a real text view.

The small Mac heading adapter currently mirrors the portable algorithm in the
iOS heading/UI file. Extracting that parser into the shared Apple module remains
part of service consolidation; this change does not modify the iOS target.
Rich tables/code, image interaction, complete style/IME fidelity, large-vault and
multiwindow acceptance, provider/agent workflows and the other tracker items remain.

Evidence under `artifacts/native-macos/` includes
`heading-preview28-fragment-baseline.log`, `heading-preview28-tests-final.log`,
`native-heading28-installed.png`, `native-note-preview28-installed.png`,
`local-build28-final.log` and `delivery-build28.json`.
The production web editor’s prepare/restore path round-trips the QA note byte for
byte, retaining stable-ID heading suffixes, aliases and encoded relative fragments.
This proves storage preservation; cross-client heading navigation acceptance
remains pending. Evidence is `heading-preview28-web-compat.log`.
This remains an ad-hoc, non-notarized Apple Silicon preview.


## Preview 29 — styled link identity and backlink indexing

Partially bold, italic or code-formatted note labels now serialize as one complete
link. The native serializer groups the link independently of font runs, retains
its target, and writes the current full label into its metadata. Plain labels
still use wikilinks; styled or escaped labels use the existing portable fragment
format. Saving/reopening and native undo/redo retain the visible formatting,
including aliases containing brackets, a pipe and Unicode. Editing the plain
part of a styled label updates that alias without changing its target. Unchanged
paragraph tokens retain their original spelling.

Web body-link indexing now reads the same fragment format, including styled
labels and reference-style Markdown links. Its shared decoder is also used by
the web editor. Wikilinks and fragment links retain document order; code, images,
HTML examples, external URLs and malformed fragments do not become backlinks.
The native inspector likewise uses parsed body references rather than substring
matches: it recognizes complete identities/heading targets, refuses ambiguous
names, and ignores code examples and ID prefixes. Parsed native source references
are cached by path/content and invalidated after changes. Paired/schema relation
workflow acceptance remains a separate tracker item.

Ninety-four native tests and 46 focused web tests pass; TypeScript checking and
the production frontend build pass. Native regressions demonstrably reproduced
split link labels, missing styled backlinks and false code/prefix/ambiguous-name
backlinks. The web baseline omitted styled fragment links. Real native UI checks
cover partial formatting, label editing, undo/redo, reopening, following the link
and showing only its actual incoming source. Production web code reads the files
saved by the native app, finds the expected backlink, and round-trips both styled
labels without losing their target, bold/italic runs or untouched paragraph.

Preview text is now prepared only when the preview is presented; repeated pointer
updates can resolve the immutable note snapshot without re-parsing its body.
This preserves the existing delayed-preview focus/cancellation checks. Broader
pointer, IME, nested/multiline style, table/image, large-vault and multiwindow
acceptance, provider/agent workflows and other parity items remain open.

Evidence under `artifacts/native-macos/` includes
`styled-links29-native-baseline.log`, `styled-links29-backlink-baseline.log`,
`styled-links29-web-baseline.log`, `styled-links29-native-final.log`,
`styled-links29-web-final.log`, `styled-links29-web-compat.log`,
`styled-links29-typecheck.log`, `styled-links29-frontend-build.log`,
`native-styled-links29-installed.png`, `native-backlinks29-installed.png`,
`local-build29-final.log` and `delivery-build29.json`.
This remains an ad-hoc, non-notarized preview and does not complete feature parity.


## Preview 30 — native image sizing and editing

Double-click an inline image, or use its context menu, to edit its address,
description, title, width and height. Keep aspect ratio stores a width with an
automatic height; disabling it permits explicit dimensions. Blank dimensions and
Automatic size restore natural sizing. Invalid sizes stay in the form. Expand
opens a native fitted preview; Remove image asks before removing just that
occurrence. The original file stays in place. Each applied edit/removal is one
native undo/redo operation, scoped to the original document and image snapshot.

Explicit dimensions use the same standard HTML image attributes as the existing
web editor. Native rich text now renders single supported image tags directly,
including width-only, height-only and explicit dimensions. It also honors the
legacy Markdown `alt|width` form. Image bounds fit the current line width while
retaining the requested ratio; tall images scale proportionally. Unedited
paragraph spelling remains intact, and image metadata participates in change
detection so a size-only edit cannot silently keep the old Markdown. Titles are
retained when an image-containing paragraph is edited.

Supported tags permit src/alt/title/width/height only. Other HTML retains source
editing. No remote image request is made; the new editor works on loaded local
images and keeps unavailable resources as saved references. Changing the address
reads only a permitted local resource when rendering; it does not import or
rewrite the original file. External image/file workflows remain in acceptance.

Ninety-six native tests pass. A size-ignoring baseline fails for legacy and HTML
dimensions. Coverage exercises proportional layout, explicit ratios, titles,
original paragraph tokens, duplicate occurrences, editor undo/removal, stale
requests and unchanged asset bytes. The image-management owning-boundary test
also retains a source file when a sized HTML occurrence still references it.
Native UI checks cover invalid input, a 300-pixel width, edited description/title,
unchanged second occurrence, undo/redo, expansion, removal and restoration.
A browser renders the saved tag at 300 × 150 from the 960 × 480 original and
retains the decoded description/title.

Remaining image work is explicit: Manage Images currently lists Markdown
occurrences; sized HTML images use the inline controls. Shared image-manager
listing/removal, full cross-client editor journeys, gesture sizing and export
fidelity remain in scope. The current native export parser includes these HTML
tags as source text; use Automatic size to return the image to ordinary Markdown
for the existing export path. This is an intermediate preview, not completed
image/workflow parity. Other editor, provider/agent and tracker work also remains.

Evidence under `artifacts/native-macos/` includes
`image-edit30-size-baseline.log`, `image-edit30-tests-final.log`,
`image-edit30-portable-contract.json`, `image-edit30-browser-layout.json`,
`image-edit30-removal-undo.json`, `native-image-edit30-installed.png`,
`native-image-sizing30-installed.png`, `local-build30-final.log` and
`delivery-build30.json`. This remains an ad-hoc, non-notarized Apple Silicon preview.


## Preview 31 — sized image management and exports

Manage Images now recognizes safe image-only HTML fragments as well as ordinary
Markdown images. It preserves exact occurrence markup, Unicode/CRLF coordinates,
alt text, title and dimensions through reviewed removal, undo and Trash restore.
Code, comments, script content and unsupported HTML remain inert. The shared
`packages/apple/Markdown` Swift package keeps Mac and iOS parsing consistent.

HTML and Word exports retain independent sizes for occurrences sharing one file.
Mac PDF export now paginates native text and explicitly draws image bitmaps with
measured attachment cells. This fixes missing images and reserves their full
height. A rendered export verified exactly three images at 300 × 150, 160 × 80
and 240 × 60, with no overlap or duplicate paint. Long-document regression
coverage also checks that all paragraph sentinels survive pagination once.

Validation: 98 macOS and 210 iOS tests passed. Baseline runs demonstrated the
previous HTML occurrence omission and missing PDF image resources. The updated
iOS Simulator app lists both sized HTML occurrences and opens the image preview;
its production version/build remains 0.3.107/57. No archive or upload was made.
Evidence includes `sized-image31-tests-final.log`, `sized-image31-ios-tests-final.log`,
`sized-image31-pdf-opaque-baseline.log`, `sized-image31-pdf-layout.json`,
`sized-image31-native-reviewed.pdf`, `sized-image31-pdf-reviewed.png` and
`ios-sized-image31-manager.png` in `artifacts/native-macos/`.

This is an ad-hoc local Apple Silicon preview. Full feature parity remains open;
unsupported HTML, gesture resizing, complete clipboard/provider lifecycle cases
and the remaining matrix items still require implementation or acceptance.

The preview-31 local DMG was mounted, copied out and verified with strict deep
signature checking; the extracted build 31 launched against the QA vault and
listed all three image occurrences. A private download matched SHA-256
`9c710b95da01071d6243dd97f2ce8a8c0b1ece6969243acdf39a3d0f0e4d63d2`.
Installed screenshots and artifact checks are recorded in `delivery-build31.json`,
`native-sized-images31-editor-installed.png` and
`native-sized-images31-manager-installed.png`. Both web preview routes returned
HTTP 200. Original QA note and image bytes remained unchanged.


## Preview 32 — native image resize handles

Selecting a rich-text image reveals a corner resize handle. Dragging previews its
new bounds and dimensions, then applies one image edit on release. The current
display aspect ratio is retained, including explicitly proportioned images;
existing source, description and title are preserved. Sizing is bounded to the
editor width and supported attachment height. Escape cancels without modifying
the note or adding an Undo step. Double-click and the existing Edit image dialog
remain available for exact dimensions and keyboard access.

A hosted SwiftUI editor test sends mouse events through the actual native view,
checks that intermediate movement does not publish edits, validates saved markup
and displayed geometry, and verifies one-step Undo/Redo and cancellation. All
99 Mac tests passed. Real UI dragging resized a 300 × 150 occurrence to
200 × 100; one Undo restored the exact original Markdown and asset hashes.
Evidence: `image-drag32-tests-final.log`, `image-drag32-undo-proof.json` and
`image-drag32-before.json` under `artifacts/native-macos/`.

The drag uses an outline preview and commits the image layout on release. Full
image lifecycle/provider acceptance and the broader parity tracker remain open.

The extracted preview-32 DMG app also passed a real corner-drag check, saving
the first occurrence at 240 × 120 while retaining the independently sized
300 × 75 occurrence, original image bytes and surrounding source. The DMG
checksum, strict signature verification and matching private download are
recorded in `delivery-build32.json`. Installed screenshots are
`native-image-drag32-before-installed.png` and
`native-image-drag32-after-installed.png`. Both web preview routes returned 200.
This remains an ad-hoc local Apple Silicon build, without notarization.


## Preview 33 — multiline rich-text formatting

Ordinary multiline paragraphs are now parsed together, so strong/emphasis spans
can cross a soft or hard line break and retain nested traits. Untouched paragraph
source is retained as one token. Editing either line serializes the complete
paragraph consistently, avoiding orphaned delimiters from an untouched second
line. Neighboring paragraphs retain their own source spelling.

The inline writer keeps leading/trailing whitespace outside opened/closed
emphasis delimiters. Formatting a selection such as ` one\nsecond ` now saves
valid CommonMark around each word. Hard breaks remain hard breaks and line
ending metadata retains CRLF when an affected line changes.

All 101 Mac tests passed, including LF/CRLF, soft/two-space/backslash hard breaks,
nested style changes on either line, independent CommonMark parsing, save/reopen
and Undo/Redo. The corrected baseline restored the previous line parser and
serializer and failed these contracts for the intended reasons. Evidence:
`multiline33-corrected-baseline.log`, `multiline33-tests-final.log`,
`multiline33-original.md` and `multiline33-saved.md`. Native keyboard editing
verified both cases; two Undo steps restored exact original note bytes.

This covers ordinary paragraphs. Nested list/quote continuations, complex inline
code delimiters, complete paste/IME/dictation and broader editor parity remain
open. Existing source fallback for unsupported blocks is retained.

The preview-33 DMG was mounted and copied out; strict signature verification and
its private download hash matched. The extracted app saved both formatting
changes and reopened them correctly after termination. Its screenshot is
`native-multiline33-installed.png`; `delivery-build33.json` records the artifact
and verification evidence. This remains an ad-hoc, non-notarized Apple Silicon
preview. Both web preview routes returned HTTP 200.


## Preview 34 — literal inline code and native font traits

Code formatting now selects a backtick delimiter longer than every literal run
in the selected text. Content that starts or ends in a backtick, or has meaningful
spaces at both ends, receives CommonMark padding. Entire code spans are gathered
across native attribute bookkeeping before choosing a delimiter. This prevents
embedded backticks from closing a span early and prevents space trimming from
changing the stored code text.

Reopened inline code retains inherited strong/emphasis font traits. Code in a
heading also follows its heading size and weight while keeping a monospaced font.
Untouched paragraphs preserve their original source, and other paragraphs retain
their spelling after code formatting.

All 102 Mac tests passed. The new owner-boundary table drives native formatting,
independently parses saved CommonMark, checks literal text and reopened font
traits, and covers Undo/Redo. Cases include embedded runs of two/three backticks,
edge backticks, leading/trailing/both-edge and all-space content, Unicode and
Markdown punctuation, with and without nested bold/italic. Baseline failures
confirmed premature closing delimiters, changed content and lost native traits.
Evidence: `inline-code34-baseline.log`, `inline-code34-unicode-baseline.log`,
`inline-code34-tests-final.log`, `inline-code34-web-parser.json`,
`inline-code34-original.md` and `inline-code34-saved.md`. The real native toolbar
converted a literal backtick run and one Undo restored exact original note bytes.

Nested list/quote continuations, complete paste/IME/dictation and the broader
feature-parity matrix remain open. This work does not replace the fenced-code
block editor or remove source fallback for unsupported blocks.

Delimiter scanning uses UTF-8 bytes so a combining accent attached to a backtick
cannot hide that literal marker as a grapheme cluster. The additional Unicode
baseline reproduced the premature delimiter; the expanded 102-test suite passed.
The web app's remark parser independently retained all three code values from
the saved native UI sample, including the original literal edge spaces.

The preview-34 DMG was mounted and copied out, its strict signature verified and
its private download matched SHA-256. The extracted app formatted the combining-
accent sample and reopened it correctly. Remark independently parsed the saved
Unicode code without changes to neighboring source. Native visual checks also
confirmed monospaced heading-sized code. `delivery-build34.json`,
`inline-code34-packaged-proof.json`, `native-inline-code34-installed.png` and
`native-code-headings34-installed.png` record this handoff. This remains an
ad-hoc, non-notarized Apple Silicon preview; full parity remains open.


## Preview 35 — external note changes and retained text

The existing eight-second/background-activation refresh detects notes created
outside the app. Refresh now also follows a clean open note after an unambiguous
stable-ID rename or move, remapping its tab and navigation path. Clean outside
content changes update source-mode requirements before reopening the editor.

Dirty moved/modified notes and clean missing/replaced notes keep their original
text visible. A banner explains the outside change; autosave cannot recreate a
missing file or overwrite another saved version. A recovery export writes the
complete retained Markdown outside the vault. Switching versions or closing a
missing note requires verifying that the exported file still matches the current
text. Editing again invalidates that export receipt. Missing or modified exports
leave the retained text open. Exports do not copy linked resource files.

Refresh requests are serialized per workspace and stale-vault errors are ignored.
Note-move, image and recovery operations are not refreshed mid-transaction.
Duplicate stable identities do not authorize following an unrelated path.

All 105 Mac tests passed. Real file mutations cover renames, source-mode changes,
modified drafts, dirty moves, clean replacement/removal, ambiguous identity,
blocked saves, exports, stale drafts and missing/tampered export receipts.
The rename regression failed against the previous implementation. Evidence:
`refresh35-baseline.log` and `refresh35-tests-final.log`. Full provider, large-vault,
window lifecycle and recovery-browser acceptance remain open.

A file returning with different contents also keeps the already-retained text
until its export is verified. The returned-file baseline reproduced the unsafe
replacement, and the final 105-test run covers this transition. Returning the
identical original file clears the retention state without dropping unavailable
text. Retained tab titles continue to show the original note title.
Native UI checks followed an external rename without relaunch and retained a
missing note; its save-panel export matched original bytes, then Close retained
note became available. The missing path was not recreated. Evidence:
`refresh35-returned-baseline.log`, `refresh35-ui-rename.json`,
`refresh35-export-proof.json`, `refresh35-exported-note.md` and
`native-retained-note35-debug.png`.

Automatic identity following is limited to active notes. A retained Trash note
does not adopt an unrelated active note sharing its stable ID. The Trash identity
baseline reproduced that unsafe jump, and the final test run covers it with the
other retention cases. See `refresh35-trash-identity-baseline.log`.

The final preview-35 DMG was mounted and copied out; its strict signature verified
and its private download matched SHA-256. The extracted app followed a second
external rename, retained the missing-note text, exported an identical Markdown
copy and closed the retained tab without recreating the missing file. Installed
screenshots are `native-rename35-installed.png` and
`native-retained-note35-installed.png`; `delivery-build35.json` records the
artifact and verification. Both web preview routes returned HTTP 200. This is an
ad-hoc, non-notarized Apple Silicon preview, with full feature parity still open.


## Preview 36 — guarded window close and note recovery browser

Window Close now runs the workspace save/checkpoint preflight before asking the
original window delegate to close. The AppKit bridge forwards the delegate’s
remaining callbacks, so SwiftUI still owns the window lifecycle. A conflicting,
missing or unreadable original keeps the retained editor open. The selected file
is checked even if the vault inventory could not be read. A verified matching
export permits closing without writing to the outside version; its private
checkpoint stays available. The final check rejects changed exports or drafts.

The vault and File menus now open Note Recovery Drafts. It scopes records to the
open vault, previews retained text and the original baseline, and exports full
Markdown while keeping the private JSON checkpoint. Existing records without a
`vaultRoot` field remain readable by their established vault/path hash; new
records include vault provenance. Changed previews, another vault, linked draft
files and destinations inside the vault/private recovery directory are rejected.
The browser does not write to original notes or copy linked resource files.
A matching browser export also satisfies the active retained editor’s close
requirement. File → New Window (Shift-Command-N) opens a workspace when needed.

All 108 Mac tests passed. Actual NSWindow close requests verify save completion,
retained conflicts, binary/unavailable originals, export-backed closing and
forwarding of the original delegate. Real private-file tests cover restart,
legacy schema, CRLF/Unicode content, scope, symlinks, immutable checkpoints and
stale previews. Baseline checks reproduced the old unresolved-editor window close
and the export/unreadable-original close gaps. Evidence:
`lifecycle36-window-baseline.json`, `lifecycle36-export-close-baseline.log`,
`lifecycle36-tests-final.log`, `lifecycle36-legacy-proof.json` and
`lifecycle36-close-proof.json`. Native UI recovery exported the old build’s
retained note byte-for-byte, including foreign YAML, after its original vanished.
A Close attempt in the updated app kept the unresolved editor visible.

Recovery currently scopes to an open vault. Unreadable records are kept with a
warning; this browser does not delete checkpoints. Concurrent-window draft
ownership, complete provider interruption and broad window/restoration
acceptance remain pending with the rest of the feature-parity matrix.

The preview-36 local DMG was mounted/copied out, strictly signature-verified and
downloaded through the private endpoint with matching SHA-256. The extracted app
kept an unresolved editor open, recovered/exported a legacy checkpoint exactly,
refused to release the active editor for an unrelated draft export, and closed
after its matching browser export. Private checkpoint bytes stayed unchanged.
New Window created a second workspace; its clean close returned to the first.
Recovery remains open for inspection. Evidence: `delivery-build36.json`,
`native-note-recovery36-installed.png`, `native-close-protected36-installed.png`
and `native-workspace36-installed.png`. Both web preview routes returned 200.
The browser reads private records up to 32 MB and keeps unreadable records with
a warning. This remains a non-notarized Apple Silicon preview; full parity is
still in progress.


## Preview 37 — independent window note checkpoints

Each workspace now writes a UUID-owned checkpoint for each note, preserving the
legacy private JSON format in the recovery reader. Saving or accepting an exported
draft removes only that window’s checkpoint and unchanged historical records it
actually adopted. A new window excludes drafts owned by another live workspace.
Restart recovery adopts one distinct baseline-matching historical text; disagreeing
values stay available in File → Note Recovery Drafts for review and export. List
excerpts distinguish multiple drafts of the same note. Exports still retain private
checkpoints; the browser has no discard or cleanup action.

Move preparation recognizes every window’s checkpoint, including unreadable matching
files. Move application checks the directory again, so a different window’s newly
created checkpoint blocks a previously reviewed move. New files use canonical vault
paths; legacy records remain readable under their established vault path. Live
window ownership is scoped to the running application process; cross-process and
large-vault acceptance remain pending.

Validation: the regression failed on preview 36 because one shared checkpoint
overwrote another and a successful save deleted the peer’s draft. All 111 Mac
tests pass after the repair, including real workspace saves, byte-preserving
conflicts, historical recovery/ambiguity, legacy export and late move protection.
Native two-window editing produced two independently owned files with different
text after the original disappeared. Evidence: `draft-owners37-baseline.log`,
`draft-owners37-tests-final.log`, and `draft-owners37-ui-proof.json`.
Full feature parity remains in progress.

The local preview-37 DMG was mounted and copied out, strictly signature-verified,
launched and checked in the native UI. Its recovery browser showed the retained
peer text after the first window’s text had saved. The downloaded DMG hash matched
the local artifact. No notarization was requested. Evidence: `delivery-build37.json`,
`native-workspace37-installed.png` and `native-recovery37-installed.png`. Both
web preview routes returned 200.


## Preview 38 — native editor preferences

Settings now provides the web editor’s two controls: Note link shortcuts (on by
default) and Code blocks (off by default). These are device preferences, shared
across native windows and kept after restart; changing them never rewrites a note.
Turning suggestions off keeps typed `@` and `[[` literal while the toolbar’s Link
button stays available. Turning code creation off hides Insert code block but
keeps Edit code entries for existing blocks. Explicit Markdown source remains
editable with either preference.

With creation on, triple backticks with an optional language followed by Return
insert a fenced block and open native source editing with the caret inside. Undo
restores the preceding rich text and typed fence; Redo restores the code block.
When creation is off, new formatted clipboard code becomes escaped literal prose,
including indentation and straight quotes. Surrounding formatting and embedded
images remain intact. Paste and Match Style stays literal. Existing blocks are
never converted when opening notes or changing preferences. Inline code remains
available independently of fenced-block creation.

Focused checks cover live suggestion enable/disable with manual insertion, typed
fences and Undo/Redo, and HTML code/image paste with both preferences. The initial
checks exposed smart punctuation in converted prose and typing coalescing across
the mode change; both were repaired at the native editor boundary. No shared iOS
source changed. Full editor, appearance and desktop parity remain in progress.

All 114 Mac tests pass (`editor-settings38-tests-final.log`). Native UI verified
Return/Undo/Redo, editing an existing block with creation off and saved Markdown
with foreign YAML intact. A note-byte inventory confirmed that changing preferences
alone did not touch the notes. The extracted local DMG app relaunched with both
preferences remembered; the default shortcut preference was restored afterward.
The DMG passed checksum and strict signature verification, and its private download
hash matched. Both web preview routes responded successfully. Evidence:
`editor-settings38-ui-proof.json`, `delivery-build38.json`,
`native-editor-settings38-installed.png`, `native-workspace38-installed.png`.
No notarization was requested.


## Preview 39 — editable code inside native rich text

Top-level fenced blocks now remain in the rich editor. Their bodies are ordinary
editable AppKit text with monospaced styling, a language label and a native block
background. The immutable original fence token stays separate from the visible
body. Unedited blocks preserve their exact fence, info string, newline spelling
and unfinished-fence form; a body edit uses the established fence serializer.
Markdown punctuation and note-link triggers inside code remain literal. Native
spell correction is disabled while the caret is in code or explicit source.

Return continues the code body; ⌘Return or Paragraph → Continue after code block
moves back to prose. Empty blocks keep a display-only insertion marker which is
never saved. Single-key deletion keeps structural separators intact; selecting a
whole block still allows deletion. Formatted code pastes form separate blocks
when creation is enabled; paste within a code body stays literal. Code creation
off still permits existing block edits. Source mode and the code editing sheet
remain available. Tables, nested block structures, syntax highlighting and broader
keyboard/selection/IME/accessibility acceptance remain open.

The focused tests cover LF/CRLF with foreign fence spelling and info strings,
empty/unfinished fences, localized code/prose edits, literal content, cross-note
clipboard transport, code creation, exit to prose and Undo/Redo. Paste operations
now receive separate native undo events even if asynchronous work finishes during
the same run-loop turn. No shared iOS sources changed. Full desktop parity remains
in progress.

All 117 Mac tests pass (`inline-code39-tests-final-fixed.log`). Native UI verified
in-place code editing, literal punctuation/triggers, Return, ⌘Return, Undo/Redo
and a rich/source round trip; the saved file retained its `~~~swift extra` fence
and foreign YAML. Final QA reproduced an emptied-block deletion bug, recorded in
`inline-code39-empty-delete-ui-baseline.json` and a failing owning-boundary test
(`inline-code39-empty-delete-baseline.log`). The repair gives whole-block deletion
its own undo command. Native deletion, Undo and Redo were repeated successfully;
the final note contains only its unchanged frontmatter. Other fixture notes stayed
byte-identical. See `inline-code39-ui-proof.json`.

The local preview-39 DMG passed checksum and strict signature verification. The
extracted release app saved an inline code edit, then Undo restored the exact
previous file SHA-256. Rich/source switching also preserved the file. Its private
download hash matched the local DMG. Evidence: `delivery-build39.json`,
`native-inline-code39-installed.png`, `native-code-source39-installed.png`.
The rich note remains open. Both web preview routes returned 200. No notarization
was requested. Inline body edits have native Undo; the older language/code-sheet
path still reloads the editor and needs further undo acceptance.


## Preview 40 — code sheets share native Undo history

Code-sheet saves now send a window- and note-scoped command to the existing native
editor. Existing block edits replace their attributed range; new blocks insert at
the caret, moving after an existing block when invoked from code. Rich/source mode
stays unchanged, and the original Undo history survives. Undo/Redo notifications
from the editor’s own manager publish native text-system changes back to the note
model, including typing performed before a code-sheet operation. No reload is used
for these sheet changes. This resolves preview 39’s code-sheet Undo limitation.

Requests capture the workspace activation and original body when the sheet opens.
Stale text or an unavailable editor leaves the sheet’s draft and error visible,
with a Copy code button; no note text is overwritten. New block creation also
rechecks the current creation preference at save time. Pending code sheets block
window/app close until Save or Cancel. File → Close Window (⌘W) now uses the guarded
close flow and is disabled while a code sheet is open. The editor regains focus after dismissal.
Toolbar actions target their specific window/note; global formatting menu actions
apply only in the key editor window.

The preview-39 UI baseline reproduced a language change that could not be undone
(`code-sheet40-undo-ui-baseline.json`). Native tests exercise rich/source edits and
inserts, earlier prose Undo history, cross-window command targeting, stale requests
and creation preference changes. The initial history test also caught an AppKit
Undo that restored the view without publishing to the note model; the manager
notification handler repairs that boundary. No shared iOS sources changed.
Full desktop parity remains in progress.

All 120 Mac tests pass (`code-sheet40-tests-focus.log`). Native UI verified two
levels of Undo across sheet/prose edits and Redo, source-mode sheet Undo without
changing mode, insertion at the caret and exact-file restoration after Undo. A
second window retained its selected prose and byte-identical file while keyboard
and toolbar formatting changed only the active note. CmdW closed a clean extra
workspace and left a pending code sheet open. An outside edit caused Save to keep
the code draft visible; Copy code round-tripped the exact draft, and the outside
file remained byte-identical after Cancel. Deferred focus restoration was checked
after Cancel from a note-list/restored-note entry point. Evidence:
`code-sheet40-ui-proof.json`, `code-sheet40-ui-start.json`,
`native-code-sheet40-stale-debug.png`. No shared iOS sources changed.

The local preview-40 DMG passed checksum and strict signature verification. The
extracted app saved a code-sheet language/body edit, then native Undo restored the
exact prior file hash. Cancel returned keyboard focus to the note. The private
download hash matched the local DMG. Evidence: `delivery-build40.json`,
`native-workspace40-installed.png`, `native-code-sheet40-installed.png`. Both
web preview routes responded successfully. The rich note remains open. No
notarization was requested. Pending sheet fields currently stay in the open sheet;
durable recovery of unfinished forms across process failure remains pending.


## Preview 41 — editable native tables

Portable GFM tables now use Apple text-table cells in the rich editor. Inline
formatting and note links stay available; Return inserts a cell line break saved
as `<br>`, Tab moves forward and adds a row after the last cell, Shift-Tab moves
backward, and ⌘Return continues in prose below the grid. Partial deletion clears
cell contents while preserving the grid; selecting the whole table can remove it.
Original width comments, column alignment, extra source cells and unchanged cell
syntax are retained. Tables with unsupported HTML still open in source mode.

The structure sheet retains earlier typing in Undo history, supports row/column,
width/alignment and spreadsheet operations, and keeps stale drafts open with
Copy Markdown. Pending table sheets guard window/app close until Save or Cancel.
Inserting a separate table from inside an existing table places it after that
block. Broader spreadsheet/grid clipboard, selection, IME, VoiceOver, table image
and multiwindow acceptance remain pending; this does not complete table parity.

All 124 native Mac tests pass (`native-tables41-tests-final.log`). Native UI checks
covered direct cell saves, row-sheet edits with two levels of Undo, Tab row
creation, multiline cells, exit to prose, and stale drafts after outside file
changes. Copy Markdown retained the draft; Cancel preserved the exact outside
file. Evidence: `native-tables41-ui-proof.json`, `native-table41-stale-debug.png`.
The tests caught and repaired an empty-cell parser-prefix leak before delivery.
No shared iOS sources changed. README platform, setup, build commands and native
limitations were reviewed before packaging this intermediate preview.

The local preview-41 DMG passed checksum and strict signature verification. The
extracted app saved a direct cell edit and native Undo restored the exact prior
file bytes. Its private download hash matched the local DMG. Evidence:
`delivery-build41.json`, `native-workspace41-installed.png`,
`native-table-sheet41-installed.png`. Both web preview routes returned 200.
The installed rich note remains open. This intermediate DMG is not notarized.


## Preview 42 — native table clipboard

Spreadsheet TSV paste now fills from the active cell and expands the grid while
retaining its existing widths, alignments and surrounding prose. Quoted multiline
cells become portable `<br>` breaks; literal Markdown stays literal. Explicit
single-column spreadsheet data also fills down. Ordinary Paste and Match Style
continues to insert text. Spreadsheet imports accept at most 10,000 cells and
reject unfinished quoted cells instead of dropping their contents.

Copying a complete table, full rows or adjacent complete cells in one row
publishes both TSV text for spreadsheets and the portable Zerus Markdown fragment
with inline formatting, alignment and widths. Partial words and irregular
cross-row selections keep ordinary text copy. Cutting a grid selection clears
its cells while retaining table structure. Grid pastes and cuts use one native
Undo event. Broader provider, attachment, irregular selection, keyboard/IME,
VoiceOver and large-table acceptance remains pending.

All 126 native Mac tests pass (`table-clipboard42-tests-single-column.log`). The
pre-change regressions reproduced flattened row copy and one-cell spreadsheet
paste (`table-clipboard42-tests-baseline.log`). Native UI saved the independently
expected expanded table with literal asterisks, multiline text and quoted Unicode;
copied adjacent cells published TSV, pasted as a table into another note, and one
Undo restored that note's exact prior bytes without changing the source grid.
Evidence: `table-clipboard42-ui-original.md`, `table-clipboard42-ui-pasted.md`,
`table-clipboard42-ui-proof.json`. No shared iOS sources changed. README platform,
setup, build commands, dependencies and native limitations were reviewed before
packaging this intermediate preview. Full feature parity remains in progress.

The local preview-42 DMG passed checksum and strict signature verification. Its
extracted app saved the same independently verified spreadsheet result, native
Undo restored exact original bytes, Redo restored the grid, and copied cells
pasted into a second note with portable widths and alignment. The private download
hash matched the local DMG. Evidence: `delivery-build42.json`,
`native-workspace42-installed.png`, `native-grid-copy42-installed.png`. Both web
preview routes returned 200. The expanded native grid remains open. This
intermediate DMG is not notarized.


## Preview 43 — native nested outlines

Marked nested bullet/numbered/checklist items, nested quotes and quoted headings
now render in Apple rich text with native paragraph indentation. Tab/Shift-Tab
move a list item and its descendants together; the Paragraph menu provides the
same commands. Return continues the current list/quote and leaves an empty nested
item one level at a time. Checklist toggles retain list indentation and quote
prefixes. Note-link completion handles Tab before list indentation.

Numbered child lists begin at 1 so both the shared Swift parser and the web
Markdown parser recognize the saved hierarchy. Outdenting restores the parent
sequence and keeps the caret at the same text. Original unedited lines and LF/CRLF
endings remain portable; edited paragraphs can use the existing canonical inline
Markdown spelling. Unsupported continuation paragraphs, embedded code/tables and
indented code retain source-mode editing. Broader pasted structures, complex
selection, numbering normalization, IME/dictation and VoiceOver acceptance remain
pending. This does not complete rich-editor or full desktop parity.

All 128 native Mac tests pass (`nested43-tests-final.log`). Pre-change checks
reproduced nested-prefix loss; later regressions caught numbered indentation that
parsed as prose, extra bold markup on quoted-heading edits and incorrect exit
from empty numbered children. The web parser independently confirmed the numbered
child-list rule. Native UI verified subtree Tab/outdent with exact-file restoration,
numbered caret typing, nested checkbox clicking, quote edits and list continuation
with native Undo. Tab accepted a note suggestion inside a nested list, and Undo
restored the exact prior file. Evidence: `nested43-ui-original.md`,
`nested43-ui-proof.json`; baseline logs `nested43-tests-baseline.log`,
`nested43-tests-number-baseline.log`, `nested43-tests-heading-baseline.log`,
`nested43-tests-empty-baseline.log`. No shared iOS sources changed. README features,
platforms, commands, dependencies and limitations were reviewed before packaging.

The local preview-43 DMG passed checksum and strict signature verification. The
extracted app saved subtree indentation and native Undo restored the exact prior
file bytes. The private download hash matched the local artifact. Evidence:
`delivery-build43.json`, `native-workspace43-installed.png`,
`native-subtree43-installed.png`. Both web preview routes returned 200. The native
outline remains open. This intermediate DMG is not notarized.


## Preview 44 — list selection keyboard handling

Tab/Shift-Tab now indent and outdent selected list items across blank paragraphs,
retaining the selected text and the untouched blank-line bytes. Selections that
mix prose and list items, different quote contexts or unsupported hierarchy shapes
are handled without replacing their contents with a tab character. Ordinary
non-list Tab behavior remains available. Each successful list operation uses the
existing native Undo history. This addresses list selection data loss; it does
not complete rich-editor selection or keyboard acceptance.

All 129 native Mac tests pass (`list-selection44-tests-fixed.log`). A regression
through the actual SwiftUI-hosted editor and native key events reproduced text
replacement before the fix (`list-selection44-tests-baseline.log`). It now covers
blank-line list selections, mixed selections starting in a list or prose, retained
selection, outdent and native Undo. Native UI independently verified exact-file
restoration after outdent and two Undo operations; mixed selection remained
selected and byte-identical after Tab and Save. Evidence:
`list-selection44-ui-proof.json`, `list-selection44-ui-list-original.md`,
`list-selection44-ui-mixed-original.md`. No shared iOS sources changed. README
features, platform support, setup/build commands, dependencies and limitations
were reviewed before packaging this intermediate preview. Full feature parity
remains in progress.

The local preview-44 DMG passed checksum and strict signature verification. The
extracted app indented a selection spanning a blank line and native Undo restored
the exact original bytes. A mixed prose/list selection stayed selected and its file
remained byte-identical after Tab and Save. The private download hash matched the
local DMG. Evidence: `delivery-build44.json`, `native-list-selection44-installed.png`,
`native-mixed-selection44-installed.png`. Both web preview routes returned 200.
The native list editor remains open. This intermediate DMG is not notarized.


## Preview 45 — connected-file images

Connected Markdown files now have an explicit project-folder chooser. It uses the
existing confined Apple project-file capability, restores the folder bookmark on
reopen and loads local image previews through coordinated reads. Selecting a
Markdown file alone does not authorize sibling-file creation. Pasted PNG/RTFD/HTML
images import into the chosen project's `assets/` folder with portable relative
references; copying project images into a vault carries their original bytes.
Long Unicode filenames use the Mac clipboard importer's byte-safe naming rules.

Image previews use bounded thumbnails and metadata refresh. Delayed previews,
folder changes and Undo snapshots preserve original Markdown tokens, selection,
typing attributes and earlier Undo history. Unavailable images are atomic native
placeholders rather than editable caption text. Each external presentation owns
its editor lifetime, preventing reused connections from retaining a previous
presentation's clipboard work. Existing BOM/frontmatter, outside-edit guards and
private recovery behavior remain in place. No vault metadata is added to the
external project. Remote image fetching, full-size/provider interruption,
external attachment management, multiwindow and complete image/clipboard
acceptance remain pending; full desktop parity is still in progress.

All 132 native Mac tests pass (`external-images45-tests-final.log`). Coverage
includes rejected image writes without a chosen folder, project paste/save with
BOM/frontmatter, Undo/Redo and retained image bytes, saved access after reopen,
project-to-vault copy transport and delayed preview refresh preserving caret,
Markdown and earlier history. The long-name case reproduced a failed import before
byte-safe normalization (`external-images45-tests-long-name.log`); the unavailable
image regression is in `external-images45-tests-placeholder-baseline.log`.
Native UI verified project selection, loading existing images without source
rewrites, portable image paste, exact-source Undo/Redo, cross-vault copy, persisted
folder access and text Undo across folder refresh. Evidence:
`external-images45-ui-proof.json`, `external-images45-ui-import.json`,
`external-images45-ui-vault-copy.json`, `external-images45-ui-original.md`,
`external-images45-ui-saved.md`. No shared iOS sources changed. README features,
platforms, setup/build commands, dependencies and limitations were reviewed before
packaging this intermediate preview.

The local preview-45 DMG passed checksum and strict signature verification. Its
extracted app restored the project folder and existing image previews, saved a new
pasted PNG with exact image bytes/BOM/frontmatter, and native Undo restored the
exact prior file. The imported PNG remained for Redo. The private download hash
matched the local artifact. Evidence: `delivery-build45.json`,
`external-images45-installed-paste.json`, `native-workspace45-installed.png`,
`native-external-images45-installed.png`. Both web preview routes returned 200.
The installed white workspace and copied image remain open. This intermediate DMG
is not notarized.


## Preview 46 — verified external recovery exports

A connected-file draft can now close through a verified text export when private
recovery storage cannot be written. Export preserves exact encoded Markdown,
including BOM and foreign frontmatter, and checks the saved bytes. The session
retains its file scope and rechecks the copy before allowing Done, window close or
quit to proceed through the existing checkpoint route. Editing the draft
invalidates its export; changed or missing copies block closing until re-exported.
Exports cannot target the connected original, its aliases or private recovery
storage. Dirty sheets use the explicit guarded close action. A successful re-export
replaces a stale export warning with the underlying recovery-storage issue.

All 133 native Mac tests pass (`external-export46-tests-final-status.log`). The
baseline reproduced an exact exported draft that still could not close
(`external-export46-tests-baseline.log`). Coverage includes same-size copy changes,
missing exports, later edits, original/private-path rejection, exact Unicode/BOM
output, and closing without changing the source or unreadable private record.
The stale-warning regression was independently reproduced in
`external-export46-tests-warning-baseline.log`. Native UI verified the existing
Command-S route, retained text after an owned QA storage failure, blocked close,
verified export, stale-copy rejection and successful close after a fresh export.
The QA private record was backed up before the failure simulation and restored
exactly afterwards. Evidence: `external-export46-ui-proof.json`,
`native-export46-verified-debug.png`, `native-export46-stale-debug.png`,
`external-export46-ui-original.md`, `external-export46-ui-expected.md`.

This is a retained-text export, not an attachment relocation operation. Broader
provider interruption, concurrent presentations, external attachment management,
keyboard and complete desktop parity remain pending. No shared iOS sources
changed. README features, platforms, setup/build commands, dependencies and
limitations were reviewed before packaging this intermediate preview.

Preview 46 was mounted read-only, copied out, and passed strict deep signature
verification. The copied app reopened the recovered copy and exported identical
Unicode/BOM/frontmatter bytes; the original remained unchanged. The private
download matched SHA-256 `19ad44cc6a47770019d5e5f1ea690aa658a7cbb518e0ab3a96aff2e804ce68e8`.
Both web preview routes returned HTTP 200. Delivery evidence: `delivery-build46.json`,
`native-workspace46-installed.png`, `native-export46-installed.png`. This is a
local, non-notarized intermediate DMG.

## Preview 47 — copy connected Markdown into the vault

The connected-file editor now provides Copy into vault. A review shows the vault,
folder, collision-resolved path, attachment count, total bytes, Markdown preview
and any portability warnings. The copy receives a fresh stable identity. Local
images and linked files require a chosen project folder and are copied into assets
with rebased Markdown. The connected original and project attachments stay in place.
Successful copies can open directly in the native editor. This handoff rechecks
the destination workspace after closing the connected-file sheet, so switching
vaults cannot open a matching path in a different vault.

The Mac adapter checks the owning workspace and editor presentation, clean source
bytes and changed drafts before committing through the shared transaction engine.
Vault switching and window close are blocked during the commit. Failed inventory
refresh after a successful copy reports the saved result rather than inviting a
second import. A real Inbox folder is distinct from the root on Mac; a new optional
shared-engine argument preserves the existing iOS virtual-Inbox default.

All 135 Mac tests pass (`external-copy47-tests-handoff.log`). New Mac-boundary tests
cover reviewed project copies, portable bytes, preserved foreign frontmatter,
fresh IDs, collision protection, required project authorization, subsequent draft
changes, reopened editors and reopening the same destination vault. Native UI
copied a note with one project image to Projects/Project brief 2.md, preserved the
existing note, then opened the copy. Evidence: `external-copy47-ui-proof.json`,
`native-copy47-review.png`, `native-copy47-workspace.png`.

External-note moves, pending-move recovery UI, provider interruptions and complete
cross-workflow acceptance remain pending. README features, supported platforms,
setup, commands, dependencies and limitations were reviewed for this preview.

The shared importer's existing iOS callers retain their default root mapping.
All six existing NativeExternalTransferTests pass in the iOS Simulator
(`external-copy47-ios-tests.log`). The updated simulator binary was built and
installed without changing the App Store build number, launched through device
tools, and left on External notes in the Device panel. Screenshot:
`native-copy47-ios-external.png`; build log: `external-copy47-ios-build.log`.

The local preview 47 DMG was mounted read-only and its copied-out app passed
strict deep signature verification. That app imported into the physical Inbox
folder with exact attachment bytes and unchanged original Markdown, then opened
the copy. The download matched SHA-256 `3b22c32e1d1508bc892747067241b872b5699996af5fbad645431eb29f401e36`.
Evidence: `delivery-build47.json`, `native-copy47-review-installed.png`,
`native-copy47-workspace-installed.png`. This intermediate DMG is not notarized.

## Preview 48 — reviewed external moves and pending recovery

The native import menu now provides Copy into vault and Move into vault. Moves
retain an existing source note ID, copy portable assets and verify the saved note
and every attachment before removing the unchanged original Markdown file. A
private journal retains the original bytes before copying and tracks prepared,
copied and removed phases until connection cleanup finishes. Original project
attachments stay in place. Other clean editors of the same original in this
process are held during transfer and become read-only after a successful move.
Dirty or changed peer drafts reject the transfer before source removal.

Pending moves appear in External notes. Recovery can open the destination vault,
reopen the original for a fresh removal review, verify and keep both copies while
closing the connection, finish a removed original’s saved connection, export exact
retained original bytes, or explicitly discard only the private record. The
recovery record cannot be closed against a changed/missing vault copy. Original
and destination paths, file aliases and private recovery storage are protected
from recovery exports. Export canonicalization resolves an existing ancestor
before appending missing components, avoiding Foundation’s /var versus
/private/var difference for future files restored from bookmarks.

All 139 Mac tests pass (`external-move48-tests-handoff.log`). Real filesystem
integration checks cover successful moves with portable image bytes and stable
IDs, a clean second editor becoming read-only, rejected outside source changes,
source-parent permission failures, durable copied-phase recovery after reopening,
resuming without a duplicate import, kept-both cleanup, changed destination
rejection and recovery export protection. A failing baseline reproduced the
future-destination export issue (`external-move48-tests.log`); nearest-existing-
ancestor canonicalization fixes it. A later complete run also passed 139 tests.

Native UI checks use an explicitly seeded copied-phase fixture for the owned
Native move review.md connection, with source/destination bytes and note ID in
agreement. They cover the pending-move browser, byte-exact recovery export,
reopening the original, selecting Finish pending move and verifying the saved
copy in a fresh removal review. The removal button was left unpressed during UI
preview; actual removals and failure/restart paths ran in the integration tests.
Evidence: `external-move48-ui-context.json`, `prepare-move48-ui.swift`,
`native-move48-recovery-debug.png`, `native-move48-review-debug.png`.
Transfer sheets now carry an explicit identified action instead of separate mode
and presentation booleans, keeping the first presented frame consistent.

Full cross-process/provider interruption, sandboxing and multiwindow acceptance
remain pending. This batch changes Mac sources only; no iOS implementation or
App Store version changed. README features, platforms, setup/build commands,
dependencies and limitations were reviewed before packaging this local preview.

The preview 48 DMG was mounted read-only; the copied-out app passed strict deep
signature verification, displayed pending recovery, and exported exact retained
bytes. The seeded private record was backed up to `external-move48-ui-record.json`
and removed afterwards, leaving the original and vault copy intact. The download
matched SHA-256 `b3db89a3d97581d3e36e9d824031ebbce1939e4e5e85bd77d8d076e71a34c1d4`.
Both web preview routes returned HTTP 200. Evidence: `delivery-build48.json`,
`native-move48-recovery-installed.png`, `native-workspace48-installed.png`. This is
a local, non-notarized intermediate build; full parity remains in progress.

## Preview 49 — native code syntax colours

Fenced code renders with lexical colours for comments, strings, keywords, numbers
and language-specific tokens. The pass recognizes the desktop language choices
(Shell, CSS, HTML/XML, Java, JavaScript/React, JSON, Markdown, Python, Rust, SQL,
Swift, TypeScript/React and YAML), plus common language-name aliases. Separate
adaptive light/dark text palettes improve readability on native code cards.
Only foreground attributes change: fonts, source text, Markdown metadata, fence
spelling, selection and Undo semantics remain owned by the existing editor.
Typing refreshes token colours in the affected document’s code blocks.

All 140 Mac tests pass (`code-colours49-tests-final.log`). The existing real editor
preservation test now checks distinct keyword/string colours before and after a
Unicode edit, native Undo/Redo, LF/CRLF fences and surrounding prose preservation.
A renderer-boundary test covers JSON, Python, HTML and SQL token distinctions,
quoted comment markers, neighbouring prose and unknown-language fallback without
pinning palette RGB values. UI editing changed only a Swift number from 42 to 73;
Command-S saved exactly that change and Undo restored the original bytes. Evidence:
`code-colours49-original.md`, `code-colours49-ui-edited.md`,
`native-code49-light-debug.png`, `native-code49-dark-debug.png`.
Dark QA used a temporary launch argument, leaving persistent appearance settings
unchanged. The screenshot shows the final adaptive palette.

This is basic lexical highlighting, not complete CodeMirror grammar parity.
Complex interpolation, raw/nested syntax and full grammar fidelity remain pending.
Unknown language names and code ranges above 100,000 UTF-16 units retain plain
native code styling; editing and serialization stay available. Large-document
performance, keyboard/selection, IME and accessibility acceptance remain open.
No iOS sources or App Store version changed. README features, platforms, setup,
commands, dependencies and limitations were reviewed before local packaging.

The preview 49 DMG was mounted read-only and its copied-out app passed strict
deep signature verification. The installed app saved exactly the intended Swift
number edit and Undo restored the original Markdown bytes. Light and dark
appearances were checked in that app, which was then relaunched normally in light
appearance. Download SHA-256: `2e54ba9cdedd9e131d4cea20be9dcd6bfb5b46b2e9f6ab8ad2ac6ba243de2de4`.
Both web preview routes returned HTTP 200. Evidence: `delivery-build49.json`,
`code-colours49-installed-edited.md`, `native-code49-light-installed.png`,
`native-code49-dark-installed.png`. This intermediate build is not notarized.

## Preview 50 — reviewed legacy relation repairs

Settings → Repair relations now runs the shared maintenance planner in the vault
actor. The review lists inferred folder definitions and inverse-scope changes,
expandable per-note line diffs, and unresolved cases. Applying updates only the
reviewed changes; ambiguous/missing targets stay unchanged. A successful screen
keeps unresolved issues visible and prevents applying the same review again.

Mac application guards bind the plan to the original workspace activation,
reject changed notes/schema/inventory, and check private retained draft locations
inside transaction validation. Clean windows on the same open vault are held
while writing and adopt the repaired notes, inspector and schema together.
Workspace switching, closing and editor changes are blocked during application.
Adoption invalidates older background refresh and metadata/inspector reads so
stale results cannot replace the repaired state.

All 142 Mac tests pass (`relation-repair50-tests-final.log`). New workspace tests
cover inferred definitions and reciprocal values in two open windows, original
body/foreign YAML preservation, unresolved-note preservation, repeated/stale
reviews, outside source edits, retained private drafts and reopening the same
vault. Native UI reviewed the summary and source diff, applied a repair to the
owned QA vault and showed the reciprocal field in the target note. Exact checks
confirmed unchanged unsafe notes and preserved unknown schema metadata. Evidence:
`relation-repair50-ui-originals.json`, `relation-repair50-ui-proof.json`,
`native-repair50-review-debug.png`, `native-repair50-diff-debug.png`.

Broader definition maintenance, ambiguous-schema recovery, cross-process/provider,
large-vault, keyboard and accessibility acceptance remain pending. No iOS sources
or App Store version changed. README features, supported platforms, setup/build
commands, dependencies and limitations were reviewed before local packaging.

The preview 50 DMG was mounted read-only and the copied-out app passed strict
deep signature verification. The packaged app reviewed and applied a repair in a
second owned vault, opened the inferred relation picker with Fleet selected, and
displayed the reciprocal Feedback value in Fleet. Exact checks confirmed body,
foreign YAML, unsafe-note and unknown schema-metadata preservation in both QA
vaults. Download SHA-256: `7553ed6c9c83de3b1f93fe1748df9488ea54df51bad11f8a84daf6e1faf9e768`.
Both preview routes returned HTTP 200. Evidence: `delivery-build50.json`,
`native-repair50-review-installed.png`, `native-workspace50-installed.png`.
This intermediate DMG is not notarized; full feature parity remains in progress.

## Preview 51 — reviewed folder property maintenance

Folder properties now uses a frozen definition/note snapshot and a separate
review for create, update, rename and removal. Reviews describe affected folder
definitions (including inverses) and provide expandable note diffs before applying.
Ordinary unchanged definitions remain byte-preserving no-ops. List choices use
one row each, retaining commas in a choice name. Relation forms load and expose
both hidden and inverse-hidden flags; shared migration retains pair identity and
unknown metadata. Unsupported definitions stay read-only. Definition selectors
are exposed as named native buttons, with visible selection state.

Both ordinary and relation reviews now use the same guarded Mac schema-maintenance
transaction and open-window adoption as relation repair. Ordinary scope reads
include currently empty values, so values added after review cannot silently
escape removal or conversion. Stale note/schema/inventory and workspace changes,
and retained private drafts, prevent writes. Child-owned overrides remain intact.

All 145 Mac tests pass (`schema-maintenance51-tests-visibility.log`). New workspace
coverage exercises literal comma choices, no-op saves, rename, multiple-to-single
conversion, ordinary and paired removal, hidden/inverse settings, pair identity,
unknown metadata, foreign YAML/body preservation, child overrides, outside schema
changes, newly populated fields, private drafts and reopening the same vault.

The previous preview 50 app independently reproduced unchanged-save regressions
in an owned QA vault: Alpha,beta became two choices, and hidden relation/inverse
flags reset to false. Evidence: `schema-maintenance51-baseline-comma.json`,
`schema-maintenance51-baseline-visibility.json`. Native UI in the new build showed
literal choice rows, a disabled no-op Apply action, reviewed and applied ordinary
and paired renames, preserved visibility, and a two-note removal review. Removal
was cancelled in UI; actual removal/conversion ran in integration tests. Evidence:
`schema-maintenance51-ui-originals.json`, `schema-maintenance51-ui-proof.json`,
`native-schema51-choices-debug.png`, `native-schema51-rename-diff-debug.png`,
`native-schema51-visibility-debug.png`, `native-schema51-removal-debug.png`.

Broader malformed-schema handling, inherited/paired migration edge cases,
cross-process/provider interruption, large-vault, keyboard and VoiceOver acceptance
remain pending. This batch changes Mac sources only; no iOS implementation or App
Store version changed. README features, platforms, setup/build commands,
dependencies and limitations were reviewed before this local package.

A packaged check exposed populated hidden relation fields still appearing in the
inspector (`schema-maintenance51-hidden-baseline.txt`). The inspector now applies
effective visibility to populated fields as well as empty definitions; values
remain stored and editable through folder-definition visibility controls. Choice
row QA also verified adding/removing first and last unsaved rows, rejecting an
empty choice list before review, and activating named definition controls. The
full 145-test suite passed again after the inspector change.

Final preview 51 DMG was mounted read-only, copied out, signature-verified and
launched against a fresh owned QA vault. Installed UI applied Stage and Contact
renames, retained literal checked choices, and hid populated source/inverse
relations while preserving stored values and exact foreign YAML/body. Screenshots:
`native-workspace51-installed.png`, `native-schema51-choices-installed.png`,
`native-schema51-diff-installed.png`, `native-schema51-visibility-installed.png`.
The private downloaded DMG matches the local SHA-256 in `delivery-build51.json`;
both frontend and private preview routes returned HTTP 200. This local package
is not notarized, and full feature parity remains in progress.


## Preview 52 — reviewed bulk move Undo

Every successful bulk move now saves a receipt in `.zerus/mac-move-history/`
within its coordinated file transaction. Partial batches update the same receipt
only for completed moves. Organization history and move results expose a separate
Undo review showing original paths and expandable note diffs. Undo restores the
original note bytes, relation definitions and link records together; attachment
files stay in place. Original creation dates are retained when available. The
receipt is marked undone in the same transaction, preventing repeated Undo, and
remains available after reopening the vault. Receipts contain original note text
and follow the vault's own storage/sharing policy.

The current exact restoration requires the post-move note inventory and content
to remain unchanged. Later note edits, occupied original paths, changed schema or
link settings, retained private drafts, stale reviews and changed vault activations
block Undo without writing. A fresh ordinary move can relocate edited notes;
merging later work into Undo and move Redo remain pending. New and in-progress
moves hold clean peer windows and refresh/remap their tabs and navigation together.
This batch changes Mac sources only. No iOS build number or App Store artifact
was changed. README features, platforms, setup/build commands, dependencies and
limitations were reviewed before packaging.

All 147 native tests pass (`move-undo52-tests-final.log`). The owning move
workflow now verifies a durable, exact inverse of note/link/schema changes,
original creation dates, unchanged attachment bytes, open-window remapping and
one-time application. New conflict coverage protects later edits, occupied
paths, changed shared settings, stale reviews, private drafts and same-root vault
reactivation. A partial-batch fixture modifies the second source through the
real progress callback and proves only completed moves enter the receipt and
can be undone after reopening. Native debug UI moved two notes and displayed
the incoming-link restoration diff (`native-move-undo52-review-debug.png`).

Final local DMG mounted read-only, copied out and passed strict deep signature
verification. The installed release opened the debug-created two-note receipt
after restart, showed its reviewed incoming-link diff, completed Undo and showed
Undone in Organization history. Independent file checks matched every original
note and schema byte-for-byte and confirmed both moved paths were gone. Evidence:
`move-undo52-ui-proof.json`, `native-move-undo52-history-installed.png`,
`native-move-undo52-review-installed.png`, `native-workspace52-installed.png`.
The private downloaded DMG matches the local SHA-256 in `delivery-build52.json`;
frontend and private proxy both returned HTTP 200. The DMG is not notarized,
and complete feature parity remains in progress.


## Preview 53 — file contents in global search

Desktop global search now indexes readable PDFs and UTF-8/BOM-marked UTF-16
text/source files, retaining native file targets, folder/date filters, matching
excerpts and full-context Ask AI preparation. Filenames and notes become searchable
before content extraction finishes. Four coordinated reads run away from the
main thread and the vault actor, with cancellation and per-read timeouts. Each
read is bounded to 20 MB input and 2 MB extracted text. The index retains at most
32 MB of file text in memory and never writes a content index to the vault.
File extraction reuses the document reader with explicit search limits; chat's
existing 50 MB limits remain unchanged.

Unsupported, malformed, locked, scanned, over-limit and unavailable files remain
searchable by filename with a reason in their row and selected preview. Refresh
re-reads inputs and removes deleted files and stale content. Reads enforce vault
confinement and reject symbolic links and changed metadata. Old workspace epochs
cannot install an index into a different vault. Office and RTF extraction, OCR,
resource connections outside the vault, large-vault performance and full provider,
keyboard and accessibility acceptance remain pending.

All 148 Mac tests pass (`file-search53-tests-final.log`). The search model's primary
file-content workflow verifies PDF/Unicode body-only matches, file-hub preservation,
excerpts and filters, unreadable/oversized fallbacks, byte-preserving reads, fresh
Ask AI document context, file edits/deletions and stale workspace replacement.
An existing attachment limit assertion caught and verified correction of a changed
50 MB message; attachment semantics stay intact. Shared NativeSearchFile records
default to no content, so iOS keeps its existing filename-only behavior. All seven
iOS native search/external-search tests pass (`file-search53-ios-compat.log`).
Simulator verification uses the existing build number and production SwiftUI
identity; it does not archive or upload to TestFlight. README features, platforms,
setup/build commands, dependencies and limitations were reviewed before this
local package.

The updated iOS Simulator app was installed without changing its App Store build
number, opened in the Device panel and searched for Codec. The existing matching
note appeared and the keyboard was dismissed for inspection. Evidence:
`native-file-search53-ios-compat.png`. Desktop debug UI independently found a
query present only inside PDF/text bodies, displayed matching excerpts, opened
the PDF and retained an unreadable file by name with a diagnostic. All original
QA vault file bytes remained unchanged.

Final preview 53 DMG was mounted read-only, copied out, signature-verified and
confirmed to contain bundle build 53. Installed UI reproduced PDF/text body-only
matches, opened the PDF, prepared its full extracted text for local AI review
without sending, and exposed filename-only diagnostics in both the result and
selected preview (including an accessibility hint). A real outside text edit
followed by Refresh removed the old match and found the new text; the original
fixture was restored and every original QA file matched byte-for-byte. Evidence:
`file-search53-ui-proof.json`, `file-search53-refresh-installed.txt`,
`native-file-search53-results-installed.png`,
`native-file-search53-fallback-installed.png`,
`native-file-search53-context-installed.png`. The private DMG download matches
the local checksum in `delivery-build53.json`. This local DMG is not notarized,
and full desktop feature parity remains in progress.


## Preview 54 — native Anthropic Messages connection

The Mac AI connection form now offers Compatible API and Anthropic. Existing
connections default to Compatible API. Choosing Anthropic from the standard
OpenAI endpoint selects its HTTPS Messages endpoint and clears the old model;
custom endpoints remain editable. Unsaved key text clears when the endpoint or
API format changes. Cancel keeps the prior configuration. A valid model and
context-window value are required before saving. Credentials remain in the
existing endpoint-specific Keychain entries, outside shared conversations.

A native Messages request builder separates system prompts, preserves ordered
user/assistant context, encodes JPEG images as base64 image sources and uses
`x-api-key` plus the pinned `2026-10-21` API version. It omits chat-completions
Authorization/choice fields. Output uses up to 4,096 tokens, bounded further by
the configured context capacity. The ephemeral no-redirect session and request,
image, text and stream limits remain in force. Compatible API and Messages share
a bounded SSE frame reader; their protocol-specific payloads remain independent.

Messages parsing supports text, separate returned thinking text, pings/unknown
future events and JSON fallback responses. Completion requires proper block and
message-stop transitions. Truncated, malformed, error, tool, output-limit,
context-limit and paused responses keep partial text rather than marking it
complete. No tool execution or extended-thinking mode is enabled. Stop and Retry
use the existing durable question/reply and portable attachment pipeline.

All 151 Mac tests pass (`anthropic54-tests-final.log`). New owning-controller
coverage captures real URLSession requests and verifies Anthropic headers,
protocol body, system separation, note/document/JPEG context, SSE and JSON text,
reopening and absence of credentials in history. Existing Stop/Retry coverage
now exercises both formats and preserves the same saved reply/turn identity.
A JSON output-limit fixture verifies partial text and subsequent Retry. Protocol
coverage checks Unicode, separate reasoning, unknown events, malformed ordering,
truncation, errors, tools and limits; existing compatible framing tests still pass.
These use synthetic HTTP fixtures, not a live Anthropic account or API credits.
Live Anthropic account/model acceptance, tools, extended-thinking controls, model
discovery, provider profiles/OAuth and complete AI parity remain pending.

Protocol references checked during implementation:
[Messages](https://platform.claude.com/docs/en/api/http/messages),
[streaming](https://platform.claude.com/docs/en/build-with-claude/streaming),
[API versions](https://platform.claude.com/docs/en/api/versioning), and
[vision](https://platform.claude.com/docs/en/build-with-claude/vision).
Native debug UI verified provider selection, endpoint defaults, missing-model
validation and cancellation retaining the original compatible connection.
README features, supported platforms, setup/build commands, dependencies and
limitations were reviewed before packaging. This batch changes Mac sources only;
no iOS App Store version or implementation changed.

Final preview 54 DMG mounted read-only, copied out and passed strict deep
signature verification; its actual bundle build is 54. The installed app launched
and selected the native Anthropic Messages form with its expected endpoint.
Evidence: `anthropic54-installed-form.txt`, `anthropic54-ui-proof.json`,
`native-anthropic54-connection-installed.png`, `native-workspace54-installed.png`.
No API key was entered and no live Anthropic request was sent during UI QA.
The downloaded DMG matches the local checksum in `delivery-build54.json`; both
web preview routes returned HTTP 200. This is a non-notarized local test package,
and full desktop parity remains in progress.


## Preview 55 — shared provider profiles and model discovery

The native connection sheet now stages independent OpenAI, Anthropic, OpenRouter
and compatible profiles. Models, endpoints and favorites restore when switching
providers. Explicit Save writes the existing shared version-1
`.zerus/ai-settings.json` format through a guarded file transaction, preserving
unrelated provider/unknown fields and native legacy connection data. Stale bytes,
unsupported formats and vault reactivation block an old save. Existing keys stay
in endpoint-specific Keychain entries; neither profile data nor discovery caches
contain API keys. ChatGPT account choice stays local and cannot be activated by a
shared cloud profile. Send/Retry resolve profiles from their own vault rather
than another open window’s global legacy settings.

Shared base URLs map to native chat-completions or Messages endpoints. Legacy
arbitrary Mac request paths use optional native metadata plus a local fallback;
other clients still require an API base URL they support. Local fallbacks are
keyed by vault, provider and model/endpoint identity. Native context capacity and
custom paths survive another client’s standard rewrite, which drops optional
native fields. Unknown fields are preserved by native writes; other clients’
existing normalization policies are unchanged. Malformed-schema, vault-folder
move and complete provider-interruption acceptance remain pending.

Load models is explicit, cancellable and separate from inference. The existing
no-redirect ephemeral HTTP client reads a bounded 4 MB page, up to 20 Anthropic
pages and 10,000 IDs; repeated/incomplete cursors fail rather than silently
installing a partial catalog. Provider authentication headers and response metadata
are handled independently. Only OpenRouter’s exact HTTPS public catalog route
allows an empty key and skips Keychain access. Other providers require an entered
or saved key. Model names/IDs can be filtered; manual selections are retained until
an explicit row choice. Supported reported context capacity is adopted on choice;
favorites stay in the selected provider’s shared profile. Endpoint/provider/key
changes invalidate old discovery results, and errors retain the manual model.
The form scrolls to keep controls usable with large catalogs.

All 154 Mac tests pass (`profiles55-tests-final.log`). Primary workspace/model
coverage verifies independent profiles, unknown fields, legacy migration, favorite
persistence, device-local ChatGPT choice, per-vault routing, stale/unsupported
writes, model pagination/authentication, manual entry preservation, explicit
selection/context, cancellation during real fixture HTTP reads, key changes,
sanitized errors, compatible metadata and keyless public catalog reads. Independent
regression baselines reproduced lost capacity and custom endpoints after a
standard profile rewrite (`profiles55-tests-capacity-baseline.log` and
`profiles55-tests-endpoint-baseline.log`); the owning model now retains both.
These private-provider tests use synthetic credentials and HTTP responses.

Native debug UI loaded 470 models from OpenRouter’s live public catalog without
credentials, retained the manual ID until explicit selection, chose/favorited a
returned model and saved it. The actual web `readSharedAiSettings` and
`writeSharedAiSettings` implementations read the native profile/favorite and
rewrote the owned QA file. Reopening native settings retained the model and
1,000,000-token capacity despite removal of native optional fields. A separate
Anthropic profile was saved; the other providers, favorites and device-local
selection remained intact. Evidence: `profiles55-native-output.json`,
`profiles55-web-roundtrip.json`, `profiles55-web-compat.json` and
`native-profiles55-models-debug.png`. No inference or API-key entry occurred.

Protocol references:
[Anthropic models](https://platform.claude.com/docs/en/api/models/list),
[OpenRouter catalog](https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties).
Private live account/model acceptance, provider OAuth, tools, extended-thinking
controls and complete feature parity remain pending. README features, supported
platforms, setup/build commands, dependencies and limitations were reviewed before
packaging. This batch changes Mac sources only; no iOS build or implementation
changed.

Final preview 55 DMG mounted read-only, copied out, passed strict deep signature
verification and confirmed bundle build 55. Installed UI restored the saved
Anthropic profile and independent OpenRouter model/favorite/context, then loaded
and filtered 470 live public catalog models without a key. Evidence:
`profiles55-ui-proof.json`, `native-profiles55-saved-installed.png`,
`native-profiles55-models-installed.png`, `native-workspace55-installed.png`.
The downloaded DMG matches the local checksum in `delivery-build55.json` and both
web preview routes returned HTTP 200. No inference or API-key entry occurred.
The local DMG is not notarized; full feature parity remains in progress.

## Preview 56 — native multiline quoted paragraphs

Quoted paragraphs now render as complete Markdown paragraphs through Apple's text
system. Explicit and lazy continuations retain their quote depth, including nested
quotes and bold/italic spans that cross physical lines. Unchanged source tokens,
LF/CRLF endings and hard-break spelling round-trip exactly. Editing emits explicit
quote prefixes on each changed paragraph's lines, preserving portable CommonMark
structure. Return continues the quote and an empty Return leaves one quote level;
paragraph formatting and native Undo/Redo retain the surrounding document.

The source-mode gate now follows Markdown list structure as well as physical
prefixes. Lazy list continuations, additional paragraphs within list items, and
headings/quotes embedded inside list items stay in source editing until their
native ownership and indentation behavior are implemented. Ordinary marked nested
lists, checklists, quoted headings and separate quoted paragraphs remain native.
Full editor and application feature parity is still pending in the tracker above.

All 155 Mac tests pass (`quotes56-tests-final.log`, 18.280 seconds). The primary
multiline-formatting test covers both lines, quote depths 0–2, explicit/lazy
prefixes, LF/CRLF and soft/two-space/backslash breaks, then parses saved Markdown to
check styles and quote depth, reopens it and verifies Undo/Redo. Native Return and
block-formatting owners cover continuing/exiting quotes and converting a quoted
line to prose. The workspace owner verifies actual note-open mode and that source
editing saves the intended bytes without changing other syntax. The quote feature
regression failed before the renderer change (`quotes56-baseline.log`); the earlier
unsafe-opening regression reproduced six failures before structural source gating
(`containers56-baseline.log`). README was reviewed and updated for this preview.

Installed-app verification: preview 56 DMG mounted read-only (CRC `213957E3`),
its copied-out app passed strict deep signature verification and reported bundle
build 56. The installed app opened the multiline quote in rich text and the
unsupported list example in source mode. Editing the second quote line retained
bold formatting, save/Redo wrote identical bytes, and native Undo restored the
exact original cross-line Markdown spelling. Reopening and rich/source switching
left the saved file intact. The web dependency `remark-parse` independently
confirmed nested quote depths, strong/emphasis runs and the hard break in the
actual saved file (`quotes56-web-compat.json`). Other note files stayed byte exact.
Screenshots: `native-quotes56-rich-installed.png`,
`native-quotes56-outline-installed.png`, `native-quotes56-source-installed.png`;
receipt: `quotes56-ui-proof.json`. The private download checksum matches the local
DMG (`delivery-build56.json`):
`2d6606ea9e4b00aa9e39ea4b090ae13753e2c003e11f9089605dce38eb0dde07`.
This is an ad-hoc, non-notarized intermediate build; no Windows/Store, production
updater or iOS release was created.

## Preview 57 — native list paragraphs and source-stable Undo

Soft-wrapped list text now renders as one native item. Hard breaks and consecutive
paragraphs before child lists stay in that item as well. Editing, Tab/Shift-Tab,
checkbox changes from a continuation paragraph and Undo/Redo retain the item and
its descendant list. Unedited items preserve source spelling; edited items write
portable Markdown indentation for bullets, multi-digit ordered and quoted lists.
Paragraphs interleaved after child lists and embedded code/tables remain in source
mode; full feature parity is still pending. Complete keyboard/paste/IME acceptance
for these new containers also remains outstanding.

All 163 Mac tests pass (`preview57-tests-final.log`, 21.035 seconds). Regression
logs cover soft wrapping, loose-item movement, presentation-only run splitting and
checkbox display-font substitution. Source fingerprints now merge equal semantic
runs and compare only bold, italic and monospace font traits. Native AppKit layout
adds an unrelated glyph-font trait to the checkbox; it previously invalidated the
original paragraph cache after Undo. Temporary diagnostic logging was removed.

Actual native UI verification repeated second-paragraph editing, subtree Tab
indentation, checkbox toggling and three Undo operations, then saved the exact
original Markdown bytes. Redo restored exactly the previously verified edit. The
web parser confirms item depths [0,1,2], paragraph counts [1,2,1], one hard break
and the checked marker. Evidence: `undo57-native-proof.json`,
`loose57-web-proof.json`, `native-loose57-verified.png`. README was reviewed and
updated for this intermediate preview. Packaging uses the local, non-notarized
channel; no production updater, Windows/Store or iOS release is included.

### Acceptance tracker reconciliation after the preview 57 review

The list/filter row previously described existing native controls as pending
implementation. `MacFilterPanel`, `MacSharedFilters`, `MacSavedViewsMenu` and
`MacNavigation` implement typed values, date comparisons, all/any matching,
shared folder filter persistence, named views and subtype filtering. The current
159-test run includes passing workspace tests
`testDesktopFiltersSelectTypedValuesAndPersistLatestEditsAcrossCollections` and
`testNamedViewsApplyOverwriteRenameAndRejectStaleDeletionWithoutChangingNotes`.
This establishes those specific contracts, not complete acceptance of every filter
or view workflow. Progressive rendering and broader keyboard/accessibility,
provider and large-vault verification remain pending.

The editor source is frozen during Opus 5.5's repair re-review. After that review,
the corrected intermediate DMG still needs packaging and installed-release UI
verification. Computer Use access to Zerus Native was denied; static signature,
checksum and process launch checks do not substitute for that UI verification.
Full desktop feature parity, including remaining editor containers, custom
appearance/editor/pane settings, voice controls, agent/tools workflows, updater
migration and the acceptance clauses above, remains the migration objective.

### Artifact receipt verification

`native-macos-artifact.mjs` validates the actual copied-out app before DMG creation,
including signature validity and the requested ad-hoc/Developer ID channel. The
packager writes the receipt only after image verification and, for distribution,
after the existing notarization/stapling/Gatekeeper steps. Receipt generation
never claims installed UI acceptance.

The verifier was exercised on the copied-out local build 57, then on disposable
copies with a mismatched build number and tampered executable, plus a deliberate
channel mismatch. The valid app passes and all three negative controls fail at
the intended checks (`artifact-verifier-proof.json`). These are artifact-contract
checks, not approval of the withdrawn editor build. Both scripts pass Node syntax
checks. No notarization submission or new DMG build accompanied this change.

### Final preview 57 review follow-up

The fourth Opus 5.5 review reported no blockers in the deletion repair or packaging
integration. Its remaining medium case was one-column delimiter rows. Those five
forms were added to the owning test, reproduced 15 assertions on the previous
guard (`opus57-one-column-baseline.log`), and now pass with the expanded GFM
delimiter-row check. The independent footer word-count regression reproduced six
failures (`word-count-baseline.log`): the old raw whitespace count included
checkboxes, headings and table syntax. The footer now counts parsed Markdown
content, retaining link labels and inline-word boundaries while excluding control
syntax, image markup and destinations. Its bounded cache avoids reparsing the
same body during unrelated SwiftUI updates. All 163 native tests pass.

Packaging now creates a temporary, non-downloadable candidate, validates and
mounts it read-only, compares its signed executable to staging, and only then
publishes the final filename and receipt. Stale notarization results are removed
before submission. The receipt records the Git revision and dirty-worktree status
but explicitly says no exact source snapshot is recorded; clean release-source
provenance remains future distribution work. The mounted verifier was exercised
on an existing local image; the final corrected local build is the integration
check. No new notarization is requested. Installed UI verification remains pending
Computer Use access, and full feature parity remains incomplete.

### Corrected preview 57 artifact handoff

The corrected local build completed through the candidate-image pipeline
(`preview57-release-verified.log`). The first attempt correctly withheld the final
filename when receipt creation read the final path before promotion; the receipt
hash now reads the verified candidate. Image integrity CRC is `E80CE27A`. The
packager mounted the candidate read-only, verified its actual app signature,
identity/build/platform/arm64/minimum OS, and matched its executable hash against
staging before publishing the final image and receipt.

`artifact-preview-57-local.json` records build 57, macOS 26 minimum, arm64, ad-hoc
signing and no notarization submission. The private download matches its SHA-256:
`7176b970e674513031480845a53fd442cc79b8a2262e45ff0b1d51bfcfa36fc0`.
Final delivery evidence is `delivery-build57-final.json`. The current native suite
passes all 163 tests. Opus 5.5 reported no blockers on its final review; its
one-column delimiter follow-up was fixed directly with failing-before/passing-after
coverage. No corrected release UI interaction has been verified: Computer Use
returned “Computer Use was not approved to use Zerus Native.” Earlier development
UI proof does not replace that pending release check. The DMG is available as an
intermediate test artifact, not a full-parity production replacement.


## Development after preview 57 — native colour preferences

Settings now opens a Colours sheet with the seven web colour roles: accent,
links, editor/list text, editor background, list background, sidebar background
and sidebar text. Light and dark palettes are independently applied; System
appearance selects the active slot through SwiftUI's colour scheme. Each slot
can return to the existing Mac defaults. Named palettes can be saved, loaded
into the editable fields and deleted. Loading a saved palette does not apply it
until Apply palette is pressed. Values accept #RGB/#RRGGBB, and names are checked
for duplicate spelling ignoring case and invalid/empty input.

The local versioned preferences record uses `zerus.mac.themes` in UserDefaults,
independent of vault Markdown and the iOS preferences. Unsupported/damaged records
are retained and the controls explain the problem; an explicit reset is available.
This does not import or synchronize web themes. The approved white/purple Mac
design stays the default when no palette is installed.

Workspace/sidebar/list surfaces and foregrounds read a SwiftUI environment palette.
The AppKit editor recolours existing text without reloading the document, moving
the selection or registering an Undo operation. Link colour, insertion point and
editor background follow the active palette; fenced-code syntax colours retain
their existing styles. Marked text is left under AppKit's control until composition
finishes. System appearance, multiple windows and actual IME behaviour still need
interactive acceptance; these statements describe the implementation, not UI proof.

All 167 native tests pass (`appearance58-tests.log`, 22.078 seconds). The new
preferences owner test covers reload, independent slots, named palettes, invalid
and unsupported records and resetting one slot without losing the other. The real
NSTextView editor owner test changes colours around an ordinary edit in rich and
source modes, checks selection/Markdown/link/body/cursor/background/code colours,
and performs Undo/Redo across a return to default colours. Existing list, literal,
clipboard and workspace tests also pass.

This milestone has been submitted to Opus 5.5 for review. No new DMG or notarization
has been produced. Preview 57 remains the delivered package. Computer Use access
to the installed native app is still unavailable, so installed visual verification
is pending. Built-in presets, colour pickers, theme import/export and remaining
editor/pane preferences are still parity work. The private web preview remains
available for comparison; these native-only controls are not added to the web app.


### Appearance review repairs before packaging

Opus 5.5 reproduced code-card overpainting and full-note attribute/layout work on
each keystroke. It also identified a palette request lost while marked text was
active, and an upgrade path missing for colour roles. Native regression checks
failed first (`appearance58-review-baseline.log` and
`appearance58-drawing-baseline.log`), including a bitmap check of the real
NSViewRepresentable editor's continue-writing label. This is an offscreen unit
render, not installed-app visual acceptance.

The editor now paints its writing surface before the code cards and keeps
NSTextView background filling off. Code cards have their own system writing
surface so their system syntax colours remain legible on a custom editor colour.
Per-editor dynamic text/link colours are shared by typing attributes and Undo
snapshots. Palette changes invalidate display; ordinary typing does not recolour
untouched paragraphs. Whole-text colour installation is confined to loading and
explicit document/Undo operations. A request received during composition is
remembered and retried by the native unmark/committed-input callbacks. Actual IME
keyboard acceptance remains pending despite the marked-text regression check.

Palette serialization now writes role-keyed objects and still reads the early
alternating-key/value development format. Missing roles fall back to their Mac
colours; unknown role values survive reload and encoding. Unrecognized document
versions and damaged data remain protected. Default swatches composite system
colour alpha onto the corresponding writing/sidebar surface. The Colours sheet
opens on the active light/dark slot and retains unapplied field edits while
switching slots. Built-in presets, richer controls and installed visual acceptance
remain outstanding.

## Development after preview 57 — durable move Redo

Bulk move receipts now support a reviewed forward replay after Undo, available
from the original results and Organization history. The review shows each forward
path and note diff. Redo reconstructs the exact pre-move note hashes from the
receipt's original file bytes; all notes, shared settings, occupied paths and the
receipt state are frozen through the coordinated commit. It reuses the same
cross-window dirty/retained-draft and vault-activation checks as Undo. Successful
Redo remaps every open vault window's tabs, selection and navigation, restores the
original creation dates, and preserves attachment bytes in place. A second Undo
can follow Redo. Receipts from partially completed batches replay only the notes
that actually moved.

The existing move owner tests now cover the exact forward note/schema contents,
paired relations and incoming/resource links after Undo/Redo, creation dates,
multiple windows, repeated operations and restart recovery for a partial batch.
The hazard table exercises both directions with later note edits, occupied paths,
shared-setting changes, stale review edits, private recovery drafts, a reopened
vault and a dirty peer window. Later edits are deliberately blocked rather than
merged. Installed UI acceptance remains pending; this is still not full migration
parity or a production release.


### Current development verification

All 169 native tests pass after the appearance repairs and move-history changes
(`preview58-tests-final.log`, 27.361 seconds). The code-card bitmap fixture was
visually inspected (`appearance58-code-card-unit.png`): its language/continue
label and syntax text remain visible on the custom writing surface. This fixture
is an offscreen native editor unit render, not an installed-app screenshot.
The move Redo milestone has been submitted to Opus 5.5 before packaging. Preview
57 remains the downloadable DMG until that review is resolved and a new local
package is created. No notarization, iOS build, Windows release or production
publication was performed for this development batch. The private web comparison
preview responds through both the frontend and Tailscale Serve `/app` routes.


### Native presets and colour pickers

The Colours sheet now includes the 11 existing web/Apple preset palettes and
AppKit-backed SwiftUI colour pickers alongside the hex fields. Presets fill the
fields before Apply palette; they do not replace the default Mac appearance
unless explicitly applied. All 77 role values were compared with the actual web
`THEME_PRESETS` export and matched (`theme-presets58-cross-client.json`). A named
palette can be explicitly updated through the Update palette action. Built-in
names are reserved for the built-in choices; previously saved records are retained.
The preferences owner test covers update-versus-accidental-duplicate behavior and
reserved names. All 169 native tests pass (`theme-presets58-tests.log`, 25.495
seconds). This does not establish installed colour-panel or whole-app UI acceptance.


### Move Redo review repairs and preview 58 preparation

Opus 5.5 found no overwrite path and confirmed existing/partial receipt replay by
tracing, but identified unnecessary BOM/draft blocks and fragile history loading.
The primary file-actor regression now reproduces unchanged BOM bytes and an
unrelated private draft without editor autosave affecting the scenario. Together
with a damaged neighbouring receipt, the pre-fix owner run failed three cases for
the intended reasons (`move-redo58-review-baseline-owner.log`).

Unchanged note guards now use their raw bytes, preserving a BOM rather than
re-encoding scanned strings. Private draft checks cover only notes whose bytes
would change, both before the review and inside commit coordination. Live dirty
vault windows still block the operation because snapshot adoption must not replace
their unsaved text. Receipt writes are limited to Markdown notes and the shared
properties/links JSON files, and settings diffs are shown alongside note diffs.
Malformed neighbouring receipts are preserved and reported while valid entries
remain visible. History loading captures its file actor before awaiting and
rejects an obsolete vault activation without force-unwrapping the current actor.
The history caption explains that later vault edits can block older receipts.

The hazard owner now verifies expected error reasons, includes a symlinked path
occupant that scan skips, rejects an unreviewed non-note receipt path and checks
that affected private drafts also block preparation. All 170 native tests pass
(`move-redo58-review-fixed.log`, 26.438 seconds). The history registry contains
weak workspace references; these tests create stores, not visible NSWindows.
Large-vault coordination and installed UI acceptance remain pending. These small
review repairs were implemented and checked by the parent, without an additional
review delegate. The README was reviewed against current native features, platform,
setup/build commands and limitations before preparing local preview 58.


## Preview 58 — themes, Markdown fidelity and durable move Redo

Local preview 58 packages the preceding development changes: heading/literal
spacing preservation, light/dark colour palettes, native colour pickers, 11
presets, named palette updates and reviewed move Redo. It retains the approved
white/purple design by default. Opus 5.5 reviewed the appearance and move-history
milestones; the reported issues were repaired with owner regressions. The last
full native run passed 170 tests (`move-redo58-review-fixed.log`, 26.438 seconds).

`pnpm desktop:build --native --local` completed successfully
(`preview58-release.log`). The packager mounted the actual DMG read-only and
verified its app identity, build 58, macOS 26 minimum, arm64 architecture, ad-hoc
signature and executable hash before finalizing the image. Its private HTTPS
download returned HTTP 200 and exactly the same SHA-256 as the packaged file.
The DMG is 8,421,860 bytes; SHA-256:
`6e75266990807e1b31c8682b95ac8377a89e11000afe6f0c17beb8fea2df170c`.
Evidence: `artifact-preview-58-local.json` and `delivery-build58.json`.

Download: [Preview 58 local DMG](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.34-preview-58-arm64-local.dmg).
Both the frontend and private Serve `/app` comparison routes returned HTTP 200.
No notarization or production publication was performed. Installed-app UI remains
unverified because Computer Use access to Zerus Native was not approved. The
native editor bitmap check is not a substitute for that acceptance. Full IME,
large-vault, provider, agent/tools, voice and remaining editor/pane parity work
remain open; preview 58 is not completion of the migration goal.


## Development after preview 58 — writing width and column alignment

Settings → Editor now exposes the existing desktop writing-column choices:
100%, 85%, 75% and 60%, with Left or Center placement. Width is relative to the
available writing area after the Mac's existing side insets. The approved native
100% default is retained; the web's current default is 75%. Alignment defaults
to Center, which has the same origin as Left at 100%. Invalid stored choices
fall back to 100%/Center without changing the stored value. Preferences are local
UserDefaults keys `zerus.mac.noteWidth` and `zerus.mac.noteAlignment`.

The real AppKit text view sets its text container width and origin while keeping
the scroll/document view at the full viewport width. Window changes recompute
the column during layout. The document and paragraph attributes are not replaced,
and changing layout does not create an Undo entry. Code cards, images and their
controls use the same container/origin; image resize dragging now takes its
maximum width from the writing container. Existing image attachments scale their
presentation to the proposed line fragment. Both rich text and source mode use
the writing-column preference, including external-note editors.

All 171 native tests pass (`note-layout59-tests.log`, 27.417 seconds). The new
owning test hosts the actual NSViewRepresentable editor with SwiftUI State and
an isolated AppStorage suite. It changes width/alignment through the persisted
preferences, measures the actual text container and origin, checks character hit
testing and caret/document preservation, resizes the host window, tests invalid
preferences, reopens an editor and performs Undo/Redo in rich/source modes. The
existing code-card native rendering test now shares that real-host fixture; all
prior tests still pass. The final caption cleanup changes only explanatory text.

Interface zoom remains a separate gap: the web scales the whole interface and
reflows to the available viewport. Scaling only editor fonts would not provide
that behavior. Native pane minimum sizes and compact-window behavior need to be
handled with the full-interface implementation. Inspector visibility is already
persisted per vault; the web's separate Properties Pane controls still need a
complete comparison. No new DMG was produced for this smaller development batch.
Preview 58 remains current, and installed UI/IME acceptance remains pending.


## Development after preview 58 — shared properties pane

The inspector now uses the existing web `.zerus/properties-pane.json` file for
Properties, Revisions, Relations, Outline and Attachments. Native headers expose
collapse/expand, drag reordering and Move up/down menus; Settings → Properties pane
uses the same controls and provides Reset and Refresh. Automatic history remains
available in the Revisions section rather than a sixth Mac-only layout field.
The default section order matches the web contract. Explicit width choices still
retain the approved Mac full-width writing default described above.

Each intent reads the latest settings before writing through a guarded vault
transaction. Collapse updates do not replace an external order change, and moves
operate on the current order. Duplicate/invalid array entries normalize like the
web while future string section IDs and unrelated JSON fields survive native
writes, including Reset. An invalid/unreadable JSON file is preserved and reported;
Refresh can load a repaired file. Valid pane contents remain usable while header
changes are unavailable. Settings are not stored in note bodies.

Successful writes publish to all windows in the same vault. A pane revision guard
prevents an older metadata read from replacing a newer layout. Actions capture
the workspace activation and reject obsolete vaults; pane writes prevent vault
switching or window close until the change finishes. Note drafts are not saved
or replaced by pane-only changes. External settings are adopted during refresh.

All 173 native tests pass (`properties-pane59-tests.log`, 27.503 seconds). The two
workspace owner tests exercise actual coordinated writes and cross-window state,
latest external settings, reset/restart, foreign fields/future IDs, unchanged note
bytes, malformed-file preservation and old-activation rejection. A mixed-array
baseline first failed six assertions (`properties-pane59-baseline.log`); parsing
was repaired to filter individual entries instead of rejecting the whole array.
Native drag gestures and installed/keyboard/accessibility visual acceptance are
still pending; these tests exercise the underlying actions and persistence, not
the physical drag interaction. The pane and writing-column milestone has been
submitted to Opus 5.5 for review. No new DMG or notarization was produced here;
preview 58 remains the delivered package.

A separate offscreen SwiftUI/AppKit framework probe investigated full-interface
zoom without changing app code (`zoom-probe/main.swift`, `zoom-probe/result.json`).
At 80%, 100% and 150%, a 100-point native rect converted to 80, 100 and 150 host
points, the logical text viewport reflowed, and first-glyph hit testing remained
correct. This supports using native coordinate scaling; it does not establish a
complete zoom feature. The app's multiple pane minimum widths, compact navigation,
sheets and native toolbar still need an implementation that stays within the
visible viewport. Editor-only font scaling would not meet the existing desktop's
full-interface zoom behavior.


### Pane/layout review repairs

Opus 5.5 found no pane-file data loss or cross-vault disk write path, but traced
late UI publication to a peer already switching vaults and heading scrolling
before a text container's width had caught up with its frame. Pane operations now
capture each participant's activation and pane revision, and apply success, error
and flag cleanup only while that ownership still matches. Vault opening rechecks
pending pane work after its save/filter/task waits; activating a new vault clears
the old pane state. These guards were repaired from the traced interleaving; a
fully controlled cross-window switching race is not claimed as reproduced.
Stale-activation errors are now distinct from busy-operation errors. Busy/closing
windows disable pane action buttons and reject drops.

Writing width updates synchronously with a real frame-width change. Initial
frames at or below the existing side insets keep their prior container rather
than forcing a 1-point layout. The real-host owner test now measures those states
before an explicit layout pass, which first failed four assertions. The image
drag owner uses native mouse handlers at 100% and 60% columns: dragging outward
at the display limit must leave a larger original saved size unchanged; shrinking
must match the displayed width and support Undo/Redo. That test first caught six
assertions where a 10-point padding mismatch silently replaced the image's larger
saved size. Both owners use the same SwiftUI State/AppStorage fixture as the
actual editing lifecycle. All 174 native tests pass after repairs
(`pane-layout59-review-fixed.log`, 28.500 seconds); failing evidence is in
`pane-layout59-review-baseline.log`.

Preservation here is bounded: native writes preserve unrelated JSON fields by
value and future string section IDs, not formatting, numeric spelling, invalid
non-string array entries, duplicate collapsed IDs or their ordering. The web
currently writes only its normalized order/collapsed object and can drop those
foreign fields. It also overwrites unreadable layouts with defaults, while the
Mac preserves them and requires an external repair followed by Refresh; native
Reset is disabled until the file is readable. Peers reached through different
case/firmlink paths and windows opened during an in-flight change may wait for
refresh. Physical drag gestures, installed UI, full IME and large-vault acceptance
remain pending. No additional delegate was started for these small review repairs.


## Preview 59 — writing columns and shared properties-pane layout

`pnpm desktop:build --native --local` completed successfully
(`preview59-release.log`). The README was reviewed against the current native
features, supported platform, build commands and limitations before packaging.
This local DMG adds writing-width/column placement and the vault-shared properties
pane controls described above, with the reviewed timing/image-cap repairs.
It keeps all features from preview 58 and the approved default white/purple look.

The mounted payload passed identity, build 59, macOS 26 minimum, arm64, ad-hoc
signature and executable-hash verification. The private HTTPS download returned
HTTP 200 and the same SHA-256 as the local image. DMG size: 8,458,976 bytes.
SHA-256: `2b5f0b4298f1bda8799b55cadbdb739d56607b2a196ba1081e4fc82d001762dc`.
Evidence: `artifact-preview-59-local.json` and `delivery-build59.json`.
Download: [Preview 59 local DMG](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.34-preview-59-arm64-local.dmg).

All 174 native tests pass. Opus 5.5 reviewed this milestone and its findings were
repaired by the parent; no additional review was claimed. The raw frame-width and
native image mouse-handler regressions failed first and pass after repair. A
controlled peer-vault-switch interleaving was not reproduced, so ownership guards
are not presented as complete installed lifecycle acceptance. Physical pane drag,
installed UI and full IME checks remain pending. Full interface zoom, provider/
agent/tools/voice workflows and the broader parity tracker remain open. Both web
comparison routes respond HTTP 200. No notarization or production publication,
Windows release, Store build or iOS build was performed for this local preview.


## Preview 60 — compact workspace and loading repairs

The main window now permits 600 × 620 points while retaining the approved
1400 × 850 default. The scene uses content-minimum resizing. Note layouts keep
inline panes only when their minimum widths fit: the inspector and library become
reachable through drawers, and single-column mode provides Notes / Back to note.
Selecting the current note reveals its existing editor without saving/reloading
its private draft. Writing makes the note the active compact pane. Gallery
collections keep their flexible width when an editor is open.

The four-pane host keeps the native editor subtree mounted when neighbouring
panes collapse or notes-list browsing hides it. A hidden/covered editor becomes
read-only and releases its first responder; approved programmatic document
updates remain separate from direct typing. Drawer content can open the existing
property/history/image sheets without introducing another modal sheet. The
minimum writing width is bounded by the viewport, and the existing 46-point
insets and full-width default remain unchanged. Compact task filtering now uses
adaptive horizontal/vertical rows so Search, Sort, Category, Priority and older
completed controls remain reachable.

Vault loading now locks workspace input before awaiting saved notes, filters,
task writes and the new scan. It refuses overlapping switches or an active table/
code sheet. Already accepted late text is retained and checkpointed. A second save
checks for edits arriving during pending writes, and a note-edit revision guard
refuses a switch if writing arrives during the incoming scan. The prior pane
revision/activation guards remain in place. This change
was checked by ordinary lifecycle tests and read-only/first-responder tests; it
is not presented as exhaustive real IME or loading-interleaving acceptance.

All 178 native tests pass (`compact60-review-repairs-tests.log`, 29.784 seconds). The
real SwiftUI/native pane fixture checks 1400/980/650/500-point transitions,
visible pane bounds, the same NSTextView identity, caret, Markdown, Undo/Redo,
read-only hidden/covered state and first responder. The navigation owner covers
same-note draft retention and active-pane selection; its initial new assertion
failed before the writing-intent repair (`compact60-active-pane-baseline.log`).
The task UI owner reproduced a 30-point search field at 600 points before the
adaptive rows (`compact60-task-filters-baseline.log`) and checks input/control
bounds at 600/900/600. A focused run also enters a query through the real AppKit
field editor and verifies it survives both reflows
(`compact60-task-query-proof.log`, one test passed). These hosts use controlled
fixture stores; they do not restore or operate the user's live app/vault.

Opus 5.5 reviewed the milestone and identified hidden compact navigation, menu
loading guards, a late-edit discard path, drawer reconciliation and focus gaps.
The repairs keep tabs and back/forward visible whenever the note editor is hidden,
route the menu Inspector through the same inline/drawer decision as the toolbar,
and close stale inspector drawers on widening or changing tabs/selection. Done
supports Escape; covered content is hidden from accessibility. Menu actions are
locked while loading and note creation takes the workspace lock before awaiting.
Attachment/chat insertion checks its original vault and selected note. Async paste
checks editability after conversion and resource import; clipboard completion
restores both the editability and interaction settings. Focus resignation is
scheduled outside the SwiftUI update because it can commit marked text; restoring
an interactive editor returns its previous typing focus only if another control
has not acquired focus.

The loading regression failed on the previous code (`compact60-loading-baseline.log`),
showing a newly created note plus discarded writing without a checkpoint. Paste
and focus regressions also failed before their fixes
(`compact60-paste-focus-baseline.log`). Their owning tests now pass in the full
suite. These are controlled native hosts and store operations, not proof of the
installed toolbar/menu/drawer UI or real IME acceptance.

The desktop voice parity row was reconciled against `AiPanel.tsx` and the desktop
speech plugin: its dedicated speech-recognition commands report iOS-only. A new
Mac chat recording/provider flow is not required to match the current desktop;
real macOS dictation acceptance remains open.

Full interface zoom is still not
implemented or exposed: compact panes are preparation for scaling and reflow,
not editor-only zoom or a substitute for the full-interface requirement. Sheets,
other complex flows and installed compact gestures still need acceptance.
Computer Use access to the installed app remains unavailable: “Computer Use was
not approved to use Zerus Native”. Installed UI acceptance remains pending.
Preview 60 uses the local ad-hoc DMG channel, without notarization. Packaging and
private-download verification are recorded separately below.

### Preview 60 artifact verification

`pnpm desktop:build --native --local` completed. The mounted DMG payload passed
bundle/version/build, macOS 26+, arm64 and strict ad-hoc signature validation;
its executable checksum matches the verified staging app. The final image was
downloaded successfully through private HTTPS and its SHA256 matched the receipt.

Download: [Preview 60 local DMG](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.34-preview-60-arm64-local.dmg).

SHA256: `dd515a67131b87e9dc9a88002d23afeaee3689dcb00033085878140d8053cb54`.
Evidence: `artifact-preview-60-local.json`, `delivery-build60.json`,
`compact60-verification.json` and `preview60-release.log` under
`artifacts/native-macos/`. This is an intermediate non-notarized build. Installed
UI/IME and full migration parity remain pending. Both `/app` frontend and private
proxy routes returned HTTP 200; the web preview remains the web client.

## Preview 61 — whole-interface zoom

Settings now offers the same device-local percentages as the current desktop:
80, 90, 100, 110, 125 and 150. The default remains 100%; unsupported saved values
fall back to 100. `MacZoomViewport` scales the entire workspace while proposing
its physical viewport divided by the factor to the layout. The existing compact
panes therefore reflow at the new logical width. Native toolbar items use a
separate scaled layout because they live outside that SwiftUI canvas. Note fonts,
Markdown, images' saved dimensions and writing-column preferences are unchanged.
The formatting toolbar scrolls horizontally when it no longer fits. The External
Notes connection header can stack at narrow logical widths.

All 61 SwiftUI sheet call sites now use shared zoom-aware presentation overloads,
including item sheets and onDismiss handlers. The standalone Settings scene and
filter popover use the same presentation. Dialog content receives a finite viewport through an AppKit hosting controller,
with the layout proposed at the logical size for the current scale. Native scroll
magnification scales that content, and the outer scroll view only overflows when
the dialog's minimum size exceeds the available viewport. Inner lists/table grids
therefore retain their own bounded scrolling and laziness. The presentation follows
screen and parent-window position/size changes. Native sheets use
[Apple's fitted presentation sizing](https://developer.apple.com/documentation/swiftui/presentationsizing/fitted)
so flexible dialogs can resize; fixed-size dialogs retain their fixed dimensions. Native system menus, alerts, file pickers
and window chrome retain the Mac's system sizing.

The AppKit-created image edit/preview panels also use the shared presentation.
Their hosting roots receive the editor's environment, including its preference
store and theme, and their content size follows the zoomed presentation. A
regression test first reproduced both the missing scale and fixed-size panel at
150% and 80% (`zoom61-image-baseline.log`); the repair passes
(`zoom61-image-fixed.log`). The note-link completion and hover preview are native
subviews inside the scaled editor scroll view and inherit its coordinate scale.

Native host verification covers all supported percentages and an unsupported
stored value, native editor identity, text/selection/Undo, scaled list geometry,
checkbox clicks at 80%/150%, task filters at 600 points with zoom, separate toolbar
item geometry, form text retention, scrolling a real dialog footer into view,
and real Boolean/item sheet windows with inherited preferences and native dismiss
callbacks. These are isolated fixtures, not installed-app screenshots or an
end-to-end claim for every dialog. The image panel test uses a generated isolated
image and a private preference suite; it does not open the user's notes.

The first implementation passed 183 tests (`zoom61-verified-tests.log`) but Opus
5.5 found that its unconstrained measurement built every large-table cell and
collapsed flexible list/split dialogs. That implementation is superseded. Regression
probes reproduced 2,400 native cell editors for a 400 × 6 table and collapsed list/
split content (`zoom61-review-baseline.log`). A real table-sheet regression also
reproduced loss of native resizing (`zoom61-window-baseline.log`).

The replacement uses bounded fitting proposals, retains flexible min/max sizing,
and removes the initial 640 × 480 measurement placeholder and unconditional elastic
outer scrolling. At 100%, toolbar items use their original native content directly.
The editor now stores `context.environment` in its coordinator instead of subscribing
to the whole environment; open image panels receive subsequent context updates.
All 185 tests pass after these repairs (`zoom61-review-repaired-tests.log`, 42.111
seconds). A focused Opus review of the replacement dialog-hosting implementation
found additional live-sizing and environment defects; see the repair section below. The final Preview 61 artifact is verified below.
Installed toolbar/menu/popover/sheet behaviour, actual IME/dictation and broader
feature parity remain pending. Computer Use access remains unavailable; this
work does not bypass that restriction.

### Zoom review repair evidence and limits

The actual table-sheet owner checks that a 400 × 6 table creates fewer than 200
native cell fields, supports native window resizing, and retains an edited cell
and its view identity after growth. The flexible list/split owner checks a useful
viewport instead of a strip. The Boolean/item owner also opens and dismisses a
nested sheet, verifies exactly one zoom factor, and checks actual sheet bounds for
a lower-positioned parent. The earlier screen-position warning was traced; the old
wrapper also stayed within display bounds in this fixture, so that check is not
claimed as a reproduced positioning regression.

Two fixture assumptions were rejected during authoring: SwiftUI buttons need not
be NSButton instances, and a stored test-only dismiss closure is not guaranteed
to clear through onDisappear when a Mac sheet closes. The latter assertion also
failed with the previous pure SwiftUI wrapper (`zoom61-native-disappearance-baseline.log`)
and was removed; native onDismiss and actual sheet disappearance remain asserted.
The nested-sheet fixture observes its model directly, as production stateful sheets
do. These tests do not establish all production task/lease cleanup or installed UI
acceptance.

### Live presentation and appearance repairs

The second Opus review reproduced an open sheet failing to resize for live zoom,
width-only forms clipping actions when their own state grew, and stale SwiftUI/
AppKit appearance in the inner hosting root. New real-sheet regressions reproduced
all three (`zoom61-live-baseline.log`); the earlier fixed-size/before-opening tests
were insufficient for those contracts.

The hosting boundary now observes its full environment and re-sends it to the
inner content, including native appearance. The rich editor remains narrowly
subscribed to theme/interaction/colour scheme and forwards resolved context to an
open image panel. A bounded content-geometry notification schedules sizing outside
SwiftUI updates. For production presentation roots, native window sizing follows
live zoom and inner content changes, while retaining a larger manual user size
when it still fits. The same finite fitting policy keeps large tables lazy. Parent
observers rebind after sheetParent becomes available, rather than assuming it is
already known in viewDidMoveToWindow.

The real-sheet owner changes 100→150→100 while the title field is being edited,
checks the native window and footer bounds, grows/collapses inner @State content,
and checks field identity, text, caret and focus. The appearance owner switches
light→dark→light both with and without an inner preferredColorScheme, checking the
sheet, native text-field appearance and the inner SwiftUI colour scheme. The
focused set passed before the final full-suite run (`zoom61-live-fixed.log`).
No third review was requested for this repair batch; installed UI, actual IME/
dictation, multiple displays, and complete app parity remain pending.

### Final Preview 61 validation

All 188 native tests pass (`zoom61-final-tests.log`, 51.597 seconds), including
ordinary active text-field editing/caret/focus across live sheet zoom. The final
repair batch resolves the two Opus reviews' reproduced sizing/appearance defects;
there was no third review or installed-app acceptance. The Mac target now compiles
the unchanged platform-neutral agent core and includes its existing tokenizer
resources. A Mac bundle-boundary test loads the actual tokenizer and checks an
independent reference count. Agent workspace/provider/UI adapters and the five
remaining web tool classes are still pending; no agent tools are exposed to users
by this build. No iOS source was edited for that integration.

The README was reviewed for current Mac features, platform, commands, dependencies
and limitations before packaging. Preview 61 uses the local, non-notarized channel; its artifact/download
verification is recorded below.

### Preview 61 artifact verification

`pnpm desktop:build --native --local` completed successfully. The mounted payload
passed version/build, bundle identity, macOS 26+, arm64 and strict ad-hoc app-signature
checks. The final DMG was fetched through the private HTTPS download endpoint with
HTTP 200, and its SHA256 matches the packager receipt. The staging app's tokenizer
resource digest also matches its bundled metadata.

Download: [Preview 61 local DMG](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.34-preview-61-arm64-local.dmg).

SHA256: `81387d1c8aaa38df101c75d51ff03a3138efab8ed573f2e0bf8a581a2e03b36f`.
Evidence: `artifact-preview-61-local.json`, `delivery-build61.json`,
`zoom61-verification.json` and `preview61-release.log`. This is an intermediate
non-notarized build. Installed UI/IME and full migration parity remain pending.
The web preview remains the web client; both frontend and private proxy `/app`
routes are checked separately.

## Development after preview 61 — Mac agent workspace adapter

`MacAgentWorkspace` now binds a run to its original vault activation and physical
filesystem identity. Journal operations use the existing actor/expected-byte
ordering without holding window locks across provider calls. Note-sensitive
operations admit all windows for the same vault (including case/path aliases),
commit pending vault-note drafts before reads, and release their busy locks after
each operation. Applying a reviewed change refuses open drafts instead of saving
newer writing over the reviewed baseline.

The shared native engine still constructs proposals and receipts. The Mac commit
boundary retains its owner/journal and note-identity checks, then adds private
vault-note recovery checks and physical vault identity validation inside the
coordinated transaction. Successful snapshots reconcile peer windows without the
navigation helper that would unconditionally replace an active body. Pause/resume,
proposal rejection, reviewed Undo, request reservations and elapsed accounting
are available to the forthcoming Mac controller.

All 193 native tests pass (`agent62-verified-tests.log`, 53.119 seconds). The Mac
owner covers a peer draft being saved before the read result, staged Review changes
leaving bytes untouched, apply/receipt/Undo and peer reconciliation; open peer,
outside-file and retained recovery hazards preserving the journal; writing triggered
by operation admission remaining checkpointed; a case-alias window retaining its
draft; same-path reopen and directory replacement invalidating an old context.
The alias case ran successfully on this Mac's volume. Fixtures use temporary vaults
and close their workspace sessions before cleaning their private test drafts.

This is backend groundwork, not an exposed agent feature or completed tool parity.
Connected external-note editing/recovery has a separate draft store; its admission
and commit integration is described below. Provider tool transports,
chat ownership/lifecycle integration, native run/review UI and the five additional
web tool classes remain pending. Encoding compatibility (including UTF-8 BOM notes)
also needs a dedicated read/write boundary check. No new DMG or notarization was
produced for this internal batch; Preview 61 remains the delivered image.


### Connected-file draft admission (development, unpackaged)

The Mac adapter now receives the connected-file registry explicitly and checks
connections to each file a reviewed transaction will change. Active connected
editors are held during file operations. Read operations save their writing first;
approval refuses newer writing. The hold also prevents closing or replacing the
connected editor during the operation. Late editor callbacks can still checkpoint
their writing, and releasing the hold re-arms autosave when needed.

Closed connected editors retain their independent recovery drafts. Preparation
checks those drafts, and the coordinated commit reads and validates them again
before changing notes or the run journal. Saved bookmarks are resolved without UI
so a moved file's retained draft remains protected. Physical file identity also
matches aliases. Unrelated private drafts are not decoded, so an unreadable draft
for a different file does not prevent an otherwise valid approval.

The 11 focused Mac agent workspace tests pass (`agent62-connected-guards.log`,
2.065 seconds). They exercise connected-editor save/read/apply/refresh, active and
closed retained drafts, recovery arriving between preparation and commit, a moved
file, a clean connection with no draft record, and an unrelated unreadable draft,
alongside the existing vault-window, activation and transaction checks. The earlier
pre-fix run (`agent62-external-baseline.log`) failed the connected save and recovery
cases before the admission/commit repair. These are isolated file and workspace
fixtures, not installed-app or IME acceptance.

The serial full suite passed: 199 tests, zero failures, 53.219 seconds
(`agent62-connected-serial-tests.log`). The initial default run crashed in the
existing code-card drawing owner with a CoreText nil-object exception
(`agent62-connected-full-tests.log`). That owner passed in isolation and in the
serial full run without a source change; the intermittent crash remains unresolved
and its evidence is retained. The Opus 5.5 review completed; its follow-up is recorded below.
No new DMG or notarization has been produced; Preview 61 remains the delivered
image. Native agent UI, provider tool transports, the five additional web tool
classes, and the separate BOM encoding investigation remain outstanding.


### Opus draft-admission review follow-up

The review identified a bookmark gap after atomic replacement followed by rename,
a late-editor-callback window after successful reconciliation, and a connection
opening while the guard inventory was already being used. No data-loss path was
reported by the review; its bookmark and BOM observations came from standalone
probes, while the other paths were traced.

The moved-file owner now covers both a plain rename and atomic replacement before
rename. A new connected-editor owner performs a held refresh after a real file
save, delivers a late callback, then checks that the approved bytes remain on disk
and the callback text remains in a conflicting recovery draft. Both regressions
failed before repair (`agent62-review-baseline.log`). The focused agent/external
owners pass after repair: 18 tests, zero failures, 2.896 seconds
(`agent62-review-guards-fixed.log`). The final serial suite passes all 200 tests
with zero failures in 53.474 seconds (`agent62-review-full-tests.log`), including
the code-card drawing owner that crashed intermittently in the earlier run.

Dirty connected drafts now fail closed when their bookmark cannot resolve, or
when either their resolved or last-known location belongs to the vault. This is
intentionally conservative: an ambiguous retained draft can block another note's
approval until the connection is located or its draft resolved. Resolved connections
outside the vault remain unrelated. Bookmark resolution uses withoutUI and
withoutMounting. Preparation and commit still revalidate the guarded draft files.

Opening/presenting a connection checks a process-local operation hold, including
the interval while approval captures its guard inventory. Existing connected and
vault editors retain late callbacks as conflicts during their own holds; releasing
the hold cannot autosave such text over the approved result. A connected-file save
failure during admission now includes the underlying failure instead of reporting
all failures as newly arrived writing. These are small repairs following the review;
no additional delegate re-review was requested.

Remaining review limitations: a stale recovery baseline after a successful save
can still require the existing Reload original… action to clear it; malformed
registry data blocks approval; unavailable-volume filesystem access can still be
slow despite withoutMounting. The separate BOM investigation includes both vault
expected-byte mismatches and double-BOM draft classification. Installed UI, full
IME acceptance, provider tools and complete migration parity remain pending.


### ChatGPT native agent transport (development, unpackaged)

The Mac ChatGPT connection now accepts a prepared native agent request and returns
structured calls, text, reasoning and optional usage. Ordinary chat and agent turns
share the same account/model validation, catalog check and active-request lock.
The shared ChatGPT manager continues to own authentication, streaming and encrypted
reasoning continuation storage; the Mac layer does not rebuild those protocols.
A response containing calls and no text is valid for the agent path, while ordinary
chat continues to require a text answer. Calls are returned to the journal/tool
runtime; receiving them does not itself authorize or execute a file change.

`MacAgentRequest` prepares requests off the main actor using the linked tokenizer,
the run's frozen scope, mode, guidance, workflow, transcript and attachment grants.
It checks reservations and remaining input/output/total budgets before sending.
Frozen images are loaded from the native private attachment store. This Mac port
uses the existing native agent data/storage contracts without importing the iOS
controller or changing iOS source. `MacAgentCompletion` bounds and validates the
returned call IDs, argument objects, reply size and reported usage before they can
reach journal admission. Missing usage remains optional for runtime estimation.

The owning account-transport test starts a real isolated Ask run, prepares and
reserves its request, receives a tool-only response through the URLSession fixture,
saves it to the native journal, executes the declared read tool and returns that
result in the next provider request. It checks encrypted reasoning continuity,
call/result IDs, read-only tool advertisement, final journal usage/status,
unchanged note bytes and credential/context separation. It also checks an unfinished
reservation and a changed selected model prevent another send. Existing account
streaming/Stop/Retry and authentication tests still run through the shared lock.
The focused five account tests passed (`agent62-chatgpt-tools-tests.log`). The final
serial suite, including the added stale-model assertion, passed all 201 tests with
zero failures in 54.305 seconds (`agent62-chatgpt-full-tests.log`).

This does not expose an agent interface yet. Compatible-API and Anthropic agent
transports, the Mac controller, native run/review controls, the five additional web
tool classes, live provider acceptance and broader migration parity remain pending.
No DMG or notarization was produced for this internal transport batch.


### Compatible API native agent transport (development, unpackaged)

Saved compatible-API connections now have an agent transport alongside ordinary
chat. `MacCompatibleAgentRequest` maps the prepared run's scope-aware transcript,
function schemas, prior calls/results and frozen images to the chat-completions
wire format. It sends the output ceiling and requests streamed usage. API keys
remain Authorization headers. The transport uses the existing Mac client's
session and HTTPS endpoint policy rather than the shared iOS manager's global
connection configuration.

The bounded SSE reader assembles up to twelve indexed calls, including interleaved
argument fragments, and keeps reasoning separate from visible text. Usage may
arrive after the finish event. JSON responses normalize to the same completion
contract. A final stop/tool-calls reason is required before a completion can reach
the runtime; truncated or length-limited replies do not return executable calls.
Duplicate IDs, non-object arguments, unsupported field types, invalid choice
indices and invalid usage are refused. Cancellation preserves the already-saved
request reservation for the controller's interrupted-run accounting.

The API owner uses an isolated URLSession fixture and a real scoped native Ask
run. Both SSE and JSON paths return two read calls, execute them through the
journal and map their results back into the next provider request. It checks frozen
image bytes in the actual HTTP body, read-only tool advertisement, selected output
ceiling, usage, call/result IDs, unchanged note bytes and credentials outside the
journal. Separate cases cancel a partially streamed call and refuse malformed,
truncated and token-limited replies. The invalid JSON choice index and malformed
streamed tool_calls field failed before hardening
(`agent62-compatible-hardening-baseline.log`). All six focused API/ordinary-stream
owners pass after repair (`agent62-compatible-fixed-tests.log`, 0.188 seconds).
The final serial suite passes all 204 tests with zero failures in 53.124 seconds
(`agent62-compatible-full-tests.log`). An Opus 5.5 review of the combined ChatGPT
and compatible-API adapters is in progress; no acceptance claim is made from the
passing suite alone.

No iOS/shared source was edited and no live provider request was sent by this
verification. This is not an exposed agent UI or completed provider acceptance.
Anthropic agent transport, the Mac run controller, native run/review controls, the
five additional web tool classes and broader parity remain pending. Preview 61
remains the latest delivered DMG; this internal batch was not packaged or notarized.


### Provider review repairs and Anthropic agent transport (development)

The Opus provider-adapter review reported no high-severity issue. Its repeated-name
probe exposed a real compatible-server variant: resending note_get in successive
deltas produced note_getnote_get. The owning transport fixture now resends the
whole name; it failed before repair (`agent62-repeated-name-baseline.log`). Names
are set once and identical repeats are accepted. Malformed-wire cases now assert
both a captured HTTP request and the parser/completion error that owns each refusal.
The cancellation owner is named for stopping the transport and refusing partial
calls; assertions about reservation/note bytes that this adapter cannot modify were
removed. Reservation persistence still needs its real run-controller owner.

Optional null roles/usage, a usage-only trailer without choices, an unindexed
unambiguous single tool call and empty no-argument input now normalize without
losing a reply. Ambiguous call indexes still fail closed. Token-limit refusals now
state the reply/context limit. The optional-wire and caller-cancellation regressions
failed before their repair (`agent62-provider-review-baseline.log`). ChatGPT's size
limit now cancels a child provider task, preserving the parent task's ability to
record an error; user Stop still cancels the child through its cancellation handler.
The same bounded helper serves ordinary chat and agent responses. The Mac fallback
output estimator now requires reasoning text as well as final text/calls.

The new Anthropic adapter uses Messages API client tools and tool_result blocks,
following the current [tool contract](https://platform.claude.com/docs/en/agents-and-tools/tool-use/handle-tool-calls)
and [streaming protocol](https://platform.claude.com/docs/en/build-with-claude/streaming).
Requests use the documented 2026-10-21 version, output ceiling and saved effort.
It maps frozen images and merges parallel tool results into one user message. It
requires a complete message_stop with closed blocks before returning calls. Truncated,
length-limited, unsigned thinking and unrequested server-tool blocks are refused.
Raw signed thinking and redacted-thinking blocks survive in a separate private
continuation cache; normalized text, reasoning, calls and usage go to the journal.
Cache identity binds endpoint, model, credential digest and run UUID plus the full
transcript prefix. It contains no API key. Missing, unreadable, mismatched or
cross-connection continuations stop before HTTP instead of reconstructing a tool
history without its provider state. Files are private to this Mac and are not
portable continuation grants. Rotating an API key requires a new request/run for
an existing Anthropic tool history.

Anthropic usage updates replace cumulative output counts. Input accounting includes
reported cache-read and cache-creation input tokens. The SSE implementation bounds
aggregate block payload incrementally rather than re-encoding all accumulated
thinking on each delta. JSON replies normalize through the same block validator.
The isolated transport owner covers signed and redacted thinking, fragmented tool
input, two read calls, frozen images, cache-aware usage and grouped result/history
restoration through streaming and JSON. It also rejects changed model/key or a
corrupt cache before a send. A cancellation case verifies that no partial provider
continuation is written. No installed app, live provider, real account or user vault
was used in this verification. The pre-review suite passed all 209 tests with zero
failures in 58.679 seconds (`agent62-anthropic-full-tests.log`). The Anthropic Opus
review and subsequent repairs are recorded below.

Still pending: run-controller usage accounting/limits after provider replies, the
ChatGPT transport's approximate output ceiling and encrypted-reasoning context cost,
explicit request options for strict compatible servers/reasoning-model token fields,
call-ID reuse normalization, and extraction of duplicated pure request functions
from the iOS/Mac controllers. The latter touches shared iOS source and will require
the iOS Simulator preview workflow. Native run/review UI and complete tool/migration
parity remain pending. No new DMG or notarization has been produced in this batch.


### Anthropic Opus review: refusals, frozen context and cache lifecycle

The review found that a mid-stream refusal could return/cache partial text, and
that newly created note IDs changed the system prompt during signed thinking.
Both are repaired. Refusal is now a distinct typed failure and never returns a
completion or saves its blocks. The future run controller must discard any live
text when it receives that refusal type, following the provider's
[refusal contract](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/handle-streaming-refusals).
It must not automatically retry unchanged refused context or silently change the
selected provider/model.

Mac system prompts no longer interpolate mutable ID lists. Permissions remain
enforced by the journal/runtime; current targets are discoverable through tools,
and verified creations append runtime receipt messages. Each Anthropic continuation
also stores its exact original system text and restores it for the next request;
all restored turns must agree. This preserves the provider binding across real
Edit-mode creation/receipt and subsequent requests, rather than merely testing a
manually changed in-memory ID array. The owning regression failed against the old
wire (`agent62-anthropic-system-baseline.log`).

Nullable usage fields are treated as unreported. Null delta values do not overwrite
previously reported input/cache counts. The refusal and nullable-usage regressions
failed before repair (`agent62-anthropic-review-baseline.log`). Limit, pause,
stream-error and HTTP-status failures now have distinct descriptions, rather than
all becoming unsupported-block errors. No untrusted provider error body is echoed.

Cache writes create a same-directory temporary file as 0600 before writing, sync
it and rename it atomically. Existing binding directories are tightened to 0700.
The encoded cache-file ceiling is 16 MB, above the maximum escaped size of the
bounded raw blocks/system text, so JSON escaping does not reject an otherwise
accepted complete reply merely at the old 2 MB cache limit. Storage I/O failures
still surface; controller recovery for such failures remains part of integration.

Caches are scoped to the physical vault as well as run/endpoint/model/credential.
Loading the Mac run list prunes orphan bindings older than fourteen days and retains
all existing journals, including unreadable journals with recoverable run UUIDs.
A live or paused journal is never expired solely by age. Explicit run cleanup is
available for the forthcoming delete controls. The lifecycle owner creates real
private cache files, ages them, reads the real run list, corrupts a journal and then
deletes it: cache retention survives the readable/unreadable states and cleanup
happens after deletion. A cache-store owner separately checks 0700/0600 permissions,
retaining live run IDs during pruning and targeted removal. Corrupt cleanup
metadata is retained for recovery rather than used to guess which live run to delete.

No second delegate re-review was requested for these repairs. Remaining low-priority
review work includes repeated transcript-prefix/image hashing cost and the already
tracked provider budget/capability/controller integration gaps. Installed acceptance,
complete migration parity and a new package remain pending. The final repaired
suite passes all 214 tests with zero failures in 58.045 seconds
(`agent62-provider-final-tests.log`).


### Mac run lifecycle controller (development, unpackaged)

`MacAgentController` now owns the window's native provider/tool loop. It starts or
resumes a durable run through `MacAgentWorkspace`, prepares granted attachments,
checks selected-model context capacity, reserves input/output allowance before a
model request, records reported usage (or reasoning-inclusive estimates), executes
saved pending calls and checkpoints elapsed active time. A deadline stops requests
at the run's remaining time allowance. Provider calls hold a frozen connection
snapshot; they do not hold note-editor locks.

A portable `macProvider` extension stores the format/endpoint/model and a digest
of the ChatGPT account identity, never API keys or OAuth credentials. Native journal
writes and approval receipts preserve the extension. Resume checks it before
changing the journal or sending. Using a different/newly selected connection is an
explicit controller action for the forthcoming UI, not an automatic fallback.
ChatGPT capacity discovery uses the same account/model admission lock as sending.
A profile's configured capacity is checked before reserving or sending; unknown
catalog capacities remain subject to the run's own context/budget checks.

Review stages changes and exposes a prepared exact-byte approval object. Edit can
automatically apply a newly staged ordinary single-note change only while the total
set of affected, non-undone receipt/proposal note IDs stays at one. Several notes
wait for review. Approval/rejection disable overlapping controller actions and
continue through the workspace commit boundary. Questions and preview/apply tools
pause the loop. Actual tools/receipts, not model text, determine saved state.

Stop cancels the provider task, then an independent finalizer checkpoints elapsed
time and pauses the journal. A request with no complete usage settles its reserved
allowance as an interrupted estimate. Completed tool results remain in history and
are not replayed on Resume. A failed final journal write sets unsaved state and
prevents closing/switching. Window close and vault switch stop/checkpoint the
controller before invalidating its workspace activation. Stale reloads cannot
replace a newer active record. Typed Anthropic refusal clears live text and never
stores its partial output as an assistant answer.

All 221 native tests pass (`agent62-controller-full-tests.log`, 59.963 seconds).
The seven controller owners use isolated URLSession fixtures and real Mac windows,
vault files and native journals. They exercise a three-step read/append/preview
Review loop, unchanged bytes before approval, saved receipt/peer-editor adoption,
Resume and binding preservation; single-note Edit versus a parallel two-note batch;
Stop reservation settlement and changed-model refusal before a send; both vault
switch and window close during a live request; typed refusal clearing; capacity
refusal before any request reservation; and reasoning-inclusive usage estimation.
The unchanged adapter/sibling suites also pass. An Opus 5.5 milestone review of
this controller is in progress.

This is still backend integration. The conversation bridge must next durably link
the prompt/reply and native run, preserve ordinary interrupted live text through
chat recovery, freeze/import the selected chat attachments and expose run/history/
review/answer controls. Currently ordinary live partial text is held in the
controller, while the run journal durably preserves completed structured replies,
tools, proposals, receipts and interruption accounting. Those are different
persistence claims; installed conversation/UI acceptance is not established.
No agent controls are exposed and no new DMG or notarization was produced.


### Opus lifecycle review repairs

The lifecycle review reproduced five defects: a permanently latched failed journal
checkpoint, Resume bypassing vault admission, a replaced controller still running,
a stale deadline flag masking later failures, and explicit rebinding failing on
unreadable binding metadata. The owning regressions failed before repair
(`agent62-controller-review-baseline.log` and `agent62-controller-deadline-baseline.log`).
All are repaired locally; no delegate re-review was requested for this repair batch.

Controllers now distinguish Stop/checkpoint from workspace departure. Departure
holds a leaving gate until close/switch completes; a failed preflight releases it
for the unchanged workspace. New and resumed requests require the current, active
controller and a non-busy/non-closing window. Resume also admits/saves all vault
peers through the same workspace boundary as Start. Replacing an idle controller
retires it, and a leaving controller cannot be replaced to bypass its gate.

After a failed Stop checkpoint, retry reads the current journal again, checks
ownership and other active windows, and pauses the fresh record. Restoring readable
journal bytes therefore allows closing without force-quit. An explicit discard
method clears only unsaved in-memory state and never changes saved journal/note
bytes; it is reserved for the future UI's confirmed discard action. A failed close
returns to its previous workspace state so recovery remains usable. The tests cover
both restored-journal retry and explicit discard while the saved journal remains
unreadable. The conversation bridge still must persist ordinary live partial text;
this repair does not claim that separate persistence work is already complete.

Each accepted request resets its deadline state before any credential/binding work.
A real deadline regression uses a run with 59.99 seconds already accounted against
a one-minute limit, exercises the actual timer and active-time checkpoint, and then
checks that a blank-key request reports its credential error. The deadline now uses
a suspending clock consistently with active uptime accounting. Explicit connection
replacement skips reading unsupported old provider metadata and writes a new
binding. Normal Resume still refuses an unexpected connection change.

Pending reviews can be rebuilt without another model request after a temporary
workspace conflict. A fully received provider completion is finalized in a separate
task before honoring Stop, preserving its reported usage and preventing subsequent
tool execution. Record-list errors do not overwrite an existing, more useful stop
or provider error. New tests cover review rebuilding without HTTP, a stale approval
whose journal changed, and a second note proposed after an earlier single-note Edit
receipt. That second note still waits for review. Account-transport capacity owners
now exercise cold ChatGPT catalog discovery, insufficient discovered capacity and a
restored model replaced during discovery; no model request/reservation is sent.

The final suite passes all 229 Mac tests with zero failures in 60.919 seconds
(`agent62-lifecycle-repaired-full-tests.log`). No live account/provider, installed
app or Computer Use was used. Conversation transcript linking, private partial-reply
recovery integration, visible run controls and full parity remain pending. No new
DMG or notarization was produced.

### Development after Preview 61: native agent conversations and first controls

Native runs now use the existing recoverable Mac conversation rather than an
isolated live-text buffer. A user request and interrupted reply placeholder are
saved before starting the run. The placeholder receives its native `runId` before
a provider request. New images keep their exact prepared JPEG bytes; document
text is frozen in the private attachment store and portable conversation history.
Older conversation text, note references and attachments are bounded explicitly,
with omissions disclosed to the provider. Credentials are not saved in journals.

Stop checkpoints both the journal and the conversation. A resumed run appends a
separate Continue turn and keeps unsent composer text and attachments. Failed
conversation writes retain the partial reply in existing private recovery storage.
Ordinary Retry refuses agent-linked replies, directing users to Resume so a run
link and tool history cannot be replaced by an ordinary chat retry.

An ownership-transfer regression initially demonstrated continued tool execution
and another paid request after transfer. The conversation authority is now checked
before every tool, automatic apply and provider reservation. Ownership-generation,
archive and deletion changes interrupt the run; already received responses can
still be accounted in its journal and the partial conversation reply is retained.
The owning regression and four other bridge tests pass with chat/lifecycle siblings
(27 tests, `agent62-chat-authority-fixed.log`). Retry also failed on its pre-fix
baseline (`agent62-chat-retry-baseline.log`) and passes after its guard.

AI conversations now have an Agent runs sheet with Ask/Review/Edit, selected-note
or vault scope, saved runs, Stop/Resume, answers to agent questions, proposal
rejection, exact note-source review/apply and failed-journal recovery controls.
This first controls implementation builds (`agent62-controls-build.log`); native
visual/interaction acceptance is still pending. The controls use the configured
connection. Connection-replacement confirmation, workflow/guidance/limit editors,
receipt Undo and run deletion are not exposed yet. The five extra web tool classes
remain pending, as do full parity, encoding and IME acceptance. No new DMG or
notarization has been produced for this development batch. Preview 61 does not
contain these changes.

The full Mac suite after this batch passes all 234 tests with zero failures in
63.039 seconds (`agent62-conversation-full-tests.log`). This establishes the tested
journal/conversation contracts; it does not establish installed visual or live
provider acceptance. Opus 5.5 milestone review is pending.

### Preview 62 preparation: Opus conversation/control review repairs

Opus 5.5 reviewed the bridge and first controls by source inspection. Two owning
regressions reproduce its early-stop attachment and rejected-resume findings in
`agent62-review-edges-baseline.log`. A saved run now writes its attachment grant
and retention markers synchronously before awaiting provider binding, so a Stop
at the first journal publication can still resume with frozen inputs. Resume
checks the current window admission and provider binding before writing conversation
turns, and repeats that check after loading the conversation. Resumed placeholders
carry the original run ID immediately; failures retain the selected run for UI
without checkpointing a journal the attempt never acquired.

Selected-note scope is constructed after stable references resolve against the
fresh note snapshot. A moved chosen note no longer leaves stale path permission
behind. Agent controls cannot be opened during an ordinary chat request. Stop is
available throughout chat preparation, not only during controller execution.
Manual Apply/Reject rechecks current conversation ownership/availability before
requesting the guarded journal/file operation. Saved-run rows now expose selected
accessibility state. Ownership checks still load the full conversation history;
optimizing this low-priority cost remains pending.

The repaired bridge/lifecycle/chat owners pass all 29 tests in 5.034 seconds
(`agent62-review-edges-verified.log`), including the previously added authority
regression. The prior full 234-test result predates these final review repairs;
a fresh full run and Preview 62 packaging are required before handoff.

The final Preview 62 suite passes all 236 Mac tests with zero failures in 63.939
seconds (`agent62-final-full-tests.log`). README was reviewed and updated for the
new native agent adapters/controls and remaining limitations before advancing the
native preview build to 62. Packaging uses `pnpm desktop:build --native --local`;
no notarization, Windows release, Store publication or iOS release is included.

Preview 62's non-notarized local DMG was built successfully and verified by mounting
its actual payload: version 0.3.34/build 62, arm64, minimum macOS 26.0, ad-hoc
signature and matching staging/mounted executable hash. Its private HTTPS download
was fetched independently and matches SHA-256
`ed219856fe80bf9024ca9498f11fc5d3d053874743d98766dda4904cdd4f2f44`.
Receipt: `artifacts/native-macos/artifact-preview-62-local.json`; conversation/test
handoff evidence: `agent62-conversation-verification.json`. The unchanged web
preview returns HTTP 200 through both loopback frontend and private proxy.
Installed visual/interaction acceptance remains pending because prior Computer
Use access to Zerus Native was denied. Packaging verification is not installed UI
acceptance, live-provider acceptance or a claim that full migration is complete.

### Development after Preview 62: agent settings and history controls

The Agent runs sheet now opens native settings for new-run limits, vault
instructions, editable memory and workflows. These use the unchanged shared Apple
persistence formats: `.zerus/ai/settings.json`, `instructions.md`, `memory.md` and
ordinary Markdown under `workflows/`. Numeric limits are validated before save;
unknown settings fields are preserved. Custom workflows can be drafted, exported,
saved, selected and edited. Existing run configuration remains frozen.

Settings editors retain their draft after stale-write or activation failures.
Tab switches are refused while a draft/save is active; Done and Reload ask before
replacing unsaved changes. The root sheet also blocks interactive dismissal while
any tab reports unsaved work. The write wrappers revalidate the captured vault and
use Mac admission before shared expected-byte transactions. The settings/workspace
owners pass 14 tests, including shared-field preservation, new-run configuration,
frozen resumed configuration, stale writes, busy windows and replaced vaults.

Run history now exposes each saved receipt's guarded Undo review. Opening that
review does not save; Apply uses the same coordinated approval path. Run journal
deletion asks for confirmation, uses owner/expected-byte checks and refuses an
active peer window. Deletion keeps applied notes and conversation history. It
attempts immediate removal of private provider continuations and reports cleanup
failure separately; frozen attachment retention is unchanged. A changed model or
account can be chosen explicitly through a separate Resume confirmation. That
confirmation retains the chosen connection snapshot and preserves existing run
permissions/limits; provider-specific continuations can still require the original
connection.

The history/settings focused owners pass 30 tests with zero failures in 5.415
seconds (`agent63-history-settings-tests.log`). This includes staged Undo/apply,
stale journal deletion refusal, deletion preserving applied writing and an active
peer deletion guard that asserts its own rejection reason. Native builds pass
`agent63-settings-fixed-build.log` and `agent63-history-fixed-build.log`.
Full-suite verification and Opus 5.5 settings review are in progress. No new DMG or
notarization has been created for these changes; the delivered Preview 62 remains
the current test artifact. Visual/interaction acceptance is still pending.

Opus 5.5 settings review completed with three medium findings (no blockers): clean
Limits/Workflows tabs retained competing settings snapshots; unsaved settings were
not part of Quit preflight; workflow editing was tied to the saved selection.
Clean editors now reload when shown again. Metadata conflicts identify AI settings
and preserve the draft. Settings writes serialize their own window and use shared
expected-byte transactions without saving or locking open note/connected drafts.

A dedicated settings-draft hold is reported by the sheet to its originating
workspace. Quit, window close, vault switching and new/resumed runs refuse while
that draft/save is held. The owning Quit test fails with the pre-existing close
behavior (`agent63-settings-quit-baseline.log`) and passes after the guard. The
root sheet clears the hold on disappearance. Repeated refused tab switches trigger
a fresh notice update, and saving clears the notice. Editors resign text focus and
yield before evaluating save input; real IME acceptance remains pending.

Workflows now have per-file Edit controls, custom copies of built-ins, automatic
selection of newly saved drafts, an explicit editing filename, separate draft
Discard that keeps the pending selection, and scrollable notices/editor content.
Unavailable selections cannot be saved; source Save uses source dirtiness. A
workflow-file save followed by a failed selection reports that partial outcome.

The repaired focused bridge/controller/workspace suite passes 38 tests in 7.456
seconds (`agent63-review-repaired-focused.log`). The Mac settings test was narrowed
to Mac routing/start configuration and its stale-editor outcome; duplicate shared
Core resume/fidelity assertions were removed. Shared core behavior remains owned
by the iOS tests. A full suite after final review edits is running. Web preferences
`mode`, `writeScope`, `textFallback` and `workers` are preserved but not exposed as
saved Mac preferences yet; those are additional parity work, alongside the five
missing tool classes and installed/IME/provider acceptance. No claim of full
migration or installed acceptance is made.

The final reviewed-controls suite passes all 241 Mac tests with zero failures in
64.198 seconds (`agent63-reviewed-full-tests.log`). Evidence and scoped source
hashes are in `agent63-controls-verification.json`. The explicitly confirmed model
replacement also passes the conversation bridge owner: it saves a separate Continue
turn, updates the provider binding and keeps the original note permissions/limits.
The web preview still returns HTTP 200 through frontend and private proxy. Preview
62 remains the delivered DMG; these later settings/history changes are unpackaged.
No additional notarization was performed.

### Development after Preview 62: scoped link and memory tools

The Mac agent now advertises fifteen tools: the existing thirteen shared native
operations plus `note_links` and `memory`. Mac additions use the same journal
owner/CAS, pending-call identity, run budgets and permission-filtered note resolver.
No iOS implementation was changed. The remaining three web tool classes are
organization, independent note analysis and the constrained CLI compatibility tool.

`note_links` reads Markdown note references and typed relation properties, including
inherited definitions. Outgoing references resolve only against permitted notes;
unknown, ambiguous or outside references remain unresolved. Backlinks are drawn
only from permitted notes and ignore code literals. Returned summaries do not mark
any linked body as fully read or grant mutation coverage. Large encoded results
return a bounded refusal rather than claiming a complete truncated graph.

`memory` reads current saved vault memory as untrusted reference data, matching the
web tool. It cannot replace the run's frozen instructions, workflow or permissions.
Remember/forget return suggestions directing the user to the visible memory editor;
they never persist model-selected preferences. Settings/prompt wording distinguishes
starting memory context from an explicit read of the current saved reference text.

The owning workspace suite passes 17 tests (`agent64-tools-tests.log`), covering
relation/body links, scoped backlinks, hidden notes, code literals, missing body-read
coverage, current memory reads, preserved instructions and non-persisted suggestions.
The full suite passes all 243 Mac tests (`agent64-read-tools-full-tests.log`). Opus
5.5 review of this milestone is pending. Installed UI/IME/provider acceptance and
full migration parity remain pending. No new DMG or notarization was produced;
Preview 62 remains the current delivered artifact.

### Link review repairs and CLI compatibility development

Opus 5.5 found no blocking/high-severity link or memory issue. Its medium finding
was reproduced: a malformed relation on one permitted note caused the entire link
query to fail (`agent64-links-review-baseline.log`). Relation/schema failures are
now isolated per note/definition and disclosed in `unsupportedRelations`, while
valid body links continue. The table covers numeric, checkbox and duplicate-key
relations, wrapped relation references, hidden inverse properties, managed-note
collisions and omitted selectors. An omitted selector follows the shared engine's
frozen current target; the test no longer assumes dictionary/file enumeration
always chooses Alpha. Hidden relation definitions are excluded, ordinary notes
alone are resolution targets, and per-call ID/path/title indexes avoid repeated
whole-vault target scans. The prompt explains link scope and unsupported data.

`zerus_cli` now maps a declared read allowlist onto the existing native handlers.
The four shared read cases were extracted, preserving body ranges, revision
coverage, properties, schema lookup, pagination and result ordering. The original
`zerus_cli` call name and ID remain in assistant/result history; no temporary alias
journal or process execution is used. `note list`, `note get [SELECTOR]`, `search
QUERY`, `type list` and `schema list` are supported. One trailing `--json` is
explicitly accepted for note reads. Unknown extra arguments are refused rather
than silently ignored. Vault overrides and mutation approvals are always refused.
Refusals list the available dedicated scoped tools. Type/schema list describe the
current note, and the first-page CLI read directs subsequent pages to `note_get`.
The runtime now offers sixteen tools; organization and independent analysis remain.

The CLI owner test verifies scoped list/get/search/schema, original call/result
identity, read coverage usable by a subsequent dedicated staged mutation, rejection
of outside notes/overrides/approvals/mutation and shell attempts, and unchanged note
bytes. The compatibility additions failed before the parser repair in
`agent65-cli-compat-baseline.log`. Opus reviewed the extraction and found no blocking
or high-severity defect; its older-log observation is resolved by the later full
Mac suite and iOS final compile. The 34 focused tests pass in 6.754 seconds
(`agent65-cli-verified-tests.log`), and the full pre-compatibility-repair suite passes
all 244 tests in 69.383 seconds (`agent65-cli-full-tests.log`). Final compatibility
verification is running separately.

The shared `native-ios/Sources/NativeAgent.swift` change is a read-handler
extraction. Generic iOS Simulator build-for-testing succeeds on its final source
(`agent65-ios-final-compile.log`); this is a compile/link check, not test execution
or a visual preview. Device inventory initialized, but `device_open` returned
`user cancelled MCP tool call`. Device UI actions were stopped; install, affected
screen preview and screenshot remain pending. No App Store build number was
advanced, and no archive/export/upload was performed. The desktop web preview
returns HTTP 200 at both frontend and private proxy. No new DMG/notarization was
produced; Preview 62 remains delivered. Installed/IME/live-provider acceptance,
saved preference parity, remaining tools and existing web-run continuation/migration
still require completion before claiming full desktop parity.

Final CLI compatibility verification passes all 244 Mac tests with zero failures
in 65.922 seconds (`agent65-cli-complete-tests.log`). The generic iOS test-build
compile passes on the final shared read-handler source. Review/test/source-hash
handoff evidence is `agent65-cli-verification.json`. CLI current/--json cases pass
after their failing baseline; advanced extra arguments remain explicitly refused.
Opus reviews are complete and findings repaired locally, without a redundant
re-review. The delivered Preview 62 DMG is unchanged. Both desktop web preview
routes return HTTP 200. Device visual preview remains pending after the cancelled
opening request; no alternative UI automation or device session was used.


### Run preferences and text-tool fallback development (after Preview 62)

New runs now freeze mode, write scope, the text-tool fallback preference and the
worker preference from the shared AI settings. The native run controls expose mode
and current-note versus context writes. The explicit current read target is frozen
by stable note identity; a missing explicit target does not silently select another
note. Saved runs retain their starting preferences when defaults change.

The Run defaults tab preserves unrelated settings fields and uses expected-byte
writes. Unknown or incorrectly typed preference values normalize to the web defaults
without changing any bytes on read. The editor discloses normalization and can save
the normalized values explicitly. Invalid JSON remains an error with its file kept.
Run defaults load again after a busy period; failed loads can be retried without
replacing mode and scope choices the user has already made. Use saved defaults is
an explicit reset of those choices.

Mac text-tool fallback offers no native tools and accepts one declared final text
call outside Markdown code literals. Generic JSON calls and the documented legacy
note tags are converted into the same scoped tool path; all write admission, read
coverage, proposal review and budget checks still apply. Multiple, mixed, native-only
or malformed calls are refused without executing any call. Refusal records the
reported usage and feedback in the journal, then pauses; explicit Resume lets the
model see that feedback. Original valid call text is stored alongside the normalized
call so provider continuations reconstruct the wire transcript. Inline/fenced code
examples stay literal. The protocol warns that literal closing tags in arguments
must use JSON Unicode escapes. iOS continues using native provider tools and freezes
text fallback off until that runtime supports it.

Opus 5.5 found no blockers and identified malformed-call detection, busy defaults
loading and strict preference parsing as medium issues. Those were repaired locally.
The malformed-call variants failed before repair in agent66-review-baseline.log;
the pure normalization owner failed with the intended preferences error in
agent66-normalization-owner-baseline.log. Earlier coordinated fixture failures are
not counted as proof of that defect. The focused repaired suite passed 39 tests.
The later full-suite and generic iOS compile results are recorded separately.

The worker preference is persisted only: independent analysis and organization
remain missing tools (sixteen of eighteen offered). Folder scope, explicit creation
permissions, web-run migration, live-provider/IME and installed-app acceptance remain
pending. Device opening was cancelled earlier, so shared iOS changes have compile
verification only; simulator install, visible affected screen and screenshot remain
pending. This batch has not been packaged: Preview 62 is still the delivered DMG.

Final run-preferences review repair verification passes all 250 Mac tests with zero
failures in 71.403 seconds (`agent66-review-full-tests.log`). The generic iOS
Simulator build-for-testing compile also succeeds (`agent66-review-ios-compile.log`).
This does not establish device UI or live-provider acceptance. The evidence record
is `agent66-review-verification.json`; Preview 62 remains the delivered package.


### Folder access and explicit creation permissions development

The Mac New run controls now offer Chosen context, Folder and Entire vault read
access. A folder includes its children; Inbox means only root-level notes. Chosen
context still resolves saved note identities immediately before constructing the
scope. Folder and vault runs do not eagerly send every note as a conversation
snapshot: the scoped tools fetch their contents as needed. Conversation scope
metadata records the corresponding selection, type path or vault boundary.

New-note creation is explicitly off by default on Mac, including folder and vault
runs. When enabled for context writes, selected-note runs choose one creation folder,
folder runs permit their chosen folder, and vault runs permit ordinary folders.
Ask and current-note-only writes disable creation regardless of the retained toggle.
A current write target must be a writable ordinary note within the chosen read scope.
Saved run details disclose the frozen read scope and creation boundary.

The shared NativeAgentScope adds allowCreation with a default of true so existing
iOS callers retain their behavior; Mac always supplies its explicit permission.
The journal continues storing the effective createFolders, so later UI changes do
not widen a saved run. No new journal format or App Store build number is needed.
The Mac permission owner test constructs scopes through the same model used by the
view, starts actual journals, exercises scoped reads and creation calls, and checks
that proposals do not write files. It covers selected/folder/vault, descendants,
outside notes, creation disabled/enabled, out-of-bound folders, Inbox, and a current
write target outside the read boundary. All 23 focused workspace tests pass in
4.714 seconds (agent67-permissions-tests.log). Full-suite, refreshed generic iOS
compile and Opus 5.5 review are pending. Installed UI and live-provider acceptance
remain pending; this development batch is not packaged.

Final permission-source verification passes all 251 Mac tests with zero failures
in 72.211 seconds (`agent67-permissions-full-tests.log`). Generic iOS Simulator
build-for-testing also succeeds (`agent67-ios-compile.log`), with install/visual
verification still pending after the prior cancelled Device opening. The evidence
record is `agent67-permissions-verification.json`. Opus 5.5 permission review is
still pending. No DMG or notarization has been generated for this milestone.


Opus 5.5 permission review found no blockers. The write option is now called Notes
in read access, and its caption discloses the effective writable set for selected,
folder and vault reads. The current note is captured when Start is clicked and
rechecked after preparation awaits. Creation is frozen per run: starting a new run
on web/iOS uses that client's permissions, which is now disclosed in the controls.
The conversation scope remains its interoperable read boundary, not a portable
creation grant. The additional scope persistence test checks selection, folder,
Inbox and vault records through the actual conversation bridge, and the permission
owner checks creation in a readable child folder is still denied. All 31 focused
workspace/bridge tests pass (agent67-review-fixed-tests.log). No redundant review
was started for these small repairs.

### Independent note analysis development

The Mac agent now implements analyze_notes behind the frozen workers preference.
Two separate Ask conversations examine explicitly selected in-scope notes from
supporting-evidence and contradiction/coverage perspectives. They have only the
four scoped read tools: note_get, note_list, note_schema and search. They cannot
write, create, ask the user, launch nested workers, or read outside the selected
notes and the parent's current folder boundary. They do not receive the parent's
attachments, conversation history, vault guidance or each other's answers. Their
untrusted final answers are returned to the parent, whose own body-read coverage
remains unchanged.

Workers run sequentially with separate conversations so every paid request uses
the parent journal's durable reservation. Their requests consume the parent's
model-step count, active time and reported/estimated tokens, plus each worker's
bounded allowance (up to eight steps, three active minutes and 3,000 output tokens).
The parent keeps a synthesis allowance when creating the workers. Completed child
responses and tool results are stored atomically with parent accounting. Stop keeps
an interrupted allowance as an estimate in both parent and worker budgets. Resume
reuses completed work and settles the unfinished worker before requesting again.
A regression failed first on the missing child debit in
agent68-worker-allowance-baseline.log and passes after repair in
agent68-worker-allowance-fixed.log.

Full child transcripts are retained in the parent's macAnalysisHistory; active
progress is macAnalysis. They are not copied into the parent provider transcript.
Completed Anthropic child continuations are removed, active ones are retained
through cache cleanup, and deleting the parent also removes child continuations.
Text fallback uses the same restricted worker schemas and provider continuation
rules. The iOS runtime refuses to resume a parent with unfinished Mac analysis
before changing its journal, since it does not yet execute those workers.

This is still development code, not a packaged preview. Focused tests, full-suite
verification and an Opus milestone review are recorded separately once complete.
Organization, existing web-run migration, installed/IME/live-provider acceptance
and device visual preview remain outstanding. No new notarization was requested.

Independent analysis verification passes all 256 Mac tests with zero failures in
73.977 seconds (`agent68-analysis-full-tests.log`). The focused 22 controller tests
pass in 5.791 seconds (`agent68-analysis-transport-tests.log`), including compatible
and Anthropic fallback continuations, completed worker reuse, disabled/outside/step
budget refusal and parent/worker interrupted allowance accounting. The generic iOS
compile succeeds (`agent68-ios-compile.log`); no simulator runtime or UI acceptance
is claimed. Opus 5.5 review is pending. Evidence is
`agent68-analysis-verification.json`. Seventeen tools are now offered in Mac source;
organization is the remaining missing tool. Preview 62 is still the delivered DMG.


### Analysis review repairs and Preview 63 handoff preparation

Opus 5.5 found no admission/CAS/accounting blocker, and identified synthesis
holdback, worker timeout propagation and oversized result/history handling as
medium issues. Three owner regressions failed on the previous source for the
intended reasons in agent68-review-baseline.log. The repaired worker pool keeps
the parent's full saved input allowance plus at least 1,000 output tokens, one
model step and 30 active seconds for synthesis. Each request checks the holdback.
The token quota owner also failed when only the old 4,000-token split was restored
(agent68-token-holdback-ablation.log); the fixed source was restored before final
verification. This was a targeted causal check, not a pristine checkout baseline.

A worker timeout now cancels only its provider task. The interrupted allowance is
settled in parent and child, the child becomes partial, and the other worker and
parent can continue. User Stop still cancels the whole operation and preserves
progress. Worker progress is a separate UI status, not assistant reply text, and
active seconds are saved in child records. Transport-rejected replies likewise
become partial worker results. The MacAgentCompletion boundary already enforced
the 12-call, ID, argument and content caps; the missing behavior was recovery from
those refusals and the size of the combined analysis result.

Synthesis results are bounded and checked against the real parent request and
provider capacity, with explicit truncation markers. A child transcript reaching
1 MB ends as a partial analysis instead of repeatedly failing an 8 MB journal
write. Completed history above 1 MB is compacted to marked identity/usage/conclusion
summaries; full parent tool results remain in the journal. New analysis refuses
journals already at 4 MB to retain storage headroom. Active metadata left behind
by a shared-only client is archived before a new analysis. Unreadable prior state
returns a tool refusal and is archived rather than repeatedly starting workers.
Stale inactive children are not retained forever by cache pruning.

The additional owner cases cover step and token holdback, a near-deadline resume,
large final answers, a 13-call rejected worker reply, a growing transcript, and an
older-client decline. All 52 focused controller/workspace tests pass in 12.521
seconds (agent68-review-final-focused.log). The iOS source is unchanged from the
successful agent68-ios-compile.log compile; its runtime guard and Device UI remain
unverified after the earlier cancelled Device opening. No redundant delegate review
was started for these repairs.

README was reviewed against the intended Preview 63 features, commands, platforms,
dependencies and limitations before advancing only the native Mac build to 63.
Preview 63 remains an intermediate ad-hoc build, not the production replacement.
Its full suite, DMG receipt and HTTPS download checks are recorded below once ready.
Organization is still the missing eighteenth agent tool. Existing web-run migration,
other-device takeover and installed UI/IME/live-provider acceptance remain pending.

Preview 63 final Debug verification passes all 263 Mac tests with zero failures
in 74.283 seconds (`preview63-final-tests.log`). The test command completed with
`TEST SUCCEEDED` before Release packaging began. The intermediate DMG is built
with `pnpm desktop:build --native --local`; notarization is intentionally skipped.

Preview 63 is packaged and available as `Zerus-Native-0.3.34-preview-63-arm64-local.dmg`. Release build,
read-only mounted payload verification, strict ad-hoc signature, version 0.3.34 /
build 63, arm64 and macOS 26 minimum checks pass. The actual private HTTPS download
matches SHA256 `e383480872190e418c2b792e1bc40489136038288cff48e2e32015e7ed479604`. The adjacent receipt is
`artifact-preview-63-local.json`; `preview63-source-manifest.json` fingerprints the
Release Swift inputs and configuration (not a full reproducible build snapshot).
The complete handoff evidence is `preview63-verification.json`. Notarization was
not submitted. Installed native UI/IME and live-provider acceptance remain pending.
Preview 63 replaces Preview 62 as the latest delivered intermediate DMG. Full
migration parity is still incomplete; organization and the remaining acceptance
and migration work remain active.


### Agent organization development after Preview 63

The eighteenth Mac tool, note_organize, now stages title, pin/archive, filing and
Trash changes. Titles update the heading and retain the filename. Filing has its
own explicit folder permission, independent of new-note creation: selected-note
runs choose a destination folder, folder scopes permit that folder and its child
folders, and vault scopes may permit ordinary folders. Inbox permits only root
notes. Ask and current-note-only scopes do not grant cross-folder filing. These
permissions are frozen with the run.

The planner reuses native note/link/relation/resource maintenance. It requires
current-revision reads of every affected ordinary writable note, refuses changes
outside that context, preserves relative attachment destinations, repairs supporting
task links without changing other task fields, and refuses folder-definition
migration. Native planner errors are sanitized before reaching the model so an
outside link conflict cannot expose unselected note paths or titles. Legacy IDs
are assigned deterministically for replay and committed only when an actual edit
or reference needs them. Pin/archive-only changes do not upgrade unrelated notes.

Organization proposals retain exact byte changes, metadata dependencies, path and
resource bindings and creation timestamps. Shared decoding checks that every note
file change matches the visible before/after snapshots, rejects duplicate paths,
and permits only the exact supporting-note link transformation in task metadata.
Native review recomputes the live plan, compares its snapshots and bindings, locks
current vault notes against new incoming links, and commits the journal/receipt
with the files. Every changed file, including task metadata, is visible in review.
Overlapping proposals can be reviewed individually. Edit can save a single ordinary
requested change; multi-note repairs and every move to Trash require explicit review.

Undo compares exact affected note bytes, refuses newer affected-note edits and new
identity/title/path links requiring a fresh repair, and leaves unrelated writing intact.
Task metadata Undo merges only the supporting-note links changed by the move, retaining
later check-offs, other task fields, new tasks and independent settings changes. A newer
edit to those same supporting-note links is refused. Relevant effective property
definitions are fingerprinted semantically; unrelated schema and saved-link settings
are read-locked at their current bytes rather than leased to their old hashes. Tabs, selection and creation dates reconcile in both directions.
An owned Trash/restore or legacy ID upgrade is adopted only when the editor still
matches the approved clean before snapshot; late writing takes the retained-draft
path. The initial Trash test reproduced a false outside-deletion draft
(agent69-trash-trace.log); the repaired case passes. The missing metadata error in
its failed cleanup was secondary, not used as proof of an AI metadata defect.
The temporary metadata probe passed and was removed; no general metadata I/O
change or fixture workaround was used to hide the actual reconciliation bug.

Archived bodies and properties remain protected. The Mac workspace opts into an
explicit unarchive exception; the shared engine defaults that capability off so
existing iOS start callers keep their previous write boundary. Shared-only review
and Undo refuse organization plans rather than applying only their body portion.
The shared shape and guard compile on iOS; runtime/install/Device preview remains
pending after the earlier cancelled device opening. No App Store version changed.

The focused 59 controller/workspace tests pass (agent69-organization-final-focused.log,
15.134 seconds). They cover native and text fallback provider loops, staged review,
apply/resume/Undo, single-note Edit pin, filing with image/task/incoming links, exact
Undo, birth-date retention, Trash/unarchive, legacy ID navigation, new-link and stale
write refusal, unread/outside targets and malformed persisted snapshots. The first
full suite passes all 270 tests in 85.076 seconds (agent69-organization-full-tests.log).
The later filing-permission model case also verifies that filing can stage a move
while new-note creation stays disabled. The platform-default scope adjustment passed 270 Mac tests and the generic iOS
compile (agent69-platform-final-tests.log and agent69-platform-ios-compile.log).
Opus 5.5 reviewed the organization milestone. Its compatibility finding is repaired:
organization grants/proposals use journal format 2, which older version-1 readers
refuse before claiming or undoing the run. Ordinary format-1 journals remain readable.
Clean owned Trash moves now close their tabs and clear selection. Legacy identity
assignment refuses an unrepeatable planner-generated identity and removes unused
companion IDs even when their bodies were repaired. The planner's metadata allowlist
matches the decoder's task-link-only contract.

The review repairs pass all 60 focused controller/workspace tests
(agent69-review-final-focused.log, 16.625 seconds). They check format-version refusal,
Trash review in Edit mode, clean Trash navigation, independent task/settings edits,
and refusal of independently changed supporting-note links. An exact-byte task Undo
regression was caught in the first repair run and fixed before the focused pass.
The attempted old-metadata-guard baseline failed but surfaced an unrelated missing
properties-pane error, so it is not claimed as a clean fail-first proof. Full-suite
and iOS compile results for the final repairs are recorded separately.

 Preview 63 remains the latest delivered
DMG and does not include this development feature. No new notarization occurred.

### Preview 64 organization handoff preparation

The final organization review repair suite passes all 271 Mac tests with zero
failures (agent69-review-full-tests.log, 81.666 seconds). The generic iOS Simulator
build-for-testing succeeds (agent69-review-ios-compile.log); runtime install and
Device-panel preview remain pending after the earlier cancellation. No iOS build
number, archive or upload changed.

README was reviewed for this preview's features, Apple Silicon/macOS 26 minimum,
setup and packaging commands, dependencies and parity limits. Preview 64 adds the
organization tool and its review repairs to Preview 63. Packaging is intermediate,
ad-hoc and non-notarized. The installed native UI, IME/dictation, live providers,
encoding fidelity, existing web-run migration and the full feature-parity audit
remain pending. Test counts do not establish that those acceptance checks passed.

Preview 64 is packaged as `Zerus-Native-0.3.34-preview-64-arm64-local.dmg`.
The Release build and mounted-payload checks pass: bundle build 64, arm64,
minimum macOS 26, verified ad-hoc signature. The private HTTPS download checksum
matches the packaged DMG: `1da96f77a94f568af2db08bb0a39f592c13c197e383ca3434f0b4134bdc8660f`.
The artifact receipt and `preview64-verification.json` record this evidence.
`preview64-source-manifest.json` fingerprints 263 Release/configuration inputs;
it is not a complete reproducible source snapshot. Preview 64 supersedes Preview 63
as the latest delivered intermediate DMG. No notarization occurred. Full migration
parity and the acceptance items above remain unfinished.

### UTF-8 prefix fidelity development after Preview 64

Vault snapshots now retain leading UTF-8 BOM bytes rather than relying on
Foundation's BOM-stripping String(data:encoding:) result. Strict UTF-8 validation
remains in place. Frontmatter recognizes and retains leading U+FEFF prefixes,
including repeated marks, keeps them outside the editable body, inserts new YAML
after them and keeps LF/CRLF body bytes intact. Metadata insertion into a headerless
CRLF note uses CRLF. Existing malformed/foreign YAML safeguards remain in force.
Markdown snapshot readers used by history, revisions, image maintenance, rename,
relations, Drive identity detection and recovery use the same decoding owner.
Network, credentials and transport/preview decoders retain their own contracts.

A second Foundation behavior was reproduced: JSONSerialization strips leading
U+FEFF inside JSON string values, even when the input uses a Unicode escape. That
made AI journal note snapshots fail their stored hash/identity validation after a
BOM note edit was staged. NativeJSON uses JSONDecoder to retain scalar text while
producing Foundation-compatible objects for the existing JSON writers. Agent
journals, history versions, revision indexes and Mac recovery drafts use it.
Historical text and patches retain their original prefix; empty-header stripping
and metadata-preserving history restoration also keep it.

Connected-file editing still removes exactly the physical encoding BOM for its
editor and restores it on save. Recovery-draft comparison now preserves any
remaining U+FEFF, so a file with two leading marks is not perpetually reported as
an unsaved draft. Move receipt hashes ignore leading encoding marks for their
logical-content comparison, retaining the previous allowance for an unrelated
encoding-only change; actual transaction writes still lock exact current bytes.

The vault owner regression failed before the repair with a byte mismatch and
blocked save (encoding70-bom-baseline.log). A temporary agent trace captured the
actual early failure as 'An AI journal has an invalid note snapshot'; cleanup later
surfaced a misleading missing properties-pane error, so that later error is not
used as proof of an I/O defect. The corrected connected-draft regression fails
against its old comparator (encoding70-double-bom-baseline.log) and passes after
the repair. Temporary trace prints were removed. The 81 focused workspace,
agent, external-file, move and recovery checks pass (encoding70-bom-final-focused.log,
21.547 seconds), including exact original/new history text and AI apply/Undo bytes.
The full Mac suite passes all 274 tests with zero failures
(encoding70-bom-full-tests.log, 92.777 seconds). The generic iOS Simulator
build-for-testing succeeds (encoding70-ios-compile.log). These shared-source changes
have no runtime/Device-panel preview after the earlier device-opening cancellation;
that visual acceptance remains pending. Opus 5.5 milestone review is pending.

No new DMG, notarization or iOS version change was made for this development batch.
Preview 64 is still the latest delivered DMG and does not contain these repairs.
Full parity, installed native UI/IME, live providers and iOS runtime/Device preview
remain pending after the earlier access denial/cancellation.

### Encoding review repairs: cross-client headers and bounded JSON

Opus 5.5 found no main-path byte loss in its traced BOM review, and identified a
cross-client repeated-BOM YAML mismatch plus untested recursive JSON depth.
The web frontmatter owner now recognizes leading U+FEFF prefixes, matching the
native header/body/identity semantics. Its body replacement keeps the existing raw
header and CRLF rather than rebuilding it with LF. Property set/rename operations
retain the prefix that reaches the parser. Tests exercise raw strings and strings
passed through Tauri's TextDecoder behavior, which consumes one physical BOM.
This establishes parsing agreement; it does not claim a change to Tauri's file
reader or full web byte-order-marker preservation at the filesystem boundary.
The pre-fix web cases failed in encoding70-web-prefix-baseline.log; all 26 focused
frontmatter/link checks and all 184 directly dependent web checks pass afterwards
(encoding70-web-prefix-fixed.log and encoding70-web-dependent-tests.log).

A detached-task test reproduced a stack-guard crash in the unbounded recursive
JSON decoder (encoding70-json-baseline.log; local test-host crash report
Zerus Native-2026-11-18-004712.ips). NativeJSON now scans nesting before recursive
decoding and refuses more than 64 object/array levels. Brackets and escaped quotes
inside strings are ignored by that scan. The 64-level boundary, refused depths
65/512, a long bracket-only string, integer/float/boolean/null values, large signed
and unsigned integers, and duplicate-key agreement with Foundation are covered at
the persisted-JSON owner. No malformed/deep source file is rewritten on refusal.

The iOS properties panel uses hasHeader rather than treating a BOM-only prefix as
Original metadata. Its agent source comparison uses the strict prefix-preserving
UTF-8 decoder. Runtime/Device-panel visual acceptance remains pending.

The two adjacent persistence paths mentioned in the review are repaired too:
bulk-action history and organization task-link metadata use the text-preserving
JSON owner. Tests reproduce leading-mark loss from a task title and from stored
bulk-property before/after values (encoding70-metadata-prefix-baseline.log and
encoding70-bulk-prefix-baseline.log), including blocked Undo from the damaged
bulk record. Their repaired full-suite results are recorded separately.

The first review-focused set passes 83 Mac checks (encoding70-review-focused.log,
22.357 seconds). Final checks after all review repairs pass: 277 Mac tests, zero failures
(encoding70-review-full-tests.log, 83.122 seconds); generic iOS Simulator
build-for-testing succeeds (encoding70-review-ios-compile.log); both app and Node
TypeScript projects pass (encoding70-review-web-typecheck.log). The existing Vite
preview serves the updated frontmatter module, and frontend/private HTTPS /app
routes both return 200. These results cover code and isolated fixtures, not installed
native UI, IME, real providers or iOS runtime/Device-panel acceptance.
No new package or notarization has been created; Preview 64 remains the delivered
DMG. Full migration acceptance has not been established.

### Gallery and card-cover development after Preview 64

Native Gallery now offers relation grouping and local collapsed/expanded groups.
Groups include observed values in collection order. Relation lists fan out into
separate groups, exact duplicates are removed, and aliases resolving uniquely to
one target share a single group/card. Ambiguous or unavailable references retain
raw labels rather than all appearing as Unavailable note. Literal No value and
literal true remain distinct from absent values and real checkboxes. Group collapse
resets when the workspace, collection, grouping property or view mode changes.
Board relation/multi-select-list restrictions remain aligned with the desktop.
The field inventory is resolved once by the collection container and reused by
its child/card bodies, avoiding repeated full collection/schema scans per access.

Gallery/Kanban cards display the first actual Markdown image (or supported single
image HTML), excluding fenced/indented code examples. Covers use the existing
confined vault resource reader, cancellation/deadline/security-scope behavior,
and orientation-aware ImageIO downsampling to a maximum of 720 pixels. Inputs
are limited to 16,384 pixels per side and 40 MP, in addition to the existing 50 MB
resource-byte bound. Originals are never rewritten. URL schemes/external paths
remain outside this vault-reader contract; broader image/provider parity remains
in scope rather than being claimed complete.

Covers retain their current bitmap during same-note text edits and refreshes.
Requests use body text rather than the whole NoteDocument; image decoding is
cached by workspace, note path, first reference and the candidate files' own
version dates. Unrelated file dates do not invalidate covers. The decoded cache
has a 32 MB budget, and unknown modification versions are not cached. A shared
FIFO pool admits at most two reads/decodes; either free permit can admit the next
card, and queued cancellation removes/resumes its waiter. Cross-vault/note identity
changes hide old images immediately, and cancelled results cannot publish later.
Board cards are lazily instantiated. Real provider stalls and in-flight cancellation
still require broader acceptance; the automated cancellation case is pre-cancelled.

The first 33 focused tests passed before the review repairs. An offscreen SwiftUI
render check caught the initial empty-Group placeholder never starting its task;
a stable container fixed it. Inspecting its rendered fixture also caught intrinsic
image width overflowing a grid cell; GeometryReader now constrains crop width.
The final pixel oracle allows macOS colour conversion and independently detects
both the initial green cover and its externally replaced blue cover without
changing note bytes. Earlier empty-collection fixture mistakes and strict-colour
assertion failures are not counted as product bugs.

Opus 5.5 found no blocking defect and requested dimension guarding and stable
cover reuse. Both are repaired locally. Its lower queue, relation-header and field
inventory findings are also addressed as described above. The oversized-header
regression initially accepted a 20k-by-1 image (collections71-dimensions-baseline.log);
it now also checks a 49 MP header while the guard is present. Disabling cache
lookup makes the frozen-version/text-edit regression attempt an unnecessary
read of a deliberately unavailable fixture image and fail
(collections71-cache-baseline.log). The repaired focused set passes 34 tests
(collections71-review-final-focused.log, 6.935 seconds).
The pre-review full suite passed 280 tests (collections71-full-tests.log,
84.860 seconds). Final post-review full checks pass all 281 Mac tests with zero failures
(collections71-review-full-tests.log, 84.946 seconds). Disabling relation alias
binding makes its owner regression fail on duplicate groups and missing target
identity (collections71-alias-baseline.log); the repaired source is restored.
These tests are
isolated fixtures, not installed native UI, keyboard/VoiceOver or real-provider
acceptance. No iOS implementation changed in this Mac-only batch.

Preview 64 remains the delivered DMG and does not contain encoding70 or these
collection changes. A new local, non-notarized DMG will be packaged after checks.

### Preview 65 handoff preparation

README was reviewed against the preview's features, supported Apple Silicon/macOS
26 platform, setup/build commands, native dependencies and incomplete-parity
limitations before advancing the Mac preview build from 64 to 65. Version 0.3.34
is unchanged. Preview 65 combines the reviewed encoding70 repairs and collections71
Gallery/covers work. It remains an ad-hoc local test channel; no notarization or
iOS version change is requested. The iOS shared-code compile from encoding70
remains the latest applicable check; collections71 changes only Mac sources.

The package must pass Release, mounted payload, identity/version/minimum OS/arm64,
signature, DMG and private HTTPS checksum checks before delivery. Installed native
launch/UI, real providers, IME/VoiceOver and full migration acceptance remain pending.

The final Preview 65 suite passes all 281 Mac tests with zero failures
(preview65-final-tests.log, 85.067 seconds). A last candidate check reproduced
an encoded-unreserved-letter asset path borrowing the fallback's version date
(collections71-encoded-version-baseline.log). Cache candidate priority now uses
the same decoded relative-path rule as the vault reader, and the real-file
unknown-version/root-to-relative fallback case passes in the final suite. The
first package candidate is superseded before handoff; Release/DMG checks are
rerun for the corrected source. There is no new notarization.

Preview 65 is delivered as `Zerus-Native-0.3.34-preview-65-arm64-local.dmg`.
Release and mounted payload checks pass: version 0.3.34/build 65, macOS 26 minimum,
arm64 executable and verified ad-hoc signature. The final private HTTPS download
matches SHA-256 `b1d6eab5234ec4a15cf76aa43ccbf10f48e88dae0387bc774c31290ca68bd787`.
`artifact-preview-65-local.json` and `preview65-verification.json` record the checks;
`preview65-source-manifest.json` fingerprints 265 Release/configuration inputs,
not a complete reproducible source snapshot. Preview 65 supersedes Preview 64 as
the latest delivered intermediate DMG. No notarization or iOS build-number change
occurred. Installed UI/provider/IME and full desktop parity acceptance remain open.


### Kanban drag/drop lifecycle (board72, after Preview 65)

Cards and column headers now use one private, process-only Transferable type with
separate note/column cases. Plain-text drops cannot invoke board mutations.
A transfer records its workspace activation, collection/folder identity, grouping
schema, visible-note membership, query and column order. The receiving board must
match those values, must contain every dragged path and the target column, and
must be idle. A card already in its destination is a no-op. Preparing a note move
rechecks the scope after saving/scanning; single-note changes use the existing
bulk commit, and multi-note or partially refused changes retain explicit review.
Existing property history supplies Undo. Column drops shift the intervening
columns (desktop arrayMove semantics), persist the shared boardColumnOrder and
preserve other saved-view fields; left/right buttons use the same path.

Owner coverage extends the existing typed board/calendar move test rather than
repeating its property/Undo assertions. A new lifecycle/persistence test exercises
a real NSItemProvider Transferable export/import before column reorder, checks
intervening order and foreign saved-view fields, rejects an old order, and refuses
a delayed card after switching collections with otherwise identical schema,
visible membership and column order. Empty/outside-note and unavailable-column
payloads are refused. The first focused run passes 35 tests (board72-focused.log);
the native transfer check also passes (board72-transfer-tests.log).

The first full suite passes 282 tests (board72-full-tests.log, 87.207 seconds).
Opus 5.5 reviewed the milestone with no high-severity finding. These are self-owned test fixtures;
installed native pointer routing, dragging over cards, keyboard/VoiceOver and
provider-stall acceptance remain pending. No iOS source changed. No new DMG or
notarization is prepared for this individual change; Preview 65 remains delivered.


Opus review follow-up: the native Info.plist now exports the custom board type
with public.data conformance. The actual built Debug app's Info.plist was checked,
in addition to the real NSItemProvider roundtrip. This repairs declaration risk;
it does not establish installed drag-session routing. Columns show targeted
outlines. Reorder controls and handlers refuse overlapping operations. Dragging a
selected card includes only currently visible selected notes, so stale hidden
selection entries cannot prevent an otherwise valid visible-note move.

A prepared board commit rechecks its scope and holds the workspace busy during
its write; vault switch and close already refuse that hold. Column persistence
holds the same lock. Context-menu moves use the same typed preparation and commit
path. Pending reviews are cleared on collection/group changes and rechecked on
Apply. A same-column card drop is refused without an empty review. The owner
move test now covers number/checkbox typing, clearing via the no-value column,
and busy commit refusal, alongside the existing property/date Undo contract.
Removing the busy admission guard makes that regression fail at the expected
commit boundary (board72-busy-baseline.log); the repair is restored before final
checks. Focused repaired and typed runs pass (board72-review-tests.log and
board72-typed-tests.log). Final full checks pass all 282 Mac tests with zero failures
(board72-final-full-tests.log, 85.779 seconds). board72-verification.json records
the source fingerprints, bundle declaration and preview readiness checks.

Non-folder collection layouts also persist locally in the Mac navigation record;
folder layouts additionally share views.json with other clients. The review's
session-only concern does not match persistNavigation/restoreCollection. Native
and desktop group pickers both exclude multiple-value list fields (the desktop
handler's listMultiple conversion is not itself evidence that the picker allows
one). The reserved __no_value__ collision exists in both clients and remains a
known wire-format limit. None of board72 is in the already delivered Preview 65.


### Native indented code development (indented73, after Preview 65)

The parity-source check found that desktop global search indexes Markdown/file-hub
reference text, not Office/RTF/OCR extraction (`buildSearchItems` in global-search.ts).
That extraction is an optional extension rather than an existing desktop feature.
The authenticated Drive folder browser lives in the mobile component; Mac desktop
file-location parity uses Finder-folder mappings. This audit does not remove the
remaining native provider/mapping interoperability acceptance requirements.

Top-level indented Markdown code now uses the same native code text view as fenced
blocks. Discovery uses swift-markdown CodeBlock source ranges and four-column
space/tab indentation; nested code in lists or quotes still uses Source mode.
Untouched blocks preserve their original spelling and line endings. Changed code
retains its first four-column indentation prefix and LF/CRLF convention, with
literal text kept outside inline formatting or link completion. Empty bodies or
leading/trailing blank code lines use fenced Markdown on save, since indented code
cannot retain those edges. The original native token remains available for Undo.
Cmark source ranges can include trailing blank separator lines; those are kept
outside the editable code token so an edit cannot consume the following gap.
Code-sheet lookup maps the requested source block to the complete top-level
code-block order, including indented tokens that have serialized as fences.

The new owner regression failed the original source-mode gate before the feature
(indented73-baseline.log). Focused owner checks pass after implementation
(indented73-boundaries.log): spaces/tabs/mixed indentation, LF/CRLF, literal Markdown
and Unicode editing, following prose, Undo/Redo, empty/blank-edge bodies, internal
blank lines, and fenced-sheet changes after an indented block. The initial edit
check caught the trailing-gap loss described above. Full-suite and Opus 5.5 review
are running. No iOS code or version changes, new package or notarization occurred.
Installed text-system/IME and full rich-editor parity acceptance remain pending.


The first indented73 full run had one failure: an earlier literal-indentation test
still asserted that a real indented code block requires Source mode. Its literal
text, entity and explicit Source-edit contracts passed. The obsolete default-mode
assertion was removed; the new native code owner retains the gate contract.
The repaired Document/Clipboard/Workspace owner run passes
(indented73-owner-tests.log), including EOF, mixed code forms and blank-edge cases.
The final full suite is running on that source; review remains pending.


Opus 5.5 review found two high issues and three smaller gaps. Repairs now verify
that each indented native token still parses as its own top-level CodeBlock after
serialization; preceding list formatting or merged blocks force a fenced spelling
rather than silently changing ownership. The owning native editor test reproduced
bullet/ordered conversion of prose and headings losing the block before repair
(indented73-list-crlf-baseline.log). Fenced fallback joins body and fence lines
using the original newline convention, fixing the CRLF failure in that same log.

All Mac table discovery, menus, clipboard recognition and sheet lookup exclude
both forms of code. This prevents mixed-indent table-shaped code being rendered
as a table (indented73-table-baseline.log) and overlapping width-marker ranges.
The exact width-marker example from the review is also covered through native
render/serialize/source-mode checks. The review's scratch probe reproduced the
pre-fix overlapping-range crash; the owner mixed-table regression failed without
crashing the test host. Disabling code creation also converts formatted indented
paste to literal prose; its real paste regression failed before the conversion
was added (indented73-preference-baseline.log).

Code sheets map all top-level code nodes to all native code tokens, so an indented
token that now saves fenced can be edited without reload, as can its following
fenced block. Exact snapshot checks and Undo/Redo remain in the owner test.
The repaired Document/Clipboard/Workspace run passes 103 tests
(indented73-review-fixed-tests.log). The earlier complete run passed 283 tests
before these review repairs (indented73-final-full-tests.log, 87.608 seconds);
that log is not final evidence for the repaired source. Final checks and the
next local package remain pending. No new notarization is performed.


### Preview 66 preparation

README was reviewed against the current native features, Apple Silicon/macOS 26
platform, selected Xcode/XcodeGen/SwiftPM setup, commands, dependencies and pending
acceptance before advancing the native build from 65 to 66. Marketing version
0.3.34 is unchanged. Preview 66 combines board72 and indented73; the local ad-hoc
DMG remains the intermediate route, with no notarization, iOS build-number change,
commit/tag or production release. The repaired code-sheet lookup regression fails
under the earlier fenced-only lookup (indented73-sheet-baseline.log), and the
source repair is restored before final checks and packaging.


Preview 66 final source passes all 283 Mac tests with zero failures
(preview66-final-tests.log, 86.503 seconds), after the Opus repairs and all
negative-control source restoration. Release/local-DMG packaging follows;
installed native pointer/IME/VoiceOver/provider acceptance remains pending.


Preview 66 Release and mounted payload verification pass: 0.3.34/build 66,
arm64, minimum macOS 26 and verified ad-hoc signature. All 268 recorded source and
configuration fingerprints remain unchanged through the build and cover the 260
actual arm64 Release Swift inputs, including the new board/indented-code sources.
The final package refreshes this testing guide. Source fingerprints are not a
complete reproducible build snapshot. Installed launch/drag/IME/provider acceptance
and full desktop parity remain pending; no notarization occurred.


Preview 66 is delivered as `Zerus-Native-0.3.34-preview-66-arm64-local.dmg`. The final private HTTPS download
matches SHA-256 `3d730facd365be84f62c71dbabb92c32ee2494dd45e9dd1333bdd342b8d7703c`.
`preview66-verification.json` records test, review, source and package evidence.
The first guide-refresh candidate is superseded; the final Release log is
`preview66-release-final.log`. Preview 66 supersedes Preview 65 as the latest
intermediate DMG, with no notarization or iOS build-number change.


### Native CLI and skill installation (cli74, after Preview 66)

The native build reuses src-tauri/crates/zerus-cli and the canonical desktop
zerus-skill.md, rather than implementing another CLI. Staging builds the locked
Rust CLI, checks --version against Cargo.toml, ad-hoc signs the arm64 helper and
writes a bounded manifest for CLI 0.3.0 / skill 3. Native resources use a folder
reference so the executable remains executable. Packaging copies freshly staged
resources, signs the nested helper first, refreshes its byte hash, then signs the
outer app. Artifact checks verify nested signature/channel/team and compare the
manifest against freshly staged version, skill bytes and pre-distribution-signing
CLI provenance. This catches an old, internally consistent Xcode resource copy.

Settings opens a native CLI and agent skills sheet with local destination review,
install/reinstall, three desktop-compatible skill destinations and Markdown export.
The installer reads the bundled manifest/assets, compares a reviewed destination
snapshot, writes/chmods a same-directory temporary file and atomically replaces the
target. A new destination uses macOS RENAME_EXCL, preventing a late file creation
from being overwritten. Existing POSIX permissions are preserved; the CLI gains
owner execute permission. Existing file metadata beyond permissions is not promised
by an atomic replacement. Prepare/install refuse symlinked or non-ordinary targets.
Status reports such destinations per row, so an unusual skill does not hide other
installation actions. Merely checking status never executes an existing CLI;
a different byte build is reported without claiming its version is known.

Owner tests use temporary homes/resources and the real bundled CLI: installation,
execution, PATH recognition, desktop skill locations and new permissions, export,
private export replacement, stale review refusal, no execution of a marker script,
symlink refusal, invalid export suffix and changed/unsupported bundle assets.
The Opus 5.5 review found a whole-sheet status failure and test gaps, with no
blocking finding. The new status/perms regression reproduced the failure before
repair for linked/oversized entries in all four destinations and a private export
losing mode 0600 (cli74-status-permissions-baseline.log). It now also performs an
unaffected install while the bad entry remains, rather than checking flags alone.
Three repaired owner tests pass (cli74-review-final-tests.log).

Copied Debug-host signing checks pass with the XCTest plug-in removed and Debug
dylibs signed. They prove helper signing/manifest refresh and copied-app resource
validation, including changed-resource and stale-provenance refusals; they are not
Release, Developer ID/notary or installed-app acceptance. The initial probe retained
an unsigned XCTest plug-in and failed deep verification for that fixture reason.
The earlier full suite passed 285 tests before the review repairs
(cli74-full-tests.log, 86.089 seconds). The final suite is running on repaired code.
No real home installation, personal vault change, iOS implementation/build-number
change or new DMG occurred. Preview 66 remains the latest delivered build.
Vault registration and the desktop's reviewed hidden-metadata preparation remain
next in scope; installation alone does not complete CLI parity or the migration.


Final cli74 checks pass all 286 Mac tests with zero failures
(cli74-final-full-tests.log, 84.943 seconds). The current Release build also
succeeds; its copied app and nested helper pass ad-hoc signature, manifest and
staged-provenance verification (cli74-release-build.log, cli74-release-signing.log,
cli74-release-check/verification.json). This is actual Release validation, distinct
from the earlier copied Debug-host probe. cli74-verification.json records the
evidence and source fingerprints. There is no new DMG or notarization; the
installer foundation is not yet in delivered Preview 66.

## CLI vault setup development after Preview 66 (cli75)

The native CLI sheet now offers an explicit vault setup flow. Registration previews
its vault identity, machine-local `Application Support/zerus/vaults.json` entry,
previous location and default choice before writing. Unknown catalog and identity
fields and other vault registrations are retained. An unreadable/unsupported
catalog is refused. A changed review cannot replace later catalog edits. The vault
identity and catalog span two locations; if catalog commit fails after identity
creation, the app reports that partial outcome and keeps the identity for retry.

The separate metadata review scans ordinary notes and Trash, excluding managed
hidden folders. It previews each changed note and CLI readiness manifest. It adds
UUIDs only where absent, renames legacy `grimoire-*` keys, and normalizes reserved
boolean flags. Invalid/duplicate IDs, conflicting keys, complex reserved YAML and
unterminated frontmatter block applying the whole review. Foreign YAML, comments,
BOM prefixes, line endings and body text remain in place. It does not import the
legacy Tauri application's out-of-file pin/archive state; that migration remains
separate. Registration alone does not prepare notes.

Metadata preparation saves open note drafts first and refuses unresolved note or
connected-file conflicts. Applying holds all windows on the same physical vault,
checks the reviewed note set and exact bytes, and coordinates retained connected
recovery drafts with the vault transaction. Late writing remains a private draft
and blocks commit. A successful identity upgrade updates clean editors without
reporting an outside replacement. If the post-commit scan fails, the error says the
metadata was already applied rather than claiming a rollback.

CLI 0.3.1 / skill 4 fixes shared Rust parsing/editing for native BOM-prefixed notes
and comments on reserved scalars. Nested foreign keys cannot masquerade as IDs.
The Rust baseline reproduced both failures before repair; final Rust checks pass
22 core tests and 25 CLI integration tests (cli75-core-baseline.log,
cli75-rust-tests.log). No dependency or iOS Swift/build-number change was needed.

Five native owner tests initially pass (cli75-setup-tests.log), covering reviewed
registration, preservation and identity adoption, blocked metadata, stale note
sets/recovery drafts, and late writing. The final version adds a real bundled CLI
read of a natively prepared BOM/CRLF note. The full native suite passes 291 tests with zero failures
(cli75-full-tests.log, 87.489 seconds). The final formatted Rust sources also pass
22 core and 25 CLI integration tests (cli75-rust-final-tests.log). Opus 5.5 review
is still in progress. The Release build and copied-app ad-hoc signature, nested
CLI manifest/provenance and resource verification pass (cli75-release-build.log,
cli75-release-signing.log, cli75-release-check/verification.json). No real home registry/CLI installation or personal vault change
was performed, and no new DMG has been made. Preview 66 contains none of cli74/75.
Installed UI, keyboard/IME, Developer ID/notary acceptance and complete migration
parity remain pending.

### Native PDF password preview (pdf76, after Preview 66)

The current desktop PDF viewer accepts a password; the native viewer previously
only displayed an instruction to open locked PDFs externally. Development now
adds a secure password field and Unlock action to the native PDF viewer. Incorrect
passwords keep the document locked and allow another attempt. Search, page and zoom
controls remain disabled until unlocking succeeds. Successful unlocking attaches
the document to PDFView and enables the existing search/navigation controls.

Passwords are cleared from the view field after every attempt and on dismissal;
they are not saved to preferences, Keychain, the vault or the file. Unlocking affects
only the current preview. The original PDF is never rewritten/decrypted. A fresh
preview asks again. The owner test creates a real two-page encrypted PDF, checks a
wrong password, unlocks it, searches/navigates, verifies exact original bytes and
opens a second locked reader. Installed secure-field/keyboard acceptance remains
pending; this implementation does not change document extraction for AI context.

The two PDF owner tests pass (pdf76-password-tests.log). README was reviewed for
current native features, macOS/architecture requirements, selected toolchain,
Rust/SwiftPM dependencies, commands and limitations before preparing native build
67. The application version remains 0.3.34 and iOS configuration is unchanged.
Preview 67 full-suite and CLI milestone review are pending; no DMG is delivered yet.

### CLI setup review repairs before Preview 67

Opus 5.5 found no blocking defect, but reproduced two cross-client issues: setup's
inventory omitted hidden-name and `.markdown` notes, and UUID spellings accepted
by Rust could disagree with exact native stable-ID lookups. It also identified
indented frontmatter delimiter parsing, unclosed-header property writes, a hidden
registration rename and needless manifest formatting changes.

New regressions reproduced the omitted notes and four noncanonical UUID forms
(cli75-review-native-baseline.log), plus a CLI-written ready manifest being
reformatted (cli75-review-native-manifest-baseline.log). The setup inventory now
matches the CLI's ordinary-file traversal, including hidden names, both suffixes
and Trash, while skipping symlink entries and other hidden directories. Every
reviewed note remains protected by its exact before bytes. Noncanonical UUIDs are
blocked with an explicit request to resolve the ID and its links together;
setup does not silently rename identities or rewrite references. This restriction
is specific to CLI readiness, not native note browsing/editing.

An already-ready manifest keeps its exact original bytes and foreign fields.
Registration confirmation explicitly shows an old/new registered name. The review
explains reserved-flag normalization and the CLI hint explains the registered
default. Stale metadata errors say the note changed after the review, including
when this app saved newer writing, rather than calling every edit external.

Rust regressions reproduced an indented YAML delimiter hiding the real ID and a
property edit wrapping an unclosed header into a new one
(cli75-review-rust-baseline.log). All three header readers now require a delimiter
at column zero, and property/state/ID edits refuse unterminated headers. The final
Rust run passes 24 core and 25 CLI integration tests
(cli75-review-rust-tests.log). Focused native repair checks are in progress. No
additional review delegate was started for these bounded repairs.

Known limits remain: metadata setup does not import the Tauri localStorage pin/
archive overlay; conflicting/outdated registry edits fail closed, but Swift/Rust
writers do not share an atomic cross-process compare-and-swap; and installed
UI/keyboard/IME acceptance is pending. Preview 67 has not yet been delivered.

The repaired CLI/setup/PDF focused run passes all 11 tests
(cli75-review-fixed-tests.log). Preview 67 is running the final full suite against
those repairs. Its package will be ad-hoc only; no Apple notarization request,
iOS archive/upload, production desktop/Windows/Store release or Git publication
is part of this intermediate handoff.

### Preview 67 verified intermediate handoff

Preview 67 packages cli74 installation, cli75 reviewed vault setup and pdf76
password unlocking. The final build-67 suite passes all **293 Mac tests**, zero
failures (preview67-final-tests.log, 88.519 seconds). Rust passes 24 core and 25
CLI integration tests; the focused native repair set passes 11 tests.

`pnpm desktop:build --native --local` succeeds (preview67-release.log). Its actual
DMG is read-only mounted and checked against native project identity/version/build,
arm64/macOS minimum, signature channel, app executable and CLI manifest/resources.
CLI 0.3.1 and skill 4 are present; both app and helper signatures are ad-hoc.
`artifact-preview-67-local.json` records the mounted artifact. The private HTTPS
download returned 200 and its SHA-256 matches the verified DMG:
`20af9b2f5084048d2f8571755532517713db4b4d0509f4b14d93fab458a0a14a`.

`preview67-verification.json` consolidates evidence. All 282 source/configuration
fingerprints stayed unchanged through packaging, covering all 264 actual arm64
Release Swift inputs (preview67-source-manifest.json). These fingerprints are not
a complete reproducible-build dependency snapshot; the tree remains dirty.
The app executable SHA-256 is
`7fbd6e18f78788463edacd9ddb8a9cb0d635ac2d9b8e76557f340faf25f2fa5e`.
The Read before testing file inside the DMG reflects the preparation snapshot;
this later section records the completed artifact/download verification.

No notarization was submitted. Installed app launch/pointer/keyboard/IME/VoiceOver,
real-provider acceptance and complete desktop parity remain pending. No production
release, Windows/Store release, iOS source/build-number change, tag, commit or push
was made. No real home CLI/registry install or personal vault modification was
performed during verification.

### Default new-note folder development after Preview 67 (default77)

The existing desktop uses the chosen default type in every type-neutral section,
with an explicitly selected folder taking precedence. Native development now
provides Settings → New notes → Default folder. This preference is stored on this
Mac separately for each canonical vault location and starts as Inbox. Selected
folder views and explicit linked-note destinations override the default. Existing
ordinary folders are offered; a remembered externally removed folder remains the
creation target and is recreated, matching the desktop preference contract.
Malformed stored paths fall back to Inbox; invalid, stale-activation and busy
settings changes are refused. No preference is written into shared vault metadata.

Peer windows read the same preference directly, without stale cached copies to
overwrite it. A folder rename remaps a default in that folder or a descendant;
Trash resets it to Inbox, and restoring the folder does not change the new default.
Folder commits now hold their window busy and re-check root/activation after IO
before adopting the snapshot or updating local preferences.

Workspace owner tests create real notes from all eight global sections, a selected
folder, an explicit target and a reopened workspace; they exercise a peer's change,
a separate vault, malformed preference input, folder rename/Trash/restore and stale
or busy settings. The first 33-test run passed (default77-workspace-tests.log).
An additional timing regression reproduced a note being redirected from Work to
Other when a peer changed the default after creation began
(default77-creation-baseline.log). Creation now captures its destination before
busy/save awaits; that change applies to the next note. All 33 workspace tests pass
on the repair (default77-final-workspace-tests.log, 8.365 seconds).

The full native suite and Opus 5.5 review are in progress. This development is not
included in delivered Preview 67. No iOS source/build-number, new DMG, notarization,
real home CLI installation or personal vault change occurred. Installed settings/
keyboard/IME and complete desktop parity acceptance remain pending.

Final default77 suite passes **295 Mac tests**, zero failures
(default77-full-tests.log). default77-verification.json records source fingerprints,
focused/baseline logs and pending review. The existing Preview 67 DMG remains
unchanged; this small settings addition is not packaged separately.

### default77 review repairs

Opus 5.5 found that the New notes sheet recaptured its workspace ID on every
redraw. It now stores the opening activation in SwiftUI State, refuses queued
writes after a vault change, disables the picker and displays a reopen message.
A self-owned hosted-view probe could not expose SwiftUI's folder picker as an
NSPopUpButton; that temporary probe was removed, and no UI acceptance is claimed.
The model guard tests remain valid but do not establish the sheet's lifecycle.

The review also identified creation-flow differences. Regressions reproduce the
native jump into the destination folder (default77-review-baseline.log) and root-
note link creation ignoring the default (default77-link-baseline.log). Creation
now preserves All Notes, Pinned, Archive or the selected folder; Trash, Tasks,
External Notes, Files and Links fall back to All Notes as on desktop. It clears
search/list filters to the created-descending default, opens the new note without
forcing its folder, and preserves a valid saved section when reopening. A further
regression reproduced Archive/Pinned reopening as Work
(default77-reopen-baseline.log). Root/hidden-note link creation uses the configured
default when no ordinary source folder exists. Explicit link destinations remain
unchanged.

New document requests freeze the default before asynchronous preparation; their
folder picker starts there and retains Files (unfiled) as an explicit option. The
owner test creates a document note through the captured request after a peer
changes the preference, then checks its destination and unchanged original bytes.
The repaired workspace run passes 35 tests (default77-review-tests.log). The full
run is in progress. These bounded repairs do not trigger another review delegate
or a new DMG; Preview 67 still lacks default77.

The post-review suite passes 297 tests (default77-review-full-tests.log,
91.124 seconds). A subsequent Inbox regression reproduced a visible failure:
with existing lowercase `inbox`, native creation returned `Inbox/...` while the
scan contained `inbox/...`, so the new editor did not open
(default77-inbox-baseline.log). Defaults/options now use an existing Inbox variant
without adding a nonexistent duplicate. Exact real folders remain distinct on a
case-sensitive filesystem; existing names are not renamed or sanitized.

Creation also follows its generated stable ID to the actual scanned path before
opening/returning it, which handles a directory's case changing during the save.
The owner fixture performs a real two-step directory rename during creation and
checks the returned/selected path against an independent filesystem listing.
The 36-test workspace run passes (default77-inbox-workspace-tests.log). Extending
that fixture to an explicitly saved lowercase choice reproduced a stale `inbox`
preference after the directory became `INBOX`
(default77-inbox-stored-case-baseline.log). Inbox aliases now follow existing
spelling when their exact saved folder is absent. Arbitrary custom folder names
still retain the existing exact-path/recreation contract. The final full suite
is running on these repairs; no new DMG or iOS change was made.

The final default77 suite passes all **298 Mac tests**, zero failures
(default77-final-full-tests.log, 91.023 seconds). No default77 code changed after
that run until subsequent unrelated date78 integration. Full installed settings
acceptance and the overall migration remain pending.

### Numeric date-format development after Preview 67 (date78)

The desktop's date preference offers DD/MM/YYYY, MM/DD/YYYY, YYYY-MM-DD and
DD.MM.YYYY, defaulting to day/month. Native Settings now offers the same device-
local choices with examples. Typed date properties in the inspector, table cells,
Gallery groups and Kanban labels, accepted date filter values, scheduled/due task
labels and completion-date labels follow that preference. Column/group identities
and stored values remain unchanged. Calendar month headers and ordinary activity
history timestamps retain their native date/time presentation.

A reusable native date field provides numeric entry and an optional native calendar
popover. Property, bulk-property, scheduled/due task and property date-range filter
controls use it. Property/bulk/task Save paths refuse invalid pending dates; explicit
clear/delete actions remain separate. Fields retain incomplete/invalid text instead
of normalizing an impossible day. A format change during editing does not reinterpret
the pending text; a successful blur/Return applies the current display preference.
Filter dates publish on blur/Return or calendar selection, avoiding persistence of
intermediate valid prefixes. Other editors update their local unsaved ISO draft
only from valid input and still require their explicit save/review action.

Formatting calendar-only YYYY-MM-DD strings does not pass through a timezone or
Date object. Zoned completion timestamps are shown on their local calendar day.
Offset-free ISO wall times retain their local date spelling. Invalid/non-date
values remain visible. Vault Markdown and JSON still store ISO values; this is a
local presentation setting, with no shared storage-format migration or iOS change.

The first three owner tests pass (date78-focused-tests.log): all four formats through
real self-owned NSTextField/field-editor input, invalid input retention, live format
changes while typing, deferred filter commits and timezone/invalid-date contracts.
The integration set passes 40 tests (date78-integration-tests.log), including the
workspace and compact task controls. Final full-suite and Opus 5.5 review are in
progress. Native calendar-popup, IME, full installed keyboard and persistence-flow
acceptance remain pending. No date78 code is in delivered Preview 67, and no new
DMG or notarization has been made for this settings batch.

### Date review repairs and Preview 68 preparation

Opus 5.5 found a task-backed required-field bug and a Due-field lifecycle bug.
New real MacTaskEditor fixtures reproduced Scheduled clearing into its created-
date fallback and Due disappearing during replacement (date78-review-baseline.log).
Required empty input now stays invalid without publishing it. Optional Due input
updates the unsaved task model while an explicit form visibility state keeps its
editor mounted, including after clearing or blur; disabling the toggle still
removes it. Reload resets that visibility override. This avoids losing the field
or depending on a blur arriving before Save.

The same baseline reproduces imported timestamp fields opening as invalid,
minute-precision zoned timestamps displaying raw, and empty required filter input
silently reverting. Imported timestamp fields now display their local day without
rewriting the underlying value on focus/blur. Explicit property Save converts an
edited/accepted date to its canonical day. Minute-precision zoned timestamps are
expanded for parsing; calendar-only values still bypass timezone conversion.
Required empty filter text remains visible/invalid with the prior criterion kept.

A second owner regression proves visiting a legacy Scheduled fallback created a
private dirty draft under the earlier unconditional blur setter
(date78-legacy-blur-baseline.log). Equal-value/no-op field callbacks and untouched
blur no longer assign into the model. The temporary negative-control source was
restored before verification. Unmounting no longer sets a shared validity flag to
true, avoiding the speculative bulk-field ordering issue identified in review.

All eight final date/task owner tests pass (date78-final-focused-tests.log),
including native task bindings/private drafts, field-editor Escape with the real
task form's cancel action present, Return/blur on deferred filters, all formats,
unknown-preference fallback, invalid text and timestamp/timezone fidelity. The
fixtures check that tasks.json stays unchanged until an explicit save. These are
self-owned test windows, not installed-app acceptance or full window-shortcut/
calendar-popup/IME coverage. No further review delegate was started for the repairs.

README was reviewed against the accumulated default77/date78 features, platform,
selected toolchain, Rust/SwiftPM dependencies, commands and limitations before
preparing native build 68. App version remains 0.3.34; no iOS version/source changed.
The final build-68 suite is in progress. Its next DMG will be local/ad-hoc only;
Preview 67 remains the delivered artifact until package/download verification.

The final Preview 68 suite passes **305 Mac tests**, zero failures
(preview68-final-tests.log, 97.511 seconds). Packaging is now using
`pnpm desktop:build --native --local`; no notarization submission is made.

### Preview 68 verified intermediate handoff

`pnpm desktop:build --native --local` completed successfully
(preview68-release.log). The actual DMG was mounted read-only and verified against
the native project's identity/version/build, macOS minimum, arm64 architecture,
signing channel, executable and bundled CLI resources. CLI 0.3.1 / skill 4 remain
included. App and helper signatures are ad-hoc; notarization was not submitted.
`artifact-preview-68-local.json` records the mounted payload.

The private HTTPS download returns 200 and matches the verified DMG SHA-256:
`baae7c64b741a43a99e9e66eccc67b99d11f0eace7c4d12d37018c50b44c829d`.
The app executable SHA-256 is
`a72b00e5807e5912b64592060d932e301c456c97165c5934727f8fe6228c1046`.
All 284 source/config fingerprints stayed unchanged through packaging and cover
all 266 actual arm64 Release Swift inputs (preview68-source-manifest.json).
This is not a complete reproducible-build dependency snapshot; the tree is dirty.

`preview68-verification.json` consolidates the 305-test result, focused checks,
review/repair evidence and artifact/download receipts. The Read before testing
file inside the DMG reflects the preparation snapshot; this later section records
the completed handoff. Installed app launch/calendar/keyboard/IME/VoiceOver and
live-provider acceptance remain pending. Rich-editor interleaved containers and
other full-parity work remain in scope. No iOS source/version/archive/upload,
production desktop/Windows/Store release, Git commit/tag/push or personal vault
change was made for this intermediate package.


### List 79: list-type ownership and embedded-block admission after Preview 68

Changing a nested or quoted list item's type now keeps its quote/depth and
adjusts actual descendants for marker-width changes. The command pairs native
item paragraphs with the current Markdown tree, so differently indented siblings
and compact quote-prefix spellings are not mistaken for parent/child boundaries.
Nested selections compose padding changes once; Undo restores the whole command
and its selection. Details and baseline evidence are in
`docs/native-macos-list-continuations.md`.

Two Opus 5.5 read-only reviews covered the initial and parser-owned algorithms.
The second found that embedded fences/tables could bypass source admission when
card ranges were stripped before container ownership was checked. The repaired
admission now checks the original tree first. Its workspace-level regression
reproduces the issue before the fix, then opens/saves eight real-file cases with
exact content checks. Standalone code/table cards remain native; embedded blocks
remain source-only pending native container support.

Final validation: 308 Mac tests, zero failures
(`list79-reviewed-full-tests.log`); source fingerprints and evidence status in
`list79-verification.json`. Web and private HTTPS `/app` readiness both return
200. Preview 68 is still the latest delivered DMG and does not include this batch.
No iOS change, new notarization or installed-app acceptance is claimed. Full
parity, including rich interleaved paragraphs after child lists, remains active.


### List 80 core and Return, still before interleaved rich admission

The native engine now represents a list item's marker and its paragraph groups
after child lists with one immutable local identity. It retains original tokens,
uses the live marker width when saving continuations, and preserves them through
ordinary edits, list-type changes and Undo/Redo. Core review findings involving
literal checklist text, quoted marker spacing, inline shortcuts and the next
plain paragraph's ownership have native regressions and repairs.

Nonempty Return creates a new sibling identity and transfers only later content;
9-to-10 marker-width changes adjust actual following descendants. Literal text
that resembles a native list marker survives the split. Full current validation
passes 313 Mac tests (`list80-return-full-tests.log`); Return's new Opus review is
pending. See `docs/native-macos-list-continuations.md` and
`artifacts/native-macos/list80-verification.json` for scope and evidence.

Interleaved notes still open as source until keyboard/subtree and container
commands are complete. No new source admission, iOS change, DMG or notarization
is included in this development stage. Preview 68 remains the latest handoff.


### List 81: whole-item Tab/Shift-Tab before rich interleaved admission

Indentation now uses actual parsed item ownership and list containers. Whole
subtrees move together; parent trailing paragraphs and remaining children keep
their owners. Opus 5.5 findings involving tight-list spacing, numbered starts
and selection movement were reproduced in native tests and repaired. The earlier
Return index-stability review is also repaired with a real editor regression.
Final validation: 316 Mac tests, zero failures
(`list81-reviewed-full-tests.log`). See `docs/native-macos-list-continuations.md`
and `artifacts/native-macos/list81-verification.json` for exact scope/evidence.

Continuation formatting, head removal, paste/shortcut identity and empty-tail
Return are still unfinished; interleaved files remain source-only. Preview 68
is unchanged. This is development evidence, not installed-app or full-parity
acceptance, and includes no iOS change or new DMG.


### List 82: checkbox and list-type commands from continuations

Checkbox toggles and list-type commands in a trailing paragraph now address its
owning head. Selected targets are deduplicated, descendant widths follow the
parsed tree, and continuation selection/typing context survives the command.
Native regressions fail before the repair; all 83 document/clipboard tests and
all 317 Mac tests pass afterward. Independent web parsing confirms the saved
ownership. Opus 5.5 then identified a headless-continuation regression after
heading/quote conversion. It is reproduced and repaired; the expanded 36-scenario
owner test also covers collapsed carets and multi-paragraph target deduplication.
The final full-suite rerun passes 317 tests, zero failures
(`list82-reviewed-full-tests.log`). Evidence and fingerprints are in
`list82-verification.json`.

Head removal, non-list conversion, shortcut/paste identities and empty-tail
Return remain unfinished. Normal interleaved admission remains source-only.
No new DMG, installed/IME acceptance or iOS change is included; Preview 68
remains the delivered artifact.


### List 83: shortcut ownership and numbered tasks

Checklist shortcuts retain an existing item's identity, keeping its trailing
paragraphs after child lists attached. Direct empty-prefix construction also
preserves CRLF and avoids literal bracket text in quoted shortcuts. Numbered
tasks retain both number and checkbox in native display, toggle at the checkbox
glyph, and continue with an incremented unchecked marker on Return.

The expanded shortcut, Return and offscreen zoom/pointer owners pass. Full
validation: 317 Mac tests, zero failures (`list83-full-tests.log`), plus GFM
ownership/task-state checks (`list83-web-parser.log`). Opus 5.5 found no
correctness regression. Its coverage/robustness findings are closed: old-source
Return/pointer failures are proven in a scratch copy, mixed terminators use the
actual newline, and quoted/parenthesis tasks plus source-only code admission
have expanded owner cases. The final full suite passes 317 tests, zero failures
(`list83-reviewed-full-tests.log`). Fingerprints and exact evidence are in
`list83-verification.json`.

Raw numeric marker spelling is retained; logical displayed ordinal reconciliation
remains pending. Head removal, empty-tail commands and partial paste/selection
ownership still block normal rich admission of interleaved notes. No new DMG or
installed/IME acceptance is claimed. Preview 68 remains delivered.


### List 84: structural Backspace at the list body boundary

Backspace at the start of an item's body, or deletion of the complete selected
visible marker, now lifts the list wrapper. Nested Backspace lifts in place and
adopts following peers; Tab keeps its whole-item move policy. Root items retain
their head text, promote direct child lists, preserve deeper
ownership and make former trailing paragraphs independent. Quotes, inline
formatting and local endings survive; explicit boundaries protect empty heads
and numbered children. Empty quoted checklist syntax is also rendered without
leaving a literal marker as body text.

The primary owner has 42 scenarios. All 84 document/clipboard tests and all 318
Mac tests pass (`list84-final-owner-tests.log`, `list84-full-tests.log`). GFM
checks confirm the intended resulting tree (`list84-web-parser.log`). Opus 5.5
review findings are repaired: empty nested recovery, indented top-level bases,
Lexical/MDX nested ordering, and empty-middle paragraph boundaries. The expanded
90-scenario owner and all 84 document/clipboard tests pass. The final full suite
passes 318 tests, zero failures (`list84-reviewed-full-tests.log`); source
fingerprints and exact evidence are in
`list84-verification.json`.

This is marker/wrapper removal with head text retained. Whole-head paragraph
deletion, arbitrary selection replacement, non-list formatting and empty-tail
commands are still pending, as is normal rich admission for interleaved notes.
No new DMG or installed/IME acceptance is included; Preview 68 remains delivered.


### List 85: empty continuation Return and list exit (development)

Return on an empty continuation creates a sibling without leaving stale gaps or
whitespace. A second Return exits an empty item through structural lifting.
Items that still own children or paragraph text split instead. Newline metadata
comes from the actual terminator, preserving LF and CRLF across repeated Return.
An empty marker that CommonMark does not yet count gains a validated paragraph
boundary before ownership is resolved.

Opus 5.5 found inconsistent splitting for the first empty child with its own
children, and a possible extra paragraph gap when splitting an orphan halfway
through its text. Both were reproduced at the native editor boundary
(`list85-review-baseline.log`) and repaired. Return and lifting now share the
parser-boundary preparation. An orphan keeps its leading gap on the left while
the right half becomes an ordinary paragraph. A continuation-only owner splits
the same way after deleting its last child as it does after reopening.

The existing Return owner now covers 78 scenarios, including standalone
continuation ownership, orphan start/middle/end splits, Undo/Redo, and empty
items between following paragraphs inside and outside quotes. All 84 document
and clipboard tests pass (`list85-reviewed-owner-tests.log`). Independent
CommonMark parsing checks the repaired parent graph and paragraph boundaries
(`list85-reviewed-web-parser.log`). The pre-review full suite passed 318 tests;
the final suite also passes 318 tests, zero failures
(`list85-reviewed-full-tests.log`). Exact status and source fingerprints are recorded in
`list85-verification.json`.

Whole-head deletion, arbitrary selection replacement, non-list formatting and
partial clipboard ownership remain pending. Normal interleaved admission stays
guarded. No new DMG or installed/IME acceptance is claimed; Preview 68 remains
the delivered build.


### List 86: complete native head paragraph deletion (development)

Deleting exactly one complete native list-head paragraph is now a structural
command. Its children move into its old parent, with deeper relationships
unchanged. Remaining item-owned paragraphs transfer to that parent in place;
at the root they become standalone paragraphs, retaining quotes. The editor
validates the remaining parent graph before committing, and one Undo restores
the original selection and contents. The next caret skips a surviving visible
marker, while an unselected blank separator remains a plain insertion point.

The native owner fails on the old deletion path
(`list86-head-deletion-baseline.log`). Its 21 scenarios cover root/nested items,
LF/CRLF, quotes, checklist and ordered markers, earlier siblings, retained gaps,
EOF, deleting the final item, Undo/Redo and typing. All 85 document/clipboard
tests pass (`list86-document-clipboard-tests.log`). Independent CommonMark
parsing checks the resulting child and paragraph owners (`list86-web-parser.log`).
The full suite passes 319 tests, zero failures (`list86-full-tests.log`).
The subsequent review repairs are described below; exact source fingerprints
and status are in `list86-verification.json`.

This is an explicit native promotion policy. Standalone Lexical and MDX
probes do not establish identical desktop selection behavior: the MDX
range probe retains an empty list container. Installed selection parity is
still unverified. Partial/multiple-paragraph replacement, non-list conversion
and clipboard ownership remain unfinished. A complete native paragraph can
contain several leading logical paragraphs, all of which the selected range
includes. Normal interleaved admission stays guarded. No new DMG or installed
acceptance is claimed; Preview 68 remains delivered.


#### List 86 review repairs

Opus found that typing on a retained blank line could turn a surviving `2.`
child into prose. The former source round-trip assertion did not prove list
structure. The native regression now checks parsed item count before/after
typing and the paragraph ownership tree. An explicit separator protects the
editable row. Deleting the first ordered sibling now preserves that list's
original start and renumbers its remaining siblings, propagating marker-width
changes to their descendants and tails. A root list newly split by promoted
children and standalone paragraphs keeps its own remaining start instead.

Temporary empty markers are normalized into validated boundaries before an
unrelated head deletion. Selecting a final marker with no newline still lifts
it through the existing empty-item recovery. Deleting the final whole paragraph
reserves an explicit plain or quoted boundary, preventing typing from joining
the preceding item. Added cases cover child-owned tails, nested quotes, 10→9
width changes, custom ordered starts and LF/CRLF.

The 43-scenario owner reproduces the review defects in
`list86-review-baseline.log`; all 85 document/clipboard tests pass in
`list86-reviewed-eof-owner-tests.log`. Independent CommonMark checks confirm the
repaired typing and ownership cases (`list86-reviewed-web-parser.log`). The final
full suite passes 319 tests, zero failures (`list86-reviewed-full-tests.log`),
and the command has exited successfully. No extra reviewer was delegated for these
bounded repairs. Cut uses a separate custom clipboard path and is still part of
the pending clipboard work; drag-move and installed selection behavior remain
unverified. The admission and packaging limitations above remain unchanged.


### List 87: Cut and standalone clipboard hierarchy (development)

Cutting exactly one complete native head paragraph now preflights the same
ownership command as Delete, before publishing to the clipboard. It retains
Cut as one Undo action. A structurally refused cut changes neither the note,
selection nor clipboard. Source mode and ordinary inline/table cuts retain their
existing paths; broader partial/multiple-paragraph removal is still unfinished.

Copied fragments are standalone documents: retained nested heads whose
ancestors were not selected move to the root, and their descendants and owned
paragraphs follow their new marker widths. A partial first paragraph remains
plain text under the existing copy contract. A partially selected visible
marker remains the literal selected glyph. Former parent tails become separate
prose, with physical boundaries that keep them out of the selected child list.
Partial-table attributes are cleared before offsets can grow. Ordinary inline
copy avoids the full-note ownership parse.

An unrelated temporary empty nested marker can prevent the normal source tree
from mapping to native rows. Copy alone can establish those boundaries in a
private snapshot, then map the resulting ownership back to original positions.
The note and its selection remain unchanged; normal command mapping and rich
admission retain their existing guards.

The original Cut and copy defects fail at the real clipboard owner in
`list87-clipboard-baseline.log`. Partial-marker and temporary-empty-map defects
have separate failing logs. The two primary owners cover 9 Cut and 13 copy
scenarios, including LF/CRLF, quotes, non-1 ordered children, direct parsed
paragraph ownership, unchanged source, Undo/Redo and clipboard refusal. All 87
document/clipboard tests pass (`list87-final-verified-owner-tests.log`). An
independent CommonMark parser confirms that the copied children remain lists
and that the tails retain their intended owners (`list87-web-parser.log`).

The full suite passes 321 tests, zero failures (`list87-full-tests.log`), and
the command has exited successfully. Subsequent review repairs are described
below. Exact source fingerprints and status are in `list87-verification.json`. Arbitrary replacement, broader paste
ownership and non-list conversion remain pending, as do normal interleaved
admission and installed/IME acceptance. No new DMG is claimed; Preview 68 is
still delivered.


#### List 87 review repairs

The review exposed an empty EOF Cut that lifted the selected item instead of
removing it, and quote boundaries that could split one quote into two. Native
regressions reproduce both (`list87-review-baseline.log`). Cut now removes an
empty final row, reserving the same explicit plain/quoted typing boundary used
by whole-head deletion. Delete on a selected EOF marker still lifts it, retains
its previous Undo label and continues typing in the lifted item. Bullet,
numbered and checklist cases run with LF/CRLF.

The partial-numbered-marker probe refined the reported mechanism: the existing
inline serializer already escapes `10.`, but it became lazy continuation text
of the preceding item. A detached marker now receives its own paragraph
boundary. No redundant escaping change was needed. Complete prose/list and
quote/list selections keep original source when their boundary already works.
Inserted gaps retain shared quote depth; orphan tails in multi-paragraph
fragments stay in that quote. The established isolated-continuation plain-text
copy contract remains unchanged.

Tests now compare the original attributed view's Markdown, not only the last
published model value. The two owners cover 19 Cut and 20 copy scenarios; all
87 document/clipboard tests pass (`list87-reviewed-owner-tests.log`). The shared
empty-marker normalization is now one production helper, covering both private
copy mapping and committed head-removal recovery. Independent CommonMark checks
confirm the repaired quote counts, literal marker paragraph and empty-row Cut
(`list87-reviewed-web-parser.log`). The final full suite passes 321 tests, zero failures
(`list87-reviewed-full-tests.log`), with command exit status 0.
No extra delegate was used for bounded repairs. Unrecoverable mapping fallback,
arbitrary replacement, broader paste and non-list formatting remain pending;
normal rich admission and installed acceptance are not claimed.


### List 88: non-list block conversion (development)

Heading, quote and plain-paragraph commands now close enclosing list containers
at the selected paragraph. Following heads skip those closed ancestors; former
tails become independent paragraphs at their existing positions. Earlier items
retain their relationships. Original marker kinds, inline content and outer
quotes survive. Code and table units in a mixed selection are left unchanged.
A parser check validates the remaining head-parent graph before one Undoable
commit. No normal rich admission is widened.

The shipped MDX importer/exporters plus Lexical `$setBlocksType` were exercised
headlessly (`list88-mdx-block-conversion.log`). In those probes the web path
merged Parent and Tail ahead of Child, and changed child marker kinds. The
native policy retains text order and marker kinds instead of reproducing that
destructive result. These are dependency probes, not installed UI acceptance.

The new real-editor owner fails on the old implementation
(`list88-formatting-baseline.log`). Its 36 scenarios cover LF/CRLF, root/nested
and quoted containers, a selected continuation, Unicode before collapsed logical
gaps, multi-paragraph selection, empty/EOF typing, temporary empty-item mapping,
and mixed code/table selections. UTF-16 anchors handle both removed markers and
heading gap collapse. Explicit typing metadata preserves the requested style
when an emptied item has no characters left. An EOF Paragraph command after a
list or quote reserves a separator, preventing later text from joining that item.

Existing formatting goldens now show explicit paragraph boundaries, including
three distinct paragraphs after two headings are cleared. A parsed assertion
protects that structure. The Return-after-format fixture now contains ordinary
prose; its host explicitly separates the simulated toolbar and native Return
input events. The diagnostic log confirmed that AppKit registered Typing inside
the same synchronous XCTest event as formatting. Undo/Redo checks remain, and
no production Undo hook was added for that fixture.

All 88 document/clipboard tests pass (`list88-final-owner-tests.log`). Independent
CommonMark checks confirm parent identities, content order and quote continuity
(`list88-web-parser.log`). The full suite passes 322 tests, zero failures (`list88-full-tests.log`), with
command exit status 0. Opus 5.5 review is running; exact fingerprints and status
are in `list88-verification.json`.

Arbitrary replacement, broader paste ownership and raw-number/displayed-ordinal
reconciliation remain unfinished. A zero-length style is carried as typing
state until text is entered; persisted empty-style fidelity still needs audit.
Normal interleaved admission, unsupported containers and installed/IME acceptance
remain pending. No new DMG is claimed; Preview 68 remains delivered.


### List editing follow-through: lists 89–93 (development)

Selective empty-item recovery, body-edit parent ownership and former-tail
promotion now pass 323 Mac tests with zero failures, command exit 0. The final
list93 Opus findings are repaired: promoted task-looking text remains literal,
imported empty parents keep their owned bodies after child deletion, and native
blank rows do not orphan the promoted body. The exact final source hashes and
full-test log are in artifacts/native-macos/list93-verification.json. See
[the current list continuation record](native-macos-list-continuations.md).

Selection replacement and broader paste are next. A headless probe of the
pinned web editor establishes its surviving-parent rules; the native owner
reproduces stale descendant indentation in those replacements. This discovery
is not implementation or acceptance. Normal interleaved rich admission, installed
input/IME checks and full parity remain pending. The sidebar remains fully
hideable, and Preview 68 remains the latest delivered DMG.


## Cross-item replacement review repair (list94, 2026-11-18)

The completed independent review found that the first implementation assigned
children of every removed item to the paragraph where typing began. This failed
when that paragraph was deeper than the removed item or in a different quote.
The repaired transaction chooses the removed item's previous surviving sibling
in its own list, otherwise its retained parent, and preserves the old quote
scope for children, tails and spacing tags. Six new fixture shapes extend the
editor table to 96 cases. The original code fails 88 assertions; all 91 updated
editor/clipboard owner tests pass. Body-range Cut refusal now proves that the
live text, selection and clipboard remain unchanged.

Direct native marked-text accent updates and commit pass with Undo/Redo, even
on the original planner. The suspected raw-accent failure is not reproduced;
no composition code was changed. Installed keyboard/IME acceptance remains
pending. Adjacent lists with different marker spellings or different list kinds
still need a separate normalization decision; the actual Lexical comparison is
retained in list94-discovery/. Full-suite re-verification passes 325 tests with
zero failures and command exit 0 (list94-reviewed-full-tests.log); repaired
source hashes are frozen in list94-review/FINAL-*. Preview 68 remains
the delivered DMG. The fully hideable folders sidebar is preserved.


## List-separator and clipboard follow-through (list95, Preview 69)

Clearing independent prose between lists now preserves the later items' root
parents, including quoted/numbered forms, Backspace and Cut. The same prepared
transaction handles a local region when another list is unmappable and refuses
only an affected adoption hazard. One-sided, different-quote, insufficient-indent
and empty-heading neighbours stay on their ordinary editing routes. CRLF body-only
copy no longer leaks an unselected carriage return; image/link spelling, resource
bytes and RTFD remain covered by the external-file-to-vault clipboard owner.

The first implementation and its review repairs have separate failing baselines
(40 and 14 assertions). Final frozen sources and verification are recorded in
list95-review/FINAL-* and list95-verification.json. Same-kind lists can reparse as
one loose list while keeping root item parents; separate list-object preservation
is not claimed. Clearing before imported indented ordinary prose remains a known
paragraph-ownership gap. Native top-level indented code already fences itself
when needed; an explicit editor control verifies that path. The wider paste,
container-kind normalization, rich admission and installed/IME work remain pending.


Preview 69 final-source verification: the post-review suite passes 325 tests,
zero failures and command exit 0 (list95-reviewed-full-tests.log). The final
sources include the one-sided/margin/quote refusal correction, keyboard Undo
naming, and exact inline-image/link CRLF clipboard coverage. Packaging uses the
matching list95-review/final-source-hashes.json; signature and mounted-DMG checks
are recorded separately in artifact-preview-69-local.json. Installed UI and
physical keyboard/IME acceptance are still pending.


### Preview 69 artifact handoff (2026-11-18)

`Zerus-Native-0.3.34-preview-69-arm64-local.dmg` contains build 69 for Apple Silicon
and macOS 26+. The Release build and packaging command exit 0. The app and nested
CLI signatures, actual plist, architecture and minimum OS pass the mounted-DMG
verifier. This is ad-hoc signing; notarization was not submitted. The private
HTTPS download responds 200 and matches the local DMG byte-for-byte.

SHA-256: `44a44c4e6b9886ca46ce2f2d73fe901b899cacddf62cb44ea8a90f6f8d3a4ead`.
The receipt is `artifacts/native-macos/artifact-preview-69-local.json`, and the
source/test/download handoff record is `artifacts/native-macos/preview69-handoff.json`.
The web companion's frontend and private /app proxy both respond 200; this is not
a substitute for native UI acceptance. No installed UI or physical keyboard/IME
check, full-parity acceptance, production release, commit or tag is claimed.


## Development after Preview 69: independent paragraph ownership (list96)

Clearing the text of a separator before imported indented prose can pull the
following paragraph into a list. The quoted forms are rich-admitted today;
unquoted indented prose remains Source-only. The current source repairs the
quoted path and exercises the other shapes in the rich core without widening
admission. It checks whether the tentative Markdown would adopt the following
paragraph, then re-spells only its syntax prefix using a new source token. It
keeps native text, inline data, quote depth, heading kind, line endings and Undo.

All 92 document/clipboard owner tests pass. The original code fails 166 assertions
on the expanded owner baseline. Exact inputs, parser-owned paragraph-role
oracles and the pinned web comparison are recorded in list96-review/. The full
suite passes 326 tests, zero failures and command exit 0 (list96-full-tests.log).
Independent review found no regressions in list96; its broader gesture and token
follow-ups are addressed in list97 below. Broader range/paste/container parity
remains pending.
This source work first ships in Preview 70 below. Preview 69 retains its
original verified checksum; no installed acceptance is claimed.


## Development after Preview 69: root block ownership on export (list97)

Imported independent paragraphs, headings and supported HTML image blocks now
carry their root ownership into native editing. Export checks the source after
boundary edits and removes syntax indentation or restores a quote-aware separator
when that source would place an independent block inside a list item. The check
includes the empty-head recovery that runs at the end of export. Its parser
context starts at the previous independent block rather than the whole note.

This covers clearing a separator body, deleting its whole row, selecting across
blank rows, repeated Backspace, and whole-row Cut. Body-only clipboard export also
keeps normalized root indentation while preserving inline image and link source.
Setext headings retain their heading representation during edits and keep their
original source while untouched. No rich-mode admission rules were widened;
unquoted indented-prose fixtures still exercise the guarded core only.

The expanded owner uses 21 handwritten source shapes, LF and CRLF, four editing
gestures, independent swift-markdown block ownership/kind checks, visible text,
selection, Undo/Redo, reopen and subsequent typing. Separate controls cover an
intentional paragraph join, empty-list recovery and refused affected-list edits.
All 93 document/clipboard owner tests pass. The exact final regression tests on
list96 production fail 648 assertions across two tests (exit 65); final production
was restored before the full-suite run. Frozen sources and hashes are in
artifacts/native-macos/list97-review/. The full Mac suite passes 327 tests, zero
failures and command exit 0 (list97-full-tests.log); all five frozen source/test
hashes still match. Independent review is completed; its heading findings and repair evidence are
recorded below and in list97-verification.json.

The web companion remains available, but it does not preview this native-only
interaction. Installed keyboard/IME and full parity acceptance remain pending.
Preview 70 below packages the repaired list96/list97 work. Preview 69 does not
contain those changes.


### list97 review repair and Preview 70 preparation

The independent review found that swift-markdown's setext heading range can
include the first source line after its underline. Native heading grouping now
ends at the inline title's final line plus the underline, with explicit bounds
checks. Multiline heading soft breaks display as spaces and remain one heading
when edited. A note with lone CR separators bypasses the new LF-indexed heading
grouping; its existing raw source is retained across native rows by a paragraph
source token. Complete bare-CR editing is still outside the verified scope.

The expanded heading owner reproduces 60 failures on the reviewed source. Its
lone-CR control separately reproduces a fatal array-index trap (exit 65).
After repair, all 93 editor/clipboard tests pass. Final repaired source hashes
are in list97-review/final-source-hashes.json; the reviewed full run passes 327 tests, zero failures and exit 0
(list97-reviewed-full-tests.log). The native preview build record is now 70; packaging
and private download verification pass as recorded below. The list98 container-normalization
prototype is saved separately under list98-review/WIP-* and is excluded from
this preview candidate. There is no new installed UI/IME acceptance claim.


### Preview 70 artifact handoff (2026-11-18)

The local Apple Silicon DMG is built from the repaired source, version 0.3.34,
build 70, minimum macOS 26. The Release build and packaging command exit 0.
App and nested CLI signatures pass; the mounted DMG payload matches the build
record. This is an ad-hoc preview, not a notarized production release.

Private download:
https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.34-preview-70-arm64-local.dmg

SHA-256: `f4e454aa3b59f38ec93ac65d74e26160b50596d021e8a883f6833aefbbb07667`.
Size: 13,344,586 bytes. A full download through the private HTTPS endpoint returns
200 and matches those bytes. Artifact and handoff receipts are
`artifacts/native-macos/artifact-preview-70-local.json` and
`artifacts/native-macos/preview70-handoff.json`. The final 327-test pass and five
reviewed source/test hashes remain unchanged through packaging. The workspace is
dirty; the package receipt does not claim a complete clean source snapshot.

The fully hideable folder sidebar is preserved. This preview includes the root
paragraph/export and heading repairs, not the saved list98 prototype. Broader
container/paste/marker work, native interleaved admission and installed keyboard,
IME and complete desktop parity acceptance remain in progress. No iOS version,
Windows release, production release, commit or tag is claimed.


## Development after Preview 70: cross-item list container kinds (list98)

Cross-item replacement now normalizes affected list containers as well as their
surviving-parent graph. Adjacent same-kind document and blockquote sibling lists
share a destination even when their bullet or ordered delimiters differ. Nested
list containers remain separate and keep source order. Native numbered tasks
remain a distinct source kind from bullet tasks.

Moved children join an existing child list only when no retained parent paragraph
separates them. Across a surviving tail they keep their own kind and checkbox
state. Wrapper promotion follows the web's saved-Markdown export, not its live
empty-wrapper display structure. Root ordered lists preserve explicit starts
consistently, including when another source list joins them. Newly promoted
nested lists start at one to remain valid after a parent paragraph.

Untouched groups retain source spelling. Marker widths before and at the selection
update the caret and descendants, including 100→2 and 1→10 widening. Typing uses
the refreshed paragraph's context and layout. Undo restores source and selection;
Cut exports the original selected fragment before normalizing retained content.

The owner now has 54 source shapes and 216 LF/CRLF deletion/typing transitions,
including widening with a nested child and a tail, typing-layout consistency,
numbered tasks, root/quote/nested grouping and untouched-list controls. All 93
editor/clipboard tests pass (list98-final-reviewed-owner-tests.log). The initial
implementation's regressions failed 182 assertions on Preview 70. The exact final
review-repair tests fail 68 assertions on the reviewed list98 source, exit 65
(list98-final-review-baseline.log). The final full rerun passes 327 tests, zero failures and command exit 0
(list98-reviewed-full-tests.log), with all five FINAL source/test hashes unchanged.

Independent review is completed, and its bounded findings are repaired. The
pinned web probes, original and FINAL snapshots, hashes and evidence labels are
in artifacts/native-macos/list98-review/. parity-evidence.md distinguishes saved
Markdown from live web display, preserves native numbered tasks and records the
web's mixed-task reload discrepancy. The Cut fragment check is a transport guard;
it already passed on the previous implementation. No claim of identical live web
list representation follows from the export probes.

No new rich admission, iOS changes, installed input/IME acceptance or new DMG is
claimed at that stage. Preview 71 below includes the final list98/list99 work. Broader paste,
marker/multiline endpoints, raw ordinal/display reconciliation, container
admission and complete desktop parity remain in progress. Final verification is
tracked in list98-verification.json.


## Development after Preview 70: checked inline paste (list99)

Single-line inline paste across supported list body selections now uses the same
checked item transaction as typing and Cut. This preserves descendants, destination
list kinds, quote boundaries and the mapped caret. Plain text, native inline
fragments, inline HTML and a single HTML paragraph retain their inline formatting;
subsequent typing and Undo/Redo stay in the edited paragraph. A refused structural
edit leaves model, visible text and selection intact and restores editor input.

HTML conversion adds a synthetic final newline even for a copied word. In rich
editing, a single-line Paragraph is recognized before code-preference conversion
and that synthetic ending is removed. Native fragment-selected breaks and source
editing retain their existing endings; structured/multiline content continues
through the existing paste path. Resource/stale-state/editability checks precede
the checked edit, and the existing Source-mode fallback still runs afterward.

The clipboard owner covers 18 combinations of three source shapes, LF/CRLF and
three payload formats, plus ordinary HTML replacement and same-item controls.
Exact structured HTML controls retain two paragraphs, explicit `<br>` hard breaks
and heading endings; Source-mode HTML retains its final terminator. Same-item
HTML paste keeps the paragraph's typing layout. The image owner covers a data-URI
PNG across the list boundary, actual imported bytes, reference position and one
Undo/Redo. Both valid angle and plain destination spelling are accepted.

Independent review completed. Its deterministic image-refusal issue is repaired
by checking a resource-bearing inline edit before importing its files, followed
by the existing post-import check. Repeated refused HTML-image attempts leave
assets, model, visible text, selection and Undo history unchanged. The duplicate
HTML matrix case was removed. Explicit HTML line breaks now save as Markdown hard
breaks; the shared iOS converter is unchanged. These are editor/paste-owner tests,
not installed clipboard/IME acceptance. The pinned web probe compares headless
insertRawText and single bold Paragraph insertNodes exports; it does not exercise
an actual browser clipboard event or establish identical live display.

The initial two regressions fail 170 assertions on pre-list99 source, exit 65
(list99-final-baseline.log). The exact final review-repair owner fails 16 assertions
on the reviewed source, exit 65 (list99-final-review-baseline.log). All 93 final
editor/clipboard tests pass (list99-review-final-owner-tests.log). The final full
rerun for Preview 71 passes 327 tests with zero failures and command exit 0
(list99-reviewed-full-tests.log). All five FINAL source/test hashes still match. Original and FINAL snapshots and hashes are in
artifacts/native-macos/list99-review/; list99-verification.json tracks evidence.
Broader multiline, marker/whole-paragraph and structured paste, rich container
admission, ordinal/display reconciliation and installed/IME/full parity remain
in progress. No new admission, iOS source, production release, commit or tag is
claimed.


### Preview 71 artifact handoff (2026-11-18)

Preview 71 packages the reviewed list98/list99 changes and their bounded repairs.
The folders sidebar remains fully hideable, with its toolbar restore control.
Version 0.3.34, native build 71, Apple Silicon, macOS 26+. This is an intermediate
ad-hoc test DMG without notarization; it retains the separate Zerus Native identity.

https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.34-preview-71-arm64-local.dmg

SHA-256: `b7e9264bcad74ac897a451687bf48b1812efc92040021f61cc97fbdd9f347c81`.
Size: 13,369,001 bytes. Packaging exited 0, verified the app and bundled CLI
signatures, and mounted the DMG read-only to recheck its identity, version,
architecture and contents. A full private HTTPS download returned 200 and
matched the local DMG checksum and byte count. Receipts are
`artifacts/native-macos/artifact-preview-71-local.json` and
`artifacts/native-macos/preview71-handoff.json`. The five final feature source/test
hashes still match the 327-test pass. The workspace is dirty; these feature hashes
do not claim a complete clean source snapshot.

The web companion also responds successfully through the frontend and private
proxy at https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/app. It does not preview
the native NSTextView interaction. Installed UI/keyboard/IME, broader paste and
marker endpoints, interleaved admission, ordinal/display reconciliation and full
feature parity remain pending. No iOS build, Windows release, production release,
commit or tag is claimed.


## Development after Preview 71: multiline inline paste (list100)

Plain multiline text and explicit hard breaks from native fragments or a single
HTML paragraph now use the checked selection transaction across supported list
bodies. They remain inside the receiving paragraph, retain surviving children,
quote boundaries and destination list kinds, and map the caret over the native
logical breaks. Caret and same-item list paste use the same transaction. Inline
breaks adopt the receiving paragraph's line ending; retained neighboring source
keeps its spelling. Plain pasted list markers remain literal text.

A single HTML Paragraph stays inline even when it contains `<br>`; separate HTML
paragraphs retain the existing structured path. Generic prose receives the same
logical-break insertion and avoids reusing source for duplicated lines. Headings,
Source editing, table cells and code keep their separate paths. Deterministic
multiline inline image refusals are preflighted before asset writes, and refusal
keeps the view, selection, clipboard assets and Undo state unchanged.

The existing paste owner now covers 48 source/format/LF/CRLF combinations and 20
same-item/caret combinations, plus structured HTML, heading and Source controls,
resource refusals and literal-marker input. Independent swift-markdown parsing
checks item parents, inline formatting and hard breaks; visible line text survives
reopening, and Undo/Redo restores the source and selection. The exact final owner
fails 348 assertions on Preview71 sources (list100-final-baseline.log, exit65).
It passes on the repair (list100-heading-control-tests.log). The final full native
suite passes 327 tests, zero failures and command exit 0 (list100-full-tests.log),
including all 93 editor/clipboard owners and the final heading controls. The five
frozen source/test hashes still match. Independent review completed; the bounded repair and its final verification are
recorded below and in list100-verification.json.

The pinned headless Lexical probe distinguishes raw text with line breaks from
multiple Paragraph nodes. Native deliberately emits Markdown hard breaks so
visible lines survive reload; the web exporter emits soft newlines and can drop
the visible break on reimport. The item graph matches the supported raw-text
cases; identical web byte spelling or browser clipboard delivery is not claimed.
Evidence is in artifacts/native-macos/list100-review/parity-evidence.md and
web-multiline-probe.log. This work is not in Preview71. Broader structured paste,
marker endpoints, general interleaved admission, ordinal/display reconciliation,
incremental serialization and installed keyboard/IME/full parity acceptance
remain pending. No iOS changes, new DMG, release, commit or tag are claimed.


### list100 review repairs and Preview 72 preparation

Independent review identified saved boundary-break loss, caret resource preflight
and single-line heading typing regressions. These are repaired in the FINAL
snapshots. Plain leading/trailing/consecutive logical breaks serialize as inline
`<br>` so one item paragraph retains every visible line. Native import now admits
inline HTML breaks in otherwise supported paragraphs. Standalone/block HTML and
unsupported embedded containers retain their existing Source admission rules.
Ordinary internal breaks still serialize as Markdown hard breaks.

Resource preflight now runs for caret as well as selected ranges. A canonical,
nonempty same-paragraph body edit uses the existing local padding/empty-head check
instead of requiring unrelated temporary list rows to map; edits needing the
structural mapper can still refuse an unmappable affected region. Those refusals
leave assets and Undo state untouched. Heading follow-up typing keeps its block,
paragraph style and font. An unterminated final paragraph inherits the preceding
line ending for newly pasted breaks.

The existing owner now includes leading/trailing/consecutive/standalone newline
payloads, tight item-paragraph structure and reopen checks, heading typing font,
CRLF without a final terminator, paragraph continuation text, local caret/body
edits with a temporary unmapped row, and repeated caret image refusals. The exact
final review-repair owner fails 51 assertions on the reviewed source, exit65
(list100-final-review-baseline.log). The final full rerun passes 327 tests, zero failures and command exit0 in
list100-reviewed-full-tests.log. All five FINAL source/test hashes still match. Review findings were repaired by the parent;
this is not a second independent sign-off on the final snapshot.

The web boundary probe compares raw leading/trailing/consecutive newlines with
the pinned Lexical exporter. Native retains visible break structure rather than
copying lossy web soft-newline spelling. Full web/iOS round-trip acceptance of
inline HTML break spelling, HTML-converter edge-break trimming, orphaned
continuations and installed IME/clipboard acceptance remain pending. Preview71
predates these repairs. Preview72 is being prepared as the next intermediate
local DMG; full parity and production release are not claimed.


### Preview 72 artifact handoff (2026-11-18)

Preview72 packages the multiline inline-paste work and parent repairs of the
independent review findings. The folders sidebar remains fully hideable with
its toolbar restore control. Version0.3.34, native build72, Apple Silicon,
macOS26+. This is an ad-hoc intermediate test DMG without notarization, retaining
the separate Zerus Native identity.

https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.34-preview-72-arm64-local.dmg

SHA-256: `b196e980ce29d9893c2d19851c81f2776e5b119c47e200437ea9f1fdc5c8f023`.
Size: 13,373,268 bytes. Packaging exited0, verified the app and bundled CLI
signatures, and mounted the DMG read-only to verify its identity, version,
architecture and contents. A full private HTTPS download returned200 and matched
the local DMG checksum and byte count. Receipts are
`artifacts/native-macos/artifact-preview-72-local.json` and
`artifacts/native-macos/preview72-handoff.json`. The final327-test pass and all five
FINAL feature hashes remain unchanged through packaging. The workspace is dirty;
these feature hashes are not a complete clean source snapshot.

Installed UI/keyboard/IME, full cross-client inline-break acceptance, broader
structured paste and marker endpoints, interleaved admission, ordinal/display
reconciliation, incremental serialization and full feature parity remain pending.
The web companion responds through the frontend and private proxy at
https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/app; it does not preview native
NSTextView interactions. No iOS build, Windows release, production release,
commit or tag is claimed.


## Development after Preview 72: web inline-break interoperability (list101)

The web editor's existing empty-paragraph plugin now imports attribute-free inline
HTML `<br>` as a LineBreakNode subclass. The default generic HTML node preserved
the markup but exposed no newline to text extraction or editor selection APIs.
The new node keeps standard line-break editing behavior and its explicit HTML
spelling through Markdown export. Legacy standalone HTML empty-line markers and
ordinary keyboard-break export keep their existing policies. No component or
vault-format change is needed; the existing plugin is already installed.

Five headless integration cases use the real MDXEditor core/plugin registry and
live Lexical editor state: native trailing, leading and consecutive breaks,
blockquote breaks and ordinary prose. They check text and break nodes, typing at
a position immediately after a break, editor-state JSON persistence and Markdown
save/reopen. All five fail before the fix for the missing newline (baseline exit1);
all nine tests in the owner pass afterward. The neighboring editor gate passes
82 tests in five files. TypeScript, focused ESLint and the production frontend
build/chunk verifier all pass. The final native paste owner also passes, including
ten LF/CRLF checks for the web exporter's self-closing `<br />` spelling, native
rich admission, visible lines and unedited source preservation.

This is headless importer/editor/exporter and native-transport proof, not a DOM
clipboard or installed IME claim. The native implementation files are unchanged
from Preview72; the native edit here adds transport coverage only. No new DMG or
iOS source change is needed for this web compatibility repair. The updated module
is served by the private web companion at
https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/app. Frontend and proxy return200.
The public production site/release was not deployed. Evidence and frozen files
are in artifacts/native-macos/list101-review/ and list101-verification.json.
Broader HTML edge conversion, structured paste, marker endpoints, interleaved
admission and full desktop/installed acceptance remain in progress.

## HTML paste and blank-paragraph interoperability (list102)

The macOS converter preserves explicit HTML breaks while keeping bold, italic,
strikethrough and links valid at break boundaries. Whitespace next to a break is
normalized, and a block's final browser layout break is removed once. Intentional
blank blocks use Zerus's existing invisible paragraph marker; repeated breaks
within one blank block stay in that paragraph. The native and web editors hide
that marker, preserve it through save/reopen, and keep literal marker characters
inside ordinary text. Native footer counts exclude blank markers and count
inline HTML breaks as word boundaries. Fragment-only breaks pasted into code
become ordinary code newlines.

This is an owning-editor and serialized Markdown repair. The web checks use the
actual MDXEditor/Lexical visitor registry, including editing blank paragraphs and
adding a Shift-Return break. They do not establish installed clipboard, physical
keyboard or IME acceptance. Shared converter differences are macOS-only; iOS
keeps its existing conversion policy and receives compile verification only.

The independent list102 review found emphasis-edge corruption, blank HTML blocks
falling back to Source, whitespace/layout-break differences, fragment/code line
separators and break-only link labels. Parent repairs cover those findings.
The final review baseline fails on the reviewed implementation: 83 assertions
across three owning tests. Web blank-marker regressions also fail before their
repair. Broader structured paste, arbitrary marker endpoints, interleaved-list
admission, ordinal/display reconciliation and full installed parity remain open.
Final source hashes and verification logs are recorded under
`artifacts/native-macos/list102-review/`; packaging evidence will be linked below.

Final checks for list102: 327 Mac tests and 88 web editor tests pass; TypeScript,
changed-file ESLint and the frontend production build pass. The generic iOS
simulator build-for-testing succeeds (compile-only; no iOS version increment or
runtime claim). The nested-wrapper cases fail six assertions before their repair
and pass in the final full suite. The regression snapshots, final hashes and
logs are linked from `artifacts/native-macos/list102-verification.json`.

## Preview 73 preparation (2026-11-18)

Version 0.3.34 build 73 packages the reviewed HTML break/blank-paragraph repairs
and all earlier native migration work. The fully hideable folder sidebar and
toolbar restore remain included. This is an ad-hoc, non-notarized local test DMG,
not production migration acceptance. Installed UI, real clipboard and keyboard/IME
acceptance remain pending; the packager's mounted-content and signature checks
are recorded separately from those interactions.

### Preview 73 artifact handoff

The packager completed successfully. The DMG was verified and mounted read-only;
the bundled app and CLI identities, versions, architecture and signatures match
the native build configuration. The complete private HTTPS download returned 200
and matches the local DMG checksum and size.

Download: https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.34-preview-73-arm64-local.dmg

SHA-256: `bd5bbc1c6d2c0c67ca888564987d9a69263e5c4c2d668dad3c0a4b7089ab923a`  
Size: 13,382,401 bytes.  
Receipts: `artifacts/native-macos/artifact-preview-73-local.json` and
`artifacts/native-macos/preview73-handoff.json`.  
Build log: `artifacts/native-macos/preview73-release.log`.

Signing is ad-hoc; notarization was not submitted. This working tree is dirty,
and the artifact receipt does not claim a complete source snapshot. The final
feature hashes are recorded separately. Installed app/clipboard and keyboard/IME
acceptance remain pending. No production release, iOS version bump, commit, tag
or push was made.


## Paragraph-block paste development after Preview 73 (list103)

Paragraph-only native fragments and HTML now have a checked block-paste path.
The first pasted paragraph merges with the receiving prefix, and the last merges
with the selection suffix. New paragraph boundaries close the receiving list;
following surviving children are promoted in place through the existing validated
block-formatting planner. Root bullet lists, quoted lists, ordinary prose and
headings have owning editor coverage. The plain blockquote case follows the
pinned web editor's inline joining rule. Native soft wrapping and cross-line
styles are parsed together; intentional blank paragraph markers are preserved.
Generated paragraph boundaries use the receiving note's line endings. The entire
paste, caret, typing state and reshaped list belong to one Undo operation.

Resource-bearing paragraph paste runs the same plan before importing files.
Repeated refusals preserve note text, selection, Undo history and existing assets.
The owning tests exercise both HTML and native fragments with LF/CRLF, body
selection and caret insertion, multiple blocks, a blank middle paragraph, loose
item paragraphs, cross-item replacement, heading and quote boundaries, reopening
and typing afterward. A pre-repair owning baseline fails; the first heading
integration also failed sixteen assertions before its paragraph-collapse repair.
The existing clipboard owner caught lost blank markers and terminator differences
during implementation; those controls now pass. The final owner run passes 94
Mac clipboard/document tests (`list103-final-owner-tests.log`).

The pinned Lexical probe is recorded in
`artifacts/native-macos/list103-review/web-paragraph-probe.mjs` and its log.
These are headless tree/export observations, not installed clipboard acceptance.
Nested wrapper export, list/heading/table/code block payloads, arbitrary marker
endpoints, normal interleaved rich admission, ordinal reconciliation and installed
IME/clipboard acceptance remain open. This is not full structured-paste or editor
parity acceptance. Preview 73 predates these native paragraph-paste changes.

### Legacy desktop flag discovery

Current pin/archive flags are shared note metadata. Older desktop flags can also
live under vault-specific keys in that app's private browser storage. The desktop
CLI-install confirmation passes those flags into its Rust metadata migration;
the already-installed CLI's Reinstall action does not run that migration again.
Native CLI metadata setup cannot read those private browser keys. Direct native
import and a complete migration route for already-installed legacy clients remain
open; no user WebKit store or real vault was accessed in this discovery.

Final list103 proof: the exact expanded tests fail against the pre-change
implementation (342 assertions across two owning tests,
`list103-final-expanded-baseline.log`). The final full Mac suite passes all 328
tests with zero failures (`list103-full-tests.log`), including 94 clipboard and
document owner tests. Final source hashes are recorded in
`artifacts/native-macos/list103-review/final-source-hashes.json`.
There are no shared iOS or web implementation changes in this milestone. Web
source hashes still match the last 88-test pass; both preview routes return 200.

## Preview 74 preparation

Version 0.3.34 build 74 contains the checked paragraph-block paste work above and
all earlier native migration work. The existing folder-sidebar hide/restore
control remains included. This is another ad-hoc, non-notarized test build;
installed clipboard/input/IME and complete migration acceptance remain pending.

### Preview 74 artifact handoff

The local build and DMG packager completed successfully. The image was verified
and mounted read-only; the app/CLI identity, versions, architecture and signatures
match the native configuration. The complete private HTTPS download returns 200
and matches the local DMG checksum and size.

Download: https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.34-preview-74-arm64-local.dmg

SHA-256: `2ab1968618b948df56c1bd336184a72c9ad55567399dda3d77df57fba9051233`  
Size: 13,394,711 bytes.  
Receipts: `artifacts/native-macos/artifact-preview-74-local.json` and
`artifacts/native-macos/preview74-handoff.json`.  
Build log: `artifacts/native-macos/preview74-release.log`.

Signing is ad-hoc and notarization was not submitted. The dirty working tree is
not recorded as a complete source snapshot; feature hashes are recorded
separately. Installed clipboard/input/IME acceptance and full parity remain
pending. No iOS changes, Windows release, production release, commit, tag or push
were made in this milestone.


## Companion legacy-state preparation after Preview 74 (migration104)

The React/Tauri desktop companion now has an independent **Review note
metadata…** action under Settings → CLI. SwiftUI already reads the shared
`zerus-pinned`/`zerus-archived` fields; this route transfers older private desktop
flags without requiring CLI installation. The companion reads those private lists
freshly instead of using cached note rows, flushes pending drafts, and freezes the
vault, requested flags, affected paths and metadata counts for confirmation.
Malformed private state is retained and blocks preparation. Apply checks the
active vault and flags again, and Rust checks the full note inventory/original
bytes against the review digest before writing.

The distinct `note_metadata_apply` command cannot install/register the CLI or
rewrite the vault manifest. The existing install flow uses the same reviewed
migration with its registration behavior. A protocol check rejects older runtime
preview responses rather than silently invoking an older installation command.
History records contain the actual planned before/after bytes, use unique IDs
and atomic writes. Rollback checks the committed revision before restoring a note,
so a later write is kept rather than overwritten. Errors after note application
report that the metadata was already applied.

A cross-client regression was also reproduced: private desktop flags could
resurrect an explicit shared `false` written by native. Shared false values now
win both on external refresh and reload. Missing metadata still permits older
private state; removing a previously true shared flag clears it.

Evidence: 26 desktop Rust tests, 24 shared-core tests and 39 related web tests
pass, with TypeScript, changed-file ESLint and the frontend build passing. The
new real-vault tests cover notes-only flag transfer, explicit unpinned values,
untouched manifest bytes, repeat application, history snapshots, and refusing
content/inventory/flag changes. Store regressions cover fresh private state,
unreadable-state preservation, and native false flags through refresh/reload.
The digest guard baseline used the new request transport with the guard disabled;
it is not a run of the unmodified old API. The private-reader baseline exposed
the old materialized-note filtering through the new reader signature. The false
precedence baseline exercised the old merge behavior with that reader present.
Logs and final source hashes are recorded in
`artifacts/native-macos/migration104-verification.json` and its review directory.

Both `/app` preview routes return 200 and serve the updated modules. These changes
belong to the companion and shared web data interpretation, not SwiftUI source;
native Preview 74 and its tested feature hashes are unchanged. The companion's
installed UI/IPC flow, matching companion release, cross-window/provider
acceptance and full migration parity remain pending. No real vault or private
browser store was modified during this work; tests use temporary vaults and
in-memory storage. No iOS change, new native DMG, production release, commit, tag
or push was made.

### List 105: normal rich admission and receiving-paragraph paste

List body paragraphs after child lists now open through the real vault-opening
path in rich mode. Their existing immutable item contexts support formatting,
Return, Backspace, indentation, Cut, body edits and Undo/Redo. Embedded code and
tables, headings/quotes inside items and unsupported HTML keep their source-mode
guards. Normal admission does not mean complete rich-editor parity.

Inline paste inherits the receiving paragraph's list ownership, paragraph layout
and heading/quote role while retaining pasted inline styles. A whole-row inline
replacement preserves the receiving marker and final terminator, so an unselected
sibling cannot merge into it. A selected native paragraph's clipboard terminator
is excluded from the inline body. Paragraph-block paste into a continuation keeps
its first surviving body attached to its item, then closes the container at new
prose. Boundary comparison uses the owning item rather than indentation-only
continuation syntax, avoiding an extra blank before the next sibling.

The owner matrix covers caret, word and whole-row replacement with plain text,
native fragments and HTML; strong styles, logical breaks, nested/quoted/numbered
and checked lists, heading/quote roles, caret placement, follow-up typing and
Undo/Redo. Independent swift-markdown parsing checks parents and body-paragraph
counts. The real workspace owner checks rich opening, edited saves and unchanged
frontmatter while retaining embedded-block source controls. Final baseline cases
fail on the original production sources (3 tests, 671 assertions); the repaired
editor/workspace owner run passes 96 tests. The final full Mac suite passes 329 tests with zero failures. Packaging evidence
is recorded separately in the artifact and handoff receipts.

Broader structured list/heading/code/table paste, arbitrary marker endpoints,
ordinal/display reconciliation, incremental serialization and installed keyboard,
clipboard/IME and full parity acceptance remain pending. The native folders
sidebar remains fully hideable with its restore control available. No iOS source
or App Store build number changes are part of this milestone.

Preview 75 packaging and handoff: the local arm64 DMG passed mounted app/CLI,
minimum-OS, bundle-version, architecture and ad-hoc signature checks. Its complete
private HTTPS download returned 200 and matched SHA-256
`c131f793c0d85edd0a1de3bd31386514a9e926949305e51a8d1f137cebc02124`. Artifact receipt: `artifact-preview-75-local.json`;
handoff: `preview75-handoff.json`; source/test evidence: `list105-verification.json`
in `artifacts/native-macos/`. Feature hashes match the final tested files; the
package receipt records a dirty tree and does not claim a complete source snapshot.

[Download Preview 75](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.35-preview-75-arm64-local.dmg) (0.3.35 build 75, Apple Silicon, macOS 26+).
The app remains an intermediate ad-hoc, non-notarized preview. Installed UI/IME
and full parity acceptance remain pending. The separate companion metadata
migration work is not part of this native DMG. No iOS build, production release,
commit, tag or push was performed.

### List 106: checked list/quote block paste

List and quote payloads now use a structured insertion path rather than carrying
visible marker text through generic replacement. The checked paragraph split
retains the receiving prefix, puts the original suffix in prose, and preserves
surviving descendants after that suffix. Pasted blocks are placed between those
bodies. A quoted list keeps its surrounding quote. Compatible list heads join
without an added loose separator; adopted numbered markers re-indent nested
children when their width grows. The resulting item identities and parents are
checked against the split document plus the inserted subtree before commit.

Plain quote containers take the inline bodies of pasted list items, while a
pasted quote retains its own visible line breaks. A leading heading followed by
paragraphs contributes its first body to the receiving block, matching the pinned
web editor's export. Other mixed block shapes still use the existing paths and
remain part of the broader structured-paste work.

On macOS, HTML child lists directly inside an item now use one Markdown source
newline after the item's preceding body rather than a synthesized blank line.
Other paragraph gaps and intentional blank markers remain distinct. This branch
is excluded from iOS; its previous conversion branch is unchanged. The generic
iOS Simulator build-for-testing passes, without changing the iOS version/build
or making an iOS runtime/installed acceptance claim.

The real clipboard/editor owner covers 144 native/HTML, caret/body-selection and
LF/CRLF combinations. It checks exact saved text, independently parsed parents,
reopening, caret placement, follow-up typing and Undo/Redo. Cross-item replacement
and after-child paragraphs are included. Repeated refused HTML list images at
a caret and across items preserve the note, selection, Undo and asset bytes. The
96 editor/clipboard owner tests pass. The exact final two regression owners fail
against the original production sources (884 assertions). An intermediate run
also exposed the HTML nested-list spacing issue before its conversion repair.

Headless probes use the project's pinned Lexical/MDXEditor visitors and check
export behavior, not an installed browser clipboard. That importer folds
after-child text into the head, so it cannot supply a tail insertion endpoint;
native tail ownership is instead checked against independent CommonMark parsing.
The frozen sources, diffs, probe and evidence logs are in
`artifacts/native-macos/list106-review/` and `list106-*.log`. The final full-suite
rerun passes 330 tests; DMG evidence is recorded in the packaging/handoff receipts.

Mixed list/prose/heading block payloads, code/table block paste, arbitrary marker
endpoints, ordinal/display reconciliation and installed clipboard/keyboard/IME
acceptance remain pending. The fully hideable folders sidebar and its toolbar
restore control remain unchanged. Full desktop parity remains the objective.

A final source review also caught whole-document validation vetoing ordinary
prose when an unrelated native list row is temporary and unmappable. Two new
controls fail before the correction. Same-paragraph prose paste now validates
its own prefix/inserted blocks/suffix without moving an original item. The final
96 editor/clipboard checks pass; the complete baseline uses the final controls.
The earlier `list106-full-tests.log` predates this local-validation repair; use
`list106-verified-full-tests.log` for the final full-suite result.

Preview 76 handoff: the local arm64 DMG passed mounted app/CLI, bundle version,
minimum OS, architecture and ad-hoc signature checks. Its complete private HTTPS
download returned 200 and matched SHA-256
`b250bd2d6ac14b984813e1e707828711f97bb8e35685cfa14360a636f4b94891`. Evidence is recorded in
`artifacts/native-macos/artifact-preview-76-local.json`, `preview76-handoff.json`
and `list106-verification.json`. The final feature hashes match; the package
receipt records a dirty tree and does not claim a complete source snapshot.

[Download Preview 76](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.36-preview-76-arm64-local.dmg) (0.3.36 build 76, Apple Silicon, macOS 26+).
This is an intermediate ad-hoc, non-notarized preview. Full migration, installed
clipboard/keyboard/IME and cross-client acceptance remain pending. No iOS version
change, production release, commit, tag or push was performed.

### List 107: nested HTML checklist ownership and content columns

The macOS HTML converter now chooses an input checkbox only when its nearest
ancestor list item is the item being converted. This retains wrapped/labelled
controls while preventing a child's checked state from changing its parent.
Explicit per-item `aria-checked="true"` and `"false"` values are also read,
matching the pinned Lexical list DOM contract. A valid explicit ARIA value wins
over an input attribute; mixed/unknown ARIA without an owned input does not
invent a checkbox. Plain ordered parents keep their original ordinal.

GFM task syntax follows the two-column bullet content prefix, so child blocks
are indented by two columns rather than by the full `- [x] ` spelling. Ordinary
numbered markers retain their own width. This preserves nested and grandchild
lists instead of turning them into over-indented text or refusing the paste.
The change is macOS-only; the iOS branch keeps its existing conversion behavior.

The real editor owner covers 11 HTML shapes with LF/CRLF endings, including
plain/checked/unchecked ancestors, wrapped inputs, an owned checkbox following
a child's checkbox, numbered parents, three levels, web ARIA state and mixed
ARIA controls. It independently checks CommonMark parent/checkbox arrays,
visible native checkbox glyphs, source/reopen fidelity, caret placement, typing
and Undo/Redo. The exact final test fails on the original converter with 188
assertions. The initial repair passes the focused owner; the final 22-case owner passes
in the full 331-test Mac suite. The iOS compile also passes. Evidence is recorded
in `list107-verification.json`.
The dependency source contract is recorded under `list107-review/`, not claimed
as an installed web clipboard probe.

Broader mixed structured paste, code/table block paste, marker endpoints,
ordinal/display reconciliation and installed HTML clipboard/IME acceptance
remain pending. The folder sidebar remains fully hideable. No iOS version
advance or installed iOS runtime acceptance is part of this milestone.

Preview 77 handoff: the local arm64 DMG passed mounted app/CLI, bundle version,
minimum OS, architecture and ad-hoc signature checks. Its complete private HTTPS
download returned 200 and matched SHA-256
`f32ec0962c36104b0b85752465382d3bd06083c01b74f07059d31f57548410cc`. Evidence is recorded in
`artifacts/native-macos/artifact-preview-77-local.json`, `preview77-handoff.json`
and `list107-verification.json`. The final feature hashes match; the package
receipt records a dirty tree and does not claim a complete source snapshot.

[Download Preview 77](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.37-preview-77-arm64-local.dmg) (0.3.37 build 77, Apple Silicon, macOS 26+).
This is an intermediate ad-hoc, non-notarized preview. Full migration, installed
clipboard/keyboard/IME and cross-client acceptance remain pending. No iOS version
change, production release, commit, tag or push was performed.

### List 108: empty HTML wrappers and leaves

On macOS, a child list with no preceding parent text now starts on a separate
physical source line. It no longer shares the parent's marker line, which the
native list representation cannot pair into distinct item rows. Plain bullet
and numbered parents retain their empty head and child ownership. Empty tasks
use the established invisible blank-paragraph marker so GFM recognizes their
checked state. Empty leaves use that marker too, preventing final whitespace
trimming from turning their marker into ordinary text or forcing source mode.
Typing into an empty leaf removes the blank placeholder from the saved body.

The existing real editor owner is extended rather than duplicated. Its 40 cases
cover prior ownership/indentation fixtures plus empty bullet/numbered wrappers,
checked and unchecked empty parents, three levels, a retained tail paragraph,
empty checked leaves and empty bullet/numbered refill. Independent CommonMark
parents and checkbox arrays, visible glyphs, exact saved source, reopen, caret,
Undo/Redo and follow-up typing are checked. The complete owner fails against the
previous converter with 50 assertions; an isolated empty-leaf baseline fails
8 assertions. All 97 editor/clipboard checks and the full 331-test Mac suite
pass after repair. The shared-file iOS compile also passes; evidence is recorded
in `list108-verification.json`.

The changed conversion branches are macOS-only; iOS retains its existing behavior
and version/build. Full installed HTML clipboard/IME acceptance, mixed structured
paste, code/table blocks, marker endpoints and ordinal/display reconciliation
remain pending. The fully hideable folders sidebar remains preserved.

Preview 78 handoff: the local arm64 DMG passed mounted app/CLI, bundle version,
minimum OS, architecture and ad-hoc signature checks. Its complete private HTTPS
download returned 200 and matched SHA-256
`520003952564d4b7bcff7cee9b8cdc6ef45c0d9abe47cd5c216dec79292d9504`. Evidence is recorded in
`artifacts/native-macos/artifact-preview-78-local.json`, `preview78-handoff.json`
and `list108-verification.json`. Feature hashes match the final tested files;
the package receipt records a dirty tree and does not claim a complete source
snapshot. The README now summarizes current native behavior, with historical
preview-specific claims retained here in the detailed migration notes.

[Download Preview 78](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.38-preview-78-arm64-local.dmg) (0.3.38 build 78, Apple Silicon, macOS 26+).
This remains an intermediate ad-hoc, non-notarized preview. Full migration and
installed clipboard/keyboard/IME acceptance remain pending. No iOS version
change, production release, commit, tag or push was performed.

### List 109: nested ordered starts and paragraph boundaries

Nondefault ordered child starts now get a paragraph boundary when CommonMark
would otherwise absorb the marker into preceding body text. The macOS converter
checks the actual emitted first marker, including an HTML li value override,
and parses its local body context with the existing Swift Markdown dependency.
It looks for the new ordered item's source line rather than resetting its start
to one. Empty tasks account for their preserved blank body, so their checked
state and child ordinal both survive. Empty plain wrappers and already-valid
list boundaries stay compact; an unnecessary blank must not close an empty head.
The owning checkbox lookup is shared by marker generation and this decision.

The existing editor owner adds 20 LF/CRLF cases for text/task/empty parents,
wrapped paragraphs, per-item ordinal overrides, a retained tail before the new
list, and compact empty/list/default-start controls. Its total is 60 cases. The
previous converter fails 102 assertions; the repair passes the focused owner.
Expected source and parent arrays are handwritten and checked with independent
CommonMark structure, native glyphs, caret, reopen, typing and Undo/Redo. A small
separate CommonMark probe records the paragraph-versus-list boundary rule in
`artifacts/native-macos/list109-review/commonmark-boundaries.log`.

The parser import and separator change are macOS-only. iOS keeps its existing
conversion behavior and version/build. The final full Mac suite passes 331 tests,
and the iOS compile passes. Evidence is recorded in `list109-verification.json`. Mixed structured payloads, code/table blocks,
marker endpoints, ordinal/display reconciliation and installed clipboard/IME
acceptance remain pending. The fully hideable folders sidebar remains unchanged.

Final ordinal validation applies the supported 0–999,999,999 integer range to
starts, item overrides and implicit continuation before emission/increment.
Overflowing numeric strings are refused instead of defaulting to one. Valid
whitespace/sign forms normalize; missing/noninteger attributes keep their prior
fallback. Numbering attributes on unordered lists are ignored.

The final owner has 74 positive LF/CRLF cases and six refusal controls. The
exploratory 15-assertion bound baseline included zero as a refusal; that policy
was corrected, and only its negative/over-limit rows support the final refusal
contract. The incomplete integer-normalization baseline has 22 failures. The
zero-start baseline has four failures before zero is accepted. CommonMark and
the native model support zero; the pinned web exporter currently normalizes it
to one, so native zero preservation is not claimed as web export parity.

These are staged baselines, not one run of every final case against original
code. Maximum-integer rejection is verified after the guard; the old increment
overflow path was code-traced and not deliberately crashed in the test host.
All 97 editor/clipboard tests pass on the final source. Earlier full logs and
the private interim DMG predate final guards/zero support and were not shared.
Final evidence uses `list109-complete-full-tests.log`,
`list109-complete-ios-compile.log` and `list109-verification.json`.

The complete final rerun passes 331 Mac tests and the shared-file iOS compile.
Only the final rebuilt artifact and checksum below are the Preview 79 handoff;
the earlier private interim binary was not shared.

Final Preview 79 handoff: the rebuilt local arm64 DMG passed mounted app/CLI,
bundle version, minimum OS, architecture and ad-hoc signature checks. Its complete
private HTTPS download returned 200 and matched SHA-256
`ebe23b0c103a2fc98b94eb144e8ed27cefa68a12d550ac8fda37b2f4b9a55774`. Evidence is recorded in
`artifacts/native-macos/artifact-preview-79-local.json`, `preview79-handoff.json`
and `list109-verification.json`. Feature hashes match the final tested files;
the package receipt records a dirty tree and does not claim a complete source
snapshot. The private interim artifact is retained only as historical evidence.

[Download Preview 79](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.39-preview-79-arm64-local.dmg) (0.3.39 build 79, Apple Silicon, macOS 26+).
This remains an intermediate ad-hoc, non-notarized preview. Full migration and
installed clipboard/keyboard/IME acceptance remain pending. No iOS version
change, production release, commit, tag or push was performed.


## Mixed structured paste — list110 / Preview 80

The checked block planner now accepts optional first and last inline paragraph
bodies around its middle blocks. The first body keeps the receiving paragraph's
role; the last body joins the retained suffix as prose. A leading pasted heading
uses the receiver's role, matching the pinned web export probes. Lists at either
payload edge remain blocks. A plain quote receiver concatenates the pasted bodies
inside its quote. Paragraphs after children follow the native ownership contract;
MDXEditor's import collapses those paragraphs, so those fixtures are not labeled
web parity. Code/table payloads and arbitrary marker endpoints remain pending.

The editor-boundary owner extends its existing matrix by fifteen mixed payload
cases across fragment/HTML, caret/replacement and LF/CRLF paths (120 combinations).
It checks exact Markdown, independent CommonMark parent arrays, reopen, caret,
Undo/Redo and follow-up typing. The final test fails on the original production
source with 568 assertions (`list110-final-baseline.log`); all mixed rows pass on
the repaired source (`list110-expanded-owner-tests.log`). Asset preflight uses
this same planner before importing files. There is no change to the shared HTML
converter or iOS behavior in this milestone. Native installed clipboard and IME
acceptance remain pending; no full desktop parity claim is made.

Final verification: `list110-full-tests.log` reports **331 tests, zero failures, TEST SUCCEEDED**. The local DMG build exits 0; the packaged arm64 app/CLI signature and mounted disk image pass verification. The full HTTPS download returns 200 and matches the artifact checksum.

[Download Preview 80](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.40-preview-80-arm64-local.dmg) (0.3.40 build 80, Apple Silicon, macOS 26+, ad-hoc and not notarized).

SHA-256: `819643c973b239ed36e10a30401c6bd38a90c4d85523e2f560de4cc92dd97bf0`. Artifact and delivery details are in `artifact-preview-80-local.json` and `preview80-handoff.json`.


## Structured code/table paste — list111 / Preview 81

The checked block path now retains native code and table cards, both alone and
between inline paragraph endpoints. Receiving prose, headings, list heads and
paragraphs after children keep their prefix and suffix. The caret stays in the
final code body or table cell when the payload ends in a card, or after the final
pasted prose body otherwise. Empty cards remain editable. Native table width
metadata stays attached to the table and is checked at the real paste boundary.
An intentional trailing blank line inside code remains content; it does not count
as the paragraph boundary before the receiving suffix.

Pinned Lexical/MDXEditor headless probes (`list111-review/web-card-probe.log`)
retain root cards in prose, headings and root list items. The web quote path
silently drops those decorators. Native deliberately closes a plain quote around
the inserted root card to preserve its content. This is a native preservation
rule, not a claim of quote export parity. As in earlier milestones, MDXEditor
cannot supply the after-child paragraph endpoint; those native cases check the
native ownership contract. Nested web wrapper exports are not acceptance evidence.

The existing structured-paste owner now has code/table cases across fragment/HTML,
caret/replacement and LF/CRLF inputs, plus native width metadata, empty-card and
multiline/trailing-blank code controls. It checks literal saved Markdown,
independent CommonMark item parents, reopen, caret, Undo/Redo and subsequent typing.
`list111-final-baseline.log` fails with 796 assertions on the original production
source for the card/quote/width/empty cases. Four later multiline code controls
were added separately: `list111-code-ending-baseline.log` records six failures
on the intermediate repair, before the card-content/boundary fix. That intermediate
source was not separately frozen, so the log is not an exact-hash baseline claim.
`list111-complete-clipboard-tests.log` passes all 22 clipboard tests on the final
behavior. Source snapshots and hashes are in `list111-review/`.

There is no iOS source or behavior change. Code creation off still converts
formatted code paste to literal prose. Embedded code/tables inside imported list
or quote containers, arbitrary marker endpoints and larger range replacement,
installed clipboard/IME acceptance and full desktop parity remain pending.

Final full Mac verification: `list111-full-tests.log` reports **331 tests, zero failures, TEST SUCCEEDED** on the frozen source hashes. Packaging and private-download verification follow in the artifact/handoff records.

Packaging exits 0. The packaged arm64 app/CLI signature and mounted disk image pass verification; the full private HTTPS download returns 200 and matches its checksum.

[Download Preview 81](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.41-preview-81-arm64-local.dmg) (0.3.41 build 81, Apple Silicon, macOS 26+, ad-hoc and not notarized).

SHA-256: `92c7fac3d38b32b85f076fbd25b9d2ff0a251054836eedcfa5151fe302715fe6`. See `artifact-preview-81-local.json` and `preview81-handoff.json`. Installed clipboard/IME and full parity remain pending.


## Marker-touching list replacement — list112 / Preview 82

List markers are native presentation, not editable body text. A selection touching
a marker now passes a normalized body range to the checked ownership planner.
The starting paragraph keeps its role; selected bodies merge and removed wrappers
re-home their surviving children through the existing planner. This covers typing,
Delete, Cut and plain/native/HTML inline or hard-break paste. A complete selected
marker keeps the lift command (including Cut); deleting only part of a marker
protects that marker and moves the caret to the body. Whole-paragraph deletion
keeps its existing command. A temporary row whose visible marker is absent is
refused before guessing a body range, preserving text, selection and clipboard.

The web editor's markers are structural decorations with no corresponding text
offset. `list112-review/web-marker-body-probe.log` therefore compares equivalent
body-boundary selections using pinned Lexical/MDXEditor visitors, including GFM
tasks. Native owner expectations are handwritten, with independent swift-markdown
parent checks. The nine replacement rows cover both marker endpoints, nested and
quoted lists, numbered lists, checklists, same-item replacement and partial-marker
protection. LF/CRLF, delete/replace, Undo/Redo, selection, typing layout and
follow-up typing are checked. Transport extensions verify original clipboard
fragments and Cut undo, plus six inline/hard-break formats. Markerless refusal
keeps the clipboard's change count and note untouched.

`list112-final-baseline.log` runs the final three changed owners on the original
production source and fails with **352 assertions** for those contracts. The
pre-fix production snapshot and final feature hashes are in `list112-review/`.
Structured block paste at marker endpoints, larger arbitrary ranges, markerless
editing, ordinal/display reconciliation, installed clipboard/IME and full desktop
parity remain open. There is no iOS source or behavior change.

Boundary follow-up: the first full run (`list112-full-tests.log`) caught one regression in the pre-existing independent-paragraph owner: a blank selected row ending exactly before an empty marker consumed it. That exclusive end now selects no marker. All four affected owners pass in `list112-boundary-owner-tests.log`; the complete rerun is recorded separately.

Final verification: `list112-complete-full-tests.log` passes **331 tests, zero failures, TEST SUCCEEDED** on the final frozen feature hashes, including the exclusive-end regression control. No iOS source, build number or runtime behavior changed.

Packaging exits 0. The packaged arm64 app/CLI signature and mounted disk image pass verification; the complete private HTTPS download returns 200 and matches its checksum.

[Download Preview 82](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.42-preview-82-arm64-local.dmg) (0.3.42 build 82, Apple Silicon, macOS 26+, ad-hoc and not notarized).

SHA-256: `cb6accede2a5b74225af5076430af93d4bd9ecb330aaa5f6b66d090582eb7d23`. See `artifact-preview-82-local.json` and `preview82-handoff.json`. Installed clipboard/IME acceptance and full desktop parity remain pending.


## Structured paste at marker selections — list113 / Preview 83

The private body-range resolver is shared by replacement and structured paste.
A touched marker selects body content; an exclusive end before a marker does not
select it. Missing visible markers refuse before resource import. Paragraphs,
lists, mixed bodies, code and tables therefore follow the same relationship plan.
When a block-only payload replaces the beginning of an item, its empty receiving
wrapper and generated separator are omitted once no child items remain owned by
it. Nonempty prefixes and literal spaces remain. A real suffix row is provided
when planning EOF insertion, preventing the formatter from changing the preceding
head. Synthetic empty EOF suffixes are not saved as extra blank paragraphs.

Unselected tails can carry two logical breaks inside a native item paragraph.
After closing that item, those breaks become real root/quote paragraph boundaries.
The saved Markdown stays the same, while immediate heading conversion affects
only the tail, matching reopening. Hard breaks and inline HTML breaks are retained.
The checked pre-insertion graph is an immutable snapshot before payload insertion.

The existing structured-paste owner gains 42 literal marker/EOF/role/tail cases,
with fragment/HTML and LF/CRLF variants. A note without any line-ending evidence
uses LF, including CRLF fragment normalization; duplicate no-ending HTML variants
are skipped. Expected bytes, independent CommonMark parents, Undo/Redo, caret and
follow-up typing are checked. Tail cases use the public heading command to prove
independent editing rather than requiring a particular internal break character.
Pinned headless Lexical/MDXEditor body-boundary probes are recorded in
`list113-review/web-structured-marker-probe.log`; marker characters themselves
are not text positions in that editor. Native tables retain their own delimiter
spelling and omit Lexical's trailing empty export paragraph as before.

`list113-final-baseline.log` runs the final owner on the original production file
and fails with **940 assertions**. `list113-tail-public-baseline.log` additionally
runs the repaired marker/EOF path with the tail materialization hunk removed; the
heading control fails eight times. That exact variant is retained as
`BASELINE-tail-public-MacListEditing.swift`. The final complete run,
`list113-full-tests.log`, passes **331 tests, zero failures, TEST SUCCEEDED**.
Feature hashes and source snapshots are in `list113-review/`.

Larger arbitrary ranges, editing at collapsed carets inside markers, embedded
containers, complete bare-CR handling, ordinal/display reconciliation, installed
clipboard/IME and full desktop parity remain open. No iOS source or behavior was
changed. The fully hideable folder sidebar and its restore control remain.

Packaging exits 0. The packaged arm64 app/CLI signature and mounted disk image pass verification. The complete private HTTPS download returns 200 and matches the artifact checksum.

[Download Preview 83](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.43-preview-83-arm64-local.dmg) (0.3.43 build 83, Apple Silicon, macOS 26+, ad-hoc and not notarized).

SHA-256: `4b3cdc658608a08f730ada36673ac197a22394e166dc70a97b3e3757512d9c5a`. See `artifact-preview-83-local.json` and `preview83-handoff.json`. Full desktop parity and installed clipboard/IME acceptance remain pending.


## Native marker carets — list114 / Preview 84

The production MacEditorTextView now asks its coordinator for a legal insertion
range. Selection changes and load/command/Undo restoration normalize collapsed
carets inside a visible list marker to the body boundary. Nonempty selections,
source mode, code/table cards and marked composition retain their existing paths.
Text services supplying an explicit replacement range receive the same guard
before insertion or the start of composition. AppKit owns provisional marked
text; it is not published to autosave. Ordinary prose needs no list parsing.

The native view uses the shared checked body-range helper. It validates the
visible prefix before moving the caret. Bare NSTextView coordinator fixtures
remain lower-level malformed-row recovery checks. An empty checked head created
by Return keeps the existing invisible empty-paragraph anchor, so its task state
survives reopening. Structured paragraph/list/code/table paste accepts a caret at
non-terminated EOF; a trailing-newline EOF remains a new paragraph.

The new hosted SwiftUI owner exercises bullet/numbered/task/quoted/nested items,
every visible prefix offset, LF/CRLF, typing, Return, backward/forward deletion,
marked text and explicit replacement ranges. It checks saved bytes, independent
CommonMark parents, reopen, Undo/Redo and follow-up typing. Forward-delete Undo
retains AppKit's restored-character selection. Empty EOF and source-mode controls
are included. Five empty-EOF caret payloads extend the existing structured-paste
owner across fragment/HTML variants. The exact final tests fail on Preview83
production with 1,273 assertions in `list114-final-baseline.log`. Earlier passing
owner evidence covers 98 tests before the explicit-range variants were added;
the final complete run is recorded in `list114-verification.json`.

Larger arbitrary ranges, embedded containers, complete bare-CR handling,
ordinal/display reconciliation and installed clipboard/IME acceptance remain
pending. Hosted text-input tests do not establish physical keyboard/IME or
installed-app acceptance. Full desktop feature parity remains in progress.
The fully hideable folder sidebar and its toolbar restore control remain.

Final verification: `list114-full-tests.log` passes **332 Mac tests, zero failures, TEST SUCCEEDED** with exit 0 on the frozen feature hashes. Packaging and download verification are recorded in the artifact/handoff receipts.

Packaging exits 0. The packaged arm64 app/CLI signature and mounted disk image pass verification. The complete private HTTPS download returns 200 and matches the artifact checksum.

[Download Preview 84](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.44-preview-84-arm64-local.dmg) (0.3.44 build 84, Apple Silicon, macOS 26+, ad-hoc and not notarized).

SHA-256: `16006c1be883c7ffb2b9be53085ab78773086214a57846dc0e1feaaf14c52fd7`. See `artifact-preview-84-local.json` and `preview84-handoff.json`. Full parity and installed clipboard/IME acceptance remain pending.


## Return over selected list content — list115 / Preview 85

Selected Return previously skipped the checked item planner and let AppKit
replace the physical range with a newline. That could leave visible marker text
inside an item and lose the relationship of retained child items on reopening.
Return now prepares the deletion with the existing ownership planner, then splits
that planned document through the ordinary Return path. Only the final edit is
committed, so a single Undo restores the source and original selection. A refused
plan changes neither the document nor the Undo history.

The planner's paragraph-split mode also handles same-item body selections and
marker-only selections. An endpoint exactly before the next visible marker maps
to that item's body start for the split; ordinary Delete/Cut retain their existing
exclusive-end rules. A prose start receives a real paragraph separator, and a
quote start receives a quoted blank separator, matching the web editor's distinct
paragraphs rather than soft continuation text. Existing collapsed Return and
source-mode paths remain in place.

The existing Return owner now contains 14 selected-range fixtures across LF and
CRLF: nested/deeper starts, root prose, quote boundaries, numbered width changes,
checked tasks, same-item and marker ranges, and next-row/exclusive endpoints.
Hosted SwiftUI tests assert exact source, independently parsed parent indexes,
paragraph counts for prose/quote starts, single-step Undo/Redo, original selection
restoration and follow-up typing. The existing unmatched-list owner additionally
checks a selected Return refusal leaves text, selection and Undo untouched.

Pinned headless Lexical/MDXEditor `insertParagraph()` output is recorded in
`list115-review/web-selected-return-probe.log`. Native retains its existing saved
ordinal spelling (the 9→10 case) and omits the web export's trailing empty paragraph;
this milestone does not claim ordinal reconciliation or installed-keyboard parity.
The final tests fail with **70 assertions** on Preview84 production in
`list115-final-baseline.log`. An intermediate implementation's row-boundary gap
is separately demonstrated by eight assertions in `list115-boundary-baseline.log`.
The final document/clipboard owner run passes 98 tests. Full-suite and packaging
results are recorded in `list115-verification.json` and the handoff receipt.

Larger arbitrary ranges, embedded containers, complete bare-CR handling,
ordinal/display reconciliation and installed clipboard/IME acceptance remain
pending. Full desktop feature parity remains in progress. The fully hideable
folder sidebar and its toolbar restore control remain.

Final verification: `list115-full-tests.log` passes **332 Mac tests, zero failures, TEST SUCCEEDED** with exit 0 on the frozen feature hashes. Packaging and download verification are recorded in the artifact/handoff receipts.

Packaging exits 0. The packaged arm64 app/CLI signature and mounted disk image pass verification. The complete private HTTPS download returns 200 and matches the artifact checksum.

[Download Preview 85](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.45-preview-85-arm64-local.dmg) (0.3.45 build 85, Apple Silicon, macOS 26+, ad-hoc and not notarized).

SHA-256: `2231aa4f7b0b509e347b99f1f320e56c04bf77ea081baf305ae83e3374c7ba06`. See `artifact-preview-85-local.json` and `preview85-handoff.json`. Full parity and installed clipboard/IME acceptance remain pending.


## Native horizontal rules — rule116 / Preview 86

The web editor supports thematic breaks as imported blocks, toolbar insertions
and typed shortcuts. Native root rules previously forced Source mode, while
quoted rules could be silently omitted by rich rendering. Rules now have an
atomic native attachment in root/quote paragraphs. The attachment fills the
writing column and carries the accessibility description “Horizontal rule”.
Original marker spelling, indentation, quote prefix, LF/CRLF and terminal-newline
choices survive unedited export and edits around the block. A heading converted
to prose above a dash rule gains a separator so the rule cannot become a setext
heading on save. Ordinary paragraph formatting does not turn a selected rule
into a heading or list.

The minus button inserts a rule through the checked structural paste planner.
Typing `---`, `***` or `___` followed by Space creates a rule and a receiving
paragraph. Empty receiving paragraphs now keep their stored role and line ending;
this also fixes a quote/CRLF inheritance issue exposed by the shortcut. Typing
beside a rule creates a separate paragraph rather than copying its literal marker
onto the new text. Existing list-selection and caret handling remain in place.

Marked input beside a rule uses an empty native input paragraph that emits no
Markdown while empty. AppKit owns composition. Transient ranges are excluded
from Undo, then a completed composition registers one immutable snapshot, even
when input spans run-loop events. Cancellation restores the original native view
without a saved blank paragraph or Undo entry. Loading/detaching balances pending
Undo registration. Hosted API tests cover these paths; physical keyboard, IME,
dictation and installed VoiceOver acceptance remain pending.

Copy and Cut retain native Markdown and additionally supply semantic HTML for
image-free rule fragments through the existing static export parser. No vault
image is created for the line. Existing `<hr>` HTML import now reaches the native
renderer. Rule insertion uses the existing card boundary policy, preserving both
the rule and surrounding text. The pinned headless web probe in
`rule116-review/web-rule-probe.log` matches root prose/list insertion structure;
its plain-quote case drops the rule, while native closes the quote and preserves
all content, as with native code cards. Native keeps imported marker spelling
rather than canonicalizing every rule to the web export's `***` spelling.

Rule boundary validation parses only the source since the previous rule, which
already closes list/paragraph ownership; it does not reparse the whole accumulated
note for every rule. Notes without rules do not build that additional window.
Empty composition-scaffold rows are skipped only while they have no content.

The new hosted native owner covers marker variants, quotes, CRLF, column sizing,
nearby edits, deletion, insertion, shortcuts, replacement, formatting controls,
setext protection, composition commit/cancellation, Undo/Redo and follow-up typing.
The new clipboard owner covers actual pasteboard Cut, Markdown/HTML transport,
resource-free HTML/fragment paste, retained children and continued typing.
Existing unedited-round-trip fixtures add adjacent rules and rules after code.
The core feature fixtures fail on Preview85 production with **147 assertions** in
`rule116-final-baseline.log`. The preceding complete editor/clipboard owner run
passed 100 tests; final composition controls also pass. Full-suite and artifact
results are recorded in `rule116-verification.json` and the handoff receipt.

Rules inside list items remain part of the pending embedded-container work.
Embedded code/tables, larger arbitrary ranges, full bare-CR handling,
ordinal/display reconciliation, incremental serialization and installed
clipboard/IME/visual acceptance remain pending. Full desktop parity remains in
progress. The fully hideable folder sidebar and its restore control remain.

The first full run, `rule116-full-tests.log`, isolates four selected-rule replacement failures. `BEFORE-selected-replacement-MacMarkdown.swift` retains that exact variant. Native input now clears inherited attachment/literal metadata before replacement; the four final focused rule, clipboard and existing composition owners pass. The final complete rerun is `rule116-verified-full-tests.log`.

Adjacent-rule Backspace/Delete matches the pinned web probe in `web-rule-delete-probe.log`: the rule is removed atomically and the surrounding paragraphs remain separate. The added root/quote, LF/CRLF keyboard rows fail 36 assertions on `BEFORE-keyboard-boundary-MacMarkdown.swift` (`rule116-keyboard-boundary-baseline.log`) and pass after repair. The original 147-assertion Preview85 baseline uses the core test variant retained in `BEFORE-keyboard-boundary-MacDocumentTests.swift`; the later keyboard rows have their own pre-fix run. The complete final rerun is `rule116-complete-full-tests.log`.

Final verification: `rule116-complete-full-tests.log` passes **334 Mac tests, zero failures, TEST SUCCEEDED** with exit 0 on the frozen feature hashes. Packaging and download verification are recorded in the artifact/handoff receipts.

The pre-handoff CR compatibility check finds three unsafe admissions in `rule116-cr-admission-baseline.log`. Bare-CR rule documents now remain in Source until complete CR tokenization is implemented; LF/CRLF native rules are unaffected. The unshared first DMG is retained as `preview86-before-cr-guard.dmg` and is not the handoff artifact. Final frozen-source verification is `rule116-final-complete-full-tests.log`, followed by rebuilding Preview86 on those sources.

Final frozen-source verification after the CR admission guard: `rule116-final-complete-full-tests.log` passes **334 Mac tests, zero failures, TEST SUCCEEDED** with exit 0. The handoff DMG is rebuilt from these hashes.

Final packaging exits 0. The packaged arm64 app/CLI signature and mounted disk image pass verification. The complete private HTTPS download returns 200 and matches the artifact checksum.

[Download Preview 86](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.46-preview-86-arm64-local.dmg) (0.3.46 build 86, Apple Silicon, macOS 26+, ad-hoc and not notarized).

SHA-256: `1279411d23ed2329e3e18e68585c3ed9ba5df2178fd93f27587a6e164f01c0c1`. See `artifact-preview-86-local.json` and `preview86-handoff.json`. This is the rebuilt artifact after the CR admission guard. Full parity and installed clipboard/IME/VoiceOver acceptance remain pending.


## Native source line endings — lines117 / Preview 87

The renderer, indented-code mapper and fenced-code scanner now use CommonMark
source rows (CR, LF or CRLF) with UTF-16 offsets and exact stored terminators.
Native paragraph boundaries remain LF. Heading/list/quote ownership no longer
uses an LF-only array or masks CR inside card bodies. Table edits use their
header's CR convention without changing the shared iOS table implementation.
Uniform fenced-code bodies normalize newly inserted rows to the original ending;
mixed existing bodies keep their bytes. Rule tokens retain an EOF ending preference.

The editor owner checks eight block shapes with all three ending conventions,
with and without a final terminator, exact edits, reopen, selection and Undo/Redo.
It includes mixed source rows, list Return, code Return and plain EOF Return.
The clipboard owner adds CR-only receiving lists for rule paste and follow-up
typing. The final tests fail **37 assertions** on Preview86 production in
`lines117-final-baseline.log`; the initial and expanded repair checks pass.
Final frozen-source verification: `lines117-full-tests.log` passes **335 Mac
tests, zero failures, TEST SUCCEEDED**, exit 0. Packaging and delivery checks are
recorded in `lines117-verification.json` and the artifact receipt.

This is a native Mac change. No iOS source/version is changed. The fully hideable
folder sidebar and its restore control remain an intentional native choice.
Embedded containers, larger arbitrary ranges, ordinal/display reconciliation,
incremental serialization and installed clipboard/IME/VoiceOver acceptance remain
pending. Full desktop parity remains in progress.

Final packaging exits 0. The packaged arm64 app and CLI signatures and mounted
DMG pass verification. The full private HTTPS download returns 200 and matches
the local DMG bytes and checksum.

[Download Preview 87](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.47-preview-87-arm64-local.dmg) (0.3.47 build 87, Apple Silicon,
macOS 26+, ad-hoc and not notarized).

SHA-256: `a73bce785db180634232da9cb0135f462a134362dc36ae225607baca051de14f`. See
`artifact-preview-87-local.json`, `lines117-verification.json` and
`preview87-handoff.json`. Full parity and installed clipboard/IME/VoiceOver
acceptance remain pending.


## Code-sheet block identity and spelling — blocks118 / Preview 88

A single top-level code-block locator now drives card rendering, menu entries and
sheet target identity. The sheet no longer counts only LF bytes to identify its
native card. Indented code is available directly from the menu, stays indented
on compatible body edits, and changes to fences only for a language or blank
edge lines. No-op saves leave the caret and Undo stack unchanged. Scoped source
snapshot checks continue to reject stale commands.

The existing sheet command owners now cover fenced and indented edits/conversion,
LF/CRLF/CR, rich/Source modes, prior prose Undo/Redo, no-op selection, insertion
and the creation preference. They fail **21 assertions** on Preview87 production
in `blocks118-baseline.log`. A hosted SwiftUI form test edits the actual text and
language fields, then sends Return to save; it independently checks the emitted
Markdown and parser body. It fails three spelling assertions on the old form
in `blocks118-form-save-baseline.log` and passes after repair. The earlier
`blocks118-form-baseline.log` and `blocks118-keyboard-form-baseline.log` are
superseded fixture/API failures and do not count as regression evidence.

The final focused command/form/window/stale-owner run passes four tests in
`blocks118-complete-owner-tests.log`. Full-suite and packaging evidence are
recorded in `blocks118-verification.json` and the artifact receipt.

This is Mac-only work. Embedded code/tables remain Source-only; this does not
claim container support. Larger arbitrary ranges, ordinal/display reconciliation,
incremental serialization and installed UI/clipboard/IME/VoiceOver acceptance
remain pending. The fully hideable folder sidebar and restore control remain.

Final frozen-source verification: `blocks118-full-tests.log` passes **336 Mac
tests, zero failures, TEST SUCCEEDED**, exit 0. The form test is a hosted native
view check, not installed-app or physical IME acceptance.

Final packaging exits 0. The arm64 app/CLI signatures and mounted DMG pass
verification. The complete private HTTPS download returns 200 and matches the
local image and artifact checksum.

[Download Preview 88](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.48-preview-88-arm64-local.dmg) (0.3.48 build 88, Apple Silicon,
macOS 26+, ad-hoc and not notarized).

SHA-256: `fd4cad357b026ff4181c9d7751144e92b6bf5d4e2d4f44fc44a4edc169788ee9`. See
`artifact-preview-88-local.json`, `blocks118-verification.json` and
`preview88-handoff.json`. Full desktop parity and installed acceptance remain
pending.


## Quote-owned code and tables — quotes119 / Preview 89

Native card tokens retain an immutable quote context separately from their
editable body/model. Unchanged cards export their exact quote spelling; changed
cards retain their original depth. The parser owns source ranges, logical code
bodies and quote depth, including compact prefixes and partially consumed tabs.
Indented fence bodies are displayed as CommonMark reads them, with canonical
fences on edits where necessary. Single-line EOF cards inherit the surrounding
source ending. Code/table menu entries and sheets use the same container-aware
locators; table row creation and spreadsheet edits carry the quote token.

Whole-card copy/Cut exports portable quoted Markdown and semantic HTML without
creating image assets. Subgrid copies remain standalone cell grids. Native and
HTML paste preserve the card's quote depth; the disabled-code-creation setting
also converts quoted pasted code to literal quoted prose. Continue-after-card at
EOF retains its quote. Continue-after-unclosed-code explicitly closes the fence
before prose and keeps that command separate from subsequent typing in Undo.

The final regression owners cover 27 quote/card/ending shapes, editor edits,
reopening, sheets, table rows, clipboard/Cut/HTML/native transport, no assets,
creation-off, quote/tab/fence edges, EOF and unclosed fences, Undo/Redo and real
workspace admission/persistence. They fail **201 assertions/errors** against
Preview88 production in `quotes119-final-baseline.log` and pass with the repair
in `quotes119-final-verified-owner-tests.log`. Earlier fixture/API and intermediate
failure logs are not final passing evidence. A direct probe against the bundled
cmark objects (`quotes119-parser-probe.log`) pins tab-prefixed fence semantics.

Full frozen-source test results and packaging are recorded in
`quotes119-verification.json` and the artifact receipt. This is Mac-only work;
there is no iOS implementation change. The fully hideable folder sidebar and its
restore control remain. List-owned cards, broader container formatting/selection,
ordinal/display reconciliation, incremental serialization and installed
UI/clipboard/IME/VoiceOver acceptance remain pending. Full desktop parity is
still in progress.

The first full run (`quotes119-full-tests.log`) finds one stale workspace
expectation requiring quoted indented code to use Source. That row is updated
for the intentional new native admission. Final frozen-source verification in
`quotes119-final-full-tests.log` passes **340 Mac tests, zero failures,
TEST SUCCEEDED**, exit 0. This is hosted/development evidence, not installed
clipboard, physical IME or visual acceptance.

Final packaging exits 0. The arm64 app/CLI signatures and mounted DMG pass
verification. The complete private HTTPS download returns 200 and matches the
local image bytes and artifact checksum.

[Download Preview 89](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.49-preview-89-arm64-local.dmg) (0.3.49 build 89, Apple Silicon,
macOS 26+, ad-hoc and not notarized).

SHA-256: `723be7768d261e988f7d6120ee6ce07863286db0a20bdb12bf36014d479cd55b`. See
`artifact-preview-89-local.json`, `quotes119-verification.json` and
`preview89-handoff.json`. Full desktop parity and installed acceptance remain
pending.


## List-owned card source boundaries — lists120

Parser-owned code/table discovery now follows list and quote containers, including
cards beginning on an item marker line, nested same-line markers, tab padding,
indented code and tables that interrupt a paragraph. The Tables and code menu
includes these cards in source order. Source sheets retain exact no-op bytes,
wrap changed payloads with the owning prefixes and check the resulting parent
graph and card body before saving. Rejected drafts remain available in the sheet.
Root code discovery also avoids treating a list fence as the start of a later
root block. Quoted tables directly after prose retain the preceding paragraph.

This is the source ownership layer for native list cards. Rich list-owned
code/table admission remains guarded until structural commands and clipboard
operations carry their native item identities. No iOS source/version changes.
The fully hideable folder sidebar remains intentional native behavior.

The final two regression owners fail 63 assertions against Preview 89 production
in `lists120-complete-baseline.log`. They use Source sheet notifications, exact
LF/CRLF/CR expected edits, independent parser parent arrays, stale/refused saves
and Undo/Redo. Final full-suite and packaging evidence are recorded separately.

The final frozen-source run (`lists120-full-tests.log`) passes **341 tests, zero
failures, TEST SUCCEEDED**, exit 0. The final message wording and bounded marker
scan are covered by this run. Earlier focused logs cover the preceding repair.
See `lists120-verification.json` for exact hashes and evidence status.

Packaging exits 0. The arm64 app and bundled CLI signatures and mounted DMG pass
verification. The complete HTTPS download returns 200 and matches the local
image bytes and artifact checksum. Both the web frontend and private proxy
respond successfully.

[Download Preview 90](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.50-preview-90-arm64-local.dmg) (0.3.50 build 90, Apple Silicon,
macOS 26+, ad-hoc and not notarized).

SHA-256: `b2447c57408f8d909fdfa1b3d5c1968d436286b2d3acc173a5a91d15e4f1b23f`. See
`artifact-preview-90-local.json`, `lists120-verification.json` and
`preview90-handoff.json`. Full desktop parity, rich list-card admission and
installed UI/clipboard/IME/VoiceOver acceptance remain pending.


## Native list-card ownership core — lists121 (development, not packaged)

Separate-line code/table cards now carry live native item identities independently
of their immutable code/table models. Export follows changed marker widths and
quote prefixes. Native cell blocks and code styling survive context refreshes.
Whole-card units retain their models when a head becomes a heading; empty heads
keep the boundary required by an indented code child. Table row replacement
retains placement, and cell source fingerprints ignore outer item placement so
unchanged inline Markdown keeps its original spelling.

The owner test deliberately uses forced rich editor entry. **Normal workspace
admission is unchanged:** list-owned cards still open in Source. Inline-first
card heads, clipboard/Continue-after-code and broader command/range integration
are not complete, so this is not a claim of native list-card feature completion.
Preview 90 remains the latest delivered DMG and does not contain this core work.

The final owner fails 15 assertions on Preview 90 production
(`lists121-complete-baseline.log`). An intermediate control demonstrates 66
failures from rewriting an untouched `__Other__` cell when placement changes
(`lists121-cell-source-baseline.log`); the cell signature repair passes the
owner. Final frozen-source full verification (`lists121-full-tests.log`) passes
**342 tests, zero failures, TEST SUCCEEDED**, exit 0. Exact hashes, change sizes
and limits are recorded in `lists121-verification.json`. This is development
evidence, with installed UI/clipboard/IME/VoiceOver acceptance still pending.
No iOS source/version is changed. The fully hideable folder sidebar remains.


## Inline-first list-card heads — lists122 (development, not packaged)

Native render/export now models empty item heads before cards that start on the
marker line. Empty head rows can share that first source line without losing
their native identities. Typing a body separates the head from its card; marker
changes rebase continuation indentation. Nested same-line markers, ordinary
quote prefixes, tab padding, tables and unclosed EOF code have editor-owner
coverage across LF/CRLF/CR. Indented code falls back to fences when a newly typed
head would otherwise absorb it. Existing edits close an unclosed fence, and
existing empty-head typing normalizes marker padding. Untouched source stays exact.

A new owner-prefix path initially dropped task syntax from paragraph heads. The
state/head-edit control fails nine assertions on that intermediate code and
passes after retaining task syntax on paragraph owners. Literal `[x]` text in
indented code remains code, with a paired negative control. The earlier
checklist-only row was too weak; the final owner asserts native checked display
and edits the head using an independent Undo history.

Final exact baseline against lists121 production fails 30 assertions across the
two owners (`lists122-complete-baseline.log`). Final frozen-source full
verification (`lists122-full-tests.log`) passes **343 tests, zero failures,
TEST SUCCEEDED**, exit 0. Hashes, earlier fixture corrections and remaining gaps
are recorded in `lists122-verification.json`.

**Normal workspace admission remains guarded.** Clipboard/code-creation-off
transport, Continue-after-card, sheets, structural ranges and uncommon
interleaved quote/list prefixes still require integration and verification.
These forced-rich editor tests do not establish installed or full parity
acceptance. Preview 90 remains the latest delivered DMG and contains neither
lists121 nor lists122. No version/build or iOS source is changed. The entire
folder sidebar remains hideable with its toolbar restore control available.


## List-card continuation and clipboard — lists123 (development, not packaged)

Continue at EOF now carries the item context into the next paragraph, including
quotes nested inside an item. Closing an unclosed fence retains card placement
and its separate Undo step. Reopening and changing the item's marker width also
re-indents the new paragraph. GFM's nil-range paragraph before an interrupting
table no longer prevents the later body paragraph from receiving its owner.

Fragment and semantic HTML clipboard export now include list-owned cards. A whole
item retains list membership; a card copied without its head becomes standalone
while retaining its surrounding quotes. Whole table grids use the same detach
rule. Code-creation-off conversion wraps literal prose in the original container
and retains an empty inline item with the existing empty-paragraph marker.
Task-looking code stays literal text. Copy/Cut and paste create no image assets
for these code/table cases.

The final two owners fail **183 assertions** against lists122 production
(`lists123-complete-baseline.log`). The earlier Continue baseline fails 132.
An intermediate run exposes the table-following-paragraph ownership gap, which
is repaired before final verification. Two early paste expectations are corrected
to include the existing trailing blank paragraph. Final focused verification
passes five owners/controls; frozen-source full verification
(`lists123-full-tests.log`) passes **345 tests, zero failures, TEST SUCCEEDED**,
exit 0. Exact hashes and coverage limits are in `lists123-verification.json`.

This remains forced-rich development evidence: **normal workspace admission is
unchanged**. Native sheets, broader selection paths, non-EOF boundary cases,
uncommon container-prefix layouts and installed clipboard/RTF/IME/VoiceOver
acceptance remain pending. No version/build or iOS source changes. Preview 90
remains the latest delivered DMG and does not contain lists121–123. The fully
hideable folder sidebar and restore control remain intact.


## Native list-card sheets and whole-item moves — lists124 (development)

Code/table sheets now save against an existing native list-card token, with the
same source snapshot and parent/body validation as Source saves. The editable
model comes from the unwrapped payload; its live placement is carried separately,
so indentation and quotes are not applied twice. No-op saves keep bytes and
selection. Stale or ownership-changing drafts are refused before mutation.
Unsupported table-cell markup retains its exact bytes by switching to Source,
and Undo restores the native model.

Whole-item indent/outdent, Backspace and full head removal retain their card
models. Table placement refresh derives cell blocks and alignment from the
immutable cell model, fixing the layout loss on transfer to a surviving parent.

The final owners fail **42 assertions** against lists123 production
(`lists124-complete-baseline.log`). The earlier sheet baseline fails 36; an
intermediate run exposes double wrapping and lost cell styles. Final focused
verification passes three owners/controls. The frozen-source full run
(`lists124-full-tests.log`) passes **346 tests, zero failures, TEST SUCCEEDED**,
exit 0. Coverage includes 72 Source/native sheet/ending cases and 24 whole-item
action/card/ending cases. Hashes and limits are in `lists124-verification.json`.

Normal workspace admission remains guarded. Cross-card selection/Cut, partial
card boundaries, remaining prefix/Continue interactions and rich open/reopen
acceptance still need work before packaging the feature. Installed UI/clipboard/
RTF/IME/VoiceOver and full parity acceptance remain pending. Preview 90 is still
the latest delivered DMG and does not contain lists121–124. No version/build or
iOS source changes. The entire folder sidebar remains hideable.


## Selections across native list cards — lists125 (development)

Body-to-body selections that fully enclose code/table cards now use the checked
list-selection transaction. Surviving cards follow the merged starting paragraph;
nested list-item heads retain their surviving-sibling rule. Inner quotes and
immutable table layout/alignment remain intact. Detached cards use their own
line endings for surrounding separators. Endpoints inside cards retain their
existing code/cell and whole-card paths.

The owner matrix adds nine shapes × two card kinds × three line endings ×
deletion/typing (108 cases), covering item/card ownership, exact saved source,
follow-up typing, selection and Undo/Redo. The existing Cut owner adds 12 successful
clipboard cases plus two refused cuts spanning a complete card. Refusals leave
writing, selection, clipboard and Undo untouched. The final owners fail 194
assertions on lists124 production (`lists125-final-baseline.log`).

Pinned headless Lexical/MDXEditor probes confirm the tested card transfer/removal
rules. The prose-absorption case deliberately emits a valid standalone card rather
than MDXEditor's malformed inline export. This establishes saved-file behavior,
not live DOM/clipboard parity. The first full run caught 24 regressions in the
existing whole-item Cut owner; restricting the new route to exterior endpoint
paragraphs fixes the leftover empty marker. The focused rerun passes 27 owners
and controls, including all 25 clipboard tests (`lists125-verified-owner.log`).

Normal rich admission remains guarded. Partial card endpoints, remaining
Continue/prefix interactions, workspace open/reopen and installed clipboard/RTF/
IME/VoiceOver acceptance still need work. Preview 90 is the latest delivered DMG
and does not contain lists121–125. No version/build or iOS source changes. The
folder sidebar remains fully hideable with its restore control.

The final frozen-source full suite (`lists125-final-full-tests.log`) passes
**347 tests, zero failures, TEST SUCCEEDED**, exit 0. `lists125-verification.json`
records source hashes, the failing baseline and intermediate whole-item regression,
final proof and scope limits. Both the frontend and private HTTPS `/app` preview
return HTTP 200. This remains development work, not a release or parity sign-off.


## Editable card-boundary selections — lists126 (development)

Typing, deletion and Cut can now cross from prose into part of a native code or
table card, or from a card into later prose. The unselected card suffix retains
its block. A starting card absorbs the ending prose into its code body or cell.
The existing checked list transaction removes selected wrappers and transfers
ownership, then restores the final models before publishing one Undo edit.
Partial grids retain every cell terminator and their alignment/layout. Code
absorbs image attachments as literal Markdown references; cells keep inline bold
and image semantics, and untouched cells retain their formatting.

Hosted marked-text tests exposed an additional input lifecycle failure. Card
composition now captures the original selection, keeps provisional input out of
autosave/Undo, and applies the final committed text as one checked edit. Clearing
the marked input restores the original note and selection. Load and detach clear
the pending snapshot. These are real AppKit API checks, not physical IME or
installed keyboard acceptance.

The final four owners fail 510 assertions against lists125 production
(`lists126-final-baseline.log`). The Preview 91 baseline, including standalone
marked-text cases, fails 522 assertions (`lists126-preview-final-baseline.log`).
Coverage includes 108 code boundary cases, 132 table cases, 12 partial-card Cut
transport cases and sixteen hosted commit/cancel cases beside existing controls. Scope and source hashes are recorded in
`lists126-review/` and `lists126-verification.json`.

Normal list-card rich admission remains guarded. Mixed code/table and two-table
endpoint checks, selected Return, multiline/structured paste, remaining Continue/
prefix interactions and workspace rich open/reopen still precede enabling it.
Installed clipboard/RTF/geometry/IME/VoiceOver and full parity acceptance remain
pending. Preview 91 includes this core work while exposing the supported root/
quote-card fixes. It advances only the native Mac version to 0.3.51/build 91;
there are no iOS changes. The folder sidebar remains fully hideable.


## Preview 91 — partial-card editing and composed input

Preview 91 packages the verified root/quote-card fixes above as **0.3.51 build 91**.
It retains the complete folder-sidebar hide/restore control. List-owned cards
continue to open in Source; their development core is included but not enabled
as a new normal rich-editor capability.

The frozen preview source/configuration passes **349 tests, zero failures,
TEST SUCCEEDED**, exit 0 (`lists126-preview-full-tests.log`). The final regression
owners fail 522 assertions on lists125 production. Both actual Debug app metadata
and the packaging verifier check 0.3.51/build 91. README features, supported
platforms, setup, commands, dependencies and limitations were reviewed before
packaging. This is an arm64 macOS 26+ ad-hoc test build, not notarized and not a
full-parity or installed-UI acceptance claim.

[Download Preview 91](https://mac-mini-m4-nox.ibex-oratrice.ts.net:8081/downloads/Zerus-Native-0.3.51-preview-91-arm64-local.dmg).
The matching artifact receipt and handoff record contain the final checksum and
private HTTPS byte verification. No commit, tag, production release, Windows
release or iOS build/upload is part of this test handoff.

Final delivery verification: `preview91-release.log` exits 0. The packager checks
the mounted app and nested CLI signatures, actual version/build, arm64 and macOS
26.0 minimum. The complete private HTTPS download returns HTTP 200 and matches
all **13,512,732 bytes** of the final DMG. SHA-256:
`09544af7feb90151193dc700e539111256b5d521c445191343d0b2dc5624f684`.
Receipts: `artifact-preview-91-local.json`, `lists126-verification.json` and
`preview91-handoff.json`. Both frontend and private HTTPS `/app` routes return
200. Installed UI/physical IME acceptance and full parity remain pending.


## Card Return and multiline paste — lists127 (development)

Selected Return now reaches the native text-view command before AppKit narrows
an edit beginning inside a table. It keeps the full selected range, applies the
checked card/list transaction and commits one Undo event. Code and cell newlines
retain their receiving role. Incoming prose splits its item while the surviving
card follows the new paragraph/item.

Plain, native-fragment and HTML inline multiline pastes now use the same checked
card path, including leading, trailing, consecutive and break-only input. First-
character replacement retains a quote's role, and cell caret offsets account for
CRLF normalization. Reopening cannot merge an adjacent table into a prose render
group. When deleting a wrapper joins two pipe tables, a real separator preserves
both models and their cells instead of treating the second delimiter as data.

The final three owners fail **1,195 assertions** on Preview 91 production
(`lists127-final-baseline.log`). Repaired focused owners pass. Coverage includes
24 hosted Return cases, 252 multiline paste cases and 36 mixed-card cases beside
the existing in-cell/body controls. The independent parser checks saved models,
parentage, text/formatting, caret and Undo/Redo; the paste owner checks reopening
and unchanged assets. Source hashes and scope are in `lists127-review/` and
`lists127-verification.json`.

This development work is not in Preview 91. No version/build or iOS changes.
Normal list-card rich admission remains guarded while structured/block/resource
paste across partial endpoints, remaining Continue/prefix cases and workspace
open/reopen are completed. Installed clipboard/RTF/IME/VoiceOver and full parity
acceptance remain pending. The folder sidebar stays fully hideable.

Final lists127 verification: `lists127-full-tests.log` completes with **351 tests,
zero failures, TEST SUCCEEDED**, exit 0. The four frozen source/test hashes still
match, whitespace checks pass, and both web preview routes return HTTP 200.
`lists127-verification.json` records the exact evidence and remaining boundaries.
Preview 91 is the latest delivered build; this development change is not packaged.


## Portable image literals in code paste — lists128 (development)

HTML and native-fragment image paste into a code card now expands the image's
portable markup before converting attributed text to code. Previously the image
file was imported but its reference became an invisible attachment glyph. The
same conversion is shared with partial-card selection replacement. Code strips
only its editor placeholders/separators and retains the image caption and path
as literal text.

The editor-boundary regression covers HTML/native fragments at a code caret and
across an outgoing partial-code selection. It checks an independent parsed code
body, one imported asset with the original bytes and a surviving reference,
Undo/Redo selection, and follow-up typing. The unchanged production baseline
fails 12 assertions in one test (`lists128-resource-baseline.log`, exit 65).
All 27 clipboard owners pass (`lists128-clipboard-tests.log`, exit 0).

This is not packaged; Preview 91 remains the latest delivered DMG. No iOS or
version/build changes. Structured/block paste across partial endpoints, remaining
Continue/prefix cases, list-card admission and workspace open/reopen remain
pending, as do installed clipboard/IME/VoiceOver and full parity acceptance.
The entire folder sidebar remains hideable.

Final lists128 verification: **352 tests, zero failures, TEST SUCCEEDED**,
exit 0 (`lists128-full-tests.log`). Frozen source hashes match; changed lines
have no trailing whitespace. Both web preview routes return HTTP 200.
`lists128-verification.json` records the evidence. This change is not packaged.


## Structured paste entering partial cards — lists129 (development)

A heading payload crossing from quoted prose into a partially selected code or
table card now uses the checked block transaction. The quote-inline rule only
applies within one receiving paragraph. Previously the cross-paragraph case
fell through to generic insertion: the source contents were correct, but the
caret landed after the final pasted paragraph's terminator. Subsequent typing
therefore edited the retained card rather than the pasted paragraph.

A new editor-boundary owner covers 96 combinations of code/table endpoints,
paragraph/heading/code/table payloads, native fragment/HTML, three line endings
and root/quote containers. It checks independently parsed contents and block
kinds, the caret, Undo/Redo selections and follow-up typing. The expanded old-
source run fails 36 assertions (`lists129-expanded-owner.log`, exit 65); the
repaired clipboard suite passes 28 tests (`lists129-clipboard-tests.log`, exit 0).

Reopen checks compare body rows and independently parsed block/cell contents.
They do not establish exact blank-row or pixel-spacing fidelity: quote-card
source ranges can absorb structural blank rows into card paragraph margins.
An initial strict text-view comparison exposed that distinction; native/source
spacing reconciliation remains open and is not claimed fixed by the caret repair.

This is development work after Preview 91, not packaged. No iOS, version/build or
admission changes. Remaining work includes structured paste starting inside a
card, uncommon Continue/prefix cases, normal list-card admission and workspace
open/reopen, spacing reconciliation, and installed clipboard/IME/VoiceOver/full
parity acceptance. The entire folder sidebar stays hideable.

Final lists129 verification: **353 tests, zero failures, TEST SUCCEEDED**,
process exit 0 (`lists129-full-tests.log`). Frozen hashes match; changed lines
have no trailing whitespace. Production +2/−3 lines; test owner +51 lines. Both
web preview routes return HTTP 200. `lists129-verification.json` records the
exact scope and remaining boundaries. No packaging; Preview 91 remains latest.


## Structured paste leaving partial cards — lists130 (acceptance core)

The outgoing structured-paste boundary is now exercised through the real paste
entry point: 96 root/quote code/table cases cover paragraph, heading, code and
table payloads, HTML/native fragments, and LF/CRLF/CR. Receiving code and cells
retain all pasted body text, the unselected suffix and surviving cells. The
caret stays before the suffix, including after Undo/Redo and follow-up typing.

No production repair was needed. The initial diagnostic's 24 failures came from
an oracle that skipped inline-code text inside table cells; the corrected reader
handles Text and InlineCode nodes. This is acceptance coverage, not a claimed
pre-fix regression. `lists130-clipboard-tests.log` ends with **29 tests, zero
failures, TEST SUCCEEDED**, exit 0. Production is byte-identical to the 353-test
full-pass lists129 source. That full run predates this additional test; no new
full-suite count is claimed. Frozen files and scope are in `lists130-review/`
and `lists130-verification.json`.

No version/build, iOS, admission or package changes. Preview 91 remains latest.
Parser-owned admission and workspace open/reopen for list cards, uncommon
Continue/prefix interactions, native/source separator spacing reconciliation,
and installed clipboard/IME/VoiceOver/full parity acceptance remain pending.
The folder sidebar remains fully hideable.


## Original-tree list-card admission — lists131 / Preview 92

Supported list-owned fenced/indented code and tables now open in rich mode from
the workspace, rather than requiring Source mode. The original Markdown tree is
checked before any card source is removed. Admission verifies item parents, each
card's owner and kind, native context identities, unchanged source bytes, and
code/table model contents. Inline-first, nested, compact/tabbed and quoted card
shapes pass; unsupported item headings/prose quotes, deeper quote/list structures,
HTML, references or unresolved mappings retain editable Source. Root/quote cards
without list ownership keep their existing path.

The extended workspace owner checks 29 fixtures across LF/CRLF/CR: **87 actual
open/save/reopen cases**, preserving exact note bytes and the selected editing
mode. Two final owner tests fail **91 assertions** against the old source
(`lists131-final-baseline.log`, exit 65). Repaired owner runs pass. The final
Preview 92 source/configuration completes **354 tests, zero failures, TEST
SUCCEEDED**, exit 0 (`lists131-preview92-full-tests.log`). Frozen hashes match
and changed-line whitespace checks pass. Existing native document and clipboard
owners cover card edits, sheets, ownership changes, Return, Cut, paste and hosted
composition. No test-only production seam was added.

The new proof performs render/serialize validation for list-card documents.
Large-note/open and installed typing performance remain acceptance work. This
does not establish full Markdown grammar coverage or complete desktop parity.
Native/source separator spacing, uncommon prefix/selection/Continue cases, and
installed clipboard/IME/VoiceOver/live-provider acceptance remain pending.

Preview 92 uses **0.3.52/build 92**, Apple Silicon and macOS 26+, separate from
production Zerus. It includes development repairs since Preview 91: checked
card-boundary Return/multiline paste, portable code image literals, structured
paste caret preservation and outgoing structured-paste acceptance. The local
DMG is ad-hoc signed and is not notarized. Packaging verifies its mounted app
and nested CLI, identity/version/build/minimum OS/architecture and signatures;
final artifact checksums and download verification are in the matching receipt
and handoff. Installed app launch/UI acceptance is not claimed. No iOS, updater,
commit, tag or production release changes. The folder sidebar stays hideable.


## Continue before following items/cards — lists132 (development)

Continue below code or a table now creates a prose destination before a following
card, list head or nonempty paragraph belonging to a different item. Previously
the caret could land inside that following structure and edit it instead. The
new paragraph keeps the current card's owner, quote suffix and line ending.
Existing prose in the same container and EOF keep their prior route. Command
Undo is separate from subsequent typing.

The same owner exposed a root-table/fenced-code byte change on Undo: export
always added a blank separator even though the fence interrupts the table. That
one boundary now retains its original spacing; other root separator rules remain.
Continue also declines during marked-text composition, preserving AppKit's marked
range, selection and provisional text until normal committed accent input.

The new owner checks **72 non-EOF cases** plus **four hosted composition controls**.
Independent parser checks cover item parents, prose/card ownership, card bodies,
cells, siblings and quote containers; native checks cover caret role and
Undo/Redo selections. The corrected non-EOF baseline fails **147 assertions**
(`lists132-reviewed-baseline.log`); the focused pre-composition-guard baseline
fails **four assertions** (`lists132-marked-baseline.log`), both exit 65. The
three repaired Continue owners pass (`lists132-marked-owner.log`, exit 0).
The first full suite passes 355 tests before the composition guard; the final
guarded-source run is recorded separately.

This is not in Preview 92. No version/build or iOS change and no new package.
Exact native/source spacing across all card boundaries, uncommon prefix/range
behavior, installed physical keyboard/IME/VoiceOver/provider checks and complete
desktop parity remain pending. The folder sidebar remains fully hideable.

Final lists132 verification: **355 tests, zero failures, TEST SUCCEEDED**,
process exit 0 (`lists132-final-full-tests.log`), on the final guarded source.
Frozen hashes match and changed-line whitespace checks pass. Production +40/−17
lines; the new command owner adds 68 lines. `lists132-verification.json` records
the baseline, marked-input, focused and full evidence with their exact scopes.
No packaging or version change; Preview 92 remains latest and lacks this repair.


## Structured-paste row and layout fidelity — lists133 (development)

The 96-case structured-paste matrix now retains its native blank rows and card/
following-paragraph vertical positions after reopening. The earlier lists129
explanation that the difference could be equivalent quote-card margin spacing
was incomplete: same-configuration TextKit measurements demonstrate a real jump.
Bare-CR cases were roughly one blank row taller after paste; block payloads also
had a smaller font-height mismatch.

A generated blank after a pasted block now has the normal receiving body font.
Previously it had no font, so AppKit used its default rather than the font used
on reopen. A generated separator before a card now reads the card's source
newline when character-level metadata is absent. The old LF fallback could
combine with a preceding bare CR into one CRLF and eliminate a blank line. The
existing clipboard newline reader moves unchanged to the shared Mac Markdown
owner for these callers; no card-parser rewrite or row deletion is involved.

The existing owner now compares all normalized native rows instead of filtering
blank rows, plus actual TextKit glyph positions for the surviving card and
following paragraph. AST data/ownership, caret, Undo/Redo and typing checks remain.
The final original-source baseline fails **192 assertions**: 160 layout and 32
row mismatches (`lists133-final-baseline.log`, exit 65). The repaired layout owner
passes (`lists133-layout-owner-fixed.log`, exit 0). Final full verification is
recorded separately. Frozen files and scope are in `lists133-review/`.

This is development work after Preview 92, with no version/build, iOS or package
change. It proves this supported paste matrix, not every container/zoom/selection
layout or installed interaction. Broader grammar/range/layout, large-vault and
installed keyboard/IME/VoiceOver/provider/full parity acceptance remain pending.
The folder sidebar remains fully hideable.

Final lists133 verification: **355 tests, zero failures, TEST SUCCEEDED**,
process exit 0 (`lists133-full-tests.log`). The final full run includes exact
normalized native rows as well as geometry in all 96 paste cases. Frozen hashes
match; changed-line whitespace checks pass. Production +11/−11 lines including
the unchanged helper move; the existing owner changes +17/−6 lines.
`lists133-verification.json` records the scope and remaining work. No packaging;
Preview 92 remains latest and does not contain this repair or lists132.


## Large-note validation cost — perf134 (development)

Release-host measurements now cover styled notes with 500, 4,000 and 20,000
paragraphs, with and without one list-owned code card. The temporary diagnostic
uses the actual editor, checks exact source before/after input, and records
three-run medians for admission, export and a single-character edit. It has been
removed from the normal test file; a frozen copy and raw logs remain in artifacts.
No timing gate, production benchmark flag or permanent test was added.

Source fingerprints now encode all portable fields losslessly in binary/Base64
instead of formatting and concatenating strings for every run. Every field is
still checked, with image canonicalization and semantic run coalescing retained.
Attribute keys are prebridged locally to each render/export; public CF/NSDictionary
reads avoid repeated Swift dictionary/key conversions. There is no shared mutable
cache or trusted-token shortcut, and no vault-format migration.

For the 20,000-paragraph/card case, median export changes from approximately
1,171 to 778 ms and input from 1,370 to 984 ms. Admission still takes about
4,703 ms. Plain 20,000-paragraph input still takes about 1,273 ms. These local
Release-host results improve overhead; they do **not** establish acceptable
large-note responsiveness or installed typing/IME performance. Whole-document
export remains linear. Incremental local-edit export and admission cost remain
active work, along with large-vault and complete desktop parity acceptance.

All Release probes pass their exact-source assertions and retain the same output
checksum. The restored normal test file is byte-identical to its baseline. The
final full suite passes **355 tests, zero failures, TEST SUCCEEDED**, exit 0
(`perf134-full-tests.log`). Frozen hashes match; data, profiling, scope and the
comparison chart are in `perf134-review/`, `perf134-measurements.json`,
`perf134-verification.json` and `perf134-comparison.html`. No version/build, iOS or
package change. Preview 92 remains latest; this development work is not included.

## Local body export reuse — perf135 / Preview 93

The coordinator now retains the output of a completed full export plus native
and source UTF-16 ranges for candidate root paragraphs. Actual NSTextStorage
changes mark the edited row and shift later ranges. A subsequent nonempty,
single-row root body edit re-exports that paragraph with the existing serializer
and splices its result into the completed output. Eligibility is checked when
the row is edited, keeping initial map construction inexpensive. Imported source
tokens are never trusted merely because their attributes still exist.

The row must have a stable blank boundary after it or end the document. Lists,
headings, quotes, cards, attachments/literals, logical breaks, emptied rows,
imported structural indentation and cross-row edits retain full export. Loading,
whole-document replacement and marked text invalidate the cache. Formatting and
Undo/Redo rebuild or revalidate through the actual storage changes. Palette-only
restyling and code highlighting do not invalidate unrelated portable output.
If empty-head protection inserts source boundaries, its result drops the map.

Matched Release-host probes use styled notes, three-run medians, exact output
checks after the first, repeated and other-paragraph edits, and a final full-export
comparison. All checks pass on both pre-cache and current implementations; the
output checksums match. The temporary diagnostic is removed from the normal
suite and retained under `perf135-review/`.

| Paragraphs | List code card | First edit before / after, ms | Repeated edit before / after, ms | Other paragraph before / after, ms |
| --- | --- | --- | --- | --- |
| 500 | No | 29.3 / 32.0 | 25.0 / 5.7 | 25.1 / 5.7 |
| 500 | Yes | 25.7 / 28.0 | 25.1 / 5.8 | 25.2 / 5.9 |
| 4,000 | No | 251.9 / 272.3 | 199.2 / 43.0 | 195.9 / 42.5 |
| 4,000 | Yes | 206.2 / 219.8 | 198.6 / 42.9 | 198.1 / 43.4 |
| 20,000 | No | 1285.6 / 1387.0 | 984.7 / 209.0 | 993.8 / 211.5 |
| 20,000 | Yes | 990.1 / 1093.2 | 990.5 / 211.1 | 986.5 / 212.7 |

These measurements do not establish acceptable large-note or installed input
latency. The first edit still builds the whole export and map, with roughly
7–10% additional cost in these samples. Local edits still copy the complete
Markdown result and shift later ranges. Cold input, admission, broader row
coverage and further input-path costs remain active work. There is no timing
XCTest, production benchmark flag, schema change or shared cache.

The new editor-owner check covers successive edits to different paragraphs,
UTF-16 length changes, earlier formatting surviving later edits, Undo/Redo,
batched direct text-storage mutations and loading another note, for LF/CRLF/CR.
It is an equivalence guard for the cache's new invalidation risk; the pre-cache
implementation also passes it. Raw measurements and frozen sources are in
`perf135-measurements.json` and `perf135-review/`. Final suite and packaging
status are recorded in `perf135-verification.json` and `preview93-handoff.json`.

The final versioned Preview 93 sources pass **356 tests, zero failures,
TEST SUCCEEDED**, terminal exit 0 (`perf135-preview93-full-tests.log`). Frozen
source/config hashes match. The new owner check passes in the baseline and
candidate Release runs as well. Preview 93 packages this work together with
lists132/133 and perf134; no iOS or production desktop version is changed.
Installed UI, physical IME/VoiceOver, full parity and broader performance
acceptance remain pending.

## Card-restyling input cost — perf136 (development after Preview 93)

The next Release profile samples warmed, nonempty root-paragraph input in the
actual hosted editor. In the 20,000-paragraph/no-card case, the main-thread sample
is dominated by `MacRichCode.style` calling `MacListCardPlacement.restyle`, which
used to bridge every complete attribute dictionary before checking whether the
run had card metadata. Whole-document snapshots were not the measured bottleneck.

Restyling now enumerates the single `macListCard` attribute first, then runs the
unchanged detailed-attribute pass only inside actual card spans. A complete
attribute run cannot cross a change in that attribute, so the old inner guard,
run-specific indentation, table-cell base style, quote suffix and code inset
retain their previous behavior. There is no skipped card-layout rule, cached
presence flag, new state or change to export/source validation.

The comparison reruns the baseline without sampling, then runs the candidate
with the same temporary diagnostic. Both pass exact expected Markdown after all
inputs plus a fresh full-export comparison. These are synchronous hosted-editor
input medians with an already warm root-paragraph export cache, excluding initial
render/admission, display-frame latency and debounced disk saves:

| Paragraphs | List code card | Baseline / candidate median input, ms | Samples |
| --- | --- | --- | --- |
| 500 | No | 5.85 / 0.55 | 9 |
| 500 | Yes | 5.79 / 0.70 | 9 |
| 4,000 | No | 43.11 / 2.12 | 9 |
| 4,000 | Yes | 43.85 / 2.48 | 9 |
| 20,000 | No | 212.04 / 9.49 | 100 |
| 20,000 | Yes | 213.23 / 10.55 | 100 |

The normal test file is restored byte-for-byte; there is no permanent timing test
or production test seam. Existing card/editor owners cover mixed inline runs,
indentation, code/table geometry, paste/reopen, zoom, caret, Undo/Redo and source
fidelity. Measurements, the owned-host sample, frozen sources and comparison
chart are in `perf136-measurements.json`, `perf136-warm-baseline-sample.txt`,
`perf136-review/` and `perf136-comparison.html`. Final full-suite status is recorded
in `perf136-verification.json`. This development change is **not in Preview 93**.
Cold input/export/admission, broader incremental-row coverage, installed physical
IME/VoiceOver and full desktop parity remain unfinished. No iOS, version or
packaging change is made for this milestone.

The final restored suite passes **356 tests, zero failures, TEST SUCCEEDED**,
terminal exit 0 (`perf136-full-tests.log`), with frozen hashes matching. The normal
MacDocumentTests, MacMarkdown and MacRichCode files match their pre-probe baselines.
The shipping-code diff is confined to MacListCards restyling (+15/−10 lines,
including indentation of the unchanged body); normal tests add/remove zero lines.

## List-card admission export reuse — perf137 (development after Preview 93)

A current-source tracker check confirmed that both web and native grouping
pickers exclude list definitions marked as multi-value. Raw web board grouping
also handles array-valued note data; parity for such stored values under another
definition remains a separate check, not a completed migration claim. Native
column-sizing polish likewise remains acceptance work.

A demonstrable cold-admission duplication was addressed. List-card admission
rendered a note, exported it to prove exact source preservation, then exported the
same unchanged render again inside native item ownership mapping. It now passes
the completed serialization to a private helper. Ordinary item-mapping callers
retain their previous row-scan/export order; empty-item recovery exports its
newly normalized document. This reuses work within one synchronous call, without
a cross-document cache, state flag or trusted-token shortcut.

Exact UTF-8 source comparison, native head/source-line matching, original item
parents, card owners and code/table model comparisons remain in place. This does
not reuse admission's rendered value in the displayed editor or remove all
parsing. It is not complete cold-load or installed responsiveness acceptance.

Matched Release probes take three admission samples per styled fixture:

| Paragraphs | List code card | Baseline / candidate median admission, ms |
| --- | --- | --- |
| 500 | No | 26.46 / 26.96 |
| 500 | Yes | 121.34 / 100.49 |
| 4,000 | No | 206.86 / 208.72 |
| 4,000 | Yes | 946.03 / 795.79 |
| 20,000 | No | 1036.21 / 1054.59 |
| 20,000 | Yes | 4707.82 / 4003.98 |

All fixtures remain rich-admitted. The normal test file is restored unchanged;
there is no permanent timing XCTest or test-only production seam. Existing
workspace admission owners cover actual note open/save/reopen, exact bytes,
original-tree ownership and unsupported Source controls. Data, frozen sources,
review and the comparison chart are in `perf137-measurements.json`,
`perf137-review/` and `perf137-comparison.html`; final suite status is recorded in
`perf137-verification.json`. No iOS, version or packaging change. This work and
perf136 are not in the delivered Preview 93. Cold UI loading, broader parity and
installed/provider/physical IME acceptance remain open.

The final restored normal suite passes **356 tests, zero failures,
TEST SUCCEEDED**, terminal exit 0 (`perf137-full-tests.log`), with frozen hashes
matching. The production diff is one file (+9/−3 lines); normal tests add/remove
zero lines. The stored-array board case remains a traced discrepancy to reproduce
at the collection owner before changing its behavior.


## Stored-array Kanban groups and guarded Undo — board138 / Preview 94

The current web picker, like the Mac picker, excludes definitions marked as
multi-value lists. Existing Markdown can still contain arrays under another
definition. Web board grouping iterates those stored values; native grouping
previously joined their display text, combining `[Draft, Review]` with the literal
scalar `"Draft, Review"` and inventing a `"Draft, Draft"` column for duplicates.
The same joined comparison also rejected a real move as a no-op.

Native board inventory and rendering now share one grouped model, with a card
once per distinct nonempty stored value. Scalars retain their entire label.
Configured/discovered columns and saved ordering remain, and empty arrays retain
the existing native No value behavior. A no-op compares the complete set of
stored labels with the one target label; new writes still use typed validation.
Displaying the board does not rewrite incoming values.

The owner regression exposed an existing Undo limitation: a single-value picker
could overwrite a preexisting array or observed out-of-option value but could
not restore it. New bulk receipts now retain a semantic fingerprint of the
relevant property definition. Undo of Set/Clear can restore its exact prior
non-relation value only under that unchanged definition; normal new selections
and Redo still validate. Hidden/unsupported definitions, changed definitions,
legacy receipts without provenance and malformed numeric spellings keep their
refusal guards. Paired relations retain their existing restoration rules.
Unrelated definitions can change without blocking the prior value restoration.
This is additive receipt metadata; older clients may conservatively refuse the
old invalid value instead of restoring it.

The owner test uses actual vault files, a single-value definition, duplicate
arrays, a literal comma option, an empty array, a discovered value and a scalar
control. It checks the shared rendering cohorts, board scope, unchanged incoming
bytes, typed moves, comment/body preservation, Undo/Redo, unrelated-definition
survival, legacy/malformed-receipt refusal, changed-definition refusal and reopen.
Undo retains previous values; property spelling may be canonicalized by the
existing value-based history engine. An owned offscreen SwiftUI fixture verifies
actual column placement; it is not installed pointer-routing acceptance.

Baseline evidence is in `board138-baseline.log` (6 functional failures after a
behavior-preserving grouping extraction), `board138-undo-baseline.log` (7 Undo
failures), and `board138-observed-value-baseline.log` (4 failures on the initially
narrow restoration). The initial compile log is not regression proof. The shared
restoration, board-scope, typed-move and relation-batch focused checks pass; final
full-suite, iOS compile and packaging status are in `board138-verification.json`
and `preview94-handoff.json`. No permanent diagnostic capture code is retained.

The shared engine change is compiled for iOS; simulator visual verification is
pending because the earlier Device-panel session was canceled and was not
reopened. Its app version/build remains 0.3.107/57. Preview 94 packages board138,
perf136 and perf137. Full desktop parity, installed clipboard/IME/VoiceOver,
provider workflows and the remaining tracker acceptance remain in progress.

The final versioned Preview 94 Mac suite passes **357 tests, zero failures,
TEST SUCCEEDED**, terminal exit 0 (`board138-preview94-full-tests.log`). Frozen
source/config hashes match. Final shared-source iOS Simulator compilation passes
**TEST BUILD SUCCEEDED**, terminal exit 0 (`board138-ios-final-compile.log`);
its canceled Device-panel preview remains pending as described above. Packaging
and full download checks are recorded in `preview94-handoff.json`.


## Selected Calendar properties — calendar139 / Preview 95

The web Calendar and native Undated cards display selected property summaries.
Native dated cards and the day list previously showed only titles. Both now reuse
the same selected-field renderer, including date/relation display and full-value
tooltips. Compact dated summaries use one line per field; Undated and day-list
summaries retain two. Month weeks grow to accommodate the two displayed cards
without clipping metadata, with the existing day list providing all dated notes.
Changing Properties updates both dated and Undated cards without editing notes.

The primary owner test hosts the actual native Calendar in an owned offscreen
window and recognizes its rendered pixels with Vision. It verifies both dated
cards, their selected summaries, the Undated positive control, hiding summaries
and unchanged note bytes. The pre-fix run fails on the four missing dated Owner
and Score labels; the focused collection run passes. Its rendered fixture shows
the expanded week and all six dated field rows. This is render evidence, not
installed Calendar pointer, keyboard or VoiceOver acceptance. No external AX
session or installed-app computer control was used. The day-list reuse is traced
in code; opening that sheet remains an installed interaction check.

Final full-suite and packaging results are recorded in
`calendar139-verification.json` and `preview95-handoff.json`. This Mac-only change
does not alter shared Apple services or the iOS app. The folder sidebar remains
fully hideable with a restore control. Full parity, installed input/IME,
VoiceOver, live providers and the remaining tracker acceptance stay open.

The final versioned Preview 95 suite passes **358 tests, zero failures,
TEST SUCCEEDED**, terminal exit 0 (`calendar139-preview95-full-tests.log`).
Frozen source/config hashes match. The packaging receipt and full downloaded
artifact check are recorded in `preview95-handoff.json`.


## Collection modifier selection — selection140 / Preview 96

Native collection buttons previously ignored modifiers and opened notes unless
explicit Select mode was enabled. They now share one workspace activation path:
Command-click toggles a note; Shift-click adds the inclusive range from the last
non-range click, retaining that anchor for repeated ranges. Explicit Select still
toggles on ordinary clicks. Modifier selection displays the bulk bar without
entering explicit Select mode, so a following ordinary click opens the note and
clears the bulk state. All and Clear share the selection owner; Clear also exits
Select. Selected rows/cards expose the selected accessibility trait.

Gallery groups and Kanban columns pass their own displayed order, matching the
web group-local range behavior. Calendar passes chronological notes in the shown
month (including notes reachable through the day list), followed by Undated.
Collection-wide List/Table use the current filtered order. New selections clamp
stale rendered paths to current membership; query, filter, subtype and collection
changes clear selection and its anchor. UI tasks capture the vault activation
before scheduling so a click queued before a vault switch cannot run in the new activation.

The real-workspace owner test covers additive/reverse ranges, a group-local
anchor fallback, explicit Select, plain opening, hidden-row refusal, query/filter/
subtype resets, All, Clear, collection resets and unchanged note bytes. The
existing Calendar render owner also posts actual AppKit mouse events to its own
offscreen window, proving Command/Shift flags reach the SwiftUI button and select
without opening a note. This is a distinct event-transport boundary, not a second
copy of the selection algorithm. The final two tests fail with 15 assertions on
the behavior-preserving pre-fix activation extraction, and pass with the repair.
The earlier broad one-letter filter fixture was corrected to a unique title;
its failed check is not evidence against the membership guard.

No installed-app automation, external AX session, shared Apple source, iOS app
or real vault was used. Installed pointer/keyboard/VoiceOver acceptance and
collection Command-A/Escape scope remain open. Native Control-click retains the
standard context-menu gesture; the selection modifier is Command. Full desktop
parity remains in progress. Final suite and DMG verification are recorded in
`selection140-verification.json` and `preview96-handoff.json`.

The final versioned Preview 96 suite passes **359 tests, zero failures,
TEST SUCCEEDED**, terminal exit 0 (`selection140-preview96-full-tests.log`).
Its source/config hashes match the frozen files. Packaging and complete download
checks are recorded in `preview96-handoff.json`.


## Collection keyboard scope — keyboard141 / Preview 97

List and alternate collection content now use a shared local AppKit responder.
Pointer activation and entering Select mode request collection focus.
Background selection-membership changes leave the current text focus alone. Its standard Select All action and Command-A key equivalent select the
current filtered collection through the existing owner; Escape clears selection
and exits Select mode. Search fields and editors sit outside the collection
content. Once another control becomes first responder, collection key equivalents
are ignored. The responder never activates an application or makes a window key,
and uses no global/local event monitor. Disabled content and attached sheets
block deferred focus requests; vault activation guards reject old requests.

The existing Calendar render/input owner now sends actual window key equivalents
and events, invokes Select All on the window's real first responder, and checks
Command-A, Escape, text-field Select All, text-field Escape isolation and Select
mode returning focus from the field. The exact pre-fix extraction fails with
**8 assertions, zero unexpected failures** (`keyboard141-exact-baseline.log`).
A second regression reproduced focus theft when selection membership changed
while the field was active (two failures in
`keyboard141-verified-focus-baseline.log`). The repair removes automatic focus
requests from membership updates while keeping pointer and Select-mode requests.
The text-field control and unchanged-note checks use real Cocoa text editing and
vault files, not a substitute selection model. No production test seam is added.

An offscreen fixture cannot become the system key window. Posting Command-A via
NSApplication consequently exercised a different menu target; it was replaced
with the owned window's real key-equivalent/first-responder dispatch. This proves
the window-level contract, not installed application-menu/key-window routing.
Those installed checks, full keyboard traversal, VoiceOver and physical IME remain
pending. The earlier SwiftUI-only implementation did not receive Command-A; the
final code uses the standard AppKit responder path. Diagnostic prints and app
activation attempts are removed. No installed-app automation or external AX was
used. No shared Apple or iOS code changes are included.

Final suite, source hashes and DMG verification are recorded in
`keyboard141-verification.json` and `preview97-handoff.json`. The folders sidebar
remains entirely hideable with its restore control. Full feature parity remains
in progress; this build does not establish installed acceptance.

The final versioned Preview 97 suite passes **359 tests, zero failures,
TEST SUCCEEDED**, terminal exit 0 (`keyboard141-final-preview97-full-tests.log`).
It includes the membership-focus regression control and matches the frozen
source/config hashes. The earlier full pass predates that refinement. Final DMG
and complete-download evidence are in `preview97-handoff.json`.


## Collection alternate opening — navigation142 / Preview 98

The existing Mac middle/triple-click handler was already mounted on List,
Gallery and Kanban notes, but absent from Table titles, dated Calendar entries
and the Calendar day list. Those buttons now use the same handler. A shared
alternate-collection callback captures the vault activation before scheduling
openNote, and reuses the existing tab lifecycle. Opening from the day list also
closes that sheet. Ordinary clicks keep modifier/range selection and typing focus.
The overlay remains hidden from accessibility; note buttons keep their labels
and selected traits.

The existing real Calendar/window input owner adds middle-click on a dated note
and middle/triple-click on Table titles in Select mode. It verifies the selected
note, absence of accidental bulk selection, one tab per path and exact original
note bytes. The validated baseline has six functional failures
(`navigation142-verified-baseline.log`); the repaired collection suite passes
five tests. The first fixture used a Cocoa factory event that reported button 0;
that run is not middle-click evidence. The corrected fixture sets button 2 in the
public CGEvent metadata, rebuilds the NSEvent and asserts that it still targets
the owned window. Rendered Table labels are located with their checkbox prefix.

The day-list handler is traced through shared code; its installed pointer route
remains an acceptance check. These are owned offscreen AppKit events, not real
hardware or installed-app acceptance. No external AX or installed application was
driven, and no shared Apple/iOS source changed. A separate formatting-routing
inspection found that the existing action owner already requires its editor to
be first responder, so this milestone makes no formatting change.

Final source hashes, full-suite and DMG/download checks are recorded in
`navigation142-verification.json` and `preview98-handoff.json`. The folders sidebar
remains fully hideable with its restore control. Full desktop parity, installed
input/key-window/VoiceOver/IME and remaining tracker acceptance remain open.

The final versioned Preview 98 suite passes **359 tests, zero failures,
TEST SUCCEEDED**, terminal exit 0 (`navigation142-preview98-full-tests.log`).
Frozen source/config hashes match. Packaging, mounted-guide/signature validation
and the complete HTTPS download are recorded in `preview98-handoff.json`.


## Complete warm vault startup — startup143 / Preview 99

The Mac previously awaited a coordinated full inventory before showing its vault.
It now retains a complete device-local snapshot, bound to the resolved directory's
volume, device/inode and creation identity. Recovery runs before cache activation.
Cached notes retain their full exact UTF-8 bodies; schema/views/tasks use their
normal decoders. The private binary-plist cache is disposable, validates counts,
paths, bytes and root identity, and falls back to the ordinary scan if unusable.
No vault-local cache file or partial editor content is introduced.

A separate file actor performs the authoritative scan. It waits around local
mutations and reruns if a newer local snapshot supersedes its result. Successful
startup saves are reread from disk before publication, including notes left since
the save. Clean untouched cached notes adopt new disk bytes or disappear when
deleted. Drafts and provisional composed input retain the old byte baseline and
use the existing outside-change/recovery path. The view reports cached status,
background progress and errors, with Retry. Opening an already active workspace
no longer reopens its vault when that view appears.

Successful filter/layout/task writes also update the snapshot. A new activation
waits for already queued cache writes in live windows of the same vault. Explicit
refresh awaits startup reconciliation before its fresh inventory; it no longer
returns early while the old cache is still displayed. The first full suite caught
stale filter/layout/task reopen values and the asynchronous refresh contract;
those existing owner tests remain the proof. A board test that externally edits
schema explicitly awaits refresh before asserting the authoritative columns.

Three owner tests exercise actual temporary vaults: coordinated reads held after
note bodies are scanned while an early save completes; failed inventories,
retry, deletion, corrupt cache rebuilding and directory replacement; and real
NSTextView marked input hosted in the actual workspace view. The latter verifies
composition survives refresh, outside bytes remain unchanged on a refused save,
and committed text reaches private recovery. These are offscreen AppKit fixtures,
not physical IME or installed-app acceptance. Removing the two protections causes
eight expected failures across the save and composition tests
(`startup143-protection-baseline.log`, exit 65). Restoring them passes all three
focused lifecycle tests (`startup143-expanded-tests.log`).

Full-suite, source hashes, mounted artifact and full-download evidence are recorded
in `startup143-verification.json` and `preview99-handoff.json`. No shared Apple/iOS
source changes are required. The folders sidebar remains fully hideable with its
restore control. Full desktop parity remains active work.

Known limits: the cache does not provide partial-body startup for vaults beyond
its budget, and the full snapshot encoding/read cost is not incremental. Provider
reads may remain blocked until the operating system returns even after request
cancellation; generation/request checks prevent stale publication. Large-vault,
cloud-provider, multiwindow and installed keyboard/physical IME acceptance remain
pending, together with the remaining parity tracker.

The final versioned Preview 99 suite passes **362 tests, zero failures,
TEST SUCCEEDED**, terminal exit 0 (`startup143-preview99-final-full-tests.log`).
It includes the repaired saved-metadata and explicit-refresh contracts. The
focused final workspace/lifecycle run passes 47 tests. Frozen source/config
hashes match; artifact and full-download verification are recorded in
`preview99-handoff.json`.


## Progressive regular note lists — collection144 / Preview 100

The native list already used LazyVStack, but supplied every filtered note to its
row inventory at once. The React note list starts with 40 results and extends
using a viewport sentinel. The native regular note list now follows that contract:
it starts with 40, appends 40 when its trailing action appears, and also exposes
Show more notes. A scope captures vault activation, destination/folder role,
query, filters and subtype visibility. A new scope resets the budget and scrolls
to the top; a callback from an old scope cannot extend the new one. The containing
collection view resolves its filtered notes once for the list, empty state and
footer instead of repeating that work.

Only view inventory is paged. The workspace retains every matching note, and
selection/ranges, All, bulk operations, opening and the footer retain their full
collection semantics. The Files-hub list and alternate collection views keep
their existing lazy layouts; their full inventories and large-vault costs remain
acceptance work. No change is made to the completely hideable folder sidebar or
its restore control.

One real-workspace owner uses 300 on-disk notes in an owned offscreen AppKit
window. It verifies a bounded first list, selects all results before more pages
are revealed, scrolls to and clicks the final row, changes/clears search, changes
sort order from an expanded list, and reactivates the vault from an expanded list.
The assertions use actual document layout, rendered-text recognition, mouse input,
model selection and unchanged file bytes. No production counter or test-only
injection is exposed. The old workspace view fails seven expected assertions in
`collection144-verified-baseline.log`. This is functional paging evidence, not an
installed performance measurement or physical input acceptance.

Final source hashes, focused/full results, DMG signatures and the complete private
HTTPS download are recorded in `collection144-verification.json` and
`preview100-handoff.json`. No shared Apple/iOS source changes are needed. Full
desktop parity, installed keyboard/VoiceOver/IME, provider behavior and the rest
of the acceptance tracker remain open.

The final versioned Preview 100 suite passes **363 tests, zero failures,
TEST SUCCEEDED**, terminal exit 0 (`collection144-preview100-full-tests.log`).
The focused run passes six collection/paging tests. Frozen source/config hashes
match. The artifact receipt and `preview100-handoff.json` record packaging,
mounted-guide/signature checks and the complete HTTPS download separately from
installed acceptance.


## Live native colour settings — appearance145 / Preview 101

The settings inventory matches the main current desktop controls, but native
colours still required a separate Apply action. The native colour editor now
commits each valid hex or picker colour immediately, and selecting a preset or
loading a named palette applies it to the selected light/dark slot. Closing the
sheet therefore retains valid edits. Incomplete hex text stays raw while focused,
so entering a short colour can continue into a six-digit colour without a caret
jump; blur or Return restores its last valid canonical value.

Each edit reads current preferences and changes the intended role. Loading a
palette merges its roles while preserving future role names; the other slot and
named palettes remain intact. External preference changes refresh the controls
while keeping focused partial input. Malformed or future-version preferences
remain preserved and disable editing until the existing explicit reset is used.
Saving a named palette uses the applied canonical colours. The Mac default design
and wholly hideable folder sidebar remain unchanged.

The owner test uses isolated UserDefaults through SwiftUI's normal
`defaultAppStorage`, real native settings fields and segmented control, and
rendered-label mouse input for named Load and defaults reset. A second owned
window hosts the actual native editor and theme environment. It covers live
recolouring/persistence, continuing short hex text, partial blur, preference
updates from a peer, reopening, dark/light isolation, future-role preservation,
named loading/reset and malformed records. Document text is never published as
an edit. The validated old-code baseline has 15 functional failures
(`appearance145-controls-baseline.log`); earlier field/button locator failures
are fixture diagnostics, not regression evidence. The final focused run passes
four settings/editor tests, including existing composition, selection and Undo
coverage. This is owned-window evidence, not installed colour-panel or physical
IME acceptance.

The settings source audit is recorded in `appearance145-settings-audit.md`.
Current React/Tauri already provides the reviewed notes-only migration for its
private legacy pin/archive lists (migration104); no duplicate import mechanism
was added. Installed old-app migration acceptance remains separate.

Final source hashes, full-suite, signatures, mounted-guide and complete HTTPS
download checks are recorded in `appearance145-verification.json` and
`preview101-handoff.json`. No shared Apple/iOS source changed. Full desktop parity
and installed/VoiceOver/keyboard/IME/system appearance/provider acceptance remain
open in the tracker.

The final versioned Preview 101 suite passes **364 tests, zero failures,
TEST SUCCEEDED**, terminal exit 0 (`appearance145-preview101-full-tests.log`).
Frozen source/config hashes match. The four focused settings/editor tests pass.
Artifact and full-download verification are recorded in `preview101-handoff.json`.


## migration146 — reviewed bounded web-agent imports (Preview 102)

Agent runs lists parent web journals from the selected conversation. Stop the
original run and claim that conversation on this Mac before importing. Review
shows the exact read/write note grants, folder rules, current connection and the
settings/instructions/workflow to freeze. Import never starts a provider request
or applies a note proposal.

The original parent and child journals remain unchanged. Exact source copies,
including embedded images, compacted event details, provider metadata and original
proposal/receipt fields, are saved under `.zerus/native-ai/web-sources/`.
The native format-3 journal carries scoped identity aliases and grants. Older
Mac/iOS decoders refuse format 3; it must not be downgraded to format 1 or 2.
Native continuation is one-way, and does not update the old web journal.

The active model transcript keeps call/result ordering, namespaced repeated call
IDs and frozen image inputs. Historical system messages become untrusted reference
messages. Reasoning and non-image provider parts stay in the original source,
matching the existing web native-provider adapter; extracted document text messages
remain active. Web revisions never become native read coverage. New writes require
fresh native reads. JPEGs already within native bounds keep their exact bytes;
other supported images use reviewed native JPEG derivatives with originals archived.

Pending/approved/applying changes require explicit native review of exact bytes.
Existing per-note receipts survive partially applied batches; already-saved files
are acknowledged without being written again. Undo refuses newer affected-file
bytes and moves newly created notes to Trash. Child journals are archived, saved
worker answers become untrusted interruption results, and reported worker usage
not yet accounted by the parent is charged once. No old worker request is restarted.
Unreported usage of a request that was running in the original client remains
unknown; the review says so rather than inventing exact accounting.

Bounds remain explicit: 240 active messages, 2 MB active text, an 8 MB native
journal, four prepared images, 100 cumulative native steps, 64 MB per web source,
and 128 MB parent/child source archives. Larger transcripts require native
compaction before import; messages are never silently removed to fit. Unsupported
scope shapes, unreadable source journals, and legacy IDs with neither stable
metadata nor an exact historical path/content match are refused with sources kept.
Wider migration/lifecycle, legacy private pin/archive flag handling, installed
handoff, IME and live-provider acceptance remain open. This is a bounded migration
workflow, not a full-parity or release sign-off.

Owner evidence uses actual `createAgentRun`/`NotesAgentRuntime` produced proposal
and receipt fixtures, then the production Mac workspace/controller boundary. It
covers import without note writes or requests, native/text continuations and
frozen images, repeated IDs with reversed tool-result ordering, original and worker
archives, one-time child accounting, partial receipts, questions/plans, explicit
Apply/Undo, newer-write refusal, folder-creation denial, stale source/settings/owner
rejection, and cleanup/retry after a refused image-bearing import. Test logs and
source hashes are recorded in `migration146-verification.json`. Generic iOS
compile evidence is separate from runtime/visual verification; the canceled Device
panel session has not been reopened.

Final review also covers a run stopped before its first model step. An empty web
transcript continues the saved original objective as its first user message.
Imported proposal operations retain their original names and corresponding labels;
the exact-snapshot representation does not relabel a body append as filing. Both
regressions fail on the pre-fix source (6 assertions across 2 owner tests).


## compaction147 — durable context summaries (Preview 103)

Native runs now compact active model history when message count, text size,
frozen input limits or the selected model's capacity require it. Large web-run
imports prepare the same compaction state without making a provider request.
Resume performs the paid summary requests under the reviewed connection and
saved step/time/token limits. A minimum viable final context is checked before
sending; each summary retains an estimated final input and minimum output
allowance, a step and synthesis time.

Mac-only journal format 4 keeps immutable context archives under
`.zerus/native-ai/context/<archive-id>/`. `messages.json` contains every original
native model message, including image references and call/result IDs;
`fragments.txt` is the exact serialized prefix used by the summarizer. Existing
native journals also receive an exact `prior-journal.json` snapshot. Hashes are
checked before summary requests and completion. Source web/worker archives stay
unchanged. Completed summary text, refused calls and charged usage are retained
in separate reply records; signed thinking and raw provider reasoning remain in
the existing device-private continuation cache, not these synced reply records.

A saved cursor and rolling reference summary let Stop/Resume continue without
repeating completed fragments. Fully received summaries and their reported or
estimated usage are persisted together before cancellation is honored. An
interrupted request keeps its reserved allowance exactly once; retrying that
fragment is a new request. Tool replies from a summarizer are refused and never
executed. Fragment sizes adapt to model capacity, and summary requests have no
note tools. Summaries remain untrusted reference data.

Completed call/result blocks stay together when choosing the archived prefix.
All original image pixels remain available to the final model request in their
original order. The runtime rebuilds the objective, tracked plan, pending
proposals and recent receipt catalog around the summary. Exact full metadata
stays in the journal. Old read coverage is cleared, requiring new reads before
edits. Retired tool-call hashes prevent reuse of an archived call ID. Exact
proposal Apply/Undo continues to use the ordinary draft, identity and byte-CAS
boundaries even while compaction is paused.

The source parser's 64 MB per web journal, four-image processing bound and 128 MB
parent/worker archive bound remain. Each native context message/text archive is
bounded at 64 MB. The active native journal still has an 8 MB envelope: very large
proposal/receipt collections and tool-result storage pressure need further work.
Compaction cannot make oversized frozen guidance, original requests, retained
images or recent executable call blocks fit an impossible model/input allowance.
The latest user turn remains exact in active context. If that answer alone cannot
fit, the run pauses before any provider request and preserves the answer unchanged.
Budget exhaustion pauses with source and completed progress retained; it never
silently discards history or exceeds the saved limits to force completion.

Owner evidence covers large imported history, native automatic compaction,
compatible native/text transports and Anthropic signed-thinking responses,
interrupted summary accounting, smaller model contexts, retained images,
Apply/Undo while paused, changed-archive refusal, refused summary tool calls,
final-step holdback, and blocked edits until fresh reads. The archive, read-
coverage and private-thinking regressions have failing pre-fix owner runs.
Full Mac and iOS compile results, hashes and packaging checks are recorded in
`compaction147-verification.json`. Installed UI, IME, physical/simulator handoff,
live providers, wider migration lifecycle and full desktop parity remain open.

The final size matrix separately exercises 523 ordinary model messages and a
single transcript exceeding 2 MB with fewer than 240 messages. Corrupt saved
limits are rejected before compaction range validation; the pre-fix pure decoder
test reproduced the fatal range check without opening a vault fixture.


## storage148 — exact large review payloads (Preview 104)

The 8 MB native journal limit previously refused an otherwise supported web run
when complete proposal snapshots and organization changes expanded beyond that
size. Applying a proposal also copies its before/after snapshots into a receipt,
so the same limit could stop a later Apply or Undo.

Large proposal and receipt records now live in immutable JSON payload files under
`.zerus/native-ai/payloads/<run UUID>/<SHA-256>.json`. The journal remains an
8 MB CAS manifest. Format 5 prevents old Mac/iOS clients from treating payload
references as complete review records. The reader derives every path from the
run and digest, checks the declared size, digest and record identity, expands the
exact original record, and runs the ordinary snapshot/permission validation.
Expanded journals are bounded at 128 MB; this is not unlimited migration storage.

Every journal-writing boundary packages its payloads and manifest together in the
existing vault transaction, including import, provider binding, pause/resume,
ordinary tool results, manual/automatic Apply, Undo, independent analysis and
context compaction. Existing payloads remain immutable. Reviews guard old
referenced payload bytes as well as newly staged records at commit time. Changed,
missing or mismatched payloads refuse progress before note writes. Unknown record
fields survive the ordinary overlay. Payload files are not shown as note changes
in the review UI. Small existing journals retain their previous representation.

The owner regression imports a 14 MB web source with a large exact proposal,
reopens it, refuses Apply after payload tampering without changing the note or
manifest, restores the exact bytes, applies, reopens, undoes and resumes through
the provider fixture. It then stages a native body edit and an independent pin
change, approves both together, and undoes each while retaining the imported
receipt. The mixed-approval baseline demonstrates the duplicate-file refusal;
only the final combined journal contributes payload changes. Note text and the original source remain exact. The
validated pre-fix run fails at the journal format/size guard; earlier fixture
diagnostics are not counted as baseline evidence. Tests and frozen-source hashes
are recorded in `storage148-verification.json`.

Payloads remain retained with the existing run/context/source recovery data,
including historical immutable versions. Deletion/reimport cleanup and provider
acceptance remain part of the wider lifecycle work. Active model/tool-result
history can still exert pressure on the 8 MB manifest and needs further work.
Other-device takeover, installed UI/IME/live providers and complete desktop parity
remain open. The fully hideable folder sidebar remains intentional.


## history149 — exact active-message payloads (Preview 105)

An accepted native response can contain twelve calls with up to 400 KB of arguments
each. JSON escaping can push that single reply beyond the 8 MB journal limit before
any tool executes or context compaction can run. Rejecting its storage loses the
arrived call data and exact reported usage.

Format 6 extends the immutable payload mechanism to large active messages. The
reader validates the role, size and SHA-256, restores the complete message, then
checks ordinary call/result identities, attachment grants and run limits. Older
clients refuse format 6. Message payloads use the same derived paths, 128 MB
expanded-journal bound, atomic manifest/payload transaction and unchanged-byte
dependencies as proposal and receipt payloads. Arguments, content, tool result
IDs and image references are not shortened. Small messages stay inline.

The normal request/context limits still apply to the restored model history.
Compaction archives complete call/result blocks and exact messages before using
any paid summary request; it never sends payload pointers as model content. Stop
retains the archived source and settles its interrupted reservation once.

The owner test records a bounded twelve-call, escape-heavy response that fails
on Preview 104 at the journal size guard. It checks all arguments and usage after
reopening, refuses a changed payload, completes twelve invalid-query refusals
without read coverage or mutations, archives matching call/result IDs, starts and
stops summarization, and checks that resuming does not charge the reservation
again. This is an owning journal/controller test, not a live-provider claim.

A process sample identified repeated BPE merges of identical long escaped spans
during fragment planning. The tokenizer now keeps completed exact counts in a
process-local cache bounded to 64 pieces and 4 MB of source bytes; pieces are keyed
by their exact bytes. Cancellation checks and accounting remain. Optimized scratch
binaries of both the uncached and cached shared tokenizer match the pinned
js-tiktoken 1.0.21 reference for cold and repeated inputs. These are algorithm and
fixture results, not installed typing or provider latency measurements.

Source hashes, owner/full runs, iOS compile and packaging checks are recorded in
`history149-verification.json`. The manifest remains bounded at 8 MB; unusually
large non-message metadata, expanded data beyond 128 MB, context archives beyond
64 MB, payload/source deletion and reimport lifecycle, other-device takeover,
installed UI/IME and live-provider acceptance remain open. Full desktop parity is
not established. The fully hideable folder sidebar remains intentional.


## lifecycle150 — indexed deletion and re-import (Preview 106)

Web import previously reused a native ID derived from the source identity. After
Delete journal, its immutable source archive and frozen private-input grant stayed
behind. Re-import then collided with those files; a delayed sync could also
restore an old journal and make it resumable again.

Each reviewed import attempt now receives a fresh native run ID. A per-source
status file under `.zerus/native-ai/web-imports/` records the active native run,
frozen source digest and explicit active/deleted state. Its path is derived from
the full relative source path. Import commits that status, public journal, source
archives and payloads in one existing byte-CAS transaction. Competing prepared
attempts cannot both claim the same local source status; failed attempts remove
only their newly created private grants and image files.

Delete journal marks its source deleted in the same transaction that removes the
active journal. A missing journal with active status is treated as possible partial
sync, not permission to import again. Restore/wait for that journal and delete it
through the app to explicitly release the source. Runtime checks and transaction
dependencies refuse a deleted/replaced import if an old journal reappears. An
owned retired journal can be removed without releasing its active replacement.
Format 7 prevents older clients from ignoring these new requirements. Legacy
unindexed imports remain readable, and their existing journal blocks a duplicate
import; deleting one through the app establishes the explicit deleted status.

A first exact source copy reserves the old deterministic archive path when it is
absent, preventing older importers from committing their before-nil archive write.
An existing copy is preserved byte-for-byte, including when a newer source version
is selected. Each fresh native run keeps its own exact parent/worker archive paths.
This compatibility reservation can retain one additional parent source copy of
up to 64 MB. The existing 128 MB parent/worker source bound still applies to each
review. Import status is bounded at 64 KB; transitions that would exceed that
bound refuse before journal deletion or any status write. Unknown fields survive
status transitions and re-import.

The delete confirmation states what stays: applied notes, the conversation,
source/context archives and attachment files. Native progress and Undo access are
removed with the active journal, and private provider continuations are removed.
Re-import review explicitly says that it starts from the selected web snapshot,
not the deleted native continuation. Prior attachment grants are preserved and
new grants use fresh run/image IDs. Unused-input and archive garbage collection
remain separate pending work. The web-source list refreshes when saved run IDs
change, so deletion makes a source available without reopening the sheet.

The existing native/text-fallback migration owner now covers competing reviews,
active-source refusal, failed-attempt input cleanup, explicit deletion, missing
active journal refusal, a resurrected retired journal, changed-source re-import,
old/new grant isolation and image pixels, unchanged old source/worker archives,
future-field preservation, the exact status-size boundary, and cleanup of an old
journal while its replacement remains usable. The pre-fix lifecycle and size-
transition runs fail at their intended boundaries. A suspected saved-run catalog
issue was disproved by its diagnostic run; no controller fix was made for it.

Source hashes, owner/full runs, generic iOS compile and packaging are recorded in
`lifecycle150-verification.json`. This is coordinated local transaction evidence,
not proof of instantaneous locking between offline devices. Wider legacy/private
flags and scope acceptance, private-data cleanup, provider sync/conflict handling,
installed UI/IME/live providers and full desktop parity remain pending. The fully
hideable folder sidebar remains intentional.

### Attachment cleanup scope audit after Preview 106

The existing React/Tauri client has no separate unused-attachment cleanup flow.
Its `purgeExpiredChats` in `src/lib/mobile-chat-history.ts` removes deleted
conversations after 30 days, only for their owning device, writes a shared
tombstone, and removes the conversation's web-run directory. Matching that
retention workflow remains native parity work. The native conversation reader
honors shared tombstones, but native automatic expiry/purge is not implemented.

Private native agent inputs and retained source/context/payload archives have a
different lifecycle. Their garbage collection is a possible extension, not proof
of missing React/Tauri attachment controls. Any future cleanup must account for
saved journals, archived context, drafts and in-flight work before removing files.
Preview 106 retains those files. This audit changes documentation only; its
packaged guide remains the version verified at handoff.

## retention151 — native conversation Trash expiry

Native history refresh now implements the existing desktop's owner-only 30-day
Trash policy. A coordinated, recoverable file transaction writes the shared
`chat-tombstones/<conversation-id>.json` record and removes the expired
conversation's descriptor, events and attachments, its web-run files, and its
associated readable native run journals. Imported run indexes become deleted in
the same transaction, preserving unknown fields. Other conversations' journals
are byte dependencies, so a changed association cancels cleanup. Delayed sync of
old conversation records cannot override the tombstone. Empty directories may
remain, but contain no retained conversation files.

Cleanup waits while a local chat or run is active, a run review is open, another
vault window is busy or closing, or another admitted file operation is underway.
Unsent prompts/attachments and saved private reply recoveries protect their
conversation even when another conversation is selected. A stale or unsupported
private draft skips cleanup and reports a warning. Deleted conversations owned
by other devices, recently deleted chats, archives and restored chats remain.

Every affected file is compared with its reviewed bytes; directory inventories
and the vault's device/inode identity are rechecked inside the transaction.
Linked, unreadable or unsupported data is preserved with a history warning. A
native journal with unknown ownership/association prevents automatic purge.
The scan bounds manifests at 8 MB each and 64 MB in aggregate, inventory at
50,000 entries, and affected conversation/web-run/journal bytes at 512 MB.
Related journals are fully decoded individually; unrelated message/proposal
payloads are not expanded. Histories outside these bounds remain available
without being automatically removed.

Private agent inputs, immutable payload files, source/context archives and
provider caches remain under their existing retention policies. This implements
conversation expiry rather than general private-file garbage collection. No
note content is changed or undone. Saved-run controls refresh after a purge,
and clear a selected run whose journal was removed. The Trash view explains the
30-day policy and draft/activity deferrals.

New owning tests exercise the exact expiry boundary, foreign ownership, restore,
archive, protected drafts, malformed events, linked files, saved native/web
runs, retained archives, portable tombstones and sync-delayed resurrection.
The real controller refresh test also covers a busy peer window and unreadable
run preservation. The migration lifecycle owner checks imported-index retirement,
retained image grants/source archives, and removal from the open run controller.
Routing refresh through the old read-only loader fails seven assertions for the
intended missing-cleanup behavior. Final checks and packaging are recorded below
when complete; installed UI, provider and cross-device sync acceptance remain
pending. The fully hideable folder sidebar is preserved.

A sibling Retry check exposed a temporary admission regression during development:
refresh acquired a preparation hold even without expired history. Cleanup now
acquires that hold only when an eligible expired conversation exists. The final
focused run passes all 13 conversation/controller/migration checks, including
immediate Retry. Temporary diagnostic logging was removed before final checks.

Final retention151 verification: the full Mac suite passes **375 tests with zero
failures**, terminal exit 0 (`retention151-full-tests.log`), and the generic iOS
simulator build-for-testing exits 0 (`retention151-ios-compile.log`). The latter
is compile-only and does not advance the iOS build number. The earlier canceled
device session was not retried. Final source hashes match
`retention151-review/source-hashes.json` and `retention151-verification.json`.
The changed-file gate script and the referenced autoreview/openclaw-testing/
crabbox skills are unavailable; self-review, test-audit, native Xcode checks,
changed-file whitespace and frozen-source hash checks were used. This evidence
does not establish installed interaction, IME, live-provider or full parity
acceptance. Preview 107 packaging is verified separately at handoff.

## documents152 — connected-document status and refresh

The React/Tauri `FileHubPanel` supplies resolved path/size, original-file reveal,
and status refresh on window focus. Native folder mapping already exists; its
tracker entry describes remaining interoperability acceptance, not an absent
Finder folder picker. The new native document actions fill the actual gaps:
Reveal selects the resolved document in Finder rather than the Markdown note,
and the header shows its on-device path and file size. Standalone attachment/
backup previews also offer Finder reveal. These actions use the retained file
lease and do not modify note metadata or original bytes.

On app activation the connected-document pane re-resolves its current binding.
An unchanged canonical path, size, modification date and per-file-override state
keep the same lease/view identity, preserving page/search state. A changed
result replaces the lease and reconstructs the document surface; explicit Reload
forces that refresh even when metadata matches. Changes that deliberately retain
all of those metadata values need manual Reload, matching the desktop's metadata
refresh contract. Unavailable files clear the lease, disable original-file
actions and expose the existing Locate action. Remapping, locating, restoring
folder mapping and replacing the document re-resolve the binding.

The preview controller checks the current vault activation and note binding
before loading and again after the await. Tokens and cancellation discard stale
results. Focus/manual requests run through SwiftUI's view task so leaving or
changing the pane cancels pending work. Display and actions are gated by the
loaded source identity, preventing a previous note's lease from appearing under
a new header. A stale callback from an earlier vault activation cannot clear a
newer valid preview. Closing the pane releases its preview lease.

The existing storage owner now covers all three storage modes, unchanged lease
identity, same-size outside edits, explicit reload, missing-file recovery, note
byte preservation and detach. The mapping owner adds identical-size/date remaps,
per-file overrides and return to folder mapping. A separate activation owner
checks a delayed old-activation request and a pre-canceled refresh. Unconditional
lease replacement fails three assertions in the identity baseline. The initial
activation implementation also fails three assertions before the stale-input
guard. Four focused tests pass after repair. Test expectations use real temporary
files, real bookmarks and actual workspace methods; no production test seam or
Finder launch is substituted.

This does not verify real Finder selection, provider stalls, installed focus/
page/search interaction, or iOS Drive account interoperability. Those remain
acceptance work. The fully hideable folder sidebar is preserved. Final frozen
hashes, full checks and packaging are recorded in `documents152-verification.json`.

Final documents152 checks: the full Mac suite passes **376 tests with zero
failures**, terminal exit 0 (`documents152-full-tests.log`). All four focused
owners also pass within that full run. The generic iOS simulator build-for-
testing exits 0 (`documents152-ios-compile.log`); this is compile-only, with no
iOS build-number change or device-session retry. Frozen source hashes match
`documents152-review/source-hashes.json`. Self-review, test-audit and whitespace
checks are complete; the referenced autoreview/openclaw-testing/crabbox skills
and changed-file gate script are unavailable. Preview 108's mounted app, bundled
guide, signatures and full private HTTPS download are verified separately at
handoff. This remains partial parity evidence, not installed acceptance.


## html153 — reviewed HTML preview modes and downloads

Connected HTML documents and standalone HTML previews now offer Only link, Safe,
and Full choices. Only link keeps the document notes without rendering HTML.
Benign HTML automatically selects and remembers Safe; source containing scripts
or external origins first asks for a choice. Safe disables JavaScript in WebKit,
blocks network requests, removes refresh redirects and keeps embedded data/blob
images. Full lists the detected HTTP(S) origins and runs scripts in an opaque
sandbox frame with no app bridge, neighboring-file read grant, popup windows,
form submission or media-capture permission. Relative local resources have no
file base URL. The existing external-open action remains available.

The immutable UTF-8 snapshot is limited to 10 MB, read with a bounded stream.
Analysis has a cumulative two-second/50,000-match bound. Full supports at most
128 discovered origins; Safe and Only link remain available above that limit.
Detection is a review aid rather than a complete JavaScript analyzer. Requests
outside the reviewed origin list are blocked, including computed URLs and child
frame requests, through both content policy and WebKit content rules. Default
TLS certificate validation remains active. No app credentials are supplied.

Choices are private to this Mac and file identity. Full approvals include the
raw-byte fingerprint, policy version and exact origin list. Activation re-reads
the bytes, so even an edit preserving size and modification date expires Full
approval. Choosing a mode also re-reads the file to reject changes during review.
A stale or closed chooser cannot approve another document. Unchanged snapshots
retain their view identity. The entire folders sidebar remains fully hideable.

Full preview downloads use a native Save panel, a separate progress/Cancel window
and the File menu's HTML Downloads action. Up to 16 accepted transfers retain
their frozen origin grants and continue after the preview closes. A completed
transfer is staged beside its chosen destination; coordinated fingerprint checks
preserve files changed during transfer, and a newly appeared destination is not
overwritten. Incomplete transfers can be canceled. Quit offers to keep downloading
or cancel, and waits for a save already committing. No installed CLI or shell is
used to render or download HTML.

Four owning tests cover content-bound preferences, unchanged-metadata changes,
stale review, limits, real WebKit rendering and real loopback HTTP requests from
both the main document and remote child frames, plus destination commit safety.
Snapshots distinguish Safe's static content from Full's script result; scripts
also attempt parent access and a neighboring local-file read. The network test
checks computed fetch and WebSocket requests against a second unapproved origin.
Disabling the content-rule installation makes this test fail; the unprotected
renderer behavior baseline also fails the script/isolation checks. These are
owned offscreen windows, not installed-app UI acceptance. Final logs and hashes
are recorded in html153-verification.json.

Actual Save-panel, download/quit interaction, HTTPS provider downloads, installed
preview controls and keyboard/IME acceptance remain pending. No previously denied
computer-use or canceled device session was retried. The iOS check is compile-only;
no shared iOS source or version was changed. Full desktop parity remains pending.

Final html153 verification: all **380 Mac tests pass with zero failures**, terminal
exit 0 (`html153-full-tests.log`), including the four HTML owners. The generic
iOS simulator build-for-testing also exits 0 (`html153-ios-compile.log`), with no
iOS version change. Final source hashes match html153-review/source-hashes.json.
Self-review, test-audit and changed-file whitespace checks are complete; the
referenced autoreview/openclaw-testing/crabbox skills and changed-file gate script
are unavailable. Preview 109 is an ad-hoc local arm64 DMG for macOS 26+, with its
mounted app, bundled guide, signatures and private HTTPS download verified
separately at handoff. This does not establish installed or full-parity acceptance.


## history154 — read-only saved-image browsing

The automatic-history browser now shows saved image pixels before opening a
restore review. This closes the native tracker’s image-preview gap and aligns
with the existing iOS rich history preview. React's automatic-history panel is
still a source/line-diff surface; its deliberate revision view already renders
frozen resources. This change does not claim a new React feature is required.

The selected record is checked before and after loading. Local image references
are rewritten to their captured history blob paths, and every loaded blob must
match its recorded SHA-256. Uncaptured references never resolve against today's
vault files. Missing, changed or undecodable images remain placeholders with a
warning; the saved text stays readable and original Markdown remains available.
Browsing creates no restore files and changes neither note nor history records.
Restoring still uses its separate existing review and transaction.

The loader reuses cancellable coordinated provider reads (15 seconds and 50 MB
per file), rejects dimensions above 16,384 pixels per side or 40 megapixels, and
creates 720-pixel thumbnails. Eight distinct saved images load per page, bounding
decoded memory while Previous/Next images exposes every captured image. Repeated
occurrences of a shared blob reuse the same preview. Source text always remains
the exact selected version rather than the rewritten display copy. Changing a
selection cancels its SwiftUI task; model guards reject an earlier vault activation
both before and after the asynchronous read. Selected saved-version rows also
expose their selected state to accessibility.

The recovery owner tests cover rendering saved pixels before a restore review,
changed live files, missing and corrupt blobs without live fallback, all nine
images across two pages, return navigation, unchanged vault bytes/file inventory,
changed-record refusal, cancellation, old activation refusal and existing restore
behavior. Omitting historical pixels fails the two changed/new owners (four
assertions). The baseline is a targeted no-pixels behavior check, not an exact
build of the old UI. No test-only production seam is added.

Installed page navigation, provider stalls, large-history responsiveness,
VoiceOver and keyboard/IME remain acceptance work. The previously denied computer
use and canceled device session are not retried. The entire folder sidebar stays
fully hideable. Final full checks and package evidence are recorded separately in
history154-verification.json; full desktop parity remains pending.

During full validation, the existing new-note-default test observed a reopened
window before its warm-cache reconciliation had found the new file. Its isolated
re-run passed. The test now awaits the public Refresh boundary before the same
section, folder and selected-note assertions; production startup behavior is
unchanged. The failed full run is retained as history154-first-full-cache-race.log.
All five recovery owners and that synchronized owner pass together (six tests).

Final history154 checks: **381 Mac tests pass with zero failures**, terminal exit
0 (`history154-full-tests.log`). All five recovery tests and the synchronized
new-note owner pass in this final run. The generic iOS simulator build-for-testing
exits 0 (`history154-ios-compile.log`); no iOS source or version changed, and the
earlier canceled device session was not retried. Source hashes match the final
history154-review/source-hashes.json. Self-review, test-audit and changed-file
whitespace checks are complete; the referenced autoreview/openclaw-testing/
crabbox skills and changed-file gate script are unavailable. Preview 110 is an
ad-hoc local arm64 DMG for macOS 26+, with mounted app, bundled guide, signatures
and private HTTPS download verified separately at handoff. Full parity and
installed interaction remain pending.


## metadata155 — large saved-run metadata

Messages, proposals and receipts already used exact immutable payload files, but
large permission lists and other root fields could still exceed the 8,000,000-byte
journal limit. The writer now puts large root fields into hash-verified field
groups. If many small fields collectively exceed the manifest allowance, they
are grouped too. Values, key/value associations, permissions, provider bindings,
analysis history and unknown fields stay exact. Unchanged large values reuse
their existing payloads instead of copying the whole run on each event.

Storage envelope 8 carries the original logical run version separately. This
keeps format-7 import-index requirements and earlier legacy-import rules intact;
it does not grant different tools, scope or ownership. Run ID, conversation ID
and owner stay in the small manifest, and field groups cannot override them or
another existing field. File paths come from the run ID and lowercase SHA-256,
not a path supplied by the manifest. Every reference has an exact byte count and
digest. Loaded payload bytes and the expanded journal remain bounded to 128 MiB;
the manifest keeps its existing 8 MB bound. Mac payload reads are coordinated,
confined, cancellation-aware streams capped at that byte limit even if a file
grows after its metadata was read.

Provider, independent-analysis and context-compaction readers consume decoded
runtime extension metadata; their writers expand the old manifest before editing
it. JSON reads preserve leading Unicode marks. New payloads, unchanged old
payload dependencies and the new small manifest share one compare-and-swap
transaction. Missing, corrupt, oversized or conflicting data is refused while
retaining the original journal. Existing storage formats 1–7 still load. Older
Mac/iOS decoders refuse envelope 8 before taking over; iOS decoding behavior is
unchanged by the Mac-conditional implementation. Conversation expiry recognizes
the new header and retains immutable payload files as before.

The runtime owner uses a journal above 8 MB with 30,000 retained permission IDs,
exact Unicode-bearing unknown metadata, an extended provider binding and archived
analysis metadata. It reopens, pauses/resumes, performs an allowed and a refused
read, checkpoints interrupted analyses, compacts, and continues through the
fixture provider. It checks exact metadata, unchanged note bytes, payload reuse,
stale transaction refusal after a payload edit, corrupt-catalog isolation,
oversized sparse-file refusal and protected-identity conflicts. A storage owner
round-trips 50,000 individually small fields above the old manifest limit. Both
fail at the old storage handler's limit. The existing conversation-expiry owner
also verifies envelope-8 journal removal with payload preservation; its earlier
header-guard baseline refuses the new format. These tests add no production seam.

Large catalogs, real provider interruption, cross-device takeover, full legacy
migration and installed/IME/live-provider acceptance remain pending. The previous
computer-use denial and canceled device session are not retried. The hideable
folder sidebar is preserved. Frozen hashes, final checks and packaging evidence
are recorded in metadata155-verification.json. This remains partial parity work.

Final metadata155 verification: **383 Mac tests pass with zero failures**, terminal
exit 0 (`metadata155-full-tests.log`), including the eight focused owners. The
generic iOS simulator build-for-testing exits 0 (`metadata155-ios-compile.log`);
the source changes are Mac-conditional and do not change iOS behavior or advance
its build number. The earlier canceled device session was not retried. Final
source hashes match metadata155-review/source-hashes.json. Self-review,
test-audit and changed-file whitespace checks are complete; the referenced
autoreview/openclaw-testing/crabbox skills and changed-file gate are unavailable.
Preview 111 is an ad-hoc local arm64 DMG for macOS 26+, with mounted app, bundled
guide, signatures and private HTTPS download verified separately at handoff.
Installed interaction and full desktop parity remain pending.


## catalog156 — bounded saved-run reads and cancellation

The run catalog previously read entire files before the decoder applied its
8,000,000-byte manifest limit. A synced oversized file could therefore allocate
far more than the decoder accepts. It also treated cancellation as an unreadable
entry and could return a partial catalog. Mac journal reads now share the bounded,
coordinated stream reader used by payloads, with the smaller manifest allowance.
Size is checked inside the coordination and the stream stops at the limit plus
one byte if an uncoordinated writer grows the file. Paths remain confined.

Catalog listing, ownership checks, Resume, recovery/review readback and native-run
retention use that same manifest reader. A bad file remains on disk, is listed as
unreadable and keeps its private provider continuation. Healthy runs remain
available. Cancellation is checked before scanning, between entries, during reads
and before returning; cancellation is propagated rather than labeled corruption.
The workspace checks again before cache cleanup, and the controller discards a
canceled refresh instead of replacing its current list.

The extended catalog/cache owner uses an actual oversized journal beside a
healthy run, verifies the reader and Resume refusal, unchanged size and prefix,
recovery-cache preservation and later cleanup after deliberate journal deletion.
It checks pre-cancellation and cancellation while a real NSFilePresenter holds a
coordinated read. The presenter is the existing startup-read test fixture, now
shared with its two startup owners; no production read or actor is substituted.
The old unbounded/swallowed-cancellation behavior fails four assertions.

This does not make the catalog lazy or cap its total decoded-run memory. A blocked
provider coordination can still delay cancellation until control returns; no
immediate cancellation or provider timeout is claimed. Large-catalog cost,
provider interruption, installed run controls, keyboard/IME, live providers and
full parity remain pending. The changes are Mac-conditional; iOS behavior and
build numbering stay unchanged. The previously denied computer use and canceled
device session are not retried. The folder sidebar remains fully hideable.
Final source hashes, checks and packaging are recorded in catalog156-verification.json.

Final catalog156 checks: **383 Mac tests pass with zero failures**, terminal exit
0 (`catalog156-full-tests.log`), including the 39 focused owners. The generic
iOS simulator build-for-testing exits 0 (`catalog156-ios-compile.log`), with no
iOS behavior or build-number change and no retry of the canceled device session.
Frozen hashes match catalog156-review/source-hashes.json. Self-review,
test-audit and changed-file whitespace checks are complete; the referenced
autoreview/openclaw-testing/crabbox skills and changed-file gate are unavailable.
Preview 112 is an ad-hoc local arm64 DMG for macOS 26+, with mounted app, bundled
guide, signatures and full private HTTPS download verified separately at handoff.
Installed interaction and full desktop parity remain pending.


## Window-close veto and agent admission (lifecycle157)

After the workspace saves and checkpoints an AI run, the original window delegate
can still refuse to close its window. The native close protector now releases the
controller's leaving guard when that happens. It also releases the captured
controller if a prepared close is canceled or the window delegate changes before
handoff. A successful close continues to block new run requests.

The existing real-NSWindow lifecycle owner now saves an edited note, receives an
original-delegate veto, reopens the saved run in the retained window, and then
closes successfully through that same delegate. The unchanged close/provider
owners cover refusal during a real transition and stopping/checkpointing a live
fixture request. The exact regression owner fails before the repair with the
leaving-controller refusal. Offscreen AppKit evidence does not establish installed
keyboard/IME or visual acceptance. The fully hideable folder sidebar remains.

Preview 113 packaging and final suite evidence are recorded in the matching
lifecycle157 verification and handoff receipts. Full parity remains in progress.


## Shared admission parsing — perf158 / Preview 114

Rich-mode admission now shares the original Markdown tree with code and table
source discovery. When code/table source is removed, structural and HTML prose
checks share one new parse of that stripped source; when nothing was removed,
they reuse the original tree. Table discovery also shares its parse between
quoted and list-owned cards. The source text, parser options, traversal order and
admission rules are unchanged. No tree is cached across note edits.

A temporary Release diagnostic compared three samples for each of twelve styled
fixtures (500, 4,000 and 20,000 paragraphs; plain, inline breaks, root code and
list-owned code). At 20,000 paragraphs, median admission fell from 1,054 to 684 ms
for plain styled prose, 1,392 to 724 ms with inline breaks, and 1,049 to 803 ms
with root code. The separate list-owned-card validation path is a control rather
than a claimed improvement. Exact measurements and logs are in
`perf158-measurements.json`. This measures admission only, not displayed-editor
load, keyboard latency or installed acceptance.

The diagnostic is removed from normal tests; existing admission, source fidelity,
card, clipboard and Undo owners remain authoritative. Final suite and packaging
results belong to the matching perf158 verification and Preview 114 handoff
receipts. No shared/iOS source or iOS build number changed. Large-note displayed
load, broader incremental export, non-AI workflow acceptance and full desktop
parity remain pending. AI work is deferred at the user's request. The folder
sidebar remains entirely hideable with its restore control.


## Empty final text blocks — containers164 / Preview 115

Empty headings, quotes and intentional blank paragraphs at an unterminated EOF
now keep a native row for their source and role metadata. Its presentation-only
terminator is omitted from Markdown. Cmd-End stays in that row, refill preserves
the role and original source ending, and item-owned Return keeps its final line
unterminated when it splits nonempty text. Canonical empty root ATX headings use
the same source-range resolver as item headings.

The primary representation owner adds 25 hosted LF/CRLF/lone-CR workflows with
source, caret, font, refill, reopen and Undo/Redo checks. It fails 305 assertions
on the pre-change code. Final document/clipboard and full-suite results are in
`containers164-verification.json`; the matching Preview 115 handoff records the
actual mounted app, guide, signature and full private download verification.

Unreleased admission work from containers160–163 is included only as guarded
core foundation: item-owned headings and prose quotes still open in Source.
Nonempty, selected and anchored-empty Return commands have owner evidence, but
Backspace/deletion, formatting, indentation, clipboard/cards, broader ranges and
installed input/IME acceptance remain open before those shapes can be admitted.
The package-only Backspace probe requires a real DOM selection and supplied no
passing keyboard evidence. No shared/iOS or AI source changed in this batch.
The folder sidebar remains fully hideable with its toolbar restore control.


## Text-block Backspace — containers165/166 / Preview 116

Nonempty item-owned text blocks retain their role when a root list wrapper is
removed or a compatible block merges. Navigation to earlier flat item text only
moves the caret. Nested outdent keeps the existing following-peer policy. The
actual registered web Backspace commands now have owned WebKit/DOM evidence;
the earlier package-only failed probe is not the current command reference.

Empty root headings and quotes respond at document start, and removing an empty
block is one explicit Undo step. A quote with later paragraphs keeps those
paragraphs and its quote role. A live explicit Tail remains separate when an
empty inner heading is removed. Clearing the final nonempty body now retains
the same presentation-only terminator as empty EOF import, preserving source
ending, role, refill and Undo/Redo. Marker-first and later blocks are covered.

The existing Backspace owner adds 77 nonempty and 52 empty-block workflows with
handwritten source, independent parser roles/parents, caret, typography, follow-up
typing, Undo/Redo and reopen. Exact baseline, owner and full-suite records are in
containers165-verification.json and containers166-verification.json. Preview 116
contains these repairs; its handoff separately verifies the mounted app, bundled
guide, signature and full private HTTPS download.

Public item-owned heading/quote rich admission remains closed. Nonempty root quote
key behavior, deeper quote/list/card boundaries, complete format/delete/indent/
clipboard and broader ranges, installed physical input/IME and full parity remain
pending. This is a local ad-hoc test DMG, not notarized release acceptance. No AI
or iOS source changed. The whole folders sidebar remains hideable/restorable.


## Leading quote and final-body Cut — containers167/168 / Preview 117

The existing native Backspace owner now covers 61 positive leading-quote workflows, plus heading no-op, Source/read-only and prior native Return history controls. The first nonempty Paragraph of a leading Document quote chain removes one nearest wrapper. Child headings, lists, paragraphs, code and tables retain their independent roles. A parser-tree comparison and byte-exact prepared export guard the one Undo transaction. Only the target native span is rendered again. The exact final owner fails 500 assertions on the prior production code.

Final-body Cut shares keyboard preparation and exports the original selected fragment before committing. Its 54 workflows and missing-resource refusal control retain original endings, block roles, caret/refill, Undo/Redo and reopen. EOF source-token reuse and caret typing styles are corrected. The frozen combined source passed the full Mac suite; logs and hashes are recorded in containers167-verification.json, with prior Cut-specific evidence in containers168-verification.json.

Preview 117 packages these changes as an ad-hoc non-notarized arm64 test DMG for macOS 26+. Mounted version, signature, bundled guide and complete private download checks are recorded separately in preview117-handoff.json after packaging. Public item-owned heading/quote rich admission, quotes after preceding blocks, deeper empty/card-first boundaries, broader structural and clipboard interactions, installed physical keyboard/IME, performance and cross-client acceptance remain pending. AI is deferred. No iOS source changed. The whole folders sidebar remains hideable and restorable.


## Quote boundaries after preceding text — containers169 / Preview 118

Backspace at a quoted paragraph or heading merges only its text into the preceding text block. The receiving prose/heading/list item keeps its role, later quote children remain in their containers, and only emptied quote ancestors disappear. For an empty preceding paragraph or heading the quote remains, while an empty bullet or numbered item receives its text. Unrelated empty quotes remain untouched. The quote caret retains its inline format; links do not extend across the join. One Undo/Redo transaction restores the exact note and selection, including earlier native Return history.

The hosted owner covers 87 added workflows across LF/CRLF/lone-CR, with 21 registered web key/typing controls as a separate reference. The exact final test fails 753 assertions on Preview 117. The final Mac suite passes 385 tests on frozen application sources before the version/documentation-only bump. Source hashes and logs are in containers169-verification.json. The empty checkbox source is a known web import distinction and is not treated as a native genuine-checkbox contract.

Preview 118 is an ad-hoc, non-notarized arm64 test DMG for macOS 26+. Mounted payload, bundled guide, signature and full private download verification are recorded in preview118-handoff.json after packaging. This is not installed keyboard/IME or full parity acceptance. Public list-owned heading/quote admission stays closed until formatting, deletion, indentation and clipboard behavior are complete. Eight actual core toolbar-signal references in containers170-discovery confirm the next repair: existing inner blocks keep their list owner, whereas flat list-row formatting can remove the wrapper. Deeper empty/card-first quote boundaries, performance and cross-client acceptance remain open. AI is deferred, iOS is unchanged, and the whole folders sidebar remains hideable/restorable.


## Inner formatting and live quote Return — containers170/171 / Preview 119

The guarded native editor core retains list ownership when an inner heading,
quote or explicit paragraph changes block type. Flat list-row wrapper removal
keeps its earlier behavior. Hard breaks, relative quote gaps, marker-width
changes and separately undoable native typing retain their block roles.

Compound formatting distinguishes a newly created quote from the paragraph
inside an imported quote. Paragraph/Heading replaces that new quote; repeated
Quote does not deepen it. Return at its start, middle or end creates a paragraph
outside that quote, retaining the owning list item and any enclosing quote.
Empty quotes stay empty rather than gaining a paragraph anchor. Nonempty
Markdown imports reconstruct their child paragraph; empty parsed quotes infer
the empty quote role. No shared persisted metadata was added.

Exact regression baselines fail on the previous implementations. Three focused
editor owners and the final 385-test Mac suite pass on frozen application
sources before the version/documentation-only bump. Web toolbar/key references
record actual live structures separately; canonical native Markdown does not
copy lazy-continuation loss or invalid nested-heading exports. Evidence is in
containers170-verification.json and containers171-verification.json.

Preview 119 is an ad-hoc, non-notarized arm64 test DMG for macOS 26+. Public
list-owned heading/quote rich admission stays closed until deletion/lifting,
shortcuts, clipboard/ranges and embedded-card interactions are accepted.
Installed keyboard/IME and pointer QA, displayed performance, cross-client
acceptance and production delivery remain open. AI is deferred; iOS source is
unchanged. The complete folders sidebar remains hideable and restorable.


## Scoped shortcuts, clipboard and indentation Undo — Preview 120

This preview includes the containers173–176 editor repairs. Typed checkbox,
bullet, heading, quote and rule-looking prefixes remain literal inside an owned
heading, quote or explicit paragraph. Flat list shortcuts retain their usual
behavior. After a successful item indent/outdent, Undo removes subsequent typing
first and then the item move.

Complete heading copies and Cuts retain the heading level. Partial text stays
inline. Mixed heading/list copies preserve their selected children and trailing
text, including ordered starts and nested headings. A whole-item selection keeps
its marker; an unselected visible marker is excluded under the native selection
policy. Heading-containing selections offer semantic HTML when the complete
export has no resource/warning limitation. Native-fragment and HTML paste retain
parsed block roles and remain undoable.

The combined application source passes the complete 385-test Mac suite before
a version/documentation-only bump. Exact regression baselines, focused gates
and the final source hashes are recorded with the build artifacts. The local
DMG is ad-hoc signed and non-notarized, for arm64/macOS26+. Mounted payload,
bundled guide, signature and complete private download checks are recorded in
preview120-handoff.json after packaging.

List-owned headings and quotes still open in editable Source mode while broader
structural replacement, quote/range/card and clipboard acceptance is completed.
These guarded-core repairs do not enable full rich admission. Installed
keyboard/IME and pointer QA, displayed performance, copied-vault cross-client
acceptance and production delivery remain open. AI is deferred, iOS is unchanged,
and the complete folders sidebar remains hideable and restorable.


## Clipboard and vault identity repairs — Preview121

This local preview packages containers177–179 and the identity180 repair. A
partial selection in a later item-owned heading follows the existing native
inline-text copy/Cut policy. Cross-block Delete/replacement keeps the starting
heading/quote role. Text-only paragraph/list/mixed paste joins the receiving
inner block without promoting its existing children; explicit bold survives.
These are guarded-core repairs: item-owned headings/quotes still open in Source
until remaining paste/card, lifecycle and input acceptance is complete.

The shared vault identity lookup reads device/inode directly. The CLI readiness
case that previously stalled in a Foundation extended-attribute query completed
after this change. This does not establish that every provider/startup stall is
resolved. All 260 tests in the scoped desktop gate passed; the thirteen AI/chat
classes were excluded per the current deferral. The interrupted AI-inclusive
run remains recorded separately. Full desktop parity is still unproven.

Preview120 received installed QA on disposable copies for folder-sidebar
hide/restore, Portuguese acute composition, table/code editing, actual Kanban
drag and reviewed history Undo, and window save/reopen. That evidence belongs
to Preview120; Preview121's installed checks must be recorded separately.
Broader IME, VoiceOver/focus, cross-app clipboard, displayed large-vault
performance, cross-client write/reopen and production delivery remain pending.
This arm64 macOS26+ DMG is ad-hoc signed and not notarized.


## Native toolbar boundary repair — Preview122

Preview121's installed smoke exposed collection/tab/inspector headers hidden
beneath the native titlebar. Preview122 adds a divider between the toolbar and
scaled workspace, keeping the split views in the usable content area without
a large blank inset. The stable editor subtree and entirely hideable folder
sidebar remain intact. Tasks and External Notes use the same corrected canvas.

The exact final regression fails sixteen header-bound checks on the old canvas
and passes after the repair. All 261 scoped desktop tests pass; thirteen AI/chat
classes remain deferred. Native Debug QA verified visible headers, sidebar
hide/restore, Tasks/External Notes, a 1000-point-wide note window, native window
zoom and quit/reopen on an isolated copy of a synthetic vault. Both notes stayed
byte-identical. Mounted/release-app checks are a separate handoff record.

Full editor admission, broader installed clipboard/IME and drag/drop, displayed
performance, cross-client write/reopen and production delivery acceptance
remain open. This Apple Silicon macOS26+ local DMG is ad-hoc signed and not
notarized. It is not the production replacement; AI work remains deferred.


## First responsiveness pass — Preview123

Release profiles on a synthetic 1001-note vault showed repeated collection
filtering/frontmatter parsing in the main-thread view-update path. Preview123
reuses per-window collection results for unchanged note/filter/query/scope
inputs. Relative-date caches include their calendar/day boundary. A Mac-only
parsed-note cache uses exact UTF-8 keys and is bounded by count and memory cost;
oversized notes retain the direct parser path. Unchanged inventories avoid
replacing published arrays. Exact note and path bytes remain authoritative,
including canonical-equivalent Unicode spellings with preserved timestamps.

The final non-AI desktop gate passes 262 tests. It includes cache freshness after
an external property edit/refresh, exact BOM/CRLF/Unicode reads, and the
Unicode-byte snapshot regression that failed on the initial refresh guard.
The thirteen AI/chat classes remain deferred. There are no timing assertions
or test-only production seams. Only the Mac parsing branch changed.

The initial collection-cache-only experiment gave modest end-to-end gains, so
it was not treated as a complete fix. Final Release profiling and installed
checks are separate handoff records. Large-vault/provider behavior, sustained
typing, cold open/save, cross-client and broader desktop acceptance remain open.
This preview is an early performance repair, not full responsiveness acceptance.

This build also includes the guarded quoted-paragraph paste repair: paragraph
bodies join inside an existing item-owned heading/quote while bold and explicit
inline breaks survive. The final regression fails 192 checks before repair; all
29 clipboard tests then pass. Those blocks still open in Source publicly.

The entirely hideable folder sidebar and Preview122 toolbar boundary repair
remain. This Apple Silicon/macOS26+ DMG is ad-hoc signed and not notarized.


## On-demand block menu and responsiveness — Preview124

Release profiles on a synthetic 1001-note vault showed repeated collection
filtering/frontmatter parsing in the main-thread view-update path. Preview124
reuses per-window collection results for unchanged note/filter/query/scope
inputs. Relative-date caches include their calendar/day boundary. A Mac-only
parsed-note cache uses exact UTF-8 keys and is bounded by count and memory cost;
oversized notes retain the direct parser path. Unchanged inventories avoid
replacing published arrays. Exact note and path bytes remain authoritative,
including canonical-equivalent Unicode spellings with preserved timestamps.

The table/code popup also uses one fresh block snapshot per opening, retaining
insert/edit actions and their source ranges without discovery during typing.
Its native control follows the toolbar theme, enabled state and canvas zoom.
The real-popup owner checks current requests, rebuilding after edits and stale
choice refusal.

The final non-AI desktop gate passes 263 tests. It includes cache freshness after
an external property edit/refresh, exact BOM/CRLF/Unicode reads, and the
Unicode-byte snapshot regression that failed on the initial refresh guard.
The thirteen AI/chat classes remain deferred. There are no timing assertions
or test-only production seams. Only the Mac parsing branch changed.

The initial collection-cache-only experiment gave modest end-to-end gains, so
it was not treated as a complete fix. Final Release profiling and installed
checks are separate handoff records. Large-vault/provider behavior, sustained
typing, cold open/save, cross-client and broader desktop acceptance remain open.
This preview is an early performance repair, not full responsiveness acceptance.

This build also includes the guarded quoted-paragraph paste repair: paragraph
bodies join inside an existing item-owned heading/quote while bold and explicit
inline breaks survive. The final regression fails 192 checks before repair; all
29 clipboard tests then pass. Those blocks still open in Source publicly.

The entirely hideable folder sidebar and Preview123 toolbar boundary repair
remain. This Apple Silicon/macOS26+ DMG is ad-hoc signed and not notarized.


## Batched inventory reads — Preview125

Mac vault scans now prepare file presenters in batches of at most 256 notes,
then read each file through the same coordinator. Every scan still reads current
UTF-8 bytes; there is no timestamp-based content cache and save transactions
still compare fresh disk bytes. iOS retains its existing scan path.

The optimized synthetic 1001-note IO-helper probe measured about 0.07–0.09
seconds per batched read, compared with about 0.50–0.84 seconds using individual
coordinators. These are helper timings, not installed UI latency or provider
acceptance. The existing non-AI desktop gate passes 263 tests. Installed Release
checks are recorded separately. AI/chat remains deferred.

The fully hideable folder sidebar, on-demand table/code menu and earlier editor
repairs remain. Large-note serialization, cold opening, network/cloud providers,
cross-client and sustained installed/IME acceptance are still open. This Apple
Silicon/macOS26+ test DMG is ad-hoc signed and not notarized.

### bulk404 installed paired bulk history

Fixed the fitted bulk relation picker collapsing its target viewport to zero
height. Installed Add/review/Cancel, paired hidden inverse updates, stale Undo
atomic refusal, refreshed Undo/Redo preserving later source/target metadata, and
restart receipt review pass on an owned fixture. Bodies/BOM/CRLF and unrelated
files survive. Internal app rebuilt/signed at unchanged 0.3.85/build125; no DMG.
Evidence: artifacts/native-macos/bulk404/verification.json. Remaining acceptance
is tracked in docs/native-macos-non-ai-acceptance.md; no full-parity claim.

### features406 task lifecycle acceptance

Installed list/category creation, task creation/editing/scheduling, due clearing,
completion/reopening, list moves/rename, filters, supporting-note save/navigation
and restart persistence pass on an owned fixture. Protected notes and unknown
task data survive. Destructive management Apply and provider/keyboard/accessibility
routes remain separately tracked. Evidence: artifacts/native-macos/features406/verification.json.
The user accepts performance for now; further profiling stops and feature coverage
is the current priority. Performance405's equivalent scan/storage changes pass the
99 editor owners and are in the current internal app, with no version bump/DMG.

### features407 external files and document connections

Installed external connect/save, rename following, missing/Locate, stale edit
protection, exported/restarted recovery and reviewed independent vault copy pass.
Document original connection, preview, context editing, replacement, detach/Cancel
and retained-file/restart behavior also pass. A root-copy navigation bug was fixed:
root notes use All Notes rather than an empty physical Inbox collection. Its
extended navigation owner fails on baseline; four affected owners pass after.
Internal Release rebuilt/signed at unchanged 0.3.85/build125; no DMG. Evidence:
artifacts/native-macos/features407/verification.json. Provider/mapping/resource-
heavy and multiwindow routes remain in the concrete acceptance checklist.

### features408 Trash and history acceptance

Installed note Trash/restore, revision Trash/restore, frozen-image preview, old
revision promotion, automatic-history label/Keep/comparison/resource restore and
cleanup/clear-review Cancel pass on an owned fixture. A deleted selected revision
no longer leaves an unlisted preview/action active: the browser selects current
after reload. Seven recovery/history owners and direct installed before/after
verification pass. Protected image/peer/shared bytes survive. Internal app rebuilt
and signed at unchanged 0.3.85/build125, no DMG. Evidence:
artifacts/native-macos/features408/verification.json. Folder/provider/large paging,
installed destructive Apply and broad keyboard/accessibility remain separately tracked.


## Feature acceptance — note links (features417)

Installed QA on the existing features414 signed Release app verifies picker
keyboard selection and dismissal, insertion Undo/Redo, relative heading-target
and styled multiline stable-link navigation, note-preview Close/reopen/Open,
missing-note review Cancel/Create, unique identity/backlink and restart
persistence. Source BOM/CRLF/foreign metadata and original link spellings survive;
untouched target/manifest bytes and every post-creation file hash survive restart.
See artifacts/native-macos/features417/verification.json. No new build or DMG.
Physical IME/VoiceOver and two-window preview updates remain pending. Settings416
also tried the separate app-menu Settings scene; the automation service pipe
closed again, with unchanged fixture/preferences. This is a tooling blocker,
not evidence of an app crash or accepted Settings/CLI/relation-repair UI.


## Attachment feature repairs — features418

Add file now commits through a scoped editor transaction, so importing an image
or file supports one Undo/Redo and keeps earlier edit history. Installed QA
reproduced the previous Undo no-op, then verified the repair including an earlier
text edit and two Undo/Redo steps. Ordinary local non-Markdown attachment links
now open the existing native file preview rather than failing as note links.
Installed saved text-file preview succeeds after restart with Unicode contents.
Shared image occurrence review/Cancel/removal and reviewed Undo preserve the
peer note and resource. Imported payloads are exact and every final vault hash
survives restart and preview. See artifacts/native-macos/features418/verification.json.

The clipboard owner set passes 30 tests; the extended heading/file-link owner
passes after its two baseline preview failures. Both internal Release builds and
final signatures pass. No version bump or DMG. Final aggregate, provider failure
and interruption cleanup, two-window resource changes and physical input remain
open. This is concrete attachment evidence, not full-parity acceptance.


## Feature acceptance — multipage export/print (features419)

Installed QA on features418 exports an owned note as PDF, Word and self-contained
HTML with visible properties, image, 12 paragraphs, 45 table rows and 30 code
lines. All marked content survives; Word/HTML embedded image pixels match the
original. Nine exported A4 PDF pages were visually inspected. Native WebKit and
Quick Look provide HTML/Word layout readback. The native print panel shows nine
pages and Save as PDF works without selecting a printer or sending a job.
Print omits properties as intended. Original fixture files stay exact and both
app processes quit normally. See artifacts/native-macos/features419/verification.json.

Narrow PDF columns wrap some values without dropping content. Direct Word/Pages
rendering, provider output failures/interruption and physical printer jobs remain
unverified; Pages first-run terms were not accepted. Cmd-P was inconclusive; More
→ Print is accepted. No source change, rebuild, version bump or DMG was made.

## Native Print keyboard entry point — features425

File → Print and Command-P now use the existing frozen current-draft print
flow. Printing a hidden retained note while browsing Gallery is refused;
returning to the note restores the action. Existing snapshot/export owner
coverage passes (2 focused checks), and the Gallery regression fails with the
earlier guard. Installed shortcut, File menu, Cancel/focus return and disabled
Gallery action are verified on the optimized internal app, with original fixture
bytes exact and normal quits. No version or DMG change. The final aggregate is
still pending for this change; features422 remains the prior 283-check pass.
See `artifacts/native-macos/features425/verification.json`.

## Saved-link shared format and editable URL boundary — features426

The real-file web-owner→native→web-owner→native round trip passes saved-link IDs,
URL metadata, annotations and links.json, including native creation and retained
ordinary prose/code. Installed readback exposed the managed URL repeated in the
editable note; Rich and Source now hide that paragraph while saving/exporting it
once. Code/table and attachment snapshots use the same editable body. Lifecycle
and menu regressions fail on the earlier behavior; 30 clipboard owners and the
final 3 lifecycle/menu/export owners pass. Installed annotation/code-sheet/file
import and Undo, ordinary-note switching and restart preserve original files
exactly. The internal app is features426, still 0.3.85/build125; no new DMG. Live
web/provider transport and two recorded numeric-host/backslash normalization
edges remain outside this proof. Final aggregate for 425/426 is pending.
See `artifacts/native-macos/features426/verification.json`.

## Transfer app-wide desktop settings — features427

In React/Tauri Zerus, open Settings → Editor → Export desktop settings. Save the
JSON file, then in Zerus Native choose File → Import Desktop Settings and review
it before Apply settings. Cancel leaves current preferences intact.

The export carries appearance, light/dark colours, named themes, date format,
interface zoom, writing width/alignment, code-block preference and note-link
shortcuts. Matching named palettes are replaced; other native named palettes and
future colour fields are kept. If those native preferences change after review,
Apply refuses and asks for a fresh import. Malformed, oversized or unsupported
exports make no changes. Vault contents and account/connection data are not in
the app-wide portion of this file. Features430 also includes per-vault default
folder, folder order, keep-open choices and subtype visibility, reviewed against
the currently open native vault. Existing native tabs, filters and drafts are kept.
Companion pin/archive metadata migration remains separate.

The actual web export function passes its file to the compiled native importer
on an isolated preferences suite. The web's full suite reports 709 passed and
one existing skip; the two focused export tests and native import/palette owners
pass, as do TypeScript checks. A broader live-colour owner fails in the macOS
Vision E5 model loader; its result is retained separately from the passing import
checks. Installed review/Cancel keeps all eight destination keys exact; Apply imports
the expected values, palettes and named theme while retaining editor text and
Undo. A normal restart retains the import. The original eight native preferences
and the fixture note bytes are restored exactly after QA. Both app processes quit
normally. The optimized internal app and nested signatures verify; no new DMG or
version change. Evidence: artifacts/native-macos/features427/verification.json.

## Sidebar folder ordering — features428

Folder context menus now offer Move up / Move down among siblings. A folder's
children travel with it; drag/drop uses the same owner with a process-local typed
payload and the original workspace, inventory and order. Ordering does not change
paths or note bytes. Its per-vault Mac preference is separate from per-window
navigation so tab/filter saves cannot overwrite it; peer windows adopt new order.
New folders follow ranked siblings, rename remaps paths and Trash removes their
ordering entries. Existing sidebar hide/show controls are unchanged.

The pinned React tree/order owner produces the same root/child fixture outputs.
Native owners cover provider round trip, sibling-only boundaries, subtree
preservation, stale scopes, busy/sheet state, peer windows, per-vault isolation,
reopen, rename and Trash/restore. A final review found canonical String equality
in the new cache could retain old Unicode path bytes; the regression failed on
the earlier cache and now passes with byte-exact cache invalidation, row IDs,
lookup and scope comparisons. Four final native owners pass. No timing test or
test-only production seam was added.

Installed Move up/down works for roots and children, retains collapse state and
editor Undo, and persists after restart. All six original notes and every vault
file across restart remain exact. One physical pointer drag returned unchanged
order; real drag delivery remains unverified, distinct from the passing typed
provider/owner checks. The final byte-identity optimized app reads back the saved order and verifies
complete sidebar hide/restore without losing it. Three owned app processes quit
normally; the actual app declares the folder type as public.data, and its nested
signatures verify. No version or DMG change. Evidence:
artifacts/native-macos/features428/verification.json.

## Finder document opening (features452/453)

Features452/453 adds the missing macOS Finder/Open With entry point. Alternate
Markdown, PDF, office and generic document declarations preserve existing default
applications. AppKit routes document events to the receiving workspace, retaining
cold-launch events until restoration and deferring opens during busy work/reviews.
Existing vault notes open in place; outside Markdown uses the editable original
connection; other documents create/reuse a local-original file note in the default
folder. Two real workspace/file owners pass, including configured destinations,
batch/repeat handling, dirty-save and receiving-window sheet deferral.

Installed Finder testing first exposed absent SwiftUI document delivery, then a
cold-start CancellationError from the view task's lifetime. The AppKit bridge and
independent post-restoration drain repair both. Warm Finder opens show the existing
vault note, editable outside Markdown and actual document preview. Repeating the
document keeps one connection note. Finder then launches the closed repaired app
and displays the requested outside Markdown original without an alert. All four
pre-existing files remain byte-exact, including BOM/CRLF/foreign metadata; normal
Quit is verified. No DMG, version, iOS or default-association change. Multi-file
Finder transport and multiple-window targeting are not separately accepted.
Evidence: `artifacts/native-macos/features453/verification.json` and
`artifacts/native-macos/features453/final-originals.json`.


## Finder multiwindow and batch acceptance (features454)

Features454 extends the installed Finder checks without source changes or a new
build. With two owned same-vault workspaces, Finder opens Work/Inside.md in the
most recently active window (workspace-AppWindow-3); the other window
(workspace-AppWindow-1) retains its Original 452 document and preview. A real
Finder selection of the original TXT and outside Markdown opens as a batch,
keeps the first document visible, and reuses the existing note and external
record. All four pre-existing files and the connection-note bytes are exact;
normal Quit and process exit are verified. Closed-window observation can
reactivate a workspace through the UI tool, so zero-window delivery is not
independently accepted. Distinct-vault routing remains separate.
Evidence: `artifacts/native-macos/features454/verification.json`.


## Finder receiving-vault isolation (features455)

Features455 accepts distinct-vault Finder delivery in the installed app. The
active second window uses OtherVault455 while the peer keeps the original vault.
Opening the peer vault's Markdown presents an editable external original without
switching the receiving vault or adding a note there. Opening a TXT adds one
local-original connection note only to the receiving vault, with an independent
note ID. The peer retains its original document and preview. All pre-existing
files in both vaults, plus the outside Markdown/TXT originals, remain byte-exact.
Normal Quit and process exit are verified. No source/test/build/version/DMG
changes. Evidence: `artifacts/native-macos/features455/verification.json`.


## Native artifact and README readiness (features456)

Features456 reviews README against the current native app and replaces stale
preview chronology with current features, source-mode limits, scope, commands,
dependencies and packaging requirements. The artifact verifier now checks the
actual delivered Finder document roles/extensions/Alternate rank and both native
drag declarations' public.data conformance. The unchanged installed signed app
passes. The old verifier accepts seven independently re-signed malformed bundles;
the new verifier refuses all seven for the intended metadata reason. The first
unsigned-mutation probe is superseded because signature errors were unrelated.
JavaScript syntax, platform configuration and diff checks pass. Release preflight
finds Developer ID and notarization authentication available; native production
feed URL/public key are missing. No app build, DMG, version or publication change.
Evidence: `artifacts/native-macos/features456/verification.json`.


## Delayed first list paragraphs (features457)

Features457 admits ordinary parser-owned list paragraphs whose body begins after
an otherwise empty marker line. The first body renders on the native marker row
rather than below a spurious empty bullet; untouched multi-line source is reused,
while edits save ordinary list spelling. Bare markers are normalized only when
the parser proves a delayed first paragraph. Existing bare-empty/unsupported
admission controls remain guarded. Six sources across LF/CRLF/CR exercise root,
numbered, quoted, nested and formatted bodies through hosted workspace editing,
Save and Rich reopening. The exact final owner fails 18 intended assertions on
original production; three affected owners pass after repair, followed by all
100 document and 30 clipboard checks. The initial setext-ambiguous nested fixture
was corrected and both final baseline/pass use its canonical child-list spelling.

The optimized signed app opens all four installed QA forms in Rich text with no
extra empty bullet. Save, Undo and Redo produce exact expected bytes; unedited
forms, BOM/CRLF, foreign metadata and the control are preserved. A final Undo
restores both original notes byte-exactly, and fresh restart retains Rich text
and selection. Both sessions exit normally. Supported item-owned headings and
quotes were already admitted; README/guide opening summaries were corrected to
remove their obsolete Source limitation. No AI, iOS, version, DMG or publication
change. The broad non-AI gate's unrelated Vision limitation remains separate.
Evidence: `artifacts/native-macos/features457/verification.json`.


## Finder delivery after closing the last window (features458)

Features458 accepts Finder delivery to a confirmed windowless running app.
After Command-W, the existing CUA app binding returns noWindowsAvailable while
the owned process remains running. Finder Open With then displays the requested
Work/Control.md in a workspace through that same binding, without getApp or a
new launch. PID/executable/start time remain identical across delivery. Both
original fixture notes are byte-exact, normal Quit is observed, and the process
exits. This supersedes the zero-window observation limit in features454/455.
No source/test/build/version/DMG changes were needed.
Evidence: `artifacts/native-macos/features458/verification.json`.


## Google Drive File Provider save and remote readback (features460)

An isolated synthetic vault in the connected Google Drive File Provider opens
and edits through the installed native app. Independent Drive API downloads
match the original note before editing and the exact expected saved bytes after
upload, including UTF-8 BOM, CRLF and foreign frontmatter. The independent remote
control and local control remain byte-exact. Normal Quit and a fresh native
process reopen the edited note in Rich text with its foreign property intact;
both owned processes exit normally. The synthetic cloud folder is retained.

This accepts actual Google Drive File Provider upload/native-save/re-upload and
native restart, without claiming account/network interruption, competing remote
writers or the legacy Drive-reference/API path. No personal documents were
modified, and no source/test/build/version/DMG changes were needed. Evidence:
`artifacts/native-macos/features460/verification.json`.


## Current integrated non-AI gate (features461)

A fresh Debug build-for-testing and flat enumeration cover the current sources,
including Finder warm/cold delivery and delayed first-list-paragraph editing.
Of 293 enumerated non-AI checks, all 286 executed checks pass in four fresh
processes: appearance 2, collections 5, workspace 57 and remaining non-AI 222.
Exact test identifiers match the scoped enumeration, with no skips or duplicate
executions. Source, test, package, compiled binary and configuration hashes are
unchanged throughout the run. The same thirteen AI classes remain deferred.

The seven diagnosed Apple Vision environment nonpasses from features451 are
explicitly retained as unresolved and were not repeated unchanged. They are not
counted as passing or silently removed from the full 293-check inventory. Thus
features444 remains the historical complete green aggregate; features461 is the
current integrated scoped pass, not a complete green gate or installed/release
acceptance. No source/test/version/DMG changes. Evidence:
`artifacts/native-macos/features461/verification.json` and
`artifacts/native-macos/features461/scoped-current-coverage.json`.


## Installed collection keyboard selection (features462)

In an isolated five-note fixture, Select followed by Command-A selects all five
filtered collection members in List, Gallery, Kanban, Table and Calendar. Escape
clears selection in every mode. Gallery and Calendar search fields retain text
focus: Command-A selects the query text rather than notes. Returning to collection
selection with a one-note query selects only that matching member. Calendar
Select All includes filtered members outside the displayed month; the selected
count is five while four cards are visible in November.

Every original note, schema, image and other fixture file remains byte-exact.
Collection mode, grouping and date choices are device-local for All Notes.
Normal Quit exits zero.
This accepts those keyboard selection routes, not full VoiceOver/dictation,
arrow-key card navigation or physical drag delivery. No source/test/build/version
or DMG change. Evidence: `artifacts/native-macos/features462/verification.json`.


## Installed Find in Note and replacement (features463)

Command-Shift-F opens the native Find bar in Rich text and Source. A three-match
query reports three occurrences; next highlights the third and previous returns
to the second. Replace All saves exactly the three expected replacements while
preserving BOM, CRLF, foreign metadata and inline bold. One Undo restores the
original. In Source, a pasted accented query selects its exact café match.
Closing Find, returning to Rich and typing/Undo all work. Both original files
are byte-exact after normal Quit, which exits zero.

CUA typeText emitted caf for café; the accented query therefore used paste and
does not establish physical IME acceptance. No source/test/build/version/DMG
changes. Evidence: `artifacts/native-macos/features463/verification.json`.


## Installed frozen-image history paging and retry (features464)

A synthetic checkpoint with 17 distinct frozen PNGs pages through 1–8, 9–16
and 17–17, then back to 1–8. First/last controls disable at the correct bounds.
Screenshots show distinct saved pixels on each page, including the final image.
Temporarily withholding only the ninth synthetic blob produces a named warning
on page two. Restoring that exact file and Reload saved images clears the warning
and displays its original pixels without closing history. Off-page image
placeholders remain expected while only the selected page is decoded.

The live note is never restored or edited. All original fixture files, including
the checkpoint and 17 blobs, are byte-exact after normal Quit; the process exits
zero. This accepts small-image multipage browsing and local unavailable-file
retry, not large-image memory, account/network outages or retention/purge Apply.
No source/test/build/version/DMG change. Evidence:
`artifacts/native-macos/features464/verification.json`.


## Vision oracle diagnosis and rejected substitution (features465)

Vision text recognition is used by the screenshot-based tests in
MacAppearanceTests, MacCollectionTests and MacWorkspaceTests, not by shipped
native-macos source. The seven nonpasses therefore do not identify a shipped
OCR feature failure. They still leave their specific UI contracts unverified
on this environment.

A bounded attempt to read the footer through the actual in-process accessibility
tree failed: the offscreen NSHostingView reports an AXGroup with no children.
Both attempts fail the five footer assertions rather than manufacturing a pass.
That replacement was rejected; the original test is restored byte-exactly, and
all source/test hashes again match features461. A restored build-for-testing
succeeds. No assertions were deleted or skipped, no production code changed and
none of the seven environment checks is counted as passed. Evidence:
`artifacts/native-macos/features465/verification.json`.


## Code blocks back to literal text (features466)

Paragraph → Turn code block into text now provides the conversion already
available in the React editor. The native command keeps literal text and line
breaks, removes code styling, preserves quote/list ownership and commits one
Undo step. Compact item-owned fences fill the existing empty marker row instead
of leaving a separate empty head. The command is available for existing blocks
regardless of whether new code-block creation is enabled.

The owner covers nine shapes with LF/CRLF: fenced, indented, quoted, list-owned,
compact, nested quote, empty blocks, blank/trailing lines and task-like literal
text. Expected Markdown is handwritten and parent arrays come from an independent
swift-markdown traversal. The exact final test fails 74 assertions on the old
implementation. All 131 current document/clipboard checks pass after repair,
including selection Undo/Redo and preservation of earlier prose Undo.

The optimized signed internal app passes the actual menu action for root and
list-owned code, exact Save, two-step Undo/Redo, and Rich reopening with further
typing/Undo. BOM, CRLF, foreign metadata and the control remain intact; every
fixture file is exact across restart. Both processes exit zero. Existing React
preview and private proxy return HTTP 200. No AI/iOS/version/DMG or publication
change. The earlier features461 aggregate predates this implementation; its
seven Vision checks remain unresolved. During acceptance, collection excerpts
were observed joining words across inline HTML breaks; that separate issue is
recorded for the next repair. Evidence:
`artifacts/native-macos/features466/verification.json`.


## HTML-break separation in shared excerpts (features467)

Collection snippets now treat parsed br tags as word separators instead of
joining adjacent text. Inline formatting tags retain their normal adjacency;
inline/fenced code containing literal HTML remains literal. The shared parser
change fixes List/Gallery/search excerpts on Mac and the iOS collection preview
without rewriting Markdown or adding a parser per card.

The new file-backed Mac owner covers ten forms, including tag spelling,
attributes, repeated breaks, linked/styled text, formatting adjacency and code.
A test-only async-autoclosure compile error was corrected before the meaningful
baseline. The corrected baseline fails the two canonical br expectations
(FirstSecond versus First Second); the repaired owner and two collection
controls pass. Three focused Mac search checks and the existing iOS collection
owner also pass. The Vision-based screenshot owner was not weakened or counted
as passing.

The optimized signed Mac app shows First Second and bold Next. in List and
Gallery, including after restart. The updated iOS binary is installed in the
isolated Zerus Native Move QA simulator, whose vault was chosen through Files.
Its collection card shows the same corrected excerpt. The screenshot is retained
and the affected screen remains open in the Device panel. Both original notes
on each platform retain exact bytes, including BOM/CRLF/foreign metadata. Mac
sessions exit normally. Both web-preview routes return HTTP 200. No version,
DMG, iOS archive or upload change. This closes the excerpt follow-up found in
features466. Evidence: `artifacts/native-macos/features467/verification.json`;
iOS preview: `artifacts/native-macos/features467/ios-preview.png`.



## Table row/column actions and focused-cell targeting (features468)

The native table sheet now moves rows up/down and columns left/right, inserts
rows below and columns after the focused cell, and narrows a column. Column
moves carry alignment and width metadata. Promoting an imported wider body row
to the header exposes its extra cells with default metadata instead of dropping
them. Pointer and Tab focus both select the action target, and moved cells keep
focus at their new coordinates. Cells have row/column accessibility labels.

Installed QA caught a pre-existing targeting defect in the initial candidate:
a caret in the last body row still left the first header selected. Replacing
the tap-only tracking with actual field focus fixes both mouse and keyboard
selection. This was observed and rechecked in the installed app; no automated
focus-regression baseline is claimed.

The extended existing table-sheet owner checks handwritten reorder and wider-row
promotion results through real Rich/Source draft application, earlier edit
history, Undo/Redo and stale refusal. Four final affected checks pass; the
optimized signed app builds and installs. Installed row/column moves and width
changes save exact expected BOM/CRLF bytes with foreign metadata and surrounding
prose preserved. Cancel discards combined moves and after-insertions. Two Undo
actions restore the exact original, two Redo restore the final table, and Rich
reopening plus the table sheet retain the saved order/widths. Every fixture file
is unchanged across restart, the control note stays exact, and both sessions
exit zero. No version, iOS, DMG or publishing change. This is affected coverage,
not a fresh full-suite claim. Evidence:
`artifacts/native-macos/features468/verification.json`.



## Current non-AI integration snapshot (features469)

A fresh Debug build/enumeration includes the code-to-text, shared excerpt and
table-action changes. Across four fresh processes, all 288 selected non-AI
checks pass: appearance 2, collections 6, workspace 57 and remaining owners 223.
Every started/passed identifier matches the expected scope exactly, with no
skipped or duplicate checks in that scope. Compiled products, configuration,
sources and tests retain their frozen hashes throughout the run. The same
thirteen AI classes remain deferred; seven diagnosed Vision environment checks
are explicitly unresolved and not counted as passing.

This is not a clean complete xcresult aggregate. The first three result trees
are intact. All 223 checks in the last process pass and Xcode reports TEST
EXECUTE SUCCEEDED, but disk-full diagnostics collection leaves its result bundle
without test nodes. Exact started/passed identifiers and the zero-failure
summary were independently verified from the complete XCTest log after space
was recovered. Only regenerable indexing, module and intermediate-build caches
were removed; built products, source, vaults and all evidence were preserved.
No test was weakened or reclassified. The initial copied-test-path/enumeration
preflight errors ran no tests and are retained separately. Evidence:
`artifacts/native-macos/features469/scoped-current-coverage.json`.



## Second-window image Undo reproduction (features470; resolved by features471)

Installed multiwindow QA confirms that saving an image change in one window
closes another window's stale image sheet; reopening reads the newer caption
and never commits the stale draft. The saved note retains BOM/CRLF, foreign
metadata, title and surrounding prose, and the original PNG/control note remain
exact. Edited Markdown canonicalizes the image URL with angle brackets.

A remaining defect was observed: a fresh image-caption edit in the second
SwiftUI window saves correctly, but native toolbar Undo and focused Cmd-Z do not
restore its prior caption. Ordinary typing Undo still works. Restarting into a
single window gives exact image Undo/Redo; opening a fresh second window then
reproduces the failure without the earlier stale-sheet sequence. Both processes
exit zero. No code repair is claimed.

Five focused diagnostics (field focus, an AppKit sheet, workspace peer refresh,
explicit polling and two hosted views) all pass on the unmodified implementation.
They invoke the image application directly and do not reproduce the installed
WindowGroup/menu-action path. Those diagnostic test edits were restored exactly,
with copies/logs retained only in the artifact folder; no test-only seam or
production change was added. Rebuild tests before reusing DerivedData after the
restoration. The next action is to trace command/Undo-manager and coordinator
lifetimes in the installed second-window path, then repair the demonstrated
owner. This issue keeps D05 image editing open. No new build version, DMG, iOS
change or release. Evidence: `artifacts/native-macos/features470/verification.json`.



## Live workspace document bridge preserves Undo (features471)

Features471 resolves the installed second-window image Undo defect recorded in
features470. A temporary optimized-app trace showed correct command routing and
Undo registration, followed by two representable loads: an obsolete queued
Markdown snapshot and then the new value. Those reloads cleared the history.
The trace recorded identities and hashes only and is removed from final source
and the installed app.

The workspace now supplies a live reader for current Markdown and source mode.
Native view creation, reuse and updates resolve that document only for the
current note/vault, rather than replaying the captured view value. A genuine
external replacement still reloads and clears old history; this is not a delay
or a rule that ignores outside changes.

The owning hosted regression supplies the delayed view snapshot observed in the
trace and checks literal LF/CRLF image output, Undo/Redo, external replacement,
mode changes and stale-image refusal. Its runtime baseline retains the old
bridge behavior with only the new reader/caller interface scaffold, and fails
18 assertions. The repaired owner passes; all 135 affected checks pass (102
editor, 30 clipboard and three workspace history/refresh checks).

The optimized signed internal app passes the original second-window sequence:
image Apply/Save, exact original-byte Undo and exact edited-byte Redo. A genuine
peer save closes the other window's stale image draft; a fresh edit there also
has exact Undo/Redo to the peer version. Reopening shows the saved image and
caption, and every fixture file is unchanged across restart. The PNG/control
note, BOM/CRLF, foreign metadata, image title and surrounding prose are kept.
All acceptance sessions exit zero. Both reference-preview routes return HTTP
200. No iOS, version, DMG or publishing change. Features469's broader snapshot
predates this repair; the seven Vision checks remain unresolved. Evidence:
`artifacts/native-macos/features471/verification.json`.



## All six heading levels and keyboard formatting (features472)

React's shared Markdown editor enables Heading 1–6. Native menus/actions exposed
only levels 1–3 in vault notes and 1–2 in external notes. Both native Paragraph
menus now expose all six, and one shared prefix formatter handles Rich and
Source. Edit → Paragraph style adds Command-Option-1–6 and Command-Option-0 for
Paragraph; commands still require focus in the editable native text view.

The extended existing formatting owner covers six literal prefixes in Rich and
Source, LF/CRLF/CR, inline Markdown, typing, Undo/Redo and independent parsed
Heading levels. An initial test AST lookup accidentally referenced first(where:)
as a function and was corrected before the meaningful baseline. The final test
fails 99 assertions against unchanged production. It also exposed an existing
Source CRLF bug: String.hasSuffix could not recognize the LF half of CRLF, so a
trailing placeholder gained another heading marker. Formatting now uses the
existing line scanner and keeps each row's terminator. Two focused owners pass;
all 110 affected checks pass (102 document and eight external-note checks).

The optimized signed installed app passes menu H4, keyboard H5/H6 and Paragraph,
outline levels, exact Save/Undo/Redo, and Source H5→H4 on a BOM/CRLF note. A
search-field shortcut leaves the background note unchanged. The external editor
shows all six menu choices, saves H6 via menu and H5 via keyboard, and preserves
exact original-file Undo/Redo without changing the vault note. Vault and external
reopening retain the saved levels; every fixture file is unchanged across
restart. Foreign metadata, inline styles, line endings and the control note stay
intact. Both processes exit zero. Reference preview routes return HTTP 200. No
version, DMG, iOS or publication change. Evidence:
`artifacts/native-macos/features472/verification.json`.

The external inline-code and code/table control gap identified by this heading
comparison is completed in features473 above. No extra external Undo failure
was reproduced or repaired in the heading change.


## External-note block controls (features473)

The connected original-file editor now shares the lazy Tables and code menu
and native table/code sheets with vault notes. It adds inline code,
indent/outdent, continue-after-block, code-to-text and horizontal-rule actions.
Commands use the connection presentation identity and current editor content,
so a hidden vault editor or retired connection cannot accept them. Shared block
creation preferences still apply: turning creation off hides Insert code block
without hiding editing of an existing block. Live document reads keep the
external binding aligned with the active Rich/full Source representation; no
additional external Undo defect is claimed.

A real hosted external-view owner exercises Rich and full Source, LF/CRLF,
foreign frontmatter and BOM, exact code/table saves, Undo/Redo, stale-sheet
refusal and retired-session command rejection. The unchanged-app baseline fails
eight assertions for the missing menu and command route. Two focused owners and
all 112 affected checks pass (102 document, nine external, one vault block-menu
owner). Frozen inputs match throughout. The initial test-only actor annotation
compile failure is retained as diagnostic evidence, not a regression baseline.

The optimized signed internal app passes existing-code language/body editing,
table editing in Rich and full Source, inline-code formatting, code-to-text,
three-step Undo/Redo, actual table insertion and exact insertion Undo. Existing
BOM/CRLF and foreign metadata remain exact through replacements/history; new
table syntax retains the shared engine's LF insertion spelling. Creation-on
code insertion was not manually toggled in this check. Reopening the saved
connection keeps the changes; every fixture file/inventory is exact across
restart, the vault control note is unchanged, and both processes exit zero.
No version change, iOS change, DMG or publication. Reference preview routes
return HTTP 200. This closes the block-control follow-up from features472,
not full external-workflow or release acceptance. Evidence:
`artifacts/native-macos/features473/verification.json`.


## Shared web and vault link controls (features474)

The editor now exposes a shared Insert or edit link dialog through the Link
menu and Command-K, in both vault and external notes. Web destinations use the
existing browser-compatible HTTP(S) normalizer. Vault choices save stable note
references; selected display text and mixed inline formatting are retained.
Existing links can be retargeted, renamed when their label is plain, removed
without deleting text, or copied. The last web/note choice is remembered, while
an existing link opens its own destination type. Inline Source edits retain
surrounding metadata and line endings; literal code is excluded.

Native note suggestions and AppKit context editing already existed. This closes
the shared toolbar/keyboard destination-and-label control gap against React;
it is not a claim that native previously had no way to edit an existing URL.
The context menu now has one guarded Edit/Remove/Copy route, replacing duplicate
AppKit entries. Dialog drafts check the editor revision, exact source and
selection before committing, and use the existing Undo transaction and sheet
zoom/theme host. The image-sheet owners remain covered after that host was
renamed for reuse.

The original hosted action baseline fails because no shared dialog opens.
Two focused owners cover real dialog Save/retarget, literal Markdown and parsed
links, Unicode, mixed formatting, note identities, titles, Rich/Source LF/CRLF,
lists/table cells, caret insertion, removal, stale drafts and Undo/Redo. The
installed duplicate-menu finding reproduces three failures in the same native
menu owner before cleanup. All 144 affected checks pass on final frozen inputs:
104 document, 30 clipboard, nine external and one vault block-menu check.

Optimized signed installed checks pass vault Command-K create/retarget,
vault-note selection, external toolbar creation/removal, removal Undo/Redo and
full Source retarget, with exact saved bytes. Reopen preserves both vault and
external destinations; the unrelated target note and every fixture file remain
exact. A final menu-only rebuild verifies unique actions and the shared dialog;
all three app processes exit zero. No test URL was opened or fetched. Copy is
present but clipboard contents were not manually exercised. No iOS, version,
DMG or publication change. Reference preview routes return HTTP 200. Evidence:
`artifacts/native-macos/features474/verification.json`.

## Shared image insertion and remote previews (features475)

Vault and connected original-file editors now share an Insert image dialog for
an HTTP(S) address or a local file, with description, title, dimensions and
aspect-ratio controls. Local files are staged without writing an asset until
Insert, then copied into the vault or chosen external project. The selected
text is replaced in one Undo transaction; stale drafts are refused.

Visible remote images load off the main actor with two active requests per
editor, bounded raster decoding and a limited in-memory transport cache.
Source mode does not fetch them. Requests do not reuse cookies or credentials,
and downloaded images are not written into the vault. Reload image works on
unavailable placeholders and already-loaded images. Paste refreshes image
presentation at its completion boundary; the loader retains its coordinator
through completion while preserving cancellation, current-note and revision
guards. Failure diagnostics omit image addresses.

The affected suite passes 153 checks on the recorded repaired snapshot. The
subsequent loader-lifetime adjustment passes both current loader owners and the
optimized installed pass; these are not a new complete non-AI aggregate.
Regression baselines catch unavailable-placeholder refusal, a repeated loaded
image remaining a placeholder and Reload failing to refetch loaded pixels.
The original installed remote-display failure and intermediate diagnostic runs
remain recorded, rather than being counted as passes.

Installed acceptance verifies local and remote insertion, repeated-image pixels,
404 recovery to new blue pixels through Reload, unchanged bytes and Undo history
after display refresh, and external original-file project import. Save,
Undo/Redo and restart preserve exact BOM, CRLF and foreign metadata, with exact
imported asset bytes. All 24 fixture files remain identical across restart;
vault red/green/blue previews and the external image reopen correctly. One
nested path-input session became misrouted and its owned QA process was stopped
after exact note checks. A fresh process using the visible file list completed
successfully; no product change was made for that input incident.

The complete React editor-control matrix is recorded alongside this evidence.
At this milestone, broader sized-HTML `img` resource discovery/transfer was a
D05 follow-up: insertion transported a Markdown reference and restored size
metadata after the portable path was assigned. Features476 supersedes that
workaround with direct, source-preserving HTML resource transfer. Animated playback and broad SVG-format compatibility
are not established. No iOS change, version increment, DMG or publication.
Evidence: `artifacts/native-macos/features475/verification.json` and
`artifacts/native-macos/features475/editor-control-matrix.json`.


## Sized HTML image resource transfer (features476)

The shared resource scanner now recognizes local `img src` references in sized
HTML images. It uses source ranges to replace only the destination, retaining
attribute spelling, dimensions, title, caption and surrounding Markdown bytes.
Code, comments and image-label examples do not become resources. Mixed existing
percent escapes, HTML entities, Unicode and bracket characters resolve without
double encoding, including when linked resources move between folders.

Image insertion now transfers its actual markup directly; the earlier temporary
Markdown spelling and presentation-restoration workaround is removed. Existing
remote display behavior is unchanged.

The final frozen sources pass 162 affected Mac checks and six iOS resource and
move owners. Regression baselines demonstrate the previously missing image
bytes and mixed-encoding move refusal. These are affected checks, not a fresh
complete non-AI aggregate.

The optimized installed Mac app copies a 240-by-144 HTML image between two
isolated vaults. Save, Undo and Redo preserve exact BOM/CRLF/foreign metadata and
HTML attributes, the imported PNG matches the original, the source is unchanged,
and Redo creates no second asset. The image displays after restart; all eight
fixture files retain their exact hashes.

The updated shared code was built and installed in the visible iOS simulator.
Image management and the original image's native QuickLook show the expected
red pixels. Literal Source-mode paste intentionally prefers text over native
fragments, so that UI path is not portable resource-transfer acceptance; no
provider bug was established or changed. The simulator remains open on the
image preview. Screenshot: `features476/ios-image-preview.png`.

Provider interruption/cancellation, physical IME/accessibility and broader
format compatibility remain separate acceptance work. AI stays deferred; no
version increment, DMG, publication or complete-parity claim.
Evidence: `artifacts/native-macos/features476/verification.json` and
`artifacts/native-macos/features476/editor-control-matrix.json`.

## Current non-AI integration and Settings access (features477–478)

Features478 passes all 303 currently enabled non-AI checks in five fresh
processes: appearance 2, collections 6, workspace 57, remaining non-AI 231 and
previously blocked Vision checks 7. Every identifier matches fresh flat Xcode
enumeration exactly, with no skips, omissions or duplicates. Source, test,
configuration and compiled-product hashes remain unchanged. All five final
result bundles contain complete test trees; all five Xcode commands return zero.
The same thirteen AI classes remain deferred.

The first 231-case run passed every expected case, but Xcode exhausted temporary
disk space while saving its result bundle. Its complete passing log and exact
identifier verification remain recorded. Rebuildable project caches were
cleared; selected historical project bundles were losslessly archived with
per-file byte/hash verification and restoration pointers. Summaries were also
exported before removing 84 old automatic Xcode cache results outside the
project evidence folder. After space was recovered, the same 231 checks passed
again with a complete result bundle. Seven formerly failing Vision checks also
passed without any source/test adjustment; no causal diagnosis is inferred from
that change in environment behavior.

This supersedes the features469 scoped aggregate and features444 older complete
green snapshot for current automated coverage. It is not physical IME,
VoiceOver, pointer delivery, cross-client/provider or production-release
acceptance. No version increment, DMG, source change or publication.

Features477 independently retried installed Settings using the signed internal
app and a synthetic vault. Computer Use returned “native pipe closed before
response” and then “native pipe startup failed.” The process remained alive,
its note bytes stayed exact and only that owned QA process was stopped. This
records an automation-service blocker, not an application crash or an accepted
Settings/CLI/relation-repair interaction. Those installed routes remain open.

Evidence: `artifacts/native-macos/features477/verification.json` and
`artifacts/native-macos/features478/verification.json`. Complete current test
identifiers/results: `features478/complete-current-coverage.json`. Historical
archive manifests and old-cache summary exports are retained alongside it.

## Installed Files-to-Word preview (features479–480)

The native Files workflow accepts a Word DOCX through its actual Add document
picker. Cancel leaves both the source and original note exact and creates no
connection or copied asset. Copy into vault then creates one byte-exact portable
DOCX with a separate annotation note. QuickLook visibly renders the properties,
styled prose, embedded image, table, code and final paragraph of the owned
multipage document.

Expand document / Show notes and Hide document / Show document retain the
annotation editor. After these mode changes, Undo removes only the annotation
text and Redo restores the exact saved note, including its connection metadata.
Normal quit/reopen restores the Files connection, rendered image and annotation.
All eight recorded vault/source files retain their exact hashes across restart.
Both owned QA processes exit normally. No direct Word/Pages or universal Office
format claim is made.

Features479 retried Settings after recovering disk space and resetting the
Computer Use runtime. The same native pipe closed before response; the app
stayed alive and the note stayed byte-exact. Only the identity-checked owned QA
process was stopped. This is an installed verification blocker, not a proved
application crash. Do not repeat that route without a relevant tool/state change.

No product source, test, version, DMG or publication changed. The features478
303/303 non-AI gate remains applicable: all its frozen source and compiled
inputs are still identical. Physical input/accessibility, additional formats,
provider interruption, remaining installed Settings/CLI/repair and final release
acceptance stay separate.
Evidence: `artifacts/native-macos/features479/verification.json` and
`artifacts/native-macos/features480/verification.json`.

## Approved purge, task metadata and native channel preparation (features481/483/484)

After the user's action-time approval, features481 permanently deletes the one
synthetic `Disposable purge QA481` note, its two automatic-history records and
its owned history blob. The separate control note and original shared PNG remain
byte-exact across normal restart. The empty Trash and retained control are
observed in the installed app. This accepts that reviewed note/history purge;
other purge types and provider interruption remain separate.

Features483 applies the two specifically approved metadata changes in the
original Features443 vault: `QA category` is removed from its one assigned task,
then `QA disposable list` is removed and that task moves to General. All three
tasks and supporting-note bytes are retained. Only the approved option/list
metadata, nullable assignment fields and that task's update timestamps change.
Normal restart preserves every resulting fixture file exactly. The initial QA
expectation used empty strings and unchanged timestamps; it was corrected
against the existing NativeTasks contract, with no product change.

The user chose a separate native GitHub Sparkle channel, independent of Tauri.
Features484 provisions the previously absent `zerus-native` Keychain key and
writes only its public key and channel metadata to
`native-macos/update-channel.json`. Production packaging loads that profile
when no native feed/key override is supplied. Both override values must be
provided together; internal builds retain their unconfigured defaults. The
public `pnpm macos:native:channel` command resolves production settings without
building, staging resources or uploading. Two protocol/configuration checks
pass, including the actual preflight command in an isolated directory, invalid
profiles, incomplete overrides and signed appcast/archive tampering.

The first signing-capability check completed after the user approved the
macOS Keychain prompt for Sparkle's sign_update tool. Computer Use could not
access SecurityAgent, so the user performed that authorization directly. The
resulting Ed25519 signature verifies against the configured native public key;
a modified payload is rejected and public Keychain readback still matches.
Signing capability is verified. No private key was exported. No version, DMG, GitHub release, appcast
publication or Tauri updater change is made by this preparation. The current
installed QA app remains unconfigured; the approved production settings take
effect when a configured distribution build is actually made.

Evidence: `artifacts/native-macos/features481/verification.json`,
`features483/verification.json` and `features484/verification.json`.

## Private configured Developer ID candidate (features485)

The current Release app is built with the approved separate native GitHub feed
and public key, without advancing 0.3.85/build125 or creating a DMG. All 365
recorded source/configuration inputs remain unchanged through building, signing
and notarization. The staged app, bundled CLI, Sparkle Autoupdate, Updater and
both XPC helpers are signed with the configured Zerus Developer ID identity;
the delivered-bundle verifier passes the approved channel and nested signatures.

Apple accepts the private notarization submission. The ticket is stapled and
validated, the complete app signature verifies, and Gatekeeper reports
Notarized Developer ID. This closes the earlier unverified Developer ID/helper
and Resources/CLI notarization path for this exact candidate. The 303-check
non-AI application evidence predates only packaging/configuration work; no
Swift application implementation changes are made here, and no new complete
configured-app test suite is claimed.

The exact candidate launches in a synthetic vault with automatic checks disabled
only for that QA process. Its native Check for Updates command starts Sparkle
and reports retrieval failure for the approved unpublished feed. HTTP 404 is
independently confirmed. Cancel returns to the original editor, its BOM/CRLF/
foreign-metadata note remains exact and the app exits normally. This proves
configured startup/error/Cancel, not a production update download or install.

After the user authorizes generate_appcast in macOS Keychain, production ZIP/feed
preparation succeeds using the real zerus-native account. Independent public-key
verification accepts both signatures and the extracted app, including its
notarization ticket and Gatekeeper assessment. These files remain unpublished.
No private key is exported, no GitHub assets/feed are published and no DMG is
created. Documentation is updated after the frozen candidate build; final
packaging must include the then-current guide and README review.

Evidence: `artifacts/native-macos/features485/verification.json`,
`notarized-app-receipt.json`, `notarization.json`, `launch-verification.json` and
`frozen-inputs.json` in that directory.

## Real signed update installation (features486)

An isolated Developer ID baseline with synthetic build124 metadata and a private
HTTPS QA feed updates to the unchanged notarized build125 candidate. The actual
Sparkle UI offers the expected version, downloads and extracts the signed ZIP,
and reaches Install and Relaunch. A read-only synthetic note directory makes
save fail: relaunch is vetoed, the baseline stays running at build124, original
files remain exact, and the unsaved draft remains visible. Restoring directory
write access permits Save and a second Install and Relaunch succeeds.

The relaunched app displays 0.3.85 (125) and the retained draft. Its executable
and app seal match the candidate byte-for-byte, its production GitHub feed is
restored by the installed bundle, and nested signatures, the stapled ticket and
Gatekeeper all verify. Every saved vault file remains exact after normal quit.
The temporary private feed route and loopback server are removed; all previous
Tailscale Serve configuration is restored exactly. This verifies the actual
production signing/notarization pipeline over private HTTPS; no public GitHub
feed, release, version increment or DMG is created. Existing unconfigured
previews still require a first manual configured-app installation.

Evidence: `artifacts/native-macos/features486/verification.json`,
`save-veto.json`, `transport.json`, and features485's production update receipt.

## Settings automation on the notarized artifact (features487)

The configured Developer ID app is a materially different artifact from the
previous ad-hoc QA app, but opening Settings still returns “Sky Computer Use
native pipe closed before response.” The owned app process remains alive and
every saved file in the isolated vault remains byte-for-byte unchanged. No
source change is made. Installed Settings, CLI setup and relation-repair UI
acceptance remain blocked by native Computer Use access; no product crash or
successful inspection is inferred. The owned QA process is stopped afterward.
Evidence: `artifacts/native-macos/features487/verification.json`.

## features488 — stable iOS Source editing and local Apple handoff

An installed iOS handoff probe exposed a mode-change defect: clearing a note
whose advanced Markdown automatically selected Source made the next typed
replacement become Rich text. Literal Markdown was then escaped on save.
NativeTextEditor now distinguishes explicit Source selection from automatic
fallback, retaining the current Source presentation during active replacement.
Explicit mode changes and different documents still take effect. Both vault
and external-note screens use this distinction; no macOS implementation changes.

The hosted real navigation/editor regression fails on the old mode and saved
bytes. All 12 affected presentation, clipboard and navigation checks pass after
the repair. The updated 0.3.107/build57 simulator app saves a chunked literal
replacement exactly, retaining its BOM/CRLF header, foreign metadata, sized HTML
image attributes and original image bytes. LF body newlines are explicitly
entered because the device tool synthesizes CRLF as two return keys; no unchanged
body-line-ending claim is made for a full replacement.

A separate owned fixture is copied locally from the actual iOS-saved vault to
the notarized Mac app. Mac Rich readback, edit, Save, Undo and Redo pass; Undo
restores the exact iOS-saved note bytes. The saved Mac file is returned to the
closed iOS fixture, then the actual app relaunches and opens both edits. Returned
note bytes, image and both control notes remain exact. The updated simulator is
left on the affected Source screen. This is local installed interoperability,
not cloud/provider transport, a physical iPhone check, or complete parity.
No version increment, release publication, new Mac build or DMG.

Evidence: `artifacts/native-macos/features488/verification.json`,
`source-baseline.log`, `source-fixed.log`, `reproduction.json`,
`ios-return-preview.png`, and the saved before/after note files.

## features489 — remove remaining direct Google Drive controls

The user confirms direct Google Drive integration is unwanted. Native iOS File
locations no longer offers a Drive account entry or a per-location Drive folder
picker. The unused OAuth/folder browser and Drive conflict/sync presentation are
removed. The legacy account bridge refuses new requests locally without
constructing an OAuth or HTTP client. Retained records, credentials, cached
working copies and recovery drafts are not deleted. Files/iCloud Drive and
on-device storage remain available; Google OAuth and live Drive verification
are removed from the completion scope.

All 16 affected file-hub, vault-registry, navigation and presentation checks pass.
The updated 0.3.107/build57 simulator app creates a synthetic shared location,
shows only Files-based folder controls, opens the standard folder picker and
returns unchanged after Cancel. The earlier Apple handoff note, image and
control remain exact. The simulator is left on the changed File locations
screen. No macOS code, version increment, release publication or DMG.
Evidence: `artifacts/native-macos/features489/verification.json`,
`files-workflows.log` and `files-only-preview.png`.

## features492 — private notarized DMG install-path acceptance

One private install-test DMG packages the already accepted features485 app; the
app is not rebuilt or re-signed, version0.3.85/build125 is unchanged, and no
public release is created. The current README is reviewed and its hash, along
with the packaged guide snapshot, is recorded. Apple accepts the signed DMG;
its stapled ticket and Gatekeeper assessment verify. Mounted and copied app
executables and seals match the existing candidate exactly.

The mounted app is copied into a new owned Applications subfolder without
replacing existing apps. Its own signature, ticket and Gatekeeper assessment
verify. Actual installed launch, exact note Save, original-byte Undo, Redo,
normal quit and restart pass with a synthetic vault. All six vault files remain
exact across restart, including the BOM/CRLF/foreign-metadata note and control.
All owned mounts are detached. This closes the bounded package-install path;
it does not establish a browser download/quarantine prompt or complete the
remaining Settings/CLI/repair and trusted gesture/input acceptance. The DMG is
private QA evidence, not another user preview or published release.

Evidence: `artifacts/native-macos/features492/verification.json`,
`package-receipt.json`, `install.json`, and `package.log`.
