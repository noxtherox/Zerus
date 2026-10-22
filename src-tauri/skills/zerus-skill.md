---
name: zerus
description: Work safely with the user's local Zerus Markdown vault through the Zerus CLI.
metadata:
  version: "3"
---

# Zerus CLI

Use `zerus` for structured access to Zerus vaults. Do not edit `.zerus`,
`.trash`, managed documents, or reserved `zerus-*` frontmatter directly.

## Required automation defaults

- Check `zerus --version` before mutations. This skill requires CLI **0.3.0 or
  newer**. Older task writers can discard task lists and older relation writers
  do not synchronize inverse links. Install the matching CLI from Settings → CLI
  before writing with an older executable.
- Start with `zerus vault list --json` and select the intended vault.
- Pass `--vault NAME_OR_PATH --json --no-input` on every automated command.
- Use `--jsonl` instead of `--json` only for commands returning large streams.
- Treat a nonzero exit status or `ok: false` as failure. Report the structured
  error code and do not claim success.
- Select notes by exact path or note ID when possible. Titles can be ambiguous.
- Before changing note content, read it and pass its returned revision through
  `--if-revision`. If the revision conflicts, re-read and reconsider the edit.

## Discovery and notes

Run `zerus --help` or `zerus COMMAND --help` when exact flags are uncertain.

- Health and vaults: `doctor`, `vault list|add|default|current`
- Read: `note list|get`, `search`, `links`, `type list`
- Write: `note create|set-body|append|prepend`, `note property list|set|unset`
- Organize: `note pin|unpin|archive|unarchive`, `type move`
- Lifecycle: `note trash|restore`, `history`, `undo`
- Transfer: `import`, `export`
- Bulk: `bulk property-set|archive`

Normal list, search, bulk, export, and type operations exclude Trash. Use the
explicit `--trash` or `--include-trash` read flags only when the request needs
trashed notes. Restore a note before making ordinary edits or moving its type.
Content insertion uses `note append SELECTOR --text TEXT` or
`note prepend SELECTOR --text TEXT`; note moves use
`type move SELECTOR --to TYPE_PATH`.

## Current Zerus resources

- Tasks: discover lists with `task lists`; use `--list ID_OR_NAME` with
  `task list`, `task create`, or `task update`. Prefer exact list IDs when names
  are ambiguous. `--list general` selects the built-in list even after renaming;
  `task update SELECTOR --clear-list` moves a task back there. Task-list creation
  and renaming remain in the app. Task writes preserve lists, assignments,
  custom General names, and unfamiliar metadata, and refresh changed-task timestamps.
  Commands are `task list|get|create|update|complete|reopen|delete` and
  `task category list|add|remove`. Task deletion and category removal require a
  preview followed by `--yes`. Link tasks with repeated `--link-note SELECTOR`.
- Saved links: `saved-link list|get|create|delete|move-to-type`. Saved-link
  deletion requires preview and `--yes`.
- Types: `type create|rename|delete|move`; `type icon get|set|unset`; and
  `type view get|set|unset`. Type deletion previews every note that will move
  to Trash and requires `--yes`.
- File hubs: `file get|attach-copy|detach`. A copied managed file moves safely
  with its note. Deleting a managed copy requires `--delete-managed --yes`.
  Inspect `file get` before `attach-copy`: it replaces the note's current file
  association with a vault copy while leaving the original file in place.
  Creating external connections or external connections with a backup remains
  an app workflow; use `attachment add-copy` for an additional snapshot copy.
- Attachments: `attachment list|add-copy|remove`. `add-copy` returns the exact
  `zerus-attachment:` Markdown reference. Deleting the managed copy requires
  `--delete-managed --yes`.
- Relationships: `links NOTE` reports body wikilinks and configured Relation
  properties separately, plus backlinks and how each backlink was formed.
  `note property set|unset` synchronizes **existing paired relation definitions**
  in both notes under one history transaction. Read the source first and pass
  `--if-revision`. Use stable references such as `[[zerus:NOTE_UUID]]`, or a JSON
  array of reference strings for multiple targets. Inspect `schema list TYPE`
  before writing. Missing or unpaired inverse definitions require migration or
  configuration in the app; do not create an ad-hoc replacement property.
  CLI bulk relation edits and removal of paired schemas are blocked; configure
  relation schemas and move notes with populated relations in the app.
- Schemas: `schema list|add|remove`. Definitions inherit through up to eight
  type levels. Never hand-edit `.zerus/properties.json`.

Deliberate note revisions (`New revision`, `Make current`, and revision Trash)
remain app features. CLI edits update the live current note; `history`/`undo`
are automatic CLI transactions, not the deliberate revision collection. Never
edit `.zerus/revisions` or revision pointer metadata directly. CLI `export`
contains raw notes and its manifest, not managed files or revision history;
copy the whole vault when a complete backup is needed.

Rendered single-note HTML, PDF, and DOCX export remains an interactive Zerus UI
feature. CLI `export OUTPUT` creates a portable raw-Markdown vault export.

## Safety and recovery

Preview every bulk or data-loss operation and obtain explicit user approval
before rerunning it with `--yes`. Do not infer approval from a general request
to organize or clean up notes. Trash is recoverable; task deletion, saved-link
deletion, managed-copy deletion, and schema value purges are not.

For paired relation edits, an interrupted write leaves a pending journal.
If the CLI reports `transaction_pending`, inspect `history` and recover with
`undo TRANSACTION_ID` before continuing. Undo checks all affected notes and
refuses to overwrite later edits; never remove a pending journal manually.

CLI note mutations create namespaced transaction records. `undo` refuses to replace
a note that changed after the selected transaction. Never bypass this conflict
by editing files directly.

Preserve unfamiliar frontmatter and all `zerus-*` metadata. Prefer narrow,
incremental mutations and re-read affected records before reporting completion.
