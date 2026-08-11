use crate::{
    content_revision, read_note_metadata, ZERUS_ARCHIVED_KEY, ZERUS_ID_KEY, ZERUS_PINNED_KEY,
};
use std::fs;
use std::io;
use std::path::Path;
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Error)]
pub enum EditError {
    #[error("note changed since it was read (expected {expected}, found {actual})")]
    Conflict { expected: String, actual: String },
    #[error("invalid property name")]
    InvalidKey,
    #[error("'{0}' is reserved for Zerus")]
    ReservedKey(String),
    #[error("could not write note: {0}")]
    Io(#[from] io::Error),
}

pub fn is_reserved_key(key: &str) -> bool {
    key.trim().to_ascii_lowercase().starts_with("zerus-")
}

fn frontmatter_parts(content: &str) -> (Vec<String>, String, &str) {
    let newline = if content.contains("\r\n") {
        "\r\n"
    } else {
        "\n"
    };
    if !(content.starts_with("---\n") || content.starts_with("---\r\n")) {
        return (Vec::new(), content.to_string(), newline);
    }
    let opening = if newline == "\r\n" { 5 } else { 4 };
    let mut offset = opening;
    for line in content[opening..].split_inclusive('\n') {
        let clean = line.trim_end_matches(['\r', '\n']);
        offset += line.len();
        if matches!(clean.trim(), "---" | "...") {
            return (
                content[opening..offset - line.len()]
                    .lines()
                    .map(ToString::to_string)
                    .collect(),
                content[offset..].to_string(),
                newline,
            );
        }
    }
    (Vec::new(), content.to_string(), newline)
}

fn replace_key(content: &str, key: &str, value: Option<&str>) -> Result<String, EditError> {
    let key = key.trim();
    if key.is_empty() || key.contains([':', '\n', '\r']) {
        return Err(EditError::InvalidKey);
    }
    let (lines, body, newline) = frontmatter_parts(content);
    let mut next = Vec::new();
    let mut skip_indented = false;
    for line in lines {
        if !line.starts_with(char::is_whitespace) {
            skip_indented = line
                .split_once(':')
                .is_some_and(|(candidate, _)| candidate.trim().eq_ignore_ascii_case(key));
            if skip_indented {
                continue;
            }
        } else if skip_indented {
            continue;
        }
        next.push(line);
    }
    if let Some(value) = value {
        next.push(format!("{key}: {value}"));
    }
    if next.is_empty() {
        return Ok(body);
    }
    Ok(format!(
        "---{newline}{}{newline}---{newline}{body}",
        next.join(newline)
    ))
}

pub fn set_property(content: &str, key: &str, value: Option<&str>) -> Result<String, EditError> {
    if is_reserved_key(key) {
        return Err(EditError::ReservedKey(key.to_string()));
    }
    replace_key(content, key, value)
}

pub fn ensure_note_id(content: &str) -> Result<(String, Uuid), EditError> {
    if let Ok(metadata) = read_note_metadata(content) {
        if let Some(id) = metadata.id {
            return Ok((content.to_string(), id));
        }
    }
    let id = Uuid::now_v7();
    Ok((
        replace_key(content, ZERUS_ID_KEY, Some(&id.to_string()))?,
        id,
    ))
}

pub fn set_note_state(
    content: &str,
    pinned: Option<bool>,
    archived: Option<bool>,
) -> Result<String, EditError> {
    let mut next = content.to_string();
    if archived == Some(true) {
        next = replace_key(&next, ZERUS_PINNED_KEY, None)?;
    } else if let Some(value) = pinned {
        next = replace_key(&next, ZERUS_PINNED_KEY, value.then_some("true"))?;
    }
    if let Some(value) = archived {
        next = replace_key(&next, ZERUS_ARCHIVED_KEY, value.then_some("true"))?;
    }
    Ok(next)
}

pub fn atomic_write(
    path: &Path,
    content: &str,
    expected_revision: Option<&str>,
) -> Result<String, EditError> {
    if let Some(expected) = expected_revision {
        let current = fs::read_to_string(path)?;
        let actual = content_revision(&current);
        if actual != expected {
            return Err(EditError::Conflict {
                expected: expected.to_string(),
                actual,
            });
        }
    }
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "note has no parent"))?;
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(
        ".zerus-write-{}-{}",
        std::process::id(),
        Uuid::now_v7()
    ));
    fs::write(&temporary, content)?;
    fs::rename(&temporary, path)?;
    Ok(content_revision(content))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn edits_properties_and_hides_false_state() {
        let note = "---\nstatus: draft\nzerus-pinned: true\n---\n# Note\n";
        let note = set_property(note, "status", Some("done")).unwrap();
        let note = set_note_state(&note, Some(false), Some(true)).unwrap();
        assert!(note.contains("status: done"));
        assert!(!note.contains(ZERUS_PINNED_KEY));
        assert!(note.contains("zerus-archived: true"));
    }
}
