use thiserror::Error;

#[derive(Clone, Debug, Eq, Error, PartialEq)]
pub enum PortablePathError {
    #[error("path must be relative to the vault")]
    Absolute,
    #[error("path contains an empty, current-directory, or parent-directory segment")]
    UnsafeSegment,
    #[error("'{segment}' contains characters that are not portable across supported platforms")]
    InvalidCharacter { segment: String },
    #[error("'{segment}' cannot end with a space or period")]
    InvalidEnding { segment: String },
    #[error("'{segment}' is a reserved Windows filename")]
    ReservedName { segment: String },
}

const WINDOWS_RESERVED_NAMES: &[&str] = &[
    "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8",
    "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
];

/// Validates a vault-relative path against the common macOS, Windows, and
/// Linux filename subset. Paths use `/` internally on every platform.
pub fn validate_portable_relative_path(path: &str) -> Result<(), PortablePathError> {
    if path.is_empty()
        || path.starts_with('/')
        || path.starts_with("\\\\")
        || path.as_bytes().get(1) == Some(&b':')
    {
        return Err(PortablePathError::Absolute);
    }

    for segment in path.split(['/', '\\']) {
        if segment.is_empty() || segment == "." || segment == ".." {
            return Err(PortablePathError::UnsafeSegment);
        }
        if segment
            .chars()
            .any(|character| character.is_control() || "<>:\"|?*".contains(character))
        {
            return Err(PortablePathError::InvalidCharacter {
                segment: segment.to_string(),
            });
        }
        if segment.ends_with(' ') || segment.ends_with('.') {
            return Err(PortablePathError::InvalidEnding {
                segment: segment.to_string(),
            });
        }
        let stem = segment
            .split('.')
            .next()
            .unwrap_or(segment)
            .to_ascii_uppercase();
        if WINDOWS_RESERVED_NAMES.contains(&stem.as_str()) {
            return Err(PortablePathError::ReservedName {
                segment: segment.to_string(),
            });
        }
    }
    Ok(())
}

/// Returns groups of otherwise distinct paths that collide on a
/// case-insensitive filesystem. Groups and their members are sorted.
pub fn find_case_insensitive_collisions<'a>(
    paths: impl IntoIterator<Item = &'a str>,
) -> Vec<Vec<String>> {
    use std::collections::BTreeMap;

    let mut groups: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for path in paths {
        groups
            .entry(path.replace('\\', "/").to_lowercase())
            .or_default()
            .push(path.to_string());
    }
    groups
        .into_values()
        .filter_map(|mut paths| {
            paths.sort();
            paths.dedup();
            (paths.len() > 1).then_some(paths)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_portable_nested_note_paths() {
        assert_eq!(
            validate_portable_relative_path("Work/Client Notes/Plan.md"),
            Ok(())
        );
    }

    #[test]
    fn rejects_parent_traversal_and_absolute_paths() {
        assert_eq!(
            validate_portable_relative_path("../outside.md"),
            Err(PortablePathError::UnsafeSegment)
        );
        assert_eq!(
            validate_portable_relative_path("C:\\Notes\\Plan.md"),
            Err(PortablePathError::Absolute)
        );
    }

    #[test]
    fn rejects_windows_reserved_names_and_case_variants() {
        assert_eq!(
            validate_portable_relative_path("work/con.md"),
            Err(PortablePathError::ReservedName {
                segment: "con.md".to_string()
            })
        );
    }

    #[test]
    fn rejects_nonportable_characters_and_endings() {
        assert_eq!(
            validate_portable_relative_path("work/Plan?.md"),
            Err(PortablePathError::InvalidCharacter {
                segment: "Plan?.md".to_string()
            })
        );
        assert_eq!(
            validate_portable_relative_path("work/Plan. "),
            Err(PortablePathError::InvalidEnding {
                segment: "Plan. ".to_string()
            })
        );
    }

    #[test]
    fn finds_case_insensitive_collisions_deterministically() {
        assert_eq!(
            find_case_insensitive_collisions(["Work/Plan.md", "work/plan.md", "Other.md"]),
            vec![vec!["Work/Plan.md".to_string(), "work/plan.md".to_string()]]
        );
    }
}
