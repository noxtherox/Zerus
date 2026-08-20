use serde::de::DeserializeOwned;
use tauri::{
    plugin::{PluginApi, PluginHandle},
    AppHandle, Runtime,
};

use crate::models::*;

#[cfg(target_os = "ios")]
tauri::ios_plugin_binding!(init_plugin_mobile_vault);

// initializes the Kotlin or Swift plugin classes
pub fn init<R: Runtime, C: DeserializeOwned>(
    _app: &AppHandle<R>,
    api: PluginApi<R, C>,
) -> crate::Result<MobileVault<R>> {
    #[cfg(target_os = "android")]
    let handle = api.register_android_plugin("", "ExamplePlugin")?;
    #[cfg(target_os = "ios")]
    let handle = api.register_ios_plugin(init_plugin_mobile_vault)?;
    Ok(MobileVault(handle))
}

/// Access to the mobile-vault APIs.
pub struct MobileVault<R: Runtime>(PluginHandle<R>);

impl<R: Runtime> MobileVault<R> {
    pub fn pick_vault_folder(&self) -> crate::Result<VaultLocationResponse> {
        self.0
            .run_mobile_plugin("pickVaultFolder", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn restore_vault_folder(&self) -> crate::Result<VaultLocationResponse> {
        self.0
            .run_mobile_plugin("restoreVaultFolder", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn clear_vault_folder(&self) -> crate::Result<()> {
        self.0
            .run_mobile_plugin("clearVaultFolder", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn pick_external_notes(&self) -> crate::Result<PickedFilesResponse> {
        self.0
            .run_mobile_plugin("pickExternalNotes", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn pick_files(&self) -> crate::Result<PickedFilesResponse> {
        self.0
            .run_mobile_plugin("pickFiles", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn pick_external_folder(&self) -> crate::Result<PickedFilesResponse> {
        self.0
            .run_mobile_plugin("pickExternalFolder", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn open_file(&self, request: OpenFileRequest) -> crate::Result<()> {
        self.0
            .run_mobile_plugin("openFile", request)
            .map_err(Into::into)
    }

    pub fn cloud_ai_status(&self) -> crate::Result<CloudAiStatusResponse> {
        self.0
            .run_mobile_plugin("cloudAIStatus", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn configure_cloud_ai(
        &self,
        request: CloudAiConfigureRequest,
    ) -> crate::Result<CloudAiStatusResponse> {
        self.0
            .run_mobile_plugin("configureCloudAI", request)
            .map_err(Into::into)
    }

    pub fn connect_openrouter(&self) -> crate::Result<CloudAiStatusResponse> {
        self.0
            .run_mobile_plugin("connectOpenRouter", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn cloud_ai_models(&self) -> crate::Result<CloudAiModelsResponse> {
        self.0
            .run_mobile_plugin("cloudAIModels", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn generate_cloud_ai(
        &self,
        request: CloudAiGenerateRequest,
    ) -> crate::Result<CloudAiGenerateResponse> {
        self.0
            .run_mobile_plugin("generateCloudAI", request)
            .map_err(Into::into)
    }

    pub fn stop_cloud_ai(&self) -> crate::Result<()> {
        self.0
            .run_mobile_plugin("stopCloudAI", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn start_speech_recognition(
        &self,
        request: SpeechRecognitionStartRequest,
    ) -> crate::Result<SpeechRecognitionStatusResponse> {
        self.0
            .run_mobile_plugin("startSpeechRecognition", request)
            .map_err(Into::into)
    }

    pub fn speech_recognition_progress(&self) -> crate::Result<SpeechRecognitionProgressResponse> {
        self.0
            .run_mobile_plugin("speechRecognitionProgress", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn stop_speech_recognition(&self) -> crate::Result<SpeechRecognitionResponse> {
        self.0
            .run_mobile_plugin("stopSpeechRecognition", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn cancel_speech_recognition(&self) -> crate::Result<()> {
        self.0
            .run_mobile_plugin("cancelSpeechRecognition", EmptyRequest::default())
            .map_err(Into::into)
    }

    pub fn device_name(&self) -> crate::Result<DeviceNameResponse> {
        self.0
            .run_mobile_plugin("deviceName", EmptyRequest::default())
            .map_err(Into::into)
    }
}
