use crate::{
    find_case_insensitive_collisions, note_properties, note_title, read_note_metadata,
    validate_portable_relative_path, NoteMetadata, PropertyValue,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;
use thiserror::Error;
use uuid::Uuid;

pub const VAULT_MANIFEST_PATH: &str = ".zerus/vault.json";

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultManifest {
    pub version: u32,
    pub vault_id: Uuid,
    pub metadata_version: u32,
    pub ids_required: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScannedNote {
    pub id: Option<Uuid>,
    pub path: String,
    pub absolute_path: PathBuf,
    pub title: String,
    pub content: String,
    pub pinned: bool,
    pub archived: bool,
    pub revision: String,
    pub updated_at_ms: u128,
    pub properties: std::collections::BTreeMap<String, PropertyValue>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DiagnosticIssue {
    pub code: String,
    pub severity: String,
    pub path: Option<String>,
    pub related_paths: Vec<String>,
    pub message: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DiagnosticReport {
    pub vault_path: PathBuf,
    pub notes_scanned: usize,
    pub missing_ids: usize,
    pub duplicate_ids: usize,
    pub issues: Vec<DiagnosticIssue>,
    pub healthy: bool,
}

#[derive(Debug, Error)]
pub enum VaultError {
    #[error("vault path does not exist or is not a directory: {0}")]
    InvalidRoot(PathBuf),
    #[error("could not read vault data: {0}")]
    Io(#[from] std::io::Error),
    #[error("vault metadata is invalid: {0}")]
    InvalidManifest(#[from] serde_json::Error),
}

pub fn read_vault_manifest(root: &Path) -> Result<Option<VaultManifest>, VaultError> {
    let path = root.join(VAULT_MANIFEST_PATH);
    if !path.exists() {
        return Ok(None);
    }
    Ok(Some(serde_json::from_str(&fs::read_to_string(path)?)?))
}

pub fn write_vault_manifest(root: &Path, manifest: &VaultManifest) -> Result<(), VaultError> {
    let path = root.join(VAULT_MANIFEST_PATH);
    let parent = path.parent().expect("manifest has a parent");
    fs::create_dir_all(parent)?;
    let temporary = path.with_extension(format!("tmp-{}", std::process::id()));
    fs::write(&temporary, serde_json::to_vec_pretty(manifest).unwrap())?;
    fs::rename(temporary, path)?;
    Ok(())
}

pub fn load_or_create_manifest(root: &Path) -> Result<VaultManifest, VaultError> {
    if !root.is_dir() {
        return Err(VaultError::InvalidRoot(root.to_path_buf()));
    }
    if let Some(manifest) = read_vault_manifest(root)? {
        return Ok(manifest);
    }
    let manifest = VaultManifest {
        version: 1,
        vault_id: Uuid::now_v7(),
        metadata_version: 0,
        ids_required: false,
    };
    write_vault_manifest(root, &manifest)?;
    Ok(manifest)
}

fn visit_markdown(
    root: &Path,
    relative: &Path,
    output: &mut Vec<PathBuf>,
) -> Result<(), VaultError> {
    let directory = root.join(relative);
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        if file_type.is_symlink() {
            continue;
        }
        let name = entry.file_name();
        let name = name.to_string_lossy();
        let child = relative.join(name.as_ref());
        if file_type.is_dir() {
            if name.starts_with('.') && name != ".trash" {
                continue;
            }
            visit_markdown(root, &child, output)?;
        } else if file_type.is_file()
            && entry
                .path()
                .extension()
                .and_then(|value| value.to_str())
                .is_some_and(|extension| {
                    matches!(extension.to_ascii_lowercase().as_str(), "md" | "markdown")
                })
        {
            output.push(child);
        }
    }
    Ok(())
}

pub fn scan_vault(root: &Path) -> Result<Vec<ScannedNote>, VaultError> {
    if !root.is_dir() {
        return Err(VaultError::InvalidRoot(root.to_path_buf()));
    }
    let mut paths = Vec::new();
    visit_markdown(root, Path::new(""), &mut paths)?;
    paths.sort();
    paths
        .into_iter()
        .map(|relative| {
            let absolute = root.join(&relative);
            let content = fs::read_to_string(&absolute)?;
            let metadata = read_note_metadata(&content).unwrap_or_else(|_| NoteMetadata::default());
            let file_metadata = fs::metadata(&absolute)?;
            let fallback = relative
                .file_stem()
                .and_then(|value| value.to_str())
                .unwrap_or("Untitled");
            Ok(ScannedNote {
                id: metadata.id,
                path: relative.to_string_lossy().replace('\\', "/"),
                absolute_path: absolute,
                title: note_title(&content, fallback),
                revision: format!("sha256:{:x}", Sha256::digest(content.as_bytes())),
                updated_at_ms: file_metadata
                    .modified()
                    .ok()
                    .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
                    .map(|duration| duration.as_millis())
                    .unwrap_or_default(),
                properties: note_properties(&content),
                content,
                pinned: metadata.pinned,
                archived: metadata.archived,
            })
        })
        .collect()
}

pub fn diagnose_vault(root: &Path) -> Result<DiagnosticReport, VaultError> {
    let notes = scan_vault(root)?;
    let mut issues = Vec::new();
    let mut ids: std::collections::BTreeMap<Uuid, Vec<String>> = std::collections::BTreeMap::new();
    let mut missing_ids = 0;
    for note in &notes {
        if let Some(id) = note.id {
            ids.entry(id).or_default().push(note.path.clone());
        } else {
            missing_ids += 1;
            issues.push(DiagnosticIssue {
                code: "missing_id".into(),
                severity: "warning".into(),
                path: Some(note.path.clone()),
                related_paths: vec![],
                message: "note does not have a Zerus ID".into(),
            });
        }
        if let Err(error) = validate_portable_relative_path(&note.path) {
            issues.push(DiagnosticIssue {
                code: "nonportable_path".into(),
                severity: "warning".into(),
                path: Some(note.path.clone()),
                related_paths: vec![],
                message: error.to_string(),
            });
        }
    }
    let duplicate_groups: Vec<Vec<String>> =
        ids.into_values().filter(|paths| paths.len() > 1).collect();
    for paths in &duplicate_groups {
        for path in paths {
            issues.push(DiagnosticIssue {
                code: "duplicate_id".into(),
                severity: "error".into(),
                path: Some(path.clone()),
                related_paths: paths
                    .iter()
                    .filter(|candidate| *candidate != path)
                    .cloned()
                    .collect(),
                message: "another note has the same Zerus ID".into(),
            });
        }
    }
    for paths in find_case_insensitive_collisions(notes.iter().map(|note| note.path.as_str())) {
        for path in &paths {
            issues.push(DiagnosticIssue {
                code: "case_collision".into(),
                severity: "error".into(),
                path: Some(path.clone()),
                related_paths: paths
                    .iter()
                    .filter(|candidate| *candidate != path)
                    .cloned()
                    .collect(),
                message: "path collides on a case-insensitive filesystem".into(),
            });
        }
    }
    issues.sort_by(|left, right| left.path.cmp(&right.path).then(left.code.cmp(&right.code)));
    Ok(DiagnosticReport {
        vault_path: root.to_path_buf(),
        notes_scanned: notes.len(),
        missing_ids,
        duplicate_ids: duplicate_groups.len(),
        healthy: !issues.iter().any(|issue| issue.severity == "error"),
        issues,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temporary_vault(name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!("zerus-core-{name}-{}", Uuid::now_v7()));
        fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn scans_notes_without_following_hidden_directories() {
        let root = temporary_vault("scan");
        fs::create_dir_all(root.join("work")).unwrap();
        fs::create_dir_all(root.join(".zerus")).unwrap();
        fs::write(root.join("work/Plan.md"), "# Plan\n").unwrap();
        fs::write(root.join(".zerus/Hidden.md"), "# Hidden\n").unwrap();
        let notes = scan_vault(&root).unwrap();
        assert_eq!(notes.len(), 1);
        assert_eq!(notes[0].path, "work/Plan.md");
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn diagnostics_report_missing_ids() {
        let root = temporary_vault("doctor");
        fs::write(root.join("Note.md"), "# Note\n").unwrap();
        let report = diagnose_vault(&root).unwrap();
        assert_eq!(report.missing_ids, 1);
        assert!(report.healthy);
        fs::remove_dir_all(root).unwrap();
    }
}
