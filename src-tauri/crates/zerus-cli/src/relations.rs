//! Paired relation writes share one recoverable, conflict-checked transaction.
use super::*;

#[derive(Clone, Serialize, Deserialize)]
pub(super) struct Change {
    path: String,
    before: String,
    after: String,
}

fn error(message: impl Into<String>) -> CliError {
    CliError::new("relation_invalid", message, 3)
}

fn values(content: &str, key: &str) -> Result<Vec<String>, CliError> {
    let properties = zerus_core::note_properties(content);
    match properties
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case(key))
        .map(|(_, value)| value)
    {
        None => Ok(Vec::new()),
        Some(zerus_core::PropertyValue::String(value)) if value.trim().is_empty() => Ok(Vec::new()),
        Some(zerus_core::PropertyValue::String(value)) => Ok(vec![value.clone()]),
        Some(zerus_core::PropertyValue::List(values)) => Ok(values.clone()),
        _ => Err(error(
            "Relations require a note reference or a list of references",
        )),
    }
}

fn multiple(definition: &Value) -> bool {
    definition["relationMultiple"].as_bool().unwrap_or(false)
}

fn accepts(definition: &Value, note: &ScannedNote) -> bool {
    definition["relationTypeKey"]
        .as_str()
        .filter(|key| !key.is_empty())
        .map_or(true, |key| type_matches(&note.path, key))
}

fn reference(note: &ScannedNote) -> Result<String, CliError> {
    note.id.map(|id| format!("[[zerus:{id}]]")).ok_or_else(|| {
        error("Relation endpoints need stable IDs; open the vault in Zerus or migrate it first")
    })
}

fn set_values(
    content: &str,
    name: &str,
    values: &[String],
    many: bool,
) -> Result<String, CliError> {
    let yaml = if many {
        values
            .iter()
            .map(|value| format!("\n  - {}", serde_json::to_string(value).unwrap()))
            .collect::<String>()
    } else {
        values
            .first()
            .map(|value| serde_json::to_string(value).unwrap())
            .unwrap_or_default()
    };
    set_property(content, name, (!values.is_empty()).then_some(yaml.as_str()))
        .map_err(|e| error(e.to_string()))
}

fn targets<'a>(
    notes: &'a [ScannedNote],
    definition: &Value,
    references: &[String],
) -> Result<Vec<&'a ScannedNote>, CliError> {
    let mut result = Vec::new();
    for value in references {
        let matches = notes
            .iter()
            .filter(|note| {
                !is_trashed_path(&note.path)
                    && accepts(definition, note)
                    && note_reference_matches(value, note)
            })
            .collect::<Vec<_>>();
        let note = match matches.as_slice() {
            [note] => *note,
            [] => {
                return Err(error(format!(
                    "Relation target {value:?} is missing, trashed, or outside the allowed type"
                )))
            }
            _ => {
                return Err(error(format!(
                    "Relation target {value:?} is ambiguous; use a stable note ID"
                )))
            }
        };
        if !result
            .iter()
            .any(|existing: &&ScannedNote| existing.path == note.path)
        {
            result.push(note);
        }
    }
    if !multiple(definition) && result.len() > 1 {
        return Err(error("This relation accepts only one note"));
    }
    Ok(result)
}

/// Ordinary fields retain their existing behavior. Paired relations validate
/// every endpoint and inverse before the first write; unpaired schemas belong
/// to the app's migration/definition UI rather than a guessed inverse here.
pub(super) fn mutate(
    root: &Path,
    notes: &[ScannedNote],
    source: &ScannedNote,
    key: &str,
    value: Option<&str>,
    expected: Option<&str>,
) -> Result<HistoryEntry, CliError> {
    let schemas = load_schemas(root)?;
    let definition = effective_schema_definitions(&schemas, &note_type_key(&source.path))
        .into_iter()
        .find(|definition| {
            definition["type"] == "relation"
                && definition["name"]
                    .as_str()
                    .is_some_and(|name| name.eq_ignore_ascii_case(key))
        });
    let operation = if value.is_some() {
        "property.set"
    } else {
        "property.unset"
    };
    let Some(definition) = definition else {
        let next = set_property(&source.content, key, value)
            .map_err(|e| CliError::new("property_invalid", e.to_string(), 3))?;
        return write_note(root, source, operation, &next, expected);
    };
    if expected.is_some_and(|revision| revision != source.revision) {
        return Err(CliError::new(
            "write_failed",
            "note changed since it was read",
            5,
        ));
    }
    let pair = definition["relationPairId"].as_str().filter(|id| !id.is_empty())
        .ok_or_else(|| error("This relation is not paired; open the vault in Zerus to migrate its relation definitions first"))?;
    let name = definition["name"].as_str().unwrap();
    // Parse the same YAML syntax accepted by ordinary property writes.
    if value.is_some_and(|value| value.contains(['\n', '\r'])) {
        return Err(error(
            "Pass a single-line scalar or JSON array of note references",
        ));
    }
    let requested = set_property(&source.content, name, value).map_err(|e| error(e.to_string()))?;
    let before = targets(notes, &definition, &values(&source.content, name)?)?;
    let requested_values = match value.map(str::trim) {
        Some(value) if value.starts_with("[[") => vec![value.to_string()],
        Some(value) if value.starts_with('[') => serde_json::from_str::<Vec<String>>(value)
            .map_err(|_| error("Pass a JSON array of note-reference strings"))?,
        _ => values(&requested, name)?,
    };
    let after = targets(notes, &definition, &requested_values)?;
    let source_reference = reference(source)?;
    let canonical = after
        .iter()
        .map(|target| reference(target))
        .collect::<Result<Vec<_>, _>>()?;
    let next = set_values(&source.content, name, &canonical, multiple(&definition))?;
    let mut changes = vec![Change {
        path: source.path.clone(),
        before: source.content.clone(),
        after: next,
    }];
    let mut seen = BTreeSet::new();
    for target in before.iter().chain(after.iter()) {
        if !seen.insert(&target.path) {
            continue;
        }
        if target.path == source.path {
            return Err(error("A relation cannot link a note to itself"));
        }
        reference(target)?;
        let inverses = effective_schema_definitions(&schemas, &note_type_key(&target.path))
            .into_iter()
            .filter(|inverse| {
                inverse["type"] == "relation"
                    && inverse["relationPairId"].as_str() == Some(pair)
                    && accepts(inverse, source)
            })
            .collect::<Vec<_>>();
        let inverse = match inverses.as_slice() {
            [inverse] => inverse,
            _ => {
                return Err(error(format!(
                "{} needs one compatible inverse definition; configure the relation in Zerus first",
                target.path
            )))
            }
        };
        let inverse_name = inverse["name"]
            .as_str()
            .ok_or_else(|| error("Inverse definition has no name"))?;
        let mut inverse_values = values(&target.content, inverse_name)?;
        inverse_values.retain(|value| !note_reference_matches(value, source));
        if after.iter().any(|note| note.path == target.path) {
            if !multiple(inverse) && !inverse_values.is_empty() {
                return Err(error(format!(
                    "The inverse relation on {} already points to another note",
                    target.path
                )));
            }
            inverse_values.push(source_reference.clone());
        }
        let next = set_values(
            &target.content,
            inverse_name,
            &inverse_values,
            multiple(inverse),
        )?;
        changes.push(Change {
            path: target.path.clone(),
            before: target.content.clone(),
            after: next,
        });
    }
    changes.retain(|change| change.before != change.after);
    commit(root, operation, changes, None)
}

fn journal_path(root: &Path, entry: &HistoryEntry) -> Result<PathBuf, CliError> {
    Uuid::parse_str(&entry.transaction_id).map_err(|_| error("Invalid transaction ID"))?;
    Ok(history_dir(root).join(format!("{}.json", entry.transaction_id)))
}

fn read_change(root: &Path, change: &Change) -> Result<String, CliError> {
    zerus_core::validate_portable_relative_path(&change.path).map_err(|e| error(e.to_string()))?;
    let path = root.join(&change.path);
    let canonical_root = fs::canonicalize(root).map_err(|e| error(e.to_string()))?;
    let canonical =
        fs::canonicalize(&path).map_err(|e| CliError::new("undo_conflict", e.to_string(), 5))?;
    if !canonical.starts_with(canonical_root) {
        return Err(error("Transaction endpoint leaves the vault"));
    }
    fs::read_to_string(path).map_err(|e| CliError::new("write_failed", e.to_string(), 5))
}

fn commit(
    root: &Path,
    operation: &str,
    changes: Vec<Change>,
    recovering: Option<&str>,
) -> Result<HistoryEntry, CliError> {
    if let Some(entry) = history_entries(root)?
        .iter()
        .find(|entry| entry.pending && Some(entry.transaction_id.as_str()) != recovering)
    {
        return Err(CliError::new("transaction_pending", format!("Recover the interrupted relation transaction with undo {} before making another relation edit", entry.transaction_id), 5));
    }
    for change in &changes {
        if read_change(root, change)? != change.before {
            return Err(CliError::new(
                "write_failed",
                "A relation endpoint changed; re-read both notes",
                5,
            ));
        }
    }
    let first = changes.first();
    let mut entry = save_history(
        root,
        operation,
        first.map(|c| c.path.as_str()),
        first.map(|c| c.path.as_str()),
        first.map(|c| c.before.as_str()),
        first.map(|c| c.after.as_str()),
    )?;
    entry.changes = changes;
    entry.pending = true;
    let path = journal_path(root, &entry)?;
    write_json(&path, &entry)?;
    for (index, change) in entry.changes.iter().enumerate() {
        if let Err(failure) = atomic_write(
            &root.join(&change.path),
            &change.after,
            Some(&zerus_core::content_revision(&change.before)),
        ) {
            let mut recovered = true;
            for applied in entry.changes[..index].iter().rev() {
                recovered &= atomic_write(
                    &root.join(&applied.path),
                    &applied.before,
                    Some(&zerus_core::content_revision(&applied.after)),
                )
                .is_ok();
            }
            if recovered {
                let _ = fs::remove_file(&path);
            }
            return Err(CliError::new(
                "write_failed",
                format!(
                    "{failure}; transaction {}{}",
                    entry.transaction_id,
                    if recovered {
                        " was rolled back"
                    } else {
                        " requires recovery with undo"
                    }
                ),
                5,
            ));
        }
    }
    entry.pending = false;
    write_json(&path, &entry).map_err(|_| CliError::new("transaction_pending", format!("Notes were written; transaction {} needs recovery with undo because its journal could not be finalized", entry.transaction_id), 5))?;
    Ok(entry)
}

pub(super) fn undo(root: &Path, entry: &HistoryEntry) -> Result<HistoryEntry, CliError> {
    let mut changes = Vec::new();
    for change in &entry.changes {
        let actual = read_change(root, change)?;
        if entry.pending && actual == change.before {
            continue;
        }
        if actual != change.after {
            return Err(CliError::new("undo_conflict", "A relation endpoint changed after this transaction; refusing to overwrite newer edits", 5));
        }
        changes.push(Change {
            path: change.path.clone(),
            before: actual,
            after: change.before.clone(),
        });
    }
    if entry.pending {
        // Recover in place: another crash leaves the same journal recoverable,
        // including when the interrupted operation was itself an undo.
        for change in &changes {
            atomic_write(
                &root.join(&change.path),
                &change.after,
                Some(&zerus_core::content_revision(&change.before)),
            )
            .map_err(|e| {
                CliError::new(
                    "transaction_pending",
                    format!(
                        "{e}; retry undo {} after resolving the endpoint",
                        entry.transaction_id
                    ),
                    5,
                )
            })?;
        }
        let mut recovered = entry.clone();
        recovered.pending = false;
        write_json(&journal_path(root, entry)?, &recovered)?;
        return save_history(root, "undo", None, None, None, None);
    }
    commit(root, "undo", changes, None)
}
