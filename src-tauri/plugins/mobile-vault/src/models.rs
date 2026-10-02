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
    pub path: Option<String>,
    pub name: Option<String>,
    pub data: Option<String>,
    pub mode: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CloudAiStatusResponse {
    pub endpoint: String,
    pub model: String,
    pub configured: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub account: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub accounts: Option<Vec<ChatGptAccountSummary>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub revocation_unconfirmed: Option<bool>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct ChatGptAccountSummary {
    pub id: String,
    pub label: String,
    pub connected: bool,
    pub active: bool,
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
    #[serde(default, rename = "agentRequestJSON")]
    pub agent_request_json: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct CloudAiGenerateResponse {
    pub answer: String,
    #[serde(default, rename = "agentResponseJSON")]
    pub agent_response_json: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CloudAiStopRequest {
    pub stream_id: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct CloudAiModelResponse {
    pub id: String,
    pub name: String,
    #[serde(rename = "contextWindow")]
    pub context_window: Option<u64>,
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

#[cfg(test)]
mod agent_transport_tests {
    use super::*;
    #[test]
    fn agent_payloads_and_targeted_cancellation_survive_the_native_bridge() {
        let request: CloudAiGenerateRequest = serde_json::from_value(serde_json::json!({"prompt":"","streamId":"step-1","images":[],"agentRequestJSON":"{\"tools\":[{\"name\":\"note_get\"}]}"})).unwrap();
        let native = serde_json::to_value(request).unwrap();
        assert_eq!(
            native["agentRequestJSON"],
            "{\"tools\":[{\"name\":\"note_get\"}]}"
        );
        let response: CloudAiGenerateResponse = serde_json::from_value(serde_json::json!({"answer":"","agentResponseJSON":"{\"toolCalls\":[{\"id\":\"call-1\"}]}"})).unwrap();
        assert_eq!(
            serde_json::to_value(response).unwrap()["agentResponseJSON"],
            "{\"toolCalls\":[{\"id\":\"call-1\"}]}"
        );
        let stop: CloudAiStopRequest =
            serde_json::from_value(serde_json::json!({"streamId":"step-1"})).unwrap();
        assert_eq!(serde_json::to_value(stop).unwrap()["streamId"], "step-1");
    }
}
