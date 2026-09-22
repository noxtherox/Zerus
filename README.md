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
  Images offer expand, edit, and undoable removal actions. A heading outline
  lets you jump through longer notes and can stay pinned open.
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
  and note-relation fields. Values remain readable YAML frontmatter.
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
  unpin, archive, unarchive, or update properties in one action; reorder types;
  and use a recoverable vault-local trash. Recent bulk actions can be undone.
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
  without a usable cache, mobile offers retry and vault selection. Google Drive can open a
  known note without waiting for unrelated folders to finish scanning. Recently
  opened full notes are saved immediately in a bounded fallback cache, and slower
  local-cache reads can fill in the list without another cloud download. Drive
  note lookups request exact filenames and reuse known parent folders.
- **Projects and planning** — keep tasks and categories beside notes, link tasks
  to their supporting material, and switch between multiple registered vaults.
  Mobile reloads tasks after the vault opens and refreshes them while active and
  when returning to the app.
- **Navigation and recovery** — work across note, type, and global-view tabs;
  middle-click types or global navigation items to open them in a tab from either
  the expanded or collapsed sidebar. Existing tabs are reused. Move backward and
  forward through navigation history and restore earlier versions of a note.
- **Work with files outside the vault** — open standalone Markdown notes without
  importing them; when copying or moving one into the vault, bring its local
  Markdown images into the vault assets folder and update their references;
  attach files; associate notes with PDFs and common office documents; preview
  HTML; and export rendered notes as HTML, PDF, or DOCX.
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
- **Context-aware AI chat** — use ChatGPT through Codex, OpenAI, Anthropic,
  OpenRouter, or another compatible API. Choose the notes used as context,
  stream or cancel answers, save answers as notes, and undo supported AI edits.
  Upload images, searchable PDFs, and text-based files, or drop them inside chat
  to use them as conversation context without attaching them to the open note.
  Documents use full text when they fit the model context budget and searchable
  excerpts otherwise. Uploads have a 50 MB per-file and 100 MB total processing
  budget, with no fixed document-count limit. Scanned PDFs require external OCR;
  unsupported binary documents must first be exported as text or searchable PDF.
  On desktop, AI chat can use the complete bundled `zerus` CLI against the
  active vault; mutating commands require an explicit current request.
  Destructive and CLI approval-gated actions are previewed with a concise
  impact summary, then only the exact previewed action can run after the user
  explicitly consents in a later message. Follow-up questions retain the prior
  CLI activity and errors as untrusted history so Zerus can explain what
  happened without treating tool output as instructions.
- **Desktop workflow tools** — reveal notes in the system file manager, open
  links in the browser, use focus mode, or automate a vault through the bundled
  `zerus` CLI. Changes made by the CLI are reflected in the open app, including
  pinned and archived state; archived notes show an editor banner and an
  unarchive action when they are included in the current view. CLI note-list,
  note-get, and search JSON includes parsed YAML frontmatter in `properties`.
- **Personalized workspace** — resize or collapse panels and choose from built-in
  light and dark themes, type icons, and list, gallery, board, table, or calendar
  type views. Save named view presets to reuse a type's layout, grouping, visible
  properties, sorting, and filters.

## Platforms

The mobile workspace has bottom navigation for Notes, Tasks, global Search, and
AI, with a highlighted New button in the center. Note navigation swipes start
at the screen edges so tables can scroll horizontally. Sort and filter opens a
mobile sheet, and a Done control dismisses the keyboard while editing. The
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
| iOS 17+ | Native mobile app | Files selected through the mobile vault picker |
| Browser | Development and interface preview | Browser local storage |

Download the current macOS DMG or Windows installer from
[GitHub Releases](https://github.com/noxtherox/zerus/releases/latest). The iOS
build is produced and distributed separately through the App Store/TestFlight
workflow. Windows users can also install [Zerus from Microsoft Store](https://apps.microsoft.com/detail/9P019ZG6HD8Q).

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
the title line renames it. Property values stay in the note's frontmatter, while
vault-wide property definitions and display metadata live under `.zerus/`.

## Getting started

### Prerequisites

- [Node.js 22.13 or newer](https://nodejs.org/) and [pnpm](https://pnpm.io/)
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
pnpm desktop:build   # build and verify the macOS DMG
pnpm windows:build   # build the unsigned Windows NSIS EXE (run on Windows)
pnpm windows:msix    # build an unsigned Store MSIX (Windows + Store identity)
```

On macOS, `pnpm desktop:build` creates a distribution-signed, notarized, and
verified DMG and requires the configured signing and notarization credentials.
Use `pnpm desktop:build:local` for an explicitly ad-hoc local build that skips
notarization. Both commands require the updater signing key described below.

Windows-specific prerequisites and commands are in
[`docs/WINDOWS.md`](docs/WINDOWS.md). To create a new signed iOS archive and
export its IPA, use `pnpm ios:new-build`; see
[`docs/testflight-cli.md`](docs/testflight-cli.md) before uploading it.
The iOS build phase selects SwiftPM's native engine for compatibility with the
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
src-tauri/            Rust desktop shell, permissions, and packaging
```

## AI and privacy

AI chat is optional. Your Markdown vault and conversation history remain local,
but when you send a cloud AI request, Zerus sends the selected note excerpts,
folder context, uploaded images and document text, conversation history, and prompt needed to answer it to the
provider you selected. Review that provider's privacy and billing terms before
using it.

Direct-provider API keys are stored in the device's secure credential store
when supported, never in the vault or browser storage. The ChatGPT through Codex
option delegates browser sign-in and credentials to the installed Codex
app-server. The browser development preview exercises the chat interface using
local excerpts and does not contact an AI provider.

For context selection, shared desktop/mobile conversation history, response
actions, and retention behavior, see [`docs/ai-chat.md`](docs/ai-chat.md).

## CLI and further documentation

The desktop app can install the `zerus` CLI and optional agent skills from
**Settings → CLI**. The CLI reads and updates local vaults using explicit
selectors, revision checks, atomic writes, and guarded destructive operations.
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

### Google Drive vaults on iOS

The iOS app includes a direct Google Drive connection in vault setup, bypassing
Drive's unsupported folder selection in Apple's Files picker. It opens an existing
My Drive folder and reads/writes its Markdown notes and assets. An iOS Google OAuth
client must be configured before sign-in works; see [Google Drive setup](docs/google-drive-ios.md).

If the folder contains duplicate names, the Drive picker shows each copy's dates
and offers text previews and individual renaming. This preserves both copies and
checks for remaining conflicts before opening the vault. Renames apply to Google
Drive on all devices; keep the original name on the copy existing links should open.

This initial integration requires connectivity for loading and saving. It keeps
local recovery copies of note edits, warms previously loaded note bodies for a
faster launch, checks for conflicting remote changes, and refreshes periodically
while Zerus is active and whenever it returns to the foreground. It is not an
offline or iOS system-background sync service.
On iOS, mapping a synced file location asks whether it uses Files/iCloud Drive or
Google Drive. The Google Drive option opens the same authenticated folder browser
instead of Apple's unsupported Files-provider folder mapping.
Linked files in that location can be checked, previewed, and opened through the
Drive API using the existing device sign-in. Shared drives, shortcuts, and uploads
above 25 MB are not supported. Actual Google sign-in and file operations must be
verified on an iPhone with the configured OAuth client before shipping.
For files mapped through Apple's Files picker, iOS may require selecting an
individual file again when access to its folder expires. Zerus offers that
selection when opening the file and saves an authorized local preview copy.
