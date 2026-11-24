# Native list continuation implementation contract

This is outstanding migration work after preview 56, not a shipped feature.

The current native list commands in `MacMarkdown.swift` infer ownership from
visible source markers and indentation. `indentList` stops at an unmarked
nonblank paragraph; `toggleChecklist` changes only the caret paragraph. Simply
accepting indented prose or assigning each continuation the list marker would
split one Markdown item into several items, or strand its paragraphs when moved.

The next implementation must assign one item identity to all of its paragraphs,
retain the parent item identity for nested lists, and distinguish the first
marker-bearing paragraph from subsequent unmarked paragraphs. The source prefix
must be computed from marker width, including multi-digit ordered markers and
quote prefixes. Blank separators inside loose items must keep item ownership.
Original source tokens should remain available until that item is changed.

`artifacts/native-macos/list-continuation-contract.json` records the web parser's
actual item/paragraph ranges for bullet, multi-digit ordered and quoted lists.
In each example the parent owns two paragraphs and a child list; its sibling is a
separate item. The ordered example needs four spaces for the item body, whereas
the bullet example needs two. This structure is the independent save contract.

Implement rendering and serialization with the ownership model together, then
update Tab/Shift-Tab to move the entire item subtree, including continuation
paragraphs and separators. A caret in any paragraph must target that same item
for checkbox and indentation commands. Return must distinguish a new item from
an intentional continuation; empty Return must exit the appropriate list level.
Block-format changes and selection across item boundaries must not orphan
paragraphs. Cover these interactions at the existing native document test owner,
including Undo/Redo, then verify saved item structure with the web parser and
exercise the installed native app before delivering another DMG.

Keep code/table blocks and other unsupported embedded structures in source mode
until their own native container editing is implemented. Do not treat that
fallback as completion of editor parity.

## Development after preview 56

Soft-wrapped list paragraphs now render as a single native paragraph, with inline
styles parsed across source lines. The renderer retains the original multiline
source until the item changes; an edited item serializes as one portable Markdown
paragraph. This lets existing item indentation and Undo operate on the complete
wrapped text. Source gating accepts lazy and indented soft continuations, while
hard breaks and multiple paragraphs still require source editing.

The native document regression covers bullet, multi-digit ordered and quoted
items, cross-line bold formatting, editing, subtree indentation, parsed item count
and exact original-source restoration by Undo. The initial regression failed on
the previous renderer (`wrapped57-baseline.log`). An existing empty numbered-child
regression caught a parser ambiguity: a list-like line that CommonMark treats as
lazy prose must retain the existing physical-marker handling rather than collapse
into the parent. That case is excluded from the wrapped renderer. Final suite and
native UI verification are tracked separately; this change is not in preview 56.

The final native suite passes all 156 tests (`wrapped57-tests-final.log`, 18.248
seconds). Packaging remains pending. The
existing frontend and private `/app` proxy both responded HTTP 200 after this
implementation; preview 56 remains the latest downloadable DMG.

Native development app verification is complete for soft wrapping. Editing the
second physical source line and pressing Tab saved exactly the intended nested
item, leaving every other source byte intact. Native Undo restored the entire
original file byte for byte; Redo restored the same edit. The web dependency
`remark-parse` confirmed six items, the edited item's child depth and quoted item
scope in the actual saved file. Evidence: `wrapped57-ui-proof.json` and
`native-wrapped57-development.png`. The app remains open in a separate QA vault.
This is a development binary, not a new packaged DMG. Multiple paragraphs, hard
breaks and complete item ownership remain outstanding.

## Multiple paragraphs and hard breaks — development verification

The renderer now keeps consecutive item paragraphs before child lists inside one
native text-system paragraph, using internal line separators for Markdown hard
breaks and paragraph gaps. Serialization computes continuation indentation from
the current marker, so Tab moves both paragraphs and the child subtree together.
Paragraphs after a child list and embedded code/tables remain source-only.

All 157 tests pass (`loose57-tests-final.log`, 18.700 seconds). The new owning
native document case failed on the earlier renderer (`loose57-baseline.log`), then
passed for bullets, multi-digit ordered and quoted lists with two paragraphs, a
hard break, child indentation and Undo. The quoted fixture was corrected to use a
quote-prefixed blank separator: an unprefixed blank line ends that quote.

Actual native UI verification in `QA Loose Lists Vault` confirmed editing the
second paragraph, Tab indentation and toggling its checkbox from that paragraph.
The actual saved Markdown independently passes web-parser assertions for item
depths [0,1,2], paragraph counts [1,2,1], one hard break and the checked marker
(`loose57-saved.md`, `loose57-web-proof.json`).

A remaining fidelity bug was found in native UI Undo: after undoing text,
indentation and checkbox changes, content and structure return correctly but the
original `**bold`/`continued**` cross-line span is serialized as separate strong
runs on each line. The original source is `loose57-original.md`; the current QA
file reproduces the normalization. Unit Undo did not reproduce this exact native
attribute lifecycle. Investigate semantic signature stability across text-storage
attribute fragmentation before packaging; do not claim byte-exact Undo for this
new multi-paragraph feature yet. No new DMG was created.

## Undo fingerprint investigation

The original-token signature now merges adjacent runs with identical portable
formatting semantics rather than treating presentation-only attribute boundaries
as edits. The existing loose-item owner now includes checklists, checkbox Undo,
and a color change inside a formatted word. A partial-word color split reproduced
eight original-source failures before the fix (`undo57-fragment-baseline.log`);
all 157 tests then passed (`undo57-tests-final.log`, 19.612 seconds). An initial
whole-word color case did not reproduce the failure because its boundaries
already matched the formatting run; the final regression uses an interior range.

This fixes that independently reproduced invalidation, but does not yet resolve
the complete native UI Undo sequence. Repeating edit/Tab/checkbox/three Undos in
`QA List Undo Vault` still returns equivalent per-line bold markup instead of the
original cross-line span. An additional Undo makes no change. The code and tests
are passing, but native byte-exact Undo remains unverified/failing for this case;
no DMG should claim the feature is ready. Investigate native typing/paste and
restore attribute lifecycle versus the direct `insertText` test fixture next.

The remaining native Undo issue is now fixed. The diagnostic trace identified
AppKit's checkbox display-font trait (16384) as the mismatch. Fingerprints now
compare only bold/italic/monospace traits; a display-font regression failed before
the repair and the final 157 tests pass. Actual native Undo restores the complete
original file byte for byte; Redo restores the exact saved edit. See
`undo57-native-proof.json` and `undo57-glyph-tests-final.log`. Temporary diagnostic
code has been removed. Preview 57 packaging is the next handoff step.

## Opus 5.5 milestone review repairs

The requested Opus 5.5 review found structural failures at separator boundaries:
Return could leave an empty item before its continuation; typing/paste and partial
copy could leak U+2028; gating admitted marker-only first lines the renderer did
not own. Additional findings covered bare line-break commands, tab marker widths,
CRLF separators and missing interaction coverage. The first preview 57 DMG is
held in `artifacts/native-macos/review-rejected-preview57/` and is not a handoff.

Repairs trim internal separators when Return splits an item; serialize each
separator independently of attribute-run boundaries; clear separator attributes
from selection typing and plain paste; share list-paragraph admission between
gating and rendering; retain the paragraph's newline style; and preserve partial
copy paragraph breaks without a list prefix. Tab-bearing markers and item bodies
starting after a marker-only line currently use source mode, pending complete
native rendering of those structures. Inline-code coalescing now stops at native
separators, keeping code formatting on either side portable.

Regressions cover three Return boundaries, separator-overlapping selection and
plain paste, partial copy, the native line-break command, code formatting across a
gap, Shift-Tab and CRLF. The initial baseline reproduced 12 failures
(`opus57-baseline.log`); the additional code-span case reproduced a raw separator
(`opus57-code-baseline.log`). Final regression results and Opus re-review are
required before rebuilding and handing off this milestone. Installed UI
verification of the release binary also remains pending Computer Use app access.

Final repair verification: all 159 native tests pass
(`opus57-tests-final.log`, 20.196 seconds). Opus 5.5 re-review of the repairs is
running. The rejected first DMG has not been reintroduced to the download path;
a corrected DMG is pending re-review. Installed release UI validation still
requires Computer Use access to Zerus Native. Development-build UI proof remains
valid for the earlier Undo fix, not a claim that the release repairs were checked
interactively.

## Literal block markers and heading conversion repairs

Opus 5.5's second review found additional structure changes after separators:
escaped list/heading/setext text could become a real block, a heading's line-break
command repeated its prefix, and applying a heading to a loose item created two
headings. The owning native regression reproduced 11 failures
(`opus57-literals-baseline.log`). Serialization now protects every logical line's
block-leading punctuation, including numeric list delimiters and setext lines.
Hard breaks inside headings serialize as spaces. Changing a multi-paragraph item
to a heading merges its internal gaps to spaces in the attributed text itself,
retaining inline runs and native Undo snapshots rather than duplicating heading
levels. All 160 native tests pass (`opus57-literals-tests.log`, 20.250 seconds).

The rejected DMG remains withdrawn. A fresh Opus re-review is required before
rebuilding; installed-release UI verification remains pending app access. The
nonblocking single-separator visual-gap discrepancy from the review is still
tracked: deleting one separator can leave a one-line visual gap whose Markdown
still represents a paragraph gap. Complete composing input and editor acceptance
remain outstanding, as does native support for paragraphs after child lists.

## First-paragraph deletion and table-looking text repairs

Opus 5.5 confirmed the prior repairs and reproduced loss of item ownership when
the first paragraph was emptied, plus promotion of literal pipe/dash text to a
Markdown table. New regression tests failed 17 assertions on that code
(`opus57-leading-baseline.log`). Serialization now drops leading internal
separators from an otherwise empty item/quote body, promoting the remaining text
within the same item instead of emitting a marker-only line followed by a gap.
A delimiter-row-shaped logical line escapes its pipes and dashes, preserving
literal text and avoiding both table parsing and smart-dash display changes.

All 162 native tests pass (`opus57-leading-tests-verified.log`, 20.577 seconds).
Coverage includes selection deletion and repeated Backspace in bullet, ordered,
quoted and hard-break items with child lists, plus a literal table-looking row's
parse structure and reopen text. A fresh Opus re-review is still required before
DMG handoff; the first preview57 remains withdrawn. Lower-priority observations
from the review remain open: deeply space-indented literal text, trailing literal
hashes in headings, consecutive/trailing hard-break presentation, converting a
parent item with descendants to a quote, and the single-kind2 visual-gap mismatch.
Some predate this milestone; none are claims of completed full editor parity.

## Heading hash fidelity after preview 57

Development now distinguishes a heading's closing-marker syntax from literal
trailing hashes. Rendering a marked heading uses the parsed Heading node, so an
import such as `# Title ###` displays `Title`; its original source survives
unchanged or through Undo. A literal escaped hash remains visible, and edited
headings escape trailing hash runs so other Markdown clients retain the text.
This also applies to quoted headings, native line breaks normalized to spaces,
and loose-list-to-heading conversion.

The expanded owning regression failed 11 assertions before repair
(`heading58-full-baseline.log`), including imported closing markers and literal
hashes. All 163 native tests pass (`heading58-tests-final.log`, 20.589 seconds).
These are development changes after the delivered preview 57; no new DMG or
notarization was produced. Installed UI verification remains pending app access.
The old delegated review's background skill-search cleanup notification adds no
new finding and requires no command restart.

## Literal prose spacing and entity-looking text after preview 57

Native prose now retains leading and trailing spaces/tabs through generated
Markdown instead of accidentally becoming an indented code block or losing the
spacing when reopened. Generated numeric entities represent this literal spacing;
Markdown's explicit hard-break markers remain separate. Text typed literally as
`&#32;`, `&#9;`, `&amp;`, `&copy;` or a numeric hash entity is escaped before
serialization so it reopens as the same literal characters. Inline/fenced code
syntax is not subjected to this prose escaping, and source-mode indented code
continues to preserve its raw Markdown.

The new native owner regression exercises prose, loose-list continuations, quotes
and headings with leading/trailing spaces and tabs, parsing, source-mode choice,
reopen and Undo/Redo. It reproduced 21 failures before spacing repair
(`indent58-baseline.log`), 26 including entity-looking literals
(`indent58-entities-baseline.log`), and 12 for trailing spacing before that repair
(`indent58-trailing-baseline.log`). The earlier code insertion/paste goldens were
updated for the canonical entity representation of the newly split paragraphs'
boundary spaces, with stronger native reopen equality checks. Source-mode code
insertion still expects the original raw form. All 164 native tests pass
(`indent58-tests-complete.log`, 21.030 seconds).

These development changes, together with the heading closing/literal-hash fix,
are pending Opus 5.5 milestone review. Preview 57 remains the latest DMG. No new
package/notarization or installed UI proof accompanies this batch; Computer Use
app access remains unavailable.

## Literal milestone review follow-up

Opus 5.5 reported no blockers and identified two medium cases: a heading body
consisting only of seven or more hashes could become empty, and a whitespace-only
line could stop separating paragraphs after entity encoding. Native editor
regressions reproduced 12 failures (`literal58-review-baseline.log`). Hash runs
can now be escaped at the beginning of heading text as well as after whitespace;
a logical line consisting only of spaces/tabs stays raw structural Markdown.
Empty headings and marker-only items therefore stay empty rather than gaining
entity content.

The lower-priority nonsemantic-run and combining-mark cases were reproduced too:
a colour-only split between `&` and the rest of an entity-looking literal could
form an entity on save; a leading space combined with an accent could disappear.
Plain-text serialization now coalesces adjacent runs with identical Markdown
styles, stopping at links, literals, code and native separators. Boundary space/tab
encoding operates on Unicode scalars, preserving combining marks. The expanded
focused baseline failed 27 assertions (`literal58-hardening-baseline.log`).
All 165 native tests pass (`literal58-review-tests-final.log`, 21.404 seconds).
The gating table also verifies quoted indented code remains source-only.

Table-cell edge spaces intentionally retain their entity representation: visible
text preservation takes priority over shorter source. Existing heading fallback
for unsupported quoted code is not used in the editor because its source gate
rejects that structure. No new DMG or installed UI proof accompanies these small
review repairs; preview 57 remains current. Native appearance still needs seven
colour roles, separate light/dark palettes and saved themes to match the web
settings. The existing iOS palette implementation depends on UIKit traits, so it
cannot be imported directly into the AppKit target. The approved Mac default
palette must remain unchanged when custom appearance is added.


## List-type conversion prerequisite after Preview 68

The existing rich-text list formatter could detach children when a bullet became
an ordered item: `- Parent` needs two columns of continuation indentation, but
`1. Parent` needs three. It also replaced nested/quoted item prefixes with a
root-level prefix. This is an existing supported-list repair, separate from the
still-outstanding ownership of paragraphs after child lists.

List-type changes now retain the selected item's quotation and indentation.
Native marker-bearing paragraphs are paired in document order with the current
Markdown parser's list-item tree. Changes to marker padding propagate through
actual parent indexes; a selection containing both a parent and child composes
their padding changes once at each level. A count mismatch refuses the command.
This tree is rebuilt only for the format command, not for each keystroke.
Loose paragraphs represented inside an item use the new marker's continuation
width. Siblings outside the selected subtree retain their source tokens.
The native command retains the selection and records the whole change in Undo.

The initial indentation-only implementation passed its first 307-test run and
Opus read-only review, but further probes found a false-parent case:
`  - Parent` followed by `   - Sibling` contains two sibling items. Shifting the
second marker after changing the first to an ordered marker made it stop being
an item. `list79-ownership-baseline.log` reproduces that loss in the real editor.
A separate web-parser check agrees. Compact quote-prefix spellings need the
same tree-based correction; matching raw quote strings is insufficient.

The two owner regressions use real `NSTextView` editor commands, independently
written expected Markdown, and a CommonMark check of item depths. They cover
nested and quoted items, loose paragraphs, selected descendants, differently
indented siblings, compact quote spelling, zero/shrinking padding changes, the
next typed character, Undo/Redo and Undo selection restoration. Both regressions
fail against the original formatter (`list79-final-regression-baseline.log`).
`list79-tree-owned-document-tests.log` records 58 document tests passing on the
parser-owned repair. The final complete suite passes 307 Mac tests, zero
failures (`list79-tree-owned-full-tests.log`). A separate remark-parse check of
all nine expected outputs agrees on the original item depths
(`list79-web-parser-parity.log`). The second Opus 5.5 review found no new
corruption in the tree traversal itself, but identified an admission gap for
embedded code; the review repair is described below. These checks are not
installed-app release acceptance.

No source admission has been widened. Paragraphs after child lists, and code or
tables embedded in lists, still use source mode. Installed-app interaction,
keyboard/IME acceptance and full migration parity remain pending. Preview 68
does not contain this repair; no DMG was produced for this prerequisite alone.

The repair is limited to changes between list types. Removing an item marker to
make a heading/quote/plain paragraph, converting non-list paragraphs immediately
before indented lists, and reconciling ordered numbering/list delimiter families
need their own tree-aware command behavior. They are not fixed by this batch.


### Embedded-block admission review repair

The final read-only Opus review found that a fence indented inside an item could
be removed by card detection before the source-mode check examined its parent.
The same happened for an item-owned table. Such notes incorrectly opened in rich
mode, where the block card had no list ownership. The list-formatting command
could then detach the block and following children when marker width changed.

The source-mode decision now examines the original Markdown tree before removing
standalone card ranges. Code and tables below any container require source mode;
standalone blocks and literal list examples inside standalone code remain native.
This enforces the existing unsupported-container boundary, rather than adding
native editing for embedded blocks. The workspace-level regression opens eight
real notes and checks the selected mode and exact save bytes. Its baseline
(`list79-embedded-admission-baseline.log`) reproduces incorrect rich admission
for both item-owned fences and an item-owned table. The eight-case owner test
passes (`list79-embedded-admission-verified.log`). The final full suite passes
308 Mac tests, zero failures in 96.965 seconds
(`list79-reviewed-full-tests.log`). `list79-verification.json` records final
source hashes and separates superseded evidence. No further review delegate was
needed for this bounded admission repair. No iOS sources changed, and no new
DMG or installed-app acceptance is claimed.


## List 80: interleaved native representation, in development

Source-mode admission is intentionally unchanged in this batch. Notes with a
paragraph after a child list still open as source until container commands are
finished. This is implementation of the required rich representation, not a
completed parity milestone or a delivered feature.

The native representation now assigns an immutable `MacListContext` identity to
an item's marker paragraph and each later paragraph group separated by a child
list. The later groups keep their original separator spelling and render with
body-aligned layout, without literal indentation spaces or another visible
marker. Marker changes retain the identity; continuation serialization reads
the current marker paragraph's prefix, so changing marker width also updates
its trailing text. Original-token reuse checks the live prefix. Contexts are
local text-system attributes and are never written into note metadata.

A copied continuation without its marker paragraph becomes standalone text.
Native command commits refresh continuation layout with the head, and immutable
contexts travel with Undo snapshots. The renderer retains the existing per-line
fallback for marker-looking lazy continuation lines that are source-only; an
existing empty nested ordered-item Return fixture caught that compatibility
regression during the first owner-suite run and passes after that correction.

The new owner test drives the real native editor engine explicitly, while UI
admission stays guarded. Its baseline (`list80-context-baseline.log`) loses the
trailing paragraph from its parent after a text edit. With the representation,
bullets, multi-digit ordered items, quotes and checklists round-trip untouched,
keep trailing text with its item after edits and marker-width changes, retain
LF/CRLF spelling, support Undo/Redo, and copy the trailing text alone as plain
text. The 75 document/clipboard tests pass
(`list80-context-owner-verified.log`). The full suite passes 309 Mac tests,
zero failures (`list80-context-full-tests.log`). The Opus 5.5 review of frozen
core files is running; see `list80-verification.json`. These are engine checks,
not acceptance of the unfinished keyboard/container commands or installed UI.

Before admitting these documents in rich mode, finish all of the following:

- Return must create a new right-hand item identity and transfer following
  content when it creates a sibling, including marker-width boundaries.
- Tab/Shift-Tab and checkbox/type commands from any continuation must target the
  item's head. Outdenting a child before a parent-owned trailing paragraph must
  move the child outside the complete parent content, rather than accidentally
  making the trailing paragraph belong to that child.
- Block conversion and head deletion must retain the remaining tree. Partial
  clipboard selections across a removed parent marker need hierarchy-aware
  promotion; merely clearing the first prefix can leave four-column children
  looking like code or attach following text to a different item.
- Verify selection replacement, formatted/plain paste, mixed block selections,
  hard/paragraph breaks, nested ownership, IME and installed-app interaction.

No source-only boundary has been declared complete, no DMG was built for this
core stage, and Preview 68 remains the latest delivered artifact.


### Core review repairs and item-aware Return

The read-only core review found four defects. All were reproduced at the real
native editor boundary in `list80-review-baseline.log`, then repaired:

- Parsed checklist items no longer strip a bracketed body value such as `[x]`.
  Literal task syntax still present inside quotes is removed using the actual
  marker spelling and its complete whitespace run, not a fixed four characters.
- Inline formatting shortcuts retain list context and line-ending attributes.
  Formatting the first text in a trailing paragraph no longer drops its gap.
- Continuation serialization tracks list ownership at the boundary with a plain
  paragraph. Deleting visual spacing, or editing that continuation, cannot make
  the following plain paragraph a lazy list continuation. Inserted boundary
  separators retain CRLF where appropriate.

The 78 document/clipboard tests pass after those bounded review repairs
(`list80-reviewed-owner-tests.log`). No extra delegate was needed for the fixes.

Return now creates a fresh sibling identity when splitting a nonempty item head
or continuation. Only later continuation groups transfer to the new sibling;
content before the caret keeps its original owner. If the new ordered marker
needs more columns (for example, 9 to 10), only following actual descendants
shift. The shared `nativeListItems` parser mapping is used by both Return and the
list-type formatter. Splitting in front of body text that looks like a visible
marker must not delete that literal text: `settingBlock` removes an old marker
from the right fragment only when the fragment actually starts at the original
paragraph start.

The Return owner covers eight cases with both LF and CRLF, including quoted and
checked items, later child lists/trailing groups, a currently rich-admitted
9-to-10 case, literal bullet/numeric body text, Undo and Redo. The old behavior
fails in `list80-return-baseline.log`; a subsequent literal-text probe fails for
its intended reason in `list80-return-literal-baseline.log`. Final document and
clipboard validation passes 79 tests (`list80-return-reviewed-owner-tests.log`).
Three independent goldens also preserve their intended parent ownership with
the web CommonMark parser (`list80-return-web-parser.log`).

Final complete suite: 313 Mac tests, zero failures in
`list80-return-full-tests.log`. Source hashes and superseded evidence are tracked
in `list80-verification.json`. A new Opus review of the Return implementation is
running against a frozen snapshot. This does not complete the unfinished empty
continuation Return/exit, Tab/subtree movement, block conversion, head removal or
cross-boundary selection/paste work. Interleaved admission is still source-only;
there is no new DMG or installed acceptance claim.


### List 81: whole-item indentation and reviewed Return repair

Tab/Shift-Tab now operate on parsed item subtrees. A selection in a continuation
addresses its head; outdenting moves the complete subtree after all content of
the old parent. Remaining children and parent-owned trailing paragraphs keep
their owners. Ordered marker-width changes shift descendants, and the command
checks the resulting parent graph before committing. Compact quote prefixes
receive the separation required to preserve indentation. Unsafe unmatched
structures are refused without replacing the draft.

The Return review exposed a markerless descendant that grew during forward
replacement and invalidated later ranges. A native regression reproduces that
failure (`list80-return-index-baseline.log`). Descendants are now replaced in
reverse order; owner lookup uses position, and a width-changing split with an
unmatched tree refuses without changing source or caret.

Opus 5.5 reviewed the indentation milestone. Its three findings have native
regressions in `list81-review-baseline.log` and bounded repairs:

- Tight lists no longer acquire an unnecessary blank line on outdent.
- Remaining numbered siblings retain their original sublist start; width
  changes propagate to their descendants.
- Selected trailing blank paragraphs move with the item, so typing after a
  reorder cannot replace an unselected sibling.

The indentation table has 38 LF/CRLF scenarios plus a caret-at-EOF case. Final
validation passes all 316 Mac tests in `list81-reviewed-full-tests.log`.
`list81-reviewed-web-parser.log` independently checks the final tight-list and
numbering goldens. Mixed marker delimiters need no added blank lines in the
checked case; an earlier speculative golden requiring them was corrected after
both parsers disproved it. Structural reorders can add a terminal newline when
the former EOF paragraph needs separation from the moved item.

Fingerprints and superseded evidence are recorded in `list81-verification.json`.
Interleaved source admission remains guarded. Continuation checkbox/block
commands, head removal, shortcuts/paste identities and empty-tail Return still
need work. Native displayed ordered ordinals also need reconciliation separately
from raw Markdown marker spelling. No DMG or installed/IME acceptance is claimed;
Preview 68 remains the delivered artifact.


### List 82: continuation list commands (development)

Checkbox toggles and bullet/ordered/checklist commands from a continuation now
address the nearest preceding head with the same local item identity. Selected
head/tail targets are deduplicated. Marker-width changes still use parsed
parents to shift descendants; continuation selection and typing attributes
retain the owning identity after the command.

The real-editor regression fails before the repair in
`list82-tail-commands-baseline-final.log`: a tail toggle does nothing, while
list-type commands create a separate item from the trailing paragraph. The
initial eight LF/CRLF scenarios cover toggle, checklist, ordered and a quoted
nested conversion, exact saved Markdown, selection, Undo/Redo and subsequent
typing. All 83 document/clipboard tests and 317 Mac tests pass before review
(`list82-tail-commands-owner-tests.log`, `list82-tail-commands-full-tests.log`).
The web parser independently confirms parent identities and paragraph ownership
(`list82-web-parser.log`).

Opus 5.5 found a regression after non-list conversion of the head: the former
tail saves as plain prose but retains spacing context, so owner lookup refused
later list commands. The native regression reproduces that failure in
`list82-review-baseline.log`. A headless continuation now resolves to itself;
its spacing context remains available to the serializer until a new list head
replaces it. The helper comment no longer claims untested duplicate-paste
behavior. The expanded owner table has 36 scenarios, including collapsed-caret
typing, head-through-tail selection deduplication, and heading/quote conversion
followed by list formatting of the former tail. It passes in
`list82-review-fixed.log`. The final full suite passes 317 tests with zero
failures in `list82-reviewed-full-tests.log`; status and fingerprints are in
`list82-verification.json`. No extra review delegate was used for bounded fixes.

This does not cover non-list block conversion, shortcut/paste identities, head
removal or empty-tail Return. Interleaved documents remain source-only on normal
open. No installed-app acceptance or DMG is claimed.


### List 83: shortcut identity and numbered task fidelity (development)

Typing a checklist shortcut on an existing item now keeps its head identity, so
paragraphs after child lists remain owned by that item. Shortcut construction
uses the known empty prefix directly rather than parsing it as a new Markdown
fragment. This also keeps CRLF and avoids literal bracket text left by quoted
empty checklist parsing. Ordinary new-list and heading shortcuts retain their
existing behavior.

Numbered task markers are now recognized as a complete prefix. Native display
keeps the source number plus checkbox; Return increments that number and starts
the next task unchecked. Checkbox hit testing uses its glyph's offset within the
full marker. Raw source numbers are preserved; reconciliation with displayed
logical ordered-list ordinals remains a separate pending task.

`list83-shortcut-baseline.log` reproduces detached tails and numbered-task loss.
The first repair exposed CRLF and empty quoted-marker defects in
`list83-shortcut-first-fixed.log`; final focused tests pass in
`list83-shortcut-fixed.log`. The existing shortcut owner now covers 16 LF/CRLF,
checked/unchecked, bullet/numbered/quoted/compact-quote scenarios, with tail
ownership, subsequent typing and Undo/Redo checks. The Return owner adds a
numbered checked task crossing 9 to 10. The offscreen native zoom fixture checks
both bullet and numbered checkbox clicks at 80% and 150%; it does not prove
installed window event routing. All 83 document/clipboard tests pass in
`list83-owner-tests.log`. The pre-review full suite passes 317 tests, zero failures
(`list83-full-tests.log`). Independent GFM parsing confirms parent identities,
paragraph ownership and task states (`list83-web-parser.log`).

Opus 5.5 found no correctness regressions and identified bounded coverage and
robustness gaps. Those are closed without an extra review delegate:

- The pointer owner stops cleanly when a checkbox label is missing. Old-source
  Return and pointer failures are demonstrated in an isolated scratch project
  (`list83-return-pointer-final-baseline.log`), including quoted numbered tasks.
- Eight mixed-ending shortcut cases exercise new empty-paragraph/list-in-quote
  creation and `)` tasks. Inherited typing attributes reproduced the wrong
  terminator in `list83-mixed-endings-baseline.log`; shortcut construction now
  reads the actual replaced newline. They pass in
  `list83-mixed-endings-fixed.log`.
- Four quoted numbered Return cases and six pointer cases (three marker kinds
  at two zooms) pass in `list83-quoted-return-pointer-fixed.log`.
- The file-open owner confirms five-space task-looking code stays source-only
  for bullet, numbered and quoted containers, with exact content preservation
  (`list83-review-additional-tests.log`). The prefix parser is not the admission
  authority for embedded code.

The final full suite passes 317 tests, zero failures
(`list83-reviewed-full-tests.log`). Independent GFM parsing also confirms the
item-owned code interpretation (`list83-code-admission-web-parser.log`).
Exact status and source fingerprints are in `list83-verification.json`.

Normal interleaved admission is still guarded. Head removal/promotion, non-list
conversion, empty-tail Return and partial clipboard operations remain unfinished.
No new DMG or installed/IME acceptance is claimed; Preview 68 remains delivered.


### List 84: Backspace lifts a list wrapper (development)

Backspace at the start of an item's body, or deletion of its complete selected
visible marker, now performs a structural list command. Nested Backspace lifts
in place and adopts following siblings; Tab retains its whole-item move policy.
At the root, removing the wrapper keeps the head
text, promotes direct children, retains deeper ownership and turns the removed
item's trailing groups into independent paragraphs. Quotes stay quoted. Explicit
paragraph boundaries prevent text from joining a list or turning a numbered
child into prose, including when the lifted head is empty. A parser check must
confirm the remaining head-parent graph before commit.

The old editor leaves literal marker text behind; the real text-system owner
reproduces this in `list84-lift-baseline.log`. Empty-head typing absorbs a
numbered child without a separator (`list84-empty-head-baseline.log`). A quoted
empty task also exposed literal marker text left by the renderer
(`list84-empty-quoted-task-baseline.log`); its first task syntax is now stripped
even when cmark trims the final space. Literal task-looking body text remains
covered by the earlier checklist owner.

The final lift owner covers 42 scenarios across LF/CRLF, root/nested items,
selected markers/collapsed carets, wide numbered/checklist prefixes, previous
siblings, quotes and compact quotes, grandchildren, inline formatting, hard and
paragraph breaks, and empty heads. It checks exact Markdown, caret, command
Undo/Redo and subsequent typing. The empty-head test verifies command Undo/Redo
before typing, avoiding an extra grouping assumption about two edits made in one
synchronous test event. All 84 document/clipboard tests pass
(`list84-final-owner-tests.log`). Independent GFM parsing confirms the intended
new parent identities and standalone paragraphs (`list84-web-parser.log`). The
pre-review full suite passes 318 tests, zero failures (`list84-full-tests.log`).

Opus 5.5 found two refusals and an ordering-parity question. Native regressions
reproduce them in `list84-review-baseline.log`. Empty final rows now use the
existing outdent recovery; promoted children retain the root list's 1–3-space
base indentation so later siblings cannot become their children. Actual Lexical
`collapseAtStart` plus the MDX list exporters confirm that tight nested
Backspace lifts in place and makes later peers children of the lifted item
(`list84-lexical-mdx-parity.log`). The native Backspace path now follows that
policy while Tab keeps its existing move policy. Existing parent-owned trailing
paragraphs keep their owners; when necessary that content precedes the lifted
block rather than being attached to the new item.

The expanded lift owner has 90 scenarios. Additional coverage includes empty
middle heads, direct render/round-trip/typing checks for empty quoted tasks, a
literal EOF bracket value, loose lists and promoted-list merging. The empty
middle test exposed a missing leading boundary and then a CRLF separator read
from the wrong character; both are repaired. Old empty-task render failures are
proven in a scratch copy (`list84-empty-task-render-baseline.log`). All 84
current document/clipboard tests pass (`list84-reviewed-final-owner-tests.log`).
Web parsing confirms the repaired parent graph and retained paragraph owners
(`list84-reviewed-web-parser.log`). The final full suite passes 318 tests,
zero failures (`list84-reviewed-full-tests.log`). Fingerprints and exact evidence are in
`list84-verification.json`. No extra delegate was used for bounded repairs.

This removes a marker/wrapper while retaining head text. Deleting a complete
head paragraph, arbitrary selection replacement, non-list format commands and
empty-tail Return are still unfinished. Normal interleaved admission remains
source-only. No new DMG or installed/IME acceptance is claimed.


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
command exit status 0. Opus 5.5 review is complete; exact fingerprints and status
are in `list88-verification.json`.

Arbitrary replacement, broader paste ownership and raw-number/displayed-ordinal
reconciliation remain unfinished. A zero-length style is carried as typing
state until text is entered; persisted empty-style fidelity still needs audit.
Normal interleaved admission, unsupported containers and installed/IME acceptance
remain pending. No new DMG is claimed; Preview 68 remains delivered.


The bounded list88 review repairs restore local heading/quote/paragraph actions
when an unrelated list cannot be mapped. A selected list-owned paragraph still
refuses with a formatting-specific message and leaves text and selection intact.
Quote replaces the requested quote depth instead of nesting an already-quoted
item. Collapsed-caret typing inherits the preceding inline style from fresh
attributes; it never copies an image attachment or literal identity.

The extended owner covers 59 formatting actions/scenarios, including LF/CRLF
quoted Quote, quote EOF Paragraph idempotence, safe and refused unmapped-list
actions, caret typing before links/code/images and within bold/italic, and a
reindented child tail containing inline formatting. All 88 document/clipboard
tests pass (`list88-reviewed-owner-tests.log`). Independent CommonMark checks
confirm the quoted block order and that newly typed text stays outside inline
objects (`list88-reviewed-web-parser.log`). A proposed extra separator before a
promoted ordered sibling was disproven by both native and CommonMark parsers:
the two marker kinds already start separate lists. No separator retry remains.

Recoverable empty-marker mapping still establishes boundaries for empty markers
throughout the document. This is an explicit recovery policy, not a guarantee of
byte preservation outside the selection. Selective autosave normalization and
source-line ownership validation remain unfinished. The reviewed full-suite
result is recorded separately in `list88-verification.json`; the earlier 322-test
pass predates these repairs. No new DMG or installed acceptance is claimed.

The reviewed list88 full suite passes 322 tests, zero failures, command exit 0
(`list88-reviewed-full-tests.log`). This covers the final bounded repairs.


### List 89: selective empty-item recovery (development)

Structural commands and copy now pair native list heads with the exact source
lines emitted by the serializer, in addition to checking item count and preorder.
The provenance follows original-token reuse, LF/CRLF, logical line breaks, quote
gaps and code/table output; it does not change serialized text by itself.

Empty-item recovery adds a boundary only where a native empty head is absent
from the parsed source item starts. Already-valid empty siblings retain their
spacing when another empty child needs repair. The existing formatting owner
now includes LF/CRLF cases that fail on the prior code for the extra blank line
(`list89-selective-baseline.log`) and pass after repair. Undo/Redo, typing and
independent parser ownership remain checked. All 88 document/clipboard tests
pass (`list89-selective-owner-tests.log`); the final full suite and frozen-source
Opus review are tracked in `list89-verification.json`.

This narrows list88's document-wide recovery policy. It does not yet normalize
every native empty marker during autosave. Normal rich admission, arbitrary
replacement, broader paste, installed acceptance and a new DMG remain pending.

The list89 full suite passes 322 tests with zero failures, command exit 0
(`list89-selective-full-tests.log`). Opus 5.5 review of the frozen sources is
pending. Automatic empty-marker autosave normalization remains separate work;
normal rich admission and installed/IME acceptance are unchanged.


Opus 5.5 found no list89 regression and confirmed the final 322-test pass. Its
low-severity CR edge case is repaired without another delegate. Source counting
now treats CRLF as one newline (even across appended chunks) and bare CR as one
newline. A regression with a preserved code-body CR first reproduced refusal;
enabling that mapping exposed a pre-existing render grouping offset that showed
Parent in place of Child. Code-card bodies are now opaque to that LF-based
grouping parse, while the card retains its exact original bytes. The list-type
owner checks the displayed child, rewritten source, Undo/Redo and subsequent
typing. All 88 document/clipboard tests pass after both repairs
(`list89-reviewed-final-owner-tests.log`). The final full rerun is recorded in
`list89-verification.json`. Bare-CR-only note tokenization remains separate work;
this repair covers lone CR inside an otherwise LF-delimited native code card.

The final bounded list89 repairs pass the full suite: 322 tests, zero failures,
command exit 0 (`list89-reviewed-full-tests.log`). No further delegate was used.


### List 90: edited empty-head autosave fidelity (development)

Erasing an item's body now preserves that native head in the published Markdown
without waiting for another structural command. A quote-aware export boundary
is added only when a changed visible marker-only head is absent from parser
item starts. The serializer updates source-line provenance so subsequent
commands see the same item graph as the saved document. Unchanged original
tokens are not candidates. The source-only separator does not add native blank
rows or move the caret, and filling the item again before reopening restores tight spacing.

The real-editor owner covers 18 LF/CRLF cases, including quoted/numbered/task
items, an empty head with children, EOF and a root marker after prose. It checks
published source, parser parents, reopening, Undo/Redo/caret and refilling; four
controls preserve unchanged imported tokens. Its baseline fails on the missing
empty items (`list90-autosave-baseline.log`). All 89 document/clipboard tests pass
(`list90-autosave-final-owner-tests.log`). Independent CommonMark checks confirm
the 18 source spellings and a tight root list after an empty child is outdented
(`list90-autosave-web-parser.log`). An existing CRLF exit case caught the now
reachable EOF marker's missing terminator metadata; the lift boundary now uses
the preceding newline. No caret or Undo checks were removed.

The full run and Opus 5.5 review are recorded in `list90-verification.json`.
Edited empty markers use a conditional parse of their containing item context.
Ordinary paragraphs and top-level cards delimit that context; owned tails do not.
No extra parse is added to ordinary nonempty/no-candidate documents. Very large
single-item contexts still need end-to-end responsiveness acceptance. Markerless/partial markers, arbitrary range
replacement, broader paste, full bare-CR tokenization, normal interleaved rich
admission and installed/IME acceptance remain unfinished. No new DMG is claimed.

The list90 full suite passes 323 tests, zero failures, command exit 0
(`list90-autosave-full-tests.log`). The frozen-source review remains pending.


The list90 review reproduced a nested-empty-chain defect: adding all missing
boundaries at once could close an empty parent before its child. Recovery now
adds one boundary and re-parses before considering another. The same planner
chooses physical recovery locations, so copied/deleted lists use the corrected
rule as well. Six chain regressions fail for the intended parent mismatch in
`list90-chain-owner-baseline.log`; the expanded owner covers 44 autosave cases,
including code-body CR preludes and independent root/quoted item contexts.
Undo for the two body deletions models separate input events in the XCTest
host; no production Undo hook was added. All 89 document/clipboard tests pass
(`list90-reviewed-verified-owner-tests.log`), and the final full suite passes
323 tests, zero failures, command exit 0 (`list90-reviewed-full-tests.log`).
No extra delegate was used for these bounded repairs.

The tight-refill guarantee applies within the same editing session. Reopening
preserves the saved separator as imported source. While empty, CommonMark can
render that list loose; this is the spelling needed to preserve the empty item.
Noncanonical marker-padding transitions still need an explicit parent-metadata
audit, alongside arbitrary replacement and broader paste. The root-list test's
child-count message now claims only two root items; exact spelling and a separate
CommonMark tightness check carry the spacing proof.

The parser-only scratch benchmark measured about 188 ms for a 1 MB note versus
about 0.02 ms for the 68-byte affected context (`list90-scoped-parser-cost.log`).
This is not an installed typing benchmark. A larger serializer probe exposed
separate pre-existing Foundation range scans; their repair is tracked as list91.


### List 91: serializer attribute-range performance (development)

The serializer now checks whether code, table or source-token attributes exist
before asking Foundation for their longest effective range. Absent attributes
previously caused a whole-document scan at every paragraph. The range queries
remain unchanged for actual cards and source tokens. A CPU sample identifies
those Foundation scans (`list91-serializer-sample.txt`); this is separate from
the conditional empty-head parser work repaired in list90.

A scratch Release executable compiles the actual render/serialize core and
MacBlockPrefix with unused image/card/reference dependencies stubbed. Complete
output is asserted. At 4,000 paragraphs the same serializer input goes from
19,116 ms to 175 ms; 500 paragraphs go from 333 ms to 22 ms. The repaired path
takes 961 ms at 20,000 paragraphs (`list91-before-serializer-cost.log`,
`list91-after-serializer-cost.log`). These are source-core microbenchmarks, not
installed typing latency. Whole-document export/signature work remains linear
and still needs incremental handling before large-note responsiveness acceptance.

All 89 document/clipboard owners pass (`list91-serializer-owner-tests.log`).
Opus 5.5 found no defect in the three presence checks and confirmed that the
existing owners cover actual cards, reusable tokens, source stability and Undo.
No timing XCTest or production test hook was added for the equivalence change.
The full-suite result and exact frozen source are in `list91-verification.json`.
No new admission, DMG, installed UI or full-parity claim is made.

The final list91 full suite passes 323 tests with zero failures, command exit 0
(`list91-serializer-full-tests.log`). The frozen three-condition change is the
source reviewed by Opus 5.5.


### List 92: body edits and first-child gap ownership (development)

Ordinary body edits now capture the actual before-edit parent graph when the
item crosses an empty first source line. Noncanonical marker padding is
canonicalized and true descendants move by the content-column difference;
root or same-container siblings keep their original ownership. A local list
region is used when an unrelated temporary row cannot be mapped. Canonical
nonempty insertion remains on the normal AppKit path, and edits that keep a
body nonempty do not copy or parse the whole document for this repair.

A blank paragraph before an item's first child keeps its native text and an
immutable parent/child affinity. Export omits that source gap while the parent
has no emitted content, then restores it on same-session refill. Structural
commands rebind the affinity, and Return transfers it to the new right sibling.
Parser-known imported empty children remain eligible for presence protection
when their parent is filled. Cached multiline root prose now receives the same
lazy-continuation boundary protection as uncached prose.

The extended body-edit and Return owners cover LF/CRLF, quoted and numbered
items, checklists as controls, parent/child/grandchild chains, independent root
siblings, source reuse around opaque code cards, delete-then-refill, and an
unrelated unmappable region. Expected Markdown is handwritten and ownership
comes from swift-markdown. Baseline failures and frozen sources are retained
under `artifacts/native-macos/list92-review/`; final evidence is recorded in
`list92-verification.json`. Review/full verification remain in progress until
that record reports completion.

This does not admit interleaved notes normally. After-child continuations that
become leading paragraphs after structural removal, arbitrary replacement,
broader paste, partial/markerless rows, incremental serialization and installed
IME acceptance remain separate work. No new package or full-parity claim.


The list92 Opus review found no data-corrupting path, but identified refusal
when clearing a parent before deleting its first child, plus stale gap tags
when another region was temporarily unmappable. Prepared structural output now
rebinds existing gaps from its explicitly planned graph before validation.
Body edits do the same from their captured before-edit graph. A head deletion
can use the checked local region when the whole note cannot be mapped.

The extended owner runs both edit orders with and without the unrelated
markerless row, for LF and CRLF. It fails 12 assertions before this bounded
repair (`list92-review-orders-baseline.log`) and passes after it. The 89 owner
checks pass in `list92-reviewed-owner-tests.log`; the full rerun is recorded
in `list92-reviewed-full-tests.log` and `list92-verification.json`.

The review's proposed multi-paragraph import/rebinding spacing discrepancy was
also checked with an explicit `Parent / More / blank / Child` source row. It
passes without changing the source rule: the complete leading paragraph group
occupies one native paragraph, and the gap after that group remains present
after head-text deletion, refill and Undo/Redo. This is distinct from a tail
after a removed child becoming leading, which remains the next milestone.

Final list92 verification: 323 Mac tests passed, zero failures, command exit 0
(`list92-reviewed-full-tests.log`); final source hashes match the verification
record. No admission, package, installed UI or IME acceptance claim.


Final list92 verification: `list92-reviewed-full-tests.log` reports 323 tests,
zero failures and command exit 0. The final frozen source hashes are recorded
in `list92-review/final-source-hashes.json` and `list92-verification.json`.
The sidebar remains fully hideable. Preview 68 is unchanged; this source is
not yet a newly packaged or installed-accepted build.


### List 93: a former tail becoming the first body (development)

Removing an item's last child can leave a former tail before all remaining
children. When its head is empty, the serializer promotes that owned paragraph
onto the marker line. Native head text, blank rows and the tail's source gap
remain available for Undo, selection and refill. A paragraph records whether
it originally followed a child list; this allows promotion after deleting a
child of an imported empty head without normalizing untouched imports whose
first paragraph already begins on a later line.

The Opus review found a new task-syntax conversion and two older variants of
the same orphaning flow. All three are repaired here. Promoted literal [ ],
[x] and [X] text is escaped, preserving its text rather than creating a
checkbox. Promotion also crosses retained blank native rows. Checklist heads
remain excluded. Return and nested head deletion preserve the immutable
paragraph provenance in their Undo snapshots and ownership transfers.

The existing interleaved-paragraph owner now has 100 promotion cases and three
unchanged-import controls. It covers root, nested, numbered and quoted items,
compact quotes, LF/CRLF, empty/four-space/imported-empty heads, loose gaps,
literal task-looking text, one/two body paragraphs and a later child. It checks
real native edits, exact source, independent swift-markdown paragraph contents,
reopen, Undo/Redo selection and refill. The final pre-repair baseline fails 256
assertions for the intended source/ownership failures
(list93-final-variants-baseline.log); the repaired owner passes
(list93-final-variants-owner-tests.log).

The final full Mac run passes 323 tests with zero failures, command exit 0
(list93-reviewed-full-tests.log). Final source snapshots and hashes are in
list93-review/FINAL-*, final-source-hashes.json and list93-verification.json.
The review was code reading plus an independent parser probe; installed UI and
IME were not exercised. The normal interleaved admission guard remains in
place. Arbitrary range replacement, broader paste, partial markers, incremental
serialization, full parity and a new DMG remain separate work. Preview 68 is
unchanged, and the folder sidebar remains fully hideable.


### List 94: selection replacement and Cut (development)

Body-to-body replacement across native paragraphs now keeps the starting
paragraph and merges the ending paragraph's suffix into it. Surviving children
and tails of removed item wrappers follow the starting item; a prose start
promotes those children to roots and leaves later body paragraphs as independent
prose inside the starting quote container. A headless probe runs the actual
pinned Lexical 0.48 list registration and MDX import/export visitors, establishing
these surviving-parent rules for ordinary lists. It does not prove installed UI.

The native transaction captures the before-edit graph, normalizes only the
merged paragraph and affected prefixes, transfers first-child gap ownership,
repairs marker-padding-driven peer adoption, and validates the planned graph
before committing. A checked local region handles an unrelated unmappable
temporary row. A temporary unknown row inside the affected region is refused
with the source and selection kept. The general paragraph, code and table
handlers retain their existing routes.

Cut uses the same prepared deletion before it publishes the clipboard. Existing
resource availability, note/selection identity, cancellation and clipboard
change-count checks remain. The copy side exports exactly the selected fragment.
The clipboard owner proves the fragment and resulting document independently.

The initial editor owner had 72 table cases, four local-region controls and one
refusal control. It covers LF/CRLF, deletion and typing, numbered/quoted lists,
emoji, bold runs, leading paragraph groups, existing trailing paragraphs,
root/prose promotion, empty heads, marker widths, independent parents, source
reopen, caret and Undo/Redo. Four core-only interleaved fixture shapes retain
their Source admission guard. The Cut owner adds two delivery cases. The final
pre-fix selection baseline fails 123 assertions; the old Cut route fails four
document assertions while exporting the correct fragment.

The initial 90 document/clipboard owners and full 324-test Mac suite passed.
Opus review then identified cases omitted from that initial comparison: a
selection starting deeper than the removed item and selections crossing quote
containers. Passing those earlier tests did not establish the intended behavior.

The repaired planner re-homes a removed item's children and later paragraphs to
its previous surviving sibling in the same list, or its retained parent when
there is no surviving sibling. It preserves the original quote scope and maps
spacing tags to that actual destination. Separate root lists receive a real
separator when the merged paragraph belongs to a different quote container.
Six added fixture shapes cover deeper starts, several surviving children,
cross-quote children and later paragraphs. Their 24 LF/CRLF and delete/type
cases extend the table to 96. The original planner fails 88 assertions on the
final expanded owner (list94-final-review-baseline.log). The Cut owner also
checks a refused body-range Cut, including the exact refusal, unchanged live
text/selection, clipboard bytes and change count.

A distinct test sends setMarkedText updates and the committed accent through
the actual hosted native editor. The initial accent remains provisional and
committing é gives one undoable replacement. This passed even with the original
planner: the suspected raw-accent defect was not reproduced by direct native
text-input calls, and no composition implementation was changed. Physical
keyboard, input-method and installed acceptance remain pending.

All 91 editor/clipboard owners pass (list94-reviewed-owner-tests.log). The full
Mac suite passes 325 tests, zero failures and command exit 0
(list94-reviewed-full-tests.log) on the frozen repaired sources. Final hashes
and status are recorded in list94-verification.json and list94-review/FINAL-*;
the original reviewed copies remain available.

Still pending: multiline and structured paste, visible-marker/whole-header
replacement endpoints, general ownership at single-paragraph boundaries,
normal interleaved admission, incremental serialization and installed/IME
acceptance. Preview 68 is unchanged; no new DMG or full-parity claim is made.


### List 95: clearing a paragraph that separates lists (development)

A plain paragraph can keep an indented list at the root even though it carries
no list context. Clearing that text previously allowed the later list to attach
to the earlier list item on autosave. The pinned Lexical/MDX comparison keeps
those root items separate. Native replacement now includes this empty-paragraph
transition in the existing captured-graph transaction. It finds adjacent list
regions, preserves their before-edit parents, and rewrites an affected root's
indentation when needed. A nonempty prose replacement remains ordinary typing.

The editor table adds plain, quoted and numbered separators, deletion and
nonempty controls, for LF and CRLF. A local-region control keeps an unrelated
unmappable row unchanged; an affected unmappable region refuses the clear with
text and selection preserved. Cut uses the same prepared edit and exports only
the selected text. Its new CRLF case exposed a source-token terminator leak:
copying a body without its newline exported an invisible CR. The clipboard now
omits that unselected terminator while retaining inline image/link spelling.
The existing image resource transfer test still passes.

All 91 editor/clipboard owners pass in list95-verified-owner-tests.log. Restoring
the original production sources produces 40 failed assertions on the expanded
owners (list95-final-baseline.log). Frozen sources, independent web probes and
hashes are in list95-review/. The full suite passes 325 tests, zero failures
(list95-full-tests.log). Opus review is in progress; final states are recorded
in list95-verification.json.

The adjacent-container probes also establish further work: a promoted list can
inherit the removed item's container kind, or merge into a surviving sibling's
existing child list. Native source preservation alone does not prove this
bullet/numbered parity. That normalization, broader replacement/paste, wider
interleaved admission and installed/physical input acceptance remain pending.


#### List 95 review repairs

The first branch also ran beside only one list, which could refuse harmless
plain deletes when that neighbour was temporarily unmappable. The final branch
requires list neighbours on both sides, compatible quote depth and a later
indentation that reaches an active ancestor's content column. It leaves empty
headings and nonempty prose on their existing routes. Four controls cover
one-sided, insufficient-indent and cross-quote neighbours. The affected-region
refusal fixture now uses three spaces below `9.`, so it represents a real
adoption hazard. Two keyboard cases cover last-character Backspace, caret,
Typing Undo and Redo. The reviewed source fails 14 assertions on these new
controls; the repaired focused run passes.

The existing external-image clipboard owner now checks an exact CRLF body-only
fragment containing both the sized image and a link, its original image bytes,
RTFD and a paste into a vault. This protects saved inline spelling in addition
to the plain Outside fragment. A native code control demonstrates the existing
serializer's contextual fallback: top-level indented code becomes fenced when
the cleared paragraph would otherwise put it inside a list. No new code-card
implementation was needed for that control.

Root item parents are the invariant here. Same-kind lists separated by several
blank lines can still reparse as one loose list; two distinct source list objects
are not claimed. A later *ordinary prose* paragraph with imported indentation
can still be adopted after clearing its separator. That pre-existing case needs
root-paragraph provenance/serialization work and is not repaired by the list
neighbour branch. The wider paragraph/paste/container work remains active.

Final sources use list95-review/FINAL-* and final-source-hashes.json. The full
post-review rerun passes 325 tests, zero failures and command exit 0
(list95-reviewed-full-tests.log). Its 91 editor/clipboard owners also pass on the
final source. Status is maintained in list95-verification.json. Preview 69 is
packaged from this repaired code; its mounted app/signature checks and matching
private HTTPS download are recorded in artifact-preview-69-local.json and
preview69-handoff.json. It remains a non-notarized test build with installed and
full-parity acceptance pending.


### List 96: independent prose after a body-only boundary clear (development)

List-item parent checks cannot detect ordinary prose being pulled into an item.
For example, clearing Outside in `> - Parent / > Outside / >   Kept tail` can
turn Kept into another paragraph of Parent. Quoted variants are admitted by the
current rich-editor guard and reproduce the defect. Unquoted imported prose
with two or more leading spaces is already Source-only; that guard is unchanged.

The prepared edit now recognizes an independent following paragraph or heading,
including its full wrapped source group. It checks the tentative Markdown prefix
with the current paragraph spelling to determine whether the edit would adopt
that block into a ListItem. If so, it removes only structural prefix indentation
and installs a new source token for the same native content. Inline attributes,
image literals, quote depth and line endings remain in the attributed text.
Text/style edits invalidate this token normally. The existing transaction still
checks list relationships and uses the bounded local fallback/refusal path.
There is no new paragraph-to-list inference in the hot serialization loop.

The new editor owner has 32 LF/CRLF transitions: 16 currently admitted quoted
cases and 16 guarded core-only cases. It independently parses paragraph owners,
quote depth and heading kind; checks exact source, unchanged imports, caret,
Undo/Redo, reopen and subsequent typing; and covers compact/nested quotes,
literal leading spaces, wrapped/hard text, Markdown images, sized HTML images
and links. The Cut owner adds two quoted-prose transport cases. Local-region
and affected-region controls cover unrelated and adjacent unmappable rows. An
insufficient-margin prose control prevents unnecessary refusal. No test-only
production seam is added.

Restoring the original production source fails 166 assertions in the final
expanded editor/Cut owners (list96-final-baseline.log). The 92 document/clipboard
owners pass in list96-owner-tests.log. The full suite passes 326 tests, zero
failures and command exit 0 (list96-full-tests.log). Opus review is running;
final statuses and frozen source hashes are in list96-verification.json and
list96-review/. The independent headless Lexical/MDX comparison is retained as
web-root-paragraph-probe.mjs/log in that folder; its root ownership agrees.

This scope is single-native-paragraph body clearing. Whole-paragraph removal,
multiline/marker endpoints, broader paste and adjacent container-kind
normalization still need their explicit transformations. No additional rich
admission, installed/physical input acceptance or new DMG is claimed. Preview 69
is unchanged and does not include this development repair.


### Lists 97–98: root ownership and list-container follow-through

The reviewed root-block export and heading repairs are delivered in Preview 70.
They extend list96 beyond body-only clearing to row deletion, blank-spanning
selection, Backspace and Cut. Setext headings retain following source content
and remain one heading on edit; lone-CR heading import no longer traps. The
verified DMG and 327-test source evidence are recorded in preview70-handoff.json.
Installed/IME and complete parity acceptance remain pending.

List98 is development after that artifact. It normalizes affected document and
blockquote sibling list containers during body selection/Cut. Nested containers
keep source order, and numbered native tasks stay separate from bullet tasks.
A retained parent tail prevents type absorption and checkbox loss. Marker changes
before or at the selection update both descendants and caret; typing context and
layout follow the refreshed owning paragraph. Root ordered starts stay consistent
with or without an adjacent list. Unrelated source containers remain unchanged.

The owner has 54 source shapes × two line endings × deletion/typing, including
marker widening with a nested child and tail, layout consistency, Undo/Redo and
subsequent typing. Cut has its own transport guard. All 93 owner tests pass. The
initial regressions failed 182 assertions on Preview 70; final repair tests fail 68
assertions on the independently reviewed list98 source. The final full suite passes
327 tests, zero failures and command exit 0, with all final hashes unchanged;
status is in list98-verification.json and FINAL snapshots are in list98-review/.

The independent review is completed; its bounded findings are repaired. Evidence
for wrapper promotion is Markdown export parity, not Lexical's live empty-wrapper
representation. See list98-review/parity-evidence.md for native numbered-task and
nested-container fidelity rules and the web's mixed-task reload discrepancy.
No admission rules or delivered artifact have changed in list98. Broader range,
paste, native container admission and installed/IME acceptance remain required
before complete editor parity can be claimed.


### List99: inline paste shares the checked list edit

Plain and formatted single-line inline replacement now use the checked body
selection transaction before the existing Source-mode fallback. Surviving
children, list kinds and quote scope stay consistent with typing/Cut. A converted
single-line HTML paragraph loses only its synthetic trailing newline in rich
editing, so a copied bold word stays inline. Native fragment-selected endings
and structured/source paste retain their prior path. Resource admission and
last-moment editor/selection checks remain before this commit.

The owner verifies 24 list paste cases across four payload formats and LF/CRLF,
ordinary HTML text replacement, same-item and refusal controls, plus an imported
PNG's source position, bytes and Undo/Redo. Exact final regressions fail 170
assertions on pre-repair source; all 93 owners and the full 327-test suite pass,
with exit 0 and unchanged frozen hashes. Independent review is pending in
list99-verification.json. The probes establish saved export comparisons using
headless Lexical raw-text and Paragraph insertion, not browser or installed UI
acceptance. Preview 70 remains delivered and does not include lists 98–99.
Multiline, marker endpoints, broader structured paste and native container
admission still need implementation before full editor parity.
