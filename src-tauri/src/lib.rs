use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use portable_pty::{native_pty_system, ChildKiller, CommandBuilder, MasterPty, PtySize};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tauri::{Emitter, Manager};

#[cfg(target_os = "macos")]
mod mlx_ai_native;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CliInstallStatus {
    installed: bool,
    executable_path: String,
    on_path: bool,
    version: String,
}

fn cli_target_path() -> Result<std::path::PathBuf, String> {
    let home = dirs::home_dir().ok_or_else(|| "Could not locate your home folder".to_string())?;
    #[cfg(target_os = "windows")]
    let path = home.join("AppData/Local/Zerus/bin/zerus.exe");
    #[cfg(not(target_os = "windows"))]
    let path = home.join(".local/bin/zerus");
    Ok(path)
}

fn path_contains_file(path: &Path) -> bool {
    std::env::var_os("PATH")
        .map(|paths| {
            std::env::split_paths(&paths).any(|directory| {
                directory
                    .join(path.file_name().unwrap_or_default())
                    .exists()
            })
        })
        .unwrap_or(false)
}

#[tauri::command]
fn cli_status() -> Result<CliInstallStatus, String> {
    let path = cli_target_path()?;
    Ok(CliInstallStatus {
        installed: path.is_file(),
        on_path: path_contains_file(&path),
        executable_path: path.to_string_lossy().into_owned(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}

#[tauri::command]
fn cli_install(app: tauri::AppHandle) -> Result<CliInstallStatus, String> {
    let target = cli_target_path()?;
    let file_name = if cfg!(target_os = "windows") {
        "zerus.exe"
    } else {
        "zerus"
    };
    let candidates = [
        app.path()
            .resource_dir()
            .ok()
            .map(|path| path.join("binaries").join(file_name)),
        std::env::current_exe()
            .ok()
            .and_then(|path| path.parent().map(|parent| parent.join(file_name))),
        Some(
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("target/release")
                .join(file_name),
        ),
        Some(
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("target/debug")
                .join(file_name),
        ),
    ];
    let source = candidates
        .into_iter()
        .flatten()
        .find(|path| path.is_file())
        .ok_or_else(|| "The CLI executable was not included in this build".to_string())?;
    fs::create_dir_all(target.parent().unwrap()).map_err(|error| error.to_string())?;
    fs::copy(source, &target).map_err(|error| format!("Could not install the CLI: {error}"))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&target, fs::Permissions::from_mode(0o755))
            .map_err(|error| error.to_string())?;
    }
    cli_status()
}

fn sync_opened_vault_record(
    registry: &mut zerus_core::VaultRegistry,
    manifest: &zerus_core::VaultManifest,
    path: std::path::PathBuf,
) -> zerus_core::VaultRecord {
    let existing_name = registry
        .vaults
        .iter()
        .find(|vault| vault.id == manifest.vault_id)
        .map(|vault| vault.name.clone());
    let base_name = path
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.trim().is_empty())
        .unwrap_or("Vault")
        .to_string();
    let name = existing_name.unwrap_or_else(|| {
        let mut candidate = base_name.clone();
        let mut suffix = 2;
        while registry
            .vaults
            .iter()
            .any(|vault| vault.name.eq_ignore_ascii_case(&candidate))
        {
            candidate = format!("{base_name} ({suffix})");
            suffix += 1;
        }
        candidate
    });
    let record = zerus_core::VaultRecord {
        id: manifest.vault_id,
        name,
        path,
    };
    registry.vaults.retain(|vault| vault.id != record.id);
    registry.vaults.push(record.clone());
    registry
        .vaults
        .sort_by(|left, right| left.name.to_lowercase().cmp(&right.name.to_lowercase()));
    registry.default_vault_id = Some(record.id);
    record
}

#[tauri::command]
fn cli_register_vault(vault_path: String) -> Result<zerus_core::VaultRecord, String> {
    let root = Path::new(&vault_path)
        .canonicalize()
        .map_err(|error| format!("Could not resolve the opened vault: {error}"))?;
    let manifest = zerus_core::load_or_create_manifest(&root).map_err(|error| error.to_string())?;
    let registry_path = zerus_core::default_registry_path().map_err(|error| error.to_string())?;
    let mut registry =
        zerus_core::load_registry(&registry_path).map_err(|error| error.to_string())?;
    let record = sync_opened_vault_record(&mut registry, &manifest, root);
    zerus_core::save_registry(&registry_path, &registry).map_err(|error| error.to_string())?;
    Ok(record)
}

fn skill_markdown(agent: &str) -> String {
    format!(
        r#"---
name: zerus
description: Work safely with the user's local Zerus Markdown vault through the Zerus CLI.
---

# Zerus CLI

Use `zerus` for Zerus vault notes. Always select the vault explicitly with `--vault` in automation and use `--json` for machine-readable output.

Start with `zerus vault list --json` and `zerus doctor --json`. Read with `note list`, `note get`, and `search`. Mutate with `note create`, `note set-body`, `note append`, `note pin`, `note archive`, `note property set`, `note trash`, `note restore`, and `import`. Include `--if-revision` when changing content read earlier. Preview `migrate` before applying it. Use `history` and `undo` for recovery. Never edit `grimoire-*` properties directly.

Manage property definitions with `schema list|add|remove`; do not hand-edit `.grimoire/properties.json`. Schema type paths are exact and inherit into sub-types. Create relations with `schema add TYPE_PATH NAME relation --relation-type TARGET_TYPE [--multiple]`. Create lists with `schema add TYPE_PATH NAME list --options A,B,C [--multiple]`.

For destructive or bulk operations, explain the preview and obtain explicit user approval. This package targets {agent}.
"#
    )
}

#[tauri::command]
fn cli_install_skill(agent: String, profile: Option<String>) -> Result<String, String> {
    let home = dirs::home_dir().ok_or_else(|| "Could not locate your home folder".to_string())?;
    let normalized = agent.to_ascii_lowercase();
    let directory = match normalized.as_str() {
        "codex" | "agent-skills" => home.join(".agents/skills/zerus"),
        "claude" => home.join(".claude/skills/zerus"),
        "hermes" => profile
            .filter(|value| !value.trim().is_empty())
            .map(|value| {
                home.join(".hermes/profiles")
                    .join(value)
                    .join("skills/note-taking/zerus")
            })
            .unwrap_or_else(|| home.join(".hermes/skills/note-taking/zerus")),
        _ => {
            return Err("Supported agents are Codex, Claude, Agent Skills, and Hermes".to_string())
        }
    };
    fs::create_dir_all(&directory).map_err(|error| error.to_string())?;
    fs::write(directory.join("SKILL.md"), skill_markdown(&normalized))
        .map_err(|error| error.to_string())?;
    Ok(directory.to_string_lossy().into_owned())
}

#[tauri::command]
fn cli_export_skill(path: String) -> Result<String, String> {
    let selected_path = std::path::PathBuf::from(path);
    let target = if selected_path
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| extension.eq_ignore_ascii_case("md"))
    {
        selected_path
    } else {
        std::path::PathBuf::from(format!("{}.md", selected_path.to_string_lossy()))
    };
    fs::write(&target, skill_markdown("other agents"))
        .map_err(|error| format!("Could not save the Zerus skill: {error}"))?;
    Ok(target.to_string_lossy().into_owned())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CliMigrationPreview {
    notes_scanned: usize,
    notes_changed: usize,
    ids_added: usize,
    pinned_added: usize,
    archived_added: usize,
    blocked: bool,
    warnings: Vec<String>,
}

fn migration_plan(
    root: &Path,
    pinned_paths: &[String],
    archived_paths: &[String],
) -> Result<zerus_core::VaultMetadataMigrationPlan, String> {
    let notes = zerus_core::scan_vault(root).map_err(|error| error.to_string())?;
    let inputs: Vec<_> = notes
        .iter()
        .map(|note| zerus_core::MigrationNoteInput {
            path: &note.path,
            content: &note.content,
            legacy_pinned: pinned_paths.iter().any(|path| path == &note.path),
            legacy_archived: archived_paths.iter().any(|path| path == &note.path),
        })
        .collect();
    Ok(zerus_core::plan_vault_metadata_migration(&inputs))
}

#[tauri::command]
fn cli_migration_preview(
    vault_path: String,
    pinned_paths: Vec<String>,
    archived_paths: Vec<String>,
) -> Result<CliMigrationPreview, String> {
    let root = Path::new(&vault_path);
    let plan = migration_plan(root, &pinned_paths, &archived_paths)?;
    Ok(CliMigrationPreview {
        notes_scanned: plan.summary.notes_scanned,
        notes_changed: plan.summary.notes_changed,
        ids_added: plan.summary.ids_added,
        pinned_added: plan.summary.pinned_added,
        archived_added: plan.summary.archived_added,
        blocked: !plan.can_apply,
        warnings: plan
            .issues
            .iter()
            .map(|issue| format!("{}: {}", issue.path, issue.message))
            .collect(),
    })
}

#[tauri::command]
fn cli_migration_apply(
    vault_path: String,
    pinned_paths: Vec<String>,
    archived_paths: Vec<String>,
) -> Result<CliMigrationPreview, String> {
    let root = Path::new(&vault_path);
    let plan = migration_plan(root, &pinned_paths, &archived_paths)?;
    if !plan.can_apply {
        return Err("Migration is blocked by note metadata that needs review".to_string());
    }
    let mut written: Vec<(std::path::PathBuf, String)> = Vec::new();
    for note in &plan.notes {
        if !note.plan.changed {
            continue;
        }
        let path = root.join(&note.path);
        let original = fs::read_to_string(&path).map_err(|error| error.to_string())?;
        match zerus_core::atomic_write(
            &path,
            &note.plan.next_content,
            Some(&note.plan.before_revision),
        ) {
            Ok(_) => written.push((path, original)),
            Err(error) => {
                for (written_path, original) in written {
                    let _ = zerus_core::atomic_write(&written_path, &original, None);
                }
                return Err(format!("Migration was rolled back: {error}"));
            }
        }
    }
    let history_dir = root.join(".grimoire/history");
    fs::create_dir_all(&history_dir).map_err(|error| error.to_string())?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    for (index, (path, original)) in written.iter().enumerate() {
        let relative = path
            .strip_prefix(root)
            .unwrap_or(path)
            .to_string_lossy()
            .replace('\\', "/");
        let transaction_id = format!("desktop-{now}-{index}");
        let after = fs::read_to_string(path).map_err(|error| error.to_string())?;
        let record = serde_json::json!({
            "transactionId": transaction_id,
            "operation": "migration.metadata",
            "pathBefore": relative,
            "pathAfter": relative,
            "contentBefore": original,
            "contentAfter": after,
            "createdAtMs": now,
        });
        fs::write(
            history_dir.join(format!("{transaction_id}.json")),
            serde_json::to_vec_pretty(&record).unwrap(),
        )
        .map_err(|error| error.to_string())?;
    }
    let mut manifest =
        zerus_core::load_or_create_manifest(root).map_err(|error| error.to_string())?;
    manifest.metadata_version = 1;
    manifest.ids_required = true;
    zerus_core::write_vault_manifest(root, &manifest).map_err(|error| error.to_string())?;
    let registry_path = zerus_core::default_registry_path().map_err(|error| error.to_string())?;
    let mut registry =
        zerus_core::load_registry(&registry_path).map_err(|error| error.to_string())?;
    registry
        .vaults
        .retain(|vault| vault.id != manifest.vault_id);
    registry.vaults.push(zerus_core::VaultRecord {
        id: manifest.vault_id,
        name: root
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("Vault")
            .to_string(),
        path: root.canonicalize().map_err(|error| error.to_string())?,
    });
    registry
        .vaults
        .sort_by(|left, right| left.name.to_lowercase().cmp(&right.name.to_lowercase()));
    if registry.default_vault_id.is_none() {
        registry.default_vault_id = Some(manifest.vault_id);
    }
    zerus_core::save_registry(&registry_path, &registry).map_err(|error| error.to_string())?;
    Ok(CliMigrationPreview {
        notes_scanned: plan.summary.notes_scanned,
        notes_changed: plan.summary.notes_changed,
        ids_added: plan.summary.ids_added,
        pinned_added: plan.summary.pinned_added,
        archived_added: plan.summary.archived_added,
        blocked: false,
        warnings: Vec::new(),
    })
}

#[derive(Default)]
struct PendingOpenFiles(Mutex<Vec<String>>);

#[derive(Default)]
struct LocalAiRuntimeState {
    #[cfg(target_os = "macos")]
    native: mlx_ai_native::NativeAiRuntime,
}

#[derive(Clone)]
struct CloudAiCredentials {
    base_url: String,
    api_key: String,
}

#[derive(Default)]
struct CloudAiState(Mutex<Option<CloudAiCredentials>>);

#[cfg_attr(target_os = "macos", allow(dead_code))]
const LOCAL_AI_BASE_URL: &str = "http://127.0.0.1:8080";
#[cfg(target_os = "macos")]
const LOCAL_AI_MODEL: &str = "Qwen3-1.7B-4bit";
#[cfg(not(target_os = "macos"))]
const LOCAL_AI_MODEL: &str = "gemma-4-E4B-it";
#[cfg_attr(target_os = "macos", allow(dead_code))]
const LOCAL_AI_TEMPERATURE: f64 = 0.2;
#[cfg(not(target_os = "macos"))]
const LOCAL_AI_MODEL_FILE: &str = "gemma-4-E4B-it.litertlm";
#[cfg(target_os = "macos")]
const LOCAL_AI_MODEL_SIZE: u64 = 984_015_687;
#[cfg(not(target_os = "macos"))]
const LOCAL_AI_MODEL_SIZE: u64 = 3_659_530_240;
const LOCAL_AI_MODEL_SHA256: &str =
    "0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0";
const LOCAL_AI_MODEL_URL: &str = "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm?download=true";
static LOCAL_AI_DOWNLOAD_ACTIVE: AtomicBool = AtomicBool::new(false);

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LocalAiStatus {
    runtime_ready: bool,
    model_downloaded: bool,
    model_path: String,
    download_size_bytes: u64,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct LocalAiDownloadProgress {
    downloaded_bytes: u64,
    total_bytes: u64,
    phase: &'static str,
}

struct LocalAiDownloadGuard;

impl Drop for LocalAiDownloadGuard {
    fn drop(&mut self) {
        LOCAL_AI_DOWNLOAD_ACTIVE.store(false, Ordering::Release);
    }
}

fn local_ai_model_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    app.path()
        .app_data_dir()
        .map(|path| {
            #[cfg(target_os = "macos")]
            {
                path.join("local-ai").join("mlx")
            }
            #[cfg(not(target_os = "macos"))]
            {
                path.join("local-ai")
                    .join("models")
                    .join(LOCAL_AI_MODEL_FILE)
            }
        })
        .map_err(|error| format!("Could not locate Zerus's model folder: {error}"))
}

fn local_ai_model_downloaded(path: &Path) -> bool {
    #[cfg(target_os = "macos")]
    {
        path.join(mlx_ai_native::READY_MARKER).is_file()
    }
    #[cfg(not(target_os = "macos"))]
    {
        path.metadata()
            .is_ok_and(|metadata| metadata.is_file() && metadata.len() == LOCAL_AI_MODEL_SIZE)
    }
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct LocalAiMessage {
    role: String,
    content: String,
    #[serde(default)]
    image_paths: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LocalAiChatRequest {
    system_prompt: String,
    messages: Vec<LocalAiMessage>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct LocalAiChatResponse {
    content: String,
    reasoning: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CloudAiModel {
    id: String,
    name: String,
}

fn normalized_cloud_ai_base_url(value: &str) -> Result<String, String> {
    let value = value.trim().trim_end_matches('/');
    let parsed = reqwest::Url::parse(value).map_err(|_| {
        "Enter a valid provider URL, such as https://openrouter.ai/api/v1".to_string()
    })?;
    let is_loopback = parsed
        .host_str()
        .is_some_and(|host| matches!(host, "localhost" | "127.0.0.1" | "::1"));
    if parsed.scheme() != "https" && !(parsed.scheme() == "http" && is_loopback) {
        return Err(
            "Cloud provider URLs must use HTTPS (HTTP is allowed only for localhost)".to_string(),
        );
    }
    if !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.query().is_some()
        || parsed.fragment().is_some()
    {
        return Err(
            "The provider URL cannot contain credentials, a query, or a fragment".to_string(),
        );
    }
    Ok(value.to_string())
}

fn cloud_ai_request_body(
    request: LocalAiChatRequest,
    model: &str,
) -> Result<serde_json::Value, String> {
    let model = model.trim();
    if model.is_empty() || model.len() > 200 {
        return Err("Select a valid cloud model".to_string());
    }
    if request.system_prompt.trim().is_empty() {
        return Err("The AI context is empty".to_string());
    }
    if request.messages.is_empty() || request.messages.len() > 64 {
        return Err("The AI conversation has an invalid number of messages".to_string());
    }

    let mut messages = vec![serde_json::json!({
        "role": "system",
        "content": request.system_prompt,
    })];
    for message in request.messages {
        if !matches!(message.role.as_str(), "user" | "assistant") {
            return Err("The AI conversation contains an invalid role".to_string());
        }
        if message.content.len() > 50_000 {
            return Err("An AI message is too large".to_string());
        }
        if !message.image_paths.is_empty() {
            return Err("Cloud image attachments are not supported yet".to_string());
        }
        messages.push(serde_json::json!({
            "role": message.role,
            "content": message.content,
        }));
    }

    Ok(serde_json::json!({
        "model": model,
        "messages": messages,
        "temperature": LOCAL_AI_TEMPERATURE,
        "max_tokens": 2048,
        "stream": false,
    }))
}

fn cloud_ai_error(payload: &serde_json::Value, fallback: &str) -> String {
    payload
        .pointer("/error/message")
        .and_then(|value| value.as_str())
        .or_else(|| payload.get("message").and_then(|value| value.as_str()))
        .unwrap_or(fallback)
        .to_string()
}

fn cloud_ai_credentials(
    state: &CloudAiState,
    base_url: &str,
    api_key: Option<String>,
) -> Result<CloudAiCredentials, String> {
    let base_url = normalized_cloud_ai_base_url(base_url)?;
    let supplied_key = api_key.unwrap_or_default().trim().to_string();
    let mut stored = state
        .0
        .lock()
        .map_err(|_| "The cloud AI configuration is unavailable")?;
    if !supplied_key.is_empty() {
        let credentials = CloudAiCredentials {
            base_url,
            api_key: supplied_key,
        };
        *stored = Some(credentials.clone());
        return Ok(credentials);
    }
    if let Some(credentials) = stored.as_ref().filter(|value| value.base_url == base_url) {
        return Ok(credentials.clone());
    }
    if base_url == "https://openrouter.ai/api/v1" {
        if let Ok(api_key) = std::env::var("OPENROUTER_API_KEY") {
            if !api_key.trim().is_empty() {
                let credentials = CloudAiCredentials { base_url, api_key };
                *stored = Some(credentials.clone());
                return Ok(credentials);
            }
        }
    }
    Err("Enter an API key. Zerus keeps it in memory for this app session only".to_string())
}

#[tauri::command]
fn cloud_ai_configure(
    state: tauri::State<'_, CloudAiState>,
    base_url: String,
    api_key: Option<String>,
) -> Result<(), String> {
    cloud_ai_credentials(&state, &base_url, api_key).map(|_| ())
}

fn validated_ai_image_path(path: &str) -> Result<String, String> {
    let canonical = Path::new(path)
        .canonicalize()
        .map_err(|error| format!("Could not open the attached image: {error}"))?;
    if !canonical.is_file() {
        return Err("The attached image is not a file".to_string());
    }
    let supported = canonical
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            matches!(
                extension.to_ascii_lowercase().as_str(),
                "png" | "jpg" | "jpeg" | "webp" | "heic" | "heif"
            )
        });
    if !supported {
        return Err("The attached file is not a supported image".to_string());
    }
    Ok(canonical.to_string_lossy().into_owned())
}

#[cfg_attr(target_os = "macos", allow(dead_code))]
fn local_ai_request_body(request: LocalAiChatRequest) -> Result<serde_json::Value, String> {
    if request.system_prompt.trim().is_empty() {
        return Err("The AI context is empty".to_string());
    }
    if request.messages.is_empty() || request.messages.len() > 64 {
        return Err("The AI conversation has an invalid number of messages".to_string());
    }

    let mut messages = vec![serde_json::json!({
        "role": "system",
        "content": request.system_prompt,
    })];
    for message in request.messages {
        if !matches!(message.role.as_str(), "user" | "assistant") {
            return Err("The AI conversation contains an invalid role".to_string());
        }
        if message.content.len() > 50_000 {
            return Err("An AI message is too large".to_string());
        }
        let content = if message.image_paths.is_empty() {
            serde_json::Value::String(message.content)
        } else {
            let mut parts = vec![serde_json::json!({
                "type": "text",
                "text": message.content,
            })];
            for path in message.image_paths {
                parts.push(serde_json::json!({
                    "type": "image_url",
                    "image_url": {
                        "url": validated_ai_image_path(&path)?,
                    },
                }));
            }
            serde_json::Value::Array(parts)
        };
        messages.push(serde_json::json!({
            "role": message.role,
            "content": content,
        }));
    }

    Ok(serde_json::json!({
        "model": LOCAL_AI_MODEL,
        "messages": messages,
        "temperature": LOCAL_AI_TEMPERATURE,
        "max_tokens": 2048,
        "stream": false,
        "reasoning_effort": "medium",
    }))
}

#[cfg_attr(target_os = "macos", allow(dead_code))]
fn response_text(value: Option<&serde_json::Value>) -> Option<String> {
    match value {
        Some(serde_json::Value::String(content)) => Some(content.clone()),
        Some(serde_json::Value::Array(parts)) => {
            let text = parts
                .iter()
                .filter_map(|part| part.get("text").and_then(|text| text.as_str()))
                .collect::<Vec<_>>()
                .join("");
            (!text.is_empty()).then_some(text)
        }
        _ => None,
    }
}

async fn local_ai_runtime_ready(app: &tauri::AppHandle) -> bool {
    #[cfg(target_os = "macos")]
    {
        return mlx_ai_native::available(app);
    }

    #[cfg(not(target_os = "macos"))]
    {
        let client = match reqwest::Client::builder()
            .timeout(std::time::Duration::from_millis(900))
            .build()
        {
            Ok(client) => client,
            Err(_) => return false,
        };
        let response = match client
            .get(format!("{LOCAL_AI_BASE_URL}/v1/models"))
            .send()
            .await
        {
            Ok(response) if response.status().is_success() => response,
            _ => return false,
        };
        response
            .json::<serde_json::Value>()
            .await
            .ok()
            .and_then(|payload| {
                payload
                    .get("data")
                    .and_then(|data| data.as_array())
                    .cloned()
            })
            .is_some_and(|models| {
                models.iter().any(|model| {
                    model
                        .get("id")
                        .and_then(|id| id.as_str())
                        .is_some_and(|id| id.eq_ignore_ascii_case(LOCAL_AI_MODEL))
                })
            })
    }
}

#[tauri::command]
async fn local_ai_status(app: tauri::AppHandle) -> Result<LocalAiStatus, String> {
    let model_path = local_ai_model_path(&app)?;
    Ok(LocalAiStatus {
        runtime_ready: local_ai_runtime_ready(&app).await,
        model_downloaded: local_ai_model_downloaded(&model_path),
        model_path: model_path.to_string_lossy().into_owned(),
        download_size_bytes: LOCAL_AI_MODEL_SIZE,
    })
}

#[tauri::command]
async fn local_ai_download_model(
    app: tauri::AppHandle,
    runtime: tauri::State<'_, LocalAiRuntimeState>,
) -> Result<LocalAiStatus, String> {
    #[cfg(target_os = "macos")]
    {
        LOCAL_AI_DOWNLOAD_ACTIVE
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| "The Qwen model is already downloading".to_string())?;
        let _download_guard = LocalAiDownloadGuard;
        let model_path = local_ai_model_path(&app)?;
        if local_ai_model_downloaded(&model_path) {
            return local_ai_status(app).await;
        }
        mlx_ai_native::download(&app, &runtime.native, &model_path, |progress| {
            let phase = match progress.phase.as_str() {
                "installing" => "installing",
                "complete" => "complete",
                _ => "downloading",
            };
            let _ = app.emit(
                "local-ai-download-progress",
                LocalAiDownloadProgress {
                    downloaded_bytes: progress.downloaded_bytes,
                    total_bytes: if progress.total_bytes == 0 {
                        LOCAL_AI_MODEL_SIZE
                    } else {
                        progress.total_bytes
                    },
                    phase,
                },
            );
        })?;
        return local_ai_status(app).await;
    }

    #[allow(unreachable_code)]
    {
        LOCAL_AI_DOWNLOAD_ACTIVE
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| "The Gemma model is already downloading".to_string())?;
        let _download_guard = LocalAiDownloadGuard;
        let model_path = local_ai_model_path(&app)?;
        if local_ai_model_downloaded(&model_path) {
            return local_ai_status(app).await;
        }

        let parent = model_path
            .parent()
            .ok_or_else(|| "The Gemma model path has no parent folder".to_string())?;
        fs::create_dir_all(parent)
            .map_err(|error| format!("Could not create the local AI model folder: {error}"))?;
        if model_path.exists() {
            fs::remove_file(&model_path)
                .map_err(|error| format!("Could not replace the invalid Gemma model: {error}"))?;
        }
        let partial_path = model_path.with_extension("litertlm.part");
        if partial_path.exists() {
            fs::remove_file(&partial_path).map_err(|error| {
                format!("Could not clear the incomplete model download: {error}")
            })?;
        }

        let result: Result<(), String> = async {
            let client = reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(60 * 60 * 3))
                .build()
                .map_err(|error| error.to_string())?;
            let mut response = client
                .get(LOCAL_AI_MODEL_URL)
                .send()
                .await
                .map_err(|error| format!("Could not start the Hugging Face download: {error}"))?;
            if !response.status().is_success() {
                return Err(format!(
                    "Hugging Face returned {} while downloading Gemma",
                    response.status()
                ));
            }
            if response
                .content_length()
                .is_some_and(|size| size != LOCAL_AI_MODEL_SIZE)
            {
                return Err("Hugging Face reported an unexpected Gemma model size".to_string());
            }

            let mut file = OpenOptions::new()
                .create_new(true)
                .write(true)
                .open(&partial_path)
                .map_err(|error| format!("Could not create the model download: {error}"))?;
            let mut hasher = Sha256::new();
            let mut downloaded = 0_u64;
            let mut last_emitted = 0_u64;
            app.emit(
                "local-ai-download-progress",
                LocalAiDownloadProgress {
                    downloaded_bytes: 0,
                    total_bytes: LOCAL_AI_MODEL_SIZE,
                    phase: "downloading",
                },
            )
            .map_err(|error| error.to_string())?;

            while let Some(chunk) = response
                .chunk()
                .await
                .map_err(|error| format!("The Gemma download was interrupted: {error}"))?
            {
                downloaded = downloaded.saturating_add(chunk.len() as u64);
                if downloaded > LOCAL_AI_MODEL_SIZE {
                    return Err("The Gemma download exceeded its expected size".to_string());
                }
                file.write_all(&chunk)
                    .map_err(|error| format!("Could not save the Gemma model: {error}"))?;
                hasher.update(&chunk);
                if downloaded == LOCAL_AI_MODEL_SIZE
                    || downloaded.saturating_sub(last_emitted) >= 8 * 1024 * 1024
                {
                    app.emit(
                        "local-ai-download-progress",
                        LocalAiDownloadProgress {
                            downloaded_bytes: downloaded,
                            total_bytes: LOCAL_AI_MODEL_SIZE,
                            phase: "downloading",
                        },
                    )
                    .map_err(|error| error.to_string())?;
                    last_emitted = downloaded;
                }
            }
            file.flush()
                .map_err(|error| format!("Could not finish saving the Gemma model: {error}"))?;
            if downloaded != LOCAL_AI_MODEL_SIZE {
                return Err(format!(
                "The Gemma download was incomplete ({downloaded} of {LOCAL_AI_MODEL_SIZE} bytes)"
            ));
            }
            app.emit(
                "local-ai-download-progress",
                LocalAiDownloadProgress {
                    downloaded_bytes: downloaded,
                    total_bytes: LOCAL_AI_MODEL_SIZE,
                    phase: "verifying",
                },
            )
            .map_err(|error| error.to_string())?;
            let digest = format!("{:x}", hasher.finalize());
            if digest != LOCAL_AI_MODEL_SHA256 {
                return Err("The downloaded Gemma model failed its integrity check".to_string());
            }
            app.emit(
                "local-ai-download-progress",
                LocalAiDownloadProgress {
                    downloaded_bytes: downloaded,
                    total_bytes: LOCAL_AI_MODEL_SIZE,
                    phase: "installing",
                },
            )
            .map_err(|error| error.to_string())?;
            fs::rename(&partial_path, &model_path).map_err(|error| {
                format!("Could not install the downloaded Gemma model: {error}")
            })?;
            if !local_ai_model_downloaded(&model_path) {
                return Err(
                    "Gemma was downloaded but the installed model could not be verified"
                        .to_string(),
                );
            }
            app.emit(
                "local-ai-download-progress",
                LocalAiDownloadProgress {
                    downloaded_bytes: downloaded,
                    total_bytes: LOCAL_AI_MODEL_SIZE,
                    phase: "complete",
                },
            )
            .map_err(|error| error.to_string())?;
            Ok(())
        }
        .await;

        if let Err(error) = result {
            let _ = fs::remove_file(&partial_path);
            return Err(error);
        }
        local_ai_status(app).await
    }
}

#[cfg(target_os = "macos")]
fn local_ai_native_response(
    app: &tauri::AppHandle,
    runtime: &LocalAiRuntimeState,
    request: LocalAiChatRequest,
) -> Result<LocalAiChatResponse, String> {
    if request.system_prompt.trim().is_empty() || request.messages.is_empty() {
        return Err("The AI conversation is empty".to_string());
    }
    if request
        .messages
        .iter()
        .any(|message| !message.image_paths.is_empty())
    {
        return Err("Qwen3 1.7B is text-only and cannot read image attachments".to_string());
    }
    let model_path = local_ai_model_path(app)?;
    if !local_ai_model_downloaded(&model_path) {
        return Err("Qwen is not downloaded".to_string());
    }
    let messages = serde_json::to_value(&request.messages)
        .map_err(|error| format!("Could not encode the MLX conversation: {error}"))?;
    let response = mlx_ai_native::chat(
        app,
        &runtime.native,
        &model_path,
        &request.system_prompt,
        &messages,
    )?;
    Ok(LocalAiChatResponse {
        content: response.content,
        reasoning: response.reasoning,
    })
}

#[tauri::command]
async fn local_ai_chat(
    app: tauri::AppHandle,
    runtime: tauri::State<'_, LocalAiRuntimeState>,
    request: LocalAiChatRequest,
) -> Result<LocalAiChatResponse, String> {
    #[cfg(target_os = "macos")]
    {
        return local_ai_native_response(&app, &runtime, request);
    }

    #[cfg(not(target_os = "macos"))]
    {
        let body = local_ai_request_body(request)?;
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(180))
            .build()
            .map_err(|error| error.to_string())?;
        let response = client
            .post(format!("{LOCAL_AI_BASE_URL}/v1/chat/completions"))
            .json(&body)
            .send()
            .await
            .map_err(|error| {
                format!("Could not reach the local Gemma runtime at {LOCAL_AI_BASE_URL}: {error}")
            })?;
        let status = response.status();
        let payload = response
            .json::<serde_json::Value>()
            .await
            .map_err(|error| format!("The local Gemma runtime returned invalid JSON: {error}"))?;
        if !status.is_success() {
            let detail = payload
                .pointer("/error/message")
                .and_then(|value| value.as_str())
                .unwrap_or("Unknown local runtime error");
            return Err(format!("Gemma request failed ({status}): {detail}"));
        }

        let message = payload
            .pointer("/choices/0/message")
            .ok_or_else(|| "The local Gemma runtime returned no message".to_string())?;
        let content = response_text(message.get("content"))
            .ok_or_else(|| "The local Gemma response contained no text".to_string())?;
        let reasoning = response_text(message.get("reasoning_content"))
            .or_else(|| response_text(message.get("reasoning")));
        Ok(LocalAiChatResponse { content, reasoning })
    }
}

#[tauri::command]
async fn cloud_ai_models(
    state: tauri::State<'_, CloudAiState>,
    base_url: String,
    api_key: Option<String>,
) -> Result<Vec<CloudAiModel>, String> {
    let credentials = cloud_ai_credentials(&state, &base_url, api_key)?;
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|error| error.to_string())?;
    let response = client
        .get(format!("{}/models", credentials.base_url))
        .bearer_auth(&credentials.api_key)
        .send()
        .await
        .map_err(|error| format!("Could not reach the AI provider: {error}"))?;
    let status = response.status();
    let payload = response
        .json::<serde_json::Value>()
        .await
        .map_err(|error| format!("The AI provider returned invalid JSON: {error}"))?;
    if !status.is_success() {
        return Err(format!(
            "Model request failed ({status}): {}",
            cloud_ai_error(&payload, "Unknown provider error")
        ));
    }
    let models = payload
        .get("data")
        .and_then(|value| value.as_array())
        .ok_or_else(|| "The AI provider returned no model list".to_string())?;
    let mut models = models
        .iter()
        .filter_map(|model| {
            let id = model.get("id")?.as_str()?.trim();
            if id.is_empty() {
                return None;
            }
            let name = model
                .get("name")
                .and_then(|value| value.as_str())
                .filter(|value| !value.trim().is_empty())
                .unwrap_or(id);
            Some(CloudAiModel {
                id: id.to_string(),
                name: name.to_string(),
            })
        })
        .collect::<Vec<_>>();
    models.sort_by(|left, right| left.name.to_lowercase().cmp(&right.name.to_lowercase()));
    models.dedup_by(|left, right| left.id == right.id);
    if models.is_empty() {
        return Err("The AI provider returned an empty model list".to_string());
    }
    Ok(models)
}

#[tauri::command]
async fn cloud_ai_chat(
    state: tauri::State<'_, CloudAiState>,
    base_url: String,
    model: String,
    request: LocalAiChatRequest,
) -> Result<LocalAiChatResponse, String> {
    let credentials = cloud_ai_credentials(&state, &base_url, None)?;
    let body = cloud_ai_request_body(request, &model)?;
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(180))
        .build()
        .map_err(|error| error.to_string())?;
    let mut request_builder = client
        .post(format!("{}/chat/completions", credentials.base_url))
        .bearer_auth(&credentials.api_key);
    if credentials.base_url == "https://openrouter.ai/api/v1" {
        request_builder = request_builder
            .header("HTTP-Referer", "https://zerus.im")
            .header("X-Title", "Zerus");
    }
    let response = request_builder
        .json(&body)
        .send()
        .await
        .map_err(|error| format!("Could not reach the AI provider: {error}"))?;
    let status = response.status();
    let payload = response
        .json::<serde_json::Value>()
        .await
        .map_err(|error| format!("The AI provider returned invalid JSON: {error}"))?;
    if !status.is_success() {
        return Err(format!(
            "Cloud AI request failed ({status}): {}",
            cloud_ai_error(&payload, "Unknown provider error")
        ));
    }
    let message = payload
        .pointer("/choices/0/message")
        .ok_or_else(|| "The cloud AI provider returned no message".to_string())?;
    let content = response_text(message.get("content"))
        .ok_or_else(|| "The cloud AI response contained no text".to_string())?;
    let reasoning = response_text(message.get("reasoning_content"))
        .or_else(|| response_text(message.get("reasoning")));
    Ok(LocalAiChatResponse { content, reasoning })
}

#[derive(Clone, Default)]
struct TerminalManager(Arc<TerminalManagerInner>);

#[derive(Default)]
struct TerminalManagerInner {
    sessions: Mutex<HashMap<u64, TerminalSession>>,
    next_id: AtomicU64,
}

struct TerminalSession {
    id: u64,
    cwd: String,
    writer: Box<dyn Write + Send>,
    master: Box<dyn MasterPty + Send>,
    killer: Box<dyn ChildKiller + Send + Sync>,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct TerminalSessionInfo {
    session_id: u64,
    working_directory: String,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct TerminalOutput {
    session_id: u64,
    data: Vec<u8>,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct TerminalExit {
    session_id: u64,
    exit_code: Option<u32>,
    signal: Option<String>,
    error: Option<String>,
}

fn configured_shell() -> String {
    #[cfg(target_os = "windows")]
    {
        std::env::var("COMSPEC").unwrap_or_else(|_| "cmd.exe".to_string())
    }

    #[cfg(not(target_os = "windows"))]
    {
        std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string())
    }
}

fn validated_terminal_directory(path: &str) -> Result<std::path::PathBuf, String> {
    let directory = Path::new(path)
        .canonicalize()
        .map_err(|error| format!("Could not open the note folder: {error}"))?;
    if !directory.is_dir() {
        return Err("The terminal working path is not a folder".to_string());
    }
    Ok(directory)
}

#[tauri::command]
fn terminal_status(state: tauri::State<'_, TerminalManager>) -> Vec<TerminalSessionInfo> {
    let sessions = state
        .0
        .sessions
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let mut infos = sessions
        .values()
        .map(|session| TerminalSessionInfo {
            session_id: session.id,
            working_directory: session.cwd.clone(),
        })
        .collect::<Vec<_>>();
    infos.sort_by_key(|info| info.session_id);
    infos
}

#[tauri::command]
fn terminal_start(
    app: tauri::AppHandle,
    state: tauri::State<'_, TerminalManager>,
    working_directory: String,
    rows: u16,
    cols: u16,
) -> Result<TerminalSessionInfo, String> {
    let directory = validated_terminal_directory(&working_directory)?;
    let canonical_directory = directory.to_string_lossy().into_owned();

    {
        let sessions = state
            .0
            .sessions
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(session) = sessions
            .values()
            .find(|session| session.cwd == canonical_directory)
        {
            return Ok(TerminalSessionInfo {
                session_id: session.id,
                working_directory: session.cwd.clone(),
            });
        }
    }

    let pair = native_pty_system()
        .openpty(PtySize {
            rows: rows.max(1),
            cols: cols.max(1),
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|error| format!("Could not create a terminal: {error}"))?;

    let shell = configured_shell();
    let mut command = CommandBuilder::new(&shell);
    #[cfg(not(target_os = "windows"))]
    command.arg("-l");
    command.cwd(&directory);
    command.env("TERM", "xterm-256color");
    command.env("COLORTERM", "truecolor");

    let mut child = pair
        .slave
        .spawn_command(command)
        .map_err(|error| format!("Could not start {shell}: {error}"))?;
    let killer = child.clone_killer();
    let mut reader = pair
        .master
        .try_clone_reader()
        .map_err(|error| format!("Could not read terminal output: {error}"))?;
    let writer = pair
        .master
        .take_writer()
        .map_err(|error| format!("Could not write to the terminal: {error}"))?;

    let session_id = state.0.next_id.fetch_add(1, Ordering::Relaxed) + 1;
    let info = TerminalSessionInfo {
        session_id,
        working_directory: canonical_directory.clone(),
    };
    let manager = state.inner().clone();
    {
        let mut sessions = manager
            .0
            .sessions
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        sessions.insert(
            session_id,
            TerminalSession {
                id: session_id,
                cwd: canonical_directory,
                writer,
                master: pair.master,
                killer,
            },
        );
    }

    let output_app = app.clone();
    std::thread::spawn(move || {
        let mut buffer = vec![0_u8; 8 * 1024];
        loop {
            match reader.read(&mut buffer) {
                Ok(0) => break,
                Ok(count) => {
                    let _ = output_app.emit(
                        "zerus-terminal-output",
                        TerminalOutput {
                            session_id,
                            data: buffer[..count].to_vec(),
                        },
                    );
                }
                Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
    });

    let exit_app = app;
    std::thread::spawn(move || {
        let result = child.wait();
        {
            let mut sessions = manager
                .0
                .sessions
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            sessions.remove(&session_id);
        }
        let payload = match result {
            Ok(status) => TerminalExit {
                session_id,
                exit_code: Some(status.exit_code()),
                signal: status.signal().map(str::to_string),
                error: None,
            },
            Err(error) => TerminalExit {
                session_id,
                exit_code: None,
                signal: None,
                error: Some(error.to_string()),
            },
        };
        let _ = exit_app.emit("zerus-terminal-exit", payload);
    });

    Ok(info)
}

#[tauri::command]
fn terminal_write(
    state: tauri::State<'_, TerminalManager>,
    session_id: u64,
    data: String,
) -> Result<(), String> {
    let mut sessions = state
        .0
        .sessions
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let session = sessions
        .get_mut(&session_id)
        .ok_or_else(|| "The terminal session is no longer running".to_string())?;
    session
        .writer
        .write_all(data.as_bytes())
        .and_then(|_| session.writer.flush())
        .map_err(|error| error.to_string())
}

#[tauri::command]
fn terminal_resize(
    state: tauri::State<'_, TerminalManager>,
    session_id: u64,
    rows: u16,
    cols: u16,
) -> Result<(), String> {
    let sessions = state
        .0
        .sessions
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let session = sessions
        .get(&session_id)
        .ok_or_else(|| "The terminal session is no longer running".to_string())?;
    session
        .master
        .resize(PtySize {
            rows: rows.max(1),
            cols: cols.max(1),
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|error| error.to_string())
}

#[tauri::command]
fn terminal_stop(state: tauri::State<'_, TerminalManager>, session_id: u64) -> Result<(), String> {
    let mut sessions = state
        .0
        .sessions
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let mut session = sessions
        .remove(&session_id)
        .ok_or_else(|| "The terminal session is no longer running".to_string())?;
    session.killer.kill().map_err(|error| error.to_string())
}

fn write_new_vault_file_impl(
    root: &Path,
    relative_path: &str,
    content: &[u8],
) -> Result<(), String> {
    let segments: Vec<&str> = relative_path.split(['/', '\\']).collect();
    if segments.is_empty()
        || segments
            .iter()
            .any(|segment| segment.is_empty() || *segment == "." || *segment == "..")
    {
        return Err("Unsafe vault-relative path".to_string());
    }

    let mut parent = root.canonicalize().map_err(|error| error.to_string())?;
    for segment in &segments[..segments.len() - 1] {
        let next = parent.join(segment);
        match fs::symlink_metadata(&next) {
            Ok(metadata) => {
                if metadata.file_type().is_symlink() || !metadata.is_dir() {
                    return Err("Vault path contains a symlink or non-directory".to_string());
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                fs::create_dir(&next).map_err(|error| error.to_string())?;
            }
            Err(error) => return Err(error.to_string()),
        }
        parent = next;
    }

    let target = parent.join(segments[segments.len() - 1]);
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(target)
        .map_err(|error| error.to_string())?;
    file.write_all(content).map_err(|error| error.to_string())?;
    file.sync_all().map_err(|error| error.to_string())
}

#[tauri::command]
fn write_new_vault_file(
    root: String,
    relative_path: String,
    content: String,
) -> Result<(), String> {
    write_new_vault_file_impl(Path::new(&root), &relative_path, content.as_bytes())
}

#[tauri::command]
fn canonicalize_path(path: String) -> Result<String, String> {
    Path::new(&path)
        .canonicalize()
        .map(|path| path.to_string_lossy().into_owned())
        .map_err(|error| error.to_string())
}

fn safe_file_name(name: &str) -> bool {
    !name.is_empty()
        && name != "."
        && name != ".."
        && !name.chars().any(|value| matches!(value, '/' | '\\' | '\0'))
}

#[tauri::command]
fn copy_file_into_vault(
    source: String,
    root: String,
    relative_directory: String,
    file_name: String,
) -> Result<String, String> {
    if !safe_file_name(&file_name) {
        return Err("Unsafe document filename".to_string());
    }
    let source = Path::new(&source)
        .canonicalize()
        .map_err(|error| format!("Could not read the source document: {error}"))?;
    if !source.is_file() {
        return Err("The selected document is not a regular file".to_string());
    }
    let root = Path::new(&root)
        .canonicalize()
        .map_err(|error| format!("Could not open the vault: {error}"))?;
    let segments: Vec<&str> = relative_directory
        .split('/')
        .filter(|segment| !segment.is_empty())
        .collect();
    if segments.iter().any(|segment| !safe_file_name(segment)) {
        return Err("Unsafe vault-relative directory".to_string());
    }
    let mut directory = root.clone();
    for segment in segments {
        directory.push(segment);
        let metadata = fs::symlink_metadata(&directory)
            .map_err(|error| format!("Could not inspect the destination: {error}"))?;
        if metadata.file_type().is_symlink() || !metadata.is_dir() {
            return Err("The destination contains a symlink or non-directory".to_string());
        }
    }
    let name_path = Path::new(&file_name);
    let stem = name_path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("Document");
    let extension = name_path.extension().and_then(|value| value.to_str());
    for index in 0_u32.. {
        let suffix = if index == 0 {
            String::new()
        } else {
            format!(" {}", index + 1)
        };
        let candidate_name = match extension {
            Some(extension) => format!("{stem}{suffix}.{extension}"),
            None => format!("{stem}{suffix}"),
        };
        let target = directory.join(&candidate_name);
        if target.exists() {
            continue;
        }
        fs::copy(&source, &target)
            .map_err(|error| format!("Could not copy the document into the vault: {error}"))?;
        let relative = if relative_directory.is_empty() {
            candidate_name
        } else {
            format!("{relative_directory}/{candidate_name}")
        };
        return Ok(relative);
    }
    unreachable!()
}

#[tauri::command]
fn take_pending_open_files(state: tauri::State<'_, PendingOpenFiles>) -> Vec<String> {
    let mut paths = state.0.lock().unwrap_or_else(|error| error.into_inner());
    std::mem::take(&mut *paths)
}

#[cfg(any(target_os = "windows", test))]
fn desktop_open_paths(args: &[String], cwd: &Path) -> Vec<String> {
    args.iter()
        .skip(1)
        .filter_map(|argument| {
            let candidate = PathBuf::from(argument);
            let candidate = if candidate.is_absolute() {
                candidate
            } else {
                cwd.join(candidate)
            };
            candidate
                .is_file()
                .then(|| candidate.canonicalize().unwrap_or(candidate))
        })
        .map(|path| path.to_string_lossy().into_owned())
        .collect()
}

fn enqueue_desktop_open_files(app: &tauri::AppHandle, paths: Vec<String>) {
    if paths.is_empty() {
        return;
    }
    app.state::<PendingOpenFiles>()
        .0
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .extend(paths);
    let _ = app.emit("zerus-open-files", ());
}

#[tauri::command]
fn reveal_in_file_manager(path: String) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    let status = std::process::Command::new("open")
        .args(["-R", &path])
        .status();

    #[cfg(target_os = "windows")]
    let status = std::process::Command::new("explorer")
        .arg(format!("/select,{}", path))
        .status();

    #[cfg(target_os = "linux")]
    let status = {
        let parent = std::path::Path::new(&path)
            .parent()
            .ok_or_else(|| "The note has no parent folder".to_string())?;
        std::process::Command::new("xdg-open").arg(parent).status()
    };

    #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
    let status = Err::<std::process::ExitStatus, _>(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "Revealing files is not supported on this platform",
    ));

    status
        .map_err(|error| error.to_string())?
        .success()
        .then_some(())
        .ok_or_else(|| "The file manager could not reveal the note".to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default();
    #[cfg(target_os = "windows")]
    let builder = builder.plugin(tauri_plugin_single_instance::init(|app, args, cwd| {
        enqueue_desktop_open_files(app, desktop_open_paths(&args, Path::new(&cwd)));
        if let Some(window) = app.get_webview_window("main") {
            let _ = window.show();
            let _ = window.unminimize();
            let _ = window.set_focus();
        }
    }));

    let app = builder
        .manage(PendingOpenFiles::default())
        .manage(TerminalManager::default())
        .manage(LocalAiRuntimeState::default())
        .manage(CloudAiState::default())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_mobile_vault::init())
        .invoke_handler(tauri::generate_handler![
            reveal_in_file_manager,
            write_new_vault_file,
            copy_file_into_vault,
            canonicalize_path,
            take_pending_open_files,
            terminal_status,
            terminal_start,
            terminal_write,
            terminal_resize,
            terminal_stop,
            local_ai_status,
            local_ai_download_model,
            local_ai_chat,
            cloud_ai_models,
            cloud_ai_chat,
            cloud_ai_configure,
            cli_status,
            cli_install,
            cli_register_vault,
            cli_install_skill,
            cli_export_skill,
            cli_migration_preview,
            cli_migration_apply
        ])
        .setup(|app| {
            #[cfg(target_os = "windows")]
            {
                let args = std::env::args().collect::<Vec<_>>();
                let cwd = std::env::current_dir().unwrap_or_default();
                enqueue_desktop_open_files(app.handle(), desktop_open_paths(&args, &cwd));
            }
            #[cfg(desktop)]
            {
                app.handle().plugin(tauri_plugin_process::init())?;
                app.handle()
                    .plugin(tauri_plugin_updater::Builder::new().build())?;
            }
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application");

    app.run(|app_handle, event| {
        #[cfg(target_os = "macos")]
        if let tauri::RunEvent::Opened { urls } = event {
            let paths: Vec<String> = urls
                .into_iter()
                .filter_map(|url| url.to_file_path().ok())
                .map(|path| path.to_string_lossy().into_owned())
                .collect();
            if paths.is_empty() {
                return;
            }

            enqueue_desktop_open_files(app_handle, paths);
        }
    });
}

#[cfg(test)]
mod tests {
    #[cfg(not(target_os = "macos"))]
    use super::LOCAL_AI_MODEL_SIZE;
    use super::{
        cli_export_skill, cloud_ai_request_body, copy_file_into_vault, desktop_open_paths,
        local_ai_model_downloaded, local_ai_request_body, normalized_cloud_ai_base_url,
        sync_opened_vault_record, write_new_vault_file_impl, LocalAiChatRequest, LocalAiMessage,
    };
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn test_root(name: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should follow the Unix epoch")
            .as_nanos();
        std::env::temp_dir().join(format!("zerus-{name}-{}-{nonce}", std::process::id()))
    }

    #[test]
    fn desktop_open_paths_keeps_existing_files_and_resolves_relative_paths() {
        let root = test_root("desktop-open-paths");
        fs::create_dir_all(&root).expect("create test root");
        let note = root.join("note.md");
        fs::write(&note, "# Note").expect("write note");
        let args = vec![
            "zerus".to_string(),
            "note.md".to_string(),
            "missing.md".to_string(),
        ];

        assert_eq!(
            desktop_open_paths(&args, &root),
            vec![note.canonicalize().unwrap().to_string_lossy().into_owned()]
        );

        fs::remove_dir_all(root).expect("remove test root");
    }

    #[test]
    fn local_ai_request_uses_low_temperature_and_default_reasoning() {
        let body = local_ai_request_body(LocalAiChatRequest {
            system_prompt: "Current note context".to_string(),
            messages: vec![LocalAiMessage {
                role: "user".to_string(),
                content: "Summarize this note".to_string(),
                image_paths: Vec::new(),
            }],
        })
        .expect("build local AI request");

        assert_eq!(body["temperature"], serde_json::json!(0.2));
        assert_eq!(body["reasoning_effort"], "medium");
        assert_eq!(body["messages"][0]["role"], "system");
    }

    #[test]
    fn cloud_ai_request_uses_the_selected_model() {
        let body = cloud_ai_request_body(
            LocalAiChatRequest {
                system_prompt: "Current note context".to_string(),
                messages: vec![LocalAiMessage {
                    role: "user".to_string(),
                    content: "Summarize this note".to_string(),
                    image_paths: Vec::new(),
                }],
            },
            "anthropic/claude-sonnet-4",
        )
        .expect("build cloud AI request");

        assert_eq!(body["model"], "anthropic/claude-sonnet-4");
        assert_eq!(body["messages"][0]["role"], "system");
        assert!(body.get("reasoning_effort").is_none());
    }

    #[test]
    fn cloud_ai_provider_requires_https_except_for_loopback() {
        assert_eq!(
            normalized_cloud_ai_base_url("https://openrouter.ai/api/v1/ ").unwrap(),
            "https://openrouter.ai/api/v1"
        );
        assert!(normalized_cloud_ai_base_url("http://openrouter.ai/api/v1").is_err());
        assert!(normalized_cloud_ai_base_url("http://127.0.0.1:11434/v1").is_ok());
    }

    #[test]
    fn local_ai_request_sends_validated_local_images() {
        let root = test_root("local-ai-image");
        fs::create_dir_all(&root).expect("create image test root");
        let image = root.join("context.png");
        fs::write(&image, b"synthetic image fixture").expect("write image fixture");

        let body = local_ai_request_body(LocalAiChatRequest {
            system_prompt: "Current note context".to_string(),
            messages: vec![LocalAiMessage {
                role: "user".to_string(),
                content: "Describe this image".to_string(),
                image_paths: vec![image.to_string_lossy().into_owned()],
            }],
        })
        .expect("build multimodal request");

        assert_eq!(body["messages"][1]["content"][1]["type"], "image_url");
        assert_eq!(
            body["messages"][1]["content"][1]["image_url"]["url"],
            image.canonicalize().unwrap().to_string_lossy().as_ref()
        );

        fs::remove_dir_all(root).expect("remove image test root");
    }

    #[test]
    fn local_ai_model_is_installed_only_at_the_verified_size() {
        let root = test_root("local-ai-model-status");
        fs::create_dir_all(&root).expect("create model test root");

        #[cfg(target_os = "macos")]
        {
            let model = root.join("mlx");
            fs::create_dir_all(&model).expect("create MLX cache fixture");
            assert!(!local_ai_model_downloaded(&model));
            fs::write(model.join(super::mlx_ai_native::READY_MARKER), b"")
                .expect("write MLX ready marker");
            assert!(local_ai_model_downloaded(&model));
        }

        #[cfg(not(target_os = "macos"))]
        {
            let model = root.join("gemma.litertlm");
            let file = fs::File::create(&model).expect("create sparse model fixture");
            file.set_len(LOCAL_AI_MODEL_SIZE - 1)
                .expect("set incomplete model size");
            assert!(!local_ai_model_downloaded(&model));
            file.set_len(LOCAL_AI_MODEL_SIZE)
                .expect("set complete model size");
            assert!(local_ai_model_downloaded(&model));
        }

        fs::remove_dir_all(root).expect("remove model test root");
    }

    #[test]
    fn creates_a_new_file_but_never_overwrites_it() {
        let root = test_root("create-new");
        fs::create_dir(&root).expect("create test vault");
        write_new_vault_file_impl(&root, "inbox/Note.md", b"first").expect("create new note");
        assert!(write_new_vault_file_impl(&root, "inbox/Note.md", b"second").is_err());
        assert_eq!(
            fs::read_to_string(root.join("inbox/Note.md")).expect("read note"),
            "first"
        );
        fs::remove_dir_all(root).expect("remove test vault");
    }

    #[test]
    fn opened_vault_updates_its_registered_path_and_becomes_default() {
        let original = test_root("registry-original");
        let moved = test_root("registry-moved");
        let other_path = test_root("registry-other");
        fs::create_dir(&original).expect("create original vault");
        fs::create_dir(&moved).expect("create moved vault");
        fs::create_dir(&other_path).expect("create other vault");
        let manifest = zerus_core::load_or_create_manifest(&original).expect("create manifest");
        zerus_core::write_vault_manifest(&moved, &manifest).expect("copy manifest");
        let other =
            zerus_core::load_or_create_manifest(&other_path).expect("create other manifest");
        let mut registry = zerus_core::VaultRegistry {
            version: 1,
            default_vault_id: Some(other.vault_id),
            vaults: vec![
                zerus_core::VaultRecord {
                    id: manifest.vault_id,
                    name: "Zerus".to_string(),
                    path: original.clone(),
                },
                zerus_core::VaultRecord {
                    id: other.vault_id,
                    name: "Other".to_string(),
                    path: other_path.clone(),
                },
            ],
        };

        let record = sync_opened_vault_record(&mut registry, &manifest, moved.clone());

        assert_eq!(record.name, "Zerus");
        assert_eq!(record.path, moved);
        assert_eq!(registry.default_vault_id, Some(manifest.vault_id));
        assert_eq!(
            registry
                .vaults
                .iter()
                .filter(|vault| vault.id == manifest.vault_id)
                .count(),
            1
        );

        fs::remove_dir_all(original).expect("remove original vault");
        fs::remove_dir_all(record.path).expect("remove moved vault");
        fs::remove_dir_all(other_path).expect("remove other vault");
    }

    #[test]
    fn opened_vault_gets_a_distinct_name_when_the_folder_name_is_taken() {
        let first_parent = test_root("registry-first-parent");
        let second_parent = test_root("registry-second-parent");
        let first = first_parent.join("Zerus");
        let second = second_parent.join("Zerus");
        fs::create_dir_all(&first).expect("create first vault");
        fs::create_dir_all(&second).expect("create second vault");
        let first_manifest =
            zerus_core::load_or_create_manifest(&first).expect("create first manifest");
        let second_manifest =
            zerus_core::load_or_create_manifest(&second).expect("create second manifest");
        let mut registry = zerus_core::VaultRegistry {
            version: 1,
            default_vault_id: Some(first_manifest.vault_id),
            vaults: vec![zerus_core::VaultRecord {
                id: first_manifest.vault_id,
                name: "Zerus".to_string(),
                path: first,
            }],
        };

        let record = sync_opened_vault_record(&mut registry, &second_manifest, second);

        assert_eq!(record.name, "Zerus (2)");
        assert_eq!(registry.default_vault_id, Some(second_manifest.vault_id));
        assert_eq!(registry.vaults.len(), 2);

        fs::remove_dir_all(first_parent).expect("remove first parent");
        fs::remove_dir_all(second_parent).expect("remove second parent");
    }

    #[cfg(unix)]
    #[test]
    fn rejects_a_type_directory_that_is_a_symlink() {
        use std::os::unix::fs::symlink;

        let root = test_root("symlink-vault");
        let outside = test_root("symlink-outside");
        fs::create_dir(&root).expect("create test vault");
        fs::create_dir(&outside).expect("create outside folder");
        symlink(&outside, root.join("research")).expect("create symlinked type");

        assert!(write_new_vault_file_impl(&root, "research/Note.md", b"outside").is_err());
        assert!(!outside.join("Note.md").exists());

        fs::remove_dir_all(root).expect("remove test vault");
        fs::remove_dir_all(outside).expect("remove outside folder");
    }

    #[test]
    fn copies_documents_without_overwriting_an_existing_name() {
        let root = test_root("copy-vault");
        let source_dir = test_root("copy-source");
        fs::create_dir_all(root.join("work")).expect("create vault type");
        fs::create_dir(&source_dir).expect("create source folder");
        let source = source_dir.join("Proposal.pdf");
        fs::write(&source, b"portable document").expect("write source");
        fs::write(root.join("work/Proposal.pdf"), b"existing").expect("write collision");

        let copied = copy_file_into_vault(
            source.to_string_lossy().into_owned(),
            root.to_string_lossy().into_owned(),
            "work".to_string(),
            "Proposal.pdf".to_string(),
        )
        .expect("copy document");
        assert_eq!(copied, "work/Proposal 2.pdf");
        assert_eq!(
            fs::read(root.join(&copied)).expect("read copied document"),
            b"portable document"
        );
        assert_eq!(
            fs::read(root.join("work/Proposal.pdf")).expect("read existing document"),
            b"existing"
        );

        fs::remove_dir_all(root).expect("remove test vault");
        fs::remove_dir_all(source_dir).expect("remove source folder");
    }

    #[test]
    fn exports_the_generic_skill_as_markdown() {
        let root = test_root("skill-export");
        fs::create_dir(&root).expect("create export folder");
        let requested = root.join("zerus-skill");

        let saved =
            cli_export_skill(requested.to_string_lossy().into_owned()).expect("export Zerus skill");
        let expected = root.join("zerus-skill.md");
        assert_eq!(PathBuf::from(saved), expected);
        let contents = fs::read_to_string(&expected).expect("read exported skill");
        assert!(contents.contains("name: zerus"));
        assert!(contents.contains("Never edit `grimoire-*` properties directly."));

        fs::remove_dir_all(root).expect("remove export folder");
    }
}
