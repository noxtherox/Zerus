use serde::de::DeserializeOwned;
use tauri::{plugin::PluginApi, AppHandle, Runtime};

use crate::models::*;

pub fn init<R: Runtime, C: DeserializeOwned>(
    app: &AppHandle<R>,
    _api: PluginApi<R, C>,
) -> crate::Result<MobileVault<R>> {
    Ok(MobileVault(app.clone()))
}

/// Access to the mobile-vault APIs.
pub struct MobileVault<R: Runtime>(AppHandle<R>);

impl<R: Runtime> MobileVault<R> {
    pub fn pick_vault_folder(&self) -> crate::Result<VaultLocationResponse> {
        Ok(VaultLocationResponse::default())
    }

    pub fn restore_vault_folder(&self) -> crate::Result<VaultLocationResponse> {
        Ok(VaultLocationResponse::default())
    }

    pub fn clear_vault_folder(&self) -> crate::Result<()> {
        Ok(())
    }

    pub fn pick_external_notes(&self) -> crate::Result<PickedFilesResponse> {
        Ok(PickedFilesResponse::default())
    }

    pub fn pick_files(&self) -> crate::Result<PickedFilesResponse> {
        Ok(PickedFilesResponse::default())
    }

    pub fn pick_external_folder(&self) -> crate::Result<PickedFilesResponse> {
        Ok(PickedFilesResponse::default())
    }

    pub fn open_file(&self, _request: OpenFileRequest) -> crate::Result<()> {
        Ok(())
    }

    pub fn cloud_ai_status(&self) -> crate::Result<CloudAiStatusResponse> {
        Err(crate::Error::Unavailable(
            "Cloud chat configuration is only available in the iOS app".into(),
        ))
    }

    pub fn configure_cloud_ai(
        &self,
        _request: CloudAiConfigureRequest,
    ) -> crate::Result<CloudAiStatusResponse> {
        self.cloud_ai_status()
    }

    pub fn generate_cloud_ai(
        &self,
        _request: CloudAiGenerateRequest,
    ) -> crate::Result<CloudAiGenerateResponse> {
        Err(crate::Error::Unavailable(
            "Cloud chat is only available in the iOS app".into(),
        ))
    }

    pub fn start_speech_recognition(
        &self,
        _request: SpeechRecognitionStartRequest,
    ) -> crate::Result<SpeechRecognitionStatusResponse> {
        Err(crate::Error::Unavailable(
            "On-device speech recognition is only available in the iOS app".into(),
        ))
    }

    pub fn speech_recognition_progress(&self) -> crate::Result<SpeechRecognitionProgressResponse> {
        Err(crate::Error::Unavailable(
            "On-device speech recognition is only available in the iOS app".into(),
        ))
    }

    pub fn stop_speech_recognition(&self) -> crate::Result<SpeechRecognitionResponse> {
        Err(crate::Error::Unavailable(
            "On-device speech recognition is only available in the iOS app".into(),
        ))
    }

    pub fn cancel_speech_recognition(&self) -> crate::Result<()> {
        Ok(())
    }

    pub fn device_name(&self) -> crate::Result<DeviceNameResponse> {
        let name = std::env::var("HOSTNAME")
            .or_else(|_| std::env::var("COMPUTERNAME"))
            .unwrap_or_else(|_| "Desktop".into());
        Ok(DeviceNameResponse { name })
    }
}
