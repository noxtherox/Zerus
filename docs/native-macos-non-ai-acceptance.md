# Remaining native desktop acceptance, excluding deferred AI work

Audit date: 2026-11-24. Latest packaged artifact: Preview125, 0.3.85/build125.
Current internal app remains 0.3.85/build125 and now includes navigation394,
rules397, the filename-first recovery matching repair in performance399, and the
bulk404 relation-target viewport repair, equivalent scan/storage work in performance405,
features407 root-copy navigation repair, features408 recovery-selection repair and
features409 Locate-preview notification repair and features414 move-history preservation
of unrelated work, plus features418 attachment Undo/file-link preview repairs and features425 native
File → Print / Command-P entry points with the hidden-Gallery-note guard, plus
features426 saved-link editable-body/command-snapshot repair and features427
reviewed app-wide desktop-settings transfer, plus features428 sibling folder
ordering with per-vault persistence and byte-exact path identity, plus features429
browser-compatible saved-link URL identity and features430 reviewed per-vault
preference transfer, features431 compact first-block divider Return handling
and features433 sequential numbered-list presentation with source preservation.
The internal app now also includes features476 sized HTML image resource transfer (162 affected Mac checks, six iOS resource checks, installed cross-vault copy/paste, exact Save/Undo/Redo and restart), features475 shared image insertion and bounded remote previews (153 affected checks on the repaired snapshot, two latest loader checks and installed exact Save/Undo/Redo/reload/restart), features474 shared web/vault link controls (144 affected checks, installed exact saves/history/reopen and final menu cleanup), features473 scoped external-note code/table controls (112 affected checks plus installed Save/Undo/Redo/restart), features472 six-level heading menus/shortcuts in vault and external notes, verified by 110 affected checks and installed exact Save/Undo/Redo/restart, plus features471 live-document bridging, verified by 135 affected checks and installed two-window image Undo/Redo/peer/restart acceptance, and features468 table row/column moves and focused-cell actions (four current affected checks plus installed Cancel/Save/Undo/Redo/restart), features467 shared HTML-break excerpt separation, with current focused Mac/iOS owner and installed previews, and features466 code-to-text conversion; its current affected document/clipboard suite passes 131 checks and installed Save/Undo/Redo/restart. Features478 now verifies all 303 current non-AI checks across five fresh processes,
with exact identifier coverage, no skipped/omitted/duplicate checks and unchanged
compiled/source/test inputs. All five final result bundles are complete. The
seven previously blocked Vision checks pass without a source or test change;
their earlier failures remain historical evidence, not current exclusions.
The first 231-case run passed but its result archive hit disk exhaustion; after
clearing old Xcode cache logs, the same checks passed again with a complete
archive. No causal claim is made about the earlier Vision failures. The same
thirteen AI classes remain deferred. This supersedes features469's scoped gate
and features444's older complete green snapshot for current automated coverage.

Installed Settings access remains blocked in features477: Computer Use reports
“native pipe closed before response” and then “native pipe startup failed.” The
app remains alive and the isolated note stays byte-exact. This is not evidence
of a Zerus crash. Physical/manual and delivery acceptance in the table remains
separate. Preview125's DMG predates these changes; no new DMG was made.

Features480 now accepts the native Files-to-Word-DOCX route: Add document
Cancel, byte-exact portable copy, rendered properties/image/table/code/final
paragraph, document-only/notes-only/split modes, annotation Save/Undo/Redo and
normal restart. All eight fixture files remain exact. Features479 confirms that
Settings still closes the Computer Use pipe after disk recovery/runtime reset,
with the app alive and its original note exact; further retries need a relevant
service/state change rather than repeated identical attempts.

Current proof: `artifacts/native-macos/features478/complete-current-coverage.json`
and `artifacts/native-macos/features478/verification.json`.
The delivery table below is the current checklist. Later historical sections
retain earlier evidence and limits, some of which have been superseded.

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

Features459 adds `pnpm macos:native:appcast prepare|verify`, replacing the
QA-only appcast recipe with a repeatable native release tool. Preparation uses an
explicit native Keychain account or owner-only CI key file, the already bundled
feed/public key, pinned Sparkle and a new output directory. It produces a ZIP,
signed XML and an un-published receipt without changing the input app or building
a DMG/version. Production mode requires Developer ID, a stapled notarization
ticket and Gatekeeper acceptance. Verification uses only the bundled public key
and checks UTF-8 signed length, metadata/URL, archive bytes, exact executable and
sealed resources, plus archived app signature/notarization policies.

The protocol owner and 12 full-command cases pass using real signed copied QA
apps and disposable keys, followed by four final-code command checks. A validly
signed alternate app with the same version/key passes the earlier signature-only
verifier and is rejected by the final app-binding guard. Feed/archive tamper,
wrong keys/channels, ad-hoc production use, unconfigured apps, unsafe output and
private-file permissions refuse. Installed app bytes remain unchanged; private
QA keys are removed. No production key, publication, DMG or version change.
Production channel preference is pending; actual Developer ID/notarized update
publication/download/install remains unaccepted. Notarization API-key file access
is confirmed without reading/logging its contents. Evidence:
`artifacts/native-macos/features459/verification.json`.

Features458 accepts Finder delivery to a confirmed windowless running app.
After Command-W, the existing CUA app binding returns noWindowsAvailable while
the owned process remains running. Finder Open With then displays the requested
Work/Control.md in a workspace through that same binding, without getApp or a
new launch. PID/executable/start time remain identical across delivery. Both
original fixture notes are byte-exact, normal Quit is observed, and the process
exits. This supersedes the zero-window observation limit in features454/455.
No source/test/build/version/DMG changes were needed.
Evidence: `artifacts/native-macos/features458/verification.json`.

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

Features455 accepts distinct-vault Finder delivery in the installed app. The
active second window uses OtherVault455 while the peer keeps the original vault.
Opening the peer vault's Markdown presents an editable external original without
switching the receiving vault or adding a note there. Opening a TXT adds one
local-original connection note only to the receiving vault, with an independent
note ID. The peer retains its original document and preview. All pre-existing
files in both vaults, plus the outside Markdown/TXT originals, remain byte-exact.
Normal Quit and process exit are verified. No source/test/build/version/DMG
changes. Evidence: `artifacts/native-macos/features455/verification.json`.

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

Features450 repairs the navigation loss found in features449 committed-phase
rename recovery. Before clearing the durable receipt, macOS now remaps saved
tabs/pins, folder view keys/current context, kept/collapsed folders, default note
destination and folder ordering, and flushes the local preferences. Recovery
keeps its receipt if that persistence fails. Startup bypasses its stale snapshot
when it has just processed pending folder renames. The existing real rename owner
now includes a committed transaction produced by the real planner/writer; it
fails ten assertions on the old code. Three final affected owners pass. An
intermediate throwing-expression compile error is retained and corrected.
The signed optimized repaired app is interrupted in a verified committed
pre-move phase on a fresh 180-note legacy fixture. Reopening restores the pinned
legacy note, active path, folder tab and query, finishes the move, and clears the
receipt. All 180 committed note bytes, valid unique IDs, original body/BOM/CRLF/
foreign fields, control and raw folder metadata are exact. A normal restart
keeps navigation and every vault file exact. Exit codes are -9, 0, 0. The shared
source addition is macOS conditional; the iOS implementation is unchanged.
No DMG or version change. The previous features444 aggregate predates this repair;
the features451 gate finished with all 292 checks executed: 285 pass and seven
OCR-dependent checks fail alongside Apple Vision missing-ANE-resource errors.
Rebuilding only the retained generated cache did not repair the targeted retry;
a standalone CPU-only Vision probe also fails with TextRecognition e5rt code 13
outside Zerus. Exact coverage and unchanged inputs are recorded in
`artifacts/native-macos/features451/current-gate-results.json`. No test weakening
or new exclusions were introduced. This aggregate predates features452/453;
their focused file-opening owners and installed transport checks are separate.
Evidence: `artifacts/native-macos/features450/verification.json`.

Features449 verified committed file recovery but exposed the lost open legacy
note tab; it is not counted as full workflow acceptance. The corrected follow-up
is features450. The first content probe expected an unquoted UUID scalar and was
corrected for valid quoted YAML without changing note bytes.
Evidence: `artifacts/native-macos/features449/verification.json`.

Features448 accepts interruption of an active local multi-file folder rename.
The installed review names 180 synthetic legacy notes and their destination.
A filesystem watcher observes the real journal and verifies the owned QA PID,
executable and launch time. Only after a mixed write set is seen does it stop
that process, recheck the frozen uncommitted record, and kill it. The frozen
journal has 24 intended files and 158 original files, with no other bytes;
the owned process exits -9. Reopening rolls back every write: all 182 vault
files match their pre-Apply hashes, Work exists, Renamed is absent, and pending
transaction/rename records are cleared. A recovered note opens in Rich text
with its foreign field and original body. Normal Quit leaves all files exact.
No fabricated journal, product/test/build/version/DMG change. This proves one
uncommitted local transaction phase; committed-rename receipts, outside conflicts,
history purge interruption and cloud outage timing remain separate.
Evidence: `artifacts/native-macos/features448/verification.json`.

Features447 accepts real iCloud Drive note materialization using a uniquely
named synthetic QA vault. Both original notes are confirmed uploaded. Only the
owned target is evicted using the public FileManager API. A fresh metadata read
and filesystem dataless flag confirm cloud-only state before the app starts;
opening the app materializes and displays the note with exact original bytes.
A native edit/Command-S preserves BOM/CRLF/foreign header bytes and the control,
and iCloud confirms upload. After normal Quit, the edited note is evicted again
and confirmed not downloaded; reopening displays the uploaded edit, with exact
saved and control bytes and current downloaded state. Both runs exit zero.
The first eviction status probe retained cached URL values and exited 2 despite
successful eviction; independent fresh metadata/stat prove the intended state.
The corrected second probe clears cached values and exits zero. No product,
test, build, version or DMG changes. No account/network disconnect, active
transaction interruption or other-device concurrent write is claimed. The owned
cloud QA folder is retained; personal files were not read or modified.
Evidence: `artifacts/native-macos/features447/verification.json`.

Features446 verifies installed task keyboard date editing in the same isolated
vault, adding only one uncategorized General-list test task so the pending
list/category review assignment counts do not change. Title → Tab focuses
Scheduled. Clearing Scheduled or entering 31 February disables Save; Return
makes no shared write. Correcting the day and Tab/Return saves the exact ISO day.
A Due date entered by keyboard saves exactly; clearing keeps the field mounted,
and Escape restores its saved day without closing the task form. A subsequent
clear and Tab/Return persists null. After normal restart, Scheduled remains
correct, Due is off and no private draft remains. Both original retained task
records and other task metadata remain equal, the supporting note is byte-exact,
and the task file is byte-exact across restart. These are native Computer Use
keyboard events, not physical hardware, general IME or VoiceOver certification.
No source/test/build/version/DMG changes.
Evidence: `artifacts/native-macos/features446/verification.json`.

Features445 reconciles the historical editor backlog against the current
production owners and fresh pinned-web import/export probes. Current passing
owners cover marker caret input, marked composition, cross-item replacement,
interleaved items, partial code/table selections and structured/multiline paste.
Reference links/images still fail the web editor import and use native Source
fallback; they are not a demonstrated missing web feature. Seven list/quote/rule
controls import successfully in the fresh web probe. This is contract-level
source/owner and headless-web evidence, not physical keyboard, full grammar or
installed clipboard acceptance. No product/test/build changes.
Evidence: `artifacts/native-macos/features445/verification.json`.

Features444 closes the aggregate verification gap after features439. A fresh
flat enumeration yields exactly 292 enabled non-AI checks. Five sequential
processes pass 2 appearance, 5 collection, 57 workspace, 222 remaining and 6 OCR
checks. The result trees match the enumeration exactly, with no skipped or
duplicate checks, and every frozen source/test/configuration/resource/compiled
hash remains unchanged. The current preview repair hashes also match the final
features439 sources. No rebuild, source/test change, cache workaround, version
change or DMG. The owned features443 app was closed normally before testing;
its task file and supporting note are unchanged. Destructive Apply remains
pending action-time confirmation and is not counted as passed.
Evidence: `artifacts/native-macos/features444/complete-non-ai-coverage.json`.

Features443 verifies installed task deletion in an isolated vault after explicit
action-time approval. Review Cancel preserves exact bytes. Apply removes only
the approved task: both retained task records and all list/category/foreign
fields remain equal, and the linked BOM/CRLF supporting note remains byte-exact
and opens normally. Normal restart shows only the two retained tasks, no stale
draft, and every vault file remains exact across reopening. List/category reviews
also identify one assigned task and state that tasks/notes are kept; both Cancel
paths preserve every vault file exactly. Their final Apply actions await separate
confirmation and are not counted as passed. No source/test/build/version/DMG
change. Evidence: `artifacts/native-macos/features443/verification.json`.

Features442 verifies forced process interruption during a cached startup failure
on the unchanged signed features439 app. The owned vault is temporarily unreadable,
so startup cannot finish and the private edit cannot overwrite the saved note.
Before SIGKILL, the app-generated checkpoint's exact baseline/body/owner/key and
the QA executable/PID/start time are verified. A path-alias lookup preflight
aborts without sending a signal; the corrected, separately recorded stage is
the actual interruption (exit -9). Permissions are restored. Relaunch announces
and displays the full private draft as unsaved; independent file reads confirm
no automatic commit. Explicit Save preserves exact BOM/CRLF/foreign-header bytes
and removes all matching recovery checkpoints. Normal reopen has no recovery
prompt and every vault file remains exact. Other runs exit normally. No
source/test/build/version/DMG change. Active coordinated-transaction interruption
and real cloud-provider behavior are separate acceptance routes.
Evidence: `artifacts/native-macos/features442/verification.json`.

Features441 verifies cached startup and temporary local access recovery on the
unchanged signed features439 app. Warm startup keeps the selected note usable
when a newly unreadable Markdown file prevents inventory refresh, names the
failure and offers Retry. A valid cached note saves with exact BOM/CRLF/header
bytes while refresh fails. Repair recovers automatically; a separate startup
also verifies an actual successful Retry click after repair. With only the owned
fixture root temporarily set to mode 000, cached content remains available,
Save reports the permission failure and keeps the private draft. Restoring the
original mode and clicking Retry retains that dirty text as unsaved; Command-S
then saves it exactly. Every vault file is exact across healthy reopen, the
other note remains unchanged, and the original root mode is restored. All five
launches exit normally. No source/test/build/version/DMG change. Actual cloud
provider reconnect and forced process interruption remain unverified.
Evidence: `artifacts/native-macos/features441/verification.json`.

Features440 verifies local two-window outside-edit recovery on the unchanged
signed features439 app. Both clean editors adopt an outside update. After a
shared file is temporarily moved out, the first window retains its text and
private edit; the peer independently opens the restored changed file and saves
new work. The retained window refuses Command-S overwriting that peer version.
Export preserves the private draft's exact BOM/CRLF/frontmatter/body; only then
Use saved version adopts the latest peer text. Both windows follow a later
outside rename by stable identity. Normal relaunch opens the renamed note
without reviving the private draft; every vault file and the private export
remain byte-exact. Both launches exit normally. No source/test changes or
repeated build/test run, version change or DMG. Cloud-provider reconnect,
interrupted startup and broader simultaneous edits remain separate.
Evidence: `artifacts/native-macos/features440/verification.json`.

Features439 repairs raw text-file preview saving (Files → Other vault files,
and attachment previews). The preview's actual file-state owner rejects invalid
UTF-8 without making an empty writable document. Its Save action preserves a
UTF-8 BOM, CRLF, creation date and permissions, and checks current bytes inside
file coordination before replacing content. No-op saves do not rewrite files.
The existing persistence logic, extracted without changing behavior, fails ten
owner assertions before repair. A separate hosted-view check fails against the
intermediate disabled TextEditor because that control still accepted typing;
unsupported data now creates no editor. All three final affected owners pass.
Installed checks verify unsupported/read-only state, exact BOM/CRLF edits and
attributes, stale-save refusal with the draft still visible, and fresh reopening
of the outside version. Original note and unsupported bytes remain exact.
This change follows the features438 aggregate and has focused/hosted and
installed proof, not a subsequent complete gate. No DMG, version or iOS change.
Evidence: `artifacts/native-macos/features439/verification.json`.

Features437 completes icon suggestions for folders first created by a successful
note move or external copy/move. The external transfer sheet now accepts a new
folder path. Suggestions cover destination ancestors only, preserve existing
folders and all overrides (including unknown values), and use one guarded icon
metadata transaction. Failure to save a suggestion is a warning after the primary
file operation; it does not report a saved copy as failed. The two real-workflow
owners fail five assertions on the baseline; all 22 affected owners pass after
the fix. Installed checks verify a move into Recipes/Travel with a suggested
ChefHat and retained custom Heart, plus an external copy into new Coffee/Books
folders with Coffee/Book artwork. Notes, external original and unrelated icon
JSON tokens remain exact. No version/DMG/iOS change. The complete integrated gate
is included in the later features438 291-check aggregate.
Evidence: `artifacts/native-macos/features437/verification.json`.

Features436 closes the folder lifecycle metadata fidelity gap. Rename patches
only folder keys and relation targets; recoverable Trash removes only owned
entries; Restore merges original owned tokens while retaining current unrelated
entries. Distinct Unicode-equivalent keys and leading-FEFF foreign strings are
preserved across properties, icons, active views and saved views. Sensitive
receipts use version 2 so older clients refuse them; ordinary representable
receipts retain version 1. Existing already-lossy receipts fail closed.
The regression owner failed 32 assertions before the repair. All 59 workspace
checks pass, followed by three final lifecycle checks after exact numeric
comparison hardening. The optimized signed internal app passes reviewed rename,
Trash, Restore after outside edits, named-view/Gallery/icon retention and normal
restart. Original BOM/CRLF notes and attachment bytes stay exact; all vault files
are exact across restart. No DMG, version change or iOS feature/behavior change.
Evidence: `artifacts/native-macos/features436/verification.json`.

Features433 adds sequential ordered-list presentation while retaining each
existing source marker through ordinary body edits, checkbox toggles and Undo.
The signed internal app passes installed lazy-number, 9→10 nested-child,
checkbox, Source/Rich and restart checks. All four BOM/CRLF/foreign-field note
files are byte-exact after Undo; all vault files remain exact across restart.
The 132 editor/clipboard/navigation owner checks pass, and the final regression
owner fails on the old code for the intended numbering behavior (33 assertions).
The final complete non-AI gate passes all 288 checks across five fresh
processes, with exact coverage and unchanged inputs. The first gate attempt
found an existing tab-close fixture racing outside-change reconciliation; the
test now explicitly refreshes before retrying Save and isolates its AppKit
helpers on MainActor. All original assertions remain. That failed run is kept
in `features433/aggregate`; the final pass is in `aggregate-final`. No DMG, version change or iOS change. Evidence:
`artifacts/native-macos/features433/verification.json`.

Features434 verifies named saved-view interoperability without source or test
changes. Five presets written through the current web format owner (Gallery,
Kanban, Table, Calendar, List) apply in the installed native app with exactly
equal persisted configurations. Native-saved Gallery and Calendar copies read
back with equal configurations through that same web owner. Installed checks
cover filter membership, grouping, properties, column order, date range, recall
and restart. All three BOM/CRLF/foreign-field notes and the schema remain exact;
all vault files remain exact across normal restart. This is local format and
native workflow evidence, not a live web/Windows UI or provider transport claim.
The features433 288-check aggregate remains current because product/test inputs
are unchanged. Evidence: `artifacts/native-macos/features434/verification.json`.

Features435 closes the missing native folder-icon feature: the sidebar and
folder tabs now render shared Tabler/legacy emoji values, with an offline
5,130-icon searchable/paginated picker, reset, emoji selection and new-folder
concept suggestions. Move/document folder selectors use the same artwork.
The Mac writer patches only the selected JSON token and uses exact UTF-8 keys;
shared transactions compare original bytes and refuse stale/root/folder changes.
Unrelated Unicode-equivalent keys, leading-FEFF strings, unknown values and
source formatting remain exact, and duplicate selected keys are refused. Peer updates and cached startup
artwork are covered. All 5,130 SVGs rasterize nonempty through AppKit; six native
owner checks, three final label/tab checks and five web icon checks pass. The
cache regression fails on the old cache owner for its missing artwork.
Installed checks pass for existing/fallback artwork, multiword search, Cancel,
selection, earlier editor Undo, outside-edit refusal/Reload, reset, emoji input,
Recipes→Chef Hat, sidebar/tab consistency and restart. All four original
BOM/CRLF/foreign-field notes stay exact; all vault files stay exact across
restart. Final raw-storage installed checks also pass for exact insertion/reset, earlier
editor Undo and restart with NFC/NFD keys and a leading-FEFF foreign string. The
original Unicode writer and the prior Foundation value conversion fail their
regressions for the intended losses. The final complete current non-AI gate
passes all 289 checks with exact coverage and frozen code/config/resources. The
first run was deliberately cancelled for the storage repair; the final OCR
shard passed on a cache-rebuild retry, with the original failure retained. No DMG or
version change. Shared snapshot additions are macOS-only; the iOS source branch
is byte-equivalent to its previous implementation.
Evidence: `artifacts/native-macos/features435/verification.json`.

## Delivery accounting — concrete workflow checklist

The four previously reported areas are categories, not four remaining tasks.
The feature tracker has 25 non-AI workflow rows. Existing code, bounded owners
and installed workflows are recorded separately; missing manual evidence is not
a demonstrated product bug. User exclusions and accepted deferrals supersede
historical checklist wording. AI remains deferred, Windows and direct Google
Drive are excluded, and further performance profiling is deferred.

Current evidence is features478's 303/303 Mac non-AI checks, features488's actual
local iOS–Mac–iOS note/resource handoff and Source repair, features489's 16 affected
iOS checks and installed Files-only workflow, and features485–486's Developer ID
notarization and real signed update installation/save veto/relaunch. These close
the old aggregate, local handoff and updater-engine gaps. No newer full Mac suite
is claimed for the iOS-only changes. Final package publication/delivery is still
separate from private candidate acceptance.

Features493 recovers native observation and accepts installed CLI install/update,
export, registration/metadata review/Cancel/Apply, relation-repair review/Cancel/Apply,
and pane configuration/reopen. Features494 accepts native Kanban card/column,
folder and tab pointer delivery, actual 600-point edge resize, overflow scrolling,
and Portuguese dead-key composition with exact Save/Undo/Redo/reopen. The remaining
input checks are accepted to the agreed scope. VoiceOver QA and microphone
dictation are excluded by the user. The verified private package is ready for
final handoff; public release publication remains separate.
The existing iOS accessibility acceptance and physical composition deferral in
the iOS guide are retained. Broader adversarial examples in the rows below
remain coverage limits; they do not establish an unimplemented feature or justify
repeating accepted workflows without a relevant change or failure.

Current platform scope: **iOS and macOS only**, as requested by the user.
Windows delivery and live Windows verification are excluded. Direct Google Drive
integration and its live verification are also excluded by the user. Existing
Drive evidence remains historical; it creates no further acceptance gate. The React/Tauri
implementation remains a behavior and shared-format reference; its separate web
UI is not a delivery gate for this Apple migration. AI remains deferred.

| ID / workflow | Evidence already recorded | Concrete remaining route / proof |
| --- | --- | --- |
| D01 Layout | Hide/restore folders; special collection OR note; compact Library dismissal; zoomed input; features420 native menu half-screen resize and original edit/Undo retention across six long tabs | features494 accepts actual 600-point edge resize and horizontal overflow scrolling; features493 accepts Settings access and pane configuration/reopen. Broader human accessibility checks remain D21 |
| D02 Vault browsing | Local scan, warm snapshots, outside-edit protection, rename following and recovery owners; features428 adds root/child folder ordering, peer/reopen persistence, rename/Trash handling, byte-exact identity and installed menu/Undo/collapse/restart verification; features435 adds the complete shared Tabler/emoji icon picker, sidebar/tab/selector artwork, new-folder suggestions, guarded persistence/peer/cache handling and installed Cancel/selection/stale/reload/reset/emoji/restart checks; features440 accepts local clean outside updates, missing-file retained edits, protected peer saves, exact draft export/reload, two-window identity-follow and restart; features441 accepts installed cached scan-failure startup, save of available notes, automatic/manual Retry, local permission-failure draft retention and reconnect save/reopen; features442 accepts forced interruption during cached startup failure, exact draft recovery without automatic commit, reviewed Save/checkpoint cleanup and healthy reopen | Open/reopen copied vault through actual distribution permissions; physical folder drag delivery; features447 accepts real iCloud upload/materialization/native save/re-upload/re-eviction/reopen; features460 accepts real Google Drive File Provider upload/native save/independent remote byte readback/reopen; account/network disconnect/reconnect and further providers remain; features448 verifies active local rollback and features450 verifies committed rename/receipt recovery with saved navigation; cloud and purge interruption remain D11/D15; features448 accepts active uncommitted local folder-rename rollback with all 182 files exact; features450 accepts committed-receipt local recovery including saved navigation; cloud-interruption phases remain; broader simultaneous-write/provider cases beyond features440–441; features437 accepts suggestions for folders first created by note moves and external copy/move, with an explicit new-path import field; features436 accepts exact Unicode/BOM/foreign metadata preservation through folder rename, recoverable Trash and Restore with unrelated later edits; broader companion-file writers remain separate |
| D03 Rich editor | Extensive list ownership, shortcuts, inline styles, clipboard, Unicode/source fidelity, Undo/Redo and bounded Portuguese IME evidence; features474 accepts shared web/vault link controls, Command-K, retained inline formatting, exact history and original-file edits; features472 accepts all six heading levels, Command-Option-0–6, Rich/Source exact saves and Undo/Redo with preserved line endings; features463 accepts installed native Find in Note in Rich/Source, next/previous, exact Replace All/single Undo and return to editing | Empty quoted-child divider Return repaired in rules397; features431 closes compact first-block divider before/after Return and installed quoted-empty-child acceptance; features433 accepts sequential numbered display with original-marker preservation, nested Return, checkbox/Undo and installed restart; features457 accepts delayed first-list-paragraph Rich opening, exact edits/Undo/Redo and restart; current owner coverage includes marker-caret/marked replacement, cross-item selection, structured and multiline paste, partial code/table selections and interleaved item operations; reconcile any specifically unsupported contract against these owners rather than treating all range/paste work as missing; features491 accepts installed automatic Source clear/replacement, exact literal Save, original-byte Undo, Redo and explicit Rich switching; installed physical composition/accessibility remains D21; no unrelated grammar expansion |
| D04 Tables/code | Native cell editing/Tab, code cards/sheets, source preservation, viewport work; features415 installed mixed list-owned code/table edits, code-sheet Cancel/Save/Undo/Redo, table-sheet added row, 30-row last-cell Tab/new row/Return/ShiftTab and exact Undo, 60-line code selection/Return/CommandReturn exit, independent GFM structure and Rich reopen; features468 accepts row/column movement, below/after insertion, narrower widths, pointer/Tab targeting, metadata-preserving Save/Cancel/Undo/Redo/restart | Physical IME/VoiceOver, larger/adversarial selection/layout and provider-failure cases; compact first-block divider Return is accepted in features431; features466 accepts native code-to-text conversion with quote/list ownership, literal lines and Undo; remaining numbered display and broader paste work is D03 |
| D05 Images/attachments | features476 accepts sized HTML image resource discovery, exact cross-vault native copy/paste, preserved size/title/BOM/CRLF/foreign metadata, Save/Undo/Redo with one asset and restart with all eight fixture files exact; 162 affected Mac and six iOS resource owners pass; features475 shared address/local-file insertion, exact vault/external project assets and Save/Undo/Redo, installed remote/repeated-image pixels, 404 Reload and exact restart; features418 installed shared-occurrence removal review/Cancel/Apply and exact reviewed Undo, imported 800×500 image preview, image/text Add file with preserved earlier edits and Undo/Redo, saved inline local-file preview after restart, unchanged source resources/peer note and exact imported payloads; attachment editor transaction and file-link navigation repaired | Features471 resolves features470 second-window image Undo through a live workspace document reader; 135 affected checks and installed two-window Save/Undo/Redo, real peer replacement and restart pass; copy/cut/import cancellation and failure with provider assets, interrupted/changed-note cleanup, same-note resource-byte changes and physical input/accessibility |
| D06 Links | features417 installed picker query/Down/Up/Return, Escape dismissal, insertion Undo/Redo, relative heading-target navigation, styled multiline stable link, preview Close/reopen/Open, missing-note Cancel/Create with unique ID/backlink, and restart persistence; BOM/CRLF/foreign fields and original link spellings retained | Physical IME/VoiceOver, two-window target changes and hover timing; precise heading scroll offset not measured by the short fixture |
| D07 Properties | Functional lifecycle accepted across properties401/402: typed validation/saves, inheritance/child overrides, reviewed create/type change/rename/removal, Cancel/stale protection, fresh Apply, persistence and CLI readback with protected bytes | Provider/unavailable-files and broader keyboard/VoiceOver acceptance remain cross-cutting D02/D21; relation definitions/repair are D08 |
| D08 Relations | relations403 installed paired add/remove, unresolved retention, exact review/Cancel, stale-target atomic refusal/fresh retry, inverse readback, definition rename/inverse hiding and restart persistence; current repair-owner tests pass | features493 accepts installed nonempty repair Review/Cancel/Apply/reopen, exact paired links and unresolved/foreign/body preservation; paired bulk Undo after later edits is accepted in bulk404 (D11); broader provider/keyboard/VoiceOver remain cross-cutting |
| D09 Lists/filters | Search, sort, typed/date/all-any filters, subtypes, named views and persistence; features411 saves/recalls named Table view across folder/global navigation, mode changes and restart; features434 applies all five web-format presets in the installed app, round-trips native Gallery/Calendar copies through the web owner, verifies exact configs, filter membership, grouping/columns/dates and restart without note/schema changes | Live iOS/macOS named-view interchange and provider transport; large Files/alternate-view inventory; features462 accepts installed Command-A/Escape across all five modes and filtered Gallery/Calendar selection with search-field focus protection; broader keyboard/VoiceOver remains D21 |
| D10 Alternate collections | Gallery groups/covers, typed Table, Calendar/Undated; board398 installed two-card menu move, exact review/Cancel, durable Undo/Redo, stale-review recovery preserving later edits, column-control order and quit/reopen persistence; features411 installed Gallery covers/collapse/property visibility, Calendar crowded-day/date edit/clear/Undated/month navigation, typed Table number/choice edits and saved-view restart | Features494 accepts Kanban card and column pointer delivery with exact saved/reopen readback; features462 accepts installed Command-A/Escape selection in Gallery/Kanban/Table/Calendar, including filtered membership and protected search focus; compact columns, provider and broader keyboard/VoiceOver acceptance |
| D11 Bulk actions | Reviewed properties/relations/moves with durable Undo/Redo; board398 installed two-card selection/review/Cancel and refreshed property Undo preserving later foreign-field edit; bulk404 paired relation Add, exact Cancel, stale/fresh Undo, Redo and restart preserve later source/inverse edits; features414 accepts collision-safe move review/Cancel, resources/incoming links, stale refusal, Undo/Redo preserving unrelated edits/additions and restart; current-graph history repair | features448 accepts active local uncommitted multi-file rollback after forced interruption; broader selection gestures, overlapping edits to receipt-written files/shared settings and interrupted provider phases remain; features450 accepts local committed rename receipt recovery with tabs and context retained |
| D12 Navigation/windows | Installed core flow accepted in navigation394: Gallery/note exclusivity, sidebar restoration, retained Undo/Redo, pin/menu reorder, Back/Forward, independent windows, guarded unavailable-file close and reopen persistence; middle-close/pinned-close and adjacent selection repaired; features440 accepts two-window outside updates, retained private drafts versus peer saves, exact export/reload and identity-follow/reopen | Features454 accepts same-vault Finder receiving-window selection and mixed-file batch delivery with the peer selection preserved. Features494 accepts pointer tab reorder, horizontal overflow scrolling and exact restart; broader keyboard/VoiceOver remains D21. Do not reopen already accepted core routes without a relevant change |
| D13 Tasks | features406 installed list/category creation, task create/edit/schedule/due clear, list move/rename, search/priority/category/Today/Completed filters, complete/reopen, supporting-note save/navigation and restart persistence; durable renamed-directory draft recovery already verified | features443 accepts approved task-deletion Apply/Cancel and restart with retained task fields and supporting-note bytes exact; features483 accepts the specifically approved category/list removals with all three tasks retained, the assigned task moved to General, supporting notes exact and normal restart verified; features446 accepts installed required/optional date keyboard validation, Escape rollback, Tab/Return Save and restart; broader keyboard/VoiceOver; already-moved, cross-volume and provider draft recovery. CLI reads identical task bytes in a separate copy with corrected QA manifest |
| D14 Trash | features408 installed note Trash/Restore returns entire fixture byte-for-byte; non-current revision Trash/Recently deleted Restore preserves current text/images; permanent-deletion review/Cancel preserves every file; features409 folder Trash/restore retains resources, empty directories and shared folder settings, refuses occupied destinations and merges later unrelated settings | Features481 accepts the approved permanent purge of one synthetic note, its two history records and owned history blob, with control note/shared image exact after normal restart. Other purge types, provider/interrupted operations and broader accessible controls remain |
| D15 History/revisions | features408 installed frozen-image preview, revision promotion with current-property preservation, history label/Keep/parent comparison and reviewed resource restore; maintenance cleanup/clear review and final Cancel; stale deleted-revision preview repaired; 7 recovery/retention owners pass | Features464 accepts installed 17-image/three-page frozen-image browsing, bound controls, named unavailable-blob warning and exact restore/Reload recovery; larger histories/images and actual provider failure remain; actual retention/purge Apply in installed app, broader keyboard/VoiceOver and interrupted operations |
| D16 Files/external notes | features407 installed external connect/save/rename-follow/missing/Locate, stale-edit draft preservation/export/restart/reload, reviewed copy/Cancel and collision-safe independent identities; document original connection/preview/context notes, replacement portable copy and detach/Cancel with files retained; imported root navigation repaired; features409 accepts shared location create/rename/map/disconnect/reconnect, per-file Locate/folder fallback and persistence, with live Locate preview refresh repaired; features439 accepts safe raw-text preview saves, invalid-encoding refusal, exact BOM/CRLF/attribute preservation and installed outside-change handling | Features452–455 accept Finder warm/cold, mixed-batch, same-vault and distinct-vault routing with original preservation. Features474 accepts shared web/vault link controls and exact external Rich/Source edits/history/reopen. Features473 accepts shared external code/table sheets, inline code, code-to-text, Rich/full Source edits, table insertion and exact history/reopen; creation-on code insertion was not manually toggled here; resource-heavy copy/move/provider interruption, resource edits and two-window close/commit; broader keyboard/VoiceOver |
| D17 PDF/HTML | features480 accepts installed Files → Word DOCX creation/Cancel, exact portable copy, native QuickLook properties/image/table/code/final paragraph, preview expansion/hiding, annotation Save/Undo/Redo and restart with all eight fixture files exact; Secure password flow, normalized PDF search, HTML isolation/approval/download owners; features413 installed 30-page search/case/Unicode/line-break highlights, Return/page jump/expand/zoom, encrypted wrong/correct password and relock; HTML safe/full/link modes, download Cancel/Save/status/exact payload, restart and changed-file approval renewal | Very large/complex PDF fixtures, broader keyboard/VoiceOver/provider failure; live-origin and interrupted long downloads; additional Quick Look formats beyond the accepted Word DOCX route |
| D18 Saved links | Create/edit, URL-bound live-page approval, resize/expansion; features410 installed URL Cancel/invalid/duplicate refusal, successful URL change preserving identity/annotations/foreign fields/BOM/CRLF, approval reset for changed URL, collection/note transitions and both enabled/hidden page mode across restart; features426 passes web-owner→native→web-owner→native saved-link metadata/body/index round trip, installed readback and managed-URL hiding in Rich/Source, annotation/code-sheet/attachment Save/Undo and restart | Large collection navigation, live cross-client/provider transport, broader keyboard/VoiceOver; features429 closes the recorded normalization differences with 75 web/native comparison cases, create/update owners and installed duplicate/restart checks |
| D19 Exports/print | export352 installed save/cancel/options; features419 installed multipage PDF/Word/HTML export with visible properties, native 9-page print dialog and Save as PDF, all paragraph/table/code markers intact, exact Word/HTML embedded pixels, PDF page raster inspection, native WebKit HTML and Quick Look Word layout readback; original note/resources unchanged; features425 adds installed File → Print / Command-P, Cancel/focus return and disabled Print in Gallery, with retained-draft snapshot owner proof | Failed/cancelled/interrupted provider output, unusually wide/adversarial pagination and broader keyboard/accessibility; direct Word/Pages rendering not verified, Pages first-run licence left unaccepted; no physical print job |
| D20 Global search | Multi-source ranked search, filters, excerpts, preview and keyboard owners; features412 installed five-source results/open actions, archived exclusion/inclusion and Trash exclusion, exact property/task priority/status/date filters, accent-folded matching, body-only TXT search/preview, 85-result paging, keyboard selection/Return, missing-local-external recovery and recent-history restart/clear; all source bytes exact | Live provider interruption/reconnect, broader folder/filter combinations, physical IME/VoiceOver and multiwindow updates; AI context actions deferred |
| D21 Input/accessibility | AppKit text, scoped composed-input checks and accessible selection state; features494 accepts native Portuguese dead-key Save/Undo/Redo/reopen | VoiceOver QA and microphone dictation are excluded by the user; broader human IME combinations are coverage limits, and dedicated chat recording is not parity scope |
| D22 Settings/themes | Palette/theme/zoom/pane owners and hosted visual checks; features427 actual exported file → native review/Cancel/Apply, all values/palettes/named theme readback, editor Undo retention and restart, original preference restoration | Recover installed Settings QA access (features477/479 repeat the Computer Use pipe failure after disk recovery/runtime reset; features487 repeats it on the notarized Developer ID artifact; features490 confirms the screenshot fallback also fails, with the app alive and all vault files exact; no product-crash claim); exercise live light/dark/system changes, partial fields, pane order and multiwindow updates without losing drafts |
| D23 CLI/migration | Reviewed metadata owner and CLI doctor/readback on owned legacy vault; install/setup code; features427 app-wide preference export and reviewed native import with stale-review protection, merge preservation and installed Cancel/Apply/Undo/restart | features493 accepts installed CLI Install/Update/Cancel/export, metadata and registration Apply with independent CLI readback, exact registry cleanup and reopen; companion acceptance (features430 transfers default folder, order, keep-open and subtype visibility); reopen with CLI/web/native preserving original note/resource semantics |
| D24 Packaging/update | Internal signatures and local signed-update/relaunch/conflict checks | Features484 configures the user-approved separate native GitHub Sparkle channel and provisions its separate zerus-native Keychain key; after user OS authorization, a real Keychain signature verifies against the configured public key and rejects tampering. Features485 accepts a private configured Developer ID app, Apple notarization including CLI/Sparkle helpers, ticket/Gatekeeper validation and controlled updater startup/error/Cancel. Production ZIP/feed signatures and extracted app independently verify after user Keychain authorization. Features486 accepts actual private HTTPS download/install/relaunch of the unchanged notarized candidate, save-failure veto with retained draft, recovered Save/retry, exact installed seal and unchanged saved vault. Features492 accepts one private signed/notarized DMG using the same app, exact mounted/copy signatures and seal, installed Save/Undo/Redo and normal restart with all six vault files exact; no app rebuild or version increment. Final user handoff remains after feature acceptance; no public release was authorized or published |
| D25 Cross-client compatibility | compatibility395 passes web-data-owner→CLI→native→web→native/CLI writes/readback for typed note fields, paired relations, task dates/links/state, view filters/order, history/revisions and frozen images; installed native readback passes | Features488 accepts actual iOS edit → local Mac Rich readback/edit/Save/Undo/Redo → iOS reopen, with exact returned note, sized HTML image attributes/resource bytes, foreign metadata and control notes; its iOS automatic-Source replacement repair passes 12 affected checks and simulator interaction. This is explicit local fixture transport. Further live iOS/macOS Files/iCloud transport, Files location interoperability, live saved-link transport (recorded URL-normalization differences closed in features429), companion metadata migration remains; features434 accepts local named-view format interchange and installed native apply/save/restart, without a live-client transport claim; app-wide settings transfer is features427 and per-vault default/order/keep-open/subtype transfer is features430; no web BOM/header-byte preservation claim |

The user accepts performance for now and requests feature completeness next.
Performance405 records an equivalent parsing-scan/storage optimization, final
optimized build, 99 passing editor owners and six sequential hosted measurements.
No physical input-to-display latency claim is made. Further profiling is deferred
under the user's direction; feature delivery and final packaging remain active.

## features415 — installed mixed tables and code

The current app opens mixed list-owned code/table content in Rich text. Inline
code replacement and confirmed cell selection/Unicode paste save exact expected
nested Markdown. Tab advances cells without losing neighbors, tails or siblings.
Code-sheet Cancel is read-only; Save/Undo/Redo retain ownership. The table sheet
edits a cell and adds/populates a row, with single Undo/Redo. In a 30-row table,
last-cell Tab creates the next row, another Tab advances cells, Return saves a
portable multiline value and Shift-Tab reaches the prior cell; Undo of that
navigation probe restores exact saved bytes. A 60-line code block accepts an
end-of-block edit/Return and Command-Return continues writing outside the fence.

An independent pinned GFM parser verifies exact mixed Markdown, list/card/tail
ownership, table rows/cells, 61 saved code lines and retained outside prose. BOM,
CRLF, identity/foreign metadata and manifest remain intact; no placeholder leaks.
All three notes reopen Rich after normal restart, with every pre-restart vault
byte unchanged. No product code, project test or build change was needed.
The automation’s dead-key sequence produced a layout-specific character instead
of composition; corrected confirmed selection/Unicode paste works, but physical
IME is unverified. This does not establish a product IME defect or close broader
compact/quoted rule/card behavior. Evidence:
`artifacts/native-macos/features415/verification.json`.

## features414 — move history preserves unrelated work

The old whole-vault hash check refused Undo after editing or adding an unrelated
note. The owner regression fails for those two reasons before the repair. Move
history now checks receipt-affected notes exactly and replans against the current
graph before accepting unrelated work. New incoming links require a fresh move
review; an ID assigned by the move cannot be removed while newer work mentions
it. Current notes remain guarded throughout the review/commit transaction.
All eight move owners pass, including the added identity-removal negative control.

Installed review numbers a filename collision and Cancel preserves all bytes.
Apply moves both notes, retains identity/foreign fields/BOM/CRLF, rebases the image
reference without moving its payload and updates incoming Watch links. An outside
edit after Undo review makes stale Apply refuse with no writes. Fresh Undo restores
all original affected bytes while retaining later Control writing and a new note.
A second unrelated edit survives Redo, whose affected bytes match the forward
result. Restart retains the moved note and actionable durable receipt. A newly
added incoming path link then refuses Undo without changing files.

Only the internal optimized signed app was updated, at the existing version;
no DMG was made. Shared-setting or changed affected-file conflicts still require
a fresh move review. Provider interruption, broader selection/input/accessibility
and final aggregate/packaging remain. Evidence:
`artifacts/native-macos/features414/verification.json`.

## features413 — PDF and HTML document lifecycle

Installed PDF checks cover 30 pages: search/match case, Return to the next
match/page, page jump, expansion preserving state, zoom controls and notes return.
Unicode compatibility matching finds full-width text; a phrase across a line
break highlights the original two lines. The encrypted PDF refuses a wrong
password, unlocks by Return with the owned fixture password and enables search;
closing/reopening requires the password again. Original encrypted bytes stay exact.

HTML Safe renders with its script disabled; explicit Full executes the owned
script. Download Cancel makes no vault/output write; Save produces exact UTF-8
bytes and the Downloads window distinguishes Saved/Canceled. Full mode survives
normal restart. Changing the HTML externally and reloading requires a fresh
preview choice; Only link then survives note close/reopen without rendering.
Only the deliberately injected outside HTML edit differs from the fixture; both
PDFs, note body/metadata/BOM/CRLF and manifest remain exact. No code change or new
build/DMG was needed. Evidence: `artifacts/native-macos/features413/verification.json`.
Very large/complex documents, provider failures, live-origin/interrupted downloads,
office Quick Look and broader physical input/accessibility remain separate gates.

## features412 — installed global search

An owned fixture verifies results and opening for notes, tasks, saved links,
local files and connected external Markdown. Archived inclusion, Trash exclusion,
exact Status filtering, combined task Open/High, modified-date filtering and
accent-insensitive Café matching work. Return opens the selected note; arrow keys
change previews and Return opens external Markdown. A body-only TXT query finds
and previews the file; unsupported binary content stays explicitly filename-only.
Paging exposes all 85 matching notes through Show more. A missing external source
refuses stale Open and remains discoverable by filename with a Locate instruction;
restoring its exact bytes and refreshing restores indexed text and opening.
Five visited source types survive restart as recent results, and Clear recent
removes only that private list. Every vault file and the external source remain
byte-identical. No app code change, build, or DMG was needed. Evidence:
`artifacts/native-macos/features412/verification.json`. A missing local file is
not live cloud-provider failure proof; broader folder combinations, physical
input/VoiceOver and multiwindow search remain separate acceptance work.

## features411 — alternate collections and named views

Installed Calendar selects Due, exposes every note on a crowded day, moves an
edited note to its new date and returns it to Undated when cleared. Next month
and Today work. Gallery displays all local covers, collapses/reopens groups and
hides/restores a visible property. Table number and choice edits save typed
values; Gallery reflects the new group and value. A named Table view restores its
mode and columns after global navigation and another mode, and survives restart.
Calendar’s date-property selection and cleared-date Undated membership persist.

The initial fixture used `options` instead of canonical `listOptions`; the app
correctly refused an unavailable choice. That fixture key was corrected before
the successful choice edit. No app source or test changes were made for this
batch. Peer notes, image bytes and Alpha’s body/foreign field/CRLF remain exact;
only intended typed fields, layout, saved view and recovery records change.
Evidence: `artifacts/native-macos/features411/verification.json`. Kanban pointer,
compact/provider and broader input/accessibility checks remain separate.

## features410 — saved-link URL and page-mode lifecycle

Installed Links opens both records and renders/expands the owned local page.
Editing the URL and cancelling, submitting an invalid file-scheme URL, or saving
an already-saved address preserves every vault byte. A successful URL change
retains note/link identity, annotations, foreign metadata, BOM and CRLF; only the
managed address field and body URL change. The new address starts with rendering
off. Explicitly enabling its page displays the new content; another link retains
its own off state. Switching notes and a normal restart retain the enabled mode;
hiding the page and restarting again retains off. No source change or additional
build was needed. Large inventories and broader cross-client/provider/input
acceptance remain. Evidence: `artifacts/native-macos/features410/verification.json`.

## features409 — folder recovery and shared file locations

Installed folder Trash and restore preserve note/attachment bytes and empty
subdirectories. Cancel changes nothing. An occupied original folder makes restore
refuse without changing either copy. After moving that conflict aside, restore
brings back the folder’s property definitions, view/layout, icon and named view
while preserving later edits to unrelated folder settings. Restored Gallery
shows its two grouped notes and named view.

Shared locations support choosing a local folder, renaming without changing its
ID, disconnecting and reconnecting, and adding a location. Cancelling removal
keeps every vault file exact; a used location cannot be removed as unused.
The mapped Unicode document path and text preview resolve correctly. Mapping
writes stay device-local; shared note bytes and relative paths remain exact.
This uses the shared file-reference format, not a live iOS/Drive transport check.

Locate-original verification exposed a missing preview notification: the private
replacement was saved, but the visible document changed only after Reload.
`locateFileHub` now advances the same mapping revision used by folder remapping.
The existing mapping owner passes. Installed fixed-build Locate immediately shows
the selected replacement without Reload; returning to the folder mapping also
refreshes immediately. Restart retains the mapping, renamed/added locations,
restored Gallery grouping and named view. All fixed-build checks leave vault
files exact. Evidence: `artifacts/native-macos/features409/verification.json`.
No new DMG or version increment is part of this work.

## features408 — note/revision Trash and resource-aware history

Installed note Trash moves only the Markdown file. Images, revision/history data,
peer notes and shared files remain exact. Cancelling the permanent-deletion review
changes no file; restoring the note returns the entire fixture byte-for-byte.
Deliberate revision review opens its frozen-image resource and Cancel is read-only.
Making the oldest revision current creates v5 from its old body/image, retains
current typed properties and snapshots the former current image. Non-current v2
can move to revision Trash and restore without changing current v5 or images.

Automatic history displays frozen images, saves a label/Keep, compares parents and
reviews restored text/resources. Cancel is exact; Apply restores the saved writing
and exact image bytes. History settings correctly counts the retained/kept data;
unused-image cleanup has nothing to remove. Clear-all review and its final
permanent-deletion confirmation show the affected scope, and Cancel writes nothing.
No permanent deletion is applied in this native pass.

The baseline exposed a view-state gap: after moving the selected revision to Trash,
its row vanished but its old preview and Make current action stayed live. The view
now excludes deleted revisions and validates selection on reload, falling back to
current/latest when needed. Seven existing recovery/history-management owners pass.
Direct installed baseline/fixed verification covers the UI transition without a
new XCTest or private production seam: after selected v1 is trashed, v5/current is
selected, its current preview is displayed and Make current is disabled. The kept
label, restored writing and saved image persist on the rebuilt app.

The final fixture retains v1 recoverably in Trash, restored v2 and current v5.
Only the original Alpha note, revision index and chosen history annotation differ;
every original image, peer note, task, schema, view and history-settings file is
unchanged. New restore snapshots are retained, and CLI readback agrees on typed
values and identity. Both native sessions exit0. Release build/signatures pass at
unchanged 0.3.85/build125; no DMG or iOS/AI change. The stopped frontend is restarted
and its local/private proxy routes reverified before handoff. Folder/provider/
large-paging and final destructive-Apply routes remain explicit in D14/D15.
Evidence: artifacts/native-macos/features408/verification.json.

## features407 — external originals and document connections

Installed external Markdown Connect/edit/Save preserves BOM, CRLF and foreign
frontmatter. The saved connection follows a same-volume rename. A truly missing
original refuses safely; Locate opens a byte-identical replacement. An outside-
first rewrite followed by editing the stale native text triggers conflict, disables
Save and retains the local draft without touching outside bytes. Export preserves
the local version. Normal quit/restart recovers that draft and its conflict; explicit
Reload then reads the outside version while the verified export stays intact.
The first append attempt autosaved before its outside change and is not counted
as conflict evidence. No merge behavior is inferred from that attempt.

Reviewed Copy Cancel changes no vault file; Apply creates an independent root
note and retains the original. Open vault copy exposed a navigation defect: the
note's display folder “Inbox” was mistaken for a physical Inbox directory, leaving
the adjacent collection empty. Actual root paths now select All Notes. The existing
navigation owner was extended and fails three intended assertions before repair;
it and Files/saved-link/portable-copy siblings pass (four tests). The rebuilt signed
internal app repeats Copy/Open with All Notes and three visible notes. A second
copy uses a collision-safe filename and distinct stable identity.

The document-note route connects an original text document with a readable preview,
resolved path and size. Hide/show preserves an editable context note. Replacing
with a portable vault copy retains note text/identity, refreshes the preview and
leaves both source documents untouched. Detach Cancel preserves every vault file;
Apply removes only connection metadata and keeps the note, sources and managed
copy. The detached note stays in All Notes. Final quit/reopen retains four notes
and its saved content; readback changes no files. All four native sessions exit0.

Only MacWorkspace.openNote and its existing navigation owner changed. Release
build/signature verification pass at unchanged 0.3.85/build125; no DMG, AI or iOS
change. Protected control notes, source metadata, exported draft and document bytes
survive. Unavailability is simulated only on an owned temporary fixture with exact
backups retained. Provider/mapping/resource-heavy/multiwindow routes remain D16.
Evidence: artifacts/native-macos/features407/verification.json.

## features406 — installed task lifecycle

Lists and categories can be created; New task inherits the selected list. Task
creation persists the title, priority, category, scheduled/due dates and supporting
note ID. Today excludes a future task; All lists, search, priority/category filters
and Completed show the correct membership. Complete records the visible completion
date, and Reopen restores pending state. Editing retains the task ID, moves it to
General, reschedules today and clears Due. Following its supporting-note link saves
the pending edits and opens the note. List rename retains its ID.

Category-removal and list-deletion reviews display affected-task counts; both
Cancels preserve all vault files. Destructive Apply was not exercised. Normal
quit/reopen retains the saved form, supporting link, renamed list and Drafts(0).
The control task's foreign field, root unknown data and original note/manifest
bytes survive. Two native sessions exit0. No feature source/test/build change.

The QA seed manifest omitted `version`, so direct CLI validation refused it. A
separate readback copy adds version1 only; CLI reads the identical tasks.json
correctly. This corrects the fixture, not the product or the original UI vault.
General serializes as null rather than necessarily an empty string; assertions
use its semantic default-list meaning. Evidence:
artifacts/native-macos/features406/verification.json. Remaining D13 routes are
listed above, not hidden behind a blanket task-parity claim.

## performance405 — scan/storage work closed for this pass

The profile identified ordinary-prose prefix matching, a whole-document admission
regex and repeated bridged string access. Equivalent ASCII/literal negative gates
skip impossible matches; input/prose UTF-8 is materialized without text or grammar
changes. The final optimized build and all 99 MacDocumentTests pass. Six alternating
fresh hosted processes verify real editor publication, exact Undo, Save, search/
Gallery memberships and guarded close; all fixture files remain unchanged.
Exploratory/overlapped timings are archived and excluded. A caught local naming
conflict caused an intentional build cancellation before the corrected final build.

The installed large root note opens in rich mode with Saved status; user direction
then stops further performance QA. Normal Quit exits0 and its copied vault remains
exact. No installed edit/composition or physical latency claim is inferred. Current
internal app is signed at unchanged 0.3.85/build125, no DMG. Evidence:
artifacts/native-macos/performance405/verification.json. Focus returns to features.

## bulk404 — paired bulk history and target viewport repair

The fitted bulk sheet collapsed the relation target scroll area to zero height:
Contact was selectable, but neither Alice nor Bob was visible or accessible.
Giving that LazyVStack viewport a bounded 170-point height fixes the installed
route. This is a one-line Mac UI change; no relation engine/history format change.
The internal optimized app was rebuilt and its ad-hoc signatures verified, with
no version change or DMG. Baseline and candidate use the same owned fixture.

The repaired picker exposes both eligible targets. Add Alice across Alpha/Gamma
reviews exactly those sources and Alice; Cancel preserves every vault byte/file.
Apply retains Bob and the unresolved reference and adds both hidden inverse links.
After review, outside edits to unrelated source and inverse metadata cause Undo
to refuse atomically. Refresh and fresh Undo restore the original graph while
keeping those later edits; Redo restores the paired links and retains the edits.
Bob, Control and schema stay byte-identical, and bodies/BOM/CRLF survive.

Normal quit/reopen retains the applied receipt and a correct actionable Undo
review. Cancel/readback changes no files. Three native sessions exit 0. The direct
installed baseline/fixed workflow verifies this layout repair; no new test or
unrelated suite was added. The final aggregate remains pending. Local frontend
and private preview proxy both return 200. Evidence:
artifacts/native-macos/bulk404/verification.json. D11 move/gesture/overlap/provider
routes and the other checklist gates remain; this is not full parity acceptance.

## relations403 — installed paired editing and definition changes

The installed picker resolves a legacy target, retains its unresolved sibling,
and restricts offered targets to Contacts. A review names Alpha/Alice/Bob; Cancel
preserves every vault file. Saving adds inverse links to both targets and retains
Bob's existing Gamma link. Bob's visible inverse field lists Gamma and Alpha.
Removing Alice after an outside target edit refuses without any writes. Reopening
with fresh state permits removal while retaining the later foreign-field edit,
Bob/Gamma links and unresolved target. An empty inverse is cleared by removing
its field key, not by retaining an empty array.

A reviewed Owner→Contact rename updates the Work keys and retains the pair ID.
Inverse hiding updates schema visibility without deleting inverse data; unknown
source/inverse settings and root metadata survive. Normal quit/reopen retains
the forward field and hidden inverse, and readback changes no vault bytes. Both
sessions exit 0. CLI data agrees; bodies, BOM/CRLF and the outside Control survive.

The two existing repair-owner tests pass on current sources: inferred definitions,
unresolved preservation, peer-window publication and outside-edit/private-draft/
previous-workspace refusal. This is not installed repair-screen acceptance; that
route remains behind the Settings automation failure. Paired bulk Undo after
later edits remains D11, and broader provider/keyboard/VoiceOver remain global
gates. No production source/test/version/DMG change. The preview already had a
live healthy listener despite the stopped parent-command report; no duplicate
server was started. Evidence: artifacts/native-macos/relations403/verification.json.

## properties402 — installed definition lifecycle completed

Creation of a Text definition changes only the schema file. A reviewed Number→Text
change retains all note bytes, matching current desktop `updateTypeProperty`
semantics. The new field accepts a value, and the converted field accepts text.
A reviewed removal of Work's Status lists only Alpha's value; Beta's deeper
same-named override is excluded. Cancel changes no files. Apply removes the parent
definition/value while retaining the child definition/value and its unknown
setting. Beta and the outside Control retain exact bytes and modification dates;
all note bodies and BOM/CRLF are preserved.

Normal quit/reopen retains the new/changed fields and child override, and CLI
readback agrees. Readback changes no vault files; both native sessions exit 0.
The existing schema-review guard owner also passes on the current recovery lookup:
private drafts, changed schemas/new values and a changed workspace still block a
commit. No new tests or production changes, build, version or DMG. Together with
properties401 this accepts the functional definition lifecycle. Provider and
broader keyboard/VoiceOver remain cross-cutting gates; relation repair remains D08.
Evidence: artifacts/native-macos/properties402/verification.json.

## properties401 — installed typed fields and inherited rename

Installed native forms reject invalid numbers and impossible dates, then save a
number, single-choice list, boolean and ISO calendar day correctly. The child
note inherits numeric/checkbox/date fields while its own Status choices override
the parent. A Work Score→Estimate review lists exactly Alpha and its child Beta.
Cancel changes no vault bytes/inventory. An outside edit after review makes Apply
refuse without writes; Reload definitions and a fresh review then rename both
values while retaining that edit. Child Status definitions and unknown settings
stay intact, note bodies/BOM/CRLF survive, and an outside-folder Control stays
byte-identical. Installed inspector and final CLI readback agree; normal quit
exits 0. Definition creation/removal/conversion, relation repair, providers and
broader keyboard/VoiceOver remain. No source/test/build/DMG/version change.
Evidence: artifacts/native-macos/properties401/verification.json.

## settings400 — installed access retry remains a tool limitation

On the current performance399 app, Settings AX capture again reports “Sky
Computer Use native pipe closed before response.” Screenshot capture reports
the same error; Escape reports Computer Use inactive and requires the failing
state route. The app remains live and its owned editor change autosaves with
exact bytes. Appearance preferences remain unchanged. Historical service crash
reports are retained for context, but no new report is attributed to this attempt.
The verified owned QA process is terminated after saved-byte verification
(exit143), not claimed a normal quit. No product rewrite or new test/build.
Installed Settings/appearance/pane acceptance remains pending; other native
property and schema sheets are accessible in properties401. Evidence:
artifacts/native-macos/settings400/verification.json.

## performance399 — measured navigation cost and installed recovery

Optimized hosted workspace measurements now separate current-editor readiness
from later saved-history completion. The owned 1,003-note fixture covers startup,
ordinary/mixed/large-root note opening and retained reopening, NSTextView edits
with exact Undo, scroll commands, folder/search/Gallery changes and guarded close.
These are owner/layout/display-drain measurements from an offscreen window, not
physical input-to-screen or compositor frame latency. First large-note rendering
remains expensive. History completion time is not treated as an interface freeze.

A baseline main-thread sample identifies recovery-directory filename matching:
every note activation constructs URLs for all unrelated entries before filtering.
`locations` now enumerates fresh names, filters the same original/canonical hash
keys and `.json` rules, then constructs only matching URLs. Checkpoint barriers,
symlink/unreadable-file guards and current disk reads remain. There is no directory
or content cache. No recovery records are removed to manufacture an improvement.

Three alternating original/candidate process pairs, 200 Inbox/Work switches each,
show a modest readiness improvement (comparison.json); repeated observations are
correlated, descriptive workload evidence. It does not close whole-interface
responsiveness. Five lifecycle checks and the retained-editor Undo owner pass;
no timing XCTest or new test seam. Only MacNoteRecovery.swift changes from the
frozen source/test/config snapshot. Diagnostic library linking uses the exact
optimized arm64 object files; the internal app is optimized testable Release.

The signed internal app also verifies a new owned Unicode recovery checkpoint:
text is discovered, explicitly saved with exact BOM/CRLF/foreign metadata, and
the seed checkpoint is removed by normal save. The earlier rules397 Return repair
is now installed: Return plus following plain paste saves exact child-owned
Markdown; navigation retains Undo and two Undo actions restore the original note.
Normal quit exits 0. Every benchmark original file remains unchanged. No DMG,
version, iOS or AI change. Evidence:
artifacts/native-macos/performance399/verification.json.

## board398 — installed reviewed board moves and durable recovery

An owned three-note Kanban fixture verifies two-card selection and native menu
moves. The review lists exactly the selected paths. Cancel leaves every vault
file and inventory unchanged. The applied move changes both Status values and
keeps BOM/CRLF, bodies and foreign fields; the unselected peer remains exact.
Organization history's reviewed Undo/Redo restores/reapplies the values. An old
review refuses a subsequent outside edit. Refresh and a fresh Undo review then
restore both Status values while preserving that unrelated foreign-field edit.
Property Undo uses normal YAML quoting; no raw-header-spelling claim.

The native column-right control saves No value, Review, Draft, Done order.
Normal quit/reopen restores that order and the two Draft cards in collection-only
Kanban. All vault bytes remain unchanged by this readback; both sessions exit 0.

One coordinate card drag again leaves state unchanged; pointer delivery remains
unverified, with no product/OS/automation cause inferred. The already inconclusive
column gesture is not repeated. These failures do not invalidate the independently
verified menu/review/history/control workflows. No source/test/build/DMG/version
change; current installed app is navigation394, before rules397. Evidence:
artifacts/native-macos/board398/verification.json.

## rules397 — empty quoted child receives divider Return

Return after an item-owned quoted divider followed by an empty child now selects
that child's body outside the inner quote. It no longer creates a root-level
item and leaves an extra empty child. Existing parser ownership/rebasing checks
remain; the completed edit retains the child's head typing role and one Undo
transaction. Before-rule, flat-empty-child and nonempty-child policies remain.

The pinned mounted desktop editor provides the receiving-child reference. The
new hosted owner case fails twelve assertions before repair and passes after it,
covering LF/CRLF, an outer quote, independent parser structure, exact output,
following typing and Undo/Redo caret restoration. All 99 MacDocumentTests pass;
a final head-typing adjustment is then covered by the two affected Return owners.
No timing assertion or production test seam. No ordinary typing/export work is
added. Compact divider-only probes place text outside the source list in the
reference and are recorded separately, not silently copied as desired behavior.

Installed acceptance was subsequently completed in performance399; Return,
following paste, exact saved bytes and retained Undo are verified there. No DMG/version/iOS/AI change. Overall
responsiveness and the remaining delivery checklist are not closed. Web frontend
and private proxy both return 200. Evidence:
artifacts/native-macos/rules397/verification.json.

## responsiveness396 — current installed functional load check

On the existing owned 1,003-note fixture, ordinary note opening, folder/search
navigation, Gallery-only switching and progressive scrolling, and retained
11,066-word mixed-note opening/scrolling complete. Exact Unicode paste survives
save/navigation and native Undo restores the original note. Normal quit exits 0;
all original files are byte-identical. Only six automatic-history records and
the expected Research Gallery view file are added to this disposable fixture.

This does not close responsiveness or physical typing/IME acceptance. CUA's
scripted typeText arrives altered, and its keyboard Undo does not act, while the
native Undo button and exact paste do act. Keep that input-delivery limitation
separate from product evidence. Tool-call duration includes dispatch, capture
and waits; no input-to-display latency or speedup claim. No product/test/build/
version/DMG change. Evidence: artifacts/native-macos/responsiveness396/verification.json.

## compatibility395 — two-way shared-data acceptance

Current web data owners run over a confined real filesystem adapter, followed by
real Rust CLI writes, compiled native VaultFiles owner writes, another web write,
and native/CLI readback. Typed booleans versus strings, numeric values, Unicode,
foreign YAML fields, stable IDs and reciprocal paired relations survive. Task
list/category, scheduled/due dates, linked note, priority and completion state
survive; Table/Calendar/Gallery/board configurations retain all/any property/date
filters, column order and visible fields through the exercised changes.

Four revisions and mixed desktop/Apple-app automatic history reconstruct. All
eight original/frozen image files retain the original PNG hash. The installed
native app displays the final one-row filtered Table, task dates/priority/state,
both pins (including a legacy quoted-true flag), reciprocal relations, four
revision buttons and selected history content with its saved image. Normal quit
exits 0. All three notes, tasks/views and image bytes still match the pre-UI
readback; the untouched Control note remains byte-identical to its initial file.

This closes the explicit shared-format matrix for those fields, not all D25.
The web execution is real data-module code, not live React/Tauri UI, actual
Tauri IPC or provider transport; Windows UI was not exercised. Web's existing
UTF-8 decoder semantics are used, so this is no claim of web BOM/header-byte
preservation. Native retains Beta's BOM. Locations/Drive references, saved links,
companion/private-preference migration and broader provider acceptance remain.
No product/test source changes, project suite rerun, version change or DMG.
Evidence: artifacts/native-macos/compatibility395/verification.json.

## navigation394 — core navigation and guarded tab close

Installed checks on one owned 12-note vault accept the core folder/Gallery/note
flow, completely hidden/restored folders, tab pin/unpin/menu move, background close,
Back/Forward, retained native Undo/Redo and independent second-window navigation.
A temporarily unavailable open file refuses window close and retains text;
restoring its exact bytes clears the condition and permits close. Native save,
Undo and Redo preserve complete BOM/CRLF/foreign metadata bytes.

Two tab-close gaps are repaired against the actual reference code: middle-button
close, including pinned tabs, and selecting the nearest surviving neighbour after
an active close. A middle-only AppKit target calls the existing guarded close
owner; ordinary/triple-left and collection alternate-open semantics remain.
The existing close owner still refuses a failed save before removing the tab/pin.
Coordinate-based installed middle clicks close background and pinned active tabs;
the latter selects the neighbouring Work Gallery without an editor. Normal quit
and reopen retain that collection and do not resurrect either closed tab.

One new transport/lifecycle owner uses rendered tab-title pixels and real owned
AppKit events. The original source fails six intended close/state assertions;
ordinary/full-triple controls pass. The final four focused checks pass: that
transport, pinned lifecycle, retained Undo and shared Calendar alternate gestures.
Earlier unavailable local AX trees and incomplete gesture probes are explicitly
excluded from regression evidence. No unrelated full-suite repeat; the last
complete 281-check aggregate is performance393, and final aggregate coverage must
include the new method. Optimized build and installed signature/bundle checks pass.
All 12 original notes are restored; only the expected Gallery configuration and
five automatic history entries remain in the disposable fixture.

D12 is not fully closed: one actual tab drag leaves order unchanged, and two
horizontal-overflow scroll routes leave the visible position unchanged. Their
input delivery/cause is unverified. No speculative drag API rewrite. Keyboard/
VoiceOver and overall responsiveness remain their separate acceptance work.
The owned QA app remains open on Work Gallery. No DMG, version, iOS or AI change.
Evidence: artifacts/native-macos/navigation394/verification.json.

## performance393 — bounded reuse of note-opening admission

Repeated opening of a retained editor now reuses its automatic rich/Source
admission only for an exact UTF-8 body match. The window retains at most four
source values, each no larger than 1 MiB UTF-8, and clears them on successful
vault activation. Changed/larger bodies retain the full parser check; other
admission paths, manual mode behavior and rich admission are unchanged.

The existing container-mode owner adds warm reopening after outside edits switch
rich→HTML Source→rich, with current-byte assertions. Original and candidate pass
both focused mode/retained-Undo owners; these are performance controls, not a
bug-regression baseline claim. All 275 non-AI/non-OCR checks pass on frozen inputs.
The six unchanged OCR checks also pass in a separate current-candidate process;
the union verifies every one of the 281 configured non-AI identifiers exactly once
across five fresh processes. The prior monolithic host failure remains separate.
The signed optimized app passes warm switching and outside replacement/restoration
in the owned 1,003-note vault. All 1,014 fixture files are restored, both sessions
quit normally, and source/test/version inputs remain frozen. A stale AX target
during inventory reordering was resolved by obtaining fresh IDs.

Separate 15-second captures no longer show the repeated admission frame on warm
reopening. They are inclusive stack observations, not CPU milliseconds, call counts
or end-to-end latency; compiler symbols/inlining, AX overhead and differing
restored pane widths limit comparison. No whole-interface speed claim. The app
remains 0.3.85/build125; no DMG, iOS or AI change. Evidence:
artifacts/native-macos/performance393/verification.json.

## resources392 — QA storage headroom and unchanged OCR checks

No app, source, test, resource, configuration, version or DMG change. Completed
owned result bundles contained repeated byte-identical data. Replacing 357 data
entries with independent APFS copy-on-write clones retained every path and byte,
permissions, modification time and extended attributes. The operation used no
hardlinks and deleted no result evidence; inode and birth time change. All target
hashes/modes/mtime and source independence were rechecked. Representative failed
and passed bundles retained their original readable results. The 323 frozen Swift
inputs, four compiled/configuration inputs and installed rules391 executable
remain unchanged. Reported available space rose from about 1.5 to 4.8 GiB during
the batch; system activity affects free-space readings. This is QA headroom,
not evidence of reduced interface latency. The initial memory snapshot showed
64% free, so existing swap allocation did not establish current memory pressure.

The original standalone default-revision Vision probe then recognized both
expected labels. All six previously excluded original OCR tests passed together
unchanged, exit 0, with exact identifiers verified. A subsequent complete non-AI
run exercised all 281 intended identifiers in one process: 278 passed, three
failed, exit 65, no skipped or duplicated tests. Footer word count, large-note-list
loading and live outline failed after missing E5 model-cache resource messages;
XCTest reported Cocoa errors about already-absent private draft directories and
error-sanitization warnings. The relationship between those reported errors is
not established. The focused success does not resolve the combined-run failure,
prove a disk-space root cause or close the complete non-AI gate. No Vision model,
cache, compute-device or oracle workaround was applied. An early result read
before Xcode finalized its bundle was retried successfully after process exit.

Evidence: artifacts/native-macos/resources392/verification.json, exact test trees,
commands/logs, clone journal and preservation checks. The earlier frozen 275
non-AI/non-OCR pass remains valid; the complete gate, broader installed parity,
performance, pointer drops, Settings and final packaging remain open. AI deferred.

## rules391 — leading Return before an unowned divider

A root or root-quote divider now keeps the selected side when a caret Return
opens its receiving paragraph. The generic fallback previously excluded newline
from its before predicate and routed both edges below the attachment. The new
predicate changes Return only when there is no list owner; item-owned split and
selected-node paths retain their own policies. The existing commit/caret/typing
transaction remains, with a before/after Undo label. No new ordinary-typing scan,
parser pass, state cache or admission widening.

The same owner exposes a CRLF fidelity bug in the dash-rule safeguard. A Swift
String suffix check did not recognize CRLF as either one-character suffix, so it
added an extra line before the required separating blank. The final-byte UTF-8
check recognizes LF/CRLF/CR while retaining the independent parse that prevents
setext conversion.

Ninety workflows extend the existing horizontal-rule owner: both caret edges,
three markers, root/one-/two-level quotes, prior/following text, EOF, LF/CRLF,
exact source, independent AST body order/quote depth, admission and Undo/Redo
selection. The final original run fails 180 assertions on wrong leading-edge
order; trailing controls pass. The first candidate fixes placement but fails 12
unchanged exact/Redo assertions for doubled CRLF gaps. The final owner and frozen
275 non-AI/non-OCR gate pass. No new test method, timing assertion or private
production seam. An initial fixture incorrectly inferred CRLF from a bare EOF
rule; invalid duplicate rows were removed before rerunning the final original.

Thirty-six mounted pinned-reference DOM cases include actual app preparation,
which leaves every source byte-identical. Ordinary unquoted root Return confirms
the selected side. Native retains original marker spelling and safe tighter gaps.
Compact and quoted synthetic inputs displace text toward the document end; that
behavior is not adopted as intended input semantics or claimed fixed. These are
synthetic DOM/package probes, not trusted physical React input. Compact/empty
list-owned divider Return and broader ordinal/container behavior remain open.

The optimized signed native app verifies leading Return plus physical New key
input in three owned files: unquoted dash, nested quote and EOF. All complete
expected BOM/CRLF/foreign-Unicode saves match, including the EOF file without a
final newline. Typing Undo restores the entered snapshot, Return Undo restores
the original, Redo reproduces the expected file and final Undo restores all four
note hashes. Rich text stays active; Root New is visibly above the divider; Quit
exits normally. Source/test hashes stay frozen through gate/build/native QA.
Internal app remains 0.3.85/build125; no DMG, version, iOS or AI change. Review is
manual only. Evidence: artifacts/native-macos/rules391/verification.json.

The prior Vision revision1/2 controls already fail the same E5 runtime error13;
no rejected CPU/cache workaround or weaker oracle was retried. Six OCR checks,
Kanban pointer delivery, Settings automation, broader performance, migration,
accessibility, full parity and final packaging remain open.

## board390 — isolate pointer-drop delivery before changing production

The current performance389 signed app is checked on a fresh copy of the
three-card board fixture. In Select mode, the selected First card's title drag to
Done leaves the board unchanged. A Draft-header drag highlights Review as a drop
target but does not reorder; a pointer click clears the highlight. Keyboard Tab
visibly activates the window before those controls. All five vault file bytes,
dates and history remain unchanged, and native Quit exits normally.

An owned standalone SwiftUI/AppKit diagnostic then removes the board scope and
planner. Its first ordinary String drag produces SwiftUI hover true/false but no
drop callback. On a fresh launch, the raw AppKit source/destination completes the
first gesture with a readable payload, correct target coordinates and copy
operation. A SwiftUI String source enters that AppKit target but does not perform
the drop. A further fresh launch's legacy String Button.onDrag creates its item
provider but never reaches its onDrop callback. Later gestures in an already-used
session are explicitly weaker evidence. A compiled own-process register variant
was not exercised and is not runtime evidence.

These controls establish a lower-level delivery problem beyond the board guard,
but do not identify a CUA timing defect, OS/framework defect or board implementation
defect. Do not replace production APIs on this evidence alone. Kanban pointer
acceptance remains open; menu moves and their accepted safety checks still stand.
The initial relative-path scratch run required TERM cleanup after inconclusive
keyboard/menu Quit; the later absolute-path diagnostic runs quit normally. The
menu tool error and one handled stale app-binding error are recorded separately.
No alternative input automation was used.

No production/test/resource/configuration or version change, project test rerun,
production app build or DMG was made. The 323 Swift source/test hashes and current
installed executable remain unchanged. Scratch apps use only synthetic payloads,
not a vault, network or private state. iOS is unchanged and AI remains deferred.
Evidence: artifacts/native-macos/board390/verification.json. A reliable SwiftUI
gesture control or trusted physical drag acceptance is still needed; other
non-AI parity/performance work can proceed independently.

## performance389 — ordinary quote prose without full-note typing export

Fresh render and rebuilt export maps now include independent, nonempty,
one-source-row quote prose with a fixed ASCII quote/space prefix. Before local
replacement, all runs must retain that block and independent role, contain no
list/card/literal/attachment or logical-break roles, and still form one complete
native paragraph. Imported indentation that could resurrect normalized source is
excluded. A following unowned blank must remain at root or the same quote depth;
its bytes are kept outside the replacement. The local result must still be one
source row. Multiline, list-owned and contextual cases use the full exporter.
Whole-document standalone detection still excludes quotes, so complete mixed
exports retain list/card and independent-boundary work.

Six rows extend the existing repeated-edit owner; two extend its composition
sibling. They cover nested/compact quote spellings, preceding lists, following
structural blocks, quote EOF, LF/CRLF/CR, formatting, external storage edits,
reload, composition commit/cancellation and Undo/Redo. Both original388 and final
candidate pass these behavior controls. An initial EOF fixture put Omega before
Alpha despite the shared storage-edit helper's required descending order; that
fixture-only failure was corrected before the final original run. No new test
method, private cache assertion, timing assertion or production seam was added.
The frozen 275 non-AI/non-OCR checks pass; six OCR checks remain open. Review is
manual only.

Matched native captures use the same 1,003-note synthetic vault and 84,658-byte,
600-section mixed note. Three key presses after Alpha produce complete expected
source in both optimized installed builds. Keyboard-path stack observations are
335 before and 11 after; serialization observations are 328 and 1. These are
inclusive overlapping samples from one 15-second, nominal-1-ms capture per build,
not CPU milliseconds, input-to-display latency, statistical acceptance or a
whole-interface speed claim. Compiler and accessibility effects still apply.

Native typing, Undo/Redo, an edit to the second quote paragraph and physical
Portuguese é/ã input save exact expected files. A provisional dead key leaves
original disk bytes unpublished. Complete BOM/CRLF/foreign metadata bytes survive,
all 1,003 note hashes finish at original values, Rich text remains active and Quit
exits normally. Source/test hashes stay frozen through gate/build/native QA.
Internal version remains 0.3.85/build125; no DMG, iOS, AI or version change.
Evidence: artifacts/native-macos/performance389/verification.json.

Contextual exports, broader performance and installed workflows, remaining parity,
accessibility, migration and final packaging remain open.

## performance388 — reuse the original divider item mapping

Quoted-divider caret Return no longer serializes/parses the unchanged original
note twice when a receiving child has already been resolved. That successful
lookup carries its item array only through the same synchronous preparation.
The transformed output still receives its own parse, parent comparison and ordered
head-identity check. Nil-child and before-divider fallbacks, selected-node Return,
ordinary typing and persisted state are unchanged. No global cache or timing test.

The existing divider owner and frozen 275 non-AI/non-OCR checks pass. Tests were
not changed; the original387 owner pass is a behavior control, not a newly failing
bug baseline. Manual review records why the immutable mapping is still valid.
Six OCR checks remain unverified; no independent review was run.

A matched native capture uses the same 1,003-note synthetic vault and 84,632-byte,
600-section mixed note with a quoted divider, child and child-owned grandchild
quote. One Return per optimized installed build is sampled for 15 seconds at a
nominal 1 ms interval. Main-thread keyboard-stack observations are 535 before and
445 after; item-mapping observations are 367 and 279. These are overlapping
inclusive sample counts, not CPU milliseconds, measured input latency or a
statistical whole-interface speed claim. Compiler inlining and accessibility
work affect attribution. Remaining commit/refresh work is still substantial.

Native Return saves the complete expected BOM/CRLF/foreign-Unicode file. A later
x key lands in the receiving Child body. Undo typing, Undo Return, Redo Return and
final Undo all match their complete expected files; all 1,003 note hashes finish
at the original values. Rich text and visible indentation are checked, Quit exits
normally, and source/test hashes stay frozen through gate/build/native QA. The
internal app remains 0.3.85/build125; no DMG, iOS, AI or version change.
Evidence: artifacts/native-macos/performance388/verification.json.

## rules387 — quoted children and receiving-child caret

Divider caret Return now rebases child/grandchild source prefixes and crossed
quote-parent snapshots while preserving quotes owned by a later child. Before
committing preparation, the parser parent graph and ordered list identities must
match the original. After the existing item split, an after-divider caret selects
the parser-resolved first child's body; new text starts plain while original
bold, link and inline-code spans retain their attributes. Selected-node Return is
unchanged. There is one existing commit/Undo transaction and no new ordinary
text-input work. Structural Return ownership parsing was not cost-profiled in this milestone;
performance388 records the later long-note measurement.

Twenty mounted pinned-editor DOM cases and actual app preprocessing are recorded.
The reference confirms quoted child caret placement and child-owned quotes. Native
keeps a parent-owned Tail separator and explicit empty-wrapper row spelling;
the reference exporter uses compact markers and omits that separator. Flat source
is already reordered by web import (Tail before child); native retains source
order and selects the first source child. These are recorded source-fidelity and
representation differences, not exact web export parity or trusted React input.

Nine rows extend the existing hosted divider owner: quoted/flat child lists,
grandchildren, multiple quote levels, child-owned quote paragraphs/list items,
and bold/link/inline-code bodies. LF/CRLF, enclosing quote, both caret positions,
exact source, independent AST owners, admission, typing and Undo/Redo selection
restoration are checked. Original386 fails 172 assertions for stale quotes/caret;
the candidate and frozen 275 non-AI/non-OCR gate pass. No new test method, timing
assertion or production test seam. Six OCR checks remain open; review is manual.

The optimized signed app opens the child-owned grandchild-quote fixture in Rich
text. Before/after divider selection with Return and Shift-N/e/w input saves exact
expected BOM/CRLF/foreign Unicode metadata files. The child transfers correctly,
the grandchild keeps its own quote, and after-divider New lands in Child rather
than the wrapper. Visual indentation is checked. Undo restores both original
notes, Redo reproduces the changed file, final Undo restores originals and Quit
terminates normally. All source/test hashes remain frozen through gate/build/QA.
Internal app stays 0.3.85/125; no DMG, version, iOS or AI change.

Compact/empty child groups, broader card/EOF/ordinal behavior, performance,
accessibility, migration, full parity and final packaging remain open.
Evidence: artifacts/native-macos/rules387/verification.json.

## rules386 — deeper direct quotes and retained paragraph boundaries

Caret Return beside an ordinary item's divider now leaves all direct inner quote
levels at the item split. The385 preparation already rebases card spelling,
quote-only gaps and item identity; this change removes its one-depth restriction.
The selected-node path, nonempty-head guard and normal single Undo transaction
are retained. No new ordinary-typing work or rich admission.

A fresh mounted WKWebView probe of the pinned editor covers six before/after
cases with two inner quote levels, a following outer-quote paragraph and a
numbered control. The actual prepareNoteLinks/prepareMarkdownForMdxEditor chain
leaves every input byte-identical. The reference leaves all inner quote wrappers;
its exporter also joins Tail and Outer tail directly. Native deliberately keeps
the separate paragraph boundary. This is a recorded source-fidelity difference,
not a claim of exact web export parity. The probe remains synthetic DOM input,
not trusted physical React input; ordered-start/trailing-anchor normalization is
outside literal native expectations.

Two rows extend the existing hosted divider owner for both caret positions,
LF/CRLF and an enclosing quote wrapper. Original385 production fails 48 assertions
for the intended split/ownership defect. Exact source, independent parsed owners,
admission, typing and Undo/Redo selection restoration pass in the candidate and
the frozen 275 non-AI/non-OCR gate. No new test method, timing assertion or seam.
Six existing OCR checks remain open. Manual review only.

The optimized signed app opens the nested source in Rich text. Native attachment
boundary selection followed by Return and Shift-N/e/w input passes before and
after the divider. Full BOM/CRLF/foreign Unicode metadata files match expected
bytes, distinct Tail/Outer tail paragraphs remain, visual indentation is checked,
and Undo restores both original notes. After-divider Redo matches the changed
file; final Undo restores originals. Normal Quit, frozen source/test hashes and
unchanged 0.3.85/125 are verified. No DMG, iOS, AI or version change.

Compact empty heads, nested quoted child-list variants, broader card/EOF/ordinal
behavior, performance, accessibility, migration, full parity and final packaging
remain open. Evidence: artifacts/native-macos/rules386/verification.json.

## rules385 — caret Return beside an inner-quoted divider

An ordinary nonempty item with one inner quote now uses the item split for caret
Return immediately before or after its divider. Before Return ends the old quote
and moves the divider/following direct blocks to the right item outside that
inner quote. After Return keeps the divider quoted with the old item and starts
the right item with the following body. An outer quote is retained. Preparation
rebases quote-only gaps and immutable card placement suffixes together; original
source remains available to Undo. The selected-node path is unchanged. No new
ordinary-typing work, rich admission or production testing seam.

The existing hosted divider owner adds one source row for both caret positions,
LF/CRLF and an outer quote wrapper. Its selected-node variant already exists and
is not duplicated. Handwritten exact sources, independent CommonMark owners,
admission, follow-up typing, Undo/Redo and restored selection are checked.
Original production fails 24 assertions for the intended ownership/split defect;
the corrected focused owner and frozen 275 non-AI/non-OCR gate pass. A recursive
first candidate and a blank-indentation second candidate were rejected; their
failed logs are not passing evidence. Six OCR checks remain open.

The optimized signed app passes both caret positions with physical CUA Right,
Return and Shift-N/e/w keys. Complete files match expected BOM/CRLF/foreign
metadata bytes. Undo restores both original fixture note hashes; after-divider
Redo reproduces the exact changed file, and final Undo restores originals. The
app quits normally. All source/test hashes remain frozen through gate/build/QA.
Internal app stays 0.3.85/125; no DMG, version, iOS or AI change. Manual review only.

Compact empty heads and deeper inner quotes retain their previous fallback.
Nested quoted child-list variants, broader quote/card/EOF/ordinal behavior,
performance, accessibility, migration, full parity and final packaging remain
open. Evidence: artifacts/native-macos/rules385/verification.json.

## board384 — current-column menu choices and keyboard moves

The current signed app reproduced a false “The board changed” alert when the
card menu chose a column already occupied by every selected card. The private
menu action now runs the existing live drop-admission check before scheduling
preparation. Both the visible menu and context-menu route share that action.
Accepted moves keep the existing preparation and post-await commit checks.
This adds no work to rendering or typing and changes no drop/permission policy.

Installed verification covers keyboard current-column choices for one and two
cards: no alert, changed vault byte, file date or history entry. Home/Return on
“No value” removes only Status, keeping BOM, CRLF, body and foreign metadata.
Organization-history Undo restores Done, then Draft. A cleared key is reinserted
after Foreign, so this is semantic property Undo, not lexical byte restoration.
A two-card Done choice still reviews exactly those two notes; Cancel preserves
all vault bytes/dates/history and the selection. After normal Quit, QA cleanup
separately restores the original note spelling; all five baseline fixture files
match. That cleanup is not evidence of byte-exact Undo.

The existing three board scope/array/typed-property/Undo owner checks pass, and
the optimized build and signed-app verification pass at unchanged 0.3.85/125.
No new test method, timing assertion or production seam. Native before/after
behavior is the menu regression evidence. The full non-AI gate was not rerun
for this localized UI guard; six OCR checks remain open. Source/test hashes were
frozen through builds, checks and installed verification. Manual review only.

One title-region pointer drag again left the board/files unchanged. This does
not distinguish automation delivery from a product defect; drag-only acceptance
remains open. No DMG, iOS, AI or version change. Broader performance, input,
migration, accessibility, full parity and final packaging remain open.
Evidence: artifacts/native-macos/board384/verification.json.

## performance383 — installed search and Gallery follow-up

Read-only main-thread sample inspection confirms that Outline computation already
uses a serial background queue, a short debounce and latest-input coalescing.
Separate installed List and Gallery captures while typing a local query do not
establish a new material stall that warrants changing search semantics. They are
diagnostic samples with accessibility overhead, not input-to-display timing,
statistical acceptance or a before/after performance claim. Navigation preference
writes remain a synchronous path worth tracking; no storage change was made.

On the owned 1,003-note fixture, local query typing and clearing return the
expected counts in both layouts. Opening Control from Gallery displays its note
without the collection; Browse notes returns Gallery without the editor. The
folder sidebar completely hides and restores. The app quits normally and every
original note hash remains exact. Source/test hashes and the installed executable
match accepted382. No implementation, tests, build, version, DMG, AI or iOS change.
The prior frozen gate remains applicable; it was not rerun for read-only QA.
Broader performance, drag-only delivery, migration, accessibility, six OCR checks,
full non-AI parity and final packaging remain open. Manual review only.
Evidence: artifacts/native-macos/performance383/verification.json.

## performance382 — ordinary quoted heads and blank quote boundaries

The item-head prefix policy now accepts fixed ASCII quote/space prefixes. Marker
spacing, pure-space indentation, one nonempty native/source row, immutable context
identity and attribute checks remain. Inherited inner-quote roles, contextual
bodies and shared compact markers stay excluded. An unowned blank successor may
retain its own source at the same quote depth when its block contains only ASCII
spaces/quote markers; owned gaps/continuations, changed quote depth, cards, rules
and nonblank successors retain full fallback. The blank is never respelled.
No whole-document parse pass, async work or new rich admission was added.

Six quoted fixtures extend the existing repeated-edit owner: bullets, numbered
and task lists, compact/spaced double quotes and leading-space quote spelling,
including quote-only blank successors. The existing hosted composition owner adds
ordinary quoted caret cases with following heads and blank quote lines, commit
and empty cancellation, all with LF/CRLF/CR. Exact source/full serialization,
formatting, Unicode, repeated edits, Undo/Redo, reload and external-storage controls
pass on original and candidate code. These are behavior-preservation controls,
not claimed failing bug regressions. No new test method, timing assertion or
production seam. The frozen 275 non-AI/non-OCR gate passes, with all source/test
hashes unchanged through build and native verification.

Fresh optimized381 baselines and updated382 captures use the same owned
600-section note and three keys. Quoted-child keyDown observations are 318 before
and 18 updated; the item followed by a blank quote line is 319 before and 17
updated. Each is one 15-second macOS sample, nominal 1ms. These are observations,
not CPU milliseconds, latency or statistical acceptance. Counts overlap, CUA
performs AX work, and compiler inlining affects attribution. Serializer function
names alone cannot distinguish local-row and whole-document calls.

Native saves match complete expected files in both cases; blank-boundary Redo
matches too. A current Portuguese layout read precedes physical acute/e and
tilde/a input in the quoted child. Provisional accent input leaves disk unchanged,
committed text matches the expected file, and Undo restores all 1003 original
note hashes. Both sessions Quit normally. The internal app stays 0.3.85/build125;
no iOS, AI, version or DMG change. Review is manual; independent autoreview was
not run. Six OCR checks, contextual full-export work, broader performance/input,
migration, full parity and final packaging remain open.
Evidence: artifacts/native-macos/performance382/verification.json.

## performance381 — source-row reuse for ordinary nested heads

The sparse-export prefix policy now accepts fixed ASCII-space indentation on
ordinary nonempty item heads. Both fresh render mappings and completed-export
mappings share the policy. The existing checks still require one native/source
row, immutable context identity, an unchanged block/marker prefix, eligible inline
attributes and a safe following head/blank/EOF. Quotes, context bodies, inner block
roles, continuations and unsupported boundaries retain full fallback. Compact
shared-marker attributes are explicitly excluded because their physical source
may represent several native heads. Imported tabbed spellings retain their
renderer's initial fallback; a normalized completed row can later be eligible.
No extra parser pass, async worker, input-policy change or rich admission was added.

Six fixtures extend the existing repeated-edit owner: nested bullets, numbered
and task rows, grandchildren, deeper leaves, loose lists and a contextual-tail
control, with LF/CRLF/CR. Exact source/full serialization, formatting/Unicode,
repeated edits, Undo/Redo, reload and multi-row external storage changes pass on
both original and candidate implementations, as expected for behavior controls
around a performance change. No timing assertion, new test method or production
seam. Some contextual core controls retain Source admission; installed admission
is not inferred from the bare editor harness. Frozen 275 non-AI/non-OCR checks
pass; all source/test hashes remain unchanged through gate, build and native QA.

The installed accepted380 app/source hash was verified before replacement. Its
existing samples are reused explicitly as baselines. For the same three-key edit
in the owned 600-section note, Unicode keyDown stack observations are 294 before
and 10 updated; the warmed ASCII control is 313 before and 10 updated. Each is one
15-second macOS sample run, nominal 1ms. Counts are not CPU milliseconds,
input-to-display latency or statistical acceptance; they overlap and compiler
inlining affects attribution. The same serializer function serves local and full
exports, so frame names alone do not establish scope. Eligibility and source
controls support the measured row-reuse behavior; no overall responsiveness claim.

Native ASCII/Unicode saves match complete expected files. Unicode Redo matches;
Undo restores all 1003 original note hashes in each owned root. A current Carbon
layout read confirms the Portuguese dead keys. In the nested row, provisional
acute input leaves disk unchanged, physical acute/e and tilde/a commit the exact
expected text, and Undo restores every original note. Both native sessions Quit
normally. The optimized internal app remains 0.3.85/build125, with no new DMG,
iOS or AI change. Review is manual; independent autoreview was not run.

Six existing OCR-dependent checks, quoted/contextual full-export cost, broader
input methods and performance, migration, full parity and final packaging remain
open. Evidence: artifacts/native-macos/performance381/verification.json.

## performance380 — avoid repeated Unicode prefix indexing

The blank-source-line predicate used NSString length/indexing on the complete
emitted prefix. In the optimized Unicode baseline, the nested-edit sample places
74 keyboard-stack observations in UTF-16 breadcrumb/index preparation below that
helper. The candidate scans only the final UTF-8 source row and recognizes the
same CR/LF/CRLF, quote-marker and ASCII space/tab grammar. It adds no cache,
parser pass, async work, admission policy or source fallback change.

A scratch equivalence control compares original production Foundation behavior
against the candidate over 671858 generated/explicit inputs, including early
Unicode, line endings, quote-only and invalid quote-padding cases. All agree.
No new timing XCTest, test method, production seam or test source change. The
existing frozen 275 non-AI/non-OCR gate passes with exact identifiers and unchanged
inputs during each run. After the gate, one comment line was corrected to name
UTF-16 index preparation precisely; executable statements remain byte-identical
to the gate source, and all other source/test hashes match. The final source was
built into the optimized signed app used for native acceptance.

One 15-second macOS sample run per build/workload records three nested-list keys
in the same owned 600-section notes. Unicode keyDown observations are 395 before
and 294 updated (full serializer: 382 and 282). The ASCII control is 306 before
and 313 updated (serializer: 295 and 304). These are stack observations, not CPU
milliseconds or input-to-display latency. Actual sampling cadence varies, compiler
inlining affects attribution, counts overlap, and one run is not statistical
acceptance. No universal speedup or zero helper execution is claimed. The ASCII
runs are warmed by an identical three-key edit/Undo before capture.

An initial xctrace attempt was interrupted when it crossed its unchanged 4 GiB
disk floor; it is retained but excluded from performance comparisons. Text-based
sample avoids its temporary storage cost. The analysis reader was corrected to
accept both observed main-thread label formats and rejects absent keyboard data.
Older generated result bundles were reversibly archived with every file verified;
source, private files and delivered artifacts were not removed.

Native ASCII/Unicode saves match the complete expected source. Unicode Redo
matches too, and Undo restores all 1003 original note hashes in each owned root.
Normal Quit passes. Six OCR-dependent checks remain unverified after the existing
environment failure. No AI, iOS, version or DMG change. Full nested/contextual
exports still run and remain a major performance follow-up, together with overall
responsiveness, input methods, migration, full parity and final packaging.
Evidence: artifacts/native-macos/performance380/verification.json. Manual review
only; independent autoreview was unavailable.

## migration379 — native preparation from untouched legacy bytes

The existing signed fidelity378 app opens an owned unprepared legacy vault
without adding IDs, renaming notes, normalizing BOM/CRLF or rewriting comments.
Opening a missing-ID BOM/CRLF note and following its relative note link preserves
all original file bytes and paths, including the explicit shared-value control,
Trash note and foreign tasks JSON. Normal Quit also keeps the original inventory.

A scratch executable imports the actual accepted Debug module and calls the real
VaultFiles metadata review/apply owner; it contains no copied migration logic or
mock transport. Review-only proposes four IDs and two reserved-key renames with
no issues and leaves every original vault file unchanged. Applying a fresh review
writes exactly its shown changes. Independent raw-body comparisons preserve all
five note bodies, BOM, CRLF, foreign YAML/comments, original filenames and relative
link text. The explicit-false note and tasks JSON stay exact. A second review has
no changes. Only the expected vault manifest and note-history records are added.

The bundled real CLI runs against this explicit owned path and an owned fake HOME,
with no private registry or installation changes. Doctor reports a healthy vault;
get by a newly generated ID returns the exact CRLF body and shared pin flag.
Installed native readback shows only the expected pinned/archived note in each
section, keeps the explicit control in All Notes, offers Unarchive and resolves
the original relative link. The complete prepared inventory and bytes stay exact
through readback, Quit and CLI get.

No source, test, build, DMG, version, iOS or AI change. Actual Debug owner and all
source/test hashes match accepted378, whose 275-check non-AI/non-OCR gate includes
seven metadata/registration owner tests. No unrelated suite was rerun. This proves
native startup and the real owner boundary, not the installed Settings review,
UI Cancel or full profile migration. Settings CUA's service crash is still open
and was not retried unchanged. Companion startup normalization from360 and legacy
private browser preferences remain separate open items. Six OCR checks, broader
migration/performance, full parity and final packaging remain open.
Evidence: artifacts/native-macos/migration379/verification.json.

## fidelity378 — preserve boundaries after quoted headings and fences

Editing root prose immediately after a quoted heading or fenced code block used
to add a redundant blank line, and Undo retained it. These blocks already end
before the following root paragraph. The serializer now omits that generic
lazy-continuation separator for quoted headings and clears previous-paragraph
adoption state after fenced-code cards. Actual list/owned continuations and
ordinary quoted paragraphs retain their guards. Indented code and quoted-table
behavior remains conservative. No parser pass, initial export mapping, admission,
input handling or Undo implementation changed.

The existing repeated-edit owner covers six prefixes (heading levels, nested
quotes, backtick/tilde fences) with LF/CRLF/CR. Both following-prose and preceding
quoted-body edits preserve handwritten source, Undo/Redo and independent parsed
root-paragraph ownership. The final table fails on original production code with
108 assertions and passes on the candidate. Frozen 275 non-AI/non-OCR checks pass
with exact identifier coverage; six Vision-dependent checks remain blocked.

The optimized internal app passed complete-file comparisons for prose edits,
Undo and Redo after a quoted heading, edits/Undo within that heading, and prose
and code-body edits/Undo around a quoted fence. All three synthetic fixture note
hashes were restored, preserving BOM, CRLF, IDs and foreign metadata. Normal Quit
passed. Final source hashes match verification. One stale AX target was refreshed;
a diagnostic expected-value comparison was corrected to target only the code
line rather than also replacing the foreign metadata value. No product failure
was hidden by that correction.

This closes the quoted-heading/fence normalization detail recorded in375; it does
not establish every quote boundary or overall source/migration fidelity. No new
performance timing claim, AI, iOS, version or DMG change. Broader performance,
input methods, migration, full parity and final packaging remain open. Review is
manual; independent autoreview was unavailable.
Evidence: artifacts/native-macos/fidelity378/verification.json.

## performance377 — export tracking through ordinary composition

The text-storage delegate now retains and updates the sparse export map during
AppKit marked-text edits, rather than discarding it merely because text is
provisional. Commit still uses the existing final-row/context, metadata, boundary
and source-shape checks. Edits spanning rows or failing eligibility still rebuild
from the complete serializer. No input transport, publication scheduling, parser,
lifecycle, Undo or admission implementation changed.

Matched optimized native captures used one acute/e + tilde/a sequence at the
same root-prose caret in the same owned 600-section note. Original keyDown stacks
sampled 306 ms CPU, including two full-export bursts totaling 279 ms. Updated
stacks sampled 11 ms keyDown CPU and no fresh full-export frames. Each is one
25-second recording, not input-to-display latency or statistical responsiveness
acceptance. Inclusive weights overlap; CUA performs AX work, so whole-capture
CPU is not treated as pure typing cost. The earlier provisional-only recording
is retained but excluded from the complete-sequence comparison.

Native complete saved bytes and Redo matched the expected accented file. Undo
restored all 1003 original note hashes. A nested-child composition also matched
exact expected bytes through full fallback; Undo restored all original notes.
Normal Quit passed. Provisional accent input left the baseline saved file
unchanged. Ordinary caret controls extend the existing hosted composition owner
for root prose beside code, headings, root/nested lists, Source mode, LF/CRLF/CR,
empty cancellation, two accents and Undo/Redo. They pass on both original and
updated implementations as behavioral controls, not a claimed failing bug
regression. No timing test or production test seam was added.

The focused owner and frozen 275 non-AI/non-OCR checks pass with exact identifier
coverage. Six existing Vision-dependent checks remain environment-blocked. Final
source/test hashes match verification. Older generated result bundles were
reversibly zipped, with every file verified before removing the uncompressed
copy; the restore manifest is retained. No real vault, cache, delivered artifact,
AI, iOS, version or DMG change. Manual review only; independent autoreview was
unavailable. Broader input methods, physical Escape/cancellation behavior,
contextual first edits, quote-boundary Undo normalization, overall performance,
full parity and final packaging remain open.
Evidence: artifacts/native-macos/performance377/verification.json.

## performance376 — first edits in canonical list heads

Fresh source mapping now also retains nonempty canonical top-level list heads.
The prefix policy is shared with existing completed-export reuse: no indentation,
quotes, continuation/gap, inner block role or noncanonical marker spacing. On
edit, the same context, whole-row, attribute, content and neighbor checks apply.
No additional parse/serialize pass, asynchronous worker or admission was added.
Empty, nested, quoted and multi-paragraph/contextual rows retain full fallback.

An owned 600-section note's first root-list insertion plus three keys sampled
160 ms in keyDown before versus 44 ms updated. The updated capture sampled no
fresh whole-document Export.init. First-opening main-thread sampled CPU was
416 ms, compared with 408 ms in the preceding verified build's recorded opening
(load: 214 versus 216 ms). Each is one 25-second observation, not latency or
statistical responsiveness acceptance; inclusive weights overlap and automation
AX work prevents using whole typing totals as pure typing cost.

Complete expected bytes matched after the mapped list save and Redo. Undo
restored all 1003 original note hashes. A fresh reopening followed by a nested
child edit also matched exact expected bytes through the fallback, and Undo
again restored every original note. Normal Quit passed. The focused repeated-edit
owner and frozen 275 non-AI/non-OCR checks pass; six existing Vision-dependent
checks remain blocked, with no CI exclusions changed.

No AI, iOS, version or DMG change. Broader performance, marked-text/composition
cost, contextual first edits, quote-boundary Undo normalization, full parity and
final packaging remain open. Older generated results were reversibly archived
with byte verification for disk headroom; current accepted375 and376 bundles
were left live. Evidence: artifacts/native-macos/performance376/verification.json.

## performance375 — first-edit export state for mixed notes

Fresh rendering now retains exact source spans for eligible independent root
paragraphs/headings even when the document also contains lists, code or tables.
Unmapped gaps retain their original bytes. Edits must still fit one mapped row
and pass the existing block, paragraph, attribute and boundary checks; other
edits fall back to full export. Prose immediately after quoted/list/continuation
metadata is omitted from the fresh map so full export can establish its separator.
No full serialize/parse or asynchronous task was added to opening.

Matched optimized recordings on the same owned 600-section note observed 168 ms
original versus 41 ms updated CPU within keyDown for the first insertion plus
three individual keys. No fresh whole-document Export.init frame was sampled in
the updated typing capture. Separate first-opening captures observed 407 versus
408 ms main-thread sampled CPU (load: 207 versus 216 ms). Each is one 25-second
observation; inclusive weights overlap and these are not input-to-display latency
or broad responsiveness acceptance. Automation performs AX work, so whole typing
capture totals are not used as pure typing cost.

The complete saved note matched expected bytes, Redo reproduced it, and Undo
restored all 1003 original fixture note hashes. Rich opening and normal Quit
passed. The focused repeated-edit owner covers exact output, mixed gaps, Unicode,
formatting, storage changes, reload and separator controls. Original-source
controls pass; the unguarded initial map fails the new separator controls, and
the guarded map passes. The frozen final-source 275 non-AI/non-OCR checks pass
in four fresh processes with exact identifier coverage.

The existing full path's added quote separator remains after native text Undo;
that baseline-verified source-normalization detail remains a broader fidelity
follow-up. At that checkpoint, first edits in list/contextual content and early compact or
tabbed render paths still required full export; canonical root heads are extended
in performance376. Six OCR checks, broader
performance/parity, migration fidelity and final packaging remain open. No AI,
iOS, version or DMG change. Evidence: artifacts/native-macos/performance375/.

## performance373 — viewport-driven inspector sections

The inspector now uses root lazy sections, so a long expanded outline does not
lay out every heading eagerly. The heading model, identifiers and reveal actions
are unchanged. A nested-lazy outline prototype was rejected because Section 599
was absent; the final root-section layout shows all 601 heading entries and
navigates to the last heading and back to the root.

Matched optimized-app recordings use the same owned 1003-note vault, loaded
600-section note, end/root-heading preparation and viewport. One 25-second
Time Profiler observation per layout measured 918 ms original versus 497 ms
candidate main-thread sampled CPU, with inclusive NSView layout samples of
379 versus 36 ms. Inclusive weights overlap. These are sampled CPU observations,
not event-to-display latency, statistical acceptance or an overall speed claim.
Neither capture performed AX traversal while recording.

The signed optimized candidate was restored with its exact executable hash.
A bounded long-note edit saved; Undo restored all 1003 original note hashes.
Control/LongMixed tab switching refreshed the outline, the folder sidebar hid
fully and restored, and normal Quit exited 0. A coordinate click on the Control
list row did not switch notes; tab switching worked. List pointer delivery is
therefore not established by this check. Debug build-for-testing passed; the
frozen 275-check non-AI/non-OCR gate passed across four fresh processes. Six OCR-dependent checks remain blocked
by the separately reproduced Vision failure. No tests or CI exclusions changed.

No new DMG, version increment, iOS change or AI work. Overall responsiveness,
remaining native parity, migration fidelity, Settings automation, blocked OCR
and final packaging remain open. Evidence: artifacts/native-macos/performance373/
REVIEW.md, analysis JSON, note-fidelity JSON and restored app receipt.

## rules372 — selected-divider Return and receiving format

Return on the selected attachment glyph now retains the horizontal rule. A flat
following text block reaches its end and the existing item Return creates the
next sibling. Following inner quote/heading paragraphs split within their item;
child lists/code cards remain on the right of the item split. A rule ending an
inner quote starts a new item outside that quote. Root paragraphs receive an
explicit empty paragraph before the following body. Receiving root bold/code
traits continue, while a following link boundary stays intact. Private item
preparation and completed root edits both commit once, so Undo restores the
original selected glyph. Ordinary range replacement, typing, deletion and
composition retain their existing owners.

A mounted WKWebView reference captures 14 selected/entered/typed model and DOM
workflows with the pinned registry, committed NodeSelection and handled DOM
beforeinput. All inputs are byte-identical through current canonical preparation.
Earlier selected source cases are retained in rules371/web-return-dom.json.
These are synthetic command probes, not trusted React pointer/keyboard proof.
Compact input displacement and root-EOF empty-anchor differences remain explicit
reference limitations, rather than being counted as identical behavior.

The existing divider editor owner adds 62 selected workflows with handwritten
source, independent parsed owners, LF/CRLF where present, Undo/Redo and caret
restoration. An intermediate root formatting defect is reproduced by 20 failing
assertions before the font/trait repair. The final original-production baseline
fails 238 assertions with zero unexpected failures; the final candidate passes.
The frozen 275 non-AI/non-OCR checks pass in four fresh processes. Six existing
Vision-dependent gates remain unverified. No test seam or new test method.

The optimized signed internal app verifies keyboard selection and Return for
flat and inner-quoted list rules, plus root selected-rule Return into bold text.
Exact BOM/CRLF saves match the expected sibling, explicit paragraph and bold
NewTail sources. Separate word/Return Undo restores all four original owned
notes byte-for-byte. A fresh explicit-vault launch opens the restored root rule
and bold Tail in Rich text; both normal Quits exit 0. One erroneous text-match
request makes no change and is recovered through fresh AX state. App/CLI/updater
signatures verify; version stays 0.3.85/build125. No new DMG, iOS or AI change.
Evidence: artifacts/native-macos/rules372/verification.json and REQUIREMENTS.md.

Inner-quote caret Return, compact/quote-role transitions, root-EOF anchor
comparison, full ordinal/display reconciliation, general performance and wider
installed/migration/release acceptance remain open. This is a bounded selected
input repair, not full rule or desktop parity acceptance.

## rules371 — ordinary-item Return beside a divider

A mounted contenteditable WKWebView probe records 21 before/after/node-selection
workflows using the pinned registry, actual empty-paragraph plugin and Lexical
handlers. On WebKit, Enter defers to handled DOM beforeinput insertParagraph.
Committed selection and completed input updates are captured with DOM, Lexical
trees and Markdown. Current canonical Markdown preparation is byte-identical for
all inputs. This is DOM-backed synthetic command evidence, not trusted keyboard
or React decorator-click acceptance. The earlier direct headless command alone
misses this browser event lifecycle.

For a nonempty flat item, native caret Return before the divider now creates a
sibling owning the divider and remaining body. Return after it starts a sibling
at the following body. Nested items and outer quotes retain their parents. The
coordinator prepares the receiving paragraph privately, then reuses normal item
Return, marker-width changes and owner transfer in one commit. It avoids an
extra generated blank row when the following paragraph becomes the new head.
Imported preceding separators, rule spelling and source ordinals retain native
fidelity; wholesale web export normalization is not claimed as byte parity.

The existing divider editor owner adds 24 handwritten LF/CRLF, before/after,
ordinary/numbered/nested and outer-quote workflows, independent parsed owners,
follow-up typing and Undo/Redo/caret checks. The frozen original production fails
72 assertions with no unexpected failures; the final candidate passes. The
matching broad gate passes 275 non-AI/non-OCR checks across four fresh processes.
Six existing Vision-dependent gates remain unverified. No test seam or new test
method is introduced, and ordinary character typing gains no new work.

The optimized signed internal app verifies Return before a nested divider and
after an outer-quoted divider, exact saved BOM/CRLF bytes, separate word/Return
Undo and fresh-launch Rich text reopening. All three original owned notes remain
byte-identical after QA. Both normal Quits exit 0. Version stays 0.3.85/build125;
no iOS change, AI work or new DMG. Evidence: rules371/verification.json,
web-return-dom.json, native-before.md and native-after.md under
artifacts/native-macos/.

At the rules371 checkpoint, selected-divider, inner-quote and compact Return
were incomplete. Rules372 now extends selected input; the broader lifecycle is
still unfinished. The web
compact cases displace New outside the list; this is not copied silently as a
native requirement. Ordinal/display reconciliation and general performance and
installed migration acceptance also remain open. See rules371/REQUIREMENTS.md.

## rules370 — list-owned horizontal rules and checked edits

Mapped list-owned horizontal rules now remain rich, including compact rule heads,
inner/outer quotes and mixed code/table/rule bodies. A shared parser-owned card
inventory supplies render, placement and admission; the rule's one physical line
is kept separate from following paragraph gaps. Marker-width changes preserve
owned rule and paragraph indentation. Atomic replacement, selected composition,
Cut and boundary deletion use checked item roles. Partial rule-edge selections
are projected into owned paragraphs before the existing selection planner checks
them. This repairs an actual hosted-editor case where visible replacement text
was previously omitted from saved Markdown.

Four existing editor/clipboard owners are extended, with handwritten source
expectations and independent parsed parents, block kinds and quote depths. The
frozen final tests fail against original production with 262 assertions and no
unexpected failures, then pass on the candidate. The matching-source broad gate
passes 275 non-AI/non-OCR checks in four fresh processes. Six existing Vision OCR
checks remain unverified; this is not complete non-AI coverage. No test seam or
new test method is added. The optimized internal app is rebuilt and its app,
nested CLI and updater signatures are verified; 0.3.85/build125 is unchanged.

Installed Computer Use in a three-note owned BOM/CRLF vault verifies nested and
compact rules in Rich text, exact Tail edits, numbered-marker reindentation,
Portuguese acute-key composition beside a nested quoted rule, and Backspace
removal at the following paragraph boundary. Native Undo restores original bytes;
all three original files match their initial hashes after QA. Normal Quit exits
0. Reopening was not tested in this pass. Stale AX and inactive-binding errors
were recovered with fresh accessibility state.

Exact web Return-key parity remains open. Native Return retains its existing
continuation-after-atomic-block policy. Actual pinned headless web Range and Node
selection probes yield different item splits; compact quoted cases also show
input displacement. These probes establish a discrepancy, not a live DOM input
contract or acceptance of a permanent native variation. Do not count the full
rule lifecycle as parity-complete until the Return behavior is reconciled.
No new DMG, version change, iOS change, AI work or general latency claim.
Evidence: artifacts/native-macos/rules370/verification.json and web-return.json.

## parity369 — executable editor admission audit

Current actual native APIs and the pinned web plugin registry are exercised on
six representative Markdown shapes. Both native Source admission and the tested
web registry fall back for reference-style link/image definitions. The web throws
definition/imageReference import errors; EditorRecoveryBoundary provides its
Note Markdown recovery textarea. No reference-rich feature is added as parity
work based on that shared limitation.

The audit confirms a distinct native gap: ordinary and outer-quoted list items
containing a horizontal rule open in Source, while the web registry imports and
exports a thematicBreak between the item's Parent and Tail paragraphs. Root-quote
rules and item-owned headings are supported controls on both sides. The probe
uses current native requiresSource/render/export APIs and the actual transpiled
prepareMarkdownForMdxEditor plus the app's preserve-empty-paragraphs plugin and
relevant pinned MDXEditor plugins. It is headless package evidence, not a live
web DOM or installed native editor claim. Guarded-core exact round-trips do not
prove editable rule ownership or justify removing the admission guard.

Tracing finds that list-card discovery models code/tables only, horizontal-rule
metadata retains quotes only, and typing/deletion around rules currently builds
quote-only roles. Implementing list-owned rules therefore requires representation,
source placement and command/clipboard lifecycle changes before rich admission.
The required ownership, compact/quoted, mixed-card, line-ending, structural edit,
Undo/Redo and installed checks are recorded in
artifacts/native-macos/parity369/REQUIREMENTS.md. The representation gap is implemented in rules370; exact Return parity remains incomplete.
No product/test source, build, version, app or DMG changes were made in discovery.
Evidence: artifacts/native-macos/parity369/verification.json.

## board368 — selected-card review, Cancel and durable Undo/Redo

The unchanged signed excerpts367 internal app opens a new three-note owned Work
board with a canonical single-choice Status list schema. Native Select mode
selects exactly First card and Second card in Draft. Drag alone leaves the board
unchanged; a follow-up click on the empty Done target completes delivery, matching
the separately controlled drag330 input-completion pattern. This is not drag-only
or physical pointer acceptance. The review names exactly Work/Card0.md and
Work/Card1.md. All five original files remain byte-exact before Apply; Cancel
retains both Draft cards and selection without writing any original file.

Repeating the selected-card drop and applying the review changes only both Status
fields to quoted Done. BOM, CRLF, bodies, foreign metadata, the peer Review card,
schema and view configuration are preserved. Organization history records one
Update properties receipt. Reviewed Undo names both cards and restores exact
expected quoted Draft values; it does not restore their original unquoted YAML
spelling, consistent with the existing typed-property receipt contract. Reviewed
Redo reproduces the first applied bytes exactly. A normal Quit and explicit
owned-root relaunch restore the Work board with Done2, Draft0 and the unchanged
Review peer; selection mode is cleared. The second Quit also exits zero.

No source, project test, app binary, version, iOS or AI change, build or DMG is
made. Frozen source and installed executable hashes still match excerpts367.
The prior 275 non-AI/non-OCR checks remain that build's evidence, not a new test
run here; six OCR-dependent gates remain open. Prior drag330 column evidence is
unchanged, not repeated in this batch. Broader card types/scopes, keyboard and
accessibility, drag-only delivery, responsiveness and full parity remain open.
Evidence: artifacts/native-macos/board368/verification.json.

## excerpts367 — avoid repeated scans of unchanged excerpt snapshots

The earlier installed performance354 navigation trace includes work in
MacCollectionExcerpt.Request equality. SwiftUI request comparisons scanned every
UTF-8 byte even when both immutable String values shared the same storage. The
comparison now checks workspace/path first, then accepts simultaneously borrowed
UTF-8 buffers with equal counts and base addresses. Different or unavailable
buffers still use the original exact-byte comparison. This preserves differences
between canonically equivalent Unicode spellings; no hash, persistent cache,
loader, cancellation or excerpt-parsing behavior changes.

An optimized standalone paired workload exercises shared-value note snapshots;
275 equality controls include small/large strings, independent equal buffers,
changed lengths, composed/decomposed accents, emoji, CRLF and Foundation-backed
strings. These are comparison diagnostics, not installed input-to-present timing.
No behavior test or production testing seam is added for this pure equivalence.
The existing rendered excerpt owner remains among the six OCR-dependent gates
blocked by the independent Vision/E5 fixture. The other 275 declared non-AI
identifiers pass across fresh processes, with exact coverage, no skips within
that subset and frozen compiled/source/test inputs. This is not complete non-AI
coverage. Debug/optimized builds and nested app/CLI signature checks pass.

The signed internal app displays a Gallery excerpt whose reference-link label is
defined after 2,000 later paragraphs. An outside edit changes Visible to Updated
without changing byte count; after the filesystem refresh, the Gallery shows the
new label. The immediate observation still shows old text, so no instantaneous
refresh or refresh-latency claim is made. A File menu inspection does not invoke
any refresh command. Its exposed Cancel action dismisses the menu after Escape
does not; screenshot capture is unavailable while that menu is the observed target.

Hiding/restoring folders retains query and updated excerpt. Native Open Vault
switches to a second owned vault with the same Work/Excerpt.md path and note ID;
List and Gallery display only Other vault excerpt. Restoring the first note's
bytes and modification time, returning to that vault and opening its saved
Gallery/query displays Visible again. The special view stays collection-only;
returning to the selected note displays the editor alone. All 104 original files
across the two fixtures remain byte-exact, and normal Quit exits zero. No real
vault, iOS or AI source changes, version advance, commit or DMG is made. The app
remains 0.3.85/build125. Evidence: artifacts/native-macos/excerpts367/verification.json.
General responsiveness, six OCR gates and broader non-AI parity remain open.

## ime366 — Portuguese dead keys across list selections

The signed compact364 internal app was launched explicitly with a new two-note
synthetic vault. The selected system layout is Portuguese. A read-only public
Carbon layout query identifies virtual key 30 as acute and key 39 as tilde; native
Computer Use sends those keys, followed by e or a. Option-E instead produces æ on
this layout; that initial control was undone and is not treated as composition.

A plain-prose control composes one é. Selecting `first` through `Beta` across the
two bullet rows then composes one é, saving exactly `- Alpha é second`. The same
selection composes one ã, saving exactly `- Alpha ã second`. Native Undo restores
the original rows and selected span; Redo restores the tilde result. Closing and
reopening Input displays that saved result as one bullet, without an extra accent
or lost text. Undo after explicitly closing the tab does not change text; this
check does not claim closed-tab Undo retention. Source-mode native paste restores
the original fixture, and both note files match their initial bytes. Cmd-Q exits
zero. One stale element error after Undo was resolved by refreshing AX before the
next input; no input after that failed selection was assumed to have run.

This is real AppKit input through Computer Use on the installed optimized app,
not physical hardware input or general IME/dictation/candidate-window acceptance.
No production code, project tests, app versions, build or DMG changed. The prior
275-check result remains evidence for compact364, not a new suite run in this
batch. Evidence: artifacts/native-macos/ime366/verification.json. Settings AX,
other input workflows, responsiveness and broader parity remain open.

## settings365 — native automation diagnostic, no product change

The two latest SkyComputerUseService reports both show EXC_BREAKPOINT/SIGTRAP
at Swift Array.remove(at:), followed by unsymbolicated service frames during
compactMap traversal. This identifies the crashing process and operation; it
does not establish which application accessibility node triggers it or rule out
an application-side accessibility issue. Zerus itself remained running in the
prior installed attempts. No tool internals, OS settings or production view were
changed. A scratch hosted Settings probe produced a black cache-display bitmap
and incomplete traversal, so it is explicitly inconclusive and excluded from
acceptance. Settings UI, zoom selection through Settings and external AX access
remain pending. Evidence: artifacts/native-macos/settings365/verification.json.

## compact364 — dismiss Library when the wide layout becomes available

Installed QA reproduces a temporary Library drawer staying modal after a Tasks
window expands from standard half-screen to Fill at 150% interface zoom. The wide
workspace remains dimmed and absent from accessibility until Done is clicked.
MacWorkspaceView now clears only compactLibrary when canInlineSidebar changes to
true, matching the existing Inspector transition. It does not change the window's
sidebar state or the inspector choice. Sidebar is window-local @State, not a saved
AppStorage preference.

The signed candidate repeats the same transition and automatically dismisses
Library. Tasks search is exposed and accepts a native q key afterward. A separate
control hides the entire sidebar before contraction; opening a temporary Library
and expanding closes the drawer while keeping folders hidden. The toolbar remains
available to restore them. In the narrow Alpha editor, Command-Option-I opens
Inspector; the background editor is absent from AX, and a native v key changes
neither note. Escape closes Inspector and restores the original editor caret.
The next v saves exactly at that caret; native Undo and Save restore both original
note files byte-for-byte. Fill restores the wide panes, and normal Quit exits zero.

All 275 declared non-OCR non-AI identifiers pass with exact coverage and frozen
source/test inputs. Six Vision/E5-dependent gates remain unverified; project CI
exclusions are unchanged. This one-line UI-state repair adds no test method,
private-state introspection or production testing seam. Its regression oracle is
the real installed before/after window transition; existing layout/editor owners
protect the surrounding contracts. Debug/optimized builds and signing verify.

Settings interaction remains blocked: opening Settings returns "Sky Computer Use
native pipe closed before response". The advised state refresh repeats that error.
The app process remains alive; no cause or product repair is inferred. Only the
owned diagnostic QA process is terminated (SIGTERM), with its original notes
unchanged; this is not a normal-Quit or Settings acceptance result. Subsequent
layout sessions use 150% as a saved fixture input seeded while the QA app is closed.
They do not prove changing zoom through Settings. The original 100% value is
restored after all sessions, and only an empty owned private task-draft folder is
cleaned up.

The half-screen/150% case exercises approximately 640 logical points, not the
physical 600-point minimum. Settings, direct edge resizing, broader compact flows,
VoiceOver/input and general performance acceptance remain open. The app stays
0.3.85/build125; no DMG, AI/iOS change, commit or publication is made. Evidence:
`artifacts/native-macos/compact364/verification.json`, `native-acceptance.json` and
`settings-transport-blocker.json`.

## tasks363 — private task drafts follow a renamed vault directory

The Mac workspace previously passed no saved identity to the shared task-draft
store. The final real-workspace owner reproduces two failures: renaming the vault
loses its draft lookup, while a separate copy at the old path sees that private
draft. The same owner also checks compatibility with the older path-only format;
it fails five intended assertions on the original implementation.

MacStartupIdentity now derives an opaque, versioned private UUID from its existing
volume UUID (device fallback), inode and creation time. Path and modification time
are excluded. MacWorkspace passes that UUID to the existing task-draft store,
without another filesystem read or scan. The existing store adopts a path-only
folder when the original directory is opened, follows a bound identity through
new root aliases and keeps another identity at a previous path separate. The
startup cache schema, shared task-draft engine, vault/task metadata format and
iOS implementation stay unchanged.

The extended owner passes adoption, actual same-volume directory rename,
replacement-copy isolation, recovered values and unchanged vault tasks before
commit, plus its original conflict/copy/delete/save controls. All 275 declared
non-OCR non-AI identifiers pass with exact coverage and frozen source/test inputs.
Six Vision/E5-dependent gates remain unverified; project CI exclusions are
unchanged. No new test method or production testing seam is introduced.

In three signed optimized native sessions, editing and closing Original task
keeps one private draft without changing any vault file. After normal Quit, the
owned vault directory is renamed and an exact copy placed at its old path. That
copy shows Drafts (0) and No task drafts, while the original private record stays
intact. The renamed directory shows Drafts (1) and recovers the same record and
values in its original private folder. Opening recovery updates private timestamp
bookkeeping; it does not change the vault before Save.

Native Save commits the recovered title to the same task ID in the moved vault,
changing only title/update timestamp and retaining other/foreign fields. The
replacement copy remains byte-identical; the moved note and manifest remain
exact; the draft clears. All sessions quit normally with exit zero. Only the two
empty private QA owner folders are removed after completion. An initial recorder
filter missed Foundation's /var alias versus Python's /private/var spelling; the
corrected capture and excluded diagnostic are retained, with no product/data
mutation caused by the recorder.

This verifies ordinary same-volume directory moves after identity binding. When
directory identity is unavailable, the prior path-only behavior remains. There is
no historical identity to associate an already-moved legacy path-only folder
automatically; cross-volume copies, restored directories, provider/remount and
older-binary behavior require separate recovery work. Those gates stay open.
The app remains 0.3.85/build125; no DMG, AI/iOS change, commit or publication.
Evidence: `artifacts/native-macos/tasks363/verification.json` and
`native-acceptance.json`.

## pdf362 — normalized PDF search with original-text highlights

The existing desktop PDF search normalizes NFKD compatibility characters and
whitespace. A real PDFKit baseline confirms that the native reader misses plain
ABC against full-width letters, repeated/tabbed query whitespace and phrases
across source line breaks. The existing PDF reader owner now includes these
contracts, composed/decomposed accents, ligatures, supplementary emoji and the
native Match case option. Its final version fails on the original reader for
nine intended search/navigation assertions.

The native reader now extracts each page on the main actor, normalizes and
matches its value text in a cancellable detached task, then creates PDFKit
selections on the main actor. Each normalized UTF-16 unit maps to its original
Unicode scalar range, preserving source characters and line breaks in highlights.
Matches stay ordered within each page and through the document. New queries and
closing invalidate the search generation and cancel both parent and worker work;
old results cannot publish into the replacement search. No all-document normalized
cache is retained. Complex PDFKit page-text extraction remains main-thread work
and large/complex PDF search performance still requires acceptance.

All 16 query selections from the real-PDF probe match the current desktop helper
on identical extracted text. The final 275 declared non-OCR non-AI identifiers
pass with frozen sources/tests and exact coverage. Six existing Vision/E5-dependent
gates remain unverified, and project CI exclusions are unchanged. The two existing
PDF owners retain cancellation/navigation and encrypted-original controls; no
new test method or production testing seam is added.

In the signed optimized app, ABC highlights the original full-width letters after
an emoji, and Next reaches page two. Repeated-space and line-break phrases work;
Match case rejects lowercase against uppercase full-width source while uppercase
still matches. Expanding and showing notes preserves the active query, match and
page. A wrong PDF password shows retry feedback; the disposable correct password
unlocks normalized search and page navigation. Closing and reopening that preview
returns the password prompt. Normal Quit exits zero, and both original PDFs plus
all three original notes remain byte-identical.

The app stays 0.3.85/build125. No DMG, AI/iOS change, commit or publication is made.
This closes the tested normalization/highlight/navigation gap, not full PDF,
provider, keyboard/VoiceOver, performance or migration acceptance. Evidence:
`artifacts/native-macos/pdf362/verification.json` and `native-acceptance.json`.

## code361 — avoid bridged per-character source-row indexing

A first opening of an owned 3,000-line Unicode code note in the signed optimized
app identifies repeated source-row indexing under code/card discovery. The
source-row initializer now scans a temporary contiguous UTF-16 buffer and decodes
complete line slices. It retains the original NSString for fragment reads.
CR/LF/CRLF handling, final empty rows, source text, UTF-16 offsets and ending
fallbacks remain unchanged. A delimiter cannot split a surrogate pair. There is
no retained cache or new editor/source fallback policy.

Seven explicit baseline/candidate controls match exact row contents, endings,
offsets, ranges and fragment results, including supplementary Unicode, combining
marks, BOM, NUL and mixed line endings. Isolated optimized helper measurements
cover both ASCII and non-ASCII sources. Unicode scanning avoids the bridged-index
work; some ASCII cases have a small additional cost. The temporary buffer uses
two bytes per UTF-16 unit while initialization runs. These are explicit trade-offs,
not a claim that every input is faster or that total interface latency is solved.

The existing 275 declared non-OCR non-AI checks all pass with exact identifiers
and frozen source/test inputs. No new timing test, test-only production seam or
test source change is introduced for this behavior-preserving repair. Six
Vision/E5-dependent gates remain unverified; project CI exclusions are unchanged.
Debug build-for-testing, optimized Release build and installed signature checks
pass. The internal app stays 0.3.85/build125; no DMG, AI/iOS change or publication.

In the installed app, Find in Note reaches the final code line. A native keypress
saves exactly one inserted byte and leaves the other note exact. Native Undo and
Save restore both original note files byte-for-byte. Finding the first line again
repaints the code header, border and body correctly. Normal Quit exits zero.
The large body exceeds the existing syntax-highlight cap, so this fixture does
not verify colour highlighting above that cap.

The installed load trace is consistent with the scoped avoided source-row work.
Both captures use exact same note contents and logical pane widths, first opening
from Control in separate owned roots/app sessions, with no AX observations during
recording. Sampled inclusive CPU is not controlled input-to-present latency and
must not be added across frames. Cold/complex rendering, general responsiveness,
broader non-AI parity and final delivery remain open. Evidence:
`artifacts/native-macos/code361/verification.json` and `installed-profile.json`.

## migration360 — reviewed companion metadata and native readback

An isolated optimized React/Tauri companion app uses a unique compiled identity,
synthetic localStorage pin/archive inputs and an owned three-note vault. The
existing Settings → CLI → Review note metadata flow calls the real Rust IPC;
no migration result or transport is mocked. A restrictive runtime sandbox denies
writes except owned fixture and unique-app locations, denies installed CLI/private
skill paths, and denies outbound network. It passes an owned allowed/denied-write
preflight. No CLI installation, registry update, private browser import or DMG is
performed. Both companion and native apps quit normally with exit zero.

The review lists exactly two notes, one pin and one archive flag. Cancel leaves
all fixture files exact. A controlled outside edit after review produces the
specific stale-review refusal and leaves notes, manifest and existing files exact;
the independent watcher records that outside edit in its own history. A fresh
approval changes only the two reviewed notes and adds their two migration history
receipts. Existing shared false values win over private flags, archived wins over
private pin, bodies remain exact relative to startup, and vault manifest bytes
stay exact. A second review reports no changes and disables Prepare notes.

The signed cards359 native app opens this same vault. Pinned contains only the
pinned note; Archive contains only the archived note; the explicit-false control
remains in All Notes, with Pin and Archive actions. The archived note offers
Unarchive. Foreign metadata is visible correctly. All vault files remain exact
through the native readback and Quit.

This closes the bounded reviewed pin/archive GUI/IPC and native readback gap,
not full legacy byte fidelity. Before the review, the existing companion startup
assigned missing IDs, renamed two notes to title-derived filenames and normalized
the BOM/CRLF frontmatter note. Thus this run does not prove missing-ID insertion
through the reviewed command, nor exact preservation from initial legacy bytes.
That startup behavior is traced to stabilizeVaultLinks/persistNote and recorded
in startup-limit.json; it is not a native change or a new defect introduced here.
The unique QA profile and denied WebKit media/debug temp writes also differ from
a normal companion profile. No product or test source changes are made.
Evidence: `artifacts/native-macos/migration360/verification.json`.

## cards359, layout358 and performance357 — bounded editor work

The internal signed app now limits code-card painting to the requested viewport
while retaining complete bounds for intersecting cards. Five real AppKit bitmap
controls match the original implementation exactly, including header-only and
bottom-border edges. Installed 100-card navigation, repaint, body save and Undo
restore the original three note files. A visible enormous card still needs its
complete geometry; this is not card virtualization.

AppKit noncontiguous layout is enabled and eager background layout disabled.
The long-note native session verifies top/end Find, caret navigation, editing,
sidebar hide/restore and outline jumps; original note bytes are restored by Undo.
A mouse-hit owner now scrolls its target into view and supplies the matching
mouse-up, retaining all original checks. Eligible single-line root prose also
reuses its already parsed Paragraph when raw and normalized bytes are identical;
reference-sensitive, wrapped and structural paths keep their previous behavior.

All 275 declared non-OCR non-AI identifiers pass on the final cards359 inputs.
Six existing Vision/E5-dependent checks remain unverified because an independent
plain-image accurate OCR control fails; they are explicitly excluded only in the
artifact runner, not project CI. No complete 281-test pass is claimed. Installed
profiles establish avoided work in these specific paths, not overall latency;
pane widths differed between code-card captures. Overall responsiveness, cold
and complex rendering, and final delivery acceptance stay open. The app remains
0.3.85/build125; no DMG, AI/iOS change or publication is made. Evidence:
`artifacts/native-macos/cards359/verification.json`,
`artifacts/native-macos/layout358/verification.json` and
`artifacts/native-macos/performance357/verification.json`.

## render355 — share source parsing and skip impossible card discovery

A native closed-tab opening of the owned 4,000-paragraph note identifies code,
table and container-card discovery inside rendering. Rendering now parses raw
source once and shares that tree with discovery. Reference-normalized rendering
uses the same tree only when its UTF-8 bytes are identical; otherwise it retains
its separate tree so physical card ranges remain tied to raw source.

When the raw tree contains only root paragraphs/headings, code and owned/quoted
cards are impossible under the existing helpers’ traversal rules. Those scans
are skipped. The independent raw root-table scanner remains, including its
accepted pipe syntax. Other documents retain the existing discovery helpers and
models. The initial export mapping from performance354 remains intact.

Two note-link/Unicode-parent cases extend the existing code/table sheet owner;
a literal-pipe control extends exact unedited round-trip coverage. Both owners
pass on the original implementation. The final 280 configured non-AI identifiers
all pass across four fresh processes, with no skips or duplicates. Build-for-
testing and optimized Release build/signature verification pass. No timing
assertion, new test method or production testing seam is added.

The signed internal app repeats Control → close long-note tab → reopen, creating
a fresh editor with warm process/file caches. The capture shows no code/list/quote
card-discovery frames under rendering in this prose fixture. Render CPU is
recorded separately from overall main-thread work; these are scoped inclusive
samples, not click-to-present measurements, cold app startup or a general speedup
claim. Both captures retain disk headroom. The note opens with 68,003 words and
editor focus; a native body edit saves, Undo restores both original note files
exactly, and normal Quit exits zero.

The app stays 0.3.85/build125. No DMG, AI/iOS change, commit or publication is made.
Main-thread rendering/theme/layout, startup, complex loads and broader acceptance
remain open. Manual review and diff checks pass; unavailable autoreview and
check-changed tooling are recorded without claiming independent review. This batch
also corrects performance354’s derived keypress field to read all sampled frames
instead of a truncated ranking; its raw trace and avoided-export finding are
unchanged. Evidence: `artifacts/native-macos/render355/verification.json`.

## performance354 — reuse fresh render mappings on the first body edit

A current optimized-app capture confirms that the first body keypress on the
owned 4,000-paragraph note still performs a complete export-cache initialization.
The renderer now records source/native offsets while it constructs fresh root
prose and headings. It publishes that mapping only after the complete source and
native ranges are covered. The coordinator installs it after loading and theme
notifications finish. Subsequent storage mutations use the existing checked row
replacement; formatting, structural changes and ineligible rows still fall back
to the full serializer. No source-wide cache is placed in attributed text or
clipboard fragments. Attachments, generated line-token breaks and structural
documents do not receive this mapping.

The first prototype added too much render work. The final mapper uses the
renderer’s existing physical row boundaries and NSString break checks instead
of repeating grapheme scans. A paired warm Debug API control confirms exact saved
source with both paths and records render/first-export CPU separately. It is not
installed latency. The expanded repeated-edit owner adds setext, whitespace-gap
and wrapped-source controls across LF/CRLF/CR. They pass on the original source
and the final implementation, preserving behavior without timing assertions or
new test methods. The final unchanged 280 configured non-AI identifiers all pass
across four fresh processes; the monolithic Vision/E5 limitation remains separate.

The optimized Release build and signed installed executable verify. A native
capture on the same note/caret saves the expected first body character with no
AX observation during the recording. Full cache initialization is absent from
those sampled keypress stacks; local publishing remains. These are scoped
inclusive CPU samples, not input-to-display latency or a general speedup claim.
Both captures retain disk headroom. Native Undo/Redo/Undo saves the expected values
and restores both original note files exactly; normal Quit exits zero.

Fresh mapping has some render-time cost. Cold rendering, complex/wrapped first
edits, save-time resource parsing and broader displayed responsiveness remain
open. The version stays 0.3.85/build125; no DMG, AI/iOS change, commit or publication
is made. Manual source review and diff checks pass; the unavailable autoreview
skill/check-changed script are recorded without claiming an independent review.
Evidence: `artifacts/native-macos/performance354/verification.json` and `final/`.

## navigation353 — avoid repeated folder schema decoding

Collection field discovery now resolves effective schema definitions once per
containing folder within one inventory calculation. It keeps the original note
iteration, inferred-property policy, hidden/unsupported filtering and inheritance
semantics. There is no retained schema cache: a later calculation reads its current
snapshot. Absent schemas take the direct empty-definition path without building
folder lookup keys.

The warm Debug API control checks the actual field-discovery function on 500
notes across two directories. Original and candidate field results match, and
separate controls match the previous algorithm for root/nested/Trash/sibling
paths, reversed order and absent/invalid schemas. These controls identify avoided
work; they do not measure installed input-to-frame latency or establish general
responsiveness. An intermediate no-schema bookkeeping cost was found and removed
before the final build; its evidence is retained separately.

The final build-for-testing and optimized Release build pass. All 280 unchanged
configured non-AI tests pass across four fresh processes, with exact original
identifiers and no skips, duplicates or omissions. The earlier monolithic
Vision/E5 runtime limitation remains; no OS-model repair is claimed. No test source
or assertion changes are made.

The signed internal app restores the 500-note Research Gallery. Its Properties
menu gains QA Refresh after an outside edit to the owned fixture schema, then
returns to Foreign/Status after exact original bytes and timestamps are restored.
Planning/List and Research/Gallery each retain their 500 notes. Normal Quit exits
zero, and all 1,022 files present at this batch's fixture baseline remain exact.
The installed executable matches its signed receipt at 0.3.85/build125. No DMG,
version bump, AI/iOS change, commit or publication is made. Broader performance,
parity, provider and final delivery acceptance remain open. Evidence:
`artifacts/native-macos/navigation353/verification.json` and its `final/` test gate.

## export352 — native PDF, Word and HTML save acceptance

The signed navigation350 internal Release app exports one owned BOM/CRLF note
through the actual macOS save panel in all three formats. Default filenames and
the owned output directory are correct. Cancelling Word export creates no file;
format/property choices survive cancellation. PDF includes visible properties,
Word excludes them, and HTML includes them; Zerus identity metadata stays hidden.
Closing the sheet returns focus to the saved rich editor. Normal Quit exits zero,
and both original note/image hashes remain exact.

PDF text and its rendered A4 page are checked visually for readable layout,
Portuguese accents, currency, formatting, lists, quote, table, code and image.
Word's ZIP/XML and native textutil import preserve the expected content; its
re-encoded PNG has identical dimensions and decoded pixels. HTML semantic/text
checks pass and its embedded PNG also has identical decoded pixels. Word layout
in Microsoft Word and HTML browser layout are not inspected. This is bounded
export acceptance, not full parity, installed IME or overall performance sign-off.
No product/test change, build, version increment or DMG is made. Evidence:
`artifacts/native-macos/export352/verification.json`.

## verification351 — complete non-AI coverage in fresh processes

All 280 configured non-AI tests pass across four fresh processes on the unchanged
navigation350 build: appearance (2), collection (7), workspace (54), and all other
non-AI checks (217). Executed test identifiers are extracted from each result
bundle and compared with the original complete 280-test run. The sets match
exactly, every test passes, and none is skipped, duplicated or omitted. Built
inputs and recorded source/test files remain unchanged. No assertion, test source
or configured AI deferral is altered.

This is complete coverage through process isolation, not a repair of the prior
monolithic Vision/E5 failure. That long-lived test-host issue remains documented;
no OS cache/model mutation or production change is made. The four-process evidence
qualifies the current source's non-AI checks without relabeling the failed
monolithic attempts. No app build, version change, DMG, iOS/AI work, commit or
publication is made. Evidence:
`artifacts/native-macos/verification351/verification.json`.

## navigation350 — reuse already parsed collection metadata

A lightweight Time Profiler recording of ordinary 500-note folder navigation
identifies repeated NativeFrontmatter construction in collection field discovery
and card property lookup. Those two reads now use the existing MacNoteFrontmatter
cache. It compares exact UTF-8 bytes, retains the original parser result and keeps
its existing entry/byte limits and large-note fallback. Schema interpretation,
property types, group ordering, saved data and pane lifecycles are unchanged.
A warm Debug API control supports avoiding repeated parsing; it is not installed
input latency. Before/after optimized-app CPU recordings finish with headroom
intact. Cache/tab warmth and key timing differ, so no overall speedup is claimed.

Build-for-testing and optimized Release build/signature verification pass. The
first combined non-AI run reports 277 passes and three unexpected rendered-UI
errors; the unchanged retry reports 275 passes and five such errors. Vision/E5
missing-model-resource diagnostics precede the failures. A fresh process passes
all five affected original owners with their assertions unchanged. No test source,
assertion or exclusion is changed, and no combined green result or OS-model repair
is claimed. The last passing combined gate remains navigation349's 280 checks.
The monolithic-process limitation remains; verification351 supplies
complete unchanged coverage across fresh processes.

The signed internal app verifies warmed metadata after an outside edit: Draft's
count decreases, and search shows the changed card in Ready with its new property.
Restoring the exact original note and modification time returns the searched card
to Draft; clearing search restores all 500 notes and the original group count.
The folders bar hides completely and restores, retaining search text and focus.
The special view remains collection-only. Normal Quit succeeds, and all 1,003
original fixture files remain byte-identical. The app remains 0.3.85/build125.

The storage audit preserves all original result bundles, app products, vaults,
release artifacts and OS model caches. A duplicate trial result archive saves
little space and is discarded; no result-bundle deletion campaign is performed.
The tracker also removes an obsolete claim that inactive external-move tabs are
still unfixed; current source, owner coverage and startup248 evidence already
prove that bounded repair. No AI/iOS change, version bump, DMG, commit or
publication is made. Evidence:
`artifacts/native-macos/navigation350/verification.json`.

## navigation349 — scope saved-version updates to the inspector

Asynchronous revision/history loading previously published its four fields on
the whole workspace. The recovery state now has its own observable owner, and
only the revisions section subscribes to it. Existing workspace recovery APIs,
selection/vault guards, storage and review behavior are retained. A real-file
API control creates a revision and reloads the inspector: both revisions arrive,
the inspector receives updates, the workspace receives no publication, and the
note bytes are unchanged. This proves avoided publication scope, not a general
navigation latency improvement.

The build and seven focused recovery/pointer/focus owners pass. The frozen final
source passes all 280 non-AI tests, zero failures, terminal exit 0; the 13 AI/chat
classes remain deferred. No test source or product testing seam is added. The
optimized internal app is built, signed and verified at 0.3.85/build125.
Installed native checks show both revisions and their current marker, open the
selected revision and automatic-history browser, retain editor focus, and save
an exact keyed edit. One Undo restores all original fixture bytes, including BOM,
CRLF and foreign metadata. An intentionally damaged owned revision index displays
the error; restoring it and returning to the note removes the error and restores
the buttons. All three original recovery-fixture files remain exact.

An ordinary 500-note Gallery opening reaches the correct rich note, focus and
Saved state; all 1,003 original large-fixture files remain exact. Its follow-up
Animation Hitches recording hits the disk guard during finalization, despite a
recorder exit of 0, so it is excluded and its owned raw/trace files are discarded.
No speedup is claimed from that recording. The valid preceding raw capture is
losslessly archived and verified before releasing its scratch space; the processed
trace and exports remain available. Further heavy Hitches captures need more
headroom. General displayed responsiveness and the remaining rendering work stay
open. No shared Instruments service or unrelated process is terminated.

The internal app quits normally. Both web reference routes return HTTP 200.
No AI/iOS change, version bump, DMG, commit or publication is made. Evidence:
`artifacts/native-macos/navigation349/verification.json`.

## navigation348 — ordinary navigation attribution, no product change

A fresh pointer opening from the 500-note Gallery reaches the correct ordinary
note, rich editor focus and Saved/428-word state on the signed optimized
acceptance347 app. A guarded 40-second Time Profiler capture finishes normally
with disk headroom intact. Its sampled application frames do not identify
Markdown parsing or initial note loading as a dominant cost; much of the sampled
main-thread work is SwiftUI/AppKit graph and transaction processing. This is CPU
attribution, not input-to-display latency, and is not a controlled before/after
comparison. No speculative product optimization is retained.

The preceding Animation Hitches recording exhausts disk during finalization,
despite its live headroom check. It is excluded from all timing conclusions. Its
owned failed trace and raw recording are discarded; no shared service or unrelated
process is terminated. The lighter CPU recording and analysis are retained.
A shorter 18-second Animation Hitches recording then completes normally with
headroom intact. It includes the pointer input and a quiet tail. Its one target
Potential Issue warning flags an expensive app update during Gallery-to-note
activation. The longest top-level app update is about 34 ms within that frame;
the 117 ms detector interval has a different scope, overlaps that update and must
not be added to it or presented as click-to-display latency. This confirms a
remaining rendering hitch, not its complete cause or an improvement over earlier
builds. Both valid captures are retained. All three ordinary notes open correctly.
Normal Quit completes, and all 1,002 pre-existing fixture files plus the added
saved-link fixture remain exact.
The acceptance347 source hashes still match. No app/test change, repeated build,
version bump, DMG, AI/iOS work, commit or publication is made. Ordinary displayed
responsiveness and broader non-AI acceptance remain open. Evidence:
`artifacts/native-macos/navigation348/verification.json`.

## acceptance347 — zoomed native split-pane input

Actual pointer clicks in collection search failed at 150% interface zoom. A hosted
native owner reproduces this with real window mouse/key events; its 100% controls
pass. The final original-source baseline fails at reduced/enlarged zoom in List
and Gallery and at 150% in Tasks and External Notes. No programmatic field focus
is supplied by that owner.

MacZoomSplitView keeps native H/V split boundaries at window scale and scales the
contents inside each existing pane graph. Non-AI split views use this wrapper;
AI views remain deferred. Native splitters and original SwiftUI state are retained.
The new pointer owner exercises all six offered zoom choices for List/Gallery and
normal/enlarged standalone search fields. Related owners retain editor selection,
Undo, checkbox input and search-to-note focus. The final non-AI gate passes 280
tests with zero failures and terminal exit 0.

The first full run hit an OCR-only footer assertion: the captured UI displays the
correct count, but Vision misses its small one-pixel caption. The footer owner now
renders the same logical bounds and clipping at two pixels per point, with all
expected visible text unchanged. Temporarily hiding the label produces five real
visibility failures. That negative-control change was restored byte-exact; no
production word-count implementation changed.

The signed optimized internal app verifies the previously failing 150% pointer
click, typed filtering, clearing, immediate Back-to-note typing and exact single
Undo. The exposed horizontal splitter control visibly resizes and restores its
pane. An additional owned saved-link fixture verifies a nested vertical split,
actual pointer typing/save, byte-exact Undo with BOM/CRLF, and vertical splitter
height changes/restoration. The page preview was switched off again, the original
note and full window restored, and the app quit normally. All 1,002 pre-existing
fixture files and the added saved-link fixture match their baselines. Saved zoom
remains 100%; 150% was a launch-only override.

Direct Computer Use dragging still produces no observed resize; its cause or
transport is unproven. Native exposed resizing controls work. The 960-point window
at 150% exercises about 640 logical points, not the physical 600-point minimum.
This is no general performance or complete compact/VoiceOver/provider acceptance
claim. Evidence: `artifacts/native-macos/acceptance347/verification.json`.

Version remains 0.3.85/build125. No AI/iOS change, version bump, DMG, commit or
publication. Broader responsiveness, workflow parity and final delivery remain open.

## acceptance346 — standard window resizing and retained editing

The standard macOS Window menu now provides installed resizing evidence where
direct edge dragging had produced no observed change. On the unchanged signed
accessibility345 app, half-screen Gallery reflows correctly. In List, the
half-screen window keeps the editor focused and automatically collapses the
inspector. Fill restores the inspector and editor focus. A bounded keyed edit
saves with all original note bytes as an unchanged prefix; the leading space is
escaped in Markdown. One Undo after expansion restores the original file exactly.
Redo restores the first saved bytes, and another single Undo after contraction
again restores the original. The window was returned to Fill and quit normally.
All 1,002 original fixture files remain byte-identical.

This covers the observed 960-point half-screen and full-width transitions, not
minimum-width compact drawers, all resize gestures, or input-to-frame latency.
Direct edge dragging still has no observed effect. Escape did not dismiss the
View menu in this session; its exposed Cancel action did. No cause or product
repair is inferred from either transport observation.

The current native reference-definition Source guard was also checked against
pinned desktop importer controls. Inline links import, while definition-first,
definition-last and shortcut-reference forms throw unsupported-construct errors.
This is headless importer evidence, not live browser acceptance; it does not
justify removing the native guard as a demonstrated parity fix.

No product/test source, app build, version, DMG, AI or iOS changes were made.
The source remains identical to accessibility345's passing 279-test non-AI gate;
that suite was not repeated. Evidence:
`artifacts/native-macos/acceptance346/verification.json`.

## accessibility345 — live navigation and selection semantics

Native accessibility snapshots showed Tasks selected while All Notes or a
Research note was active. The decorative checkmark symbol was contributing a
selected state independently of navigation. Sidebar icons are now hidden from
assistive technology, and each navigation/folder button reports selection from
the same destination condition used for its visible highlight.

The Select button had the same icon-derived state while bulk-selection mode was
off. Its selected trait now follows the actual selection mode. The button uses
the existing local collection-selection observer so its state updates live
without adding workspace-wide selection notifications.

The signed optimized internal app verifies All Notes, Tasks and Research state,
List and Gallery selection mode off/on/off, and complete sidebar hide/restore.
All 1,002 original fixture files remain byte-identical after normal Quit. The
matching-source non-AI suite passes 279 tests with zero failures and terminal
exit 0. An attempted in-process accessibility test was removed because its tree
omits SwiftUI semantic buttons; those unwrap failures are not regression proof.
Actual spoken VoiceOver output remains unverified. Evidence:
`artifacts/native-macos/accessibility345/verification.json`.

Internal version remains 0.3.85/build125. There is no performance improvement
claim, AI/iOS change, version bump, DMG, commit or publication. Broader editor,
workflow, responsiveness and final acceptance work remains open.

## navigation344 — navigation attribution and profiling controls

The installed performance342 app was traced with a complete, quiet-tail SwiftUI
recording and a separate direct-pointer Time Profiler control on the owned
1,000-note fixture. Neither establishes a concentrated app view-body,
representable-update or editor-fitting bottleneck. The earlier navigation
responsiveness concern remains open; these captures do not justify a pane rewrite,
editor sizing override or collection page-size change. No product source or tests
were changed and no new app or DMG was built.

The first SwiftUI recording clipped the input transition and is excluded from
timing conclusions. A separate Animation Hitches recording exhausted disk space
and failed with a SQLite error; it is also excluded. Five closed kernel recordings
from the prior excluded latency343 captures were removed after checking ownership
and open descriptors. Valid raw captures were retained. The artifact recording
helper now watches disk headroom during startup and recording, interrupts only its
own xctrace process below the floor, and marks interrupted evidence excluded.
That helper has syntax verification only; its live abort path remains unverified.

Native sidebar hide/restore was rechecked. The sidebar disappeared completely
and returned through its toolbar control. All 1,002 original fixture files remain
byte-exact after normal Quit. Window-edge drags and the zoom action did not change
the observed bounds, so resizing is still pending. The accessibility snapshot's
selected labels for Tasks/Select did not track the visible location; no cause or
product repair is inferred from that observation. Evidence and limits are in
`artifacts/native-macos/navigation344/verification.json`.

## latency343 — ordinary navigation diagnostics and profiling headroom

The unchanged signed performance342 app was exercised on a fresh owned
1,000-note fixture. Gallery-only/card-to-note-only navigation opens two ordinary
25-paragraph notes rich and focused. Actual search keys filter the 500-note
Gallery to one result and retain focus. Actual Portuguese acute composition
(bracketright, then e) saves exact NFC é; ordinary eleven-key typing also saves
the expected bytes. One native Undo/Save per edit restores the original. The
wrong-layout Option-E control is recorded as literal æe, not an editor defect.
Normal Quit completes; all 1,002 original note/configuration files remain exact.

Initial Animation Hitches records contain populated target-process update,
run-loop and sampled CPU data. Exports then encounter near-exhausted storage;
those unpreflighted captures are excluded from performance acceptance. Their
selected diagnostic XML and logs remain, but raw recordings were discarded.
One search recording with no delivered input was separately excluded after the
native helper required a fresh state. No application repair was made from those
uncertain samples.

Profiling headroom was recovered without removing source, products, DMGs or
vaults: two completed large XML exports were losslessly compressed, eight old
trace bundles losslessly archived with per-file SHA256 verification, and only
idle Mac build intermediates/module/index caches removed. The unrelated running
build and iOS files remain intact. Archive mappings and verification are in
artifacts/native-macos/latency343/storage-reclamation.json; decompress an archive
into QA scratch if an older report references its original path. Build caches
will regenerate, so space must be checked again before further capture.

A fresh Gallery-to-Note0999 recording and sequential export complete with exit 0.
The operational >=2 GiB headroom preflight holds throughout capture. This trace
still contains two target-attributed nonempty Potential Issue entries naming
potentially expensive app updates. Its longest warning interval and a top-level
app-update interval share a swap ID but have different scopes; their durations
are not additive. Ordinary rows in the hitches table are not all warnings.
No input-event-to-presentation timestamp was captured, so this is diagnosis,
not latency acceptance or proof that storage cleanup sped up the app.

Next is current SwiftUI body/layout attribution for the same ordinary navigation,
using small update-group exports and resource checks before selecting a repair.
MacWorkspacePanes already keeps stable pane slots; a presumed missing optimization
must not be invented from generic framework symbols. No product/test source,
build, version, DMG, AI or iOS change. The last code gate remains performance342's
279 passing non-AI tests. Evidence: artifacts/native-macos/latency343/verification.json
and next-investigation.md. Broader performance and full non-AI parity remain open.

## performance342 — remove remaining root-only export scans

The serializer's existing root-only absence proof now also skips joined-card
search, rule/gap enumeration, per-paragraph code/table range searches, and unused
source-line/CR bookkeeping. Exact source emission and UTF-16 source offsets remain;
original-token fingerprints, row eligibility, completed-export caching and the
general list/card path are unchanged. No work is moved into note opening.

The existing editor/clipboard owners pass 128 tests. The final-source non-AI gate
completes 279 tests with zero failures and terminal exit 0. No timing XCTest or
test-only production seam was added for this equivalence optimization.

Two fresh-launch optimized captures per build on the same owned 4,000-paragraph
note sample export-cache construction at 119/120 ms before and 109/113 ms after.
Whole-capture main running CPU is 369/372 ms before and 360/361 ms after. These are
inclusive 1 ms CPU samples with a modest scoped reduction, not input-to-frame
latency or ordinary-interface acceptance. The full first-edit export remains.
Both candidate runs save the exact expected eleven-character insertion; one
native Undo/Save restores the original note and control bytes after each run.
Normal Quit completes. The signed internal app remains 0.3.85/build125, with no
DMG, AI or iOS change. Evidence:
artifacts/native-macos/performance342/verification.json and export-setup-cpu.html.

Before another small stress-note optimization, the next performance acceptance
step is representative navigation/editing with display/hitch instrumentation.
The installed Xcode lists Animation Hitches and SwiftUI templates, but an actual
macOS trace still has to prove useful frame data and input/presentation correlation.
Broader non-AI parity and final delivery remain open.

## focus341 — explicit note activation owns keyboard focus

The navigation339 optimized app reproduced a focus failure on an owned two-note
Gallery: opening a new note left first responder on the window, and individual
printable key events did not enter the editor. Explicit note activation now
issues a one-time focus request. Collection navigation, vault reset and query
edits cancel pending requests; ordinary layout and model updates do not repeat
consumed requests. The native callback checks current note, active editor,
editability, composition, clipboard and sheet state, and preserves a changed
first responder. No window activation is requested.

The hosted-window regression fails four assertions on the original source and
passes with the repair. It covers initial/new/same-note activation, immediate
input ownership, search/resize focus isolation, Undo and collection search. The
existing retained-Undo owner also passes. The final-source non-AI suite completes
279 tests with zero failures and terminal exit 0.

The signed optimized app verifies startup focus, new Gallery-note activation,
retained-note activation, and actual individual printable keys without an
intervening editor click. Search retains focus and filters the collection using
actual keys. One native Undo and Save per edited note restores both originals;
normal Quit completes and all four original note/configuration files remain
byte-exact, including note BOM, CRLF and foreign metadata. Gallery and note stay
separate views. This is scoped keyboard behavior, not frame-latency, general
responsiveness or full focus/accessibility acceptance. No DMG, version bump,
AI or iOS change. Evidence: artifacts/native-macos/focus341/verification.json.
Broader performance, non-AI parity and final delivery remain open.

## memory340 — installed open/closed editor lifetime

The current navigation339 optimized app was checked on a fresh owned vault with
twelve 400-paragraph notes. Each note was opened, edited through native input,
undone and saved, leaving real live Undo/Redo history. Live `heap --noContent`
class summaries count one editor/coordinator initially, twelve with all tabs
open, and one after closing all but one tab. Closing the last note removes all
coordinators; one text view remains until focus moves to collection search, then
no MacEditorTextView or MacRichEditor.Coordinator objects remain. The empty
window's session owner remains, as expected.

This confirms bounded editor-session lifetime for this installed workflow and
clarifies the earlier hosted weak-reference observation. It does not measure
resident memory, native Undo payload bytes or input-to-frame latency. No heap
graph or object contents were saved. All twelve original note files remain
byte-exact after native Undo/Save and normal Quit. No product edits, build, version
bump, DMG, AI or iOS change. Evidence:
artifacts/native-macos/memory340/verification.json. Broader many-tab memory and
performance acceptance remains open.

## navigation339 — live Undo across collection and note tabs

Navigation338 reproduced loss of native Undo after a Gallery round trip. The
window now retains native editor/coordinator sessions for its open note tabs,
keyed by workspace generation and path. Suspended editors reject commands and
publishing; callbacks use current note/vault guards. Exact body changes reload
and clear history, while tab close, vault switch and root-view disposal discard
sessions. Stored image previews refresh on resume and Undo so retained text
history cannot revive stale picture data.

The hosted workspace regression fails on the original code. Its controls cover
Undo/Redo across collection and another note tab, hidden commands, outside body
changes, tab close/reopen, identical paths and bytes across vaults, stale-vault
commands, changed image pixels before/after Undo, and unfinished cross-item
composition. The image control caught the first retention candidate's stale
preview before the refresh repair. All 278 non-AI tests pass with terminal exit 0.

The optimized signed app verifies the original Gallery round trip, editor focus,
Cmd-Z, Redo and Undo after visiting another note tab. All 1,002 original fixture
files remain byte-exact after native Undo/Save and normal Quit. An immediate
weak-reference deallocation assertion was removed as framework-cleanup timing
did not prove a leak; physical many-tab memory acceptance remains open. This is
live per-window history, not persisted history across tab close or app restart.
Version/build stays 0.3.85/125; no DMG, AI or iOS change. Evidence:
artifacts/native-macos/navigation339/verification.json.

## performance337 — collection excerpt parsing off the main thread

The two Mac collection display call sites now use one background actor for the
existing full-source preview parser, then publish up to 512 visible graphemes.
Search, the shared full preview cache and iOS code are unchanged. Requests use
workspace generation, path and exact content. Cancelled/outdated tasks cannot
publish; a same-note previous excerpt stays visible during refresh, while another
path/vault's value is hidden. A synchronous parse may finish before cancellation
is checked.

Two preceding captures sampled 36/35 ms in the preview parser on the main thread.
The two current captures sampled none there and 36/42 ms on the worker. This
attributes the parser to its new executor; the work remains and the captures do
not measure input-to-frame latency or whole-interface acceptance.

The new rendered-card owner checks late reference definitions, external note
refresh and a vault switch with the same path. All seven collection tests and all
277 non-AI tests pass with terminal exit 0. The signed optimized app shows normal
List preview layout and refreshed typed text after autosave; native Undo restores
all 1,002 original fixture files exactly. Installed Gallery/vault-switch excerpt
acceptance remains distinct from the offscreen owner. Version/build stays
0.3.85/125; no DMG, AI or iOS change. Evidence:
artifacts/native-macos/performance337/verification.json.

## performance336 — root-export structure checks

The exporter now proves the absence of list, quote, card and rule structure once
for ordinary root prose/headings. It then skips repeated per-paragraph structure
lookups and bookkeeping. Original-token signatures, row eligibility, inline
serialization, unterminated boundaries and the full container path remain.
The existing repeated-edit owner adds a root-only formatted fixture, covering
first/repeated edits, formatting, Undo/Redo, direct multi-row storage edits and
reloads with LF, CRLF and bare CR.

Two fresh-launch captures of the preceding optimized app sampled 135/136 ms CPU
in export-cache setup; the current app samples 116/115 ms. Whole-capture CPU varied
between repeats, so this supports only the scoped cache-setup improvement, not
input-to-frame or whole-interface acceptance. The first edit still performs a
complete export. Post-autosave collection excerpt reconstruction is a separate
measured follow-up.

The two focused editor tests and all 276 non-AI tests pass with terminal exit 0.
The optimized signed app verifies native typing, autosave and Undo; all 1,002
original fixture files remain byte-exact. Version/build stays 0.3.85/125. No DMG,
AI or iOS change. Evidence: artifacts/native-macos/performance336/verification.json.

## performance335 — first-edit export allocation reduction

Paced native typing on an owned 4,000-paragraph note isolated the first edit's
full export-cache initialization. The cache already makes later prose edits
incremental. Empty block prefixes now return before the regex, and the completed
export reuses one immutable whitespace set across independent paragraphs. No
ownership, source-token, incremental-row or fallback check changed.

Two fresh-launch baseline captures sampled 147/144 ms inclusive CPU in cache
initialization; two candidate captures sampled 135/136 ms. These are running CPU
samples, not input-to-frame latency or whole-interface acceptance. The full cache
build remains on the first keypress and needs further work; this is a modest
allocation improvement, not a resolution of long-note responsiveness.

All 276 non-AI tests pass with terminal exit 0. The optimized, signed internal
app verifies paced typing, autosave, native Undo and exact restoration. All 1,002
original fixture files are byte-exact after QA. Version/build remains 0.3.85/125;
no DMG, iOS or AI change. Evidence: artifacts/native-macos/performance335/verification.json.







Performance333 reduces Gallery focus traversal by replacing per-card native
middle/triple-click overlays with a single window-local Gallery event surface.
SwiftUI anchors provide each mounted card's current bounds; ordinary clicks,
context menus and scrolling continue through SwiftUI. The region list preserves
every card occurrence, including a note present in several property/relation
groups. Other collection layouts keep their existing event path. An initial
Gallery-focus-policy trial did not improve the capture and was discarded.

The owned vault contains 1,000 notes, with 500 in the grouped Gallery. Two warmed
original captures use 494/502 ms sampled main-thread CPU; a return-to-baseline
control reproduces the cost. Two captures of the final tested optimized binary
use 409/405 ms (medians 498 versus 407 ms). Focus resolution falls from 173/174 to
109/108 ms inclusive. These are isolated 25-second Time Profiler captures without
requested AX/screenshot observations inside the recording window, not measured
input-to-frame latency. The improvement is scoped; substantial layout work and
broader navigation/typing performance remain open.

The existing native collection transport owner extends Gallery middle/triple
clicks across card positions and 900/450-point widths. A multi-group case caught
a path-keyed trial that dropped the first occurrence's region; the independent
region list passes that regression. The final collection suite and all 276
non-AI tests pass, with terminal exit 0. The signed optimized final app verifies
normal card opening, middle-click after scrolling, with folders fully hidden,
and after group collapse; sidebar restoration, full 500-note Select All, Escape,
and field-local Select All/search also pass. The special view remains exclusive
of the editor. All 1,002 original fixture files remain byte-exact. Current app
version/build remains 0.3.85/125. No iOS, DMG or production update-channel change.
Evidence and measurement limits: artifacts/native-macos/performance333/verification.json.
The chart uses final-binary measurements: artifacts/native-macos/performance333/gallery-cpu-comparison.html.

Tasks332 repairs a regression in task331's missing-checkbox adapter. Quoted
original and expanded trees already match exactly; adapting only the original
wrongly refused those notes. Compact import now accepts the exact tree match
first and uses the missing-checkbox correction only if needed. Unquoted task
recognition and the complete tree/text, byte-export and ownership guards remain.

The compact-list owner adds outer-quote, item-owned quote/bold and quoted-tab
cases under LF and CRLF. The task331 baseline fails admission and checkbox/body
assertions; the candidate owner passes, including all previous rows. The full
non-AI suite passes 276 tests with zero failures and terminal exit 0. The prior
signed app reproduces Source fallback on an owned BOM/CRLF quoted-tab fixture
without changing any note bytes. The corrected signed optimized app opens the
same note automatically rich with a checked item and nested grandchild. A real
body edit saves exact expected bytes; one Undo restores the original note,
Redo restores the whole word, and a checkbox click saves the expected quoted
unchecked expanded list. Toggle Undo restores the edited compact bytes. A
normal Quit and fresh launch reopen the saved note rich, checked and nested.
BOM, CRLF, quote/marker tabs, foreign metadata, birth date, permissions and the
control note remain intact. Actual-module literal-bracket controls pass; pinned
headless web imports confirm the intended quoted checked/unchecked states.
This supersedes task331's quoted-Source limitation for these mapped shapes.
No version, iOS or DMG changed. Other unsupported shapes and full acceptance
remain open. Evidence: artifacts/native-macos/tasks332/verification.json.

Tasks331 admits mapped unquoted compact task leaves as native checkboxes.
The pinned cmark parser misses checkbox metadata on shared marker lines, while
the web importer recognizes it. The compact import adapter now recognizes only
that exact raw leaf marker, removes its matching leading task text for the
comparison, and still compares the remaining complete block tree, paragraph
text and task state. Existing byte-exact original export and item mapping
checks remain in place. No ordinary typing path gains a parse or vault scan.

The existing compact-list owner adds checked, unchecked, uppercase checked/bold
and tabbed task rows under LF and CRLF. It fails on the original source for
admission and checkbox/body representation, then passes on the candidate; the
non-AI suite passes 276 tests with zero failures and terminal exit 0. An
actual-module probe confirms escaped markers remain literal and a second
bracket sequence stays body text. Quoted compact tasks remain Source.
The signed optimized app opens the owned tabbed fixture as a checked native
item, edits and saves its body with exact expected raw markers, and restores
all original note bytes with one Undo. Redo restores the whole word. Clicking
the checkbox saves an unchecked expanded list; Undo restores the edited compact
spelling. A normal Quit and fresh launch reopen it rich, checked and nested.
BOM, CRLF, marker/grandchild tabs, foreign metadata, birth date, permissions
and the control note remain intact. This is bounded parser parity, not full
editor acceptance or an input-latency claim. No version, iOS or DMG changed.
Evidence: artifacts/native-macos/tasks331/verification.json.

Drag330 verifies real card-payload delivery in the signed Undo329 app, using an
owned three-note vault. The automation drag by itself and a passive wait leave
the source unchanged; a follow-up target click completes delivery. An owned
Finder control exhibits the same input-completion pattern and moves its file
with exact bytes. With a canonical list-property schema, the native card moves
Draft to Review. Organization history reviews and applies Undo, then Redo; disk
checks confirm the exact expected typed-field note after both operations. BOM,
CRLF, body and foreign metadata remain intact, and peer notes, schema and view
configuration remain byte-exact. Typed Undo quotes Draft, consistent with the
existing field-value receipt contract. The initial refused run used an invalid
synthetic schema and is recorded separately; it is not a product defect.
The separate column payload also moves Done before Draft with the same input
completion route. The persisted order is No value, Done, Draft, Review; all note
bytes and schema remain unchanged by that reorder. A normal Quit and fresh
owned-root launch restore the order and the Review card. Other configured view
fields survive; the writer also emits its default null dateProperty.
This closes the bounded real payload/receipt and column check, not drag-only
automation or all drag workflows. No product source, tests, version, iOS or DMG changed.
Evidence: artifacts/native-macos/drag330/verification.json.

Undo329 addresses the compact first-character Undo boundary observed in native
QA. The existing native-typing path now also accepts a compact empty head whose
proposed edit exports the same complete item graph, even when its rendering
marker is wider than the canonical single-space form. The marker width stays
intact; NSTextView owns the complete typing sequence and its Undo/Redo.

The prior signed app reproduces the split on a fresh fixture: one Undo leaves P,
and a second restores the empty compact note. The fixture is then restored
byte-exact before candidate acceptance. The actual-module run-loop diagnostic
reproduces this for wider space/tab bullets and a numbered tab item; prose and
canonical compact controls pass. All five candidate cases restore source with
one Undo and typed text with Redo. The existing compact command owner passes
with retained-width expectations and a wider-space control; the original source
fails six expected-spelling assertions. No XCTest grouping shortcut or test-only
production seam was added. The full non-AI suite passes 276 tests with zero
failures and terminal exit 0. The signed candidate verifies actual word typing,
Save, one Undo to the byte-exact original compact note, one Redo to the full word,
Save and rich reopening. The retained marker widths, code/grandchild tabs, BOM,
CRLF, foreign metadata, birth date, permissions and control note are preserved.
This supersedes compact328's two-step typing observation for the verified shapes.
No version, iOS or DMG changed. Evidence: artifacts/native-macos/undo329/.

Compact328 extends checked tabbed-list import to supported shared-line marker
chains. Original parser byte positions identify the full structural prefix, so
inner markers expand at physical four-column stops too. Canonical native heads
keep their identities/styles; an immutable compact token restores the original
shared source and marker chain. Leaf body edits retain that spelling. Filling
an empty outer bullet uses the existing single-space marker spelling and expands
its child onto another row without changing the independently parsed parents.

Twelve public open/edit/save/reopen cases and eight compact-command rows extend
the existing owners. Final tests fail 90 assertions on the original source and
pass on the candidate, covering nested/quoted/numbered forms, descendants,
selection, emptying, outer filling and Undo/Redo. Supplemental observations cover
headings, three shared markers, Unicode and task-body literal tabs. Compact task
chains remain Source in both space and tab spellings; no round-trip pass is
claimed for them. The pinned native parser treats their shared-line [x] as
literal text, while expansion creates a checkbox. The pinned web import creates
a checked child; its live trees and exported sources are recorded separately.
Parser-consistent handling remains open. The full non-AI suite passes 276 tests
with zero failures and terminal exit 0. The signed optimized app verifies child
editing with exact raw marker reuse, outer filling with expected expansion,
saving, Undo/Redo, clean quit and rich reopening. Literal code and grandchild
tabs, BOM, CRLF, foreign metadata, birth date, permissions and the control note
are preserved. Native typing creates two Undo groups at outer expansion (first
structural character, then remaining text); exact recovery is verified, while
whole-word grouping across that boundary was open at this batch. Undo329 above
supersedes that observation for its validated compact empty-head shapes.
No version, iOS or DMG changed. Evidence: artifacts/native-macos/compact328/.

Mixed327 extends tabbed-list import across unrelated code/table cards. Code and
table source lines stay outside tab expansion. Existing immutable card models
are retained; their native ranges advance the source cursor only when their
serialized spelling matches both canonical and original source bytes. The
original parsed-HTML, exact full-source and item-parent checks still gate rich
admission. Compact shared-line tabbed heads remain Source.

The public opening/edit/save/reopen owner adds 15 mixed cases: root code or tables
before/after a list, quoted code, literal code tabs, and LF/CRLF/lone-CR files.
All 15 fail on the baseline's Source choice and pass on the candidate. An actual
module combined code/list/table check preserves exact untouched and edited
source and parents. The full non-AI suite passes 276 tests with zero failures
and terminal exit 0. The signed optimized app verifies mixed code/list/table rich
opening, child editing, saving and reopening. Exact expected file bytes, the
literal code tab, table source, unchanged parent tab, BOM, CRLF, foreign metadata,
permissions, birth date and control note are verified.
No version, iOS or DMG changed. Evidence: artifacts/native-macos/mixed327/.

Performance326 removes repeated frontmatter parsing from unchanged grouped Gallery
updates. MacWorkspace retains one grouped result keyed by the resolved collection
key, workspace identity, exact grouping name and relation interpretation. Note
inventory revisions include relation targets outside the collection; query,
filters, folder and ordering changes select a fresh result. The view uses this
production accessor instead of rebuilding groups after local collapse/selection
updates. The miss path is the original grouping function; no stored data changes.

Actual Debug-module preparation measurements use a 1000-note, 25-paragraph
synthetic collection. They measure grouping preparation, not input-to-frame
latency. Thirty-three equivalence checks and explicit scalar/list/absent/checkbox
and relation-target controls pass across invalidation cases. Seven existing
collection/Gallery owners and all 276 non-AI tests pass with terminal exit 0.
The signed optimized app verifies expected Draft/Done/Review counts, group
collapse/expand, search to one matching card and clearing back to 1000 notes.
Gallery displays alone without a simultaneous note editor. All 1002 original
fixture files remain byte-exact. This bounded grouping repair does not establish
whole-interface responsiveness. No timing XCTest, production test seam, version
or DMG was added.
Evidence: artifacts/native-macos/performance326/.

Lists325 adds a checked rich-import path for tabbed list prefixes. Tabs expand to
physical four-column stops only in a private rendering copy; original paragraph
and line tokens retain their source bytes. Admission requires equivalent parsed
HTML, exact untouched serialization and matching item parents. Editing a native
paragraph group normalizes that group's prefixes; separate untouched child rows
retain their original tabs. Code/table and compact shared-line models are not
normalized by this path; existing card admission remains independent.

The extended public opening/edit/save/reopen and list-conversion owners cover
bullets, numbers, tasks, nested/quoted items, body paragraphs, inline formatting,
links and headings across LF, CRLF and lone CR. The final tests fail 49 assertions
on the original source and pass on the candidate; the full non-AI gate passes
276 tests with zero failures and terminal exit 0. Supplemental actual-module
checks cover copying, outdent, Return, Undo/Redo, deeper outlines, literal tabs
and wiki links. The owned-card sample remains admitted through the existing
card path; a list mixed with unrelated root code and compact tabbed heads remain
Source. The signed optimized app opens the owned fixture in rich mode, saves a
child edit and reopens rich. Exact expected bytes, the untouched parent tab, BOM,
CRLF, foreign metadata, birth date, permissions and the control note are verified.
The previously installed app opened the same fixture in Source mode. Native app
access works under the current permissions; this does not establish that the
separate Settings helper crash or OS drag delivery has been resolved. No version
or DMG changed.
Evidence: artifacts/native-macos/lists325/.

Board324 retries native Kanban drag delivery after the user's newer permissions,
using the current signed Release app and a new three-note synthetic vault opened
through the native folder picker. Both card-body and card-title drag attempts
leave the card in Draft; all five original fixture files are unchanged by those
attempts. The installed app's exported board type declaration is present and
conforms to public.data. No product callback/pointer diagnostics were added.
This retry does not isolate the cause. Board308's older callback/global-pointer
observations remain separate evidence; real drag acceptance is still open.

The explicit card menu then moves Draft to Done. Native Organization history
reviews/applies Undo, Redo and a final Undo; Redo matches the first applied bytes.
Undo restores the typed Draft value with the property writer's quoted YAML
spelling, rather than the original unquoted spelling. That field-level receipt
contract also matches the desktop's value-based transition; the BOM, CRLF, body,
foreign metadata and all other fixture files stay exact. No raw-byte Undo claim
is made for the intentionally rewritten field.

The folder sidebar is then hidden completely and restored in the board, with
screenshot/AX confirmation. The non-List collection displays alone, without a
simultaneous note editor. Product hashes still match performance323's passing
sources; no code, tests, build, version or DMG changed in this acceptance batch.
Evidence: artifacts/native-macos/board324/verification.json, drag/move/Undo/Redo
records and the original/applied/undone/final card bytes.

Performance323 removes repeated timestamp parsing and calendar-day formatter
construction from Mac Tasks/search preparation. NativeRevisionIndex's Mac path
reuses the original fractional/standard Foundation formats under a private lock,
with exact UTF-8 result keys limited to 128 bytes and 4096 entries. Invalid
results are cached explicitly; longer inputs remain parsed without retention.
The Mac task query shares this parser. MacTask's Gregorian/POSIX day formatter
reuses its instance, setting the supplied time zone under its own lock. No
stored timestamp or calendar-day spelling changes; the iOS branches stay exact.

The formatter-only intermediate and final cache probes are recorded separately.
The final actual-module compatibility probe passes 12,932 comparisons against
fresh Foundation formatters, including concurrent calls, invalid/long/NUL input,
process-default-zone changes, six explicit zones and two passes over 4600 unique
timestamps beyond cache capacity. Five shared task-planning contract cases run
against the Mac module cover scheduling versus deadlines, DST completion cutoff,
invalid completion, sorting and combined filters. Preparation benchmarks retain
their actual Debug-module scope; they do not measure native input-to-frame time.
No timing XCTest or test-only production seam was added.

The final non-AI suite passes 276 tests with zero failures and terminal exit 0.
The unchanged iOS branch's generic Simulator compile/config checks pass. A signed
optimized Release app shows all 1000 pending tasks, filters Task 42 to 11 expected
matches, restores all tasks, excludes the January fixture tasks from Today and
finds Task 42 in global search with its task preview. All 1001 original fixture
files, including the tasks file, remain byte-exact. This verifies the targeted
preparation repair, not whole-interface responsiveness or full parity. No version
or DMG changed. Evidence: artifacts/native-macos/performance323/verification.json,
manual-review.json, compatibility and preparation probes, native-observation.json,
final Mac/iOS logs, Release/signature receipt and source hashes.

Performance322 removes a verified eager typing-path operation. Every writing-area
update previously called searchSources merely to supply note-link data. That
copied note/draft sources and formatted every task's search metadata on the main
actor, even while typing ordinary prose with no link picker visible.

MacRichEditor now requests its note data only for completion or preview, with
one snapshot shared by preview validation/display. MacWorkspace.noteSearchSources
retains the original notes/drafts loop without task formatting; full global
search combines that result with its unchanged task map. The workspace provider
checks its captured workspace identity, and the external editor retains its
previous note snapshot semantics. The existing test helper only adapts its
initializer argument; no timing XCTest or test-only production seam was added.

Actual Debug-module construction probes use 1000 notes and 1000 tasks and retain
the timing scope explicitly: they measure value construction, not native input-
to-frame latency. A coordinator probe observes no snapshot calls during ordinary
typing, then resolves a newly renamed note on explicit link demand without
rebuilding the editor. The final non-AI suite passes 276 tests, zero failures,
terminal exit 0, including picker, delayed-preview and global draft-search owners.

A signed optimized Release app then passes native typing, Save and manual
note-link insertion in a new synthetic 1000-note/1000-task vault. The edited
note matches the handwritten expected bytes; all 999 other notes and the tasks
file stay exact. This removes a concrete source of typing stalls but does not
establish whole-interface responsiveness. No iOS code, canonical version or DMG
changed. Evidence: artifacts/native-macos/performance322/verification.json,
manual-review.json, snapshot probes, link-demand.json, native-observation.json,
Release/signature receipts, full test log and frozen hashes.

Prose321 closes a public rich-editor admission gap: parser-owned root prose
and headings with two or three leading layout spaces no longer force Source
mode. Root paragraphs remain independent of preceding list items. Existing
code/table/list-container, tab and reference-definition checks remain in place;
this does not admit arbitrary HTML or all unsupported Markdown.

The public workspace opening owner adds 18 cases across LF, CRLF and lone CR,
including wrapped prose, a preceding list boundary and headings. All 18 failed
on the original admission path. The first candidate corrected a test
expectation: edited headings preserve their existing two-space layout. The
final non-AI run passes 276 tests with zero failures and terminal exit 0,
including exact open/edit/save/reopen bytes and the existing independent-root
paragraph boundary-edit owner. The pinned MDXEditor/Lexical probe confirms
ordinary indented root prose imports and edits as paragraphs on the desktop.

Installed Debug QA on a synthetic BOM/CRLF note observes rich mode, edits and
saves the indented paragraph, then normally quits and relaunches with the saved
text still in rich mode. Saved bytes, foreign metadata, creation date and 0640
mode match expectations; the control note is unchanged. No iOS code, version
or DMG changed. This batch makes no new performance claim. Evidence:
artifacts/native-macos/prose321/verification.json, native-observation.json,
manual-review.json, baseline/full logs and frozen hashes.

Permissions320 retries native access after the user changed permissions. The main
Zerus window is accessible, but reading the Settings hierarchy again closes the
native pipe. A new SkyComputerUseService EXC_BREAKPOINT report at 08:41:34
confirms the helper crashed; Zerus remains running (PID75505). Settings acceptance
is still blocked by the computer-use helper, rather than a permission refusal.
No product files, versions or DMGs changed. Evidence:
artifacts/native-macos/permissions320/verification.json.

Provider319 verifies an owned iCloud Drive vault through the normal native
Open Vault folder picker, not an environment-only activation. The app saved a
BOM/CRLF note while preserving foreign metadata, filesystem creation date and
0640 permissions; the untouched control stayed exact. The opaque bookmark was
stored, and a normal quit/relaunch without ZERUS_MAC_VAULT reopened that vault
and the saved note. Only synthetic QA files were used.

The new item initially reported Cocoa4355 (iCloud account unavailable), but
later snapshots reported it fully uploaded with no item error. This is a
provider status observation, not independent cross-device/server verification.
After a local byte backup, the owned note was evicted and resource metadata
confirmed NotDownloaded. Reopening the bookmarked vault displayed the saved
text; provider metadata was Current before any terminal content read. The
subsequent bytes, creation date and permissions matched the backup exactly.

The QA app was closed; the synthetic cloud folder and only its own bookmark/
recent entry were removed. Product code/test hashes still match metadata318's
276-test pass; no new build/test run, version or DMG was needed for this native
acceptance batch. Other providers, interruptions, production identity and
cross-device verification remain open. Evidence: artifacts/native-macos/provider319/
verification.json, provider snapshots and materialization-verification.json.

Metadata318 reproduces a creation-date fidelity defect through the real note
save owner. The existing eight-case UTF-8/newline/frontmatter test now includes
fixed filesystem dates, existing permissions and an independently newer control
note. The original writer fails 24 creation-date/sort assertions: body and
property saves reset the birth date, so Newest ordering changes after a fresh
scan. The final owner passes on the repaired writer; permission assertions are
controls (they already passed on the old implementation).

MacAtomicFileWrite uses Foundation's metadata-preserving replacement on macOS
inside the existing coordinated byte-CAS operation. New-file writes keep their
old path. Both legacy and stable-ID transactional note writes use the helper;
the iOS branch is unchanged and its generic Simulator compile/config check pass.
Staging is removed only after success, since replacement errors can retain the
original there. No test-only production seam is added.

Native QA on an owned two-note vault observes Newest sort, edits/saves the old
note, then normally quits/relaunches. The original birth date and 0640 mode stay
intact, mtime advances, BOM/CRLF/foreign metadata and saved body are exact, and
the newer control remains first after relaunch. The final non-AI suite passes 276 tests, zero failures, terminal exit 0. Existing historical birth dates are not reconstructed; provider
and interrupted/crash metadata acceptance remain open. No DMG/version change.
Evidence: artifacts/native-macos/metadata318/ baseline/candidate owner logs,
native-save-observation.json, manual-review.json and source hashes.

Performance317 profiles ten native keystrokes and autosave in the optimized
1,000-note/25-paragraph fixture. The trace retains the distinction between CPU
samples and actual latency. A concrete notification issue was then verified:
the first edit and a status-only change each published to the whole workspace,
although only the note footer displays saveStatus. The actual-module before
and after probes preserve body/status values and confirm the notification now
stays in the existing MacNoteDraftState. Inventory publications on Save and
all conflict/recovery guards are unchanged.

MacWorkspace keeps its status accessor; MacNoteWritingArea reads the draft's
published status directly. No timing XCTest, test-only production seam or iOS
change was introduced. All 56 focused workspace/lifecycle tests pass. The
signed optimized app displays Unsaved and Saved, autosaves the exact expected
one-character edit, and Undo restores the original bytes. All 1001 original
fixture files remain exact. The final non-AI suite passed 276 tests with zero failures, terminal exit 0.
No broader typing-latency or whole-interface responsiveness claim is made.
Evidence: artifacts/native-macos/performance317/ notification probes, native
observation, source hashes and test logs. No DMG or version change.

Performance316 builds and signs the current optimized native app without a
DMG. Native screenshot verification shows All Notes correctly highlighted;
the prior Tasks-selected accessibility text is not evidence of a navigation
state defect. No navigation patch or regression test was added for that label.

Time Profiler captures cover four short-note selections, Gallery opening and
two scrolls, and three selections in a new owned 1,000-note fixture with 25
paragraphs per note plus properties and wiki links. CPU attribution explicitly
separates accessibility-inspection stacks; it is not input-to-frame latency.
These runs do not yet establish a product hotspot warranting a code change,
and do not establish that the interface is fully responsive. Further controlled
performance work remains. Gallery displayed the collection without the note
editor, then returned to List. The old fixture's 1007 tracked original files
were restored byte-exactly; all 1001 realistic-fixture files stayed exact.
The installed optimized app remains build125; product sources match the
276-test passing hashes. No new tests/source edits, DMG or version change.
Evidence: artifacts/native-macos/performance316/verification.json and attribution.json.

Updates315 verifies update quit guards in the installed native QA app. A ready
signed update first requested quit while a note Export dialog was open: the
dialog remained intact and PID54359/build125 stayed running. With the fixture
note moved outside the vault, a typed draft failed to save and remained visible;
the update quit was refused again. With a conflicting outside version restored
to the original path, another update request retained the local draft and left
the outside bytes untouched. The native banner confirmed a changed original.

After only the fixture baseline bytes were restored (no manual Save), retrying
the pending update invoked the normal save-before-quit path. The app saved the
local draft, installed QA-only build126 and relaunched as PID54710. The editor
showed the retained text as Saved; the file exactly matched the expected edit,
including BOM, CRLF and Foreign frontmatter. This verifies an actual updater
termination request through the production guard, not a direct helper call.
The app was restored to canonical build125 and temporary feed/key removed.
Product source still matches the 276-test pass. No source/version/DMG changed.
Broader multiwindow/provider interruption and production Developer ID/notarized
update delivery remain pending. Evidence: artifacts/native-macos/updates315/verification.json.
A follow-up accessibility observation labelled Tasks selected while the main
view was All Notes. Performance316 checked the actual screenshot: All Notes is
correctly highlighted, so a navigation-state defect is not established and no
state repair is justified by that accessibility label alone.

Updates314 exercises actual native update delivery on the owned QA app. A
disposable Ed25519 seed was created outside the repository and Keychain. The
existing private HTTPS preview served a signed appcast and signed ZIP for a
QA-only build 126. Native Computer Use observed the offer, download, Ready to
Install, and Install and Relaunch. The PID changed from 52927 to 52998; the
installed app was build 126 and every regular bundle file matched the signed
archive. Its deep strict signature verified, and both synthetic vault files
remained byte-identical.

A modified feed advertising build 999 without being re-signed was refused as
an improperly signed feed. A separately signed build-127 appcast pointing at a
ZIP with one byte altered after signing (same length) was refused as an
improperly signed update, leaving build 126 installed. These are native runtime
observations, not helper-only tests. The app was then restored to the verified
unconfigured canonical build125, with temporary public feed files and private
seed removed. Product sources still match updates313's 276-test passing hashes.
No source version, DMG or production channel changed. Active-editor/save-conflict
quit cancellation and Developer ID/notarized production delivery remain pending.
Evidence: artifacts/native-macos/updates314/verification.json and the positive,
feed-rejection and archive-rejection records beside it.

Updates313 now includes native channel build settings, production packaging
preflight, and inside-out signing of Sparkle helpers/framework plus the CLI and
app. The artifact verifier independently checks the pinned framework version
and matching helper signatures/channel/team. The signed Debug QA app passes
verification. The Bundle-metadata owner test rejects incomplete, insecure,
credential-bearing and Tauri JSON feeds and malformed keys; it accepts a valid
native channel. The actual app menu was opened through native Computer Use and
showed the expected unconfigured-channel alert. No settings helper access was
needed for that flow. The final non-AI suite passed 276 tests with zero failures, terminal exit 0. This is not configured update delivery acceptance.

Updates313 permission retry: the newly granted access allows the owned native
QA app to launch and its main accessibility tree to be read. Opening Settings
still closes the native Computer Use pipe. The new helper crash report
SkyComputerUseService-2026-11-22-071444.ips records EXC_BREAKPOINT in
Array.remove(at:), matching the earlier helper failure. This is not evidence
of a permission denial or successful Settings acceptance.

The interrupted initial updater build failed because XcodeGen had run before
MacUpdates.swift was added. Regenerating the project includes the file and the
Debug build-for-testing succeeds. The built bundle remains 0.3.85/build125,
with empty native update feed/key and signed-feed verification configured.
This is compilation evidence only: updater signing, configured feed checks,
installation/relaunch, save conflicts and production delivery remain pending.
No DMG, version change, production feed publication or AI work was performed.
Evidence: artifacts/native-macos/updates313/permission-retry.json and
regenerated-build.log. The terminal non-AI suite passed: 275 tests, zero failures,
TEST EXECUTE SUCCEEDED (non-ai-tests.log).

Tasks312 proves and repairs an in-flight Mac task-save loss. A one-shot observer
of the real published tasksSaving boundary delivers an edit after the submitted
snapshot was captured. The old implementation writes that earlier snapshot, then
removes the newer private draft and resets the session, returning success. Both
normal Save and Save as new lose the later text. The final extended existing
workspace owner fails on the original source with ten intended assertions.

MacWorkspace now merges only changes delivered since submission onto the actual
saved task/copy and advances their baseline without discarding the private draft.
It returns false with a visible newer-changes message, so the existing task form
stays open. The owner proves the newer text survives in the session and private
store, then a normal retry updates the same saved record without another task.
Five focused task/workspace tests pass. No production testing seam is added.

Signed Debug native QA separately confirms paced category selection/save in both
directions with zero drafts and preserved other fields; the original supporting
note remains exact. This does not prove the cause of tasks311's earlier batched
menu/Save observation, nor a physical-input reproduction of the injected in-flight
case. The final source also rechecks the task’s vault identity after I/O and
retains its submitted workspace identity. All 275 non-AI tests pass with zero
failures and terminal exit 0 on that final source. Shared session/iOS source and deletion
semantics are unchanged; no version or DMG change.
Evidence: artifacts/native-macos/tasks312/verification.json.

Tasks311 verifies native task-list/category administration on the signed Debug
QA app. Creation by keyboard, assignment, list rename with unchanged stable ID,
review summaries and cancellation, normal app-menu Quit (PID exit confirmed),
reopen and visible saved task details pass. Both review cancellations and reopen
leave tasks.json byte-identical to its pre-review snapshot. Existing task fields,
ISO dates, completion timestamp and supporting-note identity are preserved; the
original BOM/CRLF supporting note remains exact.

One fast batched CUA category-selection/Save omits category from the first saved
snapshot while retaining it in a private draft. Recovery shows that category and
a subsequent individual Save commits it, leaving zero drafts. The cause is not
proven; do not count that first batched save as ordinary assignment acceptance.
Actual list/category removal is not applied. No source/test edit or new test run
is needed for this QA-only batch; tasks310 remains the latest 275-test non-AI
gate on this implementation. No AI/iOS/version/DMG changes.
Evidence: artifacts/native-macos/tasks311/verification.json.

Tasks310 native QA reproduces a visible optional-date save defect: clear Due,
then enter 31/02/2026. The baseline leaves Save enabled and writes dueDate null,
although invalid text remains visible. The Mac task form now gates Save, Save as
new and commit on the visible editor's validity; explicit Due off still permits
removal, and Delete remains available independently of invalid dates.

The signed Debug QA app verifies both saves disabled for that invalid sequence,
Due off/on, valid replacement, Close/recover of a valid private draft, supporting
note retention, commit/navigation through the supporting-note link, completion,
and the Completed filter. Required Scheduled empty/invalid/Return and Escape
rollback were also checked on the baseline native form. Saved date/dueDate are
2026-12-02/2026-12-03 and the supporting note uses its stable ID. The owned
supporting note remains byte-exact including BOM, CRLF and foreign metadata.

All eight existing hosted task/date owner tests pass. A proposed AX-button
regression extension cannot observe SwiftUI's buttons in its in-process hosting
tree and is withdrawn exactly, rather than counted as a pre-fix failure or kept
behind a production testing seam. The native before/after reproduction is the
fix-specific evidence. All 275 non-AI tests pass with zero failures and terminal
exit 0 on the final source. The QA app is a signed
Debug build at 0.3.85/build125; the optimized Release app from performance309
predates this repair. No shared iOS, AI, version, DMG or publication change.
Evidence: artifacts/native-macos/tasks310/verification.json.

Performance309 profiles real native navigation on the signed optimized app with
1,000 linked synthetic notes, then retains one current-path backlink result until
the inventory changes. Repeated inspector/layout reads avoid rerunning the full
calculation; the first calculation, parser, target matching and ambiguity rules
are unchanged. Every notes-array write invalidates the result, including element
content/metadata updates and replacement/removal. Storage is bounded to one result.

The preceding export probe did not justify a more complex row-offset cache, so no
editor-export change is made. Debug API controls compare the retained backlink
result against the unchanged complete resolver across stale editor metadata,
source/target changes, selection switches, Unicode, ambiguous titles and exact
path precedence. The existing outside-edit backlink owner passes, followed by
all 275 non-AI tests with zero failures and terminal exit 0. No tests or product
testing seams are added. The internal optimized Release build and strict signature verification pass.
Native inspector QA shows Note 0998 as a backlink, then no backlinks after an
owned outside source edit, then the backlink again after exact byte restoration.
All 1,007 tracked original fixture files remain exact. The navigation trace
includes AX observation and does not measure click-to-frame latency. General
responsiveness remains open.
Evidence: artifacts/native-macos/performance309/verification.json.

Board308 tests and rejects an explicit pure-SwiftUI card drag preview on a signed
Debug QA app. Temporary diagnostics confirm that the drag preview appears and
the intended Done destination (column index 3) becomes targeted. No transfer
encoding, decoding or drop callback follows. Sixteen AppKit global mouse samples
stay fixed during the automated drag. This narrows the missing handoff but does
not prove whether the cause is the automation/native drag session or the product.
The preview change and every diagnostic are removed; both production files match
their input306 hashes exactly. The dedicated QA app is restored to the verified
optimized Release build. All 1,007 tracked original files remain byte-identical.
Normal Quit attempts do not terminate the first diagnostic instance, so isolated
QA processes are terminated explicitly. No new test, version, AI or DMG change.
The restored Debug build and all three existing board scope/typed mutation/Undo
owners pass; these do not substitute for pointer acceptance.
Evidence: artifacts/native-macos/board308/verification.json and diagnostic logs.

Access307 retests native Computer Use after the user's permission update. Main
window AX and screenshots work, but the owned card drag again makes no change.
Opening Settings reproduces the helper failure: the new SkyComputerUseService
crash report shows EXC_BREAKPOINT/SIGTRAP in Array.remove(at:), while the native
app remains running. This is the same helper crash as settings302, not a newly
observed Zerus crash or an access-denial response. All 1,007 tracked original
fixture files remain exact. The isolated QA process is terminated after the
helper loses its pipe. No source, test, version or DMG change is made.
Evidence: artifacts/native-macos/access307/verification.json.

Input306 restores native keyboard QA by explicitly raising the standard app
window before sending keys. On the earlier signed QA app, printable input,
Portuguese acute composition, HTML bold paste and Undo work after Raise. A fresh
optimized Release app is then built, signed and verified at 0.3.85/build125,
including the current performance305 and export303/304 changes. No DMG is made.

Current Release checks pass on an owned BOM/CRLF note: selected parent/child-list
acute composition, no note-file write while marked, Escape rollback with selection
restoration, immediate retry/commit, and one-step Undo. Exact committed/reverted
source preserves BOM, CRLF and foreign metadata. Table typing/Tab/last-cell row
creation and independent Undo, code newline/plain paste/save/Undo, Find in Note
shortcut/result selection, and underline/save/Undo also pass. These are bounded
native interaction checks, not comprehensive IME, clipboard, VoiceOver or displayed
performance acceptance. No new product/test source is changed in this batch.

Kanban pointer drops still make no change, while an ordinary text-selection drag
works. The board menu uses the same mutation guard successfully, and the actual
app plist declares its transfer type. Cause remains unresolved between board and
native OS drag-session delivery; no protocol widening is made merely to force a
pass. Organization-history reviewed Undo works for values, but normalizes its own
YAML scalar quoting. It does not prove exact-byte property Undo. One owned card
fixture is reset to its original spelling after app closure; all 1,007 tracked
fixture files are then byte-identical.

The current QA app quits through the normal command. A too-early follow-up UI
inspection inadvertently reopens it after shutdown; that extra QA instance is
also closed normally. No new native crash report is observed. Future close QA
must rely on process state and avoid AX reads after Quit. Settings is not retried;
the distinct SkyComputerUseService crash remains open. No iOS, AI, version, DMG,
commit or publication changes. Evidence: `artifacts/native-macos/input306/verification.json`.


Performance305 coalesces still-pending private recovery checkpoint writes per
exact recovery-file identity. Each edit previously queued a complete atomic JSON
write, and Save/read/close later drained every intermediate. The writer now takes
the newest request from each pending slot. Once a slot is claimed, later input
gets a new ordered slot. Barriers seal all earlier slots and register their queue
marker under the same lock; newer input cannot merge ahead of that boundary.
Slot identity checks prevent an older task removing a newer pending entry. Raw
UTF-8 keys preserve byte-distinct paths and independent window/vault owners.
Filename hashing remains on the writer thread. Existing checkpoint format,
atomic writes, readback checks and failure feedback are retained.

An actual-helper burst probe on 96 KB bodies preserves final baseline/body bytes.
Single controlled Debug samples, including input construction, total 48.5 ->
5.4 ms for 50 rapid registrations and 143.8 -> 7.8 ms for 200. Remaining queue
drain is 46.0 -> 1.7 ms and 138.8 -> 1.5 ms respectively. These are synthetic
queue-backlog measurements, not normal typing or installed input-to-frame
latency. A first candidate added eager filename construction to registration;
the final raw-byte key removes that unnecessary caller work.

Five existing lifecycle owners pass, including multiwindow draft isolation,
burst/save cleanup, close guards and restart recovery. The exact final-source
non-AI gate passes 275 tests with zero failures and terminal exit 0. Additional
actual-helper controls run 24 rounds of latest-byte/barrier/explicit-checkpoint
ordering, independent owners/roots, Unicode byte-distinct paths, removal without
resurrection, and newest failure-callback delivery. Tracked owned control paths
are verified removed. No new XCTest, timing assertion or product test seam is
added. No real vault, iOS/shared writer, AI, versions, DMGs, commit or publication
changes. Broader UI performance and native input/Settings acceptance remain open.
Evidence and the scoped chart: `artifacts/native-macos/performance305/verification.json`.


Export304 closes the PDF/print whitespace-decoration limit recorded in export303.
AppKit's normal underline routine intentionally trims line-edge spaces. A private
PDF-only layout manager keeps superclass word/font drawing and restores explicit
edge-space/tab decoration with AppKit's own lower-level primitive. It excludes
line terminators and by-word styles, prevents overlap on all-space lines, and
clips hanging spaces to the line fragment. No note characters are substituted.
The baseline offset comes from the actual laid-out glyph baseline measured from
the fragment's bottom; an initial zero-offset candidate failed the letter-edge
case and is retained as rejected evidence.

The existing export owner gains actual-PDF raster cases: all-space underline,
matching undecorated blank control, and a letter surrounded by styled spaces.
The all-space case has no glyphs that could falsely satisfy the ink check; the
letter case requires a continuous line wider than that letter. Final tests fail
three intended assertions on the old renderer, pass after repair, and the exact
current-source non-AI gate passes 275 tests with zero failures and terminal exit
0. No new test function or product testing seam is added.

A complete real-note export page is inspected with ordinary, edge, blank-line,
quote, list and table-cell underlines. Its PDF and print page rasterizations are
byte-identical. Original synthetic note bytes remain unchanged; export/print
report no warnings. This is static output verification, not native editor/input
acceptance or physical-printer QA. Shared/iOS source, AI, versions and DMGs are
unchanged. Evidence: `artifacts/native-macos/export304/verification.json`. Broader
performance, export pagination/providers, installed workflows and full parity
acceptance remain open.


Export303 repairs styled-whitespace collapse in standalone HTML and the Mac
HTML-to-PDF/print path. The shared HTML stylesheet applies white-space:pre-wrap
to underline elements, preserving actual spaces without substituting nonbreaking
characters or disabling ordinary wrapping. Three underlined spaces between
letters and underlined word edges survive native HTML import. Whitespace-only
paragraph characters and attributes also remain; separate full-page inspection
shows AppKit still does not visibly paint the underline on an all-spaces line,
so that painting behavior remains open.

The existing export owner is extended, not duplicated. Generated HTML passes
through the actual NSAttributedString importer used for PDF, asserting literal
spacing and underline attributes. Baseline fails the two intended assertions;
repaired focused checks pass, and the non-AI gate passes 275 tests with zero
failures and terminal exit 0. After that full run, only an assertion's diagnostic
wording is narrowed to retained importer text; assertions/fixtures are identical,
the exact full-run test copy is retained, and the final focused run passes again.
A real owned note exports HTML, Word, PDF and print PDF without warnings or source
changes; the complete PDF page is inspected.

The shared writer is rebuilt/installed in the isolated iOS Simulator, preserving
0.3.107/build57 and all seven original note/resource files. The actual prepared
HTML contains the new rule. Its export preparation/warning screen is shown and
left available in the Device panel. This is a shared-writer regression preview,
not new iOS underline editing. No AI, version bump, DMG, commit or publication.
Evidence: `artifacts/native-macos/export303/verification.json`. Broader export
layout, native input, performance and full parity acceptance remain open.

Settings302 identifies the native automation blocker more precisely. Main-window
AX access works after a fresh automation reset. Opening Settings returns from the
click, but a subsequent screenshot request closes the helper pipe too. macOS
records SkyComputerUseService crashing with EXC_BREAKPOINT/SIGTRAP at
Array.remove(at:); Zerus Native remains running. This is evidence of an automation
helper crash, not an app crash or merely an AX-text failure. The exact owned QA
process is terminated and all 1,006 original fixture files remain unchanged. No
permissions or product files are changed. Evidence and filtered crash stack:
`artifacts/native-macos/settings302/`. This route should not be repeatedly retried
as a permission request; Settings interaction acceptance remains pending.


Compatibility301 runs an owned-file round trip through the actual native Mac
VaultFiles/NoteDocument/frontmatter module, the current desktop DesktopVault and
notes-store, native services again, and a fresh desktop store. Real filesystem
bytes are read/written; only Tauri filesystem/event transport is adapted to Node
and private browser storage is isolated in memory. The UTF-8 reader uses
TextDecoder to match the Tauri plugin's single-BOM handling.

Both clients retain stable IDs, ordinary foreign metadata/comments, typed list/
number/date properties and the folder schema. Desktop pin/archive/body/property
edits are read natively; a native return edit and explicit archive false are read
by desktop despite old private archive=true state. Native CAS refuses old bytes.
The unchanged target note and schema remain byte-exact. Desktop saving renames
the source to its title-derived filename; the initial harness wrongly assumed
the old path, and the final cycle follows stable identity. Edited source BOM/
line-ending spelling is normalized by the desktop reader/writer, so this is
semantic interoperability rather than exact-byte round-trip evidence for the
edited note. All four final stages exit 0.

No product source, versions, DMG, AI or iOS changes. No real vault is touched.
This does not verify GUI, watcher/coordinated-write delivery, providers/cloud
interruption or iOS interoperability. Those acceptance areas remain open.
Evidence and retained owned final-vault copy: `artifacts/native-macos/compatibility301/`.


Performance300 skips cold backlink parsing only for bodies without ASCII `[`,
`<` or `:`. These bodies cannot contain wiki/Markdown links, angle autolinks or
a bare scheme URL. Every possible link body retains the original parser and
full resolver; the existing source-content cache stores the equivalent empty
reference list. No new cache or invalidation state is added.

An actual in-memory Debug MacWorkspace probe with ordinary-prose notes and one
linked source preserves its exact backlink result. Cold getter samples improve
from 28.5 to 5.6 ms for 250 notes and 105.5 to 16.1 ms for 1,000 notes; repeated
reads are essentially unchanged. These single controlled CPU samples are not
installed interaction latency or evidence of whole-interface responsiveness.
Eleven legacy-oracle selected-note cases, nine no-syntax parser controls, seven
transport shapes and outside/cache-edit controls remain equivalent. The current
non-AI Mac gate passes 275 tests, zero failures, terminal exit 0, including the
existing real-vault backlink owner. No test seam or timing XCTest is added for
this equivalent fast path. Shared/iOS code, AI, versions and DMGs are unchanged.
The web reference endpoint responds 200 directly and through the private proxy.
Evidence: `artifacts/native-macos/performance300/verification.json`. Broader
performance and native input/Settings acceptance remain open.


Underline298 repairs whitespace fidelity at the native clipboard boundary.
An underlined copied space was retained in RTFD but lost from the portable
fragment; independently formatted words could also gain underline on their
plain gap after reopen. The inline encoder now keeps styled edge/space-only
text inside `u` with explicit entities and closes underline before a plain gap.
The macOS HTML converter retains whitespace-only element/CSS underline too.
The iOS branch is unchanged.

Existing owners are extended, with no new test function or product testing seam.
They use real NSPasteboard representations (restored afterward), native fragment
and RTFD conversion/paste, actual editor formatting/reopen, source immutability,
Undo/Redo and HTML/CSS import. The corrected identical baseline fails 18 intended
assertions across three owners, while the repair passes them. A first fixture
incorrectly demanded canonical entities when a whole-body copy correctly reused
its original source spelling; copied and RTFD-converted payloads now have separate
handwritten expectations and both must preserve native underline attributes.
The final matching-source non-AI Mac gate passes 275 tests with zero failures
and terminal exit 0.

The shared file is rebuilt and installed in the isolated iOS Simulator with
0.3.107/build57 unchanged. All seven original note/resource files remain exact,
and the existing note editor is visually checked and left available in the
Device panel. This is a regression preview for a macOS-only converter branch,
not new iOS underline editing. Native Mac installed input/clipboard acceptance
is still blocked by the permissions293 helper-pipe failure. Broader formatting,
export/layout, IME/VoiceOver and full parity acceptance remain open. No AI,
version bump, DMG, commit or publication. Evidence:
`artifacts/native-macos/underline298/verification.json`.

Underline297 closes a web/native formatting gap. The native toolbar and menu
now offer Underline (⌘U), including the external-note toolbar. Selected text,
caret typing and explicit Source wrappers use the existing guarded editor action.
Underline is part of source-reuse signatures and the portable encoder, so style
changes cannot silently reuse an earlier unformatted token. The native renderer
now understands balanced attribute-free inline formatting tags, including `u`,
with nested font/link context; unmatched or attribute-bearing HTML stays protected
Source. HTML/CSS underline paste is sanitized to portable markup on macOS.

The semantic export style carries underline through HTML, Word and PDF/print.
Word's hyperlink underline is emitted only once. Shared UIKit PDF output also
understands the style; iOS editing/parser support for underline is unchanged.
The isolated simulator build/install leaves 0.3.107/build57 intact and verifies
the existing export preparation/warning screen, with all seven owned original
note/resource files exact. It remains available in the Device panel. This is a
shared-writer regression preview, not new iOS underline editing acceptance.

One new primary editor owner covers Unicode, inherited bold and links, heading/
quote/list/table roles, LF/CRLF, reopening, selection, caret typing and Undo/Redo,
plus safe-format import and malformed/attribute-bearing negative controls. Existing
clipboard and export owners cover distinct HTML/CSS transport and writer paths.
The final corrected same-fixture baseline fails 109 intended assertions across
three owners; the repaired owners pass. An initial caret fixture started from
parsed trailing source whitespace; it was corrected to type that visible space
through NSTextView before repeating both baseline and repaired runs. Final gate:
the matching-source non-AI Mac suite passes 275 tests with zero failures and
terminal exit 0.

A real owned BOM/CRLF note is exported as HTML, Word, PDF and a print document
through production APIs, without modifying the source. Native attributed drawing
and the complete PDF page are visually inspected; plain, bold/italic, linked,
list and table text show underlines, with the final body sentinel retained. The
drawing is not native interaction QA. Mac Computer Use is still blocked by the
permissions293 helper-pipe error, so toolbar/⌘U delivery, installed IME/VoiceOver
and broader formatting acceptance remain open. No version bump, DMG, commit or
publication; AI remains deferred. Full parity is not established. Evidence:
`artifacts/native-macos/underline297/verification.json`.

Performance296 reduces repeated full-vault backlink resolution. Before resolving
against every note, the getter applies the unchanged reference matcher to the
inventory entries at the open path. A reference that cannot select that path
from the subset cannot select it from the complete vault. Every possible match
still uses complete-vault resolution, preserving ambiguity and exact-path
precedence. Inventory metadata is deliberate: a retained editor baseline may
have an older title after an outside edit. No persisted index or invalidation
cache is introduced; parsed-source caching and result ordering stay unchanged.

An actual in-memory MacWorkspace probe measures cold and repeated reads in
synthetic title-link rings; expected backlink sources remain exact. A separate
legacy full-resolution oracle matches all selected paths across stable/duplicate
IDs, trashed duplicates, ambiguous/path-shadowed titles, heading and literal-hash
references, styled/table/code examples and Unicode variants. It also checks
inventory metadata newer than the editor baseline and a changed cached source.
The chart in `artifacts/native-macos/performance296/backlink-cost.html` reports
this bounded Debug calculation cost; it does not measure native input-to-frame,
file I/O or general responsiveness. The final matching-source non-AI Mac gate passes 274 tests with zero failures
and terminal exit 0, including the real-workspace backlinks owner.

No test source or test-only product seam is added for this behavior-preserving
performance change. The existing real-vault backlinks owner stays in the non-AI
gate. Mac native interaction acceptance is still blocked by the permissions293
helper-pipe failure. No AI/iOS change, version bump, DMG, commit or publication.
The full goal and broader performance/input/accessibility acceptance remain open.
Evidence: `artifacts/native-macos/performance296/verification.json`.

Performance295 scopes live syntax highlighting to the code blocks touched by
an NSTextStorage edit, including insertion/deletion neighbours. It retains a
complete lexical pass for each affected block, so multi-line tokens are not
highlighted from an isolated changed line. Structural/unknown/marked-text edits
still request the complete pass; rendered loads already have current colours.
Card placement continues to use the existing complete layout pass. No source
content or layout cache is added.

An actual-module scratch probe uses the production editor coordinator, NSTextView
and NSWindow to replace code text in multi-block notes. It records synchronous
replacement cost and attribute-edit notifications; only affected code receives
new highlighting attributes. Every intermediate Markdown value is exact and the
complete attributed document equals the unchanged full-style reference. Six
additional rich-admitted controls cover quoted/list-owned/indented/tilde code,
a table neighbour, unknown language, Unicode/CRLF, Undo/Redo and batched edits
in distant code blocks. This is bounded Debug editor work, not an installed
input-to-frame or whole-interface responsiveness claim. The final matching-source non-AI Mac gate passes 274 tests with zero failures
and terminal exit 0.

No test source or test-only production seam is added for this behavior-preserving
performance change. Existing code colour, card/container, composition and Undo
owners remain in the non-AI suite. Native Computer Use remains blocked by the
permissions293 pipe failure; it was not retried without a state change. No AI/iOS
change, version bump, DMG, commit or publication. Full parity and broader
performance/input/accessibility acceptance remain open. Evidence:
`artifacts/native-macos/performance295/verification.json`.

Export294 bounds export/print image decoding before ImageIO thumbnail creation.
The shared Apple export engine now reads uncached source metadata and accepts up to
16,384 pixels per side and 40 megapixels, matching the existing Gallery limit.
Oversized or invalid-dimension images retain their labels and produce a readable
warning; supported images continue through the existing sized-image writers.
Cancellation detected before thumbnailing propagates instead of being converted
into an image warning. This is a bounded decode-memory protection, not evidence
that general navigation or typing latency is resolved.

The existing real-image export owner now adds valid highly compressed wide, tall
and over-area PNGs plus an image exactly at the supported side limit. It checks
omission, useful warnings, retained labels, ordinary/boundary images and unchanged
original files. The final same-fixture baseline fails ten intended assertions.
An initial fixture-size assertion was too strict despite the fixture being far
below the existing byte budget; it was corrected before repeating the baseline.
The final matching-source non-AI Mac gate passes 274 tests with zero failures
and terminal exit 0, including the extended real-image export/print owner.

The shared change is built and installed in the isolated iOS Simulator without
advancing 0.3.107/build57. Device-panel QA prepares an actual PDF, shows the
size warning, opens Quick Look, and visibly retains the ordinary blue/orange image,
the omitted image label and the final body sentinel. Poppler confirms one real
64×32 image and retained text; the complete rendered page is inspected. All four
pre-existing simulator notes and the three owned QA note/resource files remain
byte-exact. The simulator is left on the prepared export/warning screen.
Evidence: `artifacts/native-macos/export294/verification.json`.

Permissions293 records the new-permission retry: native Computer Use still fails
at app binding with “Sky Computer Use native pipe closed before response”. The
owned QA process is closed and its original files stay exact. No system settings
or permissions were changed by the agent. New Mac native interaction acceptance
is therefore pending; automated Mac export/print behavior remains testable.
No AI, version, DMG, commit or publication work was performed. Full parity,
general responsiveness, accessibility/input and final delivery acceptance remain
open.

Print292 repairs a native printing defect reproduced in the installed optimized
app: the resource-free NSTextView path printed an unavailable-image placeholder
for a valid local PNG. Its original native print preview and saved baseline PDF
both show that failure.

Print now prepares a frozen current-body request through the existing read-only
export document engine, resolving local resources with visible properties excluded,
and renders the paginated PDF without writing an intermediate file. PDFKit supplies
the native print operation, using copied NSPrintInfo, fit/rotation and the note's
job title. A preparation dialog reports pages, failures and missing-content warnings
before printing. Its task and retries share the dialog lifetime, so dismissal
cancels pending work. Export and Print reuse the visible bounded warning view.

The existing sized-image export owner is extended with a distinct printing
resource/warning contract: rasterize the actual print document at natural point
scale and require the intended blue/orange bitmap, then report a real missing
image. The previous named-color fixture was transparent in this headless context;
explicit device RGB values now make its intended image deterministic. The final
same-fixture legacy renderer baseline fails three intended assertions and the
candidate passes. The final matching-source full non-AI gate passes 274 tests,
zero failures. An earlier run was deliberately interrupted for the retry-lifetime
repair and is not a passing gate. No test function or production testing seam added.

Signed optimized native QA verifies preparation Cancel and native-panel Cancel,
editor focus restoration, Return opening Print, the image in the system preview,
the correct job/default PDF name, and native Save as PDF. The resulting ten-page
A4 file includes the image/table and each paragraph sentinel once, hides properties
and reserved metadata, and contains no unavailable-image placeholder. All rendered
pages and a high-resolution boundary detail were inspected. A separate missing-image
note shows a readable warning before opening the print panel and cancels without
output. All original note/asset bytes remain exact; the QA app is closed. No printer
was selected and no physical print job was sent. Evidence:
`artifacts/native-macos/print292/verification.json`.

Mac version remains 0.3.85/build125. No AI/iOS change, version bump, DMG, commit or
publication. Physical printing, wider print settings/layout, provider/input/
accessibility, general responsiveness and full parity acceptance remain open.

Export291 adds native PDF/Word/HTML choices, PDF as the initial format, and an
Include properties toggle matching the web flow. Export captures baseline
metadata with the current editor body when the dialog opens. That immutable note
and vault root survive later edits and asynchronous preparation; exporting does
not require saving over an outside-file conflict. The writer removes its owned
temporary artifact directory, and the dialog shows progress, failures, success
and incomplete-content warnings. Print now receives the same current-body
snapshot; complete print pagination/image acceptance remains separate.

The new real-workspace owner creates an outside edit and a retained draft, then
checks all three formats with properties off/on, frozen content after later
editing, hidden reserved metadata and unchanged disk/editor data. A small initial
request/writer extraction retains the old saved-note behavior; that baseline fails
12 stale-body assertions. The repaired owner and existing sized-image/pagination
owner pass. After the final warning-layout repair, the matching-source full
non-AI gate passes 274 tests with zero failures.

Signed optimized native QA verifies PDF defaults, all format choices, the property
toggle, option-dialog Cancel returning editor focus, save-panel Cancel retaining
options, and actual HTML/Word/PDF saves. HTML excludes properties when requested
and retains formatting/table content plus identical decoded image pixels. Word
includes visible properties, native table/image data and all source sentinels.
The ten-page A4 PDF retains properties, image/table and every paragraph sentinel;
all rendered pages were inspected. Reserved Zerus metadata stays hidden. A
missing-image PDF retains its body and label and reports its warning. The first
native warning screenshot exposed a collapsed warning area; an explicit bounded
height fixes it, and the final optimized native screenshot shows readable text.
All original note/resource files remain byte-identical and the QA app is closed.
Evidence: `artifacts/native-macos/export291/verification.json`.

Mac version remains 0.3.85/build125. No AI/iOS change, version bump, DMG, commit or
publication. General responsiveness, broader editor/export/print/accessibility,
provider/cross-client and final parity acceptance remain open.

Performance290 adds a macOS-only fast path to the shared wiki-link converter.
Without the exact literal `[[` opener, conversion can only copy the source, so it
now returns that source directly. Inputs containing openers still run the complete
existing escape, backtick and reference scanner. There is no content cache or
new parser/admission rule.

A signed optimized native capture of repeated long-note switches in a 1,000-note
vault located converter work on the main thread. Seven actual-module controls
retain exact conversion and rendered-export SHA256 values for ordinary Unicode
text, references, aliases, heading fragments, escapes, code spans and malformed
openers. The matching-source non-AI gate passes 273 tests with zero failures;
existing tests are unchanged. The final native capture is consistent with skipping
the scanner on opener-free text. Captures contain substantial accessibility
inspection, and candidate tabs are retained from baseline, so total timing is not
a controlled input-to-frame or whole-interface performance comparison.

In the updated signed optimized app, all eight requested note switches open the
correct note. A bounded edit to a long formatted note saves only the intended
insertion; native Undo restores the original exactly. All 1,000 original files
remain byte-identical after QA, and the Mac app is closed. Because the converter
lives in shared source, iOS was also rebuilt/installed on the isolated simulator
without advancing 0.3.107/build57. Its editor renders the existing Welcome note,
all four original notes remain exact, and the Device panel preview stays open.
The installer relocates its container; final integrity resolves the current path.
Evidence: `artifacts/native-macos/performance290/verification.json` and
`ios-preview.png`.

Internal Mac version remains 0.3.85/build125. No AI change, version bump, DMG,
commit or publication. General editor construction, large-vault responsiveness,
accessibility, remaining workflow parity and final acceptance remain open.

Performance289 avoids redundant paragraph-style writes when publishing an edit
in a note containing list-owned code or tables. Placement still recomputes the
full required style, including table cell geometry, context indentation, quote
suffixes and code inset; it assigns the style whenever the complete value differs.
There is no source, layout or authorization cache.

The controlled actual-Debug helper/layout probe retains every character,
attribute and exported Markdown byte and confirms that repeated unchanged
placement checks no longer create storage-edit notifications. This demonstrates
a bounded avoided cost, not installed input-to-frame or whole-interface latency.
Existing tests are unchanged; the matching-source full non-AI gate passes 273
tests with zero failures. Existing native card owners cover real style changes,
marker widths, cell layout, model transfer, sheets and Undo/Redo.

The signed optimized internal app verifies prose typing and exact native Undo/Redo
in a BOM/CRLF note with fifteen list-owned code/table pairs. Converting its first
parent to numbered form changes only that marker and its owned indentation.
Code and table edits then save only their intended substitutions. Final native
Undo restores the original fixture byte-for-byte, and the QA app is closed.
Evidence: `artifacts/native-macos/performance289/verification.json`.

Internal version remains 0.3.85/build125. No AI/iOS change, version bump, DMG,
commit or publication. Broader performance, remaining editor/workflow parity,
Settings native helper access, pointer drag and final acceptance remain open.

Outline287 resolves the compact286 Outline follow-up. Heading enumeration now
includes quotes and list items in document order, excludes fenced-code examples,
and uses displayed alias/code labels. Source offsets are computed within each
line. Rich navigation pairs the complete parsed heading sequence with actual
native heading rows, avoiding a separately rendered truncated source prefix and
placing the caret after any visible list marker.

The two extended owners fail on the baseline for the intended missing nested
contracts. Four affected owners pass on the final files, and the full non-AI gate
passes 273 tests with zero failures. In the signed optimized internal app, Source
and rich Outline jumps, offscreen compact headings, duplicate heading IDs and a
local Markdown link reach the expected caret. Typed probes change only the
intended heading body; native Undo restores both original fixture notes exactly,
including BOM, CRLF and foreign metadata. Alias/code labels display without source
backticks. This verifies the bounded navigation repair, not general responsiveness
or full accessibility acceptance. Evidence:
`artifacts/native-macos/outline287/verification.json`.

Internal version remains 0.3.85/build125. No AI/iOS change, version bump, DMG,
commit or publication. Performance, remaining input/clipboard cases, pointer drag,
Settings accessibility and final non-AI acceptance remain open.

Compact286 admits mapped shared-line list heads whose first block is a heading,
including quote/list and numbered forms. The same expansion and original-source
token path now accepts Heading alongside Paragraph; complete parsed node/text
comparison, exact exported bytes and native/parser parent mapping remain required.
Unsupported compact HTML remains Source. This is not arbitrary non-paragraph
admission.

Three existing owners are extended: compact editing/ownership, real workspace
opening/save/reopen, and standalone clipboard heading/child roles. Baseline runs
fail the intended new contracts before the import change. The final-source non-AI
gate passes273 tests, zero failures; the three focused owners pass separately.
No test function or production testing seam is added. Editor rows cover LF/CRLF,
and clipboard rows cover LF/CRLF/lone CR with source/structure, selection,
Undo/Redo, fragment/HTML paste and subsequent typing checks.

The signed optimized internal app remains0.3.85/build125. Ordinary and numbered
compact headings render as separate rich rows. Child-to-Edited saves an exact
compact substitution; native Undo/Redo restores spelling. Typing Parent into the
outer empty item expands source exactly, and one native word Undo restores the
entire original compact note. Numbered editing retains BOM, CRLF, metadata and
siblings byte-for-byte. Both forms reopen in rich mode after Quit/restart. After
closing the QA app, all three original note files are restored. Evidence:
`artifacts/native-macos/compact286/verification.json`.

A required Outline follow-up was reproduced separately. MacHeadings currently
visits only document children, whereas web NoteOutline lists all rendered nested
headings. An actual-module probe also confirms that rendering the truncated source
prefix can locate the wrong native row for compact nested headings. Enumeration
and caret mapping were still pending in compact286; outline287 above resolves
this specific follow-up. Evidence:
`artifacts/native-macos/compact286/outline-followup-results.json`. Broader rich,
clipboard/input/accessibility, performance and final acceptance remain open.
No AI/iOS change, version bump, DMG, commit or publication.

Metadata285 repairs reserved-metadata interpretation across native, web and CLI.
The CLI accepts quoted true/false case-insensitively and ignores reserved key
casing. The web reader previously missed both forms (including mixed-case IDs),
and native treated quoted uppercase TRUE as false. Web reserved lookup now folds
key casing locally and recognizes quoted boolean scalars; native flag lookup
accepts their casing. Existing explicit false/empty values still override legacy
private fallback, and ordinary user properties remain typed text without rewriting.
This does not import another application's private state or migrate a real vault.

The final-source non-AI Mac suite passes273 tests, zero failures. Web metadata,
frontmatter, history and external-store owners pass65 tests, with TypeScript and
changed-file ESLint passing. The raw web scalar/key/fallback tests fail on the
original source; native Pinned/Archive membership fails before the uppercase
scalar fix. No production testing seam is added. Final audit removes a redundant immutable-content
self-check from the new test; all six final collection owners pass after that
test-only cleanup, with the product source unchanged from the273-test gate.
Invalid numeric/list/duplicate
reserved metadata remains outside this compatibility change: CLI validation is
stricter than native/web read fallback and still refuses invalid reserved forms.

The signed optimized Mac app shows exactly the copied fixture's Pinned and Archive
members, agreeing with actual bundled CLI and web reader results. The actual web
withBody serializer preserves the BOM/CRLF header while adding body text. Native
opens and saves an exact body-only substitution, after which CLI and web readers
retain the same ID/pin/archive state. All three original Mac fixture notes are
restored after Quit/process verification. This is serializer/native/CLI evidence,
not a full web-app/provider synchronization acceptance cycle.

Because NoteDocument is shared, the unchanged0.3.107/build57 iOS simulator app was
built, installed and previewed in the Device panel. Pinned shows the synthetic
quoted-uppercase note (plus the pre-existing Welcome); Archive shows only the
synthetic archived note. The false control is absent from both. Three additive,
owned notes remain byte-identical in the isolated simulator library, with Archive
left available for preview. Screenshot and evidence:
`artifacts/native-macos/metadata285/ios-archive-preview.png` and `verification.json`.
Internal Mac stays0.3.85/build125; no AI, DMG, version advance, archive/upload,
commit or publication. Broader provider and installed accessibility/full parity
acceptance remain open.

Performance284 removes duplicate Kanban render-data preparation. A fresh board
snapshot supplies both member groups and drag scope to the rendered board. The
public scope getter still recomputes the current snapshot for every existing
before/after-await and commit guard; no cross-render authorization cache is added.
The unused columns forwarding helper is removed. Actual Debug helper probes with
warmed metadata support retaining the change; these measure preparation only,
not layout, provider IO, optimized external input-to-frame latency or broad app
responsiveness. Data is in `artifacts/native-macos/performance284/preparation-summary.json`.

The final matching-source non-AI suite passes272 tests, zero failures, including
stale scope refusal, column ordering, stored arrays and typed moves with Undo.
No test source changes. An earlier run was intentionally canceled to remove the
unused helper and is not counted as a pass. The signed optimized app reviews
exactly Alpha/Beta with no original-file write before Apply; only their Status
scalars change. History Undo restores Draft values (quoted edited scalars), and
Redo matches applied bytes exactly. A column chevron moves Done before Review in
both live UI and views.json, retaining the foreign setting. After Quit via the app
menu and process verification, all five original note/schema/views files are
restored byte-for-byte. The initial Command-Q attempt did not close the app.
Evidence: `artifacts/native-macos/performance284/verification.json`.

Board283 separately retries current native pointer drag: the helper returns
without a move/review or original-file change. Drag269's standalone controls were
also unreliable, so no board-specific defect or pointer acceptance is established.
Settings/CLI CUA limitations and broader parity/performance remain open. Internal
version stays0.3.85/build125; no AI/iOS/test change, DMG, commit or publication.

Gallery282 makes grouped Gallery build its group layouts lazily. The group loop
now lives in LazyVStack with unchanged spacing; ungrouped Gallery and each group's
progressive grid, cards, domain membership and navigation order are unchanged.
An actual-module Debug layout probe with warmed metadata and empty menus/no image
IO supports retaining the change for initial grouped-view construction. It is not
a Release input-to-frame or general responsiveness measurement. Detailed measurements
are retained in `artifacts/native-macos/gallery282/layout-cost-summary.json`.

The final matching-source non-AI suite passes 272 tests, zero failures, including
the existing grouped/ungrouped pagination/search owner. No test changes or timing
XCTests were added. The signed optimized internal app verifies 500 owned notes in
101 groups, with 200 notes in the final group: normal scrolling reaches card0000
through progressive pages, Select All includes all500 notes, Escape clears, and
the final card opens the editor alone. A collapsed group retains its state after
scrolling offscreen and back; search matches one note and clearing restores the
complete result set at the top. Synthetic local covers render. AXScrollToBottom
can initially land approximately while lazy heights settle; ordinary scrolling
reaches the end. Leaving Gallery for the editor recreates the view and resets
collapse, as before. All502 original note/image/views files remain unchanged,
with no added files. Evidence: `artifacts/native-macos/gallery282/verification.json`.

This is bounded grouped-Gallery construction work; broad responsiveness, provider,
keyboard/accessibility, cross-client and release gates remain open. Internal version
stays0.3.85/build125; no AI/iOS change, DMG, commit or publication.

Mixed281 admits mapped lists inside item quotes when they contain native code or
table cards. Admission still requires exact UTF-8 roundtrip, matching item parents,
card ownership/kind and logical models. Unsupported shared-line heading controls
remain Source. Prerequisite fixes preserve relative quote suffixes when cards are
promoted, rebase continuation gaps when marker widths change, and detach clipboard
cards without inherited list indentation. Cross-quote selection merges retain the
previous container boundary.

The final matching-source non-AI suite passes 272 tests with zero failures; ten
affected owners pass separately. Baseline runs expose admission and ownership
defects before the repairs. Signed internal Release QA verifies nested code-sheet
editing, table-cell editing with BOM/CRLF, compact body editing and Undo/Redo.
Each saved change matches only its expected byte substitution; all three modified
notes reopen in rich mode after restart. Portuguese acute composition was checked
with no disk write while marked input was pending; broader IME remains open.
An initial combined input sequence left an extra list split; clean isolated code
sheet verification passed. A stale code request was safely refused. All four owned
fixture notes were restored and their original hashes verified after closing the app.

The new-permission Settings retry still closes the CUA native pipe. This is pending
tool coverage, not accepted Settings/CLI or VoiceOver behavior. Evidence:
`artifacts/native-macos/mixed281/verification.json`. Internal version stays
0.3.85/build125. No AI/iOS change, DMG, commit or publication. General performance,
other compact non-paragraph structures and broader parity acceptance remain open.

Calendar280 removes eager creation of the entire Undated card column. The
actual-module Calendar layout probe mounted every control in the baseline's
50/250/1,000-note collections. Replacing only that column's VStack with LazyVStack
keeps card construction near the viewport and reduces initial/settled layout work.
The calculation/order, complete collection, existing cards, menu/keyboard routing,
image loader, dimensions and month grid remain unchanged. The probe hosts the
actual Debug view offscreen with metadata warmed, empty menus and no image IO;
it is not a Release input-to-frame or general interface-latency measurement.

The final-source non-AI suite passes 272 tests with zero failures; no tests changed.
Signed internal Release QA uses one dated and 500 Undated notes with intermittent
local image covers. Native end-of-list scrolling reveals the last note, which
opens in the editor alone. Command-click selects one, Command-A reports all 501
notes selected, and Escape clears selection. Returning to Calendar renders the
synthetic cover. All original note/image/views bytes remain unchanged. Evidence:
`artifacts/native-macos/calendar280/verification.json`. Broader responsiveness,
provider, rich/clipboard/IME, Settings/CLI tool and release acceptance remain open.
No AI/iOS changes, version bump, DMG, commit or publication.

Calendar279 removes repeated Calendar date setup and duplicate collection passes.
The main Calendar and selected-day sheet prepare dated groups and navigation order
in one calculation, using a calculation-local formatter. Missing/invalid dates,
out-of-month membership, property casing, date prefixes and stable tied ordering
retain the previous interpretation. Nothing caches dates across render/settings
changes. An actual-module differential probe matches groups and order in 75
combinations of time zone, month and property name. A controlled computation probe
shows reduced work on 1,000 mixed notes; it loads the Debug production helper and
copies the original view's grouping/order loops into an optimized harness. It is
not installed/Release frame latency or general responsiveness evidence.

The final-source non-AI suite passes 272 tests with zero failures, including the
Calendar rendering/selection owner and all nine zoom owners. No tests changed.
The signed internal Release remains 0.3.85/build125. Native QA on 307 owned notes
shows all 14 November 15 members through the lazy day sheet, opens Ben in the
editor alone, shows only the December-dated Eve after month navigation while
retaining Undated, and returns to November with Today. All original note hashes
match. Broader Gallery/Undated-card scaling, interface performance and full parity
remain open. Evidence: `artifacts/native-macos/calendar279/verification.json`.
No AI/iOS changes, version bump, DMG, commit or publication.

Performance278 rejects a second Gallery layout candidate. A standalone controlled
mixed-height-card probe compares LazyVStack/HStack rows with the current adaptive
LazyVGrid. Rows are slower at all sampled widths before accounting for geometry
acquisition or card-state migration. No production Gallery change is made; this
rules out that candidate, not all possible row-based implementations. Evidence:
`artifacts/native-macos/performance278/verification.json`.

Presentation277 retains the accessibility repair isolated by Access276. Presentation
content now stays in its original SwiftUI graph, with a finite-proposal Layout,
overflow ScrollView and a native window-sizing probe. The separate hosting root
and whole-environment copy are removed. A signed diagnostic verifies real typing
and button activation, inherited custom AppStorage, live 100/150 zoom with retained
text, state-driven growth and nested/parent dismissal. Existing zoom owners retain
focus/caret, native appearance, lazy large-table sizing, resizing, bounded overflow
and anchored calendar behavior. No tests or production testing seams were added.

The final full non-AI run completes 272 tests: 271 pass and one calendar screenshot
check throws Apple's Vision E5 model-loading exception. The unchanged calendar
owner passes on retry. All nine zoom owners pass in that full run, without the
initial prototype's frame-constraint warnings. This is aggregate final-source
coverage with a recorded infrastructure retry, not a clean single full-suite pass.
The optimized internal app is signed and verified at unchanged 0.3.85/build125.

Actual signed Downloads now exposes empty, Canceled and Saved records and Reveal
in Finder through CUA. That action selects the exact owned synthetic download;
its bytes match, and the original Files274 sources/note remain unchanged. Settings
and CLI inspection remain open: new permission retry does not resolve the helper
failure. The candidate's Settings also closes SkyComputerUseService's native pipe.
A standalone comparison isolates the trigger: a picker form is accessible in plain
hosting, but adding a standard SwiftUI ScrollView reproduces the helper's
Array.remove(at:) assertion without any Zerus custom layout. Removing hidden probe
attributes or adding explicit content containment does not fix it. Do not classify
that limitation as accepted Settings/CLI or VoiceOver coverage. No overall latency
or full-parity claim. Evidence: `artifacts/native-macos/presentation277/verification.json`.
No AI/iOS changes, version bump, DMG, commit or publication. Diagnostic is closed.

Access276 isolates the missing controls in the HTML downloads window. A signed
standalone native control uses the exact production zoom/presentation source.
Plain hosting exposes its real field/button and supports typing/activation; both
top-level hosting choices lose the controls when wrapped in the zoom host.
Removing whole-environment forwarding into its separate hosting root restores
accessibility. Visibility/containment, context forwarding, accessibility enablement
and full controller-containment alternatives do not. These candidates were tested
only in the diagnostic, and no product or test source changed.

At the Access276 checkpoint a production repair remained open: removing all
environment forwarding could lose inherited preferences, theme or dismissal.
Presentation277 above now retains that bounded repair and verifies Downloads;
Settings/CLI inspection and VoiceOver coverage remain pending. Evidence: `artifacts/native-macos/access276/verification.json`. No new
build version or DMG. The diagnostic is closed after recording its results.

PDF275 repairs the Files274 expansion reset. Non-HTML document previews now keep
the same layout branch while notes are shown or removed, preserving the existing
reader. Signed native before/after checks use ordinary and encrypted two-page
PDFs. The baseline loses Find and page two, and relocks an unlocked PDF on Expand.
The repaired Release keeps Find text, match index, Match case, page two and the
unlocked document across Expand/Show notes. Manual zoom's horizontal scrolling
also remains; numeric zoom scale was not measured. Switching documents starts a
fresh independent reader and explicit Reload resets Find/page as intended.
All four original note/PDF files remain byte-identical, including encrypted bytes.

The final matching-source non-AI gate passes 272 tests with zero failures. Hosted
regression-test attempts could not activate SwiftUI Expand through native/public
accessibility interfaces; these are rejected harness failures, not defect evidence.
The test file was restored exactly and no production testing seam was added.
The existing reader tests plus actual native baseline/after evidence support this
bounded repair. Divider-position persistence, broader file/VoiceOver/performance
acceptance and the other Files274 observations remain open. Evidence:
`artifacts/native-macos/pdf275/verification.json`. No DMG/version bump or iOS change.

Files274 verifies signed Release document import and preview workflows on an owned
local fixture. HTML Copy into vault preserves exact bytes; Safe leaves scripts
unexecuted, Full runs the local script, and the choice survives an app restart.
A canceled native download Save dialog leaves no file or staging entry. Saving
to the owned Downloads folder produces exact expected bytes and a visible Saved
record. PDF import preserves original/copy bytes; text search reports 1 of 1,
zoom/fit and expansion work, and notes saved beside the PDF survive close/reopen.
Every original fixture file remains unchanged. No product/test code changed.

Follow-ups discovered: Expand/Show notes resets the PDF Find query; PDF275
above repairs this. The downloads window visually renders records, but CUA exposes
only window controls, so accessibility remains unverified. A Go to Folder sheet
stopped responding to confirmation/Escape; after restarting only the QA app,
folder-menu/list selection imported the PDF successfully. No cause is assigned.
This is local/single-page acceptance, not encrypted/multipage/provider/drag or
full-file parity. Evidence: `artifacts/native-macos/files274/verification.json`.
No new test run, version bump or DMG.

Performance273 removes repeated task sorting in the Mac Tasks view and prepares
shared query timestamp keys once per task using local date formatters. Rows,
empty state and totals share one query result; list counters use one pass over
all pending tasks. The existing sort/filter semantics match the previous query
in 144 differential combinations, including ties and invalid/fractional/offset
dates. Final matching-source gates pass 272 non-AI Mac tests and five iOS task
planning tests. No tests were added or changed for this behavior-preserving work.

Signed Release native QA uses the same 120-task fixture as the preserved baseline:
General is 24 pending/6 completed, All lists 96/24, alphabetical sort and search
match expectations. Complete/Reopen persists only the chosen task and retains
foreign fields. Original files were restored exactly after closing; relaunch
shows General 24/6 and Drafts (0). The shared iOS code was built/installed on an
isolated simulator, with All/Today/Completed search checked and a visible Device
panel preview left open. Its fixture file stayed unchanged. Standalone query
cost measurements support removing formatter/comparator work, not an overall
input-to-frame or all-interface speed claim. Evidence:
`artifacts/native-macos/performance273/verification.json`. No DMG/version bump.

Popover272 fixes the calendar/filter presentation failure isolated by task270.
A plain SwiftUI control works; the custom host fails while directly resizing
AppKit's anchored popover window. The shared production popover wrapper now keeps
interface zoom but leaves window sizing to AppKit; sheets/panels retain their
existing sizing policy. The regression fails on the equivalent pre-fix host with
an NSPopover constraint-pass exception and passes at 100%/150% zoom. The final
matching-source non-AI gate passes 272 tests with zero failures and no publishing
warnings. Signed Release native QA selects Due 22/11/2026 without closing the task
sheet, and a nested date-filter calendar shows only Alpha on that date. Reset
restores all three notes. Private draft ISO values match; only that synthetic
draft was reversibly archived, and original fixture files were restored exactly.
A fresh permissions retry reads the app and Settings, but CLI settings still
closes the Computer Use helper's native pipe. Evidence:
`artifacts/native-macos/popover272/verification.json`. No DMG/version bump.

Task270 verifies current signed Release required Scheduled clearing (visible
validation and disabled Save), Escape rollback without closing the task sheet,
optional Due clearing without unmounting, Return completion without a vault save,
and private draft recovery. The recovered/archived task retains Scheduled
2026-11-21 and Due 2026-11-29 in ISO form. No vault tasks file was created and all
original fixture files stayed unchanged. Only the synthetic private draft was
reversibly archived after closing the QA app; relaunch shows Drafts (0), no tasks.
The original calendar activation failure is superseded by popover272 above. Evidence:
`artifacts/native-macos/task270/verification.json`. No production source change.

Drag269 adds controlled delivery evidence without changing the board. Ordinary
note-text drag selection works, and an initial direct AppKit diagnostic drag
completed with visible success and destination/end callbacks. Typed, plain String
and provider SwiftUI control targets did not reliably receive drops, and later
AppKit controls also failed to complete reliably. One expanded diagnostic run was
invalidated by its own synchronous file logger blocking at __open; the corrected
run uses unified logging. No custom-type or board-scope defect is established.
Current pointer transfer acceptance remains open; verified menu actions do not
substitute for it. Evidence: `artifacts/native-macos/drag269/verification.json`.
The disposable diagnostic is closed, and original board files are unchanged.

Acceptance268 verifies current signed Release multi-card Command selection and
Move-to-column review through the native card menu. The review lists exactly the
two chosen notes and writes nothing before Apply. Only their Status scalars
change; bodies, the unselected note, schema and unrelated settings stay intact.
Organization history Undo restores Draft values and Redo restores applied files.
The inverse property edit quotes Draft, so this is value restoration, not original
spelling restoration for the edited scalar. Column chevrons persist order across
collection reopen and retain foreign settings. All original fixture files were
restored byte-for-byte after closing the QA app; relaunch shows the original board.
Two multi-card, one single-card and one column-header CUA drag attempts produced
no board/review/disk change, despite working coordinate clicks. Tool delivery versus
app handling remains undiagnosed; current pointer dragging is not signed off.
Evidence: `artifacts/native-macos/acceptance268/verification.json`. No source change.

Performance267 compares adaptive and explicit fixed grid columns in a standalone
offscreen SwiftUI harness with mixed cover placeholders and properties. Explicit
widths do not improve synchronous initial layout in that approximation, even with
geometry acquisition excluded. No grid rewrite was integrated. This rules out the
proposed shortcut, not end-to-end performance acceptance. Evidence:
`artifacts/native-macos/performance267/verification.json`.

Performance266 tested and rejected an empty-cover state optimization. The candidate
passed all 271 non-AI tests, built and signed successfully, and preserved the
Gallery layout and all 1,000 synthetic note files. A matched folder-switch SwiftUI
capture showed little change in cover body evaluations and inconsistent layout
cost shifts; it did not establish a robust useful speed benefit. Production source
and the prior signed Release QA app were restored byte-for-byte. No improvement
is claimed. Next: isolate lazy-grid measurement/placement itself, including image
and property cards, then continue the remaining workflow acceptance. Evidence:
`artifacts/native-macos/performance266/verification.json`. No DMG/version bump.

Performance265 records current signed Release note switching and Gallery/folder
transitions on a fresh owned 1,000-note vault. All selected editors appeared;
Gallery retained exclusive collection layout and restored its remembered mode
after a folder switch. Every note file remains byte-identical. Time Profiler
captures include significant Computer Use accessibility inspection cost, so raw
totals are not user-latency measurements. Heuristically filtered stacks identify
SwiftUI transaction/view-graph and layout work as the next investigation; note
parsing/frontmatter is a smaller sampled contributor in these scenarios. No
performance improvement is claimed and no cache redesign is justified by these
captures. A separate completed SwiftUI trace identifies child geometry and lazy
grid/stack placement as the largest individual update descriptions; collection
body evaluation is smaller. Its standalone layout table is empty, so the analysis
uses the populated updates table. Next: isolate lazy-grid measurement/placement
while preserving viewport loading and selection/order semantics. Evidence:
`artifacts/native-macos/performance265/verification.json`. No source change or DMG.

Undo264 fixes the first-character Undo boundary when filling a canonical empty
list head whose existing native metadata already exports the same complete item
graph. On the signed Release app, typing Parent into the same compact263 outer
row now saves exact expanded bytes; one Undo restores the original compact note,
one Redo restores the entire word, and a final Undo restores the original again.
Both owned fixture notes are byte-identical to their originals. The non-AI gate
passes 271 tests with zero failures. Experimental XCTest typing variants masked
the installed bug and were removed; before/after native QA and an actual-module
standalone diagnostic provide the regression evidence. Evidence:
`artifacts/native-macos/undo264/verification.json`. No DMG/version bump.

Compact263 gives shared-line compact paragraph lists separate native item rows,
including quoted, numbered, deeper chains and ordinary `- - Child` forms. Original
compact bytes survive body edits; outer content and empty-chain transitions retain
ownership through expanded Markdown. The final matching-source non-AI gate passes
271 tests with zero failures. Signed Release/native QA checks exact accent and outer
row saves, independent parser ownership after clearing a three-marker chain, Undo,
and reopening, with both owned fixture notes restored. Native word typing into the
outer row created two Undo groups at its first-character transition;
undo264 above supersedes that observation. Compact non-paragraph and mixed quoted-list/card forms,
broader input/clipboard/performance/full parity remain open. Evidence:
`artifacts/native-macos/compact263/verification.json`. No new DMG/version bump.

Admission262 enables mapped plain lists inside item-owned quotes in rich mode,
with exact export and parser/native parent checks. Compact shared-line heads and
mixed quoted-list/card shapes retain Source. The workspace owner actually edits,
saves and reopens the new shapes; the baseline fails four assertions and the
matching-source non-AI gate passes 270 tests with zero failures. The signed
Release QA app verifies Portuguese child composition, grandchild outdent, Undo
and rich reopening, with both synthetic notes restored to original bytes.
Evidence: `artifacts/native-macos/admission262/verification.json`. Version/build
remain 0.3.85/125; no DMG was made. Full parity and broader performance/input
acceptance remain open.

Containers260 repairs standalone clipboard promotion of a list inside an
item-owned quote. Omitted outer list widths are removed before quote markers
and from continuation separators; selected owners retain their widths. The final
baseline fails twenty assertions across two clipboard owners. The matching-hash
non-AI gate passes 270 tests with zero failures, with the same thirteen AI/chat
classes deferred. Public nested admission remains guarded, and the installed
Release app predates this repair. See
`artifacts/native-macos/containers260/verification.json`. No new DMG/version bump.

Acceptance259 verifies the current Release app through native Computer Use on an
owned synthetic vault. Portuguese acute composition across list items keeps
marked input out of the saved file, Escape restores text and selection, immediate
retry commits é, and one Undo restores every original byte. Heading ã and prose é
also save exactly and undo to the original. The heading dead-key Escape behavior
matches a native TextEdit control; it is not classified as a Zerus defect.
The folder sidebar hides entirely and restores. Gallery shows only the collection;
opening a card shows only the note, and Browse notes returns to Gallery without
the editor. The current permission retry still crashes SkyComputerUseService when
opening CLI settings; Zerus stays running and no setup action executes. Evidence:
`artifacts/native-macos/acceptance259/observations.json`. These bounded checks do
not establish all-IME, dictation, accessibility or full parity acceptance. No
production source change, new build, DMG or version bump.

Startup248 uses directory stat metadata for startup identity instead of the
full Foundation attribute lookup, avoiding unnecessary extended-attribute reads.
Three existing startup/navigation owners pass. Signed Debug QA verifies inactive
pinned-tab moves and Back navigation with unchanged note bytes. The owned
Documents fixture opens through the normal picker and restores after relaunch;
the earlier environment-only launch lacked the picker folder grant. This is
functional evidence, not general latency or full acceptance. Signed Release QA
also starts the temporary vault and opens the moved pinned tab correctly. See
`artifacts/native-macos/startup248/verification.json`. No new DMG/version bump.

Performance258 builds and strictly verifies the current signed Release QA app,
including performance254/256/navigation257, with version/build unchanged.
Installed main-window QA types twelve heading characters in a synthetic
2,000-paragraph note. Both the prior CLI251 Release and current Release save
identical edited bytes; single Undo restores each original byte. Separate fresh
fixtures start with identical note bytes and no history. Time Profiler captures
show reduced sampled main-thread work in the current build, chiefly avoiding
repeated full export. There is one twenty-second capture per binary; pacing,
cache warmth and runtime state can differ. This is not measured input-to-frame
latency or all-interface responsiveness acceptance. No hang-risk rows were
recorded in either bounded capture; no broad no-hang claim is made.

Latest installed QA receipt: `artifacts/native-macos/performance258/candidate-app-receipt.json`.
Trace, byte/Undo evidence, limitations and verified owned-preference cleanup:
`artifacts/native-macos/performance258/verification.json`. Owned recent/bookmark
keys were removed; unrelated preferences remain unchanged. Fixtures and traces
are retained. No new DMG/version bump.

Screenshot-first inspection of the CLI tools sheet also crashes the native
helper. App access recovers after restarting only the owned QA app; main-window
QA works. CLI metadata apply/registration acceptance remains pending, with no
registration action executed.

Navigation257 fixes the retained List scroll offset after vault reactivation by
requesting an explicit ScrollPosition top edge instead of a zero-height lazy
item anchor. The unchanged owner passes after failing twice on the baseline;
the combined current non-AI gate passes all 270 tests with zero failures. This
supersedes performance256's failed gate and includes performance254/256.
Native QA inventory works, and app access recovers after restarting only the
disposable QA app. Opening the CLI tools sheet then reproducibly crashes
SkyComputerUseService (Array.remove assertion), while Zerus stays running.
No metadata/registration actions ran; fixture note bytes are unchanged.
Installed validation remains pending; no new DMG/version bump. Evidence:
`artifacts/native-macos/navigation257/verification.json`.

Performance256 extends local rich export to stable standalone ATX headings.
Full-export equivalence passes 108 heading fixtures and contextual fallback
controls; all existing editor owners pass. A development diagnostic caught a
block-role conversion separator mismatch, fixed by retaining the exported block
identity and falling back when it changes. The current broad gate is unpassed:
the List viewport remains at its old offset after same-vault reactivation. This
fails in both the broad run and isolated owner, with its assertion unchanged.
Next is that scroll-reset repair and a fresh combined gate. Public rich admission
is unchanged. Installed verification is pending the native CUA connection; the
CLI251 installed app predates performance254/256. No new DMG/version bump.
Evidence: `artifacts/native-macos/performance256/verification.json`.

Performance254 caches immutable note header/body strings lazily alongside parsed
frontmatter in the existing macOS cache, avoiding repeated full-body substring
construction for title/editor reads. Exact byte keys and cache limits remain;
the selected non-Mac implementation is unchanged. Byte-equivalence and concurrent
read diagnostics pass, followed by all 270 current non-AI tests with zero failures.
Release scratch measurements are diagnostic only; installed responsiveness is
still unverified. Native Computer Use continues returning a closed-pipe error
after the user's permission update and a fresh reset. The installed CLI251 QA app
predates this change; no new DMG/version bump. Evidence:
`artifacts/native-macos/performance254/verification.json`.

CLI251 repairs CLI metadata transactions with connected-file recovery guards.
App-private dependencies are coordinated separately from confined vault reads;
absent or clean records remain unchanged, while dirty/unreadable records block
metadata writes. The new owner fails on the old source. All seven CLI owners
pass, followed by the current 270-test non-AI gate with zero failures and the
same 13 AI/chat classes deferred. This supersedes acceptance249's failed gate.
Release compilation and strict app/CLI signature verification pass. The app
opens the synthetic vault, but native Computer Use disconnects while opening
CLI settings; reconnect and kernel reset return the same closed-pipe error.
Fixture note bytes remain unchanged; no metadata or registration action ran.
Installed CLI acceptance and broader parity/performance remain open.
See `artifacts/native-macos/cli251/verification.json`. No DMG or version bump.

Acceptance249 reruns the current non-AI suite with the same 13 AI/chat classes
deferred: 269 tests execute, with three CLI-setup tests failing (five assertions/
errors, two unexpected). The isolated six-test CLI class reproduces those same
failures. Missing properties-pane files and unexpected outside-vault refusals
remain under investigation; no checks or exclusions were weakened. The earlier
OCR failures and task-draft cleanup errors did not repeat. Earlier descriptions
attributing all five performance243 errors to OCR were inaccurate: two were
OCR/Vision transitions and three were task-draft cleanup errors. This current
run remains unpassed. See `artifacts/native-macos/acceptance249/verification.json`.

Performance246 aggregates ordinary-note counts for every folder ancestor once
per inventory revision. The actual API matches 56 old-prefix count controls
and invalidates on append/removal; three existing navigation/folder owners pass.
Installed checks show counts changing after native creation and a byte-preserving
outside move. Two folder-switch captures retain substantial layout cost and do
not establish click-to-frame latency. Tab/cache state differs from the baseline,
so no general speedup is claimed. The latest installed receipt and evidence are
`artifacts/native-macos/performance246/app-receipt.json` and
`artifacts/native-macos/performance246/verification.json`.

**Navigation247 repair:** inactive tabs now follow unique before/after note
identity, including source-path reuse and atomic swaps. Four focused owners pass,
covering pins/history and retained-draft conflicts. The Release build and strict
installed signature check pass; installed interaction acceptance remains pending.
A fresh synthetic-vault launch stalled in Foundation extended-attribute lookup
inside startup identity loading. Evidence is in
`artifacts/native-macos/navigation247/verification.json`. The prior temporary QA
vaults no longer exist after the restart; no new byte comparison is claimed.
No version bump or DMG was made.

The first test build ran out of disk space. Older immutable internal QA app
snapshots were losslessly archived only after every file byte was verified. A
representative restore matches bytes/modes and passes strict nested signature
verification. Current apps, DMGs, all result bundles and OS caches remain intact;
see `artifacts/native-macos/archived-qa-apps/README.md` for restoration. The same
frozen source then built successfully and passed its focused owners. This does
not establish a Vision/E5 repair or a passing combined gate.

Performance245 skips the source-link inventory when no literal `[[` opener can
produce a wiki edit. Full preview/search text is retained, including long-note
content; notes containing the opener retain their existing parser path. The
selected non-Mac file is byte-identical to the baseline. Ninety-six diagnostic
cases match, the existing search integration owner passes, and installed saves
and single Undo match the baseline byte for byte in both candidate captures.
The CPU profiles show less preview-processing work, but key pacing and cache
warmth differ; key handling in the first candidate capture is unchanged. This
is not a general typing or frame-latency claim. Its historical installed receipt is
`artifacts/native-macos/performance245/app-receipt.json`; evidence and limits are
in `artifacts/native-macos/performance245/verification.json`. No new DMG or
version bump was made. The combined suite was not rerun for this equivalent
optimization; the latest combined result below remains unpassed.

The archive owner passes and installed recovery preserves pins, the active note,
collection query/view and inspector state. Missing inactive temporary-vault
navigation was archived byte for byte, while bookmarks and current preferences
were retained. The preferences domain is now below 4 MiB. The offline operation,
conflict handling and restore path are documented in
`native-macos-navigation-archive.md`; exact evidence is in
`artifacts/native-macos/performance241/verification.json`.

Performance243 retains an equivalent literal UTF-16 CRLF search in the macOS
frontmatter parser, avoiding a Swift character walk through large headerless
bodies. Forty-five diagnostic equivalence cases match the baseline. The selected
non-macOS implementation remains byte-identical to the baseline. Installed typing
on an owned 4,000-paragraph note produces the same saved bytes as before, and one
Undo restores every original byte in both candidate captures. These bounded CPU
profiles do not establish general UI speed or input-to-frame latency; key pacing
and cache warmth differ.

The latest combined scoped non-AI run (performance243) executed 269 tests with five unexpected
errors, preceded by Vision/E5 missing-model diagnostics. All 13 focused parser,
workspace, editor and CLI setup owners passed. The full gate remains unpassed;
earlier passing runs are historical evidence. All 13 AI/chat classes remain
deferred. No assertion or exclusion was weakened and no CPU/model-cache
workaround was retained. The exact installed app receipt and evidence are in
`artifacts/native-macos/performance243/frontmatter-app-receipt.json` and
`artifacts/native-macos/performance243/verification.json`. No version bump or
DMG was made. External-note/move fixture cleanup was subsequently repaired in fixture244.
The remaining five-owner run passes, the earlier move suite passes, and exact
preference comparison finds no external-fixture leaks. The combined focused
attempt was interrupted during XCTest warning symbolication in image paste;
that owner is not counted as passed. The original preference domain was restored
exactly. See `artifacts/native-macos/fixture244/verification.json`.

Performance242 profiles eight installed Inbox/Planning folder switches. A
smaller initial List page, alone or with viewport-based loading, did not show a
convincing benefit and both candidates were reverted to the exact retained
source/app. A SwiftUI trace points to graph/layout, callbacks and repeated row
updates as larger costs. Critical disk pressure was also found; only
regenerable repository build caches were removed. Vaults, app products,
archives, release artifacts, logs and OS model caches were preserved. These
facts do not establish input-to-frame latency or a permanent Vision repair.
Evidence is in `artifacts/native-macos/performance242/verification.json`.

AI chat and agents are deferred at the user's request. This audit supplements the
full tracker in `native-macos.md`; it does not mark that tracker complete.

Preview121’s combined source passed the 260-test scoped desktop gate before its
version/documentation-only bump; all 13 AI/chat classes were deferred. The earlier
AI-inclusive attempt is not a passing full-suite result. The DMG's mounted app, signature,
version, bundled guide and full private HTTPS download were verified. Those facts
prove the recorded test and artifact contracts, not complete installed parity.

## 1. Rich-editor parity

Supported item-owned headings and prose quotes now open in rich mode, including
supported code/table combinations. The workspace owner is now
`MacWorkspaceTests.testOpeningContainerParagraphsChoosesRichOnlyForEditableNativeStructure`.
It verifies actual hosted editing, saving and reopening. The last passing combined
non-AI gate reports 280 tests with the 13 AI/chat classes excluded (navigation349).
Render355 runs all 280 configured checks successfully across fresh processes;
the monolithic Vision/E5 limitation is recorded above.

Internal installed QA also verifies Portuguese dead-key commit and Escape
rollback across list items, immediate retry, nested code-sheet editing, and saved
heading/table reopen. The installed app's signature and bundled CLI were checked;
see `artifacts/native-macos/containers191-review/installed-results.json`.

**Current scope:** mixed281 and compact286 admit mapped quoted-list/card
combinations and compact heading heads; outline287 repairs their nested heading
enumeration and caret targets. Prose321 admits root paragraphs/headings with
two- or three-space layout indentation. Lists325 admits checked tabbed-prefix
lists while preserving untouched source tokens. Mixed327 additionally admits
checked combinations with unchanged code/table cards. Compact328 adds mapped
shared-line tabbed heads. Tasks331/332 additionally admit the tested compact
checkbox chains, accepting exact quoted trees before applying the missing-checkbox
adapter. Other unmapped checkbox/container shapes still use Source mode.
Unmapped container shapes, uncommon structural/
clipboard cases, keyboard/input, accessibility and broader performance/installed
acceptance remain open. Earlier plain quoted-list/shared-line restrictions have
been superseded by the later admission batches.
This is current internal-source evidence, not a new DMG or full parity claim.
The following progress notes are historical.

Guarded progress: containers160–166 now provide representation, canonical import,
nonempty/selected Return, and checked Backspace/empty-block lifecycle behavior.
Preview 116 contains these repairs. The final 385-test Mac suite passed with zero
failures; the public item-owned heading/quote Source guard remains closed.
Details and remaining commands are in `native-macos-item-containers.md`.

Containers165 adds 77 native nonempty Backspace workflows and 17 actual registered
web command controls. Containers166 adds 52 hosted empty-block workflows,
including keyboard EOF body clears and quote/empty-heading boundaries. Exact
baseline, owner and full results are in their verification records; the mounted
app, guide, signature and full private download are in preview116-handoff.json.
Root nonempty quote keys, deeper quote/list/card boundaries and broader
clipboard/structural replacement remain open. Preview 117 includes containers168 repairs
whole final-body Cut with 54 workflows, preserves explicit paragraphs on reopen,
and hardens EOF paragraph-token reuse/caret roles. Its exact baseline, focused checks and final 385-test pass
are recorded in containers168-verification.json. These changes shipped in Preview 117. The five-case
containers167 DOM/tree reference confirms that copying the web's lossy quote
export would flatten block roles. Preview 117 native leading-quote removal now
retains those roles, guarded by parser structure and byte-exact native export.
Its 61 positive workflows and existing Cut owner pass; the final full suite passes 385 tests with zero failures.
Preview 118 includes containers169 quote text merging into preceding text blocks,
with 87 hosted workflows and 21 actual web key/typing controls, including empty predecessors. Its final focused
owner passes and its exact Preview 117 baseline fails as expected; the final full
suite passes 385 tests with zero failures. Empty/deeper/card-first boundaries remain open.

Other uncommon rich/container, ordinal, shortcut and clipboard items in the main
tracker remain unverified. Reproduce them against the current web implementation
before calling them missing features or changing behavior.

## 2. Installed native interaction and design

**Fresh permission granted and installed QA performed:** Preview120 was installed
from the verified DMG and tested on disposable copies of the synthetic QA vault.
The original 52-file fixture remains byte-for-byte unchanged. The results and
limits are recorded in `artifacts/native-macos/acceptance120/results.json`.

Observed passes: sidebar hide/restore; Portuguese acute composition in prose,
selected item text and cross-item selections with Undo; table editing/Tab/save;
list indent/outdent; actual Kanban pointer drop and reviewed history Undo;
second-window save/close and reactivation; app reopen; native code-sheet save;
and the ordinary Open Vault folder picker. These are bounded installed checks,
not full workflow, design or IME acceptance.

Two unresolved observations remain: an environment-variable startup stalled on
the workspace-path copy, while the temporary control and normal folder-picker
open succeeded; and Computer Use lost the main window after the macOS Edit
menu, recovering after clean app quit/relaunch. No new crash report appeared.
Do not infer a cause or general acceptance from the successful controls.

Recent installed checks also verify collection-only Gallery, note-only card
opening and return, and full folders hide/restore (performance227). Actual
TextEdit/native rich Copy/Paste in both directions now preserves ordinary
paragraphs, bold, italic, link, Portuguese text and a natural-size embedded
image, including saved/reopened content and exact-pixel image checks
(acceptance229). Paste and Match Style now has its standard Edit-menu action
and Command–Option–Shift–V shortcut; both save exact plain text and undo as one
edit (acceptance230). These bounded workflows do not close all clipboard,
resizing, accessibility or input acceptance.

Remaining installed coverage includes broader approved light-layout, sidebar,
hide/restore, compact drawers, resizing and zoom; editor and table/code keyboard
workflows; Portuguese accents, dead keys, marked composition and dictation;
real clipboard flavors and cross-app paste; image and Kanban pointer dragging;
window close/reopen and multiwindow edits; VoiceOver and focus order; file preview
and download save dialogs. Use a copied test vault and keep original user data
intact.

Current offscreen evidence includes the real calendar rendering and modifier/key
transport owner. Its exported Preview 114 images show selected properties on both
dated and undated cards without clipping in the fixture. The export manifest is
`artifacts/native-macos/acceptance159-calendar/manifest.json`. This does not prove
all calendar sizes, installed pointer routing or accessibility acceptance.

## 3. Performance and cross-client compatibility

**Partially verified:** later source includes the scoped typing, collection and
loading improvements recorded through render355 above. Performance333 adds
a shared Gallery pointer surface; performance334 isolates long-note first-edit
export setup; performance335 removes repeated prefix/set allocations. Remaining full first-edit cache builds for complex/ineligible rows and broader
responsiveness remain open; performance354 avoids that build for eligible fresh
root prose. Native captures and
helper probes identify bounded avoided work, not general input-to-frame acceptance.
Cold startup, broader large-note/vault interactions and provider conditions remain
open. The following Preview114 evidence is historical: it removes repeated
admission parsing. The
Release diagnostic uses three samples on twelve fixtures; its exact data and
scope are in `perf158-measurements.json`. It does not measure full displayed
editor load or installed typing latency. List-owned-card admission remains a
separate expensive path. Cold displayed load, large-note editing and large-vault
inventory cost still need measurement and acceptance.

Existing owner tests cover BOM/line-ending fidelity, source reuse, schemas and
relations, shared tasks/views, history, drafts and guarded external-file edits.
Full cross-client acceptance still needs copied-vault write/reopen cycles through
native Mac, the existing desktop/web implementation and applicable iOS services,
including sync/provider interruption and folder/reference changes. Simulator or
physical-device checks remain separate from compilation.

Installed typing attribution and bounded export reuse are now recorded through
performance228. Those single-run CPU profiles identify reduced work in specific
large-note typing paths; they do not measure general input-to-frame latency.
The TextEdit round trip above adds one cross-app clipboard check. The disposable
native/CLI cycle in compatibility231 additionally verifies note identity,
metadata, BOM/CRLF preservation, external-change adoption, revision refusal and
relative-link repair through a move. Web/iOS and provider-sync compatibility
cycles remain open.

Legacy private pin/archive migration already has a reviewed React/Tauri flow
(migration104). The isolated migration360 app now verifies the actual reviewed
pin/archive GUI/IPC flow, cancellation, stale review, repeat no-op and native
readback on an owned vault. Existing shared explicit false values win. Full
legacy fidelity stays open because normal companion startup assigned IDs,
renamed files and normalized frontmatter before review; missing-ID insertion
through the reviewed command was not exercised. This is not an absent native
importer to duplicate. No automatic reading of another app's private state or
mutation of a real vault is authorized by this audit. Provider319 verifies owned iCloud save,
bookmark reopening and materialization after eviction on this Mac. Independent
cross-device sync and interruption acceptance remain open.

## 4. Release readiness

**Latest packaged artifact:** Preview125 is an ad-hoc signed, non-notarized
arm64 test DMG for macOS 26+. `preview125-handoff.json` records mounted and
downloaded artifact checks. Later source is being verified through internal
app builds; the user wants a test handoff at the end. Source and package
evidence are not an installed launch/interaction sign-off.

**Pending:** remaining installed workflow/design coverage, Developer ID/notarized
native delivery acceptance, helper notarization, and a native automatic-update
channel. The native app must not consume the existing Tauri updater feed.
Production channel publication and a general Windows/Store release are not
inferred from the native preview goal. Keep release preparation reviewable and
obtain any needed publication authorization only after concrete artifacts and
configuration are ready.

## Checked behaviors that should not be expanded as supposed gaps

- The whole folder sidebar is intentionally hideable in native Mac, with a
  restore control. Preserve it even though React/Tauri does not offer it.
- Kanban columns have fixed widths in both current implementations. Resizable
  columns are not an existing desktop parity feature; compact column layout
  still needs native acceptance.
- Both current native and web grouping pickers exclude multi-select list
  definitions. The web drag handler's array branch does not establish an
  available picker feature. No Kanban widening was made.
- Native note creation now preserves the browsing collection, falling back to
  All Notes from special hubs, matching the web flow. The earlier folder-jump
  review finding is no longer current.
- Native spreadsheet paste and portable table-row clipboard transport exist;
  do not treat the feature as absent based on the main tracker's short summary.

The next remaining areas include nested quote/list rich admission, broader
clipboard/card cases, installed marked input/accessibility and copied-vault
cross-client cycles. Reproduce suspected gaps against current code and evidence
before treating historical review notes as current defects. Native QA permission
remains granted. The progress notes below are historical.


Unreleased containers170 adds initial inner-block formatting with 151 hosted
workflows. The final exact baseline fails 731 assertions on Preview 118; two
focused owners and all 385 Mac tests pass. Source hashes and limits are in
containers170-verification.json. Compound format/Return probes identify a missing
transient quote-leaf distinction, recorded in containers171-discovery. Rich
admission remains closed; this does not complete formatting or installed parity.


Unreleased containers171 preserves the live quote-leaf distinction through
compound formatting and Return, including empty quotes and outer quote
separators. The focused three owners pass; the exact final tests fail 454
assertions on containers170 source. The final full suite passes all 385 Mac tests with zero failures; frozen source
hashes match containers171-verification.json.
This adds no rich admission, packaged build, AI or iOS change. Remaining
container work includes live-role transitions through deletion, shortcuts,
clipboard/ranges and embedded cards. Installed QA, displayed performance,
cross-client acceptance and production delivery remain pending as above.


Preview 119 packages containers170/171 as 0.3.79/build119. The mounted app
version, signature, bundled guide and full private HTTPS download are verified
in preview119-handoff.json. The source gate remains the exact final 385-test
containers171 run before a version/documentation-only bump. Backspace discovery
uses ten completed web cases in smaller owned WebKit batches; it supports the
existing head-lift/nonempty-navigation policy and does not justify changing it.
No installed launch/IME or full-parity acceptance is inferred.


## Inner block shortcut scope (containers173, unreleased)

Typing checkbox, bullet, heading, quote or rule-looking prefixes inside a
list-owned heading, quote or explicit paragraph preserves that block and its
literal text. The shortcut entry point no longer mistakes an outer list marker
for the inner text role. Ordinary flat-list shortcuts and independent inline
formatting keep their earlier behavior.

The existing shortcut owner adds 175 real-typing workflows with handwritten
source, independent parser roles, caret/font, Undo/Redo, follow-up typing and
reopen. The final test fails 378 assertions on Preview119; four final focused
owners pass. The final full suite passes 385 Mac tests with zero failures and terminal exit 0;
frozen source hashes match containers173-verification.json. Seven built-in references and two actual app
shortcut-component references execute in owned offscreen WebKit fixtures.
These do not establish installed input/IME acceptance.

Preview119 does not contain this repair. Public list-owned heading/quote rich
admission remains closed until the remaining structural, paste/range and card
interactions are accepted. No AI, iOS, version or bundled-guide change was made.


## Standalone inner heading clipboard (containers174, unreleased)

Copying a complete list-owned heading without its item head retains a standalone
heading. Unselected quote/item ancestors do not accompany that single block;
partial heading selections and plain quoted text keep their inline behavior.
Heading copies also offer semantic HTML through the existing bounded export
path when resources or parser warnings do not prevent a complete export.

The existing clipboard owner adds 72 copy selections and 114 native/HTML paste
workflows across nested/quoted headings, three source endings and selection
with/without a terminator. It checks exact fragment Markdown, unchanged source,
selection and Undo history, independent parsed heading levels/text, paste
Undo/Redo, follow-up typing and reopen. The exact final three owners fail 196 assertions
on the previous clipboard implementation; all 29 clipboard tests pass. The final full
suite passes 385 tests with zero failures and terminal exit 0; frozen source
hashes match containers174-verification.json.

Six actual web selected-node/HTML generator references confirm heading versus
inline quote-text behavior. They are owned offscreen fixtures, not installed
cross-app clipboard/IME acceptance. Broader indentation, ranges, structured
paste and card interactions remain open; public rich admission is unchanged.
Preview119 does not contain containers173/174. No AI, iOS, version or bundled
guide changes were made.

Containers174 boundary clarification: first-block and later-body headings are
covered; prefix-only selections remain inline. The first-block web HTML keeps
its list wrapper, whereas native excludes an unselected visible marker under
its existing selection policy. Heading-role preservation is verified; wrapper
byte parity and broader multi-block clipboard completion are not claimed.
The initial full run caught old complete-heading Cut goldens and was stopped;
those expectations and explicit prefix controls are now checked by the final
clipboard gate and a fresh full rerun.

Final containers174 verification: all 29 clipboard tests and the fresh 385-test
Mac suite pass with zero failures. The exact final three owners fail 196
assertions against the previous clipboard implementation. Frozen source hashes
match. The earlier failed/interrupted run remains recorded separately. No new
DMG or public rich-admission change was made.


## Indentation and native typing Undo (containers175, unreleased)

The tested whole-item indentation paths preserve inner heading/quote roles,
children and tails. Typing after a successful indent/outdent now begins its own
Undo event, using the existing formatting-to-typing boundary. Unchanged/refused
commands keep their previous behavior.

The existing owner adds 144 hosted workflows covering first/later blocks,
ordinary/nested/numbered/quoted items, three source endings, caret/selection and
immediate/later typing. Twelve also check live quote Return after moving and
Undo/Redo. The exact final test fails 432 assertions before the repair and passes
after it. The broader document/clipboard/workspace gate passes 168 tests with zero failures
and terminal exit 0; frozen source hashes match containers175-verification.json. The previous 385-test pass
applies to containers174 before this one-line change.

Eight registered web commands expose transient inner-block indentation rather
than a persisted changed item parent. Native retains its established whole-item
move policy, verified against saved Markdown ownership. No byte/live-tree parity
or complete indentation acceptance is claimed. Public rich admission and
Preview119 are unchanged. AI remains deferred; no iOS/version/bundled-guide
change was made. Other structured/clipboard/card and installed acceptance work
remains open.


## Mixed heading/list clipboard selection (containers176, unreleased)

A complete copied heading body retains its standalone role when selected child
items are promoted around an unselected visible marker. Partial-heading text
stays inline; selected whole items keep their list wrapper. Semantic HTML export
now detects headings through live item text roles as well as root block markers,
using the existing complete/bounded export gate.

The existing owner adds 36 copy selections, 36 native and 27 HTML paste workflows
covering nested descendants, trailing text, ordered starts and heading children
across three source endings. Exact handwritten fragments and independent parsed
parents/heading levels/list starts/text guard the result, with unchanged copied
notes, paste Undo/Redo, follow-up typing and reopen. The unchanged final test
fails 75 assertions on the pre-repair source; three focused owners pass. The
broader editor/clipboard/workspace gate passes 168 tests with zero failures and
terminal exit 0; frozen source hashes match containers176-verification.json.

Four actual web clipboard-generator references keep the heading but omit
intervening selected child lists. They establish heading-role behavior, not
child-content or byte parity. Native keeps all selected children under its
existing visible-marker selection policy. No installed clipboard/IME, public
rich admission or full-parity acceptance is inferred. Mixed structural Cut and
other quote/range/card interactions remain open. Preview119 and its bundled
guide are unchanged; AI remains deferred and no iOS/version change was made.


## Preview120 packaging and installed QA update

Preview120 packages containers173–176, following a combined 385-test pass with
zero failures. Mounted version/signature/guide and complete private-download
hash checks passed. Earlier “unreleased” sections describe their state when
authored; these four changes are now in the delivered DMG. Public rich admission
remains closed. Installed ordinary-editor evidence above does not remove that
guard or establish the outstanding container, clipboard/card, IME, performance,
cross-client or production-delivery contracts. AI remains deferred.


## Mixed inner-block Cut and clipboard policy (containers177, unreleased)

Twenty-four hosted Cut workflows cover first/later headings with selected child
items, nested/numbered owners, complete/partial starts and LF/CRLF/CR. The
retained heading and item parentage, caret, Cut Undo/Redo, refill and reopen are
checked at the existing clipboard owner. The old source fails three clipboard
assertions: a two-character offset into a continuation heading accidentally
matched its owner's visible list-marker width and was treated as a complete
heading. The repair measures the current paragraph's actual display prefix.
The exact final owner and all 29 clipboard tests pass with zero failures and
terminal exit 0 after that one-line repair.

Fresh current-web selected-node probes retain heading HTML even for a partial
single-block heading selection and omit intervening selected child lists in
these shapes. Native currently keeps its established inline partial-text policy
and selected content. Those differences are recorded, not called full clipboard
parity; broader role-policy reconciliation remains open. This repair adds no
public rich admission, installed clipboard/IME acceptance, iOS or AI work.
Preview120 does not contain it. Exact evidence: containers177-verification.json.


## Cross-role text selection (containers178)

The existing rich engine preserves the starting block when a text selection
crosses an item-owned heading, quote or paragraph: surviving suffix text joins
that heading or quote, and following typing retains the same role. Six current
web registered-command controls confirm this starting-role behavior, including
later body headings/quotes. Their normalized marker, blank-line and trailing
empty-paragraph spelling is not asserted as native byte parity.

The existing selection-replacement owner now covers 36 guarded-core workflows
across six shapes, empty/nonempty replacement and LF/CRLF/CR. It checks exact
saved text, independent item parents and heading/quote roles, native typography,
caret, Undo/Redo, reopen stability and subsequent typing. The engine already
passed these editing checks, so no production repair was needed. An initial
admission-only assertion failure is recorded separately, not called a product
regression. The final selection, Return and actual workspace-admission owners
pass three tests with zero failures and terminal exit 0.

Public rich admission is unchanged. Structured paste, selections across item
boundaries/cards, quote-leaf lifecycle and installed marked-input acceptance
still need proof before the remaining Source guard can be removed. This is
regression evidence, not full admission/parity or a new packaged app. Exact
source hashes and logs are in containers178-verification.json. AI stays deferred.


## Structured inner-block paste and vault identity (containers179 / identity180)

The structured paste owner now covers 192 workflows for first/later item-owned
headings and quotes. Paragraph, list, mixed and explicitly bold payloads join
the receiving text container while its child list keeps its parent. Caret and
body replacement, native/HTML transports and LF/CRLF/CR are covered. The exact
final test fails 960 assertions on the old source. Registered current-web paste
commands agree on the receiving roles and child ownership for sixteen matching
cases; root controls confirm that ordinary paragraphs/flat lists still split.
The native repair shares an inline-body insertion path across paragraph and
structured-block paste. Cards keep their independent structural paths.

A broader run exposed a shared vault-identity query stalled in Foundation's
extended-attribute read during CLI setup. Device/inode lookup now uses POSIX
metadata directly, retaining canonical-path identity and missing-path refusal.
The same CLI readiness owner subsequently completed in 1.365 seconds; all 29
clipboard tests passed with it. This is observed-case recovery, not a claim that
all filesystem/provider stalls or the earlier installed startup observation are
resolved. No AI feature implementation or acceptance was performed.

The attempted all-tests run timed out in deferred AI external-draft capture,
and its interrupted log is retained. The final scoped desktop gate excludes
all thirteen AI/chat classes and passes 260 tests with zero failures and terminal
exit 0. Frozen source hashes match identity180-verification.json and
containers179-verification.json. This is not a passing all-AI-inclusive suite.

These changes are not in Preview120. Public rich admission remains guarded,
and arbitrary multi-item/card boundaries, broader quoted/empty payloads,
installed clipboard/IME, displayed performance, cross-client acceptance and
production delivery remain open.


## Preview121 handoff and installed smoke

Preview121 (0.3.81/build121) packages containers177–179 and identity180 after
the 260-test scoped desktop gate passed. Its mounted version/signature/bundled
guide, 335 recorded source/build inputs and complete private download were
verified. The exact DMG executable was installed in a separate QA copy.
Launch, Portuguese acute composition, save, note navigation, whole-sidebar
hide/restore and native quit/reopen passed on a fresh two-note disposable vault.
The other note remained byte-identical; no original user vault was edited.
See preview121-handoff.json and acceptance121/results.json.

The wide-window screenshots also show top collection/tab/inspector content
partly obscured beneath the title bar, including after reopen. This is a concrete
layout observation to investigate next; the smoke pass is not design acceptance.
The build remains ad-hoc/non-notarized, and public rich-container admission,
broader IME/clipboard/card checks, performance, cross-client and production
delivery acceptance remain open. AI stays deferred.


## Native toolbar boundary and Preview122 (layout181)

Installed Preview121 exposed four clipped pane headers beneath the native
title/toolbar. The shared zoom canvas now places a divider before its content,
keeping split views in the usable native content area. The final owner uses
real NSWindow/toolbar and workspace split panes; it checks header and footer
positions across 100/80/150/100 percent zoom without accepting a large top gap.
It fails sixteen header-bound checks on the exact original canvas. All 261
scoped desktop tests pass after the repair, excluding thirteen AI/chat classes.
The native split/editor subtree itself stays unchanged.

Separate Debug QA verified note headers, full folder-sidebar hide/restore,
Tasks, External Notes, narrowing the note window, native window zoom and
quit/reopen. Both synthetic notes remained byte-identical. Preview122 then
passed packaging, mounted version/signature/guide checks, source/build input
fingerprints and a full private download checksum. The exact mounted DMG
executable was installed separately and passed launch, visible pane headers,
complete sidebar collapse/restore and clean quit/reopen. It remains open on a
synthetic vault for inspection. See layout181-verification.json,
preview122-handoff.json, acceptance181/results.json and acceptance122/results.json.

Preview122 is 0.3.82/build122, Apple Silicon/macOS26+, ad-hoc and not notarized.
Broader editor admission, installed clipboard/IME/drag-drop, displayed
performance, cross-client write/reopen and production delivery acceptance
remain open. AI stays deferred. No full-parity or production-release claim.


## Quoted paste and responsiveness priority (containers182 / performance183–184)

The quoted-paragraph paste owner was extended at the existing clipboard
boundary. Eight registered pinned-web paste references retain the receiving
heading/quote, bold text and child ownership. Native's final test fails 192
checks before the repair; 48 new regression workflows and 24 explicit-break
controls then pass in all 29 clipboard tests. The public Source guard remains.

The user then prioritized broadly sluggish UI. Release profiling on 1001
synthetic notes and a 500-paragraph note showed repeated collection filtering
and frontmatter parsing in view updates. A collection-cache-only experiment
gave modest results and was not accepted as a full fix. The combined repair
adds bounded exact-byte Mac metadata reuse and avoids replacing unchanged
inventories. The initial Unicode-canonical equality guard failed a new exact
content/path byte test with preserved timestamps; final comparisons retain
exact UTF-8. Existing filter and frontmatter owners cover external refresh and
BOM/CRLF/Unicode freshness. The iOS compilation branch retains the original
parser behavior; this work changes the Mac read path.

A follow-up Release profile still showed closed toolbar menus parsing the
whole note per edit. The table/code control now discovers current blocks from
one parsed document when its native menu opens. The real-popup owner checks
current table/code requests, handwritten source fragments at request ranges,
rebuilding after edits and stale-choice refusal. The first fixture did not
open the menu; a subsequent cancellation fixture was stopped while waiting in
AppKit's tracking loop. An event-tracking timer corrected that test fixture.
There is no production timer or test-only seam.

Preview123 was a verified local cache candidate but was not handed to the user
after its mixed performance result. Preview124 packages the combined changes
after all 263 non-AI desktop tests passed. Mounted version/signature/guide,
337 recorded source/build inputs and the complete private download checksum
were verified. Its exact executable was profiled against Preview122 on matched
synthetic 500-paragraph notes containing actual code and table cards. In that
10-second typing sample, repeated collection/code-discovery frames disappear
from the sampled typing path, and observation times improve. These are five
key-plus-accessibility observations per build, with automation overhead, not
pure input/frame latency or general performance acceptance. The slower first
input and periodic full-vault scans remain explicit follow-up work.

The installed Preview124 menu opens the correct table and Swift editors;
cancelling both leaves the note unchanged, and Escape restores editor focus.
Five benchmark keys are saved exactly, all other 1000 notes remain byte-identical,
and native quit/reopen retains the text and menu. No user vault was edited.
See performance183/ and performance184/, performance184-verification.json,
preview124-handoff.json and acceptance124/results.json. Preview124 is
0.3.84/build124, Apple Silicon/macOS26+, local ad-hoc and not notarized.

Performance remains the priority. Cold/first input, polling and open/save I/O,
larger/provider-backed vaults and sustained interaction need further profiling.
Full editor admission, broader installed clipboard/IME, cross-client and
production delivery acceptance stay open. AI remains deferred.

### Preview125 / performance185 — batched fresh inventory reads

Preview125 (0.3.85/build125) reduces Mac inventory coordination overhead. File
presenters are prepared in batches of at most 256 notes; each note still gets an
individual coordinated read of current bytes. Save transactions/CAS and the iOS
scan path are unchanged. No timestamp-based content cache was introduced.

The optimized actual-helper probe on 1001 synthetic notes measured roughly
0.08 seconds per batched read versus 0.50 seconds with separate coordinators.
It also checked pending file-presenter saves and invalid UTF-8 refusal. Matched
17-second idle installed profiles show fewer scan-stack samples (1341 before,
361 after); these are sampling observations, not frame latency or a guaranteed
provider-wide ratio. No timing XCTest or production test seam was added.

The non-AI gate passes 263 tests. The exact DMG app was installed, signature and
bundled guide checked, and its full private HTTPS download matched the receipt.
An external same-size edit with a preserved mtime appeared automatically; a
native edit/save retained it byte-for-byte, the other 1000 notes were unchanged,
and clean quit/reopen retained the result. All 338 recorded build fingerprints
still match. See `artifacts/native-macos/acceptance125/results.json`,
`performance185/idle-comparison.json` and `preview125-handoff.json`.

The hideable folders sidebar remains. AI/chat stays deferred. Large-note export,
cold input/opening, cloud providers, cross-client and broader installed/IME
acceptance remain open. This is an ad-hoc signed Apple Silicon/macOS26+ preview,
not a notarized production release or full parity acceptance.


### Internal performance batch 186/187 — no DMG handoff

The user clarified the delivery cadence: intermediate builds are for agent QA;
provide a DMG for user testing only at the end. Use internal app builds unless
artifact-specific testing actually requires a DMG. Preview125 remains the latest
packaged artifact; version/build remain unchanged during this batch.

Automatic note recovery now selects only the opened note's established recovery
filenames before reading/decoding them. Global Recovery review still inventories
all drafts and preserves warnings, including legacy/current records and unsafe
files. The installed open profile no longer spends time decoding unrelated
private drafts. Prose input also retains existing code styling rather than
re-highlighting unchanged cards; code/structural edits retain styling updates.

The final 263-test scoped desktop gate passes. The internal Release bundle's
app/CLI signatures and manifest freshness pass canonical verification. Native
QA on a 1500-line code fixture checks Portuguese acute composition, code edit
Undo/Redo, exact source bytes after Save, 1001 unchanged peer notes and clean
quit/reopen. No real user vault was modified. See
`artifacts/native-macos/performance187-verification.json`.

The measured native key-plus-AX observations still include substantial
accessibility-inspection cost and do not establish pure key latency. Larger
code editing/layout, general responsiveness, provider/cross-client workflows,
guarded rich admission and wider installed/IME/design acceptance remain open.
AI/chat remains deferred. No new DMG, tag, commit or publication was made.


### Internal performance192 — code-body export

The installed performance187 typing sample also showed export copying a whole
syntax-coloured code block and then making two attribute lookups per UTF-16
character. Export and code-sheet requests now extract from the original range,
scanning only separator/placeholder attribute runs. This retains all real body
characters and strips the same editor-only LF/U+200B markers as before. No saved
content cache or timestamp shortcut was introduced.

The optimized scratch comparison of actual before/after helpers on a 3000-line
coloured code span measured 299 ms versus 21 ms for 30 exports, with identical
bytes and range/Unicode/CRLF/empty controls. These figures measure helper cost;
they are not installed typing latency or complete responsiveness acceptance.
The four existing native code export/edit/sheet owners and the complete scoped
263-test non-AI desktop gate pass. Evidence is under
`artifacts/native-macos/performance192/`. No new timing XCTest, version bump or
DMG was added. Larger-note export, layout, cloud-provider and overall installed
responsiveness still require acceptance.


The performance192 internal Release app also passed canonical app/CLI signature
verification and installed QA on a matched 1002-note synthetic vault with a
1500-line Swift card. Five key-plus-AX observations per build were mixed: median
2377 ms before versus 1712 ms after, including automation/accessibility overhead.
The profile no longer shows the whole coloured-block copy on that export path,
but these observations do not prove general responsiveness. Code editing,
Undo/Redo, exact saved prose/code bytes and clean rich-mode reopen passed; the
other 1001 notes were unchanged. The next measured main-thread cost is recovery
checkpoint JSON plus atomic disk write/readback on typing. Any offloading needs
to preserve ordering, error reporting, save/remove and close/quit guarantees.
No new DMG or version bump was made.


### Internal performance193 — recovery I/O outside typing

Recovery checkpoint encoding, atomic write and readback now run on an ordered
serial worker rather than AppKit's typing call stack. Every edit registers its
own immutable checkpoint; no debounce or checkpoint-dropping policy was added.
The canonical vault is captured at registration. Failure reporting returns to
the current matching workspace draft on the MainActor.

Recovery snapshot, enumeration and export drain queued work before reading;
Save/discard removal drains before deletion so old work cannot resurrect a draft.
Successful close/quit asynchronously waits before its final state check. Existing
note-save CAS and save serialization are retained. An abrupt process termination
can still interrupt pending work; this is not a zero-loss crash guarantee.

The final scoped gate passes 263 tests. The concurrent-window lifecycle owner now
includes a 12-edit Unicode burst immediately before Save and checks that the
peer checkpoint survives while the saved window's draft is absent. The first
full-suite attempt was intentionally interrupted to freeze canonical-root
capture; only `performance193/final-desktop-tests.log` is final passing evidence.
The internal Release profile confirms checkpoint encoding/write/readback moved
from the main thread to the recovery queue. A matched 30-key burst, with one AX
read afterward, did not improve overall call timing; no end-to-end responsiveness
claim is made. Immediate quit without explicit Save retained the final keystroke
exactly, and clean relaunch stayed rich without a recovery notice. All 1001 peer
notes were unchanged. App/CLI signatures and manifest freshness passed. The next
measured UI cost is whole-note word counting in the footer. Evidence is in
`artifacts/native-macos/performance193/verification.json`.
No new version or DMG was made.


### Internal performance194 — stable code-body word counts

The footer still counts code words. It now reuses the grapheme-based count for
an identical AST code body when its boundary is provably independent of adjacent
prose. Other Unicode/boundary shapes retain the original whole-text path. The
separate code-body cache is bounded, and changed code remains a different key.
Inline formatting, wiki labels, images, HTML breaks and empty-marker behavior
are unchanged.

The existing footer owner adds literal Unicode, changed-code, changed-prose,
combining-mark and empty-code cases. The full scoped gate passes 263 tests.
A scratch comparison against the pinned parser matches the before/after count
in 720 mixed code/prose cases, and shows lower count cost on 40 changing-prose
versions sharing a large Unicode code body. Its wiki and empty-marker helpers
are stubbed only for this no-link/no-marker benchmark; the native footer owner
uses the actual app helpers. Those helper timings are not installed latency.
The internal installed sample confirms repeated full-code grapheme splitting
no longer dominates the footer update. The matched keyboard burst has lower
automation-call time in this sample, but is not frame-latency or general
responsiveness acceptance. Code edits changed the visible footer count correctly
through Undo/Redo and clean relaunch. Exact saved bytes and all 1001 unchanged
peer notes passed; the folders sidebar still hides completely and restores.
Canonical app/CLI verification passed. Evidence is under `performance194/`.
Broader navigation/collection profiling, remaining rich parity and installed
acceptance remain open. No new version or DMG was made.


### Internal performance195/196 — collections and row menus

Native QA now covers Planning/Research navigation, in-collection search,
Gallery scrolling and Table/Kanban switching in the synthetic vault. The
collection profile exposed ordinary rows reparsing frontmatter in closed
context menus solely to choose the file-link action label. The Mac view now
checks the required file-hub ID through the existing exact-content metadata
accessor first. Valid or incomplete metadata still goes through full validation;
file-link actions and writes are unchanged. The installed scrolling sample still
contains card/context-menu construction but no NativeFileHub constructor frames
for ordinary rows. This is reduced repeated work, not general latency acceptance.

Installed QA also found unselected list rows opening menus on their text but
not the blank row center. An explicit rectangular interaction shape fixes that
exact native regression. Menu labels for ordinary, linked and incomplete notes,
normal activation, middle-click tab opening and the linked text-document preview
pass. All 1005 note bytes (1002 earlier notes plus 3 intentional QA fixtures) and
the synthetic attachment remain unchanged. No user vault was edited.

Six focused collection/file-link tests pass for each view-only change. The last
broad scoped gate is performance194's 263-test pass; it is not relabeled as a
new full-suite result. Current app/CLI signatures pass canonical verification.
Evidence: `artifacts/native-macos/performance195/` and `performance196/`.
Broader responsiveness, remaining rich parity and installed acceptance stay open.
No version bump, DMG, commit or publication was made.


### Guarded nested quote/list foundation197/198

The pinned web app preserves these containers. Native now recognizes quote
indentation inherited from wider outer list markers, and the new body-edit owner
preserves source/parents and Undo/Redo across ten LF/CRLF workflows. It fails 20
assertions on the old parser; the prefix foundation's scoped gate passes 264 tests.
A follow-up keeps raw literal typing on the old standalone shortcut grammar;
the original source passes the corrected fixture, the expanded parser fails four
assertions, and both final focused owners pass. No public admission was widened.
Structural command rebasing, visual indentation and broader clipboard/IME work
remain before these sources can leave Source mode. Evidence: containers197-review
and containers198-review. No new installed app, version or DMG was made.


### Internal QA packaging cadence

The user clarified that intermediate DMGs are for agent Computer Use only and
are not requested as user test deliveries. Prefer internal app builds; generate
a DMG only for packaging-specific verification or the final handoff. Keep
performance and non-AI workflow correctness as the active priorities, retain the
fully hideable folder sidebar, and leave AI acceptance deferred.

### Guarded nested quote/list marker-width repair199

Ancestor padding changes now rebase descendants at the owning quote depth and
move owned blank quote separators with them. Six LF/CRLF editor scenarios cover
one and two changed ancestors, exact source, parser parentage, Undo/Redo and
caret/typing. The previous source fails the expanded owner; both focused owners
pass with the repair. Evidence is in `containers199-review`. Public admission
remains Source pending layout and broader command/clipboard/IME verification;
this is internal foundation work, not installed or release acceptance. No new
DMG was generated.

Final containers199 validation: the scoped non-AI desktop suite completed with
264 tests and zero failures; the frozen source hashes match the tested source.


### Guarded nested quote/list layout200

List contexts now retain the ancestor items crossed before inner quotes.
Paragraph styles include those ancestors' rendered offsets, and existing
context refreshes resolve current heads after marker changes. This adds no
whole-document parse. Context-copy paths preserve the layout information.
The six-shape editor owner checks quote/child alignment on import, formatting,
Undo and Redo; the previous source fails 48 assertions and both focused owners
pass after the repair. Markdown and parser ownership stay unchanged. Evidence:
`containers200-review`. Installed layout, remaining commands, clipboard and
IME behavior are still pending; public rich admission remains closed for these
nested shapes. No DMG or version bump was made.

Final containers200 scoped validation completed: 264 non-AI tests, zero failures,
with matching frozen source hashes. Installed layout acceptance remains pending.


### Special-view navigation correction202

The user clarified desktop parity: Gallery, Kanban, Table and Calendar show
only their collection or an opened note. List alone keeps the collection beside
the editor at wide sizes. The arrangement now applies that rule at every width;
the toolbar switches between the collection and the retained note. Choosing a
layout or saved view reveals its collection while retaining the open note.
The redundant Expand collection action was removed.

The hidden special collection tree is unmounted inside a stable pane container.
The native editor remains mounted, preserving drafts, selection and Undo. The
expanded existing pane owner failed 20 assertions on the old layout. Its final
wide/compact cases pass with editor identity, visibility, focus, caret and
Undo/Redo checks for all four special views. The existing saved-view owner
reproduced two missing collection-reveal behaviors and passes with the model
repair. Broad and installed validation are recorded in `layout202`.

The performance201 experiment isolating Gallery invalidation was removed after
this clarification; it is not part of the source. Its original typing profile
captured the incorrect side-by-side Gallery. The List control is kept separately
and must not be described as an apples-to-apples speedup. No DMG or version bump.


Final layout202 validation: the two focused owners and all 264 non-AI tests
pass. The internal Release app and bundled CLI signatures are verified, with
version/build unchanged at 0.3.85/125. Installed QA verifies Gallery, grouped
Kanban, Table and dated Calendar collection→note→collection transitions; only
List stays beside the editor. A draft survives the Gallery round trip and Undo
restores the original file. The folders sidebar still hides and restores.
All 1005 original notes and the linked attachment remain byte-identical; one
additional dated synthetic Calendar fixture is unchanged after the check.

The corrected note-only typing sample contains no gallery card, field-discovery
or MacCollectionViews frames. The 30-key transport measurement is recorded, but
is not a frame-latency or general responsiveness claim; the earlier Gallery
sample exercised the wrong product layout. Screenshots, profiles, signatures and
bounded installed results are in `artifacts/native-macos/layout202/`. No DMG,
version bump, user-vault change or AI acceptance was made. Broader performance,
rich parity and installed/release acceptance remain open.


### Internal performance203 — saved-note attachment snapshots

A matched installed large-note profile in the intended List split found repeated
attachment-reference scanning in the inspector while typing in ordinary prose
outside an unchanged 1,500-line code block. The attachment panel reads saved
text, so a per-window cache now retains its references until the saved baseline
changes. Save, refresh and note/vault switches invalidate it. The original parser,
path resolution and preview actions are unchanged; no entire-source key is
hashed on each draft keystroke.

All 264 non-AI tests pass. No timing XCTest or test-only production seam was
added for this equivalence. The internal Release app and bundled CLI verify at
unchanged version/build 0.3.85/125. Installed checks verify a saved Markdown
reference appearing, its existing text-file preview, Undo/Save removal, external
add/remove refreshes, and clearing/restoring references across note switches.
All 1,006 synthetic notes and the existing attachment return byte-for-byte to
their baseline. The plain-paste control remains literal as intended; source
editing was used to add the Markdown reference.

In the matched 15-second call-tree samples, attachment-reference weights fall
from 146 to 10; the remaining scan occurs as saved snapshots change. A 30-key CUA
transport trial records 6,218 ms before and 3,555 ms after. These are bounded
profile and automation observations, not frame latency or a general speedup
percentage. Full footer Markdown parsing remains visible in the profile; broader
editing, export, navigation and large-vault responsiveness still require work.
Evidence: `artifacts/native-macos/performance203/`. No DMG, version bump or iOS/AI
implementation was made. The full migration goal remains open.


### Internal performance204 — bounded background footer counts

The footer no longer calls the full Markdown word counter while building the
window view. A dedicated serial queue counts immutable text snapshots. Each
label keeps one running request and one latest pending input, coalesces a short
typing burst, and checks a revision before publishing. Its own observable state
updates only the label. Note/vault identity scopes that state, and disappearing
labels cancel delayed work. Active parsing may finish, but an obsolete result
cannot update the count. The counting rules, including code words, remain
unchanged; the unused synchronous workspace getter was removed.

The existing footer owner retains its literal Markdown/Unicode table and now
reads the actual rendered footer after rapid draft changes, Save and note
switches. Its final synchronous control and background implementation both
pass, as expected for this semantic equivalence. An initial OCR case mismatch
and missing main-actor annotation were corrected in the harness; only the
final-control and final-owner logs are final evidence. Both final runs and the
264-test non-AI suite pass without Main Thread Checker warnings. No timing
assertion or test-only production seam was added.

The internal Release app and CLI verify at unchanged version/build 0.3.85/125.
In the installed large note, three new words change 13,509 to 13,512; Undo
returns 13,509, switching to a short note shows 7, and returning shows 13,509.
The saved positive edit changes only the intended phrase. All 1,006 synthetic
notes and the attachment return byte-for-byte to their baseline.

The matched profile moves word-count parsing from the main thread to
`com.zerus.notes.footer-word-count`. Main-thread count samples drop to zero;
background count work is observed directly. The 30-key transport trial is
3,555 ms before versus 3,506 ms after, essentially unchanged. This does not
establish general responsiveness or frame latency: remaining export, outline,
view-update and navigation costs need measurement and work. Evidence is in
`artifacts/native-macos/performance204/`. No DMG, version bump or iOS/AI change.

### Internal performance205 — unchanged metadata and navigation

Metadata polling now compares the raw shared-view, named-view and schema bytes
before adopting unchanged snapshots. Schema provenance also includes the root
and workspace identity. Real byte changes, including unknown fields and Unicode
changes, still reach the existing adoption paths. Navigation uses sorted JSON
and writes preferences only when its encoded value differs from the saved value.
Actual navigation changes remain immediately persisted.

All 264 scoped non-AI tests pass. The internal Release app and bundled CLI verify
at unchanged version/build 0.3.85/125. In matched 20-second idle profiles, sampled
main-thread navigation-persistence weight falls from 56 to zero; metadata polling
is observed in both. These sample weights establish removal of this repeated
work, not an overall latency or responsiveness improvement.

Installed QA verifies external Table and List settings are still adopted, with
the expected collection/note layout. The original shared-view file is restored
byte-for-byte. The selected note and List layout survive relaunch. All 1,006
synthetic notes and the attachment remain byte-identical. Evidence is in
`artifacts/native-macos/performance205/`. No DMG, version bump, iOS or AI change
was made. Remaining task publication, editor/export, outline and view-update
costs still need measurement; broad performance and full parity remain open.

### Internal performance206 — unchanged task snapshots

Task refresh reuses the existing sorted JSON snapshot to skip publication of
identical tasks, lists, categories, general-list name and warnings. The snapshot
is reset when opening a vault; changed bytes and encoding failures still use
the existing application path. Comparison retains exact Unicode spellings and
foreign fields. No second serialization, timing assertion or test-only seam was
added. Queued-write and refresh race protections are unchanged.

All 264 scoped non-AI tests pass. The internal Release app and bundled CLI verify
at unchanged version/build 0.3.85/125. Installed checks verify external creation
and changes to title, priority, category, list and general-list name; unsupported
records still show the warning. Completing and reopening through the app saves
correctly while preserving foreign task/envelope fields and unsupported records.
Removing the external task file clears the tasks, custom lists and warning.
The originally absent task file is restored to absent; all 1,006 synthetic notes,
the attachment and shared-view bytes remain unchanged.

Matched 20-second idle samples are retained in
`artifacts/native-macos/performance206/`, alongside source hashes, test results,
signatures and installed checks. Other window view work remains visible; these
checks do not establish an overall latency improvement. Unchanged saved-note
reconciliation, editor/export/outline work and broader responsiveness still need
measurement and repair. No DMG, version bump, iOS or AI change was made.

### Internal performance207 — unchanged saved notes and properties pane

Saved-note reconciliation keeps an identical snapshot rather than invalidating
its attachment cache. It assigns the body, recovery readiness and save/conflict
status only when the respective value changes. Snapshot comparison includes
metadata equality and exact path/content UTF-8, retaining provider spelling
changes. The properties-pane refresh similarly avoids repeating identical
layout, readiness and error assignments. Actual updates and revision/vault
guards keep their existing paths.

All 264 scoped non-AI tests pass, including retained-draft/export protection,
external renames, startup refresh and pane error recovery. No timing assertion
or test-only seam was added for these value guards. The internal Release app
and bundled CLI verify at unchanged version/build 0.3.85/125. Installed checks
verify an external body edit, attachment add/remove, rename following, pane
reorder/collapse, invalid-settings warning and recovery to the same valid
layout. The prior layout remains visible while settings are unreadable, and
restoring valid settings clears the error and re-enables controls.

In a matched 20-second idle sample pair, main-thread window-body getter and
inspector evaluation frames present before are absent after, while refresh
polling remains observed. This is a bounded sampling result, not invocation
counts, a CPU percentage or a general latency improvement. Active typing,
export/outline and larger navigation workloads still require work.

All 1,006 synthetic notes, the attachment and shared-view bytes are restored
exactly. The renamed note returns to its original path; the originally absent
pane and task files remain absent. Evidence is in
`artifacts/native-macos/performance207/`. No DMG, version bump, iOS or AI change
was made. Full migration and performance acceptance remain open.

### Internal performance208 — background Outline refresh

Outline presentation no longer parses the full note while building the window.
It shares the existing word-counter scheduling mechanism through a production
Markdown snapshot worker: one running input, one newest pending input, a short
coalescing delay and revision-checked publication. Each view owns its result
state; note/vault identity resets the Outline and disappearance cancels pending
work. Active parsing may finish without publishing obsolete results. Heading
clicks resolve the fragment against the current draft, never a background range.
The parser, heading labels, duplicate slugs and counting rules are unchanged.

A new rendered Outline owner checks duplicate headings, exclusion of code
headings, rapid draft changes, note switching and reopened saved content. Its
synchronous control passes, as expected for a performance equivalence. The
initial in-process accessibility-tree harness could not expose hosted SwiftUI
buttons and was replaced with rendered text; that initial failed harness is
not product evidence. The Outline, footer and heading-navigation controls pass,
and the final scoped non-AI suite passes 265 tests with zero failures. The final
worker closures avoid the intermediate function-conversion sendability warnings.

The internal Release app and bundled CLI verify at unchanged version/build
0.3.85/125. Installed QA checks large-note typing/Undo, current-note Outline
switching, an edited heading's new title/slug and button, and Undo restoring the
original heading and footer count. Clicking Outline scrolls the large note from
the bottom to the heading, focuses its editor and leaves saved bytes unchanged.
All 1,006 synthetic notes, the attachment and shared settings are restored.

Matched 15-second typing profiles move observed heading parsing from Main to
`com.zerus.notes.outline`. The 30-key transport trial is 4,637 ms before versus
4,425 ms after under sampling; sampling itself adds overhead and these are not
frame-latency or general speedup measurements. A separate SwiftUI trace records
transaction groups and update events. It contains no potential-hang rows at its
250 ms threshold in this short workload, but this is not complete hang or frame
acceptance. The frame table is not interpreted as a hitch count. Attaching after
views were created also leaves some view names unavailable.

The trace identifies remaining typing-related window transactions around
10–14 ms, plus saved-inventory updates. A causal workspace setter identifies
the transaction's origin, not exclusive CPU cost. The next performance pass
should isolate note-editing state from unrelated window content, rather than
assuming that removing that setter alone removes the transaction. Evidence,
trace exports and summaries are in `artifacts/native-macos/performance208/`.
No DMG, version bump, iOS or AI change was made. Broader performance and full
feature parity remain open.

### Internal performance209 — isolate live draft updates

The per-window draft now has its own observable state. The writing area and
Outline observe that state directly; `workspace.body` remains a read/write
adapter to the same String for saves, recovery and actions. The draft publisher
is deliberately not forwarded to the workspace: doing so would invalidate the
folder, collection and saved-note inspector on every key again. Actual save,
status, navigation, inventory and permission changes keep workspace publication.
The edit callback also avoids assigning unchanged browsing, recovery-readiness
and save-status values. No persistence or autosave timing rule changed.

The existing footer and Outline owners now settle an intermediate draft before
a further edit. The Outline owner also checks that the same editable NSTextView
shows the latest text. Original and candidate controls both pass, as expected
for this semantic equivalence. The final scoped non-AI suite passes 265 tests,
including marked-text startup, late writing, block menus, layout, save and
retained-draft/export protection. No timing XCTest or test-only seam was added.

The internal Release app and CLI signatures verify at unchanged 0.3.85/125.
Installed checks verify a 30-key large-note edit and Undo; Outline focus/scroll
navigation; note switching; Portuguese dead-key `é` and the updated footer while
still unsaved; a changed heading and slug; and navigation through that new
fragment. Cmd-S writes exactly the intended live-draft bytes, and Undo/Cmd-S
restores the original note. All 1,006 synthetic notes, the attachment and shared
settings return to their baseline bytes.

A matched 15-second SwiftUI trace uses the performance208 source/binary as its
baseline and the same 30-key workload and saved-note bytes. Typing-originated
transaction records fall from 100 to 27; their 95th-percentile duration falls
from 10.458 ms to 0.993 ms. Graph-update records fall from 87,594 to 11,870.
The largest typing-originated transaction remains 13.210 ms for a real
save-status transition.
The median changes from 0.332 to 0.676 ms: these are distributions of different
numbers of downstream records after coalescing, not paired per-key latencies.
The after trace records 24 draft-originated and 3 save-status-originated typing
transactions, replacing the repeated workspace-wide origin.

This is one instrumented fixture, not a general speedup, input-latency or frame
acceptance claim. Some view names are unavailable because recording attached
after view creation; causal setters identify origins rather than exclusive CPU
cost. The short after trace has no potential-hang rows at its 250 ms threshold.
Navigation, external-document editing and other large-note workloads still need
verification. Raw traces, exports, the comparison and reproducible extraction
script are in `artifacts/native-macos/performance209/`. No DMG, version bump,
iOS or AI change was made. Full feature parity and performance acceptance remain
open.

### Internal acceptance210 — collection navigation and actionable reviews

Installed QA verifies the fully hideable/restorable folders sidebar, Gallery
collection-only presentation, note-only opening, and returning to the collection
and back with an unsaved draft and editor focus retained. Undo/Save restores the
note. Wide List retains collection and note together. Table and Calendar likewise
replace the note pane; opening a row/date displays its note alone. Calendar uses
a temporary declared Due field in the synthetic QA vault.

An actual pointer Kanban drop with an inferred but undeclared Status field
correctly yields a skipped-change issue from the engine. The review nevertheless
offered Apply with no changes. Collection and bulk/history reviews now use the
existing plan.hasChanges predicate: empty plans offer Close, while actionable
plans retain Apply. Installed negative verification confirms Close-only review.
A temporary declared Status schema then permits a pointer drop from Draft to
Done. The board counts update, the note shows Done, and Organization history
Review undo/Apply restores Draft and marks the receipt Undone. The property
writer normalizes YAML quoting, so this is semantic Undo evidence; QA cleanup
separately restores the original unquoted bytes and verifies their baseline hash.

Build-for-testing, the scoped non-AI suite (265 tests, zero failures), and the
internal Release build terminate successfully. App and bundled CLI verification
pass at unchanged 0.3.85/125. Evidence, screenshots, baseline/repaired review AX,
Undo receipt and source snapshots are in artifacts/native-macos/acceptance210/.
No timing test or production test seam was added for the dialog predicate.

All 1,006 baseline note files and the attachment return to their recorded hashes;
shared views return to exact original bytes, and temporary schema/bulk-history
files return to their originally absent state. The app is left on Menu QA
Ordinary in List mode, Saved, seven words. A first pointer attempt after schema
refresh did not move a card; a later title-region drag after remount succeeded.
Because both mounting and hit region changed, this is not evidence of a stale
scope defect. Live-schema drag isolation remains unverified.

A second workspace opens independently. Resizing it to a narrow window removes
the side panes; folders and inspector open as drawers, with the underlying editor
absent from accessibility. A test key while the folder drawer is open leaves the
note unchanged. Done dismisses folders and Escape dismisses inspector. Global
search places Performance note 0998 first, and Open reaches its saved note.
Closing that second window leaves the original List window and Menu QA Ordinary
intact. Screenshots record both compact drawers.

This batch does not complete all drag/drop routes, physical IME acceptance,
broad performance or full parity. No DMG, version bump, iOS or AI change was made.
The private frontend and proxy both respond successfully at the existing /app
preview endpoint.

### Internal performance211 — share rendered board columns

A 333-note installed Kanban display/scroll profile identifies per-card column
menus repeatedly scanning every collection note on Main. Card context and
ellipsis menus now receive the already-rendered board scope's column array.
The rightmost-column button uses the rendered groups count. Both are the same
field/order/membership snapshot already used by that board; no global cache or
new invalidation rule is introduced. Live scope admission and the checks before
and after asynchronous moves remain unchanged.

The Debug build-for-testing, 265-test scoped non-AI suite and internal Release
build all terminate successfully. App and bundled CLI verification pass, with
version/build unchanged at 0.3.85/125. No new tests or timing seam were added for
this rendering equivalence; existing board scope/reorder/stored-array/Undo owners
pass, supplemented with installed checks of the changed menus.

Matched 15-second sample workloads choose Status from no grouping, display the
333-note board and scroll three pages. Inclusive sample weights in the repeated
card-column helper fall from 1,921 to zero; aggregate board-grouping nodes fall
from 2,016 to 143. These are one trial per binary, sampled stack weights rather
than invocations, CPU percentages, frame times or general input latency. The
helper's removal is expected from source; the lower remaining grouping weight
provides runtime evidence that the work was not simply moved to another card
path. Transport durations differ and no broad speedup is claimed.

Installed menus initially show No value/Draft. A temporary declared schema adds
Review/Done while the board stays mounted; both the ellipsis and context menu
pick up all four choices. A card-menu move to Done updates note Status and board
counts. Native Organization history Review undo/Apply restores Draft and marks
the receipt Undone. The writer normalizes YAML quoting; separate fixture cleanup
restores exact original bytes. All 1,006 baseline note hashes, attachment bytes,
shared views and originally absent schema/history are restored. Evidence and
reproducible sample extraction are in artifacts/native-macos/performance211/.

No DMG, version bump, iOS or AI change was made. Broader navigation/editor
performance, guarded nested containers, installed input/accessibility and
cross-client acceptance remain open. This is not full parity or final delivery.


### Internal performance220 — persist completed tab transitions

The installed 1,000-note synthetic vault profile identifies synchronous
NSUserDefaults/CFPreferences work in navigation. Opening a previously absent
collection or note tab used to persist after appending the tab and again after
activating it. MacWorkspace now suppresses persistence for those synchronous
intermediate assignments, then immediately saves the completed state. Previous
collection state is still captured first. No deferred writer, persistence format,
queue, new cache or parser pass is introduced.

Two existing navigation/filter owners pass, including creating another workspace
and restoring the active folder, distinct global/folder/note tabs, query, typed
filters, inspector and expanded folders. No timing test or production test seam
was added for this equivalent state transition.

An internal Release at unchanged 0.3.85/build125 is signed and verified, including
the bundled CLI, then installed in the owned QA app. From Planning with no Work
or Inbox tab, both old and new binaries open Work then Inbox during a 20-second
sample at 1ms. Inclusive navigation-persistence node weights are 162 before and
55 after. This is one trial per binary, not invocation counts, frame times,
per-input latency, CPU percentages or a general responsiveness speedup. The
preference domain has 5,340 keys and about 3.46 MB of encoded values, which can
amplify CFPreferences cost; preferences were not cleared to improve the result.
The earlier Research/Planning sample is discovery only because those tabs
already existed and did not exercise the eliminated intermediate append write.

The updated app restores active Inbox and both newly created tabs after an
actual quit/relaunch. Only the two profiling tabs are then closed, and Planning
is restored. Comparing every baseline note, asset and shared views file confirms
unchanged bytes. An offscreen close accessibility element invalidated; refreshing
native state and using the tab context menu closed it. This is recorded as an
automation limitation, not evidence of document or navigation corruption.

Source hashes, receipts, sample logs/extraction and final scoped desktop results
are in artifacts/native-macos/performance220/. The installed app now includes
the guarded core repairs through containers218. Public nested quote/list
admission remains closed. Broader displayed responsiveness, installed physical
IME/accessibility, cross-client acceptance and final delivery remain open.
No DMG, version bump, iOS or AI change was made.

The final scoped non-AI suite passes 265 tests with zero failures and terminal
exit 0 on matching frozen source hashes. The internal Release build and both
existing focused owners also terminate successfully.


### Internal performance221 — reuse unchanged collection property inventories

The installed Gallery display/scroll profile shows property inventory inference
on Main. MacWorkspace now reuses its resolved field list while the collection
key, workspace identity and exact schema bytes remain unchanged. The existing
collection key already includes the note revision, destination/folder identity,
query, filters, subtype choice and applicable date/calendar boundary. Inferred
and declared fields still use the existing resolver; folder-owned definitions
remain available even when no notes match. Board scope admission reads the same
fresh-keyed getter. No persistence, parser, permission, refresh interval or
image-loading behavior changes.

Three existing layout/board owners pass, covering scope identity, stored arrays,
typed moves and Undo. No timing XCTest or production test seam was added for
this memoization. An internal Release at unchanged 0.3.85/build125 is signed,
CLI-verified and installed in the owned QA app.

The matched workload starts with a warm first-page 333-note Gallery, no grouping,
and toggles Select on/off/on/off during a 20-second 1ms sample. Inclusive sampled
weights in MacCollectionValues.definitions are 68 before and zero after. This
is one sample per binary, not invocation counts, CPU percentages, frame time,
per-input latency or broad responsiveness acceptance. Initial inventory work
still runs when its inputs change. The discovery display/scroll sample remains
separate and is not compared against this selection workload.

Actual mounted-UI checks, without restart, verify these invalidations:

- A schema edit adds Schema freshness and hides Status; Properties updates.
- Adding Note freshness to one note makes that inferred field appear.
- Searching for another note removes Note freshness; clearing search restores it.
- A zero-result search retains the declared Schema freshness field only.
- Restoring the original note bytes and originally absent schema returns the
  original Status/Tags menu.

All 1,008 compared note/asset/view files are restored, query is clear, selection
mode is off and Planning is active. Source hashes, internal app receipt, raw
samples, repeatable extraction and scoped desktop evidence are in
artifacts/native-macos/performance221/. The final suite status is recorded in
that folder's verification.json when the process terminates.

Public nested quote/list admission remains guarded. Remaining work includes
broader displayed responsiveness and actual input/frame measurement, guarded
clipboard/container routes, installed physical IME/accessibility, cross-client
acceptance and final delivery. No DMG, version bump, iOS or AI change was made.

The final performance221 non-AI desktop run passes 265 tests, zero failures,
terminal exit 0 on matching frozen source hashes. The three existing focused
owners and internal Release build also terminate successfully. Final byte
comparison still matches all baseline files after the suite.


### Internal performance222 — do not republish identical search commits

SwiftUI responsiveness tracing of Gallery selection identifies query-setter
transactions even though the query remains empty. Entering collection selection
moves the responder from the search field to the collection keyboard target;
the text field commits the same value. The search binding now skips only
byte-identical UTF-8 values. Changed text, including distinct Unicode spelling,
still reaches the existing model setter and persistence/filter path. No keyboard
focus rule, model mutation API, parser or persistence format changed.

The initial trace includes AX inspection after each toggle and records a
278.63 ms microhang. Samples in that interval include accessibility and graph
work, so it is discovery rather than ordinary input-latency evidence. A stricter
control starts with a warm 333-note Gallery and focused empty search. It waits
for xctrace's Darwin start notification, performs four deterministic 500 ms held
Select clicks and reads AX only after recording stops. Both binaries capture
four separated callback clusters. The baseline contains six query-setter
transactions; the repair contains none. One microhang is recorded before and
none after, but these are single instrumented runs with inclusive downstream
work and trace overhead: no general speedup or end-to-end latency claim follows.
Other selection transactions remain expensive and require further work.

The internal Release remains 0.3.85/build125, is signed and CLI-verified, and is
installed in the owned QA app. Actual checks confirm changed search text yields
one matching note, Select then Cmd-A selects that filtered note without changing
the query, Escape clears selection, and clearing the search restores 333 notes.
Planning, empty query and cleared selection are restored. All 1,008 compared
baseline note/asset/view bytes remain unchanged. The two initial focused
large-list/search/filter owners pass.

The original full run executes 265 non-AI tests: 260 pass and five rendered-UI
owners throw OS Vision/E5 resource errors. A fresh owner and isolated CPU request
reproduce the framework failure. Moving only the generated E5 cache aside does
not resolve it; original derived files are preserved in the artifact folder.
A revision-2 CPU probe and five focused owners pass, but the attempted test-only
pin still fails three OCR owners in the full run and workspace-class diagnostic.
That configuration is therefore rejected and fully reverted. Original test
sources and assertions remain unchanged, no skip or fallback is added to the
repository, and full-suite verification is pending rather than reported green.
An attempted compiler-worker reset stops at its same-user guard because the
idle worker is root-owned; no service is terminated. No OS repair is claimed.

Raw traces, inspect-deferred recording/extraction scripts, source hashes,
internal app receipt, complete failed logs and rejected-oracle evidence are in
artifacts/native-macos/performance222/. The final build and partial-verification
status is recorded in verification.json. The public nested quote/list guard is
unchanged. Broader frame/input measurement, rendering graph cost, structural and
clipboard/card routes, installed physical IME/accessibility, cross-client
acceptance and final delivery remain. AI is deferred. No DMG, version bump or
iOS change was made.

Final restoration check for performance222: the original test sources rebuild
successfully, and the restored filter/persistence owner passes (one test).
All recorded source hashes, the installed executable receipt and all 1,008
baseline file hashes match. After relaunch, Planning has an empty search and
no selected notes. Both web-preview routes return HTTP 200. The full-suite
status remains 260 passing checks plus five Vision runtime errors; no full
green result is claimed.

### Internal performance223 — identify collection graph cost without retaining an ineffective change

A Time Profiler recording of the verified performance222 app confirms substantial
main-thread update/layout work during four warm 333-note Gallery selection-mode
toggles. Accessibility focus rebuilding and the SwiftUI graph account for much
of the sampled work. AX inspection was deferred until after capture. These are
running CPU samples, not input-to-frame latency.

An internal Release experiment passed the note menu's concrete SwiftUI type
through the collection instead of wrapping it in AnyView. It built and its
native context menu retained the expected actions, but the matched recording
did not demonstrate a meaningful improvement. The experiment is rejected:
all production sources are byte-identical to the before snapshot, and the
owned installed app is restored to the verified performance222 receipt. The
experimental binary and source copies are retained only as rejected artifacts.
No tests or expectations were changed. All 1,008 QA baseline file bytes are
restored, including the original views.json; Planning returns to List.

The first Animation Hitches capture failed to save (exit 17). Its orphaned
same-user tracing helper retained a 6.3 GB temporary ktrace. After confirming
the helper belonged to this recording, it was stopped and the unused scratch
file was removed. Four large generated XML exports were losslessly compressed
and verified by SHA-256; the original data is available in their .xml.gz files
(performance208, performance209, performance222). A regenerable build index
was removed. Source, QA vaults, saved traces and test-result bundles were kept.
The interrupted Release build is recorded separately from the successful retry.

Evidence and rollback checks are in artifacts/native-macos/performance223/.
The next target is selection-state observation scope and focus rebuilding,
with keyboard and accessibility behavior preserved. This turn claims no broad
responsiveness improvement or full-suite pass. The performance222 Vision gate
remains unresolved. AI is deferred; no DMG, version bump or iOS change.

### Internal performance224 — confine collection selection updates

Collection selection now has a per-workspace observable state. The workspace
keeps its existing selection APIs, anchors, range logic and permission checks,
while list rows, bulk controls, alternate collection content and keyboard
routing subscribe directly to that state. Identical assignments are ignored.
Selection alone no longer publishes a change to the entire workspace, so the
folders, toolbar, tabs and editor need not rebuild. Original context-menu
types, saved formats and the public rich-container guard are unchanged.

The frozen Debug build succeeds. The existing scoped non-AI suite passes all
265 tests, zero failures, with terminal exit 0. This includes the rendered
collection/keyboard, large list, theme, footer and outline owners. All five
default Vision OCR checks that failed in performance222 now pass without
changing their settings, assertions or expected values. No particular OS repair
is claimed. The earlier Vision gate is clear in this current run. Existing
AI/chat exclusions remain per the user's deferral; no new skip is introduced.

The internal Release builds, signs and verifies at unchanged 0.3.85/build125.
Installed checks cover Select, Cmd-A and Escape in List, Gallery, Table,
Calendar and Kanban; filtered Gallery selection and search-field focus;
native board-card actions; hiding/restoring folders with a retained selection;
and Gallery -> note -> Gallery navigation. The special view and note remain
mutually exclusive. All 1,008 baseline note/asset/view file bytes are restored.
The QA app ends in Planning/List with empty search, cleared selection and
folders visible. No note editing or new tab was needed for these checks.

A fresh matched Time Profiler capture uses four warm 333-note Gallery toggles,
99 mounted note buttons in each build, the same window and held clicks, and
no AX polling or concurrent build/tests. Main running CPU sample weight is
618 ms before and 508 ms after. The four event-related CPU clusters are
164/121/149/141 ms before and 132/103/130/106 ms after. Toolbar-building
samples present before are absent after. These single-run CPU samples support
less work in this interaction; they do not measure input-to-frame latency,
exclusive function time, or establish broad responsiveness acceptance.
Collection graph and accessibility focus costs remain substantial.

Evidence, exact source hashes, test summaries, installed app receipt, raw
traces and file restoration checks are in artifacts/native-macos/performance224/.
No tests were added for notification counts or timing; the existing behavior
owners and installed profiling cover this refactor without a test-only seam.
Broader performance, structural/clipboard parity, physical IME/accessibility,
cross-client acceptance and final delivery remain. AI is deferred. No DMG,
version bump or iOS change was made.

### Internal performance225 — reject an ineffective focus scheduling change

Recorded stacks still show considerable layout and accessibility focus work.
An experiment moves the Select-mode focus request into the existing AppKit
representable update, removing a second SwiftUI state pass. Initial mode
semantics, enabled/sheet/vault guards and superseded-request rejection were
preserved. The candidate builds and passes all 265 unchanged non-AI tests,
including the rendered keyboard/selection owner. Installed checks also keep
Cmd-A in search until Select transfers focus, select one filtered result, and
clear selection with Escape without changing the query.

The first20s baseline is excluded because the fourth event reaches the capture
end. Replacement40s before/after recordings include quiet tails after all four
events. Both use the same333-note Gallery,99 mounted buttons and held clicks,
without AX polling, tests or builds during capture. Entry CPU clusters are
125/129ms before and127/123ms after. Main running sample weight500->479ms and
exit differences do not demonstrate that this focus change meaningfully helps.
These are single-run running CPU samples, not input-to-frame latency.

The experiment is therefore rejected. MacAlternateOpen and the installed app
are restored exactly to performance224; all 1008 baseline file bytes are
restored. Rejected sources, binaries, successful test evidence and both usable
and excluded recordings remain in artifacts/native-macos/performance225/.
The retained implementation and passing suite remain performance224. A clean
Debug build of the restored source is also recorded, so the local test host
will not retain the rejected experiment. No new tests or skips were added.

The next performance target is real editor typing/export/layout work rather
than another small focus adjustment. Structural/clipboard parity, physical
IME/accessibility, cross-client acceptance and final delivery remain open.
AI is deferred. No DMG, version bump or iOS change.

### Internal performance226 — installed long-note typing attribution

Two owned fixtures contain the same text volume:500 independent paragraphs
and500 root list items, about149KB and21,962 words each. Five native x
keypresses at the same target are profiled in each rich editor, with40s
Time Profiler captures and no AX inspection during recording. Both persisted
files exactly match the original plus the five characters. One native Undo
and Save restores each original byte-for-byte. The fixture tabs are closed
and the exact-hash-guarded owned files removed; copies remain in artifacts.
All1008 original baseline note/asset/view file bytes remain unchanged.

Main running CPU sample weight is166ms for paragraphs and216ms for the list.
The direct keyDown stacks account for37ms and89ms respectively. Full Markdown
serialization occupies29ms and79ms inclusive in those captures. Total time
includes separate autosave and periodic refresh work, so it must not be
presented as typing latency. These are single-run1ms samples with overlapping
stack categories, not general responsiveness acceptance.

Source inspection explains the difference: the existing incremental Export
records independent plain root paragraphs, while list-body edits fall back to
full serialization. Ordinary nonempty canonical list typing already bypasses
the structural editing parser, so that parser is not the first target. The
next repair should extend export reuse only where stable marker/context and
paragraph-boundary invariants hold, with owner-boundary source/parent checks
and full serialization for structural edits. No implementation is claimed yet.

Evidence, originals, saved edits, exact Undo checks and raw traces are under
artifacts/native-macos/performance226/. Production source and the installed
performance224 app are unchanged; no new test run is needed for this discovery.
The265-test performance224 pass remains the retained implementation's evidence.
No DMG, version bump or iOS change. AI stays deferred, and broader parity,
physical IME/accessibility, cross-client and final delivery work remains.

### Internal performance227 — bounded root-list export reuse

Completed exports now record stable root list-head rows as well as independent
prose rows. A nonempty canonical root item can replace its own cached source
line while preserving the marker and immutable item context. Qualification
checks both the initial source span and the edited row; empty heads, owned
continuations, structural neighbors, cards, literal/attachment content and
changed context fall back to full serialization. Public rich admission is
unchanged.

The existing repeated-edit owner now covers bullets, ordered items, checkboxes,
source/native offset divergence from an escaped asterisk, direct storage
empty/refill edits, formatting, external storage changes, Undo/Redo and reload
under LF, CRLF and CR. Three focused owners pass, including the existing
interleaved paragraph owner. The matching full non-AI run completed265 tests:
260 passed and5 threw macOS Vision/E5 text-recognition errors. This is not a
green full-suite claim; the tests and OCR expectations remain unchanged.

Installed Time Profiler captures repeat performance226's500-row/~149KB fixtures,
paragraphs then list, with five native x keys and40s captures without AX reads,
builds or tests during recording. List keyDown running CPU sample weight fell
from89ms to61ms; full serialization samples fell from79ms to53ms. The paragraph
control stayed similar (37ms to39ms). These are single-run1ms inclusive CPU
samples, not input-to-frame latency or general responsiveness acceptance.
Both saved files exactly matched the original plus five characters; one Undo
and Save restored each original byte-for-byte.

An attempted follow-up deferred initial row qualification. The full suite's
existing interleaved owner caught24 assertions: refilling a previously empty
head could replace a source span containing its promoted tail. That attempt
was fully reverted. The retained implementation qualifies both when recording
and when editing. Initial export overhead remains a performance follow-up;
the results do not establish faster first-keystroke latency.

The profiled installed app's signature and bundled CLI were verified. Gallery
was also checked as collection-only, opening a card as note-only, and returning
as collection-only; folders hide entirely and restore. The owned fixture tabs
were closed and exact-hash-guarded files removed. All1008 baseline note/asset/
view bytes remain unchanged; Planning/List is restored. Evidence and the
rejected attempt are under artifacts/native-macos/performance227/.

No DMG, version bump, iOS implementation or AI work. Initial export cost,
other responsiveness bottlenecks, remaining structural/clipboard parity,
physical IME/accessibility, cross-client acceptance and final delivery remain
open. The overall migration goal remains active.

### Internal performance228 — exact single-pass list eligibility scan

The retained performance227 guards are unchanged apart from replacing three foreign-string
substring searches for U+2028, U+2029 and U+200B with one exact NSString
CharacterSet scan. Initial and edited-row ownership, nonempty-body, neighbor,
attribute, context and source-span checks remain. The rejected deferral from performance227
has not returned. No public rich admission or persistence format changes.

The prior installed list trace attributed 14 ms to the three contains searches
within qualification. A scratch optimized probe over the same foreign-string
rows checks equivalent results, including Unicode controls; it is a mechanism
probe, not installed latency evidence. No timing XCTest or predicate-mirroring
test was added. Existing hosted editor owners protect the real behavior.

All 96 editor tests, 29 clipboard tests and 3 focused owners pass. The full scoped
non-AI run completes 265 tests with 260 passes and the same 5 unexpected macOS
Vision/E5 text-recognition failures, with no assertion failures. Tests were
not skipped or weakened. The full suite remains non-green.

The verified installed Release app repeats performance227's matched 40s native typing
captures: 500 rows/~149KB per fixture, paragraphs then list, five native x keys,
no AX/build/test activity during recording. List keyDown CPU sample weight
moves 61 ms to 48 ms, full export 53 ms to 37 ms, and qualification 26 ms to 11 ms. The
paragraph control is similar at 39 ms to 41 ms. Overall main-thread samples include
autosave and refresh (179 ms to 175 ms), so this does not establish overall UI
latency. These are single-run 1 ms inclusive CPU samples, not input-to-frame or
first-keypress latency measurements.

Saved bytes exactly match the original plus five characters in both fixtures.
One native Undo and Save restores each original byte-for-byte. Both owned tabs
are closed, the exact-hash-guarded fixture files removed, and all 1008 baseline
note/asset/view files unchanged. Planning/List is restored. Signature and CLI
verification, frozen hashes, test logs, source originals, scratch probe, raw
traces and comparison evidence are under artifacts/native-macos/performance228/.

No DMG, version bump, iOS or AI change. Broader responsiveness, structural and
clipboard parity/admission, physical IME/accessibility, cross-client and final
packaged acceptance remain open. The migration goal remains active.

### Internal acceptance229–230 — real rich clipboard and standard plain paste

Actual TextEdit Copy/Paste exposed a gap that the hosted formatting checks did
not cover: separate Cocoa paragraphs were saved as Markdown soft lines. The
rich import boundary now normalizes LF, CRLF, CR and U+2029 to Markdown paragraph
separators while retaining U+2028 as an inline line break. It builds attributed
chunks in one pass, preserving formatting, links and attachment literals.

The existing RTFD owner gains four paragraph-ending rows with literal paragraph
text arrays from an independent swift-markdown parse, save/reopen checks and
Undo/Redo. Its paragraph assertions fail eight times before the repair and pass
afterward; existing bold/link/image/plain controls remain. A redundant Undo-
manager availability assertion was removed after the baseline; the causal
paragraph assertions are unchanged. No test-only production API was added.

Installed real-system-clipboard QA preserves ordinary paragraphs, bold, italic,
a link, Portuguese text and a 128×48 image. Native save/reopen retains the block
structure; one Undo restores the original note bytes and Redo restores the exact
pasted bytes without another import. Native Copy into a saved TextEdit RTFD
retains text order, font traits, link destination and all decoded image pixels.
Cocoa re-encodes the image, so pixel identity is claimed rather than original
PNG-file byte identity. This is one bounded rich passage, not all RTF list/table,
heading or resized-image support.

The final plain-paste control also exposed a missing user route: the handler
existed, but the app's Edit menu and standard shortcut did not invoke it.
Paste and Match Style is now exposed after the pasteboard group, using the
existing first-responder action and Command–Option–Shift–V. Both the actual menu
and shortcut strip the rich source's formatting, save the same exact plain
text, and undo in one step. No menu-inventory or source-grep XCTest was added;
real pre-fix failure and installed post-fix routing are recorded instead.
The exposed AX Cancel action also recovers the main window when Computer Use
stays focused on the Edit menu after Escape; no app relaunch is needed.

The final combined frozen-source gate passes all 265 non-AI tests with zero
failures, including 96 editor and 29 clipboard tests; the 13 AI/chat classes stay
deferred. Earlier intermittent Vision/E5 failures remain in their original logs,
and no permanent OS repair is claimed. The final Release app's signature and
bundled CLI were verified. Both owned notes, their native tabs and the two
imported images were removed with exact-byte/hash guards after preserving
artifacts. The TextEdit source is unchanged, its owned documents are closed,
and all 1008 baseline note/asset/view files remain byte-identical. Planning/List
is restored.

Evidence: artifacts/native-macos/acceptance229/ and acceptance230/. No DMG,
version bump, iOS implementation or AI work. Broader responsiveness, nested
container/clipboard admission, input/accessibility, cross-client and final
packaged acceptance remain open. The migration goal remains active.

### Internal compatibility231 — native/CLI copied-vault write and move cycle

A new disposable three-note vault is created through the verified bundled
CLI 0.3.1, using exact paths and generated note IDs. A BOM/CRLF external Markdown
input with unfamiliar YAML and a Status field is imported through the CLI;
the Work schema is created through its schema command. No reserved metadata or
shared settings are hand-edited. CLI commands use an explicit vault path,
JSON and no-input flags. No registry override exists, so the real registry is
read-only and hash-checked unchanged; the test vault is not registered. The
Zerus skill's revision-checked mutation workflow is followed.

A native x edit saves exactly and is read byte-for-byte by the CLI. The CLI
changes Status to Reviewed and appends a line using fresh returned revisions.
It relocates the selected Status field to the header end; after excluding that
changed field, the metadata and body bytes are exact. An initial harness
assertion incorrectly assumed fixed field position and was corrected to check
the actual preservation contract. Error JSON is emitted on stderr; an old
revision is refused with write_failed and the specific 'note changed since it
was read' message, and note bytes remain unchanged. No failed operation is
reported as a successful mutation.

The native app adopts the new body and Status without reopening. A second y
edit saves exactly while retaining all CLI changes, the BOM, CRLF and unfamiliar/
reserved metadata. Relative Markdown navigation and a CLI-created stable-ID
backlink both work. A native move into Work/Filed preserves the original note
ID and every source byte except the necessary ./Target.md → ../Target.md repair.
Both native navigation routes work after the move. The CLI finds the moved note
by its original ID, reads its exact bytes/properties, reports the stable-ID
backlink and returns a healthy three-note doctor result. CLI links covers body
wikilinks/relations; relative Markdown navigation is verified through native UI
rather than inferred from that command's outgoing list.

The unrelated anchor and shared schema stay byte-identical. The real registry
and all 1008 files in the original QA baseline remain unchanged. The test app
is returned to the original Planning/List workspace, and the final disposable
vault file set is preserved under compatibility231/Vault-final-copy with hashes.
No production or XCTest changes were needed, so the matching installed
acceptance230 receipt and 265-test pass remain applicable; no extra test run,
internal rebuild, DMG, version bump, iOS implementation or AI work was performed.

This checks ordinary note/property/file contracts against the native UI and
bundled CLI in an unregistered disposable vault. It does not establish web/iOS,
registered-vault setup, paired-relation, cross-client history/undo, file-provider
interruption or full sync acceptance. Evidence is under
artifacts/native-macos/compatibility231/. Broader migration goals remain active.


### Internal performance233 — coalesced collection-search preferences

A native Time Profiler capture of typing 0997 then four Backspaces in the
333-note Planning/List collection attributes 79 ms of inclusive main-thread
samples to synchronous navigation persistence, versus 25 ms to collection
filtering. The QA preferences domain has roughly 5,700 keys, so this is a bounded
finding rather than a general latency measurement.

Search membership still updates immediately. Only device-local navigation
preferences wait for a 250 ms typing pause. Other navigation, vault switches and
normal close flush the newest state. A new window flushes matching peers before
restoring preferences; a later action cancels an older pending write in the same
vault. The first deferred-write attempt failed two new owner assertions: stale
query on new-window restore and an older pending write replacing newer state.
Both pass after the boundary repair. The existing navigation owner also checks
rapid search, per-collection state and close/reopen without timing assertions or
new production test seams. Its 500 ms quiet interval permits the delayed job to
run; the asserted contract is the retained query, not performance.

The final combined gate completes 265 tests: 262 pass and three throw Vision/E5
runtime errors, with no assertion failures. A single isolated retry passes all
three affected footer, large-list/search and outline checks. The full-run status
remains non-green, and no tests or OCR expectations were skipped or weakened.

The verified internal Release app repeats the eight native keys in another
40-second capture without AX reads, tests or builds during recording. Total
main-thread running CPU samples are 357 ms before and 195 ms after. Persistence
appears in 79 ms of the earlier samples and none of the later samples; this does
not mean zero persistence cost. Sampling is 1 ms, key transport pacing is not
fixed, and inclusive stack categories overlap. This is not input-to-frame latency
or broad responsiveness acceptance.

Installed search finds only Performance note 0997, retains that query/result
after quit/reopen and clears back to all 333 notes. All 1,104 files in the current
owned QA baseline remain byte-identical, including the original 1,008-file set;
no file was added. Planning/List with empty query is restored. The app signature
and bundled CLI are verified, still 0.3.85/build125. No DMG, version bump, iOS or
AI implementation, public rich-admission widening or release publication.
Evidence, rejected attempt, logs, raw traces and source hashes are under
artifacts/native-macos/performance233/. Broader goal gates remain open.


### Internal acceptance234 — compact drawer navigation and focus

Installed QA at 600px/100% reproduced a toolbar defect: Browse notes changed the
underlying compact pane while leaving the inspector overlay open. The collection
remained covered, disabled and absent from AX. A single browsingCollection
observer now clears both temporary drawer states, complementing the existing
active-tab, selection and workspace observers. It does not change persistent
sidebar visibility or note content. No test seam or new XCTest was added; the
real installed toolbar route is the regression boundary for this reversible UI
change.

Three existing editor-identity/resize, zoom and navigation owners pass. The final
combined non-AI gate completes 265 tests with 262 passes and the same three
unexpected Vision/E5 runtime errors in footer, large-list/search and outline OCR
checks, with no assertion failures. It remains non-green. The isolated retry
recorded in performance233 predates this view change and is not relabeled as an
acceptance234 passing combined run. All 13 AI/chat classes remain deferred.

The internal Release app signature and bundled CLI are verified, still
0.3.85/build125. Its edge-resize attempt did not establish the requested size,
and one CUA attempt returned windowNotFoundAtPosition((958.0,704.0)). A native
macOS quarter-window action plus the supported 150% interface zoom reached the
single-column arrangement. There, Inspector → Browse notes closes the drawer,
exposes Search notes and 333 notes, and leaves the hidden editor out of AX.
Inspector → Return to note also closes it and exposes the native editor. Escape
returns focus to an editor caret established before opening the inspector.

The before-update 100% folders drawer likewise hid the editor in AX and returned
focus with Escape. These are bounded focus/overlay checks, not full keyboard
traversal, VoiceOver, dictation, physical IME or all resize acceptance. The
post-update physical-600px/100% route remains unverified; zoomed single-column QA
is recorded explicitly rather than presented as that exact geometry.

Zoom is restored to 100%, the pre-tiling wide window is restored, the QA-opened
Performance note0997 tab is closed, and Planning/List with an empty query is left
open. Folder hide/restore is checked in the updated app. All 1,104 baseline files
remain byte-identical, with none added. Tab overflow/reveal remains a follow-up
observation; no web behavior conclusion or implementation change was made there.

Evidence and source hashes: artifacts/native-macos/acceptance234/. No new DMG,
version bump, iOS/AI work, public rich-admission widening or release publication.
The broader migration and acceptance gates remain open.


### Internal acceptance235 — unresolved Vision oracle investigation

No production or test-source change is retained. The investigation traced the
recurring unexpected failures to Vision/E5 model loading, with missing generated
ANE model files in the app's cache. Files observed after short passing controls
disappeared during the combined run before PDFKit started; PDFKit alone therefore
was not established as the trigger. Five-test PDF/workspace controls and a
six-test appearance/PDF/workspace sequence pass, while the unchanged full run
continues to fail three screenshot oracles.

Two test-only CPU configurations were tried against the same pixel-based
oracles. Request-level compute-device introspection failed five screenshot checks.
Direct CPU selection passed seven focused checks but still failed the same three
checks in the combined run. Neither was retained. The three modified test files
were restored byte-for-byte, the temporary helper removed, the test project
regenerated and the original tests rebuilt. No fixture image, OCR region,
recognition setting, expected text, bounding-box assertion or test exclusion was
weakened in the final source.

The original 47 workspace tests pass in a fresh process. The other 218 tests
have 217 passes and one Vision InvalidTransition error in the calendar pixel
check. Execution-ID comparison proves these groups cover exactly the same 265
cases, with no overlap, extra or missing tests. The split attempt is still
non-green and is not presented as a passing replacement gate.

A first empty-cache move was stopped by a preflight when the controls had
regenerated real model files; nothing was moved in that attempt. After a later
run again left only empty generated directories, those were moved reversibly and
the original full suite rerun. It still completes 265 tests with 262 passes and
three unexpected E5 errors. The original cache state was restored, and the
rejected regenerated state is preserved in the diagnostic artifacts. This is not
an OS/framework repair or a production PDF/Live Text acceptance claim.

The installed acceptance234 app is unchanged; its signature, CLI and executable
hash are verified. Planning/List with an empty query and 333 notes is restored.
All 1,104 files in the owned QA baseline remain byte-identical, with none added.
No Release rebuild, DMG, version bump, iOS/AI implementation, source workaround
or public admission change. Artifact evidence, failed controls, cache metadata
and restored hashes are under artifacts/native-macos/acceptance235/.

Continue the unblocked workflow, performance and compatibility acceptance work.
Keep the monolithic Vision gate unresolved; do not repeat rejected CPU/cache
attempts or claim that an isolated pass establishes a reliable combined gate.


### Internal navigation236 — device-local pinned tabs

Current web source exposes Pin/Unpin tab, a pin marker and a hidden inline close
control, while explicit context Close remains available. Native lacked these
actions. Both clients currently use manual tab overflow, so automatic active-tab
scroll was not treated as an established web-parity defect or implemented here.

Native note/folder/global tabs now expose Pin/Unpin in the existing context menu.
Pins have a visible/accessibility-labeled marker and hide only the inline close
button; explicit context Close remains. Pinning neither activates nor reorders a
tab, and it does not change note frontmatter or the note's Pinned flag. The close
buttons for unpinned tabs now have descriptive names. Native's existing retained-
tab/opening policy remains; this is not a claim of complete web tab lifecycle or
keyboard/VoiceOver parity.

The optional pinnedTabs field lives in the existing per-vault, device-local
version-1 navigation preference. Missing legacy data decodes unpinned. Closing or
invalidating a tab prunes its pin, and existing note-move/external-rename/folder-
rename reconciliation remaps pins before obsolete paths can be pruned. A new
workspace feature owner exercises actual persistence, per-vault separation,
reorder, moves, folder and note renames, close/reopen and unchanged note bytes.
It also decodes a handwritten pre-feature preference. The existing external-
rename owner gains pin assertions. No production test-only API was added.

Two initial owner failures were fixture issues rather than product defects: the
first assumed All Notes preceded the startup-selected note, and the second wrote
a legacy preference over live models that may flush newer navigation. The final
reorder assertion checks adjacency, and legacy compatibility is checked at its
persisted-format decoder boundary. Real model reopen and per-vault restoration
remain in the owner. Twelve focused tests and the frozen combined non-AI gate
pass; the latter executes 266 tests with zero failures and the same 13 AI/chat
classes deferred. Earlier Vision failures are preserved, not relabeled as fixed.

The signed internal Release app and bundled CLI are verified, still
0.3.85/build125. Installed checks pin a folder and a note tab, verify their markers
and hidden close controls, and retain both across quit/reopen. Explicit context
Close removes the pinned QA note; reopening it is unpinned and its uniquely named
close button works. Unpin restores the folder close control. A second quit/reopen
confirms the temporary pins stay removed. Planning/List, empty query, 333 notes
and the original tab set are restored. All 1,104 vault files remain byte-identical,
with none added. No DMG, version bump, iOS/AI work or rich-admission widening.
Evidence and exact source hashes are under artifacts/native-macos/navigation236/.
Broader workflow, performance, compatibility, accessibility and delivery gates
remain open.

### Internal find237 — Find in Note keyboard and menu dispatch

Installed keyboard QA found that Command-F opens global search and Return opens
its selected result, but Command-Shift-F and View → Find in Note did nothing with
the editor focused. Both native routes sent `performFindPanelAction` without the
sender tag selecting `showFindInterface`. A shared production dispatcher now
supplies that action for the menu/responder route and the editor coordinator.
No shortcut-policy change or new tab-cycling shortcut was introduced.

`MacDocumentTests.testFindInNoteShowsNativeBarWithoutChangingContentOrSelection`
uses the hosted native editor in rich and Source modes. It checks visible native
Find UI while preserving attributed content, Markdown, selection and Undo state.
The pre-fix run fails four intended assertions (hidden bar and absent bar view,
in both modes); the repaired owner passes. There is no test-only production seam.

The combined non-AI run completed 267 tests: 264 passed, with three unexpected
Vision/E5 framework errors in footer word count, large-note-list and outline
checks. These are the same recorded acceptance235 failures; this run is **not a
passing combined gate**. No CPU/cache workaround, assertion change or extra test
exclusion was applied. All 13 AI/chat classes remain deferred.

The internal Release app built and passed local signature/CLI verification at
0.3.85/build125, with no DMG or version increment. Actual Computer Use verified:
Command-Shift-F opens and focuses Find; Paragraph 7 reports one rich-mode match;
Return selects it and Escape dismisses the bar. The View menu opens Find too.
Source-mode Paragraph 3 matching and dismissal work. Command-F still opens the
separate global search. The QA-added0997 tab was closed and Planning/List restored
with empty collection search,333 notes and no selected note. All1104 vault files
remain byte-identical, with no additions or removals. Evidence, hashes, logs and
app receipt are in artifacts/native-macos/find237/.

This verifies the repaired Find route, not complete keyboard, VoiceOver,
performance, IME or desktop parity. The latest packaged DMG still predates this
internal repair; no user retest is requested at this stage.

### Internal performance238 — measured Gallery layout investigation

This batch retained no production or test changes. One isolated installed switch
from Planning/List to the saved 333-note Research/Gallery used 303 ms sampled
main-thread CPU in a 40s, 1ms Time Profiler capture. A candidate that extracted the
card label into its own private SwiftUI view passed all 10 focused cover, selection,
layout and board checks, built successfully, and loaded the same Gallery. Its
isolated capture used 307 ms. This does not support a useful navigation improvement,
so the candidate was rejected and source restored byte-for-byte. The exact find237
installed executable was restored by verified hash, and Debug build-for-testing
was rebuilt from the restored source. No assertions or test exclusions changed.

These are single warmed captures per Release binary, not statistical or
input-to-frame measurements. No accessibility snapshots ran inside the isolated
captures. An earlier attempted eight-click capture stopped after one switch when
the accessibility tree changed; it also included snapshots and is discovery-only,
excluded from the comparison. Most sampled navigation work remains in layout;
card construction is a small fraction. The next investigation should address the
collection layout inventory and invalidation, not repeat this rejected extraction
or add more snippet caching without evidence.

The QA window is restored to Work/Planning, List, 333 notes and no selected note.
All 1104 vault files are unchanged with no additions or removals. No AI/iOS change,
version bump or DMG was made. The preceding combined 267-test gate still records
264 passes and 3 Vision/E5 framework errors; no new combined pass is claimed.
Evidence and the rejected candidate are under artifacts/native-macos/performance238/.

### Internal performance239 — viewport-driven progressive Gallery loading

Gallery now gives its grid an initial page of 40 cards and reveals further pages
when the loading footer enters the actual scroll viewport. It retains a Show
more notes fallback. Grouped galleries have independent page budgets while group
counts, card activation order, filtering and selection use the full collection.
Changing query/filter/workspace scope resets the page budget and scroll position.
The existing List implementation is unchanged. Special views still show either
the collection or the selected note, preserving the requested native behavior.

The new owner,
`MacWorkspaceTests.testGalleryLoadsMoreWithoutLimitingSelectionAndResetsForSearch`,
hosts the real workspace with 300 notes, grouped and ungrouped, at widths 900 and
1600. It checks bounded document extent, expansion through scrolling, result and
scroll resets, complete Select All after a bounded reset and unchanged note
bytes. The exact final test fails on the original unbounded source with 12
intended assertions in final-workspace-baseline-owner.log. It passes on the final
source. Geometry assertions describe the visible document inventory; there is no
timing XCTest, private predicate check or test-only production seam.

Installed QA caught a runtime edge that the hosted fixture did not reproduce:
appearance-driven loading could stall at 80 cards in a wide window. Giving only
the button a new identity did not fix it; moving the identity outside the
appearance handler restored loading but prefetched too much work and measured
worse. That approach was rejected. The retained implementation uses
onScrollVisibilityChange instead, so a footer mounted for prefetch does not load
another page. The fixture must not be described as proof against that runtime
edge. Actual wheel scrolling in the retained Release app automatically progressed
through 0728, 0617, 0512, 0386, 0260, 0140, 0029 to the final note 0002, without
pressing the fallback. That late card opened normally in the note-only view and
its temporary tab was closed. Command-A selected all 333 Research notes before
all pages were revealed; search for 0002 found one result and clearing it restored
333. These actions were repeated in the retained visibility build.

The isolated navigation workload is a warmed Planning/List to 333-note
Research/Gallery switch, with no accessibility observations during recording.
The original find237 app used 303 ms sampled main-thread CPU in performance238's
before-gallery capture. Two retained-build captures used 264 and 259 ms. The
appearance-driven candidate used 337 ms and was rejected. Each is a 40-second
Time Profiler capture with 1 ms running CPU sampling; there is one original and
two retained captures, not a statistical study. These observations show less
sampled work for this workload, not input-to-frame latency or a general app
speedup. Larger-vault, cold-start and broader interaction performance remain open.
The earlier failed multi-click discovery capture is excluded from comparison.

The final combined non-AI run completed all 268 tests with zero failures and
terminal exit 0 in visibility-desktop-tests.log. The source hashes match the
retained build. Earlier runs in this batch had Vision OCR InvalidTransition/E5
errors in Calendar, Appearance, footer, large-list and outline checks. Those
failures are preserved; this pass does not prove that framework reliability is
repaired. All 13 AI/chat classes remain deferred. The final focused run passed ten
of eleven checks with a Calendar OCR framework error, followed by the combined
pass covering that same test too. No exclusions or assertions were changed.

The retained internal Release app passes local signature and bundled CLI
verification at 0.3.85/build125. It remains installed in the owned QA app path.
The window is restored to Planning/List with 333 notes, empty query, no selected
note, no tab pins and no QA-added 0002 tab. All 1,104 vault files are byte-identical,
with no additions or removals. No version bump, DMG, iOS or AI implementation
change was made. Artifacts, rejected candidates, exact hashes, receipts and logs
are under artifacts/native-macos/performance239/.

A separate follow-up is now evidenced by the logs: the shared QA preferences
domain has grown beyond the platform's stated 4 MB limit. Investigate owned
fixture cleanup and stale test metadata without deleting unknown user preferences
or bookmarks. Broader accessibility-focus/layout cost, input/frame measurement,
IME and remaining parity/acceptance gates remain open. This is scoped progress,
not full migration or final-package acceptance.

### Internal performance240 — workspace fixture cleanup race

A read-only inventory confirmed that vault bookmarks and navigation data dominate
the app preferences domain. The existing workspace fixture already removed its
primary keys, but it did not settle warm reopened peer workspaces before that
removal. A controlled execution of the existing pinned-tab owner passed its
assertions yet left one new navigation key after process exit. Closing/checkpointing
all peers for the exact owned temporary root before preference cleanup prevents
the late write. The operation's original error is retained through teardown.

This changes only the private MacWorkspaceTests fixture helper: 13 lines added,
two removed, no production changes, assertions, skips or new tests. Test-audit's
boundary evidence is the actual persistent-domain key delta around an existing
fixture, rather than a new test of a test helper. The controlled run leaked one
key before and none after. All 49 workspace tests pass with zero added/removed
keys across the suite. The controlled fixture also passes after archival without
recreating any archived entry. The combined suite was not rerun for this private
helper-only change; the prior performance239 production gate remains 268 passes.
Manual diff review and git diff --check pass. The referenced check-changed script
and autoreview skill remain unavailable; no delegated/formal review is claimed.

Historical cleanup was intentionally narrower than the inventory. A dry-run plan
qualified 34 deleted fixtures using exact repository-defined names plus UUIDs,
the OS user temporary directory, failed bookmark resolution, a missing target,
matching path hashes and the verified /var system alias. Recent vaults were
excluded. Their bookmark/navigation entries, plus the exact controlled baseline
leak, totalled 69 keys. These were archived to a 0600 binary plist before per-key
removal. A preservation check confirmed every unselected entry was equal, and an
independent key inventory matched the plan exactly with no unexpected additions.
The restore utility was compiled/dry-run only; it refuses to overwrite any key
that has since reappeared. Unknown historical records were not pruned.

Binary plist serialization at the cleanup boundary measured 4,481,503 bytes
before and 4,427,822 after; the former was reconstructed only in memory from the
unchanged entries and exact backup. Both remain above 4 MiB. This is not a claim
that app responsiveness or the preferences-size problem is solved. The next
storage work must preserve unknown historical state rather than broaden deletion
based on guessed fixture ownership.

The existing performance239 app was explicitly reopened with the owned QA vault
and restored Planning/List, 333 notes, empty search and no selected note. Automatic
recent-vault restoration was not attempted: a read-only guard found that its first
entry did not identify the QA vault. The recent list was preserved by archival;
subsequent explicit QA opening updates it normally. All 1,104 vault files remain
byte-identical. No app rebuild, version bump, DMG, AI or iOS change was made.
Evidence, scripts, exact hashes and the private owned-entry backup are under
artifacts/native-macos/performance240/. Broader performance/parity and final
packaging remain open.


## access299 — native automation recovery and current app checks

Resetting the native automation session restored main-window accessibility access.
Opening Settings still closes the native pipe. The optimized internal Release app
built successfully and was signed/verified at 0.3.85/build 125; no DMG was made.

On an owned 1,000-note fixture, native underline saved with BOM, CRLF and foreign
metadata preserved, and Undo restored the original. Board navigation displayed
the board alone, opening a card displayed the note alone, and the folder sidebar
could be fully hidden and restored. The Work folder opened and Note 0999 showed
the expected Note 0998 backlink. These are functional checks, not frame-latency
measurements.

Four pointer drags left the board unchanged. Printable key presses and paste
also left the focused editor unchanged, despite successful accessibility actions.
Drag and IME acceptance therefore remain inconclusive; this evidence cannot
distinguish a product drag defect from automation input delivery. Quit via the
menu did not terminate the app, so the exact owned QA process was terminated
through the shell. All 1,006 original fixture files remained byte-identical.
Evidence: artifacts/native-macos/access299/verification.json. Settings access,
physical input delivery, broader parity/performance and final packaging remain
open; AI remains deferred.

## features417 — installed note-link lifecycle

The existing features414 internal signed Release app passed manual note-picker
query and Down/Up/Return selection, insertion Undo/Redo, and Escape dismissal.
The chosen destination title became the inserted label. Relative section and
styled multiline stable links opened Target A. The short fixture establishes
heading-target resolution, not precise heading scroll offset. Coordinate
right-click exposed Preview linked note; its title, path and Unicode excerpt were
correct, Close dismissed it, reopening worked and Open note navigated correctly.
Accessibility-index right-click did not reliably hit the link, so no product
failure is inferred from that input attempt.

The missing-link review's Cancel created no file. Create and open made the note
in Work with a unique valid UUID and displayed its Source backlink. Source kept
the exact bytes captured after the deliberate insertion; Target A, Target B and
the manifest stayed original. BOM, CRLF, foreign metadata and both original
relative/styled link spellings survived. Both app processes exited normally with
code 0. Restart restored Rich Source and followed the created link without another
creation prompt; every vault file hash stayed identical across restart.
Evidence: artifacts/native-macos/features417/verification.json and fixture snapshots.
No source changes, build, version bump, DMG, AI or iOS work was performed.
Physical IME/VoiceOver, two-window changes and hover timing remain unverified.

## settings416 — separate Settings scene also blocked by automation

The app-menu Settings window was tried separately from the previously failing
workspace Settings sheet. It also returned “Sky Computer Use native pipe closed
before response.” The prior service crash stack includes Array.remove(at:) in
SkyComputerUseService, not a Zerus crash. Every owned fixture file and captured
preference remained unchanged. The owned app process was terminated after those
checks; this was not a normal quit. No speculative product change was made.
Installed Settings/themes, relation repair and CLI setup remain pending through
this route. Evidence: artifacts/native-macos/settings416/verification.json.


## features418 — attachment Undo and inline file preview

Installed image management passed preview/Done, removal review/Cancel, removal of
one occurrence while retaining the shared file and peer note, and reviewed Undo
restoring the original note bytes. The import chooser's Cancel changed no original
files. An owned 800×500 PNG displayed correctly in the full image preview.

Two actual feature gaps were reproduced. Add file imported an image but editor
Undo was a no-op because the view changed the stored body outside the editor undo
transaction. It now posts a scoped attachment command with an exact source guard,
imports to a unique encoded asset path, and commits through the editor once.
The chooser retains its existing file-size behavior. Earlier edits and Undo
history survive. A stale chooser is rejected before writing; if the note changes
after an async resource write, the resource is retained with an explicit message.
The new owner fails with two intended Undo assertions on the extracted unfixed
behavior and passes after the repair in Rich and Source modes. All 30 clipboard
owners pass. The first harness attempt missed a required argument and failed to
compile; that is excluded from regression evidence.

The other gap was an ordinary local text-file link being treated as a note link.
Following a relative local non-Markdown resource now opens the existing leased
native preview after relative-note resolution. The extended heading/navigation
owner fails twice on the baseline and passes with the repair: encoded Unicode
paths, relative and vault-root spellings, unchanged unsaved draft/source bytes,
outside-path refusal and existing note/heading controls. One owner ran; a requested
nonexistent MacFileHubTests selection ran nothing and is not counted as evidence.

Installed verification on the signed optimized internal app confirms image
import, one Undo retaining an earlier text edit, another Undo reverting that edit,
and two Redos restoring both. Text-file import also supports Undo/Redo. After a
normal quit/restart, its inline link opens the native preview showing both lines
and café; Done returns to the unchanged Rich note. Every final vault hash is
identical across restart, preview and quit. All imported payloads match the owned
originals; the shared resource, control note, vault manifest, BOM and foreign
metadata stay intact. The baseline import had introduced LF into the original
CRLF body; this batch does not claim a uniformly CRLF body. Fixture IDs are legacy
non-UUID strings, so this establishes preservation, not identity migration.

Final Release build and app/CLI/updater signature verification pass; all three
installed processes quit normally with code 0. Version remains 0.3.85/build125.
No DMG, AI or iOS work was performed. Current web frontend and private proxy both
return 200. Evidence, source snapshots, exact hashes, tests and app receipts:
artifacts/native-macos/features418/. Final full non-AI aggregate verification,
provider/interrupted import failure cleanup, two-window resource edits and
physical IME/VoiceOver remain pending. The repository's check-changed script and
autoreview skill were unavailable; direct source review, diff checks and the
actual owner checks were used without claiming those unavailable gates ran.


## features419 — multipage exports and native print-to-PDF

The existing features418 signed internal app exports an owned BOM/CRLF note with
visible properties, an 800×500 image displayed at 360×225, 12 marked paragraphs,
a 45-row table and a 30-line code block through the actual PDF, Word and HTML save
dialogs. One chooser was cancelled while confirming a changed format; it created
no extra output. Choosing formats and observing the resulting sheet before Export
produced the correct filename/format. The original note, manifest and image stay
byte-identical throughout. No product/test change, build or DMG was needed.

The More → Print route prepares nine pages, opens the system print panel with All
9 Pages and no printer selected, and saves Print419.pdf through PDF → Save as PDF.
No physical job was sent. Cmd-P did not open the route in one attempt; keyboard
shortcut delivery is not accepted by this evidence. The print operation uses the
existing properties-excluded print document; export includes visible properties.
Zerus identity metadata is hidden in all four outputs.

All nine exported PDF pages are rendered and visually inspected, with page 3 also
checked at 144 dpi. The image, accents/currency, inline formatting, table cells,
page continuations and final code/prose are present without demonstrated clipping
or loss. Item identifiers and the Amount header wrap in the narrow PDF columns.
A layout-text search initially flagged wrapped identifiers; raw extraction plus
whitespace normalization proves every one of the 45 identifiers is present once.
Every paragraph start/end and code identifier also occurs once in PDF, print PDF,
DOCX and HTML. This is not an arbitrary-wide-table layout claim.

DOCX ZIP/XML contains the four-row property table, 46-row content table and one
embedded PNG. HTML contains the corresponding semantic tables and self-contained
image. Both images retain all original decoded pixels at 800×500. Native WebKit
safe preview visibly displays HTML properties/image, table and final code/prose.
Native Quick Look visibly renders the Word properties/image/styled prose, table
and ending. Direct Pages readback was blocked by its first-run software licence;
Pages was closed without accepting terms. Microsoft Word rendering is unverified.
Two owned readback assets and a Preview note were deliberately added to the QA
fixture; none of its original files changed. Both native app processes quit
normally with code 0. Evidence: artifacts/native-macos/features419/verification.json,
output-validation.json, PDF page rasters and decoded-image checks.

Provider failed/cancelled/interrupted writes, physical printer output, more
adversarial pagination and broader keyboard/accessibility remain separate gates.
There is no new full-suite, final-release, AI or iOS acceptance claim.


## features420 — native resize/overflow delivery limits

An owned copy of the collection fixture adds six long-titled notes. The installed
features418 app keeps a deliberate edit through opening those six notes and
returns its exact original bytes with Undo. Every original fixture file is exact
after normal Quit (exit 0). Native Window → Move & Resize → Left actually changes
the frame to 960-point half-screen. An earlier edge drag and zoom action leave
the full frame unchanged. A later tiled-window edge drag returns
windowNotFoundAtPosition((959.0, 1006.0)); a fresh AX read recovers. Direct physical
600-point acceptance is not established. Horizontal scroll over the tab viewport
also leaves the visible strip unchanged, so pointer delivery remains inconclusive.
No source/test change or speculative UI rewrite was made. Current native and web
tab strips both lack an activation-scroll hook; this batch does not silently
expand parity around that optional behavior. Evidence:
artifacts/native-macos/features420/verification.json.

## features421 — exact current non-AI aggregate attempt, not green

The current compiled bundle enumerates 283 enabled checks using the existing 13
AI-class deferrals. The five-process attempt executes every enabled identifier
exactly once, with no skipped/duplicate checks and unchanged compiled/source/test
inputs. Appearance (1), collection (5), the remaining feature group (219) and all
six separate OCR checks pass. Of 52 workspace checks, 51 pass and the middle-click
transport check fails. The total is 282/283; this is not a passing aggregate.

That test's hosted tab locator uses VNRecognizeTextRequest. A fresh single-test
process also fails, before its pointer assertions complete. The serialized
exception reports a missing directory under NativeTaskDrafts; nearby Vision E5
model-resource errors are present. This association is not proof of the exact
cause. No OS/model caches were deleted or changed manually, no product/test
assertions changed, and the failed result remains available. The six older OCR
checks subsequently pass; the new transport check still requires investigation.
The installed middle-click evidence in navigation394 is retained, but it does not
turn this automated failure green. No source edit, rebuild, version or DMG was
made for this attempt. Evidence: artifacts/native-macos/features421/
complete-non-ai-attempt.json, original and fresh result bundles, exact enumerated
identifiers, commands and frozen input hashes.


## features422 — corrected configuration, complete current non-AI pass

A temporary diagnostic around the middle-click test's VNRecognizeTextRequest
calls passes all four locators and all original pointer/save assertions. The
logging is removed afterward; the test file is restored byte-for-byte to the
features421 input. An isolated run of that original test then passes, followed
by its full workspace group. No assertion or product behavior was changed.

The copied features421 .xctestrun had made TestHostPath absolute but retained
__TESTROOT__ in dependent-product and testing-library paths, which resolve from
the copied configuration's new location. Features422 resolves every such token
against the canonical Products directory before relocation. This is a proven
runner-configuration defect; it does not prove the sole cause of the intermittent
Vision exception. No OS/model caches were manually changed. The earlier failures
remain available and are not relabelled as passes.

Fresh enumeration confirms the same 283 enabled identifiers and the same 13
AI-class deferrals. All 283 pass across five fresh processes: appearance (1),
collection (5), workspace excluding the six separately grouped OCR cases (52),
remaining feature owners (219), and the six OCR cases. Exact identifier sets,
zero skips/duplicates, terminal exit 0 for every process, and unchanged compiled
binaries/configuration/source/test inputs are verified. This supersedes the
features421 attempt as the current green aggregate, without claiming that the
older monolithic host issue is repaired. Evidence:
artifacts/native-macos/features422/complete-non-ai-coverage.json,
configuration-repair.json, verification.json, original/final test snapshots,
commands, result bundles and frozen input hashes.

No production change, new Release app, version bump, DMG, AI or iOS work was
performed. Installed physical-minimum/pointer delivery, Settings/CLI/repair access,
remaining editor/compatibility/input routes and production packaging stay in scope.

## features423/424 — bounded native-tool checks

Opening sidebar Settings followed only by a screenshot still closes the Sky
Computer Use native pipe. No accessibility-tree read was needed to trigger it.
All fixture files and eight captured preference values remained exact; the owned
QA process was terminated after verification (exit 143), not treated as a normal
quit or a product crash. Settings visual acceptance remains pending. Evidence:
`artifacts/native-macos/features423/verification.json`.

A distinct right-edge-center resize returned without changing the frame. Native
Window → Fill restored the wide layout, and the app quit normally (exit 0), with
all original fixture bytes intact. Physical 600-point pointer resize remains
unverified; this did not justify a product rewrite. Evidence:
`artifacts/native-macos/features424/verification.json`.

## features425 — native File → Print and Command-P

The note menu already printed, but File → Print and Command-P had no native
entry point. Both now capture the same current-draft snapshot as the note menu.
An open sheet cannot be replaced, busy/closing/editor-sheet states are refused,
and Gallery browsing cannot print the internally retained hidden note. Returning
to the note restores Print.

The existing export snapshot owner now checks Print against a real outside-edit
conflict: the captured visible draft is printed, later text and saved/outside
bodies are excluded, properties are omitted, and disk bytes are unchanged. It
also checks the Gallery transition and return to the note. The Gallery assertion
fails with the earlier guard (exit 65) and passes with the repair. Both focused
Print/export owners pass (2 checks, 0 failures). No test-only production seam
was added. The previous features422 aggregate predates this change.

The optimized internal app builds and its nested signatures verify. Installed
Command-P and File → Print open the correct one-page Print note sheet; Cancel
returns editor focus. Gallery shows Print disabled and Command-P leaves it
unchanged. Both owned app sessions quit normally (exit 0), and every original
fixture file remains byte-for-byte exact. No physical print job, version bump or
DMG was made. Frontend and private HTTPS preview both return 200. Evidence:
`artifacts/native-macos/features425/verification.json`.

## features426 — saved-link shared format and editing boundary

Web metadata/body owners create a saved link in an isolated real directory;
compiled native VaultFiles owners read it, change the URL and create a second
link; web owners read both and write a final annotation/URL; native owners read
the final result. IDs and links.json agree, native creation updates the index,
and annotations, foreign metadata, ordinary prose and a code example of the old
URL survive. This is module/owner execution on local files, not live web/Tauri
IPC or provider acceptance. The probe initially needed its Debug framework search
path corrected; those loader failures are not product failures.

Installed readback exposed the managed URL repeated inside the editor beneath
its separate URL bar. The Mac writing surface now removes only the managed
standalone paragraph and restores it when publishing edits; disk/export content
keeps it. Attach-file and code/table menu snapshots use the same editable body.
Metadata lookup refreshes with the saved baseline rather than reparsing it on
ordinary typing. Shared/iOS source is unchanged.

The existing saved-link lifecycle owner fails on the original implementation in
Rich and Source, then passes with the repair: editing saves exactly one managed
URL and retained metadata, Undo restores the annotation, and stale URL forms
remain refused. All 30 clipboard owners also pass. The code/table menu owner
adds a saved-link fixture and fails with its old transport on source mismatches;
the final range assertion reads the request's own captured source, avoiding an
out-of-bounds baseline assertion. Final lifecycle/menu/export owners pass (3), including the final baseline-metadata
lookup. The aggregate is not rerun for this change.

The optimized internal app and nested signatures verify. Installed annotations
Edit/Save/Undo retain exactly one managed URL, and code-sheet Save/Undo targets
the correct block. Add file imports the exact text payload and Undo restores the
original note. Rich/Source and restart hide only the managed URL, while ordinary
prose and the old URL in code stay visible. Switching to Control and back retains
the correct editing boundary. All original fixture files are exact after Undo;
every vault file is exact across normal restart. Three owned app processes quit
normally (exit 0). No live page was rendered, no external URL opened, and no
DMG/version/iOS change was made. Both private preview routes return 200. Evidence:
`artifacts/native-macos/features426/verification.json`.

URL normalization probe differences remain explicit: web canonicalizes
`http://127.1/` to `http://127.0.0.1/` and treats a path backslash as `/`; native
keeps the abbreviated host and encodes the backslash as `%5C`. The other tested
ordinary Unicode/space/default-port/dot-segment and invalid-scheme/port cases
agree. This is not a claim of complete WHATWG/Foundation URL equivalence.

## features427 — explicit app-wide desktop settings transfer

React/Tauri Settings → Editor can export a versioned JSON snapshot of appearance,
light/dark colours, named themes, dates, interface zoom, writing width/alignment,
code blocks and note-link shortcuts. The new transfer UI is enabled only in the
desktop Settings dialog; the shared legacy mobile editor-settings component
keeps it off by default. Its module loads only on Export. The file is an explicit
allowlist, excluding vault/account/connection state.

Native File → Import Desktop Settings reads and validates the chosen export,
then reviews its values before Apply. Cancel changes nothing. An exact snapshot
of the eight destination preference keys rejects stale review before any write.
Both palettes are updated, matching named themes are replaced once, and other
named themes, unrelated preferences and future native colour fields survive.
Invalid format/version/values/palettes, duplicate theme names and oversized input
are refused. This is a new feature, so absent-API compile failures are not used
as regression evidence.

The actual web export function writes a file accepted/applied by the compiled
native owner in an isolated preferences suite. Final native import/palette owners
pass (2); import plus saved-link lifecycle owners also pass (2). The two focused
web export tests and final TypeScript checks pass. The broader web run reports
709 passing tests and one existing skip, before the final desktop-only UI prop;
its transfer owner is unchanged. An attempted 4-test native appearance/export run
has one failure in Vision's E5 model loader (`InvalidTransition`); it is retained
and is not counted as green or as a demonstrated importer defect.

Installed review shows the exported values. Cancel preserves all eight captured
keys and editor focus/text. Apply produces the exact expected preferences,
light/dark palettes and named theme. The earlier note edit remains undoable;
Undo/Save restores its original BOM/CRLF/foreign metadata bytes. Normal restart
keeps imported settings and a readable note. Both app processes exit normally.
After QA the eight original native preference values are restored exactly.
The optimized internal app/nested signatures verify; no version, DMG or native
iOS change. Frontend, its transformed settings module and the private HTTPS route
return 200. Source/test hashes are frozen in features427.

Per-vault private navigation/default-folder state, the live web Export-button
interaction, provider transport, the general Settings Computer Use failure and
the final aggregate remain separate pending items. This does not duplicate the
companion's existing pin/archive migration or read a real companion profile.
Evidence: `artifacts/native-macos/features427/verification.json`.

## features428 — sibling folder ordering

React has sibling folder ordering; native previously rendered alphabetical
folders without an ordering control. Native folder context menus now offer Move
up/down. Subtrees remain together and cannot be reparented by an ordering drop.
The typed own-process drag includes the original workspace, inventory and order;
stale/cross-window/cross-vault/busy/sheet drops are refused. Ordering is stored
per vault on this Mac, apart from per-window tabs/filters, and peer windows adopt
it immediately. Rename remaps stored paths and Trash removes them. Inventory
ordering and sibling lookup are cached; ordinary text editing adds no ordering
scan. Existing complete sidebar hide/restore remains available.

Pinned current React tree/order functions match the root, child and after-target
native fixture expectations. Four final native owners pass: real NSItemProvider
round trip and ordering, peer/vault isolation, stale inventory/order, reopen,
rename/Trash/restore and exact Unicode identity. The earlier new cache failed two
Unicode assertions; the fixed cache invalidates on byte-spelling updates, row IDs
and lookup use bytes, and the old byte-spelling drag is refused. Distinct
byte-spelled paths keep distinct subtrees. This is not a pre-feature compile
failure being counted as a regression baseline.

Installed context-menu ordering works for roots and children, preserving collapse
state and editor Undo. Restart retains both order levels. One physical pointer
drag leaves order unchanged, so native routing remains unverified; typed provider
and owner checks are separate proof. The final byte-identity optimized app reads
back the saved order and hides/restores the entire folder sidebar without losing
it. All six original BOM/CRLF/foreign-metadata notes remain exact after Undo, and
every vault file is exact across restart/final readback. Three owned app processes
quit normally. The actual app declares the exported folder-transfer type as
public.data; internal app/nested signatures verify. No version/DMG/iOS change.
Private frontend/proxy routes return 200. Evidence:
`artifacts/native-macos/features428/verification.json`.

Per-vault preference transfer, physical pointer delivery and final aggregate and
distribution acceptance remain open. This completes an actual native feature gap,
not the full migration objective.

## features429 — saved-link URL identity

Mac saved links now use pinned WebURL 0.4.2 for browser-compatible HTTP(S)
parsing. Canonical address text stays separate from the Foundation URL used at
system boundaries. Numeric IPv4 aliases reuse the existing saved link; literal
backslashes become path separators; fragment braces keep browser spelling.
Existing records are not bulk-rewritten. The iOS branch retains its prior
Foundation behavior. Dependency licence and notice files ship in the Mac app.

The final baseline fails five assertions for the original numeric-host duplicate
and canonical-storage defects. Two Mac owner checks pass, including saved-link
editor lifecycle. All 75 cases run through the actual web normalizer and compiled
native normalizer agree, with no Foundation bridge refusals. Five iOS saved-link
tests pass; the exact simulator app is installed in the Device panel, and valid
form input enables Save before Cancel returns without creating a link.

The optimized signed internal Mac app passes creation/reuse, duplicate-update
refusal, path/fragment storage and normal restart. Duplicate creation and refused
updates change no vault file; every vault file stays exact across restart. No
page is loaded during these checks. Version numbers remain unchanged and no DMG
was made. Final aggregate and live cross-client/provider transport remain pending.
Evidence: `artifacts/native-macos/features429/verification.json`.

## features430 — per-vault desktop preference transfer

Desktop Export settings now includes the current vault’s default note folder,
folder order, keep-open choices and subtype visibility. It includes the vault
name and relative folder names, without its absolute path. App-wide-only files
remain supported. Native import displays source name and destination vault,
skips absent order/keep-open entries with a review message, and validates the
current vault and its preferences before writing any app-wide or vault value.
Imported subtype visibility also applies to unvisited folders; native per-folder
overrides remain available. Tabs, filters and editor buffers are retained.

Three web export checks and two native owners pass, including stale-review and
reactivated-vault refusal, preserved note bytes, current navigation and reopen.
Application TypeScript checks pass. The actual web export file is reviewed in
the installed optimized signed Mac app: Cancel leaves all eleven actual target
preference keys exact; Apply changes order and expands the kept folder; earlier
writing retains Undo; All Notes creation uses Work/Research. After normal restart,
order and expansion persist and Work excludes nested notes. All five original
BOM/CRLF notes remain exact after Undo, and all vault files are exact across restart.
Original app-wide preferences were restored after QA. The first cancellation
snapshot used a different Python path spelling and is superseded by the actual
vault-key snapshots. No iOS changes, version increment or DMG. Full aggregate,
companion metadata and broader cross-client/provider acceptance remain pending.
Evidence: `artifacts/native-macos/features430/verification.json`.

## features431 — compact first-block divider Return

Return before a compact list divider now creates a receiving sibling on the
requested side; the original divider, tail and child content retain an owning
item. Return after uses the ordinary list split and quoted receiving-child
paths. Marker widening shifts children and grandchildren in reverse order, and
the prepared graph is checked before the single editor commit. No normal typing
or serialization work was added. The mounted web reference’s compact-only
behavior can move typing to document end; native intentionally preserves text
and local item ownership rather than reproducing that bug.

The final regression baseline fails 72 assertions. Four current editor owners
pass, covering literal output, independent parser ownership, LF/CRLF, outer
quotes, 9→10 widening, selection and Undo/Redo, plus existing card continuation.
The optimized signed internal app passes compact before/after Return, Redo,
quoted preservation and numbered child/grandchild/peer re-indent. The earlier
quoted-empty-child repair is accepted installed. All four original BOM/CRLF
notes return byte-for-byte after Undo, and every vault file is exact across
normal restart. No iOS change, version increment or DMG. Numbered-list display,
broader paste/input, current aggregate and full release acceptance remain.
Evidence: `artifacts/native-macos/features431/verification.json`.

## features432 — complete current non-AI test gate

All 287 currently enabled non-AI checks pass in five fresh processes: appearance
2, collections 5, workspace 54, remaining non-OCR 220 and OCR 6. Exact test
identifiers match a fresh flat Xcode enumeration with no missing, skipped or
duplicate enabled tests. Source, test, package source, binary and test
configuration hashes remain unchanged throughout all five processes. The same
thirteen AI classes remain deferred. The first harness attempt consumed the
default hierarchical enumeration instead of flat output and ran no tests;
that input error was corrected without changing product code or test selection.

This supersedes the features422 aggregate for current integrated source, while
retaining its evidence and the earlier failure records. It does not certify
physical IME/VoiceOver/drag routing, live cross-client/provider transport or
production release delivery. No source changes, version increment or DMG.
Evidence: `artifacts/native-macos/features432/complete-non-ai-coverage.json`.

## features493 — native permission recovery

After the user enabled T3 Code control and screen capture, the alternate native
AX route succeeds against the exact installed notarized QA process. Settings
and CLI screens are now observable without the earlier Sky helper crash.
Installed CLI replacement review shows the real destination and Cancel returns
without installing. Relation repair completes an empty-fixture review and
Cancel returns. Light → Dark → System → Light updates the installed interface;
the original appearance is restored, Settings Done returns to the original note,
and every isolated vault file remains exact. This closes the access blocker,
not CLI installation/setup/export or nonempty relation-repair Apply acceptance.
No production source, build, version or DMG change. Evidence:
`artifacts/native-macos/features493/permission-recovery.json`.

Features493 follow-through accepts actual CLI export, metadata Apply and
registration Apply with independent bundled CLI readback. Registration Cancel
keeps the registry exact; temporary QA493 registration resolves correctly and
the original registry is restored after verification. Metadata adds only the
reviewed ID/readiness manifest and keeps other note/resource bytes exact.
A separate Foundation-isolated home verifies installed CLI Install, differing
executable detection without execution, Update Cancel and replacement with exact
bundled bytes/mode; the personal CLI stays unchanged. A nonempty relation repair
review lists the two changed notes and unresolved value, Cancel keeps the entire
fixture exact, and Apply changes only the reviewed schema/two notes while keeping
bodies, foreign schema/note data, unresolved and unrelated files. Normal quit and
reopen keep all repaired-vault bytes exact and recognize the CLI installation.
These installed CLI and repair routes no longer wait on access. Settings pane
and draft/multiwindow checks plus pointer/input acceptance remain separate.

## features494 — native pointer, minimum layout and keyboard acceptance

The user-authorized alternate native route delivers a real SwiftUI card drag
Draft → Done, changing only the note's exact Status bytes while retaining its
BOM, body and foreign metadata. Column drag into the target column body persists
No value / Done / Review / Draft; a prior header-to-header attempt made no change.
Sidebar folder drag saves Zulu / Alpha / Work, and tab drag moves Work before
Peer card. An actual window-edge drag reaches the 600-point minimum. Folders
hide/restore completely there, and horizontal pointer scrolling reveals overflow
tabs. Portuguese keyboard-layout dead acute plus e produces a single é; Save is
exact, one Undo/Save restores the original note bytes and Redo/Save restores the
composed text. Normal UI quit/reopen preserves the card/column/folder/tab state,
composition and every vault-file hash. These are synthetic native event checks,
not claims of human physical typing, dictation or VoiceOver spoken-output QA.
No production source/test/build/version/DMG change or repeated test suite.
Evidence: `artifacts/native-macos/features494/verification.json`.

## features495 — current-source, package and input-service audit

All 359 frozen gate inputs were checked again. The six differing iOS-only files
are absent from the Mac target; every Mac source/test, compiled artifact and
configuration input still matches the passing 303-check gate. The notarized
installed app executable/seal and exact previously mounted DMG remain unchanged.
Current strict app verification, app/DMG signatures, stapled tickets and
Gatekeeper assessment pass without a rebuild or new DMG. README and the native
guide now distinguish accepted Settings/CLI/repair/pointer routes from current
limits rather than presenting their historical tool failures as active blockers.

The Keyboard settings UI shows Dictation off and “No microphone was found.”
Independent system audio inventory exposes two output devices and no input
device. VoiceOver settings show it off. No OS input/accessibility toggle or
microphone access was changed. Spoken-output and recognition acceptance remain
unverified; a temporary VoiceOver toggle needs specific confirmation and actual
dictation needs an available microphone. Evidence: `features495/` current input
hash audit, audio inventory and package-verification receipt.

The final private handoff path is also checked: loopback and Tailscale HTTPS
HEAD return 200 for the existing 18,484,639-byte DMG, and a full private HTTPS
download hashes to `db89491d4c97684a0e60654b2d4e9d9b8671921dfb47242ae2be4474a9db790f`,
exactly matching the previously mounted/installed notarized package. The existing
private endpoint is reused; no Funnel, new port, app rebuild or package is made.
The VoiceOver confirmation remains pending and no OS toggle has been changed.

## Current scope correction — microphone dictation excluded

The user explicitly excludes microphone dictation from this goal. The historical
no-microphone finding is retained as evidence but is no longer a completion
requirement or blocker. VoiceOver spoken-output acceptance remains pending the
existing temporary-enable confirmation. The verified candidate and private
download remain prepared for final handoff.

## Current scope correction — VoiceOver QA excluded

The user explicitly excludes VoiceOver QA as well as microphone dictation from
this goal. Neither remains a completion gate, and neither is claimed verified.
The temporary-enable question is withdrawn; no OS accessibility setting changes
are needed. Historical input findings remain evidence only.

## Final agreed-scope acceptance

The agreed non-AI native macOS goal is accepted after the user's explicit
VoiceOver/dictation exclusions. The 25 workflow areas map to 77 installed/shared
format acceptance receipts in `features495/final-requirement-evidence.json`.
Current Mac source/test/compiled/configuration inputs match the 303 passing
non-AI checks. The configured Developer ID app and exact notarized DMG pass
current signature/ticket/Gatekeeper checks; the private HTTPS download matches
the accepted package hash. Features493–494 close the previous Settings/CLI/repair
and pointer/input gates. Final private handoff reuses the accepted build125 DMG.
AI remains deferred. Windows, direct Drive, microphone dictation and VoiceOver
QA are excluded; historical limitations are retained rather than claimed tested.
No public release, commit, tag, new app build or additional DMG is performed.

## themes496 — user-reported preset mismatch repair

The delivered build125 opened Colours on the Dark palette while Zerus was set
to Light on a dark-system Mac. Presets updated an inactive palette, appearing
to do nothing. Both the theme host and Colours now resolve Zerus's explicit
appearance before falling back to the system scheme. The inspector also uses
the palette surface instead of a hard-coded system background. The existing
real-settings/editor owner now exercises Light mode under a Dark environment;
it fails on the original code with the wrong preview background and missing
Light fields. All three appearance checks pass after the fix. The test fixture
uses a matching dark background so its later OCR Load action remains readable.
The final run uses an exact relocated compiled test host outside Documents to
avoid a loader-level protected-folder prompt; no broader file access is granted.
Build126 packages the correction. A new 303-check aggregate is not claimed.
Evidence: `artifacts/native-macos/themes496/` baseline/final result bundles,
source snapshot and packaging log.

The additional full-chrome correction selects Dark/Light when loading a complete preset or named palette and preserves the opposite palette. Its baseline failed six assertions before the repair. The final focused run passes all 12 appearance and presentation tests, including live native sheet/control appearance switching. The common sheet/popover wrapper explicitly applies the app appearance. Signed-app visual verification and the final package receipt are recorded under `artifacts/native-macos/themes496/`.

Final themes496 signed-app check: Paper selects Light; Midnight selects Dark; the full title bar/search/sidebar/list/editor/inspector appearance changes accordingly. Nested Settings/Colours remain Dark and choose the active palette after restart. The isolated note remains byte-exact. Build126 passes notarization/stapling/Gatekeeper and private-download SHA-256 verification (`final-verification.json`). No complete 303-test rerun is claimed for this focused patch.

Tabs497 keeps the existing tab strip above a collection whenever the editor pane is hidden. Live isolated native checks cover List/Table/Gallery/Kanban/Calendar, exactly one visible copy of three open tabs, note activation and return to the folder Table, with exact note bytes preserved. Both navigation/pane lifecycle owner tests pass. This change is newer than packaged build126; no additional DMG was produced.
