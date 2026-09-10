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
- **Connected notes** — autocomplete `[[wikilinks]]`, follow links from the
  editor, create missing notes, and inspect backlinks grouped by note type.
- **Structured properties** — define text, URL, number, date, checkbox, list,
  and note-relation fields. Values remain readable YAML frontmatter.
- **Fast organization** — search and filter by type, date, and properties;
  reorder types; pin or archive notes; and use a recoverable vault-local trash.
- **Projects and planning** — keep tasks and categories beside notes, link tasks
  to their supporting material, and switch between multiple registered vaults.
- **Navigation and recovery** — work across note tabs, move backward and forward
  through navigation history, and restore earlier versions of a note.
- **Work with files outside the vault** — open standalone Markdown notes without
  importing them; attach files; associate notes with PDFs and common office
  documents; preview HTML; and export rendered notes as HTML, PDF, or DOCX.
- **Saved links** — keep web links with editable notes in the Links section.
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
- **Desktop workflow tools** — reveal notes in the system file manager, open
  links in the browser, use focus mode, or automate a vault through the bundled
  `zerus` CLI.
- **Personalized workspace** — resize or collapse panels and choose from built-in
  light and dark themes, type icons, and alternative type views.

## Platforms

| Platform | Status | Vault storage |
| --- | --- | --- |
| macOS Apple Silicon | Desktop release with signed automatic updates | Local filesystem |
| Windows 10/11 | Unsigned per-user EXE; MSIX packaging for Store submission | Local filesystem |
| iOS 17+ | Native mobile app | Files selected through the mobile vault picker |
| Browser | Development and interface preview | Browser local storage |

Download the current macOS DMG or Windows installer from
[GitHub Releases](https://github.com/noxtherox/zerus/releases/latest). The iOS
build is produced and distributed separately through the App Store/TestFlight
workflow.

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

Official tagged releases import the Developer ID Application certificate in
GitHub Actions, authenticate to Apple's notary service with a Team App Store
Connect API key, and require both Gatekeeper acceptance and stapled
notarization tickets before the draft release is published.

## Releases and automatic updates

To publish a new desktop version, start from a clean, up-to-date `main` branch
and run the command with the intended next semantic version:

```sh
pnpm release <major.minor.patch>
```

The release command verifies the build and tests, keeps the Tauri and Rust
versions in sync, commits the version bump, creates the matching version tag,
and pushes both atomically. GitHub Actions then builds the notarized Apple
Silicon DMG, signed macOS updater bundle, and unsigned Windows NSIS EXE. An unsigned
Microsoft Store MSIX is also built when all three Partner Center identity variables in
[the Windows packaging guide](docs/WINDOWS.md) are configured. Store packaging is
skipped when none are configured; partial configuration blocks publication. The release is published only after both
platform jobs succeed. The MSIX asset is a Store submission artifact, not a
direct-install download. Store certification, signing, and publication happen
separately in Partner Center. Installed macOS copies check
`latest.json` on launch and every six hours. When an update is available, the
user can install it or ask Zerus to remind them again in 24 hours.

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
