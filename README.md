<p align="center">
  <img src="public/grimoire-logo.svg" alt="Grimoire logo" width="96" />
</p>

<h1 align="center">Grimoire</h1>

<p align="center">
  A local-first Markdown notes app built around folders, links, and files you own.
</p>

Grimoire turns an ordinary folder of Markdown files into a structured knowledge
base. Folders become note types, `[[wikilinks]]` connect ideas, and YAML
frontmatter adds queryable properties without locking your writing into a
proprietary database.

The desktop app reads and writes your files directly. You can keep using the
same vault with a text editor, Git, sync software, or any other Markdown tool.

## Highlights

- **Plain files, real folders** — choose any folder as a vault. A path such as
  `Projects/Active/Grimoire.md` appears as a nested type in the sidebar.
- **Focused Markdown editing** — CodeMirror live preview supports headings,
  lists, tables, links, tags, pasted images, and keyboard-friendly formatting.
- **Connected notes** — autocomplete `[[wikilinks]]`, follow links from the
  editor, create missing notes, and inspect backlinks grouped by note type.
- **Structured properties** — define text, URL, number, date, checkbox, list,
  and note-relation fields. Values remain readable YAML frontmatter.
- **Fast organization** — search and filter by type, date, and properties;
  reorder types; pin or archive notes; and use a recoverable vault-local trash.
- **Work with files outside the vault** — open standalone Markdown notes without
  importing them, or associate notes with PDFs and common office documents.
- **Desktop workflow tools** — reveal notes in the system file manager, open
  links in the browser, use focus mode, and run an embedded terminal in the
  selected note's folder.
- **Personalized workspace** — resize or collapse panels and choose from built-in
  light and dark themes with a theme-aware Grimoire mark.

## How the vault works

```text
My Vault/
├── Projects/
│   ├── Active/
│   │   └── Grimoire.md
│   └── Project Index.md
├── People/
│   └── Ada.md
├── assets/                 # pasted and dropped images
├── .grimoire/              # Grimoire's vault metadata
└── .trash/                 # recoverable deleted notes
```

Each `.md` file is a note. Grimoire derives its type from its containing folders,
up to three levels deep. Moving a note to another type moves the file; changing
the title line renames it. Property values stay in the note's frontmatter, while
vault-wide property definitions and display metadata live under `.grimoire/`.

## Getting started

### Prerequisites

- [Node.js](https://nodejs.org/) 22.13 or newer and [pnpm](https://pnpm.io/)
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
desktop launch, choose the folder you want Grimoire to use as its vault.

## Development

```sh
pnpm test            # run the Vitest suite
pnpm build           # build the web app
pnpm desktop:build   # build installable desktop bundles for the current OS
```

## Releases and automatic updates

To publish a new Apple Silicon version, start from a clean, up-to-date `main`
branch and run:

```sh
pnpm release 0.3.1
```

The release command verifies the build and tests, keeps the Tauri and Rust
versions in sync, commits the version bump, creates the matching `v0.3.1` tag,
and pushes both atomically. GitHub Actions then builds the DMG and signed updater
bundle, publishes the GitHub Release, and generates `latest.json`. Installed
desktop copies check that file on launch and every six hours. When an update is
available, the user can download and install it or ask Grimoire to remind them
again in 24 hours. Grimoire relaunches after an accepted update is installed.

The updater private key is stored in the repository's
`TAURI_SIGNING_PRIVATE_KEY` Actions secret. Back up the local key at
`~/.tauri/grimoire-updater.key`; losing it prevents existing installations from
accepting future updates.

The project is built with React, TypeScript, CodeMirror 6, Tailwind CSS,
shadcn/ui, and Tauri 2. The native Rust layer provides filesystem integration,
desktop file opening, and the embedded PTY terminal.

```text
src/                  React application and browser vault
src/components/       editor, notes, terminal, and shared UI
src/lib/              Markdown, filtering, properties, links, and vault helpers
src/store/            note and vault state
src-tauri/            Rust desktop shell, permissions, and packaging
```

## Built with Codex and GPT-5.6

A substantial part of Grimoire's recent development was completed through an
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

Codex and GPT-5.6 were development tools; they are not bundled into the app.
Grimoire currently has no OpenAI API integration, and using it does not require
an OpenAI account or API key.

## Project status

Grimoire is under active development. The browser build is useful for previewing
the interface, but its vault is stored in browser local storage; use the desktop
app when you want Grimoire to work directly with files on disk.

## License

Grimoire is available under the [MIT License](LICENSE).
