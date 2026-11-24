# Native item-owned headings and quotes

Current internal source admits supported item-owned headings, prose quotes,
nested lists and code/table combinations after native/parser ownership checks.
Later admission work also covers mapped compact/tabbed heads and tested checkbox
chains. Unsupported HTML/reference constructs and unmapped structures retain
editable Source mode. The current implementation and installed evidence are
summarized in the [non-AI acceptance ledger](native-macos-non-ai-acceptance.md);
older Source guards, test totals and preview limitations below are historical.
AI remains deferred and performance has been accepted. Preview125 is the latest
packaged artifact and predates the current internal source.

## Target

Preserve both the owning list item and an inner heading/quote role, including a
container directly after the item marker and later body containers. The current
web package pipeline retains both shapes. Exact headless package probes are in
`artifacts/native-macos/acceptance159-review/web-item-containers.log`.

## Representation foundation (containers160)

The immutable item context keeps the source marker separately from its inner
block prefix. The marker continues to determine item identity, nesting and marker
width; the inner prefix determines heading typography and quote depth. Imported
paragraph tokens still preserve untouched bytes. Heading prefixes are kept out
of quote-only blank separator rebasing. Editing a heading does not turn its
heading weight into literal inline strong delimiters.

The new editor owner covers ten source shapes plus seven empty-block shapes with LF and CRLF: marker-first
headings and quotes, later headings and quotes, outer quotes, headings inside an
item-owned quote, setext headings, and nested heading items, marker-only leading rows, and refill of empty and consecutive empty headings/quotes. It checks exact
source, body edits, independently parsed container ownership, ordered-marker
width changes, follow-up typing and Undo/Redo with selection. It fails with 164
assertions on the old representation and passes all thirty-four LF/CRLF cases after the
repair. This is representation/command foundation evidence, not rich admission.

## Required editing behavior before admission

A probe using the actual MDXEditor core/list/heading/quote registry and the app's
transpiled empty-paragraph plugin dispatches the registered paragraph-insertion
command. Its twelve cases are recorded in
`artifacts/native-macos/containers160-review/web-item-return-app.log`. The earlier
`web-item-return.log` omits the app's blank-paragraph policy and is only a package
role-transition probe, not the oracle for saved empty-line spelling.

- Return inside a nonempty heading splits into two headings within the same
  item. It does not create another list item.
- Return at the end of a heading creates a plain paragraph in the same item.
- Return at the beginning leaves a plain empty paragraph before that heading.
- Return inside an item-owned quote creates another paragraph inside that quote,
  including start, middle and end positions.

These rules need native owner tests and a role-aware Return path before widening
admission. Ordinary item Return cannot be reused blindly. The app's empty lines
use an invisible paragraph marker, including empty paragraphs inside items and
quotes. A marker-only first row followed by a heading now keeps that heading as a
continuation, rather than copying its role onto the empty marker row. Empty ATX
heading ranges omitted by cmark are resolved once per parent in source order.
Setext-like unfinished child markers stay available for existing physical-row
recovery; the first full run exposed three existing Cut/Delete/format owners
that now pass after this distinction was repaired. Empty heading/quote exit and
selection replacement, Backspace/deletion, indent/outdent, non-list formatting,
clipboard ownership, cards, marked input and save/reopen remain to be verified.

## Canonical source versus unfinished editor rows (containers161)

Canonical file import now follows the parser, including single-hyphen setext
headings inside items. The temporary physical-marker rejection was removed.
The three guarded-core Cut/Delete/format fixtures now create unfinished rows by
deleting text through the actual editor, retaining native contexts and autosave
boundary protection. Their existing post-action and selection contracts remain;
Undo restores the true pre-action state rather than an ambiguous raw-source
spelling. No test-only production flag was introduced.

Two canonical setext cases extend the representation owner, which also checks
heading typography after marker changes and follow-up typing. That owner now
covers 38 LF/CRLF workflows. Four final owner tests fail 42 assertions with the
compatibility rejection present and pass after its removal. The actual web
registry preserves both new inputs as item-owned level-two headings; see
`containers161-review/web-canonical-setext.log`.

### Return lifecycle evidence for the next phase

`containers161-review/web-item-return-sequence.log` records eight actual-app
command sequences, live and after Markdown export/reimport. After a heading,
Return creates an explicit paragraph in the live list item; after reimport the
web importer can flatten its text into the item. Quote paragraphs retain their
quote container. One quoted-body sequence merges the following Tail into the
quote on reimport. These package observations are not installed UI acceptance.

Native Return work must preserve content and the intended paragraph/quote tree,
not copy a lossy export spelling. It needs an explicit live paragraph role for a
plain paragraph created by heading Return, the existing empty-paragraph anchor,
and preservation of role metadata when later content changes item ownership.
Check start/middle/end, repeated Return and typing, semantic source/reopen
structure, caret, font role and Undo/Redo. Keep the canonical and unfinished-row
contracts above intact. The older core paragraph-splitting path cannot simply
assign a new item identity to every inner block.

### Return implementation constraints

Keep the owning item id when splitting an inner heading/quote. A middle heading
split retains the heading role on both halves; an end split gives the new half a
plain paragraph role; a start split gives the left half a plain empty paragraph.
Quote splits keep both paragraphs in the same quote and need a quote-only source
separator. Use the existing invisible anchor for intentional empty paragraphs.
The plain paragraph created after a heading needs a distinct live block role so a
second Return does not blindly execute the flat list-item continuation path.
Include that role in immutable context cloning/signatures and Undo snapshots.

Place this handling before ordinary blank-item/list continuation. Preserve the
original line ending and UTF-16 caret coordinates. Invalidate paragraph-source
reuse on split halves while retaining inline traits and link/image literals.
Do not transfer later item content to a new item for an inner-block Return.
The ordinary sibling-creation path must preserve inner suffix/paragraph metadata
when it intentionally transfers later continuations to a new item. Keep following
paragraph/quote source boundaries intact; the web lifecycle probe is evidence of
live command roles, not permission to merge Tail into a preceding quote.

## Admission and delivery

Existing source-mode guards remain unchanged. The workspace owner continues to
expect Source mode for marker-first headings and quotes. Only enable shapes
whose original parser tree, native ownership, source export and editing commands
have been proved consistent; incomplete shapes must remain editable Source.
Full desktop parity is still unproven. The folder sidebar remains hideable.

Final suite status and exact source hashes are recorded separately in
`artifacts/native-macos/containers160-verification.json`.

## Nonempty inner Return and paragraph lifecycle (containers162)

The guarded rich core now splits a nonempty item-owned heading or quote without
creating a sibling item. Start/middle/end positions keep the existing item id.
Heading splits keep the heading on both halves in the middle, create a plain
paragraph at the end, and leave an explicit empty paragraph before the heading
at the start. The actual web registry probe confirms that the caret remains on
the right heading at the start, not in the new empty paragraph:
`containers162-review/web-return-caret.log`.

An immutable explicit-paragraph role keeps a paragraph created after a heading
inside its item on subsequent Return. Import preserves individual paragraphs in
items containing text headings/quotes, including intentional empty-paragraph
anchors. Those anchors must not count as whitespace gaps claimed by a following
paragraph. The ordinary flat-list Return path remains separate. Its transfers
now retain inner role metadata when they deliberately create a sibling.

One editor-boundary owner covers 60 LF/CRLF/lone-CR workflows: nonempty
start/middle/end, later body containers and Tail boundaries, nested items, outer
quotes, bold follow-up typing, Unicode UTF-16 positions, final unterminated lines,
reopened empty paragraphs, repeated Return after typing, and Undo/Redo. Expected
source is handwritten and its roles/content are checked with swift-markdown.
The final owner fails 429 assertions against the pre-change sources. This is
core behavior evidence while the public Source guard remains closed; it is not
installed keyboard/IME acceptance or a delivered feature.

Still to verify before admission: empty heading/quote exit, selected Return and
arbitrary selection replacement, Backspace/deletion, indent/outdent and other
block formatting, clipboard ownership/cards, marked input, and full installed
interaction. General feature parity remains open. Exact hashes and final focused
and full results are recorded in `containers162-verification.json`.

Final verification: 124 document/clipboard owners and the full 385-test Mac suite
passed with zero failures, terminal exit 0. Frozen source hashes still match.
No version, package, admission or iOS change was made.

## Selected Return across inner roles (containers163)

Same-paragraph selected Return already preserved roles on the previous code;
54 selection controls verified it. Crossing a heading/quote boundary needed a
repair: removing text must not promote a surviving plain Tail into a heading or
quote, or erase the final heading/quote role when flat list Return creates a new
sibling. Actual-app command trees are in
`containers163-review/web-selected-return.log` and
`containers163-review/web-cross-block-return.log`. Their saved Markdown can lose
a later quote boundary; native retains that boundary and intended live tree.

The existing removal planner first validates the selected item relationships.
The role-aware path then retains the final block, transfers following paragraphs
and children when creating a sibling, re-indents descendants for marker-width
changes, and checks parsed item/parent edges before one native commit. Empty new
quote paragraphs use the explicit anchor. Plain-to-plain selections keep their
ordinary list Return path. Body endpoints at an unterminated EOF are supported.

The primary Return owner now covers 171 LF/CRLF/lone-CR workflows, including local
and cross-block body selections, whole body removal, empty heading/anchored quote
commands, numbered sibling width changes with children, outer quotes, Unicode,
EOF, caret, follow-up typing, save/reopen and Undo/Redo. Empty anchored quotes stay
in their quote under the actual registered web command; physical key handling is
still separate installed acceptance. Marker/newline endpoints and broader range,
delete/format/clipboard/card operations remain pending. Admission stays closed.
Exact final gate outcomes and source hashes are in `containers163-verification.json`.

Final containers163 verification: 124 document/clipboard tests and the full
385-test Mac suite passed with zero failures and terminal exit 0. Frozen hashes
match. No admission, package, version, AI or iOS change was made. Before admission,
verify the source-traced possibility that a later empty heading/quote at an
unterminated EOF has no native row to retain its source/context metadata.

## Canonical empty EOF text blocks (containers164 / Preview 115)

The hosted owner reproduced missing native rows and metadata for empty final
headings, quotes and explicit blank paragraphs, including root shapes already
admitted to rich mode. A presentation-only terminator now carries their source
and role without adding Markdown bytes. Cmd-End stays in the block; refill keeps
its font/role and original absent source ending. Inner Return distinguishes the
native terminator from a source newline. Empty root ATX headings reuse canonical
source-range resolution.

The representation owner adds 25 distinct hosted workflows: item/root blocks,
nesting and outer quotes, consecutive empty headings, LF/CRLF/lone-CR, untouched
export, Cmd-End, font, refill, reopen, Undo/Redo and inner Return. The final exact
test fails 305 assertions on old production code. All 124 document/clipboard
tests and the full 385-test Mac suite pass with zero failures, terminal exit 0.

Delivered in local Preview 115 (0.3.75/build115): mounted app/guide, signature and
full private download checksum verified in preview115-handoff.json. List-owned
heading/quote admission remains closed. Installed/IME, broader structural/range
and clipboard/card acceptance remain open; AI work is unchanged and deferred.

## Nonempty inner-block Backspace (containers165 / Preview 116)

The guarded rich core now retains heading/quote roles when Backspace removes a
root list wrapper, and retains the existing nested-outdent policy. At the start
of a later nonempty heading/quote after flat item text, Backspace moves the caret
to that preceding text without changing source or adding an Undo event. A
preceding visible child remains in source order. Compatible heading, quote and
explicit paragraph peers still merge through the checked planner. Payload and
follow-up typing use the surviving role's typography and preserve inline traits.

Seventeen actual registered web command probes run in an owned nonpersistent
WKWebView with real DOM selection. The live Return-created paragraph control is
important: web import can flatten a Tail paragraph or reorder a child list before
an inner heading. Native keeps its explicit paragraph role and original source
order instead of copying those lossy imports.

The existing editor-boundary Backspace owner adds 77 LF/CRLF/lone-CR workflows:
wrapper and selected-marker removal, nested outdent, caret-only navigation,
compatible merges, semantic fonts, follow-up typing, exact source, independent
parser roles/parents, Undo/Redo and reopen. The final test fails 421 assertions
on old production code. The repaired Backspace/Return/representation owners pass.
Final full-suite status and hashes are in containers165-verification.json.

Public rich admission remains closed. Empty-block Backspace and document-start
key routing remain separate work: ten actual web command discovery cases are in
containers166-review, with no native implementation yet. Full container
format/delete/indent/clipboard/cards, broader ranges, installed/IME interaction,
performance/cross-client acceptance and production release readiness remain open.
No version or DMG was created at the containers165 gate; it was subsequently
included in Preview 116 with containers166.

Final containers165 verification: the full 385-test Mac suite passed with zero
failures and terminal exit 0. Frozen final source hashes still match. Exact
baseline: one test, 421 assertion failures, exit 65 as expected. Focused repaired
Backspace/Return/representation: three tests, zero failures, exit 0. No version,
package, admission or iOS change was made.

## Empty text-block Backspace and EOF body clear (containers166 / Preview 116)

Backspace now has an actual text-view command handler for empty text blocks,
including document start where AppKit supplies no character deletion. Removing
a later empty block keeps the preceding caret role and following explicit Tail;
root empty headings/quotes become explicit plain paragraphs when appropriate.
When a quote has later text paragraphs or headings, removing its empty first
paragraph keeps that remaining quote and moves focus into its first block.
Marker-first root/nested list wrappers keep their existing lift path.

The body-clear boundary now retains a presentation-only row when all text in a
final unterminated heading, quote or explicit paragraph is removed. This keeps
metadata available to Backspace, refill and Undo without adding a Markdown
newline. The subsequent removal is one explicit command rather than coalescing
with the earlier clear. Existing list item parent edges must remain unchanged.

The Backspace owner adds 52 hosted LF/CRLF/lone-CR workflows, including root and
item shapes, marker-first and later blocks, EOF, quote paragraph boundaries,
source, independent parser roles/parents, caret/font, follow-up typing,
Undo/Redo and reopen. The final test fails 250 assertions on old production code.
All 124 document/clipboard owners passed before two final EOF controls; those
final controls plus Backspace/Return/representation owners also pass. The frozen
full-suite status is recorded in containers166-verification.json.

Actual web reference is an owned nonpersistent WKWebView using registered
Backspace/clear/Return commands and real DOM selection. The live explicit Tail
control prevents copying the web importer's lossy flattening. This is not
installed keyboard or IME acceptance. Root nonempty quote keys and deeper
quote/list/card boundaries remain open, along with full format/delete/indent/
clipboard/range parity and public inner-container rich admission. No AI/iOS
change was made. Preview 116 now includes this repair; its actual app, guide,
signature and full private download are verified in preview116-handoff.json.

Final containers166 verification: 385 Mac tests passed with zero failures and
terminal exit 0 on the final frozen source, including all 52 new hosted workflows.
The final exact test fails 250 assertions on containers165; the empty-heading
boundary control independently fails 27 assertions before its repair. Source
hashes still match. The earlier 385-test pass is retained as pre-boundary evidence.
Version and release documentation changes for Preview 116 occur after this gate;
packaging is verified separately from native installed/IME acceptance.

## Final text-body Cut and reopen (containers168, unreleased)

Whole final-body Cut now uses the same retained-block preparation as keyboard
clearing. Existing real source endings stay intact; an unterminated body gets a
presentation-only carrier, and an explicit empty paragraph gets the anchor needed
to survive parsing/reopen. The clipboard exporter still reads the original
selection. Missing resource bytes, changed note/selection or changed clipboard
continue to refuse publication and mutation before the Cut commit.

The primary Cut owner is extended and renamed to cover root and item roles. Its
54 workflows cover eleven shapes with real or absent final terminators and
LF/CRLF/lone-CR, native/plain clipboard bytes, foreign metadata, handwritten parser
heading/quote/item counts, caret/font, immediate refill, Cut Undo/Redo and reopen.
A missing-attachment heading checks refusal after edit preparation, and one
explicit Bold control proves that caret setup preserves the user's chosen style.
The exact two final tests fail 183 assertions on Preview 116 source.

Reopen also exposed partial paragraph-token reuse at EOF: appending new text can
leave the original token on only an unchanged marker prefix. Reuse now requires
that token to end at a native paragraph boundary or EOF. This retains original
wrapped groups while preventing duplicate markers on export. Empty caret setup
also recognizes marker-only rows, uses the inner role font and inherits a missing
Strong flag instead of treating heading weight as literal bold markup.

Five focused Cut/refusal/Backspace/Return/representation tests pass. The final
frozen full-suite status is in containers168-verification.json. Nine owned
nonpersistent WebKit registered CUT_COMMAND cases independently confirm retained
roles, including a live Return-created explicit paragraph. Their DataTransfer is
in memory; this is not installed clipboard/IME acceptance or byte-identical
native/web clipboard flavor evidence.

This source change is not in Preview 116; no version or new DMG was created here.
Public inner-container rich admission remains closed. Nonempty root quotes,
deeper quote/list/card commands, broader range/structured paste and formatting,
installed input/IME, performance and cross-client acceptance remain open. AI and
iOS sources are unchanged. The fully hideable folders sidebar is preserved.

Final containers168 verification: 385 Mac tests passed with zero failures and
terminal exit 0 on the final frozen source, including the renamed clipboard
owner and all 54 new Cut workflows. Source hashes still match. Five focused
owners pass; the exact final two clipboard tests fail 183 assertions on Preview
116 production source. No admission, version, package, AI or iOS change was made.


## Leading nonempty quote Backspace (containers167, unreleased)

At the first nonempty paragraph in the leading Document quote chain, Backspace
removes one nearest quote wrapper. Outer wrappers and child paragraphs, headings,
lists, code and tables are retained. The command compares the intended tree to
an independent parse before committing, then checks byte-exact export of the
prepared native text. Adjacent lists keep their independent starts through a
compatible alternate marker delimiter when needed. Only the target native span
is re-rendered, preserving outside native editing state and previous Undo work.

The hosted Backspace owner adds 61 positive workflows and controls for heading
no-op, Source/read-only behavior and a prior Return/Undo history. Native reopening
now restores the current caret's block and inline typing role rather than
resetting to plain defaults. Exact baseline: 500 expected assertion failures on
the prior production source. Focused quote and Cut owners pass; full status is
recorded in containers167-verification.json when terminal.

This is not broad quote or list-container admission. Quotes after preceding
blocks, deeper empty/card-first boundaries and complete structural/clipboard
commands remain open, as do installed physical input/IME, performance and
cross-client acceptance. No AI/iOS source change or new DMG is implied here.


Preview 117 handoff: containers167 and containers168 are packaged in version
0.3.77/build117. The combined final Mac suite passed 385 tests with zero failures
on the frozen application sources before the version/documentation-only bump.
The local ad-hoc DMG's mounted app version, signature and bundled guide match;
the complete private HTTPS download has the same checksum as the local artifact.
See preview117-handoff.json. This does not establish installed physical keyboard,
IME, full rich admission or full feature parity. AI remains deferred.


## Quote paragraphs after preceding text (containers169 / Preview 118)

Backspace at the start of a nonempty quoted paragraph or heading now merges that
text into the preceding text block. The receiving prose/heading/list item keeps
its block role; remaining quote paragraphs, headings, lists and cards retain
their own containers. Empty quote ancestors alone are removed. A native item row
can contain several logical paragraphs; the merge targets its final paragraph,
not the head. The intended parser tree must match before committing one Undo
transaction. Outside native rows and earlier Return history are retained.

Twenty-one registered web key commands and subsequent insertions use actual DOM
text selections in an owned nonpersistent WKWebView with the app registry. The
event loop settles before and after Backspace. The quote caret's inline format
is retained at the join, while the receiving block supplies its role; links do
not extend across that boundary. The code is checked by 87 new source-ending
workflows in the existing Backspace owner, plus the prior native-edit history
control. The exact final baseline fails 753 assertions on Preview 117, including the empty-predecessor coverage.
The final focused owner passes. Full-suite status and hashes are recorded in
containers169-verification.json after the full run terminates.

Empty prose/heading predecessors are removed without stripping the quote, while an empty bullet/numbered item receives the text. Parser cleanup preserves unrelated empty quotes.

Preview 118 includes this repair; Preview 117 does not contain it. Empty/deeper/card-first
quote boundaries, complete list-container formatting/delete/indent/clipboard
commands and public rich admission remain open. Installed keyboard/IME,
performance/cross-client and production delivery acceptance remain separate.
AI is deferred; no iOS source changed.

Final containers169 verification: 385 Mac tests passed with zero failures and terminal exit 0. Frozen source hashes match. The final focused Backspace owner passes; the exact same final test fails 753 assertions on Preview 117 production source. No admission, version, package, AI or iOS change was made. The next independently confirmed gap is inner-container block formatting, recorded in containers170-discovery/discovery.json.


Preview 118 handoff: containers169 ships in 0.3.78/build118, an ad-hoc non-notarized
arm64 DMG for macOS 26+. The final 385-test source gate, 87 new hosted quote
workflows, exact 753-failure baseline and 21 registered web key/typing controls
are recorded in containers169-verification.json. preview118-handoff.json verifies
the actual mounted app version, signature, bundled guide and complete private
HTTPS download. Source and test hashes remain exact after packaging. This does
not establish installed keyboard/IME or full parity acceptance.


## Initial inner block formatting (containers170, unreleased)

Existing inner headings/quotes and native explicit paragraphs retain their item
owner during block formatting. Ordinary flat list rows keep wrapper removal.
Inner quote hierarchy and later text blocks survive conversion; mixed wrapper
removal promotes later inner roles as valid root blocks. Hard breaks remain
inside headings. Quote-only gap rows keep their actual depth and spelling when
marker width changes. Formatting remains separately undoable from native typing
both in the same event and after AppKit advances the event loop.

The existing formatting owner adds 151 workflows with handwritten source,
independent parser parents/roles, caret/font, typing, Undo/Redo and reopen. The
exact final test fails 731 assertions on Preview 118. Two focused owners and the
final 385-test Mac suite pass on frozen sources. Seventeen actual core toolbar
signals are recorded separately; invalid nested headings and lossy flattened
web exports are not copied. Native explicit paragraph roles stay explicit.

This is initial format support, not full formatting acceptance. Compound probes
in containers171-discovery confirm the next model requirement: a toolbar-created
quote contains text directly, while an imported quote contains a paragraph.
Further format commands and Return distinguish those live roles. That transient
state must be preserved through native structural edits and Undo, then reset
on Markdown import. Public rich admission stays closed until this and the other
delete/indent/clipboard/range contracts are verified. Preview 118 does not contain
containers170. AI/iOS and the hideable folders sidebar are unchanged.


## Compound formatting and live quote Return (containers171, unreleased)

A quote created by the toolbar holds text directly until its live structure
changes. It is distinct from the paragraph inside a nonempty imported quote.
Paragraph/Heading replaces that new quote; repeated Quote does not deepen it.
Return at its start, middle or end creates a paragraph outside that quote,
retaining enclosing quotes and the owning list item. An empty left quote stays
empty rather than gaining a paragraph anchor. Empty parsed quotes infer this
role; nonempty quotes reconstruct their paragraph role on Markdown import.
No persisted metadata or shared file schema was added.

Existing native owners cover compound commands, source-ending variants,
marker-width changes, clear/refill, caret style, Undo/Redo and reopen. A
Paragraph → Quote → clear producer control checks that an old paragraph flag
does not leak an invisible anchor into the quote. Quote-only separators keep
the outer blockquote intact. Fourteen executed web toolbar/key sequences supply
independent live-tree references; native canonical Markdown retains boundaries
that the web's lazy-continuation export can lose.

The focused three owners pass. The exact final tests fail 454 assertions on
containers170 production source, with no unexpected failures. The final full suite passes 385 Mac tests with zero failures and terminal exit 0.
Frozen source hashes match containers171-verification.json.

Public rich admission remains closed. Further deletion/lifting, typed shortcut,
clipboard/range and embedded-card live-role transitions still need acceptance.
This is not installed IME, full parity or release evidence. Preview 118 does not
contain containers170/171. AI stays deferred and the hideable folders sidebar
is unchanged.


Preview 119 delivery: containers170/171 now ship in 0.3.79/build119, ad-hoc
and non-notarized for arm64/macOS26+. preview119-handoff.json verifies the
mounted payload/signature/bundled guide and full private download checksum.
The exact application sources retain the 385-test pass; only version and
release documentation changed afterward. No public rich admission or installed
input acceptance was added. Read-only Backspace references are recorded in
containers172-discovery.json; no speculative behavior change was made.


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


## Nested quote/list prefix foundation (containers197/198)

The pinned web app plugins preserve lists inside item-owned quotes and perform
body typing, Return and list conversion there. Native prefix parsing previously
missed the inherited indentation under wider outer markers such as `10. `.
The guarded rich core now imports those heads and retains exact body-edit source,
parent ownership, selection and Undo/Redo for five LF/CRLF source shapes.
The regression owner fails 20 assertions on the earlier prefix parser and passes
with inherited indentation recognized. The 197 scoped gate passes 264 tests.

Raw typing remains separate: an indented literal `>` must not become a quote
shortcut merely because parsed inner quotes can inherit wide indentation. The
198 owner proves original retained-space behavior against the pre-197 source,
then reproduces four failures under the expanded parser and passes with the
standalone typing mode. Both final focused owners pass. The public nested
quote/list guard remains closed; the installed app is still performance196.

Next: rebase descendant source prefixes and blank quote separators at the
ancestor's quote depth when marker width changes; establish correct visual
indentation; then exercise structural commands, clipboard/ranges, compact heads,
cards and marked input before admission. This is foundation evidence, not a
completed nested-container feature or installed acceptance. No DMG was made.


## Internal containers199: marker widths across nested quote boundaries

Changing a list marker now propagates each ancestor's padding delta at that
ancestor's quote depth. Blank quote separators carry the enclosing item's
identity, so they follow the same marker-width change instead of retaining stale
indentation. This avoids detaching a quoted child list when a parent changes
between a bullet, a one-digit number and a wider number. Two selected ancestors
at different quote depths accumulate their shifts independently.

The existing nested-list editor owner now checks six LF/CRLF shapes, exact
saved Markdown, independently parsed parents, body edits, marker conversion,
selection, Undo/Redo and follow-up typing. These expanded cases failed against
the previous production source; both focused owners pass after the repair,
including the unchanged literal-typing guard. Broader validation is recorded in
`artifacts/native-macos/containers199-review/`.

The public nested quote/list admission guard remains closed. Correct visual
indentation, the remaining structural commands, clipboard/range operations,
compact same-line heads and installed marked-input checks remain. The installed
QA app is still performance196. No app version bump or DMG was made.

Final containers199 validation: the scoped non-AI desktop suite completed with
264 tests and zero failures; the frozen source hashes match the tested source.


## Internal containers200: layout follows list ownership across quotes

A nested quoted list now carries immutable snapshots of the list items crossed
before its quote. Paragraph styles include those items' rendered body offsets;
optional whitespace before an ordinary root quote does not create an invented
list indent. The existing context refresh resolves current ancestor heads after
marker changes, without another document parse. Continuation, Return, block
conversion and card context copies retain the layout ancestry.

The existing six-shape LF/CRLF editor table checks that child markers align with
their containing quote text, including the extra quote depth case, after import,
formatting and Undo/Redo. Grandchildren stay further indented. The previous
production source fails 48 assertions, while both focused owners pass on the
repaired source. Exact Markdown and independently parsed item parents remain
unchanged by layout. Evidence: `artifacts/native-macos/containers200-review/`.

Public admission remains closed for nested quote/list shapes. Broader structural
commands, compact heads, clipboard/range operations and installed/IME behavior
still require verification. This is no installed-layout or full-performance
claim. The installed QA app remains performance196; no DMG or version bump.

Final containers200 verification: 264 non-AI tests passed with zero failures.
The frozen source hashes match the tested files.


## Internal containers212: Return across inherited quote indentation

The existing Return owner now covers outer numbered items growing from 9 to 10
with a quoted child list, the same shape inside a root quote, an inner numbered
item with another quote boundary, and an unchanged-width bullet control. Both
LF and CRLF are exercised through real editor Return, Undo/Redo and follow-up
typing. Child markers must remain aligned with their containing quoted text.

The previous Return re-indent moved whitespace after every descendant's final
quote instead of at the split ancestor's quote depth. It also retained the old
head in quoted descendants' layout ancestry. Return now uses the existing
quote-depth prefix operation, transfers those descendants to the new sibling,
and preserves that transfer while rewriting descendants backwards. Owned quote
separator spellings rebase with the new head width.

The final expanded owner fails 18 assertions against the old source and passes
after the repair. The first focused command had an invalid extra module prefix
and selected zero tests; its log is retained and is not counted as pass evidence.
The final scoped non-AI suite completes with 265 tests and zero failures, terminal
exit 0. Frozen source/test hashes match the checked files. Evidence is in
artifacts/native-macos/containers212-review/.

Public nested quote/list rich admission remains guarded. Selected Return across
inner roles has a separate planner re-indent, and indentation/outdent, deletion,
clipboard/card/compact-head and installed input acceptance still need work. The
installed QA app remains performance211; no Release rebuild, DMG, version bump,
iOS or AI change was made. This is a guarded core repair, not full parity.


## Internal containers213: selected Return through quoted inner roles

The selected inner-block Return planner now applies descendant padding at the
split ancestor's quote depth and transfers quoted layout ancestry to the new
sibling. Reverse rewrites preserve those transferred attributes. This closes
the separate selection path left after the caret-only containers212 repair.

A new sibling whose inner role is a quote cannot place that syntax directly
after a GFM checkbox: it becomes literal task text. Changed task heads with an
inner role now emit an explicit task paragraph followed by the indented block.
The checked old item and unchecked new sibling remain separate. This adds no
parser pass or cache; unchanged source-token reuse is unaffected.

The existing owner gains four cross-role rows (wider number, enclosing quote,
numbered task, bullet control), across LF/CRLF/CR, checking exact source,
independent Markdown trees, caret, Undo/Redo, typing, reopen and child alignment.
The task expectation was corrected using the parser before the final baseline:
the original inline-after-checkbox spelling was not a quote. That final owner
fails 63 assertions before the repair and passes afterward.

The first 265-test non-AI run had three assertions fail in one restart-recovery
test, coincident with Foundation logging a cancelled file-access claim. The
original note and recovery drafts remained intact. That workspace save path
does not call the edited editor serialization/planner. Its existing assertion
now reports issue/saveStatus to make a future failure attributable; no retry or
recovery production behavior was changed. All five lifecycle tests then passed,
and a full rerun passed 265 tests with zero failures, terminal exit 0, on the
frozen source/test hashes. The earlier failure remains recorded and is not
counted as a pass. Evidence: artifacts/native-macos/containers213-review/.

Public nested quote/list admission stays guarded. Tab/Shift-Tab, deletion,
clipboard/card/compact-head and installed input work remain before admission.
The installed app is still performance211; no Release rebuild, DMG, version bump,
iOS or AI change was made. Broader performance, accessibility, cross-client and
final delivery acceptance remain open.


## Internal containers214: move whole items with quoted descendants

Tab/Shift-Tab subtree rewrites now move indentation at the changed ancestor's
quote depth. The same correction applies when adopted or remaining numbered
siblings change marker width. Prefix movement after the descendant's final
quote could otherwise leave its quoted list at the old column and make the
parent-graph validation refuse an ordinary whole-item move. Ownership checks,
reordering policy and refusal behavior remain intact; no parser pass/cache is
added. The production diff is three rewrite expressions in MacListEditing.

The existing whole-item movement owner gains seven LF/CRLF cases: bullet indent
and outdent, numbered indent and widening outdent, an enclosing root quote,
an extra nested quote/list boundary, and a remaining sibling whose number gets
shorter. Exact saved source, independent parser ownership, child alignment,
selection, Undo/Redo and follow-up typing are checked. An initial fixture that
started an inner ordered list at 9 without a blank separator was corrected;
the final test checks that its selected item exists in the source parser tree.
The final baseline fails 42 assertions, and the repaired owner passes.

The final scoped non-AI suite passes 265 tests with zero failures and terminal
exit 0, including restart recovery. Frozen source/test hashes match. Evidence:
artifacts/native-macos/containers214-review/. Public nested quote/list admission
remains guarded. Moving an item out across a quote boundary needs separate
semantic verification, as do deletion, clipboard/card/compact-head and marked
input interactions before admission. The installed QA app remains performance211;
no Release rebuild, DMG, version bump, iOS or AI change was made. Broader
performance, installed/accessibility, cross-client and final delivery acceptance
remain open.


## Internal containers215: outdent respects the containing quote

Current pinned web plugins with registered Lexical list/rich-text commands leave
an inner list's outermost item unchanged on Outdent. Five before/after exported
trees prove the no-op, while three same-quote indent/outdent controls change.
The current web toolbar also disables Decrease indent when the item's list is
owned by a quote rather than directly by a list item. This is headless command
and source evidence, not installed keyboard or byte-for-byte export parity:
web import normalizes numbers and adds its usual trailing empty paragraph.

Native ordinary Outdent now returns unchanged when the parsed parent belongs
outside the current quote depth. Previously it could reorder the item, add an
Undo step, or warn that Source editing was needed. Backspace's explicit
adoptingFollowingSiblings calls remain exempt because deletion has a distinct
contract. No parser pass/cache or persistence change was added.

The existing whole-item movement owner gains five boundary no-op rows and one
deeper-child outdent control in LF/CRLF. It checks quiet handling, no Undo entry,
source/selection stability, normal movement, typing and the existing subtree
contracts. Quote alignment compares against the quote text's headIndent; an
inline quote head's firstLineHeadIndent may locate its item marker instead.
The baseline fails 26 assertions; the repaired owner passes. The scoped non-AI
suite passes 265 tests with zero failures and terminal exit 0, including restart
recovery. Frozen files match source-hashes.json. Evidence is recorded under
artifacts/native-macos/containers215-review/.

A lower-level DELETE_CHARACTER_COMMAND discovery merged into preceding quoted
text, but it bypassed the higher-priority list Backspace-key handler. That result
is superseded as actual Backspace evidence by containers216 below; its earlier
root-quote "window object not found" result also does not block that key-handler
path. Native deletion was the next distinct contract to repair/verify. Public nested quote/list admission stays guarded;
clipboard/cards/compact heads, installed marked input/accessibility, cross-client
and broader performance acceptance remain. The installed app remains
performance211. No Release rebuild, DMG, version bump, iOS or AI change was made.


## Internal containers216: Backspace removes an inner list wrapper inside its quote

The pinned list plugin handles KEY_BACKSPACE_COMMAND before rich-text deletion.
ListItemNode.collapseAtStart removes the wrapper into a paragraph inside the
quote; a deeper list child still outdents normally. All eight current-plugin
key-command probes complete, including the root-quote case. The preventDefault
capability is supplied for headless command dispatch; this is not installed
keyboard or IME acceptance. The lower-level deletion discovery in containers215
bypassed this handler and must not define Backspace semantics.

Native lifting now recognizes a list whose parsed item parent is outside its
quote depth. Its converted paragraph retains the enclosing item's identity and
quote role; children are promoted inside that outer item. Prefix changes apply
at each changed ancestor's quote depth. Separator lines retain the quote depth
shared by neighboring blocks, without inserting a quote line before or after
content outside that quote. A deeper nested quote and its list remain together.

The existing Backspace owner gains eight LF/CRLF rows, each exercising both body
caret Backspace and selected native marker deletion. They check exact source,
quiet handling, caret, Undo/Redo selection and follow-up typing. Direct parser
ancestry counts ensure the converted text retains one quote and only the
intended list owners, and promoted children preserve their quote/item owners.
The baseline fails 82 assertions; the repaired owner passes. The full scoped
non-AI suite passes 265 tests with zero failures and terminal exit 0, including
restart recovery, on matching frozen hashes. Evidence is in
artifacts/native-macos/containers216-review/.

One deeper web export has a blockquote inside an exported paragraph and saves
Child> Nested. Native deliberately preserves valid separate quote blocks and
checks their ancestry, rather than reproducing that export defect. There is no
byte-for-byte web export parity claim for that shape.

Public nested quote/list admission stays guarded. Whole-head/range deletion,
clipboard/cards/compact heads, installed marked input/accessibility and
cross-client acceptance remain, alongside broader performance and final
delivery. The installed app is still performance211; no Release rebuild, DMG,
version bump, iOS or AI change was made.


## Internal containers217: whole-head deletion and Cut preserve quote ownership

Removing a list head inside an item-owned quote now retains that quote role on
the surviving tail paragraphs transferred to the outer item. Quote-only gaps
rebase at the removed ancestor's depth. Removing an outer head that owns quoted
blocks recognizes imported quote gap rows and keeps newly generated separators
at the shared quote depth, so nested quotes and their lists stay together.
No parser pass/cache, persistence format or permissions changed.

The existing whole-head owner gains six LF/CRLF shapes: an inner head with tail
and child; numbered markers; enclosing root quote; an outer head whose remaining
body is quoted; a nested ordinary parent with quoted content; and a deeper quote
with a list. Literal parser ancestry counts check surviving text and children,
and quote identities check that tails/nested lists remain in the same blocks.
The existing Cut owner gains one real clipboard transport row, including exact
fragment, remaining note, Cut undo name and Undo/Redo selection checks.

The copied item already has valid standalone quote syntax with optional leading
indentation; its original spelling is kept. Newly generated blank quote lines
use the lifting command's existing > plus space spelling. Correcting those
fixture spelling decisions does not weaken the independent ancestry/quote
identity assertions. The exact final tests fail 58 assertions on the baseline
and pass after the repair. The scoped non-AI suite passes 265 tests with zero
failures, terminal exit 0, on matching frozen source/test hashes, including
restart recovery. Evidence: artifacts/native-macos/containers217-review/.

Public nested quote/list admission remains guarded. The next distinct routes
are cross-item replacement, clipboard/paste/card and compact-head combinations,
then installed marked-input/accessibility and cross-client acceptance. Broader
performance and final delivery remain open. The installed app stays at
performance211; no Release rebuild, DMG, version bump, iOS or AI change was made.


## Internal containers218: selection renumbering preserves quoted descendants

Cross-item replacement can normalize earlier numbered rows from `1.` to `10.`.
The replacement planner now carries each ancestor's movement at that ancestor's
quote depth, including through multiple descendant levels. Previously it added
that width to the descendant's final indentation inside the quote; the owner
validation then refused the edit. The removed-parent destination policy is not
changed by this batch. No parser pass, persistence format or admission rule was
added.

The existing replacement owner gains one guarded-core LF/CRLF shape, exercised
for deletion and typed replacement. A quoted child and its nested child remain
under the earlier renumbered item. Handwritten source and parent arrays, an
independent quote-ancestry assertion, caret/layout, Undo/Redo selection and
follow-up typing protect the result. Final baseline evidence has 28 assertion
failures in one owner; the repaired owner passes. The initial expanded fixture
accidentally duplicated a Leaf line in its expected string; that typo was fixed
before the final baseline and repaired runs.

The discovery also executes twelve headless current-plugin web selection API
probes. Some complex cross-quote shapes differ between removeText and insertText,
and some exports are malformed. Those outputs remain discovery evidence, not
an installed Delete/Cut contract or a reason to copy invalid Markdown. Broad
cross-quote replacements, moved quote tails, clipboard/paste/cards and compact
heads remain open; this batch only closes ancestor-width propagation.

Public nested admission remains guarded. The installed app remains performance211.
No internal Release rebuild, DMG, version, iOS or AI change is part of this batch.
Final scoped suite results and source hashes live in
artifacts/native-macos/containers218-review/verification.json.


## containers232: preserve an unselected quote tail during cross-item replacement

A guarded-core editor case now reproduces a surviving Tail paragraph losing its
quote when a selection starts in its outer ancestor and removes the quoted item
head. Both Delete and typing exhibited the loss with LF and CRLF. The existing
replacement owner adds an independent swift-markdown quote-ancestry assertion,
plus Undo/Redo and selection restoration. The pre-fix run has four failures for
the intended quote loss; the repaired editor/clipboard gate passes 125 tests.

The transfer now carries the removed head's relative quote depth into the tail's
block suffix and uses the surviving head's layout ancestry. It adds no parser
pass, cache, test seam, or public admission. This follows the existing whole-head
removal rule; it is not a claim of web selection parity. The shallow web selection
API probes differ for removeText and insertText, and the deeper fixture loses an
endpoint during web import, so those results are discovery evidence only.

Normal rich admission of lists inside item-owned quotes remains closed. The
installed QA app remains acceptance230; this source-only guarded repair has no
Release rebuild, DMG, version, iOS or AI change. Exact scoped-gate status and source
hashes are recorded in artifacts/native-macos/containers232-review/verification.json.


## containers260: standalone copy removes outer list widths before quotes

Copying a retained child from an unselected numbered parent could keep four or
more spaces before its quote marker. A standalone parser then read the copied
fragment as code. Clipboard promotion now removes each omitted owner's width
at that owner's quote depth, rather than only changing the final list indent.
The same adjustment applies to quote-only continuation separators. Owners
included in the selection retain their widths. No parser pass or cache was added;
the extra context sweep is skipped when no quoted owner was omitted.

The existing partial-copy owner gains four LF/CRLF shapes: an omitted numbered
parent, an enclosing quote, a deeper outer parent, and an included-owner control.
It checks exact real clipboard Markdown, no code blocks, independently parsed
paragraph owners, and unchanged note/selection. The existing Cut transport row
now expects its standalone quote without the omitted two-space outer width;
remaining-note and Undo/Redo expectations are unchanged.

The final two owners fail 20 assertions against the baseline. The repaired,
matching-hash non-AI gate passes 270 tests with zero failures and terminal exit 0,
with the same thirteen AI/chat classes deferred. A malformed deeper-list fixture
and the old Cut spelling expectation were corrected after the first broad run;
the final baseline and final gate both use those corrected tests. Earlier stalled
reporter sessions are not passing or completed baseline evidence. Test-process
symbolication was disabled through an ephemeral argument to avoid that reporting
stall; no app preference or assertion was changed. Evidence:
`artifacts/native-macos/containers260/verification.json`.

Public nested quote/list admission remains guarded. The installed Release app
predates this source repair. Broader clipboard/command and installed acceptance,
performance and full parity remain open. No iOS/AI change, DMG, version bump,
Release rebuild or commit was made.


## admission262: open mapped plain quoted lists in the native rich editor

The plain prose admission path now recognizes lists inside item-owned quotes.
It requires both exact original source export and a complete native item-row
mapping with the same parent graph as swift-markdown. Original-token round trips
alone are insufficient: compact `- > - …` syntax has two parser items on one
physical row and therefore stays Source. Mixed quoted-list/card admission keeps
its previous independent guard. Ordinary notes do not run this extra validation.

The existing workspace owner adds ordinary nested quoted children, an enclosing
root quote with a numbered child, and a deeper quote. It actually hosts the rich
workspace, edits the child, saves exact file bytes, and opens it in a new workspace.
Compact and mixed-card controls stay Source. The existing admission owner moves
the now-supported plain example to its supported group. The baseline fails four
assertions across the two owners; the repaired focused tests pass, followed by
all 270 non-AI tests with zero failures on frozen matching source hashes.

The signed internal Release app (still 0.3.85/build125) opens the ordinary quoted
list in rich mode. Native Computer Use commits a Portuguese acute in its child,
saves exact Markdown, undoes it, outdents its grandchild inside the containing
quote, undoes that, and closes/reopens the note in rich mode. Both QA notes,
including the compact Source control, finish byte-identical to their originals.
This is bounded installed acceptance, not all-command/IME/accessibility parity.
See `artifacts/native-macos/admission262/verification.json`. The preceding
containers261 actual-module diagnostic also confirms standalone copy/paste,
reopen rendering and window-hosted Undo/Redo without adding a duplicate test.

Compact head representation, mixed-card admission, broader cross-container and
clipboard workflows, accessibility/dictation, general performance and full
migration acceptance remain open. AI is deferred. No DMG/version bump, iOS
change or commit was made.


## compact263: separate native rows for shared-line paragraph heads

Compact `- > - Child`, numbered and enclosing-quote forms, deeper quote chains,
and ordinary `- - Child` forms now retain each list item's native identity.
The existing renderer traversal detects shared item lines. Those lines are
expanded into distinct native rows only after comparing the full block tree and
paragraph contents. Immutable source-group metadata preserves original compact
bytes on untouched/body edits; structural changes use expanded Markdown while
keeping the original per-paragraph tokens underneath. Export records all native
heads even when they share one emitted source line. Ordinary notes do not run
compact expansion/tree comparison.

The new primary editor owner covers six LF/CRLF shapes, checking the empty outer
editable row, exact body edits, independently parsed item parents, source expansion
when the outer row gains text, clearing the child, and Undo/Redo/caret restoration.
The public workspace owner now actually opens, edits, saves and reopens the compact
quoted form in rich mode. The representation/admission baseline failed 61 assertions
before the later empty-body control extension. That later control found six failures
in the intermediate candidate: three marker-only heads could join into a thematic
break. Empty bodies now use expanded spelling instead. The filled-parent fixture
also needed a real blank separator before an empty intermediate item; its handwritten
expected spelling was corrected while retaining the independent parent assertions.
The final matching-source non-AI gate passes 271 tests, zero failures, terminal exit 0.

The signed internal Release QA app (still 0.3.85/build125) verifies compact rich
opening, Portuguese accent save with exact compact bytes, outer-row filling with
exact expanded bytes, and close/reopen. Clearing the ordinary three-marker chain
commits and an independent mdast parser confirms `[null,0,1,2,null]`; one Undo
restores its original bytes. Both synthetic notes end byte-identical to their
originals. A native-input follow-up remains: typing Parent into the outer row
creates two Undo groups at the first-character source transition. This is recorded,
not claimed as single-Undo native word typing. Evidence and bounded QA corrections:
`artifacts/native-macos/compact263/verification.json`.

Compact non-paragraph forms, mixed quoted-list/card admission, broader clipboard
and structural workflows, native Undo grouping, accessibility/dictation, general
performance and full migration acceptance remain open. AI stays deferred. No DMG,
version bump, iOS change, commit or publication was made.


## undo264: preserve native word Undo while filling canonical empty heads

The compact263 first-character typing follow-up is repaired. When filling a
canonical empty head, `editingBody` lets NSTextView keep its ordinary typing
transaction only if the candidate's existing metadata exports the same complete
native/parser item graph. Noncanonical marker padding, missing mappings, changed
parents and clearing retain their existing repair/refusal paths. Ordinary
nonempty typing pays no additional parser/cache pass.

The same owned compact fixture and signed Release app now save Parent with exact
expanded bytes, restore the complete original compact note with one Undo, restore
the entire word with one Redo, and return to the original with one final Undo.
Both fixture notes end with their original bytes. An actual-module standalone
run-loop diagnostic matches the native before/after behavior with ordinary prose
as a control. Manual Undo-group XCTest experiments distorted AppKit behavior;
bare/hosted run-loop XCTest variants masked the installed split and passed before
the fix. All experimental test changes were removed, so those trials are not
regression evidence. Existing tests are unchanged; the matching-source non-AI
gate passes 271 tests with zero failures. The Release build and app/nested CLI
signature verification pass. Evidence: `artifacts/native-macos/undo264/verification.json`.

This closes the bounded canonical empty-head word-typing issue, not general
keyboard, IME, accessibility or performance acceptance. Compact non-paragraph and
mixed quoted-list/card forms and broader clipboard/workflow parity remain open.
AI remains deferred. No DMG, version bump, iOS change or commit was made.


## mixed281: mapped quote/list cards

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



## compact286: shared-line heading heads

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
and caret mapping both need repair; no Outline parity is claimed here. Evidence:
`artifacts/native-macos/compact286/outline-followup-results.json`. Broader rich,
clipboard/input/accessibility, performance and final acceptance remain open.
No AI/iOS change, version bump, DMG, commit or publication.


## outline287: nested heading enumeration and native navigation

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


## performance289: unchanged card style assignments

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


## performance290: opener-free wiki conversion

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


## List-owned horizontal rules (rules370, unreleased)

Rules now share parser-owned card identity and current-marker placement with
code/tables. Supported compact and quoted shapes remain rich. The four existing
rule/card/clipboard owners cover representation, formatting, item moves/removal,
selected/edge replacement, composition and Undo/Redo with independent parsed
parents and quote depths. Original-source final baseline fails for the intended
contracts; candidate owners and the matching 275-check non-OCR gate pass.
Installed nested/compact edit, numbered-marker, Portuguese dead-key, boundary
Backspace and Undo checks restore all three original BOM/CRLF files exactly.

Exact Return parity is explicitly pending: native continues after the atomic
rule, while pinned headless web Range/Node selections split items differently.
The earlier discovery requirement that Return simply retain the owner was a
provisional native policy, not verified web behavior. Reconcile live selection
semantics before claiming complete rule parity. See rules370/web-return.json
and rules370/verification.json. No new DMG or performance acceptance claim.

## Ordinary-item divider Return (rules371, unreleased)

DOM-backed pinned web probes establish ordinary before/after caret item splits.
Native now privately prepares a receiving paragraph and runs the existing item
Return transaction, moving the divider and remaining body to the new sibling
when appropriate. Nested and outer-quoted parents remain intact; generated
empty left rows are avoided. Original separators and source ordinals retain
native fidelity rather than adopting whole-export web normalization.

The existing divider owner covers 24 LF/CRLF, numbered/nested/outer-quote flows
with handwritten source, independent parsed owners, typing and Undo/Redo/caret.
Original production fails 72 assertions; final owner and matching 275 non-OCR
checks pass. Optimized signed native before/after Return, exact saves, Undo and
fresh reopen pass with all three original owned notes restored. No new DMG or
version change. See artifacts/native-macos/rules371/verification.json.

Selected-divider, inner-quote and compact Return are still open; the final web
probe records 21 committed-selection DOM workflows and exposes a compact input
displacement anomaly. Those pending cases are not redefined as complete. Six OCR
gates, ordinal/display reconciliation and broader acceptance remain pending.

## Selected horizontal-rule Return (rules372, unreleased)

A selected attachment now stays in the document on Enter. The selected next block
controls whether normal item Return creates a sibling or inner Return creates an
owned paragraph. Root text receives an explicit paragraph split and preserves
bold/code traits without extending a following link. Item preparation remains
private until one existing coordinator commit; Undo restores the selected glyph.

The existing horizontal-rule editor owner adds 62 selected workflows and keeps
all ordinary replacement/deletion/composition controls. The final old-production
baseline fails 238 assertions, the root-format intermediate baseline fails 20,
and the final focused and matching 275 non-OCR gates pass. Signed optimized native
flat/quote/root-bold Return, exact save, Undo and restored Rich text reopen pass.
All four original notes remain exact; both native launches quit normally. No new
DMG or version change. See artifacts/native-macos/rules372/verification.json.

The synthetic DOM reference records 14 selected source workflows. Compact input
placement, root-EOF empty anchors and adjacent quote-role transitions still need
reconciliation, as does inner-quote caret Return. Full desktop/performance and
release acceptance remain incomplete; AI stays deferred.
