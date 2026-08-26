use clap::{Args, Parser, Subcommand};
use dialoguer::{theme::ColorfulTheme, Select};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
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
    Task {
        #[command(subcommand)]
        command: TaskCommand,
    },
    SavedLink {
        #[command(subcommand)]
        command: SavedLinkCommand,
    },
    File {
        #[command(subcommand)]
        command: FileCommand,
    },
    Attachment {
        #[command(subcommand)]
        command: AttachmentCommand,
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
        #[arg(long)]
        text: String,
        #[arg(long)]
        if_revision: Option<String>,
    },
    Prepend {
        #[command(flatten)]
        selector: NoteSelector,
        #[arg(long)]
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
    Create {
        type_path: String,
    },
    Rename {
        from: String,
        to: String,
    },
    Delete {
        type_path: String,
        #[arg(long)]
        yes: bool,
    },
    Move {
        #[command(flatten)]
        selector: NoteSelector,
        #[arg(long)]
        to: String,
    },
    Icon {
        #[command(subcommand)]
        command: TypeIconCommand,
    },
    View {
        #[command(subcommand)]
        command: TypeViewCommand,
    },
}

#[derive(Subcommand)]
enum TypeIconCommand {
    Get { type_path: String },
    Set { type_path: String, icon: String },
    Unset { type_path: String },
}

#[derive(Subcommand)]
enum TypeViewCommand {
    Get {
        type_path: String,
    },
    Set {
        type_path: String,
        #[arg(long)]
        mode: Option<String>,
        #[arg(long)]
        group_by: Option<String>,
        #[arg(long)]
        date_property: Option<String>,
        #[arg(long)]
        sort: Option<String>,
        #[arg(long)]
        show_archived: Option<bool>,
    },
    Unset {
        type_path: String,
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
    #[arg(long, conflicts_with = "include_trash")]
    trash: bool,
    #[arg(long)]
    include_trash: bool,
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
    #[arg(long, conflicts_with = "include_trash")]
    trash: bool,
    #[arg(long)]
    include_trash: bool,
}

#[derive(Subcommand)]
enum TaskCommand {
    List {
        #[arg(long)]
        completed: bool,
        #[arg(long)]
        open: bool,
        #[arg(long)]
        today: bool,
    },
    Get {
        selector: String,
    },
    Create {
        title: String,
        #[arg(long)]
        category: Option<String>,
        #[arg(long, default_value = "none")]
        priority: String,
        #[arg(long)]
        date: Option<String>,
        #[arg(long)]
        due: Option<String>,
        #[arg(long = "link-note")]
        linked_notes: Vec<String>,
    },
    Update {
        selector: String,
        #[arg(long)]
        title: Option<String>,
        #[arg(long)]
        category: Option<String>,
        #[arg(long)]
        clear_category: bool,
        #[arg(long)]
        priority: Option<String>,
        #[arg(long)]
        date: Option<String>,
        #[arg(long)]
        due: Option<String>,
        #[arg(long)]
        clear_due: bool,
        #[arg(long = "link-note")]
        linked_notes: Vec<String>,
        #[arg(long)]
        clear_links: bool,
    },
    Complete {
        selector: String,
    },
    Reopen {
        selector: String,
    },
    Delete {
        selector: String,
        #[arg(long)]
        yes: bool,
    },
    Category {
        #[command(subcommand)]
        command: TaskCategoryCommand,
    },
}

#[derive(Subcommand)]
enum TaskCategoryCommand {
    List,
    Add {
        name: String,
    },
    Remove {
        name: String,
        #[arg(long)]
        yes: bool,
    },
}

#[derive(Subcommand)]
enum SavedLinkCommand {
    List,
    Get {
        selector: String,
    },
    Create {
        url: String,
        #[arg(long)]
        title: Option<String>,
    },
    Delete {
        selector: String,
        #[arg(long)]
        yes: bool,
    },
    MoveToType {
        selector: String,
        to: String,
    },
}

#[derive(Subcommand)]
enum FileCommand {
    Get {
        #[command(flatten)]
        selector: NoteSelector,
    },
    AttachCopy {
        #[command(flatten)]
        selector: NoteSelector,
        #[arg(long)]
        source: PathBuf,
    },
    Detach {
        #[command(flatten)]
        selector: NoteSelector,
        #[arg(long)]
        delete_managed: bool,
        #[arg(long)]
        yes: bool,
    },
}

#[derive(Subcommand)]
enum AttachmentCommand {
    List {
        #[command(flatten)]
        selector: NoteSelector,
    },
    AddCopy {
        #[command(flatten)]
        selector: NoteSelector,
        #[arg(long)]
        source: PathBuf,
    },
    Remove {
        #[command(flatten)]
        selector: NoteSelector,
        #[arg(long)]
        attachment_id: String,
        #[arg(long)]
        delete_managed: bool,
        #[arg(long)]
        yes: bool,
    },
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

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TaskRecord {
    id: String,
    title: String,
    #[serde(default)]
    completed: bool,
    #[serde(default)]
    category: Option<String>,
    #[serde(default = "default_task_priority")]
    priority: String,
    #[serde(default)]
    date: String,
    #[serde(default)]
    due_date: Option<String>,
    #[serde(default)]
    completed_at: Option<String>,
    #[serde(default)]
    linked_note_ids: Vec<String>,
    #[serde(default)]
    created_at: String,
}

fn default_task_priority() -> String {
    "none".into()
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TaskDocument {
    #[serde(default)]
    tasks: Vec<TaskRecord>,
    #[serde(default)]
    category_options: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SavedLinkRecord {
    id: String,
    path: String,
    title: String,
    url: String,
}

#[derive(Clone, Debug)]
struct SavedLinkNote {
    record: SavedLinkRecord,
    content: String,
    absolute_path: PathBuf,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct FileReference {
    id: String,
    name: String,
    kind: String,
    path: Option<String>,
    location_id: Option<String>,
    managed: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AttachmentRecord {
    id: String,
    name: String,
    kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    path: Option<String>,
    managed: bool,
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

const TASKS_PATH: &str = ".zerus/tasks.json";
const SAVED_LINKS_DIR: &str = ".zerus/links";
const SAVED_LINKS_INDEX_PATH: &str = ".zerus/links.json";
const TYPE_ICONS_PATH: &str = ".zerus/type-icons.json";
const TYPE_VIEWS_PATH: &str = ".zerus/views.json";
const MAX_TYPE_DEPTH: usize = 8;

fn read_json_or_default<T>(path: &Path) -> Result<T, CliError>
where
    T: serde::de::DeserializeOwned + Default,
{
    if !path.exists() {
        return Ok(T::default());
    }
    serde_json::from_slice(
        &fs::read(path)
            .map_err(|error| CliError::new("metadata_read_failed", error.to_string(), 2))?,
    )
    .map_err(|error| CliError::new("metadata_invalid", error.to_string(), 3))
}

fn write_json<T: Serialize + ?Sized>(path: &Path, value: &T) -> Result<(), CliError> {
    fs::create_dir_all(path.parent().unwrap())
        .map_err(|error| CliError::new("metadata_write_failed", error.to_string(), 5))?;
    let temporary = path.with_extension(format!("tmp-{}", Uuid::now_v7()));
    fs::write(&temporary, serde_json::to_vec_pretty(value).unwrap())
        .map_err(|error| CliError::new("metadata_write_failed", error.to_string(), 5))?;
    fs::rename(temporary, path)
        .map_err(|error| CliError::new("metadata_write_failed", error.to_string(), 5))
}

fn file_reference(note: &ScannedNote) -> Option<FileReference> {
    file_reference_from_properties(&note.properties)
}

fn file_reference_from_content(content: &str) -> Option<FileReference> {
    file_reference_from_properties(&zerus_core::note_properties(content))
}

fn file_reference_from_properties(
    properties: &BTreeMap<String, zerus_core::PropertyValue>,
) -> Option<FileReference> {
    let text = |key: &str| {
        properties
            .iter()
            .find(|(candidate, _)| candidate.eq_ignore_ascii_case(key))
            .and_then(|(_, value)| match value {
                zerus_core::PropertyValue::String(value) if !value.trim().is_empty() => {
                    Some(value.trim().to_string())
                }
                _ => None,
            })
    };
    let id = text("zerus-file-id")?;
    let name = text("zerus-file-name")?;
    let kind = text("zerus-file-kind")?;
    if !matches!(kind.as_str(), "vault" | "location" | "local") {
        return None;
    }
    Some(FileReference {
        id,
        name,
        kind,
        path: text("zerus-file-path"),
        location_id: text("zerus-file-location"),
        managed: properties
            .iter()
            .find(|(candidate, _)| candidate.eq_ignore_ascii_case("zerus-file-managed"))
            .is_some_and(|(_, value)| matches!(value, zerus_core::PropertyValue::Boolean(true))),
    })
}

fn attachment_records(note: &ScannedNote) -> Vec<AttachmentRecord> {
    note.properties
        .iter()
        .find(|(key, _)| key.eq_ignore_ascii_case("zerus-attachments"))
        .and_then(|(_, value)| match value {
            zerus_core::PropertyValue::List(values) => Some(values),
            _ => None,
        })
        .into_iter()
        .flatten()
        .filter_map(|value| serde_json::from_str(value).ok())
        .collect()
}

fn set_attachment_records(
    content: &str,
    attachments: &[AttachmentRecord],
) -> Result<String, CliError> {
    let raw = (!attachments.is_empty()).then(|| {
        format!(
            "\n{}",
            attachments
                .iter()
                .map(|attachment| { format!("  - {}", serde_json::to_string(attachment).unwrap()) })
                .collect::<Vec<_>>()
                .join("\n")
        )
    });
    zerus_core::set_reserved_property(content, "zerus-attachments", raw.as_deref())
        .map_err(|error| CliError::new("note_invalid", error.to_string(), 3))
}

fn normalize_type_path(input: &str) -> Result<String, CliError> {
    let normalized = input.trim().trim_matches('/').replace('\\', "/");
    zerus_core::validate_portable_relative_path(&normalized)
        .map_err(|error| CliError::new("invalid_type", error.to_string(), 3))?;
    let segments = normalized.split('/').count();
    if segments == 0 || segments > MAX_TYPE_DEPTH || normalized.starts_with('.') {
        return Err(CliError::new(
            "invalid_type",
            format!("type paths must contain 1 to {MAX_TYPE_DEPTH} visible segments"),
            3,
        ));
    }
    Ok(normalized)
}

fn validate_date(value: &str, label: &str) -> Result<(), CliError> {
    chrono::NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map(|_| ())
        .map_err(|_| CliError::new("invalid_date", format!("{label} must be YYYY-MM-DD"), 3))
}

fn validate_priority(value: &str) -> Result<(), CliError> {
    if matches!(value, "none" | "low" | "medium" | "high") {
        Ok(())
    } else {
        Err(CliError::new(
            "invalid_priority",
            "priority must be none, low, medium, or high",
            3,
        ))
    }
}

fn validate_type_icon(value: &str) -> Result<(), CliError> {
    let tabler = Regex::new(r"^tabler:[A-Za-z][A-Za-z0-9]*$").unwrap();
    if tabler.is_match(value) || !value.is_ascii() {
        Ok(())
    } else {
        Err(CliError::new(
            "invalid_icon",
            "icon must be a tabler:IconName value or emoji",
            3,
        ))
    }
}

fn task_document(root: &Path) -> Result<TaskDocument, CliError> {
    let path = root.join(TASKS_PATH);
    if !path.exists() {
        return Ok(TaskDocument::default());
    }
    let value: Value = serde_json::from_slice(
        &fs::read(&path)
            .map_err(|error| CliError::new("tasks_read_failed", error.to_string(), 2))?,
    )
    .map_err(|error| CliError::new("tasks_invalid", error.to_string(), 3))?;
    let mut document = if value.is_array() {
        let tasks = serde_json::from_value(value)
            .map_err(|error| CliError::new("tasks_invalid", error.to_string(), 3))?;
        TaskDocument {
            tasks,
            category_options: Vec::new(),
        }
    } else {
        serde_json::from_value(value)
            .map_err(|error| CliError::new("tasks_invalid", error.to_string(), 3))?
    };
    for task in &mut document.tasks {
        if task.created_at.is_empty() {
            task.created_at = "1970-01-01T00:00:00Z".into();
        }
        if task.date.is_empty() {
            task.date = task
                .created_at
                .get(..10)
                .unwrap_or("1970-01-01")
                .to_string();
        }
        if !matches!(task.priority.as_str(), "none" | "low" | "medium" | "high") {
            task.priority = "none".into();
        }
        if let Some(category) = &task.category {
            if !document
                .category_options
                .iter()
                .any(|value| value.eq_ignore_ascii_case(category))
            {
                document.category_options.push(category.clone());
            }
        }
    }
    Ok(document)
}

fn save_tasks(root: &Path, document: &TaskDocument) -> Result<(), CliError> {
    write_json(&root.join(TASKS_PATH), document)
}

fn choose_task_index(tasks: &[TaskRecord], selector: &str) -> Result<usize, CliError> {
    let lowered = selector.to_lowercase();
    let matches = tasks
        .iter()
        .enumerate()
        .filter(|(_, task)| {
            task.id.to_lowercase().starts_with(&lowered)
                || task.title.eq_ignore_ascii_case(selector)
        })
        .map(|(index, _)| index)
        .collect::<Vec<_>>();
    match matches.as_slice() {
        [index] => Ok(*index),
        [] => Err(CliError::new(
            "task_not_found",
            "No task matches that selector",
            3,
        )),
        _ => Err(CliError::new(
            "ambiguous_selector",
            "Multiple tasks match that selector; use an ID prefix",
            4,
        )),
    }
}

fn resolve_note_ids(
    cli: &Cli,
    notes: &[ScannedNote],
    selectors: &[String],
) -> Result<Vec<String>, CliError> {
    let mut ids = Vec::new();
    for value in selectors {
        let selector = NoteSelector {
            target: Some(value.clone()),
            id: None,
            path: None,
            title: None,
        };
        let note = choose_note(cli, notes, &selector)?;
        if is_trashed_path(&note.path) {
            return Err(CliError::new(
                "note_trashed",
                "tasks cannot link to trashed notes",
                3,
            ));
        }
        let id = note.id.ok_or_else(|| {
            CliError::new("note_missing_id", "linked notes must have a zerus-id", 3)
        })?;
        let value = id.to_string();
        if !ids.contains(&value) {
            ids.push(value);
        }
    }
    Ok(ids)
}

fn saved_link_paths(root: &Path) -> Result<Vec<String>, CliError> {
    read_json_or_default(&root.join(SAVED_LINKS_INDEX_PATH))
}

fn load_saved_links(root: &Path) -> Result<Vec<SavedLinkNote>, CliError> {
    let mut links = Vec::new();
    for path in saved_link_paths(root)? {
        if !path.starts_with(&format!("{SAVED_LINKS_DIR}/")) || !safe_vault_relative(&path) {
            continue;
        }
        let absolute_path = root.join(&path);
        let Ok(content) = fs::read_to_string(&absolute_path) else {
            continue;
        };
        let properties = zerus_core::note_properties(&content);
        let text = |key: &str| {
            properties
                .iter()
                .find(|(candidate, _)| candidate.eq_ignore_ascii_case(key))
                .and_then(|(_, value)| match value {
                    zerus_core::PropertyValue::String(value) => Some(value.clone()),
                    _ => None,
                })
        };
        let Some(id) = text("zerus-link-id") else {
            continue;
        };
        let Some(url) = text("zerus-link-url") else {
            continue;
        };
        let fallback = Path::new(&path)
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or("Link")
            .to_string();
        links.push(SavedLinkNote {
            record: SavedLinkRecord {
                id,
                path,
                title: zerus_core::note_title(&content, &fallback),
                url,
            },
            content,
            absolute_path,
        });
    }
    Ok(links)
}

fn save_saved_link_paths(root: &Path, paths: &[String]) -> Result<(), CliError> {
    write_json(&root.join(SAVED_LINKS_INDEX_PATH), paths)
}

fn choose_saved_link<'a>(
    links: &'a [SavedLinkNote],
    selector: &str,
) -> Result<&'a SavedLinkNote, CliError> {
    let lowered = selector.to_lowercase();
    let matches = links
        .iter()
        .filter(|link| {
            link.record.id.to_lowercase().starts_with(&lowered)
                || link.record.title.eq_ignore_ascii_case(selector)
                || link.record.url.eq_ignore_ascii_case(selector)
        })
        .collect::<Vec<_>>();
    match matches.as_slice() {
        [link] => Ok(*link),
        [] => Err(CliError::new(
            "link_not_found",
            "No saved link matches that selector",
            3,
        )),
        _ => Err(CliError::new(
            "ambiguous_selector",
            "Multiple saved links match that selector; use an ID prefix",
            4,
        )),
    }
}

fn normalize_http_url(value: &str) -> Result<String, CliError> {
    let trimmed = value.trim();
    if (trimmed.starts_with("https://") || trimmed.starts_with("http://"))
        && trimmed
            .split_once("://")
            .is_some_and(|(_, rest)| !rest.is_empty())
    {
        Ok(trimmed.to_string())
    } else {
        Err(CliError::new(
            "invalid_url",
            "saved links require an explicit http:// or https:// URL",
            3,
        ))
    }
}

fn collect_type_directories(root: &Path) -> Result<Vec<String>, CliError> {
    fn visit(
        root: &Path,
        relative: &Path,
        depth: usize,
        output: &mut BTreeSet<String>,
    ) -> io::Result<()> {
        if depth >= MAX_TYPE_DEPTH {
            return Ok(());
        }
        for entry in fs::read_dir(root.join(relative))? {
            let entry = entry?;
            if !entry.file_type()?.is_dir() || entry.file_type()?.is_symlink() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with('.') || (relative.as_os_str().is_empty() && name == "assets") {
                continue;
            }
            let child = relative.join(&name);
            let key = child.to_string_lossy().replace('\\', "/");
            output.insert(key);
            visit(root, &child, depth + 1, output)?;
        }
        Ok(())
    }
    let mut values = BTreeSet::new();
    visit(root, Path::new(""), 0, &mut values)
        .map_err(|error| CliError::new("vault_unavailable", error.to_string(), 2))?;
    Ok(values.into_iter().collect())
}

fn remove_empty_type_tree(path: &Path) -> Result<(), CliError> {
    if !path.exists() {
        return Ok(());
    }
    for entry in fs::read_dir(path)
        .map_err(|error| CliError::new("type_delete_failed", error.to_string(), 5))?
    {
        let entry =
            entry.map_err(|error| CliError::new("type_delete_failed", error.to_string(), 5))?;
        if entry
            .file_type()
            .is_ok_and(|kind| kind.is_dir() && !kind.is_symlink())
        {
            remove_empty_type_tree(&entry.path())?;
        } else {
            return Err(CliError::new(
                "type_not_empty",
                format!(
                    "{} remains after notes were trashed; refusing to delete an unrelated file",
                    entry.path().display()
                ),
                5,
            ));
        }
    }
    fs::remove_dir(path).map_err(|error| CliError::new("type_delete_failed", error.to_string(), 5))
}

fn collect_regular_files(path: &Path, output: &mut Vec<PathBuf>) -> Result<(), CliError> {
    if !path.exists() {
        return Ok(());
    }
    for entry in fs::read_dir(path)
        .map_err(|error| CliError::new("type_read_failed", error.to_string(), 2))?
    {
        let entry =
            entry.map_err(|error| CliError::new("type_read_failed", error.to_string(), 2))?;
        let kind = entry
            .file_type()
            .map_err(|error| CliError::new("type_read_failed", error.to_string(), 2))?;
        if kind.is_symlink() {
            return Err(CliError::new(
                "type_unsafe",
                format!(
                    "refusing to delete a type containing symlink {}",
                    entry.path().display()
                ),
                5,
            ));
        }
        if kind.is_dir() {
            collect_regular_files(&entry.path(), output)?;
        } else {
            output.push(entry.path());
        }
    }
    Ok(())
}

fn remap_type_key(key: &str, from: &str, to: &str) -> Option<String> {
    if key == from {
        Some(to.to_string())
    } else {
        key.strip_prefix(&format!("{from}/"))
            .map(|suffix| format!("{to}/{suffix}"))
    }
}

fn update_type_keyed_document(
    root: &Path,
    relative: &str,
    from: &str,
    to: &str,
) -> Result<(), CliError> {
    let path = root.join(relative);
    let mut document: BTreeMap<String, Value> = read_json_or_default(&path)?;
    let mut next = BTreeMap::new();
    for (key, value) in document.iter_mut() {
        if relative == ".zerus/properties.json" {
            if let Some(definitions) = value.as_array_mut() {
                for definition in definitions {
                    if let Some(relation) = definition
                        .get_mut("relationTypeKey")
                        .and_then(|value| value.as_str())
                        .and_then(|key| remap_type_key(key, from, to))
                    {
                        definition["relationTypeKey"] = json!(relation);
                    }
                }
            }
        }
        next.insert(
            remap_type_key(key, from, to).unwrap_or_else(|| key.clone()),
            value.clone(),
        );
    }
    if next != document {
        write_json(&path, &next)?;
    }
    Ok(())
}

fn relation_titles(note: &ScannedNote, schemas: &serde_json::Map<String, Value>) -> Vec<String> {
    let definitions = effective_schema_definitions(schemas, &note_type_key(&note.path));
    let relation_names = definitions
        .iter()
        .filter(|definition| definition.get("type").and_then(Value::as_str) == Some("relation"))
        .filter_map(|definition| definition.get("name").and_then(Value::as_str))
        .collect::<Vec<_>>();
    relation_names
        .into_iter()
        .flat_map(|name| {
            note.properties
                .iter()
                .find(|(candidate, _)| candidate.eq_ignore_ascii_case(name))
                .map(|(_, value)| match value {
                    zerus_core::PropertyValue::List(values) => values.clone(),
                    zerus_core::PropertyValue::String(value) => vec![value.clone()],
                    _ => Vec::new(),
                })
                .unwrap_or_default()
        })
        .filter(|value| !value.trim().is_empty())
        .collect()
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
    root.join(".zerus/history/cli")
}

fn legacy_history_dir(root: &Path) -> PathBuf {
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
    let mut entries = Vec::new();
    for directory in [history_dir(root), legacy_history_dir(root)] {
        if !directory.exists() {
            continue;
        }
        for item in fs::read_dir(directory)
            .map_err(|e| CliError::new("history_read_failed", e.to_string(), 2))?
        {
            let path = item
                .map_err(|e| CliError::new("history_read_failed", e.to_string(), 2))?
                .path();
            if path.is_file() && path.extension().and_then(|v| v.to_str()) == Some("json") {
                if let Ok(value) = serde_json::from_slice(&fs::read(path).unwrap_or_default()) {
                    entries.push(value);
                }
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

fn safe_vault_relative(value: &str) -> bool {
    !value.is_empty()
        && !Path::new(value).is_absolute()
        && Path::new(value).components().all(|component| {
            matches!(
                component,
                std::path::Component::Normal(_) | std::path::Component::CurDir
            )
        })
}

fn unique_document_path(root: &Path, directory: &str, name: &str, current: &str) -> String {
    let path = Path::new(name);
    let stem = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("Document");
    let extension = path
        .extension()
        .and_then(|value| value.to_str())
        .map(|value| format!(".{value}"))
        .unwrap_or_default();
    for index in 0.. {
        let file = format!(
            "{stem}{}{extension}",
            if index == 0 {
                String::new()
            } else {
                format!(" {}", index + 1)
            }
        );
        let candidate = if directory.is_empty() {
            file
        } else {
            format!("{directory}/{file}")
        };
        if candidate == current || !root.join(&candidate).exists() {
            return candidate;
        }
    }
    unreachable!()
}

fn move_note_with_managed_file(
    root: &Path,
    note: &ScannedNote,
    relative: &str,
) -> Result<String, CliError> {
    let destination = valid_note_destination(root, relative)?;
    fs::create_dir_all(destination.parent().unwrap())
        .map_err(|error| CliError::new("write_failed", error.to_string(), 5))?;
    let managed = file_reference(note).filter(|reference| {
        reference.managed
            && reference.kind == "vault"
            && reference.path.as_deref().is_some_and(safe_vault_relative)
    });
    let document_move = managed.as_ref().and_then(|reference| {
        let source_relative = reference.path.as_ref()?;
        let source = root.join(source_relative);
        if !source.is_file() {
            return None;
        }
        let target_dir = Path::new(relative)
            .parent()
            .and_then(|path| path.to_str())
            .unwrap_or("")
            .replace('\\', "/");
        let target_relative =
            unique_document_path(root, &target_dir, &reference.name, source_relative);
        Some((
            source_relative.clone(),
            source,
            target_relative.clone(),
            root.join(target_relative),
        ))
    });

    fs::rename(&note.absolute_path, &destination)
        .map_err(|error| CliError::new("write_failed", error.to_string(), 5))?;
    if let Some((source_relative, source, target_relative, target)) = document_move {
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent).map_err(|error| {
                let _ = fs::rename(&destination, &note.absolute_path);
                CliError::new("write_failed", error.to_string(), 5)
            })?;
        }
        if let Err(error) = fs::rename(&source, &target) {
            let _ = fs::rename(&destination, &note.absolute_path);
            return Err(CliError::new("write_failed", error.to_string(), 5));
        }
        let next = zerus_core::set_reserved_property(
            &note.content,
            "zerus-file-path",
            Some(&target_relative),
        )
        .map_err(|error| CliError::new("note_invalid", error.to_string(), 3))?;
        if let Err(error) = atomic_write(&destination, &next, Some(&note.revision)) {
            let _ = fs::rename(&target, root.join(source_relative));
            let _ = fs::rename(&destination, &note.absolute_path);
            return Err(CliError::new("write_failed", error.to_string(), 5));
        }
        return Ok(next);
    }
    Ok(note.content.clone())
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

fn normalize_schema_type_path(input: &str) -> Result<String, CliError> {
    normalize_type_path(input).map_err(|error| CliError {
        code: "schema_invalid",
        ..error
    })
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
        .take(MAX_TYPE_DEPTH)
        .collect::<Vec<_>>()
        .join("/")
}

fn type_matches(path: &str, type_path: &str) -> bool {
    let normalized = type_path.trim_matches('/');
    path.starts_with(&format!("{normalized}/"))
}

fn is_trashed_path(path: &str) -> bool {
    path.starts_with(".trash/")
}

fn filtered_list<'a>(notes: &'a [ScannedNote], args: &ListArgs) -> Vec<&'a ScannedNote> {
    notes
        .iter()
        .filter(|note| {
            let trash_matches = if args.trash {
                is_trashed_path(&note.path)
            } else if args.include_trash {
                true
            } else {
                !is_trashed_path(&note.path)
            };
            trash_matches
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
            let trash_matches = if args.trash {
                is_trashed_path(&note.path)
            } else if args.include_trash {
                true
            } else {
                !is_trashed_path(&note.path)
            };
            trash_matches
                && args
                    .query
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
                    let next_content = move_note_with_managed_file(&root, note, &relative)?;
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
                        Some(&next_content),
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
                if current.exists() {
                    if let Some(expected) = entry.content_after.as_deref() {
                        let actual = fs::read_to_string(&current)
                            .map_err(|error| CliError::new("undo_failed", error.to_string(), 5))?;
                        if actual != expected {
                            return Err(CliError::new(
                                "undo_conflict",
                                "the note changed after this transaction; refusing to overwrite newer edits",
                                5,
                            ));
                        }
                    }
                }
                match (&entry.path_before, &entry.content_before) {
                    (Some(before_path), Some(before)) => {
                        let destination = root.join(before_path);
                        let before_file = file_reference_from_content(before)
                            .filter(|reference| reference.managed && reference.kind == "vault")
                            .and_then(|reference| reference.path);
                        let after_file = entry
                            .content_after
                            .as_deref()
                            .and_then(file_reference_from_content)
                            .filter(|reference| reference.managed && reference.kind == "vault")
                            .and_then(|reference| reference.path);
                        let file_move = match (after_file, before_file) {
                            (Some(from), Some(to)) if from != to => {
                                let source = root.join(&from);
                                let target = root.join(&to);
                                if source.exists() {
                                    if target.exists() {
                                        return Err(CliError::new(
                                            "path_exists",
                                            format!("{} already exists", target.display()),
                                            3,
                                        ));
                                    }
                                    Some((source, target))
                                } else {
                                    None
                                }
                            }
                            _ => None,
                        };
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
                            if let Some((source, target)) = &file_move {
                                fs::create_dir_all(target.parent().unwrap()).map_err(|error| {
                                    CliError::new("undo_failed", error.to_string(), 5)
                                })?;
                                fs::rename(source, target).map_err(|error| {
                                    CliError::new("undo_failed", error.to_string(), 5)
                                })?;
                            }
                            if let Err(error) = fs::rename(&current, &destination) {
                                if let Some((source, target)) = &file_move {
                                    let _ = fs::rename(target, source);
                                }
                                return Err(CliError::new("undo_failed", error.to_string(), 5));
                            }
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
                    let values = collect_type_directories(&root)?;
                    output_collection(cli, &values, || values.join("\n"))
                }
                TypeCommand::Create { type_path } => {
                    let key = normalize_type_path(type_path)?;
                    let destination = root.join(&key);
                    let created = !destination.exists();
                    fs::create_dir_all(&destination).map_err(|error| {
                        CliError::new("type_create_failed", error.to_string(), 5)
                    })?;
                    success(cli, json!({"type": key, "created": created}), || {
                        if created {
                            format!("Created {key}")
                        } else {
                            format!("{key} already exists")
                        }
                    })
                }
                TypeCommand::Rename { from, to } => {
                    let from = normalize_type_path(from)?;
                    let to = normalize_type_path(to)?;
                    let source = root.join(&from);
                    let destination = root.join(&to);
                    if !source.is_dir() {
                        return Err(CliError::new(
                            "type_not_found",
                            "the source type does not exist",
                            3,
                        ));
                    }
                    if destination.exists() {
                        return Err(CliError::new(
                            "path_exists",
                            "the destination type already exists",
                            3,
                        ));
                    }
                    fs::create_dir_all(destination.parent().unwrap()).map_err(|error| {
                        CliError::new("type_rename_failed", error.to_string(), 5)
                    })?;
                    fs::rename(&source, &destination).map_err(|error| {
                        CliError::new("type_rename_failed", error.to_string(), 5)
                    })?;
                    for relative in [".zerus/properties.json", TYPE_ICONS_PATH, TYPE_VIEWS_PATH] {
                        update_type_keyed_document(&root, relative, &from, &to)?;
                    }
                    let renamed_notes = scan_vault(&root).map_err(|error| {
                        CliError::new("vault_unavailable", error.to_string(), 2)
                    })?;
                    let old_prefix = format!("{from}/");
                    let new_prefix = format!("{to}/");
                    let mut metadata_changed = 0;
                    for note in renamed_notes
                        .iter()
                        .filter(|note| note.path.starts_with(&new_prefix))
                    {
                        let Some(reference) = file_reference(note) else {
                            continue;
                        };
                        let Some(path) = reference.path else { continue };
                        let Some(suffix) = path.strip_prefix(&old_prefix) else {
                            continue;
                        };
                        let next_path = format!("{new_prefix}{suffix}");
                        let next = zerus_core::set_reserved_property(
                            &note.content,
                            "zerus-file-path",
                            Some(&next_path),
                        )
                        .map_err(|error| CliError::new("note_invalid", error.to_string(), 3))?;
                        atomic_write(&note.absolute_path, &next, Some(&note.revision)).map_err(
                            |error| CliError::new("type_rename_failed", error.to_string(), 5),
                        )?;
                        metadata_changed += 1;
                    }
                    success(
                        cli,
                        json!({"from": from, "to": to, "managedFileReferencesUpdated": metadata_changed}),
                        || format!("Renamed {from} to {to}"),
                    )
                }
                TypeCommand::Delete { type_path, yes } => {
                    let key = normalize_type_path(type_path)?;
                    let affected = notes
                        .iter()
                        .filter(|note| {
                            !is_trashed_path(&note.path) && type_matches(&note.path, &key)
                        })
                        .collect::<Vec<_>>();
                    let mut expected_files = affected
                        .iter()
                        .map(|note| note.absolute_path.clone())
                        .collect::<BTreeSet<_>>();
                    for note in &affected {
                        if let Some(path) = file_reference(note)
                            .filter(|reference| reference.managed && reference.kind == "vault")
                            .and_then(|reference| reference.path)
                            .filter(|path| safe_vault_relative(path))
                        {
                            expected_files.insert(root.join(path));
                        }
                    }
                    let mut actual_files = Vec::new();
                    collect_regular_files(&root.join(&key), &mut actual_files)?;
                    let unrelated = actual_files
                        .into_iter()
                        .filter(|path| !expected_files.contains(path))
                        .map(|path| {
                            path.strip_prefix(&root)
                                .unwrap_or(&path)
                                .to_string_lossy()
                                .replace('\\', "/")
                        })
                        .collect::<Vec<_>>();
                    if !*yes {
                        return success(
                            cli,
                            json!({"approvalRequired": unrelated.is_empty(), "blocked": !unrelated.is_empty(), "type": key, "notesToTrash": affected.iter().map(|note| &note.path).collect::<Vec<_>>(), "unrelatedFiles": unrelated }),
                            || {
                                if unrelated.is_empty() {
                                    format!(
                                        "Preview: {} notes will move to Trash. Re-run with --yes.",
                                        affected.len()
                                    )
                                } else {
                                    format!("Blocked: {} unrelated files must be moved out of the type first.", unrelated.len())
                                }
                            },
                        );
                    }
                    if !unrelated.is_empty() {
                        return Err(CliError::new(
                            "type_not_empty",
                            "the type contains unrelated files; move them before deleting the type",
                            5,
                        )
                        .details(json!(unrelated)));
                    }
                    for note in affected {
                        let target = format!(".trash/{}", note.path);
                        let next = move_note_with_managed_file(&root, note, &target)?;
                        save_history(
                            &root,
                            "type.delete-trash",
                            Some(&note.path),
                            Some(&target),
                            Some(&note.content),
                            Some(&next),
                        )?;
                    }
                    let directory = root.join(&key);
                    remove_empty_type_tree(&directory)?;
                    for relative in [".zerus/properties.json", TYPE_ICONS_PATH, TYPE_VIEWS_PATH] {
                        let path = root.join(relative);
                        let mut document: BTreeMap<String, Value> = read_json_or_default(&path)?;
                        document.retain(|candidate, _| {
                            candidate != &key && !candidate.starts_with(&format!("{key}/"))
                        });
                        if path.exists() || !document.is_empty() {
                            write_json(&path, &document)?;
                        }
                    }
                    success(cli, json!({"type": key, "deleted": true}), || {
                        format!("Deleted {key}; notes moved to Trash")
                    })
                }
                TypeCommand::Move { selector, to } => {
                    let note = choose_note(cli, &notes, selector)?;
                    if is_trashed_path(&note.path) {
                        return Err(CliError::new(
                            "note_trashed",
                            "restore the note before moving its type",
                            3,
                        ));
                    }
                    let to = normalize_type_path(to)?;
                    let name = Path::new(&note.path)
                        .file_name()
                        .and_then(|v| v.to_str())
                        .unwrap_or("Note.md");
                    let relative = format!("{to}/{name}");
                    let next_content = move_note_with_managed_file(&root, note, &relative)?;
                    let entry = save_history(
                        &root,
                        "type.move",
                        Some(&note.path),
                        Some(&relative),
                        Some(&note.content),
                        Some(&next_content),
                    )?;
                    success(
                        cli,
                        json!({"path": relative, "transactionId": entry.transaction_id}),
                        || format!("Moved to {relative}"),
                    )
                }
                TypeCommand::Icon { command } => {
                    let path = root.join(TYPE_ICONS_PATH);
                    let mut icons: BTreeMap<String, String> = read_json_or_default(&path)?;
                    match command {
                        TypeIconCommand::Get { type_path } => {
                            let key = normalize_type_path(type_path)?;
                            success(cli, json!({"type": key, "icon": icons.get(&key)}), || {
                                icons.get(&key).cloned().unwrap_or_else(|| "default".into())
                            })
                        }
                        TypeIconCommand::Set { type_path, icon } => {
                            let key = normalize_type_path(type_path)?;
                            let icon = icon.trim();
                            if icon.is_empty() {
                                return Err(CliError::new(
                                    "invalid_icon",
                                    "icon cannot be empty",
                                    3,
                                ));
                            }
                            validate_type_icon(icon)?;
                            icons.insert(key.clone(), icon.to_string());
                            write_json(&path, &icons)?;
                            success(cli, json!({"type": key, "icon": icon}), || {
                                format!("Updated icon for {key}")
                            })
                        }
                        TypeIconCommand::Unset { type_path } => {
                            let key = normalize_type_path(type_path)?;
                            icons.remove(&key);
                            write_json(&path, &icons)?;
                            success(cli, json!({"type": key, "icon": null}), || {
                                format!("Reset icon for {key}")
                            })
                        }
                    }
                }
                TypeCommand::View { command } => {
                    let path = root.join(TYPE_VIEWS_PATH);
                    let mut views: BTreeMap<String, Value> = read_json_or_default(&path)?;
                    match command {
                        TypeViewCommand::Get { type_path } => {
                            let key = normalize_type_path(type_path)?;
                            let value = views.get(&key).cloned().unwrap_or_else(|| json!({
                                "mode": "list", "groupBy": null, "boardColumnOrder": {}, "dateProperty": null,
                                "filters": {"sort": "updated-desc", "date": null, "showArchived": false, "typeKeys": [], "fileExtensions": [], "properties": []}
                            }));
                            success(cli, json!({"type": key, "view": value}), || {
                                serde_json::to_string_pretty(&value).unwrap()
                            })
                        }
                        TypeViewCommand::Set {
                            type_path,
                            mode,
                            group_by,
                            date_property,
                            sort,
                            show_archived,
                        } => {
                            let key = normalize_type_path(type_path)?;
                            if let Some(mode) = mode.as_deref() {
                                if !matches!(
                                    mode,
                                    "gallery" | "board" | "table" | "calendar" | "list"
                                ) {
                                    return Err(CliError::new(
                                        "invalid_view",
                                        "mode must be gallery, board, table, calendar, or list",
                                        3,
                                    ));
                                }
                            }
                            if let Some(sort) = sort.as_deref() {
                                if !matches!(
                                    sort,
                                    "updated-desc"
                                        | "updated-asc"
                                        | "created-desc"
                                        | "created-asc"
                                        | "title-asc"
                                        | "title-desc"
                                ) {
                                    return Err(CliError::new(
                                        "invalid_view",
                                        "unsupported sort",
                                        3,
                                    ));
                                }
                            }
                            let mut value = views.get(&key).cloned().unwrap_or_else(|| json!({
                                "mode": "list", "groupBy": null, "boardColumnOrder": {}, "dateProperty": null,
                                "filters": {"sort": "updated-desc", "date": null, "showArchived": false, "typeKeys": [], "fileExtensions": [], "properties": []}
                            }));
                            if let Some(mode) = mode {
                                value["mode"] = json!(mode);
                            }
                            if let Some(group) = group_by {
                                value["groupBy"] = json!(group);
                            }
                            if let Some(property) = date_property {
                                value["dateProperty"] = json!(property);
                            }
                            if let Some(sort) = sort {
                                value["filters"]["sort"] = json!(sort);
                            }
                            if let Some(show) = show_archived {
                                value["filters"]["showArchived"] = json!(show);
                            }
                            views.insert(key.clone(), value.clone());
                            write_json(&path, &views)?;
                            success(cli, json!({"type": key, "view": value}), || {
                                format!("Updated view for {key}")
                            })
                        }
                        TypeViewCommand::Unset { type_path } => {
                            let key = normalize_type_path(type_path)?;
                            views.remove(&key);
                            write_json(&path, &views)?;
                            success(cli, json!({"type": key, "view": null}), || {
                                format!("Reset view for {key}")
                            })
                        }
                    }
                }
            }
        }
        Command::Links { selector } => {
            let (notes, _, root) = load_notes(cli)?;
            let note = choose_note(cli, &notes, selector)?;
            let wiki = Regex::new(r"\[\[([^\]|#]+)").unwrap();
            let body_outgoing: Vec<_> = wiki
                .captures_iter(&note.content)
                .map(|capture| capture[1].trim().to_string())
                .collect();
            let schemas = load_schemas(&root)?;
            let relation_outgoing = relation_titles(note, &schemas);
            let outgoing = body_outgoing
                .iter()
                .chain(relation_outgoing.iter())
                .cloned()
                .collect::<BTreeSet<_>>()
                .into_iter()
                .collect::<Vec<_>>();
            let needles = [
                note.title.clone(),
                note.path.clone(),
                note.id.map(|id| id.to_string()).unwrap_or_default(),
            ];
            let backlinks: Vec<_> = notes
                .iter()
                .filter(|candidate| {
                    candidate.path != note.path && !is_trashed_path(&candidate.path)
                })
                .filter_map(|candidate| {
                    let body = needles
                        .iter()
                        .filter(|value| !value.is_empty())
                        .any(|value| candidate.content.contains(&format!("[[{value}")));
                    let relation = relation_titles(candidate, &schemas)
                        .iter()
                        .any(|title| title.eq_ignore_ascii_case(&note.title));
                    (body || relation).then(|| {
                        json!({
                            "path": candidate.path,
                            "title": candidate.title,
                            "noteId": candidate.id,
                            "viaBody": body,
                            "viaRelation": relation
                        })
                    })
                })
                .collect();
            success(
                cli,
                json!({"note": note.path, "outgoing": outgoing, "bodyOutgoing": body_outgoing, "relationOutgoing": relation_outgoing, "backlinks": backlinks}),
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
                    !is_trashed_path(&note.path)
                        && (*include_archived || !note.archived)
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
                        && !is_trashed_path(&note.path)
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
        Command::Task { command } => {
            let (root, _) = resolve_root(cli)?;
            let notes = scan_vault(&root)
                .map_err(|error| CliError::new("vault_unavailable", error.to_string(), 2))?;
            let mut document = task_document(&root)?;
            match command {
                TaskCommand::List {
                    completed,
                    open,
                    today,
                } => {
                    let today_value = chrono::Local::now()
                        .date_naive()
                        .format("%Y-%m-%d")
                        .to_string();
                    let values = document
                        .tasks
                        .iter()
                        .filter(|task| {
                            (!*completed || task.completed)
                                && (!*open || !task.completed)
                                && (!*today || task.date == today_value)
                        })
                        .collect::<Vec<_>>();
                    output_collection(cli, &values, || {
                        values
                            .iter()
                            .map(|task| {
                                format!(
                                    "{}\t{}\t{}",
                                    if task.completed { "done" } else { "open" },
                                    task.title,
                                    &task.id[..task.id.len().min(8)]
                                )
                            })
                            .collect::<Vec<_>>()
                            .join("\n")
                    })
                }
                TaskCommand::Get { selector } => {
                    let index = choose_task_index(&document.tasks, selector)?;
                    let task = document.tasks[index].clone();
                    success(cli, serde_json::to_value(&task).unwrap(), || {
                        serde_json::to_string_pretty(&task).unwrap()
                    })
                }
                TaskCommand::Create {
                    title,
                    category,
                    priority,
                    date,
                    due,
                    linked_notes,
                } => {
                    let title = title.trim();
                    if title.is_empty() {
                        return Err(CliError::new("invalid_task", "title cannot be empty", 3));
                    }
                    validate_priority(priority)?;
                    if let Some(date) = date {
                        validate_date(date, "date")?;
                    }
                    if let Some(due) = due {
                        validate_date(due, "due date")?;
                    }
                    let now = chrono::Utc::now();
                    let task = TaskRecord {
                        id: Uuid::now_v7().to_string(),
                        title: title.into(),
                        completed: false,
                        category: category
                            .as_ref()
                            .map(|value| value.trim().to_string())
                            .filter(|value| !value.is_empty()),
                        priority: priority.clone(),
                        date: date.clone().unwrap_or_else(|| {
                            chrono::Local::now()
                                .date_naive()
                                .format("%Y-%m-%d")
                                .to_string()
                        }),
                        due_date: due.clone(),
                        completed_at: None,
                        linked_note_ids: resolve_note_ids(cli, &notes, linked_notes)?,
                        created_at: now.to_rfc3339(),
                    };
                    if let Some(category) = &task.category {
                        if !document
                            .category_options
                            .iter()
                            .any(|value| value.eq_ignore_ascii_case(category))
                        {
                            document.category_options.push(category.clone());
                        }
                    }
                    document.tasks.push(task.clone());
                    save_tasks(&root, &document)?;
                    success(cli, serde_json::to_value(&task).unwrap(), || {
                        format!("Created task {}", task.title)
                    })
                }
                TaskCommand::Update {
                    selector,
                    title,
                    category,
                    clear_category,
                    priority,
                    date,
                    due,
                    clear_due,
                    linked_notes,
                    clear_links,
                } => {
                    let index = choose_task_index(&document.tasks, selector)?;
                    if let Some(priority) = priority {
                        validate_priority(priority)?;
                    }
                    if let Some(date) = date {
                        validate_date(date, "date")?;
                    }
                    if let Some(due) = due {
                        validate_date(due, "due date")?;
                    }
                    let resolved_links = if linked_notes.is_empty() {
                        None
                    } else {
                        Some(resolve_note_ids(cli, &notes, linked_notes)?)
                    };
                    let task = &mut document.tasks[index];
                    if let Some(title) = title {
                        if title.trim().is_empty() {
                            return Err(CliError::new("invalid_task", "title cannot be empty", 3));
                        }
                        task.title = title.trim().into();
                    }
                    if *clear_category {
                        task.category = None;
                    } else if let Some(category) = category {
                        task.category =
                            (!category.trim().is_empty()).then(|| category.trim().to_string());
                    }
                    if let Some(priority) = priority {
                        task.priority = priority.clone();
                    }
                    if let Some(date) = date {
                        task.date = date.clone();
                    }
                    if *clear_due {
                        task.due_date = None;
                    } else if let Some(due) = due {
                        task.due_date = Some(due.clone());
                    }
                    if *clear_links {
                        task.linked_note_ids.clear();
                    } else if let Some(links) = resolved_links {
                        task.linked_note_ids = links;
                    }
                    let updated = task.clone();
                    if let Some(category) = &updated.category {
                        if !document
                            .category_options
                            .iter()
                            .any(|value| value.eq_ignore_ascii_case(category))
                        {
                            document.category_options.push(category.clone());
                        }
                    }
                    save_tasks(&root, &document)?;
                    success(cli, serde_json::to_value(&updated).unwrap(), || {
                        format!("Updated task {}", updated.title)
                    })
                }
                TaskCommand::Complete { selector } | TaskCommand::Reopen { selector } => {
                    let complete = matches!(command, TaskCommand::Complete { .. });
                    let index = choose_task_index(&document.tasks, selector)?;
                    document.tasks[index].completed = complete;
                    document.tasks[index].completed_at =
                        complete.then(|| chrono::Utc::now().to_rfc3339());
                    let updated = document.tasks[index].clone();
                    save_tasks(&root, &document)?;
                    success(cli, serde_json::to_value(&updated).unwrap(), || {
                        format!(
                            "{} {}",
                            if complete { "Completed" } else { "Reopened" },
                            updated.title
                        )
                    })
                }
                TaskCommand::Delete { selector, yes } => {
                    let index = choose_task_index(&document.tasks, selector)?;
                    let task = document.tasks[index].clone();
                    if !yes {
                        return success(
                            cli,
                            json!({"approvalRequired": true, "task": task}),
                            || {
                                "Preview: one task will be permanently deleted. Re-run with --yes."
                                    .into()
                            },
                        );
                    }
                    document.tasks.remove(index);
                    save_tasks(&root, &document)?;
                    success(cli, json!({"deletedTaskId": task.id}), || {
                        format!("Deleted task {}", task.title)
                    })
                }
                TaskCommand::Category { command } => match command {
                    TaskCategoryCommand::List => {
                        output_collection(cli, &document.category_options, || {
                            document.category_options.join("\n")
                        })
                    }
                    TaskCategoryCommand::Add { name } => {
                        let name = name.trim();
                        if name.is_empty() {
                            return Err(CliError::new(
                                "invalid_category",
                                "category cannot be empty",
                                3,
                            ));
                        }
                        if !document
                            .category_options
                            .iter()
                            .any(|value| value.eq_ignore_ascii_case(name))
                        {
                            document.category_options.push(name.into());
                        }
                        save_tasks(&root, &document)?;
                        success(cli, json!({"category": name}), || {
                            format!("Added category {name}")
                        })
                    }
                    TaskCategoryCommand::Remove { name, yes } => {
                        let affected = document
                            .tasks
                            .iter()
                            .filter(|task| {
                                task.category
                                    .as_deref()
                                    .is_some_and(|value| value.eq_ignore_ascii_case(name))
                            })
                            .count();
                        if !yes {
                            return success(
                                cli,
                                json!({"approvalRequired": true, "category": name, "tasksToClear": affected}),
                                || {
                                    format!("Preview: category will be cleared from {affected} tasks. Re-run with --yes.")
                                },
                            );
                        }
                        document
                            .category_options
                            .retain(|value| !value.eq_ignore_ascii_case(name));
                        for task in &mut document.tasks {
                            if task
                                .category
                                .as_deref()
                                .is_some_and(|value| value.eq_ignore_ascii_case(name))
                            {
                                task.category = None;
                            }
                        }
                        save_tasks(&root, &document)?;
                        success(
                            cli,
                            json!({"category": name, "tasksCleared": affected}),
                            || format!("Removed category {name}"),
                        )
                    }
                },
            }
        }
        Command::SavedLink { command } => {
            let (root, _) = resolve_root(cli)?;
            let links = load_saved_links(&root)?;
            match command {
                SavedLinkCommand::List => {
                    let values = links.iter().map(|link| &link.record).collect::<Vec<_>>();
                    output_collection(cli, &values, || {
                        values
                            .iter()
                            .map(|link| format!("{}\t{}", link.title, link.url))
                            .collect::<Vec<_>>()
                            .join("\n")
                    })
                }
                SavedLinkCommand::Get { selector } => {
                    let link = choose_saved_link(&links, selector)?;
                    success(
                        cli,
                        json!({"link": link.record, "content": link.content}),
                        || link.content.clone(),
                    )
                }
                SavedLinkCommand::Create { url, title } => {
                    let url = normalize_http_url(url)?;
                    if let Some(existing) = links.iter().find(|link| link.record.url == url) {
                        return success(
                            cli,
                            serde_json::to_value(&existing.record).unwrap(),
                            || format!("Already saved: {}", existing.record.title),
                        );
                    }
                    let id = Uuid::now_v7().to_string();
                    let title = title
                        .clone()
                        .filter(|value| !value.trim().is_empty())
                        .unwrap_or_else(|| {
                            url.split_once("://")
                                .map(|(_, rest)| {
                                    rest.split('/')
                                        .next()
                                        .unwrap_or(rest)
                                        .trim_start_matches("www.")
                                        .to_string()
                                })
                                .unwrap_or_else(|| "Link".into())
                        })
                        .replace(['\r', '\n'], " ");
                    let mut content = format!("# {title}\n\n<{url}>\n");
                    content =
                        zerus_core::set_reserved_property(&content, "zerus-link-id", Some(&id))
                            .map_err(|error| CliError::new("link_invalid", error.to_string(), 3))?;
                    content =
                        zerus_core::set_reserved_property(&content, "zerus-link-url", Some(&url))
                            .map_err(|error| CliError::new("link_invalid", error.to_string(), 3))?;
                    content = zerus_core::set_reserved_property(&content, "zerus-id", Some(&id))
                        .map_err(|error| CliError::new("link_invalid", error.to_string(), 3))?;
                    let path = format!("{SAVED_LINKS_DIR}/{id}.md");
                    atomic_write(&root.join(&path), &content, None).map_err(|error| {
                        CliError::new("link_write_failed", error.to_string(), 5)
                    })?;
                    let mut paths = saved_link_paths(&root)?;
                    paths.push(path.clone());
                    save_saved_link_paths(&root, &paths)?;
                    let record = SavedLinkRecord {
                        id,
                        path,
                        title,
                        url,
                    };
                    success(cli, serde_json::to_value(&record).unwrap(), || {
                        format!("Saved {}", record.url)
                    })
                }
                SavedLinkCommand::Delete { selector, yes } => {
                    let link = choose_saved_link(&links, selector)?;
                    if !yes {
                        return success(
                            cli,
                            json!({"approvalRequired": true, "link": link.record}),
                            || {
                                "Preview: one saved link will be permanently deleted. Re-run with --yes.".into()
                            },
                        );
                    }
                    fs::remove_file(&link.absolute_path).map_err(|error| {
                        CliError::new("link_delete_failed", error.to_string(), 5)
                    })?;
                    let paths = saved_link_paths(&root)?
                        .into_iter()
                        .filter(|path| path != &link.record.path)
                        .collect::<Vec<_>>();
                    save_saved_link_paths(&root, &paths)?;
                    success(cli, json!({"deletedLinkId": link.record.id}), || {
                        format!("Deleted {}", link.record.title)
                    })
                }
                SavedLinkCommand::MoveToType { selector, to } => {
                    let link = choose_saved_link(&links, selector)?;
                    let to = normalize_type_path(to)?;
                    let stem = link
                        .record
                        .title
                        .replace(['/', '\\', ':', '*', '?', '"', '<', '>', '|'], "");
                    let relative = format!(
                        "{to}/{}.md",
                        if stem.trim().is_empty() {
                            "Link"
                        } else {
                            stem.trim()
                        }
                    );
                    let destination = valid_note_destination(&root, &relative)?;
                    let mut content =
                        zerus_core::set_reserved_property(&link.content, "zerus-link-id", None)
                            .map_err(|error| CliError::new("link_invalid", error.to_string(), 3))?;
                    content =
                        zerus_core::set_reserved_property(&content, "zerus-link-url", None)
                            .map_err(|error| CliError::new("link_invalid", error.to_string(), 3))?;
                    atomic_write(&destination, &content, None).map_err(|error| {
                        CliError::new("link_write_failed", error.to_string(), 5)
                    })?;
                    fs::remove_file(&link.absolute_path).map_err(|error| {
                        CliError::new("link_delete_failed", error.to_string(), 5)
                    })?;
                    let paths = saved_link_paths(&root)?
                        .into_iter()
                        .filter(|path| path != &link.record.path)
                        .collect::<Vec<_>>();
                    save_saved_link_paths(&root, &paths)?;
                    success(
                        cli,
                        json!({"noteId": link.record.id, "path": relative}),
                        || format!("Moved link to {relative}"),
                    )
                }
            }
        }
        Command::File { command } => {
            let (notes, _, root) = load_notes(cli)?;
            match command {
                FileCommand::Get { selector } => {
                    let note = choose_note(cli, &notes, selector)?;
                    let reference = file_reference(note);
                    success(cli, json!({"note": note.path, "file": reference}), || {
                        reference
                            .map(|value| serde_json::to_string_pretty(&value).unwrap())
                            .unwrap_or_else(|| "No file attached".into())
                    })
                }
                FileCommand::AttachCopy { selector, source } => {
                    let note = choose_note(cli, &notes, selector)?;
                    if is_trashed_path(&note.path) {
                        return Err(CliError::new(
                            "note_trashed",
                            "restore the note before attaching a file",
                            3,
                        ));
                    }
                    if file_reference(note).is_some() {
                        return Err(CliError::new(
                            "file_exists",
                            "the note already has a file attachment; detach it before attaching another",
                            3,
                        ));
                    }
                    let source = source.canonicalize().map_err(|error| {
                        CliError::new("source_unavailable", error.to_string(), 3)
                    })?;
                    if !source.is_file() {
                        return Err(CliError::new(
                            "source_unavailable",
                            "source must be a file",
                            3,
                        ));
                    }
                    let name = source
                        .file_name()
                        .and_then(|value| value.to_str())
                        .ok_or_else(|| {
                            CliError::new("invalid_path", "source name is not UTF-8", 3)
                        })?
                        .to_string();
                    let directory = Path::new(&note.path)
                        .parent()
                        .and_then(|value| value.to_str())
                        .unwrap_or("");
                    let target_relative = unique_document_path(&root, directory, &name, "");
                    let target = root.join(&target_relative);
                    fs::copy(&source, &target)
                        .map_err(|error| CliError::new("file_copy_failed", error.to_string(), 5))?;
                    let id = Uuid::now_v7().to_string();
                    let mut next = note.content.clone();
                    for (key, value) in [
                        ("zerus-file-id", Some(id.as_str())),
                        ("zerus-file-name", Some(name.as_str())),
                        ("zerus-file-kind", Some("vault")),
                        ("zerus-file-path", Some(target_relative.as_str())),
                        ("zerus-file-location", None),
                        ("zerus-file-managed", Some("true")),
                    ] {
                        next = zerus_core::set_reserved_property(&next, key, value)
                            .map_err(|error| CliError::new("note_invalid", error.to_string(), 3))?;
                    }
                    let entry = match write_note(
                        &root,
                        note,
                        "file.attach-copy",
                        &next,
                        Some(&note.revision),
                    ) {
                        Ok(entry) => entry,
                        Err(error) => {
                            let _ = fs::remove_file(&target);
                            return Err(error);
                        }
                    };
                    success(
                        cli,
                        json!({"note": note.path, "file": file_reference_from_content(&next), "transactionId": entry.transaction_id}),
                        || format!("Attached {name}"),
                    )
                }
                FileCommand::Detach {
                    selector,
                    delete_managed,
                    yes,
                } => {
                    let note = choose_note(cli, &notes, selector)?;
                    let reference = file_reference(note).ok_or_else(|| {
                        CliError::new("file_not_found", "the note has no file attachment", 3)
                    })?;
                    if *delete_managed && !yes {
                        return success(
                            cli,
                            json!({"approvalRequired": true, "file": reference}),
                            || {
                                "Preview: the managed vault copy will be permanently deleted. Re-run with --yes.".into()
                            },
                        );
                    }
                    let mut next = note.content.clone();
                    for key in [
                        "zerus-file-id",
                        "zerus-file-name",
                        "zerus-file-kind",
                        "zerus-file-path",
                        "zerus-file-location",
                        "zerus-file-managed",
                    ] {
                        next = zerus_core::set_reserved_property(&next, key, None)
                            .map_err(|error| CliError::new("note_invalid", error.to_string(), 3))?;
                    }
                    let entry =
                        write_note(&root, note, "file.detach", &next, Some(&note.revision))?;
                    if *delete_managed && reference.managed && reference.kind == "vault" {
                        if let Some(path) = reference.path.filter(|path| safe_vault_relative(path))
                        {
                            if root.join(&path).exists() {
                                fs::remove_file(root.join(&path)).map_err(|error| {
                                    CliError::new("file_delete_failed", error.to_string(), 5)
                                })?;
                            }
                        }
                    }
                    success(
                        cli,
                        json!({"note": note.path, "detached": true, "transactionId": entry.transaction_id}),
                        || format!("Detached file from {}", note.title),
                    )
                }
            }
        }
        Command::Attachment { command } => {
            let (notes, _, root) = load_notes(cli)?;
            match command {
                AttachmentCommand::List { selector } => {
                    let note = choose_note(cli, &notes, selector)?;
                    let values = attachment_records(note);
                    output_collection(cli, &values, || {
                        values
                            .iter()
                            .map(|attachment| format!("{}\t{}", attachment.name, attachment.id))
                            .collect::<Vec<_>>()
                            .join("\n")
                    })
                }
                AttachmentCommand::AddCopy { selector, source } => {
                    let note = choose_note(cli, &notes, selector)?;
                    if is_trashed_path(&note.path) {
                        return Err(CliError::new(
                            "note_trashed",
                            "restore the note before adding attachments",
                            3,
                        ));
                    }
                    let note_id = note
                        .id
                        .ok_or_else(|| {
                            CliError::new("note_missing_id", "the note requires a zerus-id", 3)
                        })?
                        .to_string();
                    let source = source.canonicalize().map_err(|error| {
                        CliError::new("source_unavailable", error.to_string(), 3)
                    })?;
                    if !source.is_file() {
                        return Err(CliError::new(
                            "source_unavailable",
                            "source must be a file",
                            3,
                        ));
                    }
                    let name = source
                        .file_name()
                        .and_then(|value| value.to_str())
                        .ok_or_else(|| {
                            CliError::new("invalid_path", "source name is not UTF-8", 3)
                        })?
                        .to_string();
                    let directory = format!(".zerus/attachments/{note_id}");
                    fs::create_dir_all(root.join(&directory)).map_err(|error| {
                        CliError::new("attachment_write_failed", error.to_string(), 5)
                    })?;
                    let target_relative = unique_document_path(&root, &directory, &name, "");
                    fs::copy(&source, root.join(&target_relative)).map_err(|error| {
                        CliError::new("attachment_write_failed", error.to_string(), 5)
                    })?;
                    let attachment = AttachmentRecord {
                        id: Uuid::now_v7().to_string(),
                        name,
                        kind: "vault".into(),
                        path: Some(target_relative),
                        managed: true,
                    };
                    let mut attachments = attachment_records(note);
                    attachments.push(attachment.clone());
                    let next = set_attachment_records(&note.content, &attachments)?;
                    let entry = match write_note(
                        &root,
                        note,
                        "attachment.add-copy",
                        &next,
                        Some(&note.revision),
                    ) {
                        Ok(entry) => entry,
                        Err(error) => {
                            if let Some(path) = attachment.path.as_deref() {
                                let _ = fs::remove_file(root.join(path));
                            }
                            return Err(error);
                        }
                    };
                    success(
                        cli,
                        json!({"attachment": attachment, "markdown": format!("[{}](zerus-attachment:{})", attachment.name, attachment.id), "transactionId": entry.transaction_id}),
                        || format!("Attached {}", attachment.name),
                    )
                }
                AttachmentCommand::Remove {
                    selector,
                    attachment_id,
                    delete_managed,
                    yes,
                } => {
                    let note = choose_note(cli, &notes, selector)?;
                    let mut attachments = attachment_records(note);
                    let index = attachments
                        .iter()
                        .position(|attachment| attachment.id.starts_with(attachment_id))
                        .ok_or_else(|| {
                            CliError::new(
                                "attachment_not_found",
                                "no attachment matches that ID",
                                3,
                            )
                        })?;
                    let attachment = attachments[index].clone();
                    if *delete_managed && !yes {
                        return success(
                            cli,
                            json!({"approvalRequired": true, "attachment": attachment}),
                            || {
                                "Preview: the managed vault copy will be permanently deleted. Re-run with --yes.".into()
                            },
                        );
                    }
                    attachments.remove(index);
                    let next = set_attachment_records(&note.content, &attachments)?;
                    let entry = write_note(
                        &root,
                        note,
                        "attachment.remove",
                        &next,
                        Some(&note.revision),
                    )?;
                    if *delete_managed && attachment.managed && attachment.kind == "vault" {
                        if let Some(path) = attachment
                            .path
                            .as_deref()
                            .filter(|path| safe_vault_relative(path))
                        {
                            if root.join(path).exists() {
                                fs::remove_file(root.join(path)).map_err(|error| {
                                    CliError::new("attachment_delete_failed", error.to_string(), 5)
                                })?;
                            }
                        }
                    }
                    success(
                        cli,
                        json!({"removedAttachmentId": attachment.id, "transactionId": entry.transaction_id}),
                        || format!("Removed {}", attachment.name),
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
