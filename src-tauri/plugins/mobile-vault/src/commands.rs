use tauri::{command, AppHandle, Runtime};

use crate::models::*;
use crate::MobileVaultExt;
use crate::Result;

#[command]
pub(crate) async fn pick_vault_folder<R: Runtime>(
    app: AppHandle<R>,
) -> Result<VaultLocationResponse> {
    app.mobile_vault().pick_vault_folder()
}

#[command]
pub(crate) async fn restore_vault_folder<R: Runtime>(
    app: AppHandle<R>,
) -> Result<VaultLocationResponse> {
    app.mobile_vault().restore_vault_folder()
}

#[command]
pub(crate) async fn clear_vault_folder<R: Runtime>(app: AppHandle<R>) -> Result<()> {
    app.mobile_vault().clear_vault_folder()
}

#[command]
pub(crate) async fn pick_external_notes<R: Runtime>(
    app: AppHandle<R>,
) -> Result<PickedFilesResponse> {
    app.mobile_vault().pick_external_notes()
}

#[command]
pub(crate) async fn pick_files<R: Runtime>(app: AppHandle<R>) -> Result<PickedFilesResponse> {
    app.mobile_vault().pick_files()
}

#[command]
pub(crate) async fn pick_external_folder<R: Runtime>(
    app: AppHandle<R>,
) -> Result<PickedFilesResponse> {
    app.mobile_vault().pick_external_folder()
}

#[command]
pub(crate) async fn open_file<R: Runtime>(
    app: AppHandle<R>,
    request: OpenFileRequest,
) -> Result<()> {
    app.mobile_vault().open_file(request)
}

#[command]
pub(crate) async fn cloud_ai_status<R: Runtime>(
    app: AppHandle<R>,
) -> Result<CloudAiStatusResponse> {
    app.mobile_vault().cloud_ai_status()
}

#[command]
pub(crate) async fn configure_cloud_ai<R: Runtime>(
    app: AppHandle<R>,
    request: CloudAiConfigureRequest,
) -> Result<CloudAiStatusResponse> {
    app.mobile_vault().configure_cloud_ai(request)
}

#[command]
pub(crate) async fn connect_openrouter<R: Runtime>(
    app: AppHandle<R>,
) -> Result<CloudAiStatusResponse> {
    app.mobile_vault().connect_openrouter()
}

#[command]
pub(crate) async fn cloud_ai_models<R: Runtime>(
    app: AppHandle<R>,
) -> Result<CloudAiModelsResponse> {
    app.mobile_vault().cloud_ai_models()
}

#[command]
pub(crate) async fn generate_cloud_ai<R: Runtime>(
    app: AppHandle<R>,
    request: CloudAiGenerateRequest,
) -> Result<CloudAiGenerateResponse> {
    app.mobile_vault().generate_cloud_ai(request)
}

#[command]
pub(crate) async fn stop_cloud_ai<R: Runtime>(app: AppHandle<R>) -> Result<()> {
    app.mobile_vault().stop_cloud_ai()
}

#[command]
pub(crate) async fn start_speech_recognition<R: Runtime>(
    app: AppHandle<R>,
    request: SpeechRecognitionStartRequest,
) -> Result<SpeechRecognitionStatusResponse> {
    app.mobile_vault().start_speech_recognition(request)
}

#[command]
pub(crate) async fn speech_recognition_progress<R: Runtime>(
    app: AppHandle<R>,
) -> Result<SpeechRecognitionProgressResponse> {
    app.mobile_vault().speech_recognition_progress()
}

#[command]
pub(crate) async fn stop_speech_recognition<R: Runtime>(
    app: AppHandle<R>,
) -> Result<SpeechRecognitionResponse> {
    app.mobile_vault().stop_speech_recognition()
}

#[command]
pub(crate) async fn cancel_speech_recognition<R: Runtime>(app: AppHandle<R>) -> Result<()> {
    app.mobile_vault().cancel_speech_recognition()
}

#[command]
pub(crate) async fn device_name<R: Runtime>(app: AppHandle<R>) -> Result<DeviceNameResponse> {
    app.mobile_vault().device_name()
}
