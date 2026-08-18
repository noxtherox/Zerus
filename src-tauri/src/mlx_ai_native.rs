use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use tauri::Manager;

pub const READY_MARKER: &str = "zerus-qwen3-1.7b-4bit.ready";

#[derive(Default)]
pub struct NativeAiRuntime(Mutex<RuntimeState>);

#[derive(Default)]
struct RuntimeState {
    process: Option<SidecarProcess>,
    next_id: u64,
}

struct SidecarProcess {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
    cache_path: PathBuf,
}

impl Drop for SidecarProcess {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SidecarRequest<'a> {
    id: u64,
    command: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    system_prompt: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    messages: Option<&'a serde_json::Value>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SidecarResponse {
    id: u64,
    #[serde(rename = "type")]
    kind: String,
    content: Option<String>,
    reasoning: Option<String>,
    message: Option<String>,
    downloaded_bytes: Option<i64>,
    total_bytes: Option<i64>,
    phase: Option<String>,
}

pub struct ChatResponse {
    pub content: String,
    pub reasoning: Option<String>,
}

pub struct DownloadProgress {
    pub downloaded_bytes: u64,
    pub total_bytes: u64,
    pub phase: String,
}

fn sidecar_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let bundled = app
        .path()
        .resource_dir()
        .map_err(|error| format!("Could not locate Zerus's MLX resources: {error}"))?
        .join("vendor/mlx/zerus-mlx");
    if bundled.is_file() {
        return Ok(bundled);
    }
    let development = Path::new(env!("CARGO_MANIFEST_DIR")).join("vendor/mlx/zerus-mlx");
    development
        .is_file()
        .then_some(development)
        .ok_or_else(|| "The bundled Zerus MLX runtime is missing".to_string())
}

pub fn available(app: &tauri::AppHandle) -> bool {
    sidecar_path(app).is_ok()
}

fn spawn(app: &tauri::AppHandle, cache_path: &Path) -> Result<SidecarProcess, String> {
    std::fs::create_dir_all(cache_path)
        .map_err(|error| format!("Could not create the MLX model cache: {error}"))?;
    let mut child = Command::new(sidecar_path(app)?)
        .arg("--cache-dir")
        .arg(cache_path)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("Could not start the Zerus MLX runtime: {error}"))?;
    let stdin = child
        .stdin
        .take()
        .ok_or_else(|| "The MLX runtime did not open its input stream".to_string())?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "The MLX runtime did not open its output stream".to_string())?;
    Ok(SidecarProcess {
        child,
        stdin,
        stdout: BufReader::new(stdout),
        cache_path: cache_path.to_path_buf(),
    })
}

fn send(
    app: &tauri::AppHandle,
    state: &NativeAiRuntime,
    cache_path: &Path,
    command: &str,
    system_prompt: Option<&str>,
    messages: Option<&serde_json::Value>,
    mut on_progress: impl FnMut(DownloadProgress),
) -> Result<SidecarResponse, String> {
    let mut state = state.0.lock().unwrap_or_else(|error| error.into_inner());
    let needs_spawn = match state.process.as_mut() {
        Some(process) => {
            process.cache_path != cache_path || process.child.try_wait().ok().flatten().is_some()
        }
        None => true,
    };
    if needs_spawn {
        state.process = Some(spawn(app, cache_path)?);
    }
    state.next_id = state.next_id.wrapping_add(1).max(1);
    let id = state.next_id;
    let request = serde_json::to_string(&SidecarRequest {
        id,
        command,
        system_prompt,
        messages,
    })
    .map_err(|error| format!("Could not encode the MLX request: {error}"))?;
    let process = state.process.as_mut().expect("MLX sidecar was initialized");
    writeln!(process.stdin, "{request}")
        .and_then(|_| process.stdin.flush())
        .map_err(|error| format!("Could not send the request to MLX: {error}"))?;

    let mut last_progress_bytes = 0_u64;
    let mut last_progress_phase = String::new();
    loop {
        let mut line = String::new();
        let read = process
            .stdout
            .read_line(&mut line)
            .map_err(|error| format!("Could not read the MLX response: {error}"))?;
        if read == 0 {
            return Err("The Zerus MLX runtime stopped unexpectedly".to_string());
        }
        let Ok(response) = serde_json::from_str::<SidecarResponse>(&line) else {
            continue;
        };
        if response.id != id {
            continue;
        }
        match response.kind.as_str() {
            "progress" => {
                let downloaded_bytes = response.downloaded_bytes.unwrap_or(0).max(0) as u64;
                let total_bytes = response.total_bytes.unwrap_or(0).max(0) as u64;
                let phase = response.phase.unwrap_or_else(|| "downloading".to_string());
                let should_emit = phase != last_progress_phase
                    || downloaded_bytes >= total_bytes && total_bytes > 0
                    || downloaded_bytes.saturating_sub(last_progress_bytes) >= 8 * 1024 * 1024;
                if should_emit {
                    last_progress_bytes = downloaded_bytes;
                    last_progress_phase.clone_from(&phase);
                    on_progress(DownloadProgress {
                        downloaded_bytes,
                        total_bytes,
                        phase,
                    });
                }
            }
            "result" => return Ok(response),
            "error" => {
                return Err(response
                    .message
                    .unwrap_or_else(|| "The MLX runtime returned an unknown error".to_string()));
            }
            _ => continue,
        }
    }
}

pub fn download(
    app: &tauri::AppHandle,
    state: &NativeAiRuntime,
    cache_path: &Path,
    on_progress: impl FnMut(DownloadProgress),
) -> Result<(), String> {
    send(app, state, cache_path, "download", None, None, on_progress)?;
    Ok(())
}

pub fn chat(
    app: &tauri::AppHandle,
    state: &NativeAiRuntime,
    cache_path: &Path,
    system_prompt: &str,
    messages: &serde_json::Value,
) -> Result<ChatResponse, String> {
    let response = send(
        app,
        state,
        cache_path,
        "chat",
        Some(system_prompt),
        Some(messages),
        |_| {},
    )?;
    let content = response
        .content
        .filter(|content| !content.trim().is_empty())
        .ok_or_else(|| "Qwen returned an empty response".to_string())?;
    Ok(ChatResponse {
        content,
        reasoning: response.reasoning,
    })
}
