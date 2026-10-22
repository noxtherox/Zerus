# Zerus CLI

The `zerus` command automates local Zerus vaults while keeping Markdown
as the primary document format. Install it and the optional AI-agent skills
from **Settings → CLI** in the desktop app.

The current CLI is **0.3.0**, paired with agent skill **3**. Check
`zerus --version` after installing. Older 0.2.0 binaries predate task lists and
paired relation writes; update them before making task or relation changes.

## Vaults and output

Register vaults with `zerus vault add NAME PATH`, inspect them with
`zerus vault list`, and set a default with `zerus vault default NAME`.
The desktop app automatically registers each successfully opened vault and
makes it the CLI default, including updating the path when a vault is moved.
Automation should pass `--vault NAME_OR_PATH --json` explicitly. Use `--jsonl`
for streams and `--no-input` to guarantee that a script never prompts.

## Notes

- Read: `note list`, `note get`, `search`, relation-aware `links`, `type list`
- Write: `note create`, `note set-body`, `note append`, `note prepend`
- Organize: `note pin`, `note archive`, `type create|rename|delete|move`
- Properties: `note property list|set|unset`, `schema list|add|remove`
- Lifecycle: `note trash`, `note restore`, `history`, `undo`
- Transfer: `import`, `export`
- Bulk: `bulk property-set`, `bulk archive`

Normal reads and bulk operations exclude `.trash`. Use `note list --trash` or
`search --trash` to inspect only Trash, and `--include-trash` only when a
combined read is intentional. Type listing includes empty folders but excludes
`.zerus`, `.trash`, and `assets`.

JSON results from `note list`, `note get`, and `search` include each note's
parsed YAML frontmatter in `properties`. `note get` also returns the raw note
content by default; `--body` limits `content` to the Markdown body without
removing `properties` from the result.

## Tasks, links, files, and attachments

- Tasks: `task list|get|create|update|complete|reopen|delete` and
  `task category list|add|remove`
- Saved links: `saved-link list|get|create|delete|move-to-type`
- File hubs: `file get|attach-copy|detach`
- Note attachments: `attachment list|add-copy|remove`
- Type display metadata: `type icon get|set|unset` and
  `type view get|set|unset`

Task links use repeated `--link-note SELECTOR` values and resolve them to stable
note IDs. `attachment add-copy` returns the exact `zerus-attachment:` Markdown
reference that can be inserted into the note body. Managed vault copies move
with their notes during type moves, trash, restore, and undo.

Discover task lists with `task lists`. `task list --list ID_OR_NAME` filters by
list; `task create TITLE --list ID_OR_NAME` and `task update SELECTOR --list
ID_OR_NAME` assign tasks. Exact list IDs take precedence over names; ambiguous
names fail rather than selecting arbitrarily. `--list general` always selects
the built-in list, including when it has a custom name. `task update SELECTOR
--clear-list` moves a task back there. Create and rename lists in the app.
Task writes preserve list definitions, assignments, the custom General name,
and unfamiliar task/document metadata. Changed tasks receive an `updatedAt`
timestamp; unrelated tasks retain theirs.

`file attach-copy` makes a managed vault copy and replaces the note's current
file association; inspect `file get` first. The source file stays in place.
External-connection and external-connection-with-backup creation remain app
workflows. `attachment add-copy` adds a separate snapshot without replacing
the file-hub association.

The desktop note menu exports one rendered note as HTML, PDF, or DOCX. CLI
`export OUTPUT` has a different purpose: it exports selected notes as portable
raw Markdown plus `zerus-export.json`.

Selectors accept an exact relative path, a unique note-ID prefix, or an exact
title. Ambiguous interactive selections display title, path, and ID; scripts
receive an `ambiguous_selector` error instead. Content mutations accept
`--if-revision sha256:…` for optimistic concurrency.

## Paired relation edits

`note property set|unset` synchronizes existing paired relation definitions in
both notes. Inspect `schema list TYPE_PATH` first: the definitions on both
endpoints must share a `relationPairId`, accept the opposite note's type, and
have compatible multiplicity. Read the source and pass its `--if-revision`;
the CLI also checks the affected inverse notes before writing. Stable references
avoid ambiguous titles:

```sh
zerus --vault VAULT --json --no-input note property set Work/Plan.md Related \
  '["[[zerus:019f7923-8fae-7733-8357-48b16a134c39]]"]' \
  --if-revision sha256:REVISION_FROM_NOTE_GET
```

The edit returns one transaction ID. `undo TRANSACTION_ID` restores both sides
and refuses to overwrite later edits on either note. Validation failures write
neither endpoint; write failures attempt to roll back completed writes. A crash
or incomplete rollback leaves a pending history record. If a command reports
`transaction_pending`, inspect `history` and run `undo TRANSACTION_ID` to recover
before continuing. Pending records are retained beyond normal history limits.

Missing or legacy unpaired definitions require migration or configuration in
the app. CLI bulk relation edits, removal of paired schema definitions, and
type moves of notes with populated paired relations are blocked; use the app
for those operations. CLI `schema add ... relation` creates an unpaired
definition; open the vault in Zerus to pair it before editing its values.

## Deliberate revisions and backups

Creating, promoting, trashing, and restoring deliberate note revisions remain
app features. CLI content edits change the live current note. Automatic CLI
`history` and `undo` are separate from `.zerus/revisions`; never edit revision
indexes, files, or pointer metadata directly.

CLI `export` includes raw Markdown notes and `zerus-export.json`. It does not
copy managed files or deliberate revision history and is not a complete vault
backup. Copy the entire vault, including `.zerus`, for that purpose.

## Property schemas

Property definitions can be scoped to any type path, up to the app's eight
folder levels, and are inherited by its sub-types. For example, a definition
on `Development` applies to Initiatives,
Epics, and User Stories, while one on `Development/Initiatives` applies only to
Initiatives and any types nested below it.

```sh
zerus --vault VAULT schema add Development/Initiatives Epics relation \
  --relation-type Development/Epics --multiple
zerus --vault VAULT schema add Development/Epics Initiative relation \
  --relation-type Development/Initiatives
zerus --vault VAULT schema add "Development/User Stories" Status list \
  --options Planned,Active,Done --multiple
```

`--relation-type` restricts selectable notes to that type and its sub-types.
`--multiple` enables multiple values on relation or list properties. `--options`
defines the allowed values for list properties. `schema list TYPE_PATH` returns
the effective inherited definitions for that type; `schema list` without a path
returns definitions grouped by their exact owner path.

Removing a definition affects only the exact owner path. Values remain in note
frontmatter unless `--purge-values --yes` is supplied; a purge is limited to
the selected type and its sub-types.

## Hidden metadata and migration

Zerus reserves all `zerus-*` frontmatter. This includes note identity and state,
file-hub references, saved-link references, and attachment records; these fields
never appear in the normal Properties UI. False pin/archive values are omitted,
and archiving always unpins a note.

Run `zerus migrate preview` before `zerus migrate apply --yes`. Duplicate
IDs or malformed reserved metadata block migration for review. Once ready, the
vault manifest records that IDs are required on every device.

## Safety

Writes use atomic replacement and revision checks. Bulk and data-loss actions
require a preview and explicit `--yes`. Notes can only be trashed and restored;
task deletion, saved-link deletion, managed-copy deletion, and schema value
purges are permanent. CLI mutation snapshots are namespaced under
`.zerus/history/cli`, retained for 30 days up to 500 MB, and can be inspected
with `history` or reversed with `undo`. Undo refuses to overwrite content that
changed after the selected transaction.
Removing a schema preserves note values unless `--purge-values --yes` is used.
