<p align="center">
  <img src="public/zerus-logo.svg" alt="Zerus logo" width="96" />
</p>

<h1 align="center">Zerus</h1>

<p align="center">
  A local-first Markdown notes app built around folders, links, and files you own.
</p>

<p align="center">
  <a href="https://github.com/noxtherox/zerus/releases/latest">Download the latest desktop release</a>
  ·
  <a href="docs/CLI.md">CLI guide</a>
  ·
  <a href="docs/ai-chat.md">AI chat guide</a>
</p>

Zerus turns an ordinary folder of Markdown files into a structured knowledge
base. Folders become note types, `[[wikilinks]]` connect ideas, and YAML
frontmatter adds queryable properties without locking your writing into a
proprietary database.

The desktop app reads and writes your files directly. You can keep using the
same vault with a text editor, Git, sync software, or any other Markdown tool.

## Highlights

- **Plain files, real folders** — choose any folder as a vault. A path such as
  `Projects/Active/Zerus.md` appears as a nested type in the sidebar.
- **Focused Markdown editing** — the MDXEditor/Lexical editor supports headings,
  lists, links, tags, pasted images, keyboard-friendly formatting, and advanced
  GFM tables, including spreadsheet paste and a compact large-table editor.
  Resized column widths survive save and reload through an unobtrusive HTML
  comment while the table remains standard, portable GFM Markdown.
  Code blocks are off by default; enable them in **Settings → General → Editor**
  to create blocks with the toolbar, triple backticks, or pasted code.
  Indented prose stays ordinary text. Existing fenced blocks remain editable
  with the setting off, and each offers **Turn back into text**, with Undo support.
  Typing reuses parsed links from unchanged notes and avoids reparsing the
  editor’s own Markdown on each render, reducing work during text entry.
  Images offer expand, edit, and undoable removal actions. Copying images between
  open notes in the same vault preserves their asset references; copying to other
  apps includes image data. Pasted clipboard images are saved as vault assets.
  A heading outline in the desktop properties panel lets you jump through longer
  notes.
  Title edits also reuse unchanged link-stabilization results and skip title
  lookups for labelled ID links, while preserving older title-based links.
- **Connected notes** — use `@` or `[[` to find notes while writing, or choose
  a vault note or web URL from the link dialog. Inline note-link shortcuts can
  be disabled in **Settings → General → Editor**. Preview and follow links from
  the editor, create missing notes, and inspect backlinks grouped by note type. Links and Relation
  properties use stable `zerus-id` targets, so backlinks survive title and path
  changes. Markdown stores readable labels as `[[zerus:<id>|Label]]`; Relation
  values use `zerus:<id>|Label`. Existing unambiguous title links are upgraded by
  the app. Missing or ambiguous legacy targets remain unchanged; links already
  broken by an earlier rename need their target selected again.
- **Structured properties** — define text, URL, number, date, checkbox, list,
  and note-relation fields. Relations synchronize additions and removals in
  both notes; older unpaired relations are upgraded when the vault loads.
  Hiding an inverse field affects its visibility only. Backlinks from note text
  appear alongside relations, above the heading outline. Values remain readable
  YAML frontmatter.
- **Global search** — press ⌘F (Ctrl+F on Windows) or use Search everything to
  find notes, external notes, files, saved links, tasks, and AI conversations.
  Matches include note bodies and frontmatter keys/values, with titles ranked
  first and typo-tolerant fallback. Filter by collection, date, archived state,
  note type/properties, or task status/priority. Trash is excluded; attachments
  match their names and metadata rather than extracted document contents.
  Hover or use arrow keys to preview, click or press Enter to open, and press
  Esc to close search. Find within the current note/PDF uses ⌘⇧F (Ctrl+Shift+F).
  Search remembers queries and filters during the session and shows recently
  opened items when cleared. Mobile provides full-screen search. Ask AI opens
  chat with an unsent query and the selected result as editable context.
- **Fast organization** — search and filter by type, date, and properties;
  combine property filters with all/any matching, select multiple accepted
  values, and compare date properties with presets or exact ranges;
  progressively render large All Notes lists; select multiple notes to pin,
  unpin, archive, unarchive, move to a folder, or update properties in one action;
  bulk-edit shared relations with note pickers and set, clear, add, or remove
  operations while keeping reciprocal relations synchronized;
  reorder types; and use a recoverable vault-local trash. Pin, archive, and
  property actions have undo history. Moving from the editor’s folder picker
  lets you choose the open note or all selected notes in one dialog, including
  external notes. Managed files move with their notes; attachments and external
  file connections stay accessible. External Markdown moves copy local images
  into the vault while keeping the original images for other notes.
  Note-list titles and snippets show readable text without Markdown formatting
  markers or image sources, while preserving the underlying note content.
- **Warm note startup** — desktop and mobile keep a device-local copy of loaded
  note bodies, make that copy usable immediately on the next launch, finish
  warming uncached mobile notes without blocking the first screen, and reconcile
  changed files periodically and whenever the app returns to the foreground.
  Edits saved during startup keep their content and conflict-check baseline when
  the background scan finishes, preventing false conflicts on the next edit.
  Opening a mobile note loads its full body before enabling the editor; cached
  list snippets are never treated as complete note content. Older startup indexes
  keep the note list available while bodies reload. If a cloud scan times out,
  the cached list stays open and Zerus retries when storage becomes available;
  without a usable cache, mobile offers retry and vault selection. Legacy Google Drive working copies can open a
  known note without waiting for unrelated folders to finish scanning. Recently
  opened full notes are saved immediately in a bounded fallback cache, and slower
  local-cache reads can fill in the list without another cloud download. Drive
  note lookups request exact filenames and reuse known parent folders.
- **Projects and planning** — keep tasks and categories beside notes, link tasks
  to their supporting material, and switch between multiple registered vaults.
  Mobile reloads tasks after the vault opens and refreshes them while active and
  when returning to the app.
- **Navigation and recovery** — work across note, type, and global-view tabs;
  triple-click/tap or middle-click notes to open them in a tab. Right-click a
  note in List, Gallery, Kanban, Table, or Calendar for the same note actions,
  including opening a tab, duplicating, archiving, pinning, and editing properties;
  middle-click types or global navigation items to open them in a tab from either
  the expanded or collapsed sidebar. Existing tabs are reused. Reorder tabs by
  dragging them or using their context menu. Right-click a folder and enable
  **Keep folder open** to keep it and its parent folders expanded. The choice
  is remembered per vault on this device and follows folder renames.
  Move backward and
  forward through navigation history and restore earlier versions of a note.
- **Properties pane layout** — drag section handles or use each section's menu
  to reorder Properties, Revisions, Relations, Outline, and Attachments. Click a
  section heading to collapse or expand it. The same controls and a reset are in
  **Settings → General → Properties pane**. The layout applies to all notes in
  the vault and is stored in `.zerus/properties-pane.json`, so it travels with
  the vault. Mobile uses the saved order and collapsed state for its available
  sections. On desktop, **Keep open** preserves the pane's last open or closed
  state across notes and app restarts. Closing it keeps it closed until you
  open it again. With the option off, changing notes closes the pane.
- **Deliberate revisions** — use the Revisions section in note properties on
  desktop, iOS, or the web to keep versions you choose to preserve. **New revision**
  copies the current content and vault files into a new editable version; older
  revisions are read-only and retain their own file bytes. **Make current** copies
  an older revision into a new numbered version. Numbers and creation dates are
  automatic, and revisions remain indefinitely until explicitly deleted.
  Title, properties, folder, pinned status, and archive status belong to the whole
  note. Deleting or restoring a note carries all its revisions with it. Individual
  revisions go to Trash; deleting the current one selects the latest remaining
  revision, and deleting the last one asks to move the whole note to Trash.
  Emptying Trash permanently removes deleted revisions and unreferenced revision
  files. Revision data lives in `.zerus/revisions/`, separately from automatic
  history, and must travel with the vault. Bring external notes and linked files
  into the vault first; missing local files block revision creation so an
  incomplete copy is never presented as preserved. Remote web resources remain
  links. Browser revisions use browser storage and are subject to its quota.
- **Work with files outside the vault** — open standalone Markdown notes without
  importing them; when copying or moving one into the vault, bring its local
  Markdown images into the vault assets folder and update their references;
  attach files; associate notes with PDFs and common office documents; preview
  HTML; and export rendered notes as HTML, PDF, or DOCX.
  Creating a file note asks whether to **Copy into Vault**, **Keep External
  Connection**, or **Keep External Connection + Backup**. The backup option
  keeps the original as the linked file and adds a snapshot copy as an attachment
  in the note; later edits to the original do not update that backup. **Copy into
  Vault** on an existing external file note asks for confirmation before changing
  the link to the vault copy. All choices leave the original file in place.
  The browser supports vault copies; external connections require the native app.
- **Portable cloud file references** — map each shared file location to its local
  folder on every device. File hubs resolve the saved relative path beneath that
  root, including Windows extended paths such as `\\?\G:\My Drive`.
- **Saved links** — keep web links with editable notes in the Links section.
  Edit a saved link's URL without losing its title or notes.
  Choose **Render page** for a live, isolated preview above your notes, resize the
  split, or expand the page. The choice is remembered per URL on this device.
  Sites that block embedding or need browser features may require **Open Link**;
  live previews require a network connection and are not offline HTML copies.
  Markdown autolinks such as `<https://example.com>` open in the formatted editor,
  including links saved by earlier versions.
- **Search PDFs** — switch Find between a file's note and its PDF, highlight
  matches, and move between results. PDF previews support selectable text and
  automatic fit-to-width sizing. Search requires a text layer; scanned PDFs need
  OCR from another tool first.
- **Context-aware AI chat** — use ChatGPT directly on iOS or through Codex on
  desktop, OpenAI, Anthropic,
  OpenRouter, or another compatible API. Choose the notes used as context,
  stream or cancel answers, save answers as notes, and undo supported AI edits.
  On desktop, toggle **Use Pi agent** in AI settings to switch between Pi core
  and the current AI SDK engine. AI SDK remains the default; the choice saves
  on that desktop and applies to the next message. Both engines use the same
  models, note tools, approvals, budgets, and saved history.
  AI link inspection includes body links and relation properties, with incoming
  connections limited to notes in the permitted read context.
  Toggle **Simple mode** in AI settings for a cleaner desktop or mobile chat
  with messages and file uploads; mobile keeps on-device voice dictation.
  The preference follows the vault, and required reviews and undo stay available.
  Upload images, searchable PDFs, and text-based files, or drop them inside chat
  to use them as conversation context without attaching them to the open note.
  Documents use full text when they fit the model context budget and searchable
  excerpts otherwise. Uploads have a 50 MB per-file and 100 MB total processing
  budget, with no fixed document-count limit. Scanned PDFs require external OCR;
  unsupported binary documents must first be exported as text or searchable PDF.
  Desktop and mobile share a notes agent with **Ask**, **Review**, and **Edit**
  modes; Review is the default. Choose whether edits are limited to the current
  note or the selected context. Trash and changes spanning multiple notes require
  approval even in Edit mode. It can search and page through notes, read long
  notes in ranges, patch passages, create notes, update properties and paired
  relations, inspect links, and organize notes. Review shows exact diffs before saving; changes have
  verified receipts, conflict-aware undo, and a durable run journal. Track plans,
  answer questions, queue messages, steer ongoing work, or resume an interrupted
  run. Configure budgets, vault instructions, editable memory, reusable workflows,
  and optional independent analysis, which is off by default and can incur extra
  provider costs. Chat tools stay inside the selected note context; CLI
  compatibility reads use the same boundary.
- **Desktop workflow tools** — reveal notes in the system file manager, open
  links in the browser, use focus mode, or automate a vault through the bundled
  `zerus` CLI. Changes made by the CLI are reflected in the open app, including
  pinned and archived state; archived notes show an editor banner and an
  unarchive action when they are included in the current view. CLI note-list,
  note-get, and search JSON includes parsed YAML frontmatter in `properties`.
- **Personalized workspace** — resize or collapse panels and choose from built-in
  light and dark themes, type icons, and list, gallery, board, table, or calendar
  type views. Set the note column's width and left or centered alignment in
  **Settings → Appearance**. Save named view presets to reuse a type's layout,
  grouping, visible properties, sorting, and filters. Delete a saved preset with the trash icon in
  the view menu; your current layout and notes stay intact.

## Platforms

The mobile workspace has bottom navigation for Notes, Tasks, global Search, and
AI, with a highlighted New button in the center. Note navigation swipes start
at the screen edges so tables can scroll horizontally. Sort and filter opens a
mobile sheet, and a downward-arrow control dismisses the keyboard while editing. In AI
chat, tapping the conversation area dismisses the keyboard without a separate button. The
library includes saved Links, Files, external
notes, types, and Recently Deleted. Mobile uses the desktop sort/date/property
filters and bulk pin, archive, and property actions, including action previews
and undo history. Saved web addresses can be added, opened, and edited alongside
their notes. Returning from a task's linked note restores that task's details.
The browser `/app` route uses this workspace below 768px; `/mobile` always opens
the mobile interface. Desktop board, table, gallery, calendar, and saved-view
layouts remain desktop features. See the [mobile review](docs/mobile-audit/README.md)
for the verified flows and remaining native-device checks.

| Platform | Status | Vault storage |
| --- | --- | --- |
| macOS Apple Silicon | Desktop release with signed automatic updates | Local filesystem |
| Windows 10/11 | Microsoft Store app; unsigned per-user EXE download | Local filesystem |
| iOS 26+ | SwiftUI mobile app | Files selected through the mobile vault picker |
| Browser | Development and interface preview | Browser local storage |

Download the current macOS DMG or Windows installer from
[GitHub Releases](https://github.com/noxtherox/zerus/releases/latest). The iOS
build is produced and distributed separately through the App Store/TestFlight
workflow. Windows users can also install [Zerus from Microsoft Store](https://apps.microsoft.com/detail/9P019ZG6HD8Q).

**SwiftUI is the production iOS app** for iOS 26+, owned by
`native-ios/`. It uses Apple's TextKit 2 editor and replaces Tauri mobile under
the existing `com.zerus.notes` identity as **Zerus**. The old vault bookmark is
reused on upgrade; Files can renew folder access if needed. Preview-app data
under `com.zerus.notes.native` stays separate; select its vault through Files. The current native migration goal excludes AI and Google Drive
integration; their existing preview implementations are retained separately from
the remaining completion criteria. The preview includes native rich editing, formatted HTML/RTFD
paste with portable images and an adaptive paste sheet that dismisses the active keyboard,
a visible keyboard-dismiss button in the iOS 27 formatting toolbar,
stable formatting across newly typed text runs, and table-cell composition,
local image loading with automatic retries, visible progress and manual retry,
bounded provider-image reads for vault notes and external project files,
metadata-aware external image refresh that retains previews, selection and Undo,
foreground refresh of loaded vault/revision images and a direct Refresh images action,
reviewed image removal with Undo, native previews, shared-file protection and image Trash restore/deletion,
code/table/image previews that follow appearance, text size and available width without clearing Undo,
with table footers that wrap at accessibility text sizes and full-size native
collection/task choices at accessibility sizes,
properties/relations with reviewed conversion between ordinary fields and reciprocal links,
note-link insertion at the cursor or selection with mixed label formatting,
`@`/`[[` suggestions and an optional shortcut setting,
native back/forward note navigation with saved open-note/history/reading-position restoration, a note outline with local/cross-note heading jumps, reviewed title/file renaming and moves, revisions with independent file snapshots, reviewed permanent note/revision cleanup,
automatic history with image recovery, external-edit capture and reviewed vault-wide
cleanup, foreground file refresh, saved vault switching with bookmark-based folder identity
and explicit selection between duplicate registrations, per-vault default note folders,
device date formats, note-link and code-block creation preferences, undoable conversion
of existing code blocks to literal text, readable Markdown/link excerpts, native collection sorting with
date/folder/typed-property filters, reviewed bulk pin/archive/property/relation changes
with durable undo/redo and repeatable change reviews, saved links with editable addresses and folder
filing, task planning with lists, categories and supporting notes, private task drafts
that survive closing and restarting, unified search
across notes/external Markdown/tasks/files/links/conversations, document notes with portable copies,
original-file connections, frozen backups and Files-based device folder mappings, editable external
Markdown files with private recovery drafts, explicitly selected project attachments,
reviewed copy/move into a vault and interrupted-move recovery, read-only external
references in Ask’s context picker, inline image retries and refreshed local previews
when Files reports resource changes, without closing the editor, native PDF/Word/HTML
exports with system previews and direct Save to Files, local AI chat history bound to saved
vault identities across folder moves and app-container updates, native editors for
shared vault instructions and editable AI memory, per-vault AI limits and reasoning
effort with native token estimation and timed cancellation, built-in and custom
Markdown workflows with native creation/editing and saved per-run instructions,
ordered AI plans with saved Pending, In progress and Complete states,
device-private ChatGPT continuation for native runs across app restarts,
conversations that reopen at the latest reply with an explicit return from older messages,
dedicated on-device dictation into unsent prompts, Files/Photos attachments with native previews,
private drafts, PDF/text extraction and actual image inputs, and native
Ask/Review/Edit body and typed-property tools with explicit scope, native before/after
review, inherited-schema reads, coordinated edits to configured reciprocal links,
durable journals, verified receipts and conflict-aware undo. Linked changes wait
for review when they affect multiple notes, including in Edit mode; every linked
note must be in the writable context and freshly read. Configure missing relation
pairs and legacy note identities in the native property editor first.
Notes use compact spacing, and bulk-selection controls stack at accessibility
text sizes so their labels stay readable. Bulk actions have larger touch targets,
and secondary text in Notes, Tasks and Library uses stronger adaptive contrast. The user accepts the current accessibility options for this native-testing goal.
See the [native iOS guide](docs/native-ios.md) for build,
installation, storage safeguards, and the remaining feature-parity limitations.
The [completion review](docs/native-ios-completion-review.md) records current
acceptance evidence and remaining work. **AI and Google Drive integration work
are excluded from the native migration goal.** Existing integrations remain.

Signed native preview **0.3.107/1** is installed and launch-verified on
**iPhone 18 Pro Max**, running iOS 27.2. It includes the new Library/Notes
navigation, the Notes/Tasks/Ask/Search/New note bottom bar, and collection actions
grouped in Settings. The existing 483-note workspace reopens after the update.
It retains the accumulated native folder catalogue,
reviewed folder rename and recoverable folder Trash/restore, independent custom
light/dark palettes with 11 presets and saved themes, and Find within vault/external
notes. Find searches full code/table text, shows contextual results and reveals a
temporary highlight without editing the note.

The earlier 0.3.106 iPhone 11 verification confirmed that the reported Collapse
chart legend note renders its heading, bold prose and original image correctly. Find returns 10 legend matches and reveals
the selected occurrence. Appearance and folder actions are inspected without
changing phone settings or folders. The original 483-note workspace is restored;
all backed-up local Documents and private support files remain byte exact, and
all 59 diagnostic entries are unchanged. The agreed native testing goal is complete,
with AI/Drive work excluded, current accessibility accepted and the composing-
keyboard check explicitly deferred. See the completion review for supported limits.

Previous preview105 delivered large-text saved-vault/Recent/details layouts and
external-file retry/recovery; its physical layout and Quick Look proof remain.

Physical local-file unavailability/retry/return recovery now passes with source
bytes preserved. Physical prewrite interruption/cold recovery also passes, with
the QA note restored afterward. Cloud-provider disconnection remains unverified;
the composing-keyboard check is explicitly deferred. The unfiltered
four-screen journey completes but its Apple audit still fails with 36 findings, with all findings
retained. The completion review distinguishes current device proof, local recovery
checks and remaining limits. Related fixes are batched before device updates;
repeated typing benchmarks have stopped.
The previously verified scoped UIKit search-placeholder adjustment is included
in106. No further accessibility work or new audit accompanies this batch.

The browser preview and existing App Store pipeline continue to use the
established mobile interface.

## How the vault works

```text
My Vault/
├── Projects/
│   ├── Active/
│   │   └── Zerus.md
│   └── Project Index.md
├── People/
│   └── Ada.md
├── assets/                 # pasted and dropped images
├── .zerus/                 # Zerus's vault metadata
└── .trash/                 # recoverable deleted notes
```

Each `.md` file is a note. Zerus derives its type from its containing folders,
up to eight levels deep. Moving a note to another type moves the file; changing
the title line renames it in the established interface. The SwiftUI preview
keeps the current filename during heading edits and offers reviewed Rename note.
Property values stay in the note's frontmatter, while
vault-wide property definitions and display metadata live under `.zerus/`.

## Getting started

### Prerequisites

- [Node.js 22.19 or newer](https://nodejs.org/) and [pnpm](https://pnpm.io/)
- [Rust](https://www.rust-lang.org/tools/install) and the
  [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/) for desktop
  development

### Install and run

```sh
pnpm install

# Browser development mode (uses a virtual vault in localStorage)
pnpm dev

# Desktop development mode (uses the real filesystem)
pnpm desktop:dev
```

Vite serves the browser app at `http://localhost:8080` by default. On first
desktop launch, choose the folder you want Zerus to use as its vault.

## Development

```sh
pnpm test            # run the Vitest suite
pnpm lint            # check ESLint rules
pnpm typecheck       # check the TypeScript projects
pnpm build           # build the web app
pnpm platform:verify # validate platform-specific packaging boundaries
pnpm ios:native:verify # validate the independent SwiftUI app configuration
pnpm ios:shared:test # test the shared Apple ChatGPT core
pnpm ios:native:build # build the SwiftUI device app
pnpm desktop:build   # build and verify the macOS DMG
pnpm windows:build   # build the unsigned Windows NSIS EXE (run on Windows)
pnpm windows:msix    # build an unsigned Store MSIX (Windows + Store identity)
```

On macOS, `pnpm desktop:build` creates a distribution-signed, notarized, and
verified DMG and requires the configured signing and notarization credentials.
Use `pnpm desktop:build:local` for an explicitly ad-hoc local build that skips
notarization. Both Tauri commands require the updater signing key described below. The
separate SwiftUI commands and native Sparkle requirements are documented in
[Native macOS migration preview](#native-macos-migration-preview).

Windows-specific prerequisites and commands are in
[`docs/WINDOWS.md`](docs/WINDOWS.md). To create a new signed iOS archive and
export its IPA for the SwiftUI iOS app, use `pnpm ios:new-build`; see
[`docs/testflight-cli.md`](docs/testflight-cli.md) before uploading it.
`pnpm testflight` uploads the native IPA to the existing Zerus TestFlight app.
Legacy Tauri commands remain explicitly available as `ios:tauri:new-build` and
`ios:tauri:testflight`. Native release versions live in `native-ios/project.yml`.
See [`docs/ios-apps.md`](docs/ios-apps.md) for ownership and upgrade details.
The legacy Tauri iOS build phase selects SwiftPM's native engine for compatibility with the
current Rust-to-Swift bridge on Xcode 27, and checks the archived app's scene
lifecycle and signature before export.

Official tagged releases import the Developer ID Application certificate in
GitHub Actions, authenticate to Apple's notary service with a Team App Store
Connect API key, and require both Gatekeeper acceptance and stapled
notarization tickets before the draft release is published.

## Releases and automatic updates

Microsoft Store builds check for Store updates on launch and every six hours.
The in-app prompt offers **Update** or **Remind me later** (24 hours). Zerus saves
pending notes before installation and blocks it on save errors or unresolved
conflicts. Microsoft handles confirmation and installation and may close the app.
These checks are included starting with Windows v0.3.25 and require the
Store-installed app; they do not run in the web preview.

To publish a new desktop version, start from a clean, up-to-date `main` branch
and run the command with the intended next semantic version:

```sh
pnpm release <major.minor.patch>
```

The release command verifies the build and tests, keeps the Tauri and Rust
versions in sync, commits the version bump, creates the matching version tag,
and pushes both atomically. GitHub Actions then builds the notarized Apple
Silicon DMG, signed macOS updater bundle, and unsigned Windows NSIS EXE.

The verified macOS release is published first, after notarization and stapling.
The Windows job then builds and attaches the NSIS installer. Microsoft Store
MSIX packaging and Partner Center submission are separate, explicitly requested
release operations documented in [the Windows packaging guide](docs/WINDOWS.md).
A Windows packaging failure does not withdraw the already-verified macOS release.
Installed macOS copies check `latest.json` on launch and every six hours. When an
update is available, the user can install it or ask Zerus to remind them again
in 24 hours.

The updater private key is stored in the repository's
`TAURI_SIGNING_PRIVATE_KEY` Actions secret. Back up the local key at
`~/.tauri/zerus-updater.key`; losing it prevents existing installations from
accepting future updates.

## Native macOS migration preview

The separate SwiftUI app in `native-macos/` requires **Apple Silicon and macOS
26+**. Its **Zerus Native** identity lets it coexist with the current Tauri
desktop release. It uses the same Markdown vault and shared Apple storage
services. It is still a migration preview; the current GitHub desktop release
has not been replaced. Current implementation and acceptance evidence are in
[the native macOS guide](docs/native-macos.md) and the
[non-AI acceptance ledger](docs/native-macos-non-ai-acceptance.md).

The native app currently includes:

- **Workspace and navigation:** a fully hideable folders sidebar; persistent
  note, folder and global-view tabs; pins, back/forward, separate windows,
  compact layouts and interface zoom. Tabs stay within content panes and never
  span above the sidebar. Gallery, Kanban, Table and Calendar show
  either the collection or the opened note. List retains its adjacent editor.
- **Editing:** AppKit rich text and literal Source mode, inline formatting,
  all six heading levels and paragraph shortcuts (⌘⌥0–6),
  web/vault links with a shared dialog (⌘K), edit/remove/copy and retained labels,
  nested lists/quotes, numbered checklists, Markdown shortcuts, item-aware
  Return/indent/outdent, checked selection replacement and structured paste,
  native Undo/Redo, note-link suggestions and heading navigation. Supported
  list-owned headings, quotes, code and tables edit natively when their
  ownership maps to the native representation; unsupported containers and HTML
  retain editable Source mode.
  A body starting after its empty list marker still edits as one native item.
  Unchanged syntax and UTF-8 BOM/line endings are preserved. The code-block
  creation setting does not prevent editing existing blocks.
- **Code, tables and images:** editable code cards and sheets, basic syntax
  colours, conversion back to literal text from the vault-editor Paragraph menu, GFM table
  cells with row/column insertion, removal and movement, alignment and width
  controls, spreadsheet paste, shared address/local-file image insertion,
  description/title/size controls, image edit/expand/removal, portable pasted
  assets and reviewed image management. Visible HTTP(S) images load in the
  editor with a Reload action; Source does not fetch them. External insertion
  copies local assets into the chosen project folder. Sized HTML image references
  carry their local assets through native cross-vault clipboard transfer while
  preserving dimensions and other attributes. Covers use bounded local
  thumbnails; they never fetch remote images. Unknown languages and very large code blocks remain editable without
  syntax colouring.
- **Organization and collections:** typed/inherited properties, paired
  relations and backlinks, reviewed schema/legacy-relation repairs, bulk
  properties and moves, durable reviewed organization Undo/Redo, and shared
  List/Gallery/Kanban/Table/Calendar layouts, filters and named views. Folder
  ordering, keep-open state and default new-note destinations are device-local
  per vault; Tabler/emoji icons and properties-pane layout use shared metadata.
- **Tasks:** lists/categories, planning and filters, supporting-note links,
  numeric date preferences with ISO storage, and private task-draft recovery,
  export, reload and save-as-new. Failed saves keep the draft available.
- **Files and Finder:** Finder/Open With delivery, including cold launch and
  multiple files. Vault notes open in place; outside Markdown uses editable
  original connections with inline code and shared table/code sheets, code-to-text,
  and Undo/Redo in Rich or full Source. Other documents create/reuse a file note in the
  receiving vault's default folder. Alternate document-handler declarations
  preserve existing default applications. File notes support vault copies,
  original connections and frozen backups, with private local mappings for
  shared locations. External Markdown copy/move reviews bring local resources
  into the vault and protect changed originals.
- **Previews and exports:** native PDF text search/navigation/password unlock,
  office Quick Look, safe HTML and explicit content-bound Full preview,
  saved links with opt-in live pages, HTML/PDF/DOCX export and native Print.
  PDF search requires a text layer; passwords apply only to the current preview
  and are not persisted. Full HTML/live-page modes may access the network.
- **Search and recovery:** ranked notes/tasks/saved-links/external-file search,
  bounded PDF/text extraction, deliberate revisions, automatic history with
  frozen resources, comparisons, Keep/labels, retention and reviewed cleanup.
  Per-window note checkpoints and external/task drafts protect unsaved text.
  Changed or unavailable originals retain drafts instead of being overwritten.
  Device-local warm snapshots open while a fresh inventory reconciles files;
  failed refreshes keep the cached workspace available with Retry.
- **Settings and CLI:** light/dark/system appearance, separate editable palettes
  and named presets, numeric dates, pane order/collapse and zoom; reviewed
  companion settings import; bundled CLI/skills with hash checks, reviewed
  install/export, vault registration and note-metadata preparation. Setup
  includes hidden and `.markdown` files counted by the CLI and refuses invalid,
  duplicate or noncanonical note IDs. It never executes an existing CLI just
  to identify it.
  Custom colour editing starts with Zerus’s active appearance, including when
  it differs from macOS. The inspector follows the palette’s surface colour.

AI/chat implementations remain present, but their acceptance is deferred by
agreement. Performance work has been accepted. Installed Settings, CLI lifecycle,
relation repair, pane layout, Kanban/folder/tab dragging, minimum-window resizing,
overflow scrolling and Portuguese dead-key Save/Undo/Redo/reopen are verified.
The Developer ID candidate, signed update installation and notarized DMG install
path are also verified. Local iOS/macOS note-and-image interchange is accepted;
Windows and direct Google Drive are outside this migration's current scope.
VoiceOver QA and microphone dictation are excluded from this goal by
agreement. Neither is claimed as verified. The ledger distinguishes verified behavior from broader
coverage limits. This is not a completed production release.

### Native development and packaging

Use Node/pnpm, Xcode with the selected supported macOS toolchain, XcodeGen, and
Rust/Cargo for the standalone CLI. Swift package versions and deployment/version
settings are pinned in `native-macos/project.yml`.

```sh
pnpm macos:native:build           # optimized app, no DMG or version increment
pnpm macos:native:test            # native macOS tests
pnpm macos:native:channel        # inspect production feed/key defaults; no build
pnpm macos:native:appcast --help  # prepare/verify signed native update artifacts
pnpm desktop:build --native      # distribution-signed, notarized native DMG
pnpm desktop:build --native --local # explicitly ad-hoc DMG, no notarization
```

Intermediate QA uses the built app; another DMG is unnecessary unless a check
needs packaging or the final handoff is ready. Artifacts are under
`artifacts/native-macos/`. The canonical native Mac version is in
`native-macos/project.yml`; the theme-correction build is 0.3.85/build126.
Presets and saved palettes select their matching Light/Dark appearance, including
native title bars, controls, sheets and popovers. Its implementation is newer
than the last delivered Preview125 DMG. A separate
configured Developer ID candidate has passed Apple notarization, ticket
validation, Gatekeeper assessment and a controlled launch. It remains private;
production update delivery remains separate. The corrected native build126 DMG
is notarized, stapled and checked through its private download endpoint.

Native distribution packaging needs a Developer ID Application identity and
notarization credentials. Production packaging defaults to the approved separate
GitHub Sparkle channel in `native-macos/update-channel.json`; its private signing
key stays in the `zerus-native` Keychain account. The public feed/key can be
overridden together with `ZERUS_NATIVE_UPDATE_FEED_URL` and
`ZERUS_NATIVE_UPDATE_PUBLIC_KEY`; a partial override is refused. Internal builds
still omit the production defaults unless both values are supplied explicitly.
The current internal app reports that its update channel is unavailable. This
configuration does not publish a GitHub release or appcast and does not change
the Tauri updater. Never put private signing keys in the vault or repository. See [native update configuration](docs/native-macos.md#native-update-channel-development).

Packaging signs the CLI and Sparkle helpers before the app, verifies the actual
bundle identity/version/deployment target/architecture and signing channel,
then mounts and rechecks the DMG payload. The JSON receipt records checksums and
signature status. Distribution DMGs must pass notarization, stapling and
Gatekeeper checks. Installed interaction and production update-channel checks
remain separate requirements; an artifact receipt does not establish them.

`pnpm macos:native:appcast prepare` creates a signed ZIP/feed in a new directory
from the already configured app, and `verify` checks signatures, channel metadata,
and the exact archived app. Keys stay in an explicitly selected native Keychain
account or a protected CI file. These commands do not publish or create a DMG;
see [native update artifact preparation](docs/native-macos.md#preparing-native-update-artifacts).

## Architecture

The project is built with React 19, TypeScript, MDXEditor and Lexical, Tailwind
CSS, shadcn/ui, and Tauri 2. The native Rust layer provides filesystem
integration, desktop file opening, secure AI credentials, CLI support, and
native packaging.

```text
src/                  React application and browser vault
src/components/       editor, notes, AI chat, and shared UI
src/lib/              Markdown, filtering, properties, links, and vault helpers
src/store/            note, vault, and task state
src-tauri/            Tauri desktop/mobile runtime, permissions, and packaging
native-ios/           production SwiftUI iOS app, resources, and tests
packages/apple/       shared iOS services and ChatGPT protocol packages
```

## AI and privacy

AI chat is optional. Your Markdown vault and conversation history remain local,
but when you send a cloud AI request, Zerus sends the selected note excerpts,
folder context, uploaded images and document text, conversation history, and prompt needed to answer it to the
provider you selected. Review that provider's privacy and billing terms before
using it.

Direct-provider API keys are stored in the device's secure credential store
when supported, never in the vault or browser storage. The ChatGPT through Codex
option on desktop delegates browser sign-in and credentials to the installed
Codex app-server. On iOS, **Chat model → ChatGPT** connects an eligible account
directly, keeps its renewable credentials in device-only Keychain storage, and
uses the account's model catalog and shared plan allowance. Saved account
selection, reconnection, sign-out and usage controls are included; see
[`docs/chatgpt-ios.md`](docs/chatgpt-ios.md). The browser development preview
exercises the chat interface using
local excerpts and does not contact an AI provider.

For context selection, shared desktop/mobile conversation history, response
actions, and retention behavior, see [`docs/ai-chat.md`](docs/ai-chat.md).

## CLI and further documentation

The desktop app can install the `zerus` CLI and optional agent skills from
**Settings → CLI**. The CLI reads and updates local vaults using explicit
selectors, revision checks, atomic writes, and guarded destructive operations.
CLI **0.3.0** and agent skill **3** add task-list selection and preserve task
metadata during writes. Edits to existing paired relation properties synchronize
both notes with a shared, conflict-checked undo transaction. Upgrade older CLI
installations before changing tasks or relations. Deliberate revision management
and relation-schema configuration remain in the app.
CLI **0.3.1** and skill **4** preserve native BOM-prefixed metadata/body, support
reserved scalar comments and ignore nested foreign metadata keys. The native preview
includes reviewed CLI vault registration and note preparation.
See [`docs/CLI.md`](docs/CLI.md) for commands and automation guidance.

- [`docs/tables.md`](docs/tables.md) — table editing, large tables, recovery,
  and verification
- [`docs/WINDOWS.md`](docs/WINDOWS.md) — Windows development and packaging
- [`docs/testflight-cli.md`](docs/testflight-cli.md) — iOS archives, IPA export,
  and TestFlight upload

## Built with Codex and GPT-5.6

A substantial part of Zerus's recent development was completed through an
iterative human–AI workflow using [OpenAI Codex](https://openai.com/codex/) with
GPT-5.6.

- **Product direction stayed human-led.** Features began with concrete goals,
  screenshots, interaction feedback, and acceptance decisions from the project
  owner.
- **Codex worked in the real repository.** It explored the existing codebase,
  edited React, TypeScript, and Rust files, followed changes across the Tauri
  boundary, and used Git and GitHub to keep the work reviewable.
- **GPT-5.6 powered the reasoning.** The model helped turn product requests into
  implementation plans, trace behavior across multiple files and languages,
  diagnose failures, and propose focused changes.
- **Changes were validated, not simply generated.** Codex ran targeted tests,
  lint and production builds where appropriate, inspected diffs, and iterated on
  issues found during live desktop and browser checks.

Codex and GPT-5.6 were development tools; those development sessions are not
bundled into the app. Zerus does include optional AI integrations, but an
OpenAI account or API key is required only when the user selects an OpenAI- or
ChatGPT-backed provider.

## Project status

Zerus is under active development. The browser build is useful for previewing
the interface, but its vault is stored in browser local storage; use the desktop
app when you want Zerus to work directly with files on disk.

Zerus is available under the [MIT License](LICENSE).

### File locations on iOS

Use Files/iCloud Drive or on-device storage. Direct Google Drive vault,
linked-file mapping, account/folder browsing and sync controls are removed from
the native app. Existing connection records, cached working copies, recovery
drafts and credentials are retained; this change does not delete notes or
remote files. Old direct mappings can be replaced by choosing a folder or
locating an individual document through Files. No Google OAuth setup or live
Drive acceptance is required for the native migration.

For files mapped through Apple's Files picker, iOS may require selecting an
individual file again when access to its folder expires. Zerus offers that
selection when opening the file and saves an authorized local preview copy.
