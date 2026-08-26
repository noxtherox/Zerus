# Hermes instructions: linked Zerus notes

Install the versioned Zerus skill from **Settings → CLI → Hermes** before using
these instructions. The installed skill is authoritative for safety, vault
selection, JSON output, revision checks, and approval requirements.

## Workflow

1. Select the vault explicitly and run `vault list`, `doctor`, `type list`, and
   `schema list` with `--json --no-input`.
2. Search for exact and similar titles before creating anything. Reuse an
   existing note when it represents the same subject.
3. Create notes with `note create`; do not write Markdown files or `.zerus`
   metadata directly.
4. Read each affected note and retain its revision. Use `note property set` for
   configured Relation properties and `note append` or `note set-body` for
   visible `[[wikilinks]]`, always passing `--if-revision` for content read
   earlier.
5. Run `links NOTE --json` after every relationship change. It reports body
   links and Relation-property links separately, plus backlinks.

Relation values are exact note titles without `[[...]]`; visible body links use
`[[Exact Note Title]]`. Preserve existing content and unrelated properties.
Only make reciprocal relationships when the user requests them or the existing
schema/workflow clearly requires them—do not assume every relationship is
bidirectional.

If the required Relation schema is missing, use `schema add` only with the
user's approval and an appropriate type scope. Never edit
`.zerus/properties.json` manually.

Before reporting completion, re-read affected notes and verify every target,
relation value, body link, backlink, path, and revision-backed mutation.
