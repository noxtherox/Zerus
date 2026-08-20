use serde::{Deserialize, Serialize};

#[derive(Debug, Default, Deserialize, Serialize)]
pub struct EmptyRequest {}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultLocation {
    pub url: String,
    pub name: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultLocationResponse {
    pub vault: Option<VaultLocation>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PickedFile {
    pub path: String,
    pub name: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PickedFilesResponse {
    pub files: Vec<PickedFile>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenFileRequest {
    pub path: String,
    pub mode: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CloudAiStatusResponse {
    pub endpoint: String,
    pub model: String,
    pub configured: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CloudAiConfigureRequest {
    pub endpoint: String,
    pub model: String,
    pub api_key: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CloudAiImageRequest {
    pub bytes: Vec<u8>,
    pub mime_type: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CloudAiGenerateRequest {
    pub prompt: String,
    pub stream_id: String,
    #[serde(default)]
    pub images: Vec<CloudAiImageRequest>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct CloudAiGenerateResponse {
    pub answer: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct CloudAiModelResponse {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct CloudAiModelsResponse {
    pub models: Vec<CloudAiModelResponse>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpeechRecognitionStartRequest {
    pub locale: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpeechRecognitionStatusResponse {
    pub listening: bool,
    pub on_device: bool,
    pub engine: String,
    pub build: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct SpeechRecognitionResponse {
    pub transcript: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpeechRecognitionProgressResponse {
    pub listening: bool,
    pub on_device: bool,
    pub transcript: String,
    pub engine: String,
    pub build: String,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct DeviceNameResponse {
    pub name: String,
}
