---
name: zerus
description: Work safely with the user's local Zerus Markdown vault through the Zerus CLI.
metadata:
  version: "2"
---

# Zerus CLI

Use `zerus` for structured access to Zerus vaults. Do not edit `.zerus`,
`.trash`, managed documents, or reserved `zerus-*` frontmatter directly.

## Required automation defaults

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

- Tasks: `task list|get|create|update|complete|reopen|delete` and
  `task category list|add|remove`. Task deletion and category removal require a
  preview followed by `--yes`. Link tasks with repeated `--link-note SELECTOR`.
- Saved links: `saved-link list|get|create|delete|move-to-type`. Saved-link
  deletion requires preview and `--yes`.
- Types: `type create|rename|delete|move`; `type icon get|set|unset`; and
  `type view get|set|unset`. Type deletion previews every note that will move
  to Trash and requires `--yes`.
- File hubs: `file get|attach-copy|detach`. A copied managed file moves safely
  with its note. Deleting a managed copy requires `--delete-managed --yes`.
- Attachments: `attachment list|add-copy|remove`. `add-copy` returns the exact
  `zerus-attachment:` Markdown reference. Deleting the managed copy requires
  `--delete-managed --yes`.
- Relationships: `links NOTE` reports body wikilinks and configured Relation
  properties separately, plus backlinks and how each backlink was formed.
- Schemas: `schema list|add|remove`. Definitions inherit through up to eight
  type levels. Never hand-edit `.zerus/properties.json`.

Rendered single-note HTML, PDF, and DOCX export remains an interactive Zerus UI
feature. CLI `export OUTPUT` creates a portable raw-Markdown vault export.

## Safety and recovery

Preview every bulk or data-loss operation and obtain explicit user approval
before rerunning it with `--yes`. Do not infer approval from a general request
to organize or clean up notes. Trash is recoverable; task deletion, saved-link
deletion, managed-copy deletion, and schema value purges are not.

CLI note mutations create namespaced transaction records. `undo` refuses to replace
a note that changed after the selected transaction. Never bypass this conflict
by editing files directly.

Preserve unfamiliar frontmatter and all `zerus-*` metadata. Prefer narrow,
incremental mutations and re-read affected records before reporting completion.
