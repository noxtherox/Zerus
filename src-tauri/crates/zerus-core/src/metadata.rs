use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;
use uuid::Uuid;

pub const ZERUS_ID_KEY: &str = "grimoire-id";
pub const ZERUS_PINNED_KEY: &str = "grimoire-pinned";
pub const ZERUS_ARCHIVED_KEY: &str = "grimoire-archived";

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteMetadata {
    pub id: Option<Uuid>,
    pub pinned: bool,
    pub archived: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MetadataMigrationPlan {
    pub before_revision: String,
    pub after_revision: String,
    pub metadata: NoteMetadata,
    pub next_content: String,
    pub changed: bool,
}

#[derive(Clone, Debug)]
pub struct MigrationNoteInput<'a> {
    pub path: &'a str,
    pub content: &'a str,
    pub legacy_pinned: bool,
    pub legacy_archived: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlannedNoteMigration {
    pub path: String,
    pub plan: MetadataMigrationPlan,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MetadataMigrationSummary {
    pub notes_scanned: usize,
    pub notes_changed: usize,
    pub ids_added: usize,
    pub pinned_added: usize,
    pub archived_added: usize,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MigrationIssue {
    pub code: String,
    pub path: String,
    pub related_paths: Vec<String>,
    pub message: String,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultMetadataMigrationPlan {
    pub summary: MetadataMigrationSummary,
    pub notes: Vec<PlannedNoteMigration>,
    pub issues: Vec<MigrationIssue>,
    pub can_apply: bool,
}

#[derive(Clone, Debug, Eq, Error, PartialEq)]
pub enum MetadataError {
    #[error("frontmatter is not terminated")]
    UnterminatedFrontmatter,
    #[error("reserved metadata key '{key}' appears more than once")]
    DuplicateKey { key: String },
    #[error("'{key}' must contain a valid Zerus note ID")]
    InvalidId { key: String },
    #[error("'{key}' must be true or false")]
    InvalidBoolean { key: String },
}

#[derive(Clone, Copy)]
struct Frontmatter<'a> {
    raw: &'a str,
    body_offset: usize,
    closing_offset: usize,
    newline: &'static str,
}

fn split_frontmatter(content: &str) -> Result<Option<Frontmatter<'_>>, MetadataError> {
    let (opening_len, newline) = if content.starts_with("---\r\n") {
        (5, "\r\n")
    } else if content.starts_with("---\n") {
        (4, "\n")
    } else {
        return Ok(None);
    };

    let mut cursor = opening_len;
    while cursor <= content.len() {
        let next = content[cursor..]
            .find('\n')
            .map(|offset| cursor + offset + 1)
            .unwrap_or(content.len());
        let line_end = if next == content.len() {
            content.len()
        } else {
            next - 1
        };
        let line = content[cursor..line_end].trim_end_matches('\r');
        if line.trim() == "---" || line.trim() == "..." {
            let body_offset = if next < content.len() || content.ends_with('\n') {
                next
            } else {
                content.len()
            };
            return Ok(Some(Frontmatter {
                raw: &content[opening_len..cursor],
                body_offset,
                closing_offset: cursor,
                newline,
            }));
        }
        if next >= content.len() {
            break;
        }
        cursor = next;
    }
    Err(MetadataError::UnterminatedFrontmatter)
}

fn unquote(value: &str) -> &str {
    let trimmed = value.trim();
    if trimmed.len() >= 2
        && ((trimmed.starts_with('"') && trimmed.ends_with('"'))
            || (trimmed.starts_with('\'') && trimmed.ends_with('\'')))
    {
        &trimmed[1..trimmed.len() - 1]
    } else {
        trimmed
    }
}

fn reserved_values(raw: &str) -> Result<Vec<(String, String)>, MetadataError> {
    let mut values = Vec::new();
    for line in raw.lines() {
        let Some((raw_key, raw_value)) = line.split_once(':') else {
            continue;
        };
        let key = raw_key.trim().to_ascii_lowercase();
        if !matches!(
            key.as_str(),
            ZERUS_ID_KEY | ZERUS_PINNED_KEY | ZERUS_ARCHIVED_KEY
        ) {
            continue;
        }
        if values.iter().any(|(existing, _)| existing == &key) {
            return Err(MetadataError::DuplicateKey { key });
        }
        values.push((key, unquote(raw_value).to_string()));
    }
    Ok(values)
}

fn parse_bool(key: &str, value: &str) -> Result<bool, MetadataError> {
    match value.to_ascii_lowercase().as_str() {
        "true" => Ok(true),
        "false" | "" => Ok(false),
        _ => Err(MetadataError::InvalidBoolean {
            key: key.to_string(),
        }),
    }
}

pub fn read_note_metadata(content: &str) -> Result<NoteMetadata, MetadataError> {
    let Some(frontmatter) = split_frontmatter(content)? else {
        return Ok(NoteMetadata::default());
    };
    let mut metadata = NoteMetadata::default();
    for (key, value) in reserved_values(frontmatter.raw)? {
        match key.as_str() {
            ZERUS_ID_KEY => {
                metadata.id = Some(
                    Uuid::parse_str(&value)
                        .map_err(|_| MetadataError::InvalidId { key: key.clone() })?,
                );
            }
            ZERUS_PINNED_KEY => metadata.pinned = parse_bool(&key, &value)?,
            ZERUS_ARCHIVED_KEY => metadata.archived = parse_bool(&key, &value)?,
            _ => unreachable!(),
        }
    }
    Ok(metadata)
}

pub fn content_revision(content: &str) -> String {
    format!("sha256:{:x}", Sha256::digest(content.as_bytes()))
}

fn append_metadata_lines(content: &str, lines: &[String]) -> Result<String, MetadataError> {
    if lines.is_empty() {
        return Ok(content.to_string());
    }
    if let Some(frontmatter) = split_frontmatter(content)? {
        let mut next =
            String::with_capacity(content.len() + lines.iter().map(String::len).sum::<usize>() + 8);
        next.push_str(&content[..frontmatter.closing_offset]);
        if !next.ends_with('\n') {
            next.push_str(frontmatter.newline);
        }
        next.push_str(&lines.join(frontmatter.newline));
        next.push_str(frontmatter.newline);
        next.push_str(&content[frontmatter.closing_offset..frontmatter.body_offset]);
        next.push_str(&content[frontmatter.body_offset..]);
        Ok(next)
    } else {
        let newline = if content.contains("\r\n") {
            "\r\n"
        } else {
            "\n"
        };
        Ok(format!(
            "---{newline}{}{newline}---{newline}{content}",
            lines.join(newline)
        ))
    }
}

/// Plans the hidden metadata changes for one note without writing anything.
///
/// Existing valid IDs and explicit metadata win. Legacy pinned/archive state is
/// only added when the corresponding reserved key is absent. Archived notes
/// are never migrated as pinned.
pub fn plan_note_metadata_migration(
    content: &str,
    generated_id: Uuid,
    legacy_pinned: bool,
    legacy_archived: bool,
) -> Result<MetadataMigrationPlan, MetadataError> {
    let current = read_note_metadata(content)?;
    let frontmatter = split_frontmatter(content)?;
    let existing_values = frontmatter
        .map(|value| reserved_values(value.raw))
        .transpose()?
        .unwrap_or_default();
    let has_key = |needle: &str| existing_values.iter().any(|(key, _)| key == needle);

    let mut lines = Vec::new();
    let id = current.id.unwrap_or(generated_id);
    if current.id.is_none() {
        lines.push(format!("{ZERUS_ID_KEY}: {id}"));
    }
    if legacy_archived && !has_key(ZERUS_ARCHIVED_KEY) {
        lines.push(format!("{ZERUS_ARCHIVED_KEY}: true"));
    }
    if legacy_pinned && !legacy_archived && !current.archived && !has_key(ZERUS_PINNED_KEY) {
        lines.push(format!("{ZERUS_PINNED_KEY}: true"));
    }

    let next_content = append_metadata_lines(content, &lines)?;
    let metadata = read_note_metadata(&next_content)?;
    Ok(MetadataMigrationPlan {
        before_revision: content_revision(content),
        after_revision: content_revision(&next_content),
        changed: next_content != content,
        metadata,
        next_content,
    })
}

/// Builds a vault-wide preview. It does not write files and marks the plan as
/// blocked when malformed or duplicate reserved metadata needs review.
pub fn plan_vault_metadata_migration(
    notes: &[MigrationNoteInput<'_>],
) -> VaultMetadataMigrationPlan {
    use std::collections::HashMap;

    let mut result = VaultMetadataMigrationPlan {
        summary: MetadataMigrationSummary {
            notes_scanned: notes.len(),
            ..MetadataMigrationSummary::default()
        },
        ..VaultMetadataMigrationPlan::default()
    };
    let mut id_paths: HashMap<Uuid, Vec<String>> = HashMap::new();

    for note in notes {
        match plan_note_metadata_migration(
            note.content,
            Uuid::now_v7(),
            note.legacy_pinned,
            note.legacy_archived,
        ) {
            Ok(plan) => {
                // Safe because planning succeeded, which includes metadata parsing.
                let before_metadata = read_note_metadata(note.content).unwrap_or_default();
                if let Some(id) = plan.metadata.id {
                    id_paths.entry(id).or_default().push(note.path.to_string());
                }
                if plan.changed {
                    result.summary.notes_changed += 1;
                    if before_metadata.id.is_none() {
                        result.summary.ids_added += 1;
                    }
                    if note.legacy_pinned
                        && !note.legacy_archived
                        && !before_metadata.pinned
                        && plan.metadata.pinned
                    {
                        result.summary.pinned_added += 1;
                    }
                    if note.legacy_archived && !before_metadata.archived && plan.metadata.archived {
                        result.summary.archived_added += 1;
                    }
                }
                result.notes.push(PlannedNoteMigration {
                    path: note.path.to_string(),
                    plan,
                });
            }
            Err(error) => result.issues.push(MigrationIssue {
                code: "invalid_metadata".to_string(),
                path: note.path.to_string(),
                related_paths: Vec::new(),
                message: error.to_string(),
            }),
        }
    }

    for paths in id_paths.into_values().filter(|paths| paths.len() > 1) {
        for path in &paths {
            result.issues.push(MigrationIssue {
                code: "duplicate_id".to_string(),
                path: path.clone(),
                related_paths: paths
                    .iter()
                    .filter(|candidate| *candidate != path)
                    .cloned()
                    .collect(),
                message: "another note in this vault has the same Zerus ID".to_string(),
            });
        }
    }

    result
        .notes
        .sort_by(|left, right| left.path.cmp(&right.path));
    result
        .issues
        .sort_by(|left, right| left.path.cmp(&right.path));
    result.can_apply = result.issues.is_empty();
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn id() -> Uuid {
        Uuid::parse_str("019f7922-8fae-7733-8357-48b16a134c38").unwrap()
    }

    #[test]
    fn plans_new_frontmatter_without_touching_the_body() {
        let plan = plan_note_metadata_migration("# Note\n\nBody\n", id(), true, false).unwrap();
        assert_eq!(
            plan.next_content,
            "---\ngrimoire-id: 019f7922-8fae-7733-8357-48b16a134c38\ngrimoire-pinned: true\n---\n# Note\n\nBody\n"
        );
        assert!(plan.changed);
        assert_eq!(plan.metadata.id, Some(id()));
        assert!(plan.metadata.pinned);
    }

    #[test]
    fn appends_to_existing_frontmatter_and_preserves_raw_lines() {
        let content = "---\nstatus: draft\n# preserved comment\n---\n# Note\n";
        let plan = plan_note_metadata_migration(content, id(), false, true).unwrap();
        assert_eq!(
            plan.next_content,
            "---\nstatus: draft\n# preserved comment\ngrimoire-id: 019f7922-8fae-7733-8357-48b16a134c38\ngrimoire-archived: true\n---\n# Note\n"
        );
        assert!(plan.metadata.archived);
        assert!(!plan.metadata.pinned);
    }

    #[test]
    fn migration_is_idempotent() {
        let first = plan_note_metadata_migration("# Note\n", id(), true, false).unwrap();
        let second =
            plan_note_metadata_migration(&first.next_content, Uuid::now_v7(), true, false).unwrap();
        assert!(!second.changed);
        assert_eq!(second.next_content, first.next_content);
    }

    #[test]
    fn preserves_crlf_line_endings() {
        let plan = plan_note_metadata_migration(
            "---\r\nstatus: draft\r\n---\r\n# Note\r\n",
            id(),
            false,
            false,
        )
        .unwrap();
        assert_eq!(
            plan.next_content,
            "---\r\nstatus: draft\r\ngrimoire-id: 019f7922-8fae-7733-8357-48b16a134c38\r\n---\r\n# Note\r\n"
        );
    }

    #[test]
    fn rejects_duplicate_reserved_keys() {
        let content = "---\ngrimoire-id: 019f7922-8fae-7733-8357-48b16a134c38\nGrimoire-ID: 019f7922-8fae-7733-8357-48b16a134c38\n---\n";
        assert_eq!(
            read_note_metadata(content),
            Err(MetadataError::DuplicateKey {
                key: ZERUS_ID_KEY.to_string()
            })
        );
    }

    #[test]
    fn vault_preview_summarizes_hidden_changes() {
        let notes = [
            MigrationNoteInput {
                path: "work/One.md",
                content: "# One\n",
                legacy_pinned: true,
                legacy_archived: false,
            },
            MigrationNoteInput {
                path: "archive/Two.md",
                content: "# Two\n",
                legacy_pinned: false,
                legacy_archived: true,
            },
        ];
        let preview = plan_vault_metadata_migration(&notes);
        assert!(preview.can_apply);
        assert_eq!(preview.summary.notes_scanned, 2);
        assert_eq!(preview.summary.notes_changed, 2);
        assert_eq!(preview.summary.ids_added, 2);
        assert_eq!(preview.summary.pinned_added, 1);
        assert_eq!(preview.summary.archived_added, 1);
    }

    #[test]
    fn vault_preview_blocks_duplicate_ids() {
        let content = "---\ngrimoire-id: 019f7922-8fae-7733-8357-48b16a134c38\n---\n# Note\n";
        let notes = [
            MigrationNoteInput {
                path: "One.md",
                content,
                legacy_pinned: false,
                legacy_archived: false,
            },
            MigrationNoteInput {
                path: "Two.md",
                content,
                legacy_pinned: false,
                legacy_archived: false,
            },
        ];
        let preview = plan_vault_metadata_migration(&notes);
        assert!(!preview.can_apply);
        assert_eq!(preview.issues.len(), 2);
        assert!(preview
            .issues
            .iter()
            .all(|issue| issue.code == "duplicate_id"));
    }
}
