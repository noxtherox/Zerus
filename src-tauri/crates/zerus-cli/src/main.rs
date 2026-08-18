use clap::{Args, Parser, Subcommand};
use dialoguer::{theme::ColorfulTheme, Select};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::io::{self, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::{env, fs};
use uuid::Uuid;
use zerus_core::{
    atomic_write, default_registry_path, diagnose_vault, ensure_note_id, load_or_create_manifest,
    load_registry, note_body, plan_note_metadata_migration, resolve_vault, save_registry,
    scan_vault, set_note_state, set_property, write_vault_manifest, ScannedNote, VaultRecord,
    VaultRegistry,
};

const SCHEMA_VERSION: u32 = 1;

#[derive(Parser)]
#[command(name = "zerus", version, about = "Automate Zerus vaults safely")]
struct Cli {
    #[arg(long, global = true, value_name = "NAME_OR_PATH")]
    vault: Option<String>,
    #[arg(long, global = true, conflicts_with_all = ["jsonl", "quiet"])]
    json: bool,
    #[arg(long, global = true, conflicts_with_all = ["json", "quiet"])]
    jsonl: bool,
    #[arg(long, global = true, conflicts_with_all = ["json", "jsonl"])]
    quiet: bool,
    #[arg(long, global = true)]
    no_input: bool,
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    Vault {
        #[command(subcommand)]
        command: VaultCommand,
    },
    Doctor,
    Note {
        #[command(subcommand)]
        command: NoteCommand,
    },
    Search(SearchArgs),
    Import(ImportArgs),
    Migrate {
        #[command(subcommand)]
        command: MigrateCommand,
    },
    History,
    Undo {
        transaction_id: Option<String>,
    },
    Type {
        #[command(subcommand)]
        command: TypeCommand,
    },
    Links {
        #[command(flatten)]
        selector: NoteSelector,
    },
    Export {
        output: PathBuf,
        #[arg(long)]
        query: Option<String>,
        #[arg(long)]
        include_archived: bool,
    },
    Bulk {
        #[command(subcommand)]
        command: BulkCommand,
    },
    Schema {
        #[command(subcommand)]
        command: SchemaCommand,
    },
}

#[derive(Subcommand)]
enum VaultCommand {
    List,
    Add {
        name: String,
        path: PathBuf,
        #[arg(long)]
        make_default: bool,
    },
    Default {
        selector: String,
    },
    Current,
}

#[derive(Subcommand)]
enum NoteCommand {
    List(ListArgs),
    Get {
        #[command(flatten)]
        selector: NoteSelector,
        #[arg(long)]
        body: bool,
        #[arg(long)]
        raw: bool,
    },
    Create {
        path: String,
        #[arg(long)]
        title: Option<String>,
        #[arg(long)]
        body: Option<String>,
    },
    SetBody {
        #[command(flatten)]
        selector: NoteSelector,
        #[arg(long)]
        content: String,
        #[arg(long)]
        if_revision: Option<String>,
    },
    Append {
        #[command(flatten)]
        selector: NoteSelector,
        text: String,
        #[arg(long)]
        if_revision: Option<String>,
    },
    Prepend {
        #[command(flatten)]
        selector: NoteSelector,
        text: String,
        #[arg(long)]
        if_revision: Option<String>,
    },
    Pin {
        #[command(flatten)]
        selector: NoteSelector,
    },
    Unpin {
        #[command(flatten)]
        selector: NoteSelector,
    },
    Archive {
        #[command(flatten)]
        selector: NoteSelector,
    },
    Unarchive {
        #[command(flatten)]
        selector: NoteSelector,
    },
    Trash {
        #[command(flatten)]
        selector: NoteSelector,
    },
    Restore {
        #[command(flatten)]
        selector: NoteSelector,
    },
    Open {
        #[command(flatten)]
        selector: NoteSelector,
    },
    Property {
        #[command(subcommand)]
        command: PropertyCommand,
    },
}

#[derive(Subcommand)]
enum PropertyCommand {
    List {
        #[command(flatten)]
        selector: NoteSelector,
    },
    Set {
        #[command(flatten)]
        selector: NoteSelector,
        key: String,
        value: String,
        #[arg(long)]
        if_revision: Option<String>,
    },
    Unset {
        #[command(flatten)]
        selector: NoteSelector,
        key: String,
        #[arg(long)]
        if_revision: Option<String>,
    },
}

#[derive(Args)]
struct ImportArgs {
    source: PathBuf,
    #[arg(long)]
    to: Option<String>,
    #[arg(long, conflicts_with = "copy")]
    r#move: bool,
    #[arg(long)]
    copy: bool,
}

#[derive(Subcommand)]
enum MigrateCommand {
    Preview,
    Apply {
        #[arg(long)]
        yes: bool,
    },
}

#[derive(Subcommand)]
enum TypeCommand {
    List,
    Move {
        #[command(flatten)]
        selector: NoteSelector,
        to: String,
    },
}

#[derive(Subcommand)]
enum BulkCommand {
    PropertySet {
        query: String,
        key: String,
        value: String,
        #[arg(long)]
        yes: bool,
    },
    Archive {
        query: String,
        #[arg(long)]
        yes: bool,
    },
}

#[derive(Subcommand)]
enum SchemaCommand {
    List {
        type_path: Option<String>,
    },
    Add {
        type_path: String,
        name: String,
        kind: String,
        #[arg(
            long,
            value_delimiter = ',',
            help = "Allowed values for a list property"
        )]
        options: Vec<String>,
        #[arg(
            long,
            value_name = "TYPE_PATH",
            help = "Restrict a relation property to this note type and its sub-types"
        )]
        relation_type: Option<String>,
        #[arg(
            long,
            help = "Allow more than one value for a list or relation property"
        )]
        multiple: bool,
    },
    Remove {
        type_path: String,
        name: String,
        #[arg(long)]
        purge_values: bool,
        #[arg(long)]
        yes: bool,
    },
}

#[derive(Args, Default)]
struct ListArgs {
    #[arg(long)]
    type_path: Option<String>,
    #[arg(long)]
    pinned: bool,
    #[arg(long)]
    archived: bool,
    #[arg(long)]
    include_archived: bool,
}

#[derive(Args)]
struct SearchArgs {
    query: Option<String>,
    #[arg(long)]
    title: Option<String>,
    #[arg(long)]
    body: Option<String>,
    #[arg(long)]
    regex: Option<String>,
    #[arg(long)]
    type_path: Option<String>,
    #[arg(long, value_name = "KEY=VALUE")]
    property: Vec<String>,
    #[arg(long)]
    pinned: bool,
    #[arg(long)]
    archived: bool,
    #[arg(long)]
    include_archived: bool,
}

#[derive(Args)]
#[group(id = "note_selector", required = true, multiple = false)]
struct NoteSelector {
    #[arg(value_name = "SELECTOR", group = "note_selector")]
    target: Option<String>,
    #[arg(long, group = "note_selector")]
    id: Option<String>,
    #[arg(long, group = "note_selector")]
    path: Option<String>,
    #[arg(long, group = "note_selector")]
    title: Option<String>,
}

#[derive(Debug)]
struct CliError {
    code: &'static str,
    message: String,
    details: Value,
    exit: u8,
}

impl CliError {
    fn new(code: &'static str, message: impl Into<String>, exit: u8) -> Self {
        Self {
            code,
            message: message.into(),
            details: Value::Null,
            exit,
        }
    }

    fn details(mut self, details: Value) -> Self {
        self.details = details;
        self
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct NoteSummary<'a> {
    vault_id: String,
    note_id: Option<String>,
    title: &'a str,
    path: &'a str,
    pinned: bool,
    archived: bool,
    revision: &'a str,
    updated_at_ms: u128,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HistoryEntry {
    transaction_id: String,
    operation: String,
    path_before: Option<String>,
    path_after: Option<String>,
    content_before: Option<String>,
    content_after: Option<String>,
    created_at_ms: u128,
}

fn registry_path() -> Result<PathBuf, CliError> {
    default_registry_path()
        .map_err(|error| CliError::new("config_unavailable", error.to_string(), 2))
}

fn registry() -> Result<(PathBuf, VaultRegistry), CliError> {
    let path = registry_path()?;
    let value = load_registry(&path)
        .map_err(|error| CliError::new("registry_invalid", error.to_string(), 2))?;
    Ok((path, value))
}

fn upward_vault(start: &Path) -> Option<PathBuf> {
    start
        .ancestors()
        .find(|path| path.join(".zerus/vault.json").is_file())
        .map(Path::to_path_buf)
}

fn resolve_root(cli: &Cli) -> Result<(PathBuf, String), CliError> {
    let (registry_path, registry) = registry()?;
    let requested = cli
        .vault
        .as_deref()
        .map(str::to_string)
        .or_else(|| env::var("ZERUS_VAULT").ok());
    if let Some(selector) = requested.as_deref() {
        let explicit = Path::new(selector);
        if explicit.is_dir() {
            let root = explicit
                .canonicalize()
                .map_err(|error| CliError::new("vault_unavailable", error.to_string(), 2))?;
            let id = zerus_core::read_vault_manifest(&root)
                .map_err(|error| CliError::new("vault_invalid", error.to_string(), 2))?
                .map(|manifest| manifest.vault_id.to_string())
                .unwrap_or_else(|| "unregistered".into());
            return Ok((root, id));
        }
        let record = resolve_vault(&registry, Some(selector))
            .map_err(|error| CliError::new("vault_not_found", error.to_string(), 2))?;
        return Ok((record.path.clone(), record.id.to_string()));
    }
    if let Ok(current) = env::current_dir() {
        if let Some(root) = upward_vault(&current) {
            let manifest = zerus_core::read_vault_manifest(&root)
                .map_err(|error| CliError::new("vault_invalid", error.to_string(), 2))?
                .expect("upward search found manifest");
            return Ok((root, manifest.vault_id.to_string()));
        }
    }
    let record = resolve_vault(&registry, None).map_err(|error| {
        CliError::new(
            "vault_not_configured",
            format!("{} ({})", error, registry_path.display()),
            2,
        )
    })?;
    Ok((record.path.clone(), record.id.to_string()))
}

fn summary<'a>(note: &'a ScannedNote, vault_id: &str) -> NoteSummary<'a> {
    NoteSummary {
        vault_id: vault_id.to_string(),
        note_id: note.id.map(|id| id.to_string()),
        title: &note.title,
        path: &note.path,
        pinned: note.pinned,
        archived: note.archived,
        revision: &note.revision,
        updated_at_ms: note.updated_at_ms,
    }
}

fn load_notes(cli: &Cli) -> Result<(Vec<ScannedNote>, String, PathBuf), CliError> {
    let (root, vault_id) = resolve_root(cli)?;
    let notes = scan_vault(&root)
        .map_err(|error| CliError::new("vault_unavailable", error.to_string(), 2))?;
    Ok((notes, vault_id, root))
}

fn history_dir(root: &Path) -> PathBuf {
    root.join(".zerus/history")
}

fn save_history(
    root: &Path,
    operation: &str,
    before_path: Option<&str>,
    after_path: Option<&str>,
    before: Option<&str>,
    after: Option<&str>,
) -> Result<HistoryEntry, CliError> {
    let entry = HistoryEntry {
        transaction_id: Uuid::now_v7().to_string(),
        operation: operation.to_string(),
        path_before: before_path.map(ToString::to_string),
        path_after: after_path.map(ToString::to_string),
        content_before: before.map(ToString::to_string),
        content_after: after.map(ToString::to_string),
        created_at_ms: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis(),
    };
    let directory = history_dir(root);
    fs::create_dir_all(&directory)
        .map_err(|e| CliError::new("history_write_failed", e.to_string(), 2))?;
    let path = directory.join(format!("{}.json", entry.transaction_id));
    fs::write(path, serde_json::to_vec_pretty(&entry).unwrap())
        .map_err(|e| CliError::new("history_write_failed", e.to_string(), 2))?;
    let cutoff = entry.created_at_ms.saturating_sub(30 * 24 * 60 * 60 * 1000);
    let mut files: Vec<_> = fs::read_dir(&directory)
        .map_err(|e| CliError::new("history_read_failed", e.to_string(), 2))?
        .flatten()
        .filter_map(|item| item.metadata().ok().map(|metadata| (item.path(), metadata)))
        .collect();
    files.sort_by_key(|(_, metadata)| std::cmp::Reverse(metadata.modified().ok()));
    let mut retained_bytes = 0_u64;
    for (path, metadata) in files {
        let old = metadata
            .modified()
            .ok()
            .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
            .is_some_and(|value| value.as_millis() < cutoff);
        retained_bytes = retained_bytes.saturating_add(metadata.len());
        if old || retained_bytes > 500 * 1024 * 1024 {
            let _ = fs::remove_file(path);
        }
    }
    Ok(entry)
}

fn history_entries(root: &Path) -> Result<Vec<HistoryEntry>, CliError> {
    let directory = history_dir(root);
    if !directory.exists() {
        return Ok(Vec::new());
    }
    let mut entries = Vec::new();
    for item in fs::read_dir(directory)
        .map_err(|e| CliError::new("history_read_failed", e.to_string(), 2))?
    {
        let path = item
            .map_err(|e| CliError::new("history_read_failed", e.to_string(), 2))?
            .path();
        if path.extension().and_then(|v| v.to_str()) == Some("json") {
            if let Ok(value) = serde_json::from_slice(&fs::read(path).unwrap_or_default()) {
                entries.push(value);
            }
        }
    }
    entries.sort_by_key(|entry: &HistoryEntry| std::cmp::Reverse(entry.created_at_ms));
    Ok(entries)
}

fn write_note(
    root: &Path,
    note: &ScannedNote,
    operation: &str,
    next: &str,
    expected: Option<&str>,
) -> Result<HistoryEntry, CliError> {
    atomic_write(&note.absolute_path, next, expected.or(Some(&note.revision)))
        .map_err(|error| CliError::new("write_failed", error.to_string(), 5))?;
    save_history(
        root,
        operation,
        Some(&note.path),
        Some(&note.path),
        Some(&note.content),
        Some(next),
    )
}

fn valid_note_destination(root: &Path, relative: &str) -> Result<PathBuf, CliError> {
    zerus_core::validate_portable_relative_path(relative)
        .map_err(|error| CliError::new("invalid_path", error.to_string(), 3))?;
    let path = root.join(relative);
    if path.exists() {
        return Err(CliError::new(
            "path_exists",
            format!("{} already exists", path.display()),
            3,
        ));
    }
    Ok(path)
}

fn schema_path(root: &Path) -> PathBuf {
    root.join(".zerus/properties.json")
}

fn load_schemas(root: &Path) -> Result<serde_json::Map<String, Value>, CliError> {
    let path = schema_path(root);
    if !path.exists() {
        return Ok(serde_json::Map::new());
    }
    serde_json::from_slice::<Value>(
        &fs::read(path).map_err(|e| CliError::new("schema_read_failed", e.to_string(), 2))?,
    )
    .map_err(|e| CliError::new("schema_invalid", e.to_string(), 3))?
    .as_object()
    .cloned()
    .ok_or_else(|| CliError::new("schema_invalid", "schema root must be an object", 3))
}

fn save_schemas(root: &Path, schemas: &serde_json::Map<String, Value>) -> Result<(), CliError> {
    let path = schema_path(root);
    fs::create_dir_all(path.parent().unwrap())
        .map_err(|e| CliError::new("schema_write_failed", e.to_string(), 5))?;
    let temporary = path.with_extension(format!("tmp-{}", std::process::id()));
    fs::write(&temporary, serde_json::to_vec_pretty(schemas).unwrap())
        .map_err(|e| CliError::new("schema_write_failed", e.to_string(), 5))?;
    fs::rename(temporary, path).map_err(|e| CliError::new("schema_write_failed", e.to_string(), 5))
}

const MAX_SCHEMA_TYPE_DEPTH: usize = 3;

fn normalize_schema_type_path(input: &str) -> Result<String, CliError> {
    let normalized = input.trim().replace('\\', "/");
    zerus_core::validate_portable_relative_path(&normalized)
        .map_err(|error| CliError::new("schema_invalid", error.to_string(), 3))?;
    if normalized.split('/').count() > MAX_SCHEMA_TYPE_DEPTH {
        return Err(CliError::new(
            "schema_invalid",
            format!("type paths can contain at most {MAX_SCHEMA_TYPE_DEPTH} segments"),
            3,
        ));
    }
    Ok(normalized)
}

fn schema_owner_keys(type_path: &str) -> Vec<String> {
    let segments = type_path.split('/').collect::<Vec<_>>();
    (1..=segments.len())
        .map(|depth| segments[..depth].join("/"))
        .collect()
}

fn effective_schema_definitions(
    schemas: &serde_json::Map<String, Value>,
    type_path: &str,
) -> Vec<Value> {
    let mut effective = Vec::<Value>::new();
    for owner_key in schema_owner_keys(type_path) {
        let Some(definitions) = schemas.get(&owner_key).and_then(Value::as_array) else {
            continue;
        };
        for definition in definitions {
            let Some(name) = definition.get("name").and_then(Value::as_str) else {
                continue;
            };
            if let Some(position) = effective.iter().position(|existing| {
                existing
                    .get("name")
                    .and_then(Value::as_str)
                    .is_some_and(|value| value.eq_ignore_ascii_case(name))
            }) {
                effective[position] = definition.clone();
            } else {
                effective.push(definition.clone());
            }
        }
    }
    effective
}

fn effective_schema_definition_owner(
    schemas: &serde_json::Map<String, Value>,
    type_path: &str,
    name: &str,
) -> Option<String> {
    let mut owner = None;
    for owner_key in schema_owner_keys(type_path) {
        let defines_property = schemas
            .get(&owner_key)
            .and_then(Value::as_array)
            .is_some_and(|definitions| {
                definitions.iter().any(|definition| {
                    definition
                        .get("name")
                        .and_then(Value::as_str)
                        .is_some_and(|value| value.eq_ignore_ascii_case(name))
                })
            });
        if defines_property {
            owner = Some(owner_key);
        }
    }
    owner
}

fn note_type_key(path: &str) -> String {
    let mut segments = path.split('/').collect::<Vec<_>>();
    segments.pop();
    segments
        .into_iter()
        .take(MAX_SCHEMA_TYPE_DEPTH)
        .collect::<Vec<_>>()
        .join("/")
}

fn type_matches(path: &str, type_path: &str) -> bool {
    let normalized = type_path.trim_matches('/');
    path.starts_with(&format!("{normalized}/"))
}

fn filtered_list<'a>(notes: &'a [ScannedNote], args: &ListArgs) -> Vec<&'a ScannedNote> {
    notes
        .iter()
        .filter(|note| {
            args.type_path
                .as_deref()
                .map_or(true, |type_path| type_matches(&note.path, type_path))
                && (!args.pinned || note.pinned)
                && if args.archived {
                    note.archived
                } else if args.include_archived {
                    true
                } else {
                    !note.archived
                }
        })
        .collect()
}

fn selector_candidates<'a>(
    notes: &'a [ScannedNote],
    selector: &NoteSelector,
) -> Vec<&'a ScannedNote> {
    if let Some(id) = selector.id.as_deref() {
        let id = id.to_lowercase();
        return notes
            .iter()
            .filter(|note| {
                note.id
                    .is_some_and(|value| value.to_string().starts_with(&id))
            })
            .collect();
    }
    if let Some(path) = selector.path.as_deref() {
        let path = path.replace('\\', "/");
        return notes.iter().filter(|note| note.path == path).collect();
    }
    let title = selector
        .title
        .as_deref()
        .or(selector.target.as_deref())
        .unwrap_or_default();
    if selector.target.is_some() {
        let normalized = title.replace('\\', "/");
        let paths: Vec<&ScannedNote> = notes
            .iter()
            .filter(|note| note.path == normalized)
            .collect();
        if !paths.is_empty() {
            return paths;
        }
        let id = title.to_lowercase();
        let ids: Vec<&ScannedNote> = notes
            .iter()
            .filter(|note| {
                note.id
                    .is_some_and(|value| value.to_string().starts_with(&id))
            })
            .collect();
        if !ids.is_empty() {
            return ids;
        }
    }
    notes
        .iter()
        .filter(|note| note.title.eq_ignore_ascii_case(title))
        .collect()
}

fn choose_note<'a>(
    cli: &Cli,
    notes: &'a [ScannedNote],
    selector: &NoteSelector,
) -> Result<&'a ScannedNote, CliError> {
    let candidates = selector_candidates(notes, selector);
    if candidates.is_empty() {
        return Err(CliError::new(
            "note_not_found",
            "No note matches that selector",
            3,
        ));
    }
    if candidates.len() == 1 {
        return Ok(candidates[0]);
    }
    let details = json!(candidates
        .iter()
        .map(|note| json!({"title": note.title, "path": note.path, "noteId": note.id}))
        .collect::<Vec<_>>());
    if cli.no_input
        || cli.json
        || cli.jsonl
        || !io::stdin().is_terminal()
        || !io::stderr().is_terminal()
    {
        return Err(CliError::new(
            "ambiguous_selector",
            "Multiple notes match that selector",
            4,
        )
        .details(details));
    }
    let labels: Vec<String> = candidates
        .iter()
        .map(|note| {
            format!(
                "{}   {}   {}",
                note.title,
                note.path
                    .rsplit_once('/')
                    .map(|(folder, _)| folder)
                    .unwrap_or("unfiled"),
                note.id
                    .map(|id| id.to_string()[..8].to_string())
                    .unwrap_or_else(|| "no-id".into())
            )
        })
        .collect();
    let selection = Select::with_theme(&ColorfulTheme::default())
        .with_prompt("Multiple notes match")
        .items(&labels)
        .interact_opt()
        .map_err(|error| CliError::new("selection_failed", error.to_string(), 2))?
        .ok_or_else(|| CliError::new("cancelled", "Selection cancelled", 5))?;
    Ok(candidates[selection])
}

fn property_string(value: &zerus_core::PropertyValue) -> String {
    match value {
        zerus_core::PropertyValue::String(value) => value.clone(),
        zerus_core::PropertyValue::Number(value) => value.to_string(),
        zerus_core::PropertyValue::Boolean(value) => value.to_string(),
        zerus_core::PropertyValue::List(value) => value.join(","),
    }
}

fn search_notes<'a>(
    notes: &'a [ScannedNote],
    args: &SearchArgs,
) -> Result<Vec<&'a ScannedNote>, CliError> {
    let regex = args
        .regex
        .as_deref()
        .map(Regex::new)
        .transpose()
        .map_err(|error| CliError::new("invalid_regex", error.to_string(), 2))?;
    let properties: Result<Vec<(&str, &str)>, CliError> = args
        .property
        .iter()
        .map(|filter| {
            filter.split_once('=').ok_or_else(|| {
                CliError::new(
                    "invalid_filter",
                    format!("Property filter must be KEY=VALUE: {filter}"),
                    2,
                )
            })
        })
        .collect();
    let properties = properties?;
    let lower = |value: &str| value.to_lowercase();
    Ok(notes
        .iter()
        .filter(|note| {
            let searchable = format!("{}\n{}", note.title, note.content).to_lowercase();
            args.query
                .as_deref()
                .map_or(true, |query| searchable.contains(&lower(query)))
                && args
                    .title
                    .as_deref()
                    .map_or(true, |query| lower(&note.title).contains(&lower(query)))
                && args.body.as_deref().map_or(true, |query| {
                    lower(note_body(&note.content)).contains(&lower(query))
                })
                && regex
                    .as_ref()
                    .map_or(true, |pattern| pattern.is_match(&note.content))
                && args
                    .type_path
                    .as_deref()
                    .map_or(true, |type_path| type_matches(&note.path, type_path))
                && (!args.pinned || note.pinned)
                && if args.archived {
                    note.archived
                } else if args.include_archived {
                    true
                } else {
                    !note.archived
                }
                && properties.iter().all(|(key, expected)| {
                    note.properties
                        .iter()
                        .find(|(candidate, _)| candidate.eq_ignore_ascii_case(key))
                        .is_some_and(|(_, value)| {
                            property_string(value).eq_ignore_ascii_case(expected)
                        })
                })
        })
        .collect())
}

fn success(cli: &Cli, data: Value, human: impl FnOnce() -> String) -> Result<(), CliError> {
    if cli.json || cli.jsonl {
        let envelope = json!({"schemaVersion": SCHEMA_VERSION, "ok": true, "data": data});
        println!(
            "{}",
            if cli.json {
                serde_json::to_string_pretty(&envelope)
            } else {
                serde_json::to_string(&envelope)
            }
            .unwrap()
        );
    } else if cli.quiet {
        if let Some(value) = data.as_str() {
            println!("{value}");
        } else {
            println!("{}", serde_json::to_string(&data).unwrap());
        }
    } else {
        println!("{}", human());
    }
    Ok(())
}

fn output_collection<T: Serialize>(
    cli: &Cli,
    values: &[T],
    human: impl FnOnce() -> String,
) -> Result<(), CliError> {
    if cli.jsonl {
        for value in values {
            println!("{}", serde_json::to_string(value).unwrap());
        }
        Ok(())
    } else {
        success(cli, serde_json::to_value(values).unwrap(), human)
    }
}

fn execute(cli: &Cli) -> Result<(), CliError> {
    match &cli.command {
        Command::Vault { command } => match command {
            VaultCommand::List => {
                let (_, registry) = registry()?;
                let values = registry.vaults.clone();
                output_collection(cli, &values, || {
                    if values.is_empty() {
                        "No vaults registered".into()
                    } else {
                        values
                            .iter()
                            .map(|vault| {
                                let marker = (Some(vault.id) == registry.default_vault_id)
                                    .then_some(" *")
                                    .unwrap_or("");
                                format!(
                                    "{}{}\t{}\t{}",
                                    vault.name,
                                    marker,
                                    vault.id,
                                    vault.path.display()
                                )
                            })
                            .collect::<Vec<_>>()
                            .join("\n")
                    }
                })
            }
            VaultCommand::Add {
                name,
                path,
                make_default,
            } => {
                let root = path
                    .canonicalize()
                    .map_err(|error| CliError::new("vault_unavailable", error.to_string(), 2))?;
                if !root.is_dir() {
                    return Err(CliError::new(
                        "vault_unavailable",
                        "Vault path is not a directory",
                        2,
                    ));
                }
                let manifest = load_or_create_manifest(&root)
                    .map_err(|error| CliError::new("vault_invalid", error.to_string(), 2))?;
                let (registry_path, mut registry) = registry()?;
                if registry.vaults.iter().any(|vault| {
                    vault.name.eq_ignore_ascii_case(name) && vault.id != manifest.vault_id
                }) {
                    return Err(CliError::new(
                        "vault_name_exists",
                        "Another vault already uses that name",
                        3,
                    ));
                }
                registry
                    .vaults
                    .retain(|vault| vault.id != manifest.vault_id);
                let record = VaultRecord {
                    id: manifest.vault_id,
                    name: name.trim().to_string(),
                    path: root,
                };
                registry.vaults.push(record.clone());
                registry.vaults.sort_by(|left, right| {
                    left.name.to_lowercase().cmp(&right.name.to_lowercase())
                });
                if *make_default || registry.default_vault_id.is_none() {
                    registry.default_vault_id = Some(record.id);
                }
                save_registry(&registry_path, &registry).map_err(|error| {
                    CliError::new("registry_write_failed", error.to_string(), 2)
                })?;
                success(cli, serde_json::to_value(&record).unwrap(), || {
                    format!(
                        "Registered vault '{}' at {}",
                        record.name,
                        record.path.display()
                    )
                })
            }
            VaultCommand::Default { selector } => {
                let (path, mut registry) = registry()?;
                let id = resolve_vault(&registry, Some(selector))
                    .map_err(|error| CliError::new("vault_not_found", error.to_string(), 3))?
                    .id;
                registry.default_vault_id = Some(id);
                save_registry(&path, &registry).map_err(|error| {
                    CliError::new("registry_write_failed", error.to_string(), 2)
                })?;
                success(cli, json!({"vaultId": id}), || {
                    format!("Default vault set to {selector}")
                })
            }
            VaultCommand::Current => {
                let (root, id) = resolve_root(cli)?;
                success(cli, json!({"vaultId": id, "path": root}), || {
                    root.display().to_string()
                })
            }
        },
        Command::Doctor => {
            let (root, _) = resolve_root(cli)?;
            let report = diagnose_vault(&root)
                .map_err(|error| CliError::new("vault_unavailable", error.to_string(), 2))?;
            success(cli, serde_json::to_value(&report).unwrap(), || {
                format!(
                    "Scanned {} notes: {} missing IDs, {} duplicate ID groups, {} issues",
                    report.notes_scanned,
                    report.missing_ids,
                    report.duplicate_ids,
                    report.issues.len()
                )
            })
        }
        Command::Note { command } => {
            let (notes, vault_id, root) = load_notes(cli)?;
            match command {
                NoteCommand::List(args) => {
                    let matches = filtered_list(&notes, args);
                    let values: Vec<_> = matches
                        .iter()
                        .map(|note| summary(note, &vault_id))
                        .collect();
                    output_collection(cli, &values, || {
                        matches
                            .iter()
                            .map(|note| {
                                format!(
                                    "{}\t{}\t{}",
                                    note.title,
                                    note.path,
                                    note.id
                                        .map(|id| id.to_string()[..8].to_string())
                                        .unwrap_or_else(|| "no-id".into())
                                )
                            })
                            .collect::<Vec<_>>()
                            .join("\n")
                    })
                }
                NoteCommand::Get {
                    selector,
                    body,
                    raw,
                } => {
                    let note = choose_note(cli, &notes, selector)?;
                    let content = if *body {
                        note_body(&note.content)
                    } else {
                        &note.content
                    };
                    if cli.json {
                        success(
                            cli,
                            json!({"note": summary(note, &vault_id), "content": content, "properties": note.properties}),
                            || note.content.clone(),
                        )
                    } else if *raw || *body || cli.quiet {
                        print!("{content}");
                        io::stdout().flush().ok();
                        Ok(())
                    } else {
                        success(
                            cli,
                            json!({"note": summary(note, &vault_id), "content": note.content, "properties": note.properties}),
                            || note.content.clone(),
                        )
                    }
                }
                NoteCommand::Create { path, title, body } => {
                    let relative = if path.ends_with(".md") || path.ends_with(".markdown") {
                        path.clone()
                    } else {
                        format!("{path}.md")
                    };
                    let destination = valid_note_destination(&root, &relative)?;
                    let heading = title.clone().unwrap_or_else(|| {
                        Path::new(&relative)
                            .file_stem()
                            .and_then(|v| v.to_str())
                            .unwrap_or("Untitled")
                            .to_string()
                    });
                    let initial = body.clone().unwrap_or_else(|| format!("# {heading}\n"));
                    let (content, id) = ensure_note_id(&initial)
                        .map_err(|e| CliError::new("note_invalid", e.to_string(), 3))?;
                    atomic_write(&destination, &content, None)
                        .map_err(|e| CliError::new("write_failed", e.to_string(), 5))?;
                    let entry = save_history(
                        &root,
                        "note.create",
                        None,
                        Some(&relative),
                        None,
                        Some(&content),
                    )?;
                    success(
                        cli,
                        json!({"noteId": id, "path": relative, "transactionId": entry.transaction_id}),
                        || format!("Created {relative}"),
                    )
                }
                NoteCommand::SetBody {
                    selector,
                    content,
                    if_revision,
                } => {
                    let note = choose_note(cli, &notes, selector)?;
                    let body = note_body(&note.content);
                    let prefix = &note.content[..note.content.len() - body.len()];
                    let next = format!("{prefix}{content}");
                    let entry =
                        write_note(&root, note, "note.set-body", &next, if_revision.as_deref())?;
                    success(
                        cli,
                        json!({"path": note.path, "transactionId": entry.transaction_id}),
                        || format!("Updated {}", note.path),
                    )
                }
                NoteCommand::Append {
                    selector,
                    text,
                    if_revision,
                }
                | NoteCommand::Prepend {
                    selector,
                    text,
                    if_revision,
                } => {
                    let note = choose_note(cli, &notes, selector)?;
                    let append = matches!(command, NoteCommand::Append { .. });
                    let body = note_body(&note.content);
                    let prefix = &note.content[..note.content.len() - body.len()];
                    let next_body = if append {
                        format!("{body}{text}")
                    } else {
                        format!("{text}{body}")
                    };
                    let next = format!("{prefix}{next_body}");
                    let operation = if append {
                        "note.append"
                    } else {
                        "note.prepend"
                    };
                    let entry = write_note(&root, note, operation, &next, if_revision.as_deref())?;
                    success(
                        cli,
                        json!({"path": note.path, "transactionId": entry.transaction_id}),
                        || format!("Updated {}", note.path),
                    )
                }
                NoteCommand::Pin { selector }
                | NoteCommand::Unpin { selector }
                | NoteCommand::Archive { selector }
                | NoteCommand::Unarchive { selector } => {
                    let note = choose_note(cli, &notes, selector)?;
                    let (pinned, archived, operation) = match command {
                        NoteCommand::Pin { .. } => (Some(true), None, "note.pin"),
                        NoteCommand::Unpin { .. } => (Some(false), None, "note.unpin"),
                        NoteCommand::Archive { .. } => (None, Some(true), "note.archive"),
                        _ => (None, Some(false), "note.unarchive"),
                    };
                    let (with_id, _) = ensure_note_id(&note.content)
                        .map_err(|e| CliError::new("note_invalid", e.to_string(), 3))?;
                    let next = set_note_state(&with_id, pinned, archived)
                        .map_err(|e| CliError::new("note_invalid", e.to_string(), 3))?;
                    let entry = write_note(&root, note, operation, &next, None)?;
                    success(
                        cli,
                        json!({"path": note.path, "transactionId": entry.transaction_id}),
                        || format!("Updated {}", note.path),
                    )
                }
                NoteCommand::Trash { selector } | NoteCommand::Restore { selector } => {
                    let note = choose_note(cli, &notes, selector)?;
                    let restoring = matches!(command, NoteCommand::Restore { .. });
                    let relative = if restoring {
                        note.path
                            .strip_prefix(".trash/")
                            .ok_or_else(|| CliError::new("not_trashed", "note is not in trash", 3))?
                            .to_string()
                    } else {
                        if note.path.starts_with(".trash/") {
                            return Err(CliError::new(
                                "already_trashed",
                                "note is already in trash",
                                3,
                            ));
                        }
                        format!(".trash/{}", note.path)
                    };
                    let destination = valid_note_destination(&root, &relative)?;
                    fs::create_dir_all(destination.parent().unwrap())
                        .map_err(|e| CliError::new("write_failed", e.to_string(), 5))?;
                    fs::rename(&note.absolute_path, &destination)
                        .map_err(|e| CliError::new("write_failed", e.to_string(), 5))?;
                    let operation = if restoring {
                        "note.restore"
                    } else {
                        "note.trash"
                    };
                    let entry = save_history(
                        &root,
                        operation,
                        Some(&note.path),
                        Some(&relative),
                        Some(&note.content),
                        Some(&note.content),
                    )?;
                    success(
                        cli,
                        json!({"path": relative, "transactionId": entry.transaction_id}),
                        || format!("Moved to {relative}"),
                    )
                }
                NoteCommand::Open { selector } => {
                    let note = choose_note(cli, &notes, selector)?;
                    #[cfg(target_os = "macos")]
                    let status = std::process::Command::new("open")
                        .args(["-a", "Zerus"])
                        .arg(&note.absolute_path)
                        .status();
                    #[cfg(target_os = "windows")]
                    let status = std::process::Command::new("cmd")
                        .args(["/C", "start", ""])
                        .arg(&note.absolute_path)
                        .status();
                    #[cfg(all(not(target_os = "macos"), not(target_os = "windows")))]
                    let status = std::process::Command::new("xdg-open")
                        .arg(&note.absolute_path)
                        .status();
                    status.map_err(|e| CliError::new("open_failed", e.to_string(), 2))?;
                    success(cli, json!({"path": note.path}), || {
                        format!("Opened {}", note.path)
                    })
                }
                NoteCommand::Property { command } => match command {
                    PropertyCommand::List { selector } => {
                        let note = choose_note(cli, &notes, selector)?;
                        let visible: std::collections::BTreeMap<_, _> = note
                            .properties
                            .iter()
                            .filter(|(key, _)| !key.to_ascii_lowercase().starts_with("zerus-"))
                            .collect();
                        success(cli, serde_json::to_value(&visible).unwrap(), || {
                            visible
                                .iter()
                                .map(|(k, v)| format!("{k}\t{}", property_string(v)))
                                .collect::<Vec<_>>()
                                .join("\n")
                        })
                    }
                    PropertyCommand::Set {
                        selector,
                        key,
                        value,
                        if_revision,
                    } => {
                        let note = choose_note(cli, &notes, selector)?;
                        let next = set_property(&note.content, key, Some(value))
                            .map_err(|e| CliError::new("property_invalid", e.to_string(), 3))?;
                        let entry =
                            write_note(&root, note, "property.set", &next, if_revision.as_deref())?;
                        success(
                            cli,
                            json!({"path": note.path, "key": key, "transactionId": entry.transaction_id}),
                            || format!("Updated property {key} on {}", note.path),
                        )
                    }
                    PropertyCommand::Unset {
                        selector,
                        key,
                        if_revision,
                    } => {
                        let note = choose_note(cli, &notes, selector)?;
                        let next = set_property(&note.content, key, None)
                            .map_err(|e| CliError::new("property_invalid", e.to_string(), 3))?;
                        let entry = write_note(
                            &root,
                            note,
                            "property.unset",
                            &next,
                            if_revision.as_deref(),
                        )?;
                        success(
                            cli,
                            json!({"path": note.path, "key": key, "transactionId": entry.transaction_id}),
                            || format!("Removed property {key} from {}", note.path),
                        )
                    }
                },
            }
        }
        Command::Search(args) => {
            let (notes, vault_id, _) = load_notes(cli)?;
            let matches = search_notes(&notes, args)?;
            let values: Vec<_> = matches
                .iter()
                .map(|note| summary(note, &vault_id))
                .collect();
            output_collection(cli, &values, || {
                matches
                    .iter()
                    .map(|note| {
                        format!(
                            "{}\t{}\t{}",
                            note.title,
                            note.path,
                            note.id
                                .map(|id| id.to_string()[..8].to_string())
                                .unwrap_or_else(|| "no-id".into())
                        )
                    })
                    .collect::<Vec<_>>()
                    .join("\n")
            })
        }
        Command::Import(args) => {
            let (root, _) = resolve_root(cli)?;
            let source = args
                .source
                .canonicalize()
                .map_err(|e| CliError::new("source_unavailable", e.to_string(), 3))?;
            if !source.is_file() {
                return Err(CliError::new(
                    "source_unavailable",
                    "source must be a Markdown file",
                    3,
                ));
            }
            let extension = source
                .extension()
                .and_then(|v| v.to_str())
                .unwrap_or("")
                .to_ascii_lowercase();
            if !matches!(extension.as_str(), "md" | "markdown") {
                return Err(CliError::new(
                    "unsupported_file",
                    "only Markdown notes can be imported",
                    3,
                ));
            }
            let name = source.file_name().and_then(|v| v.to_str()).ok_or_else(|| {
                CliError::new("invalid_path", "source name is not valid UTF-8", 3)
            })?;
            let relative = args
                .to
                .as_deref()
                .map(|folder| format!("{}/{name}", folder.trim_matches('/')))
                .unwrap_or_else(|| name.to_string());
            let destination = valid_note_destination(&root, &relative)?;
            let original = fs::read_to_string(&source)
                .map_err(|e| CliError::new("source_unavailable", e.to_string(), 3))?;
            let (content, id) = ensure_note_id(&original)
                .map_err(|e| CliError::new("note_invalid", e.to_string(), 3))?;
            atomic_write(&destination, &content, None)
                .map_err(|e| CliError::new("write_failed", e.to_string(), 5))?;
            if args.r#move {
                if let Err(error) = fs::remove_file(&source) {
                    let _ = fs::remove_file(&destination);
                    return Err(CliError::new("source_remove_failed", error.to_string(), 5));
                }
            }
            let entry = save_history(
                &root,
                if args.r#move {
                    "note.import-move"
                } else {
                    "note.import-copy"
                },
                None,
                Some(&relative),
                None,
                Some(&content),
            )?;
            success(
                cli,
                json!({"noteId": id, "path": relative, "absolutePath": destination, "source": source, "moved": args.r#move, "transactionId": entry.transaction_id}),
                || format!("Imported to {}", destination.display()),
            )
        }
        Command::Migrate { command } => {
            let (notes, _, root) = load_notes(cli)?;
            let legacy_metadata_dir = root.join(".grimoire");
            let zerus_metadata_dir = root.join(".zerus");
            let moves_metadata_directory = legacy_metadata_dir.is_dir();
            if moves_metadata_directory && zerus_metadata_dir.exists() {
                return Err(CliError::new(
                    "migration_blocked",
                    "both .grimoire and .zerus exist; merge or remove one before migrating",
                    4,
                ));
            }
            let mut plans = Vec::new();
            for note in &notes {
                let plan = plan_note_metadata_migration(
                    &note.content,
                    Uuid::now_v7(),
                    note.pinned,
                    note.archived,
                )
                .map_err(|e| {
                    CliError::new("migration_blocked", format!("{}: {e}", note.path), 4)
                })?;
                if plan.changed {
                    plans.push((note, plan));
                }
            }
            match command {
                MigrateCommand::Preview => success(
                    cli,
                    json!({"notesScanned": notes.len(), "notesChanged": plans.len(), "legacyKeysRenamed": plans.iter().map(|(_, plan)| plan.legacy_keys_renamed).sum::<usize>(), "movesMetadataDirectory": moves_metadata_directory, "changes": plans.iter().map(|(note, plan)| json!({"path": note.path, "beforeRevision": plan.before_revision, "afterRevision": plan.after_revision, "addsId": plan.id_added, "legacyKeysRenamed": plan.legacy_keys_renamed})).collect::<Vec<_>>() }),
                    || {
                        format!(
                            "{} of {} notes will receive hidden Zerus metadata",
                            plans.len(),
                            notes.len()
                        )
                    },
                ),
                MigrateCommand::Apply { yes } => {
                    if !yes {
                        return Err(CliError::new(
                            "approval_required",
                            "review `zerus migrate preview`, then run with --yes",
                            6,
                        ));
                    }
                    if moves_metadata_directory {
                        fs::rename(&legacy_metadata_dir, &zerus_metadata_dir).map_err(|error| {
                            CliError::new("migration_metadata_move_failed", error.to_string(), 5)
                        })?;
                    }
                    let mut transaction_ids = Vec::new();
                    for (note, plan) in plans {
                        let entry = write_note(
                            &root,
                            note,
                            "migration.metadata",
                            &plan.next_content,
                            Some(&plan.before_revision),
                        )?;
                        transaction_ids.push(entry.transaction_id);
                    }
                    let mut manifest = load_or_create_manifest(&root)
                        .map_err(|e| CliError::new("vault_invalid", e.to_string(), 2))?;
                    manifest.metadata_version = 1;
                    manifest.ids_required = true;
                    write_vault_manifest(&root, &manifest)
                        .map_err(|e| CliError::new("vault_invalid", e.to_string(), 2))?;
                    success(
                        cli,
                        json!({"notesChanged": transaction_ids.len(), "transactionIds": transaction_ids}),
                        || format!("Migrated {} notes", transaction_ids.len()),
                    )
                }
            }
        }
        Command::History => {
            let (root, _) = resolve_root(cli)?;
            let entries = history_entries(&root)?;
            output_collection(cli, &entries, || {
                entries
                    .iter()
                    .map(|e| {
                        format!(
                            "{}\t{}\t{}",
                            e.transaction_id,
                            e.operation,
                            e.path_after.as_deref().unwrap_or("-")
                        )
                    })
                    .collect::<Vec<_>>()
                    .join("\n")
            })
        }
        Command::Undo { transaction_id } => {
            let (root, _) = resolve_root(cli)?;
            let entries = history_entries(&root)?;
            let entry = if let Some(id) = transaction_id {
                entries
                    .into_iter()
                    .find(|e| e.transaction_id.starts_with(id))
                    .ok_or_else(|| {
                        CliError::new("history_not_found", "transaction was not found", 3)
                    })?
            } else {
                entries
                    .into_iter()
                    .next()
                    .ok_or_else(|| CliError::new("history_not_found", "history is empty", 3))?
            };
            if entry.operation == "undo" {
                return Err(CliError::new(
                    "undo_invalid",
                    "an undo record cannot be undone directly",
                    3,
                ));
            }
            if let Some(after_path) = &entry.path_after {
                let current = root.join(after_path);
                match (&entry.path_before, &entry.content_before) {
                    (Some(before_path), Some(before)) => {
                        let destination = root.join(before_path);
                        if current != destination && current.exists() {
                            if destination.exists() {
                                return Err(CliError::new(
                                    "path_exists",
                                    format!("{} already exists", destination.display()),
                                    3,
                                ));
                            }
                            fs::create_dir_all(destination.parent().unwrap())
                                .map_err(|e| CliError::new("undo_failed", e.to_string(), 5))?;
                            fs::rename(&current, &destination)
                                .map_err(|e| CliError::new("undo_failed", e.to_string(), 5))?;
                        }
                        atomic_write(&destination, before, None)
                            .map_err(|e| CliError::new("undo_failed", e.to_string(), 5))?;
                    }
                    (None, None) => {
                        if current.exists() {
                            fs::remove_file(&current)
                                .map_err(|e| CliError::new("undo_failed", e.to_string(), 5))?;
                        }
                    }
                    _ => {
                        return Err(CliError::new(
                            "undo_invalid",
                            "history entry is incomplete",
                            3,
                        ))
                    }
                }
            }
            let undo = save_history(
                &root,
                "undo",
                entry.path_after.as_deref(),
                entry.path_before.as_deref(),
                entry.content_after.as_deref(),
                entry.content_before.as_deref(),
            )?;
            success(
                cli,
                json!({"undoneTransactionId": entry.transaction_id, "transactionId": undo.transaction_id}),
                || format!("Undid {}", entry.transaction_id),
            )
        }
        Command::Type { command } => {
            let (notes, _, root) = load_notes(cli)?;
            match command {
                TypeCommand::List => {
                    let mut types = std::collections::BTreeSet::new();
                    for note in &notes {
                        let mut parts: Vec<_> = note.path.split('/').collect();
                        parts.pop();
                        for depth in 1..=parts.len() {
                            types.insert(parts[..depth].join("/"));
                        }
                    }
                    let values: Vec<_> = types.into_iter().collect();
                    output_collection(cli, &values, || values.join("\n"))
                }
                TypeCommand::Move { selector, to } => {
                    let note = choose_note(cli, &notes, selector)?;
                    let name = Path::new(&note.path)
                        .file_name()
                        .and_then(|v| v.to_str())
                        .unwrap_or("Note.md");
                    let relative = format!("{}/{name}", to.trim_matches('/'));
                    let destination = valid_note_destination(&root, &relative)?;
                    fs::create_dir_all(destination.parent().unwrap())
                        .map_err(|e| CliError::new("write_failed", e.to_string(), 5))?;
                    fs::rename(&note.absolute_path, &destination)
                        .map_err(|e| CliError::new("write_failed", e.to_string(), 5))?;
                    let entry = save_history(
                        &root,
                        "type.move",
                        Some(&note.path),
                        Some(&relative),
                        Some(&note.content),
                        Some(&note.content),
                    )?;
                    success(
                        cli,
                        json!({"path": relative, "transactionId": entry.transaction_id}),
                        || format!("Moved to {relative}"),
                    )
                }
            }
        }
        Command::Links { selector } => {
            let (notes, _, _) = load_notes(cli)?;
            let note = choose_note(cli, &notes, selector)?;
            let wiki = Regex::new(r"\[\[([^\]|#]+)").unwrap();
            let outgoing: Vec<_> = wiki
                .captures_iter(&note.content)
                .map(|capture| capture[1].trim().to_string())
                .collect();
            let needles = [
                note.title.clone(),
                note.path.clone(),
                note.id.map(|id| id.to_string()).unwrap_or_default(),
            ];
            let backlinks: Vec<_> = notes.iter().filter(|candidate| candidate.path != note.path && needles.iter().filter(|value| !value.is_empty()).any(|value| candidate.content.contains(&format!("[[{value}")))).map(|candidate| json!({"path": candidate.path, "title": candidate.title, "noteId": candidate.id})).collect();
            success(
                cli,
                json!({"note": note.path, "outgoing": outgoing, "backlinks": backlinks}),
                || {
                    format!(
                        "{} outgoing links, {} backlinks",
                        outgoing.len(),
                        backlinks.len()
                    )
                },
            )
        }
        Command::Export {
            output,
            query,
            include_archived,
        } => {
            let (notes, _, _) = load_notes(cli)?;
            let selected: Vec<&ScannedNote> = notes
                .iter()
                .filter(|note| {
                    (*include_archived || !note.archived)
                        && query.as_deref().map_or(true, |value| {
                            note.title.to_lowercase().contains(&value.to_lowercase())
                                || note.content.to_lowercase().contains(&value.to_lowercase())
                        })
                })
                .collect();
            fs::create_dir_all(output)
                .map_err(|e| CliError::new("export_failed", e.to_string(), 5))?;
            for note in &selected {
                let destination = output.join(&note.path);
                fs::create_dir_all(destination.parent().unwrap())
                    .map_err(|e| CliError::new("export_failed", e.to_string(), 5))?;
                fs::write(destination, &note.content)
                    .map_err(|e| CliError::new("export_failed", e.to_string(), 5))?;
            }
            let manifest = json!({"schemaVersion": 1, "notes": selected.iter().map(|note| summary(note, "export")).collect::<Vec<_>>()});
            fs::write(
                output.join("zerus-export.json"),
                serde_json::to_vec_pretty(&manifest).unwrap(),
            )
            .map_err(|e| CliError::new("export_failed", e.to_string(), 5))?;
            success(
                cli,
                json!({"output": output, "notesExported": selected.len()}),
                || format!("Exported {} notes to {}", selected.len(), output.display()),
            )
        }
        Command::Bulk { command } => {
            let (notes, _, root) = load_notes(cli)?;
            let (query, yes) = match command {
                BulkCommand::PropertySet { query, yes, .. }
                | BulkCommand::Archive { query, yes } => (query, *yes),
            };
            let lowered = query.to_lowercase();
            let matches: Vec<_> = notes
                .iter()
                .filter(|note| {
                    !note.archived
                        && (note.title.to_lowercase().contains(&lowered)
                            || note.content.to_lowercase().contains(&lowered))
                })
                .collect();
            if !yes {
                return success(
                    cli,
                    json!({"approvalRequired": true, "notesMatched": matches.len(), "notes": matches.iter().map(|note| json!({"path": note.path, "title": note.title, "revision": note.revision})).collect::<Vec<_>>()}),
                    || {
                        format!(
                            "Preview: {} notes match. Re-run with --yes to apply.",
                            matches.len()
                        )
                    },
                );
            }
            let mut transactions = Vec::new();
            for note in matches {
                let (next, operation) = match command {
                    BulkCommand::PropertySet { key, value, .. } => (
                        set_property(&note.content, key, Some(value))
                            .map_err(|e| CliError::new("property_invalid", e.to_string(), 3))?,
                        "bulk.property-set",
                    ),
                    BulkCommand::Archive { .. } => (
                        set_note_state(&note.content, None, Some(true))
                            .map_err(|e| CliError::new("note_invalid", e.to_string(), 3))?,
                        "bulk.archive",
                    ),
                };
                transactions.push(
                    write_note(&root, note, operation, &next, Some(&note.revision))?.transaction_id,
                );
            }
            success(
                cli,
                json!({"notesChanged": transactions.len(), "transactionIds": transactions}),
                || format!("Updated {} notes", transactions.len()),
            )
        }
        Command::Schema { command } => {
            let (root, _) = resolve_root(cli)?;
            let mut schemas = load_schemas(&root)?;
            match command {
                SchemaCommand::List { type_path } => {
                    let value = match type_path.as_deref() {
                        Some(path) => {
                            let key = normalize_schema_type_path(path)?;
                            Value::Array(effective_schema_definitions(&schemas, &key))
                        }
                        None => Value::Object(schemas.clone()),
                    };
                    success(cli, value.clone(), || {
                        serde_json::to_string_pretty(&value).unwrap()
                    })
                }
                SchemaCommand::Add {
                    type_path,
                    name,
                    kind,
                    options,
                    relation_type,
                    multiple,
                } => {
                    if zerus_core::is_reserved_key(name) {
                        return Err(CliError::new(
                            "property_invalid",
                            "zerus-* names are reserved",
                            3,
                        ));
                    }
                    if !matches!(
                        kind.as_str(),
                        "text" | "url" | "number" | "date" | "checkbox" | "list" | "relation"
                    ) {
                        return Err(CliError::new(
                            "schema_invalid",
                            "kind must be text, url, number, date, checkbox, list, or relation",
                            3,
                        ));
                    }
                    if kind != "list" && !options.is_empty() {
                        return Err(CliError::new(
                            "schema_invalid",
                            "--options can only be used with list properties",
                            3,
                        ));
                    }
                    if kind != "relation" && relation_type.is_some() {
                        return Err(CliError::new(
                            "schema_invalid",
                            "--relation-type can only be used with relation properties",
                            3,
                        ));
                    }
                    if *multiple && !matches!(kind.as_str(), "list" | "relation") {
                        return Err(CliError::new(
                            "schema_invalid",
                            "--multiple can only be used with list or relation properties",
                            3,
                        ));
                    }
                    let key = normalize_schema_type_path(type_path)?;
                    let definitions = schemas
                        .entry(key.clone())
                        .or_insert_with(|| Value::Array(Vec::new()))
                        .as_array_mut()
                        .ok_or_else(|| {
                            CliError::new("schema_invalid", "type schema must be an array", 3)
                        })?;
                    if definitions.iter().any(|definition| {
                        definition["name"]
                            .as_str()
                            .is_some_and(|value| value.eq_ignore_ascii_case(name))
                    }) {
                        return Err(CliError::new(
                            "schema_exists",
                            "that property is already defined",
                            3,
                        ));
                    }
                    let mut definition = json!({"name": name, "type": kind});
                    if kind == "list" {
                        let mut normalized_options = Vec::<String>::new();
                        for option in options {
                            let option = option.trim();
                            if option.is_empty()
                                || normalized_options
                                    .iter()
                                    .any(|value| value.eq_ignore_ascii_case(option))
                            {
                                continue;
                            }
                            normalized_options.push(option.to_string());
                        }
                        if !normalized_options.is_empty() {
                            definition["listOptions"] = json!(normalized_options);
                        }
                        definition["listMultiple"] = json!(multiple);
                    }
                    if kind == "relation" {
                        if let Some(relation_type) = relation_type {
                            definition["relationTypeKey"] =
                                json!(normalize_schema_type_path(relation_type)?);
                        }
                        definition["relationMultiple"] = json!(multiple);
                    }
                    definitions.push(definition.clone());
                    save_schemas(&root, &schemas)?;
                    success(
                        cli,
                        json!({"type": key, "name": name, "kind": kind, "definition": definition}),
                        || format!("Added {name} to {key}"),
                    )
                }
                SchemaCommand::Remove {
                    type_path,
                    name,
                    purge_values,
                    yes,
                } => {
                    if *purge_values && !yes {
                        return Err(CliError::new("approval_required", "purging note values is a data-loss action; preview without --purge-values or re-run with --yes", 6));
                    }
                    let key = normalize_schema_type_path(type_path)?;
                    let remove_empty_schema = {
                        let definitions = schemas
                            .get_mut(&key)
                            .and_then(Value::as_array_mut)
                            .ok_or_else(|| {
                                CliError::new("schema_not_found", "type schema was not found", 3)
                            })?;
                        let before = definitions.len();
                        definitions.retain(|definition| {
                            !definition["name"]
                                .as_str()
                                .is_some_and(|value| value.eq_ignore_ascii_case(name))
                        });
                        if definitions.len() == before {
                            return Err(CliError::new(
                                "schema_not_found",
                                "property definition was not found",
                                3,
                            ));
                        }
                        definitions.is_empty()
                    };
                    if remove_empty_schema {
                        schemas.remove(&key);
                    }
                    save_schemas(&root, &schemas)?;
                    let mut transactions = Vec::new();
                    if *purge_values {
                        for note in scan_vault(&root)
                            .map_err(|e| CliError::new("vault_unavailable", e.to_string(), 2))?
                            .iter()
                            .filter(|note| type_matches(&note.path, &key))
                            .filter(|note| {
                                effective_schema_definition_owner(
                                    &schemas,
                                    &note_type_key(&note.path),
                                    name,
                                )
                                .is_none()
                            })
                        {
                            let next = set_property(&note.content, name, None)
                                .map_err(|e| CliError::new("property_invalid", e.to_string(), 3))?;
                            if next != note.content {
                                transactions.push(
                                    write_note(
                                        &root,
                                        note,
                                        "schema.purge-values",
                                        &next,
                                        Some(&note.revision),
                                    )?
                                    .transaction_id,
                                );
                            }
                        }
                    }
                    success(
                        cli,
                        json!({"type": key, "name": name, "valuesPurged": purge_values, "transactionIds": transactions}),
                        || {
                            if *purge_values {
                                format!("Removed {name} and purged {} values", transactions.len())
                            } else {
                                format!("Removed {name}; existing note values were preserved")
                            }
                        },
                    )
                }
            }
        }
    }
}

fn render_error(cli: &Cli, error: &CliError) {
    if cli.json || cli.jsonl {
        eprintln!("{}", serde_json::to_string(&json!({"schemaVersion": SCHEMA_VERSION, "ok": false, "error": {"code": error.code, "message": error.message, "details": error.details}})).unwrap());
    } else {
        eprintln!("Error [{}]: {}", error.code, error.message);
        if !error.details.is_null() {
            eprintln!("{}", serde_json::to_string_pretty(&error.details).unwrap());
        }
    }
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match execute(&cli) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            render_error(&cli, &error);
            ExitCode::from(error.exit)
        }
    }
}
