# Hermes Instructions: Create Linked Zerus Notes

## Objective

Create Markdown notes in my Zerus vault with valid relationships between them. The notes must appear correctly in Zerus, their relation properties must resolve to real notes, and their visible wikilinks and backlinks must work.

## Vault boundary

Work only inside this vault:

```text
<REPLACE WITH THE ABSOLUTE PATH TO MY ZERUS VAULT>
```

Do not create, move, rename, or modify files outside that vault. Do not modify files inside `.grimoire`, `.trash`, or `assets` unless I explicitly request it.

## Before creating notes

1. Read my request and identify every note that needs to be created or updated.
2. Decide the exact title and type folder for each note.
3. Inspect the vault for notes with the same or very similar titles.
4. Reuse an existing note when it represents the same subject. Do not create duplicates.
5. Build the complete relationship list before writing files.
6. Preserve existing frontmatter and user-written content when updating a note.

## Zerus title rules

Zerus uses the first non-empty line after YAML frontmatter as the note title. For every note, use this format:

```markdown
# Exact Note Title
```

Keep these values consistent:

- Filename: `Exact Note Title.md`
- First body heading: `# Exact Note Title`
- Relation value: `Exact Note Title`
- Wikilink: `[[Exact Note Title]]`

Every note title must be unique across the vault. Use the exact title of the target note when creating a relationship. Do not use a folder path, filename extension, alias, or heading fragment inside a wikilink.

Correct:

```markdown
[[Project Polaris]]
```

Do not use:

```markdown
[[work/projects/Project Polaris]]
[[Project Polaris.md]]
[[Project Polaris|Polaris]]
[[Project Polaris#Goals]]
```

## Type and folder rules

Folders represent Zerus note types. Put each note in the type folder requested by the user.

Example:

```text
work/projects/Project Polaris.md
work/meetings/Kickoff Meeting.md
people/Alex Morgan.md
```

Do not invent a new folder hierarchy when the requested or established type already exists. Inspect nearby notes and follow the vault's existing organization.

## Relation-property rules

Use an existing Zerus Relation property named `Related`, unless the user specifies another existing relation property.

Relation values in YAML are plain note titles. Do not wrap them in `[[wikilink brackets]]`.

For several related notes, use a YAML block list:

```yaml
---
Related:
  - Project Polaris
  - Kickoff Meeting
---
```

For a single relation, use the existing style of the vault. A block list is safe when `Related` allows multiple values:

```yaml
---
Related:
  - Project Polaris
---
```

Important: `Related` must already be configured in Zerus as a **Relation** property for the note's top-level type. If it is missing or configured as another property type, do not edit `.grimoire/properties.json` automatically. Report the issue and explain which top-level type needs a `Related` Relation property. Continue using body wikilinks when doing so is consistent with the user's request.

## Linking rules

Use both of the following for each requested relationship:

1. Put the target's exact title in the `Related` frontmatter property.
2. Put a visible `[[Exact Note Title]]` link under `## Related notes` in the body.

Unless the user explicitly asks for a directional relationship, make relationships reciprocal.

If `Architecture Decision` relates to `Project Polaris`:

- `Architecture Decision` must relate and link to `Project Polaris`.
- `Project Polaris` must relate and link back to `Architecture Decision`.

A one-way link will already create a backlink in Zerus. Reciprocal relationships are required here so both notes display an outgoing relation and a visible link to the other note.

## Creation order

1. Create or update all target notes with their final titles.
2. Add relation-property values after every target note exists.
3. Add the visible wikilinks.
4. Re-read every affected file.
5. Run the validation checklist below.

This order avoids leaving relationships temporarily pointed at missing notes.

## Complete note template

```markdown
---
Related:
  - Project Polaris
  - Kickoff Meeting
---

# Architecture Decision

Write the note content here.

## Related notes

- [[Project Polaris]]
- [[Kickoff Meeting]]
```

## Reciprocal target example

```markdown
---
Related:
  - Architecture Decision
---

# Project Polaris

Write the project content here.

## Related notes

- [[Architecture Decision]]
```

## Updating existing frontmatter

When an existing note already has frontmatter, preserve all existing fields and add or update only the intended relation field.

Before:

```yaml
---
Status: Active
Owner: Alex Morgan
---
```

After:

```yaml
---
Status: Active
Owner: Alex Morgan
Related:
  - Project Polaris
---
```

Do not replace the entire frontmatter block, reorder unrelated fields unnecessarily, or discard comments and unfamiliar fields.

## Updating an existing Related section

If the note already has a `## Related notes` section:

- Merge the new wikilinks into that section.
- Preserve existing valid links.
- Remove exact duplicates.
- Do not create a second Related notes section.

If the note already has a `Related` property:

- Merge in the new exact titles.
- Preserve existing valid relations.
- Remove exact duplicates.
- Do not create a second property whose name differs only by capitalization.

## Validation checklist

Before reporting completion, verify every affected note:

- The file is inside the specified vault.
- The file has a `.md` extension.
- Its folder matches the intended Zerus type.
- The first non-empty body line is exactly `# Exact Note Title`.
- Its filename and title are consistent.
- Its title is unique across the vault.
- Every relation value exactly matches an existing note title.
- Relation values contain plain titles, without `[[` or `]]`.
- Every body wikilink exactly matches an existing note title.
- No wikilink contains a path, `.md`, alias, or heading fragment.
- Reciprocal relations and links exist unless the relationship was explicitly directional.
- Existing content and unrelated frontmatter were preserved.
- There are no duplicate relation values or duplicate related-note links.
- YAML fences and indentation remain valid.

## Completion report

When finished, report:

1. Every note created, with its vault-relative path.
2. Every existing note updated, with its vault-relative path.
3. The relationships added, clearly identifying any directional relationships.
4. Any unresolved or ambiguous title.
5. Any top-level type where the required Relation property is not configured.

Do not claim that the links are valid unless you checked every target title against the completed files.
