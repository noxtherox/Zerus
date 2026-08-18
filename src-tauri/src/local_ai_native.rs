use std::ffi::{c_char, c_void, CStr, CString};
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::Mutex;

use libloading::Library;
use tauri::Manager;

type EngineSettingsCreate =
    unsafe extern "C" fn(*const c_char, *const c_char, *const c_char, *const c_char) -> *mut c_void;
type EngineSettingsDelete = unsafe extern "C" fn(*mut c_void);
type EngineSettingsSetMaxTokens = unsafe extern "C" fn(*mut c_void, i32);
type EngineCreate = unsafe extern "C" fn(*const c_void) -> *mut c_void;
type EngineDelete = unsafe extern "C" fn(*mut c_void);
type SamplerCreate = unsafe extern "C" fn(i32) -> *mut c_void;
type SamplerDelete = unsafe extern "C" fn(*mut c_void);
type SamplerSetTopK = unsafe extern "C" fn(*mut c_void, i32);
type SamplerSetTemperature = unsafe extern "C" fn(*mut c_void, f32);
type SessionConfigCreate = unsafe extern "C" fn() -> *mut c_void;
type SessionConfigDelete = unsafe extern "C" fn(*mut c_void);
type SessionConfigSetSampler = unsafe extern "C" fn(*mut c_void, *const c_void);
type ConversationConfigCreate = unsafe extern "C" fn() -> *mut c_void;
type ConversationConfigDelete = unsafe extern "C" fn(*mut c_void);
type ConversationConfigSetSession = unsafe extern "C" fn(*mut c_void, *const c_void);
type ConversationConfigSetJson = unsafe extern "C" fn(*mut c_void, *const c_char);
type ConversationCreate = unsafe extern "C" fn(*mut c_void, *mut c_void) -> *mut c_void;
type ConversationDelete = unsafe extern "C" fn(*mut c_void);
type OptionalArgsCreate = unsafe extern "C" fn() -> *mut c_void;
type OptionalArgsDelete = unsafe extern "C" fn(*mut c_void);
type OptionalArgsSetMaxTokens = unsafe extern "C" fn(*mut c_void, i32);
type ConversationSend =
    unsafe extern "C" fn(*mut c_void, *const c_char, *const c_char, *const c_void) -> *mut c_void;
type JsonResponseGet = unsafe extern "C" fn(*const c_void) -> *const c_char;
type JsonResponseDelete = unsafe extern "C" fn(*mut c_void);

#[derive(Clone, Copy)]
struct Api {
    engine_settings_create: EngineSettingsCreate,
    engine_settings_delete: EngineSettingsDelete,
    engine_settings_set_max_tokens: EngineSettingsSetMaxTokens,
    engine_create: EngineCreate,
    engine_delete: EngineDelete,
    sampler_create: SamplerCreate,
    sampler_delete: SamplerDelete,
    sampler_set_top_k: SamplerSetTopK,
    sampler_set_temperature: SamplerSetTemperature,
    session_config_create: SessionConfigCreate,
    session_config_delete: SessionConfigDelete,
    session_config_set_sampler: SessionConfigSetSampler,
    conversation_config_create: ConversationConfigCreate,
    conversation_config_delete: ConversationConfigDelete,
    conversation_config_set_session: ConversationConfigSetSession,
    conversation_config_set_system_message: ConversationConfigSetJson,
    conversation_config_set_messages: ConversationConfigSetJson,
    conversation_create: ConversationCreate,
    conversation_delete: ConversationDelete,
    optional_args_create: OptionalArgsCreate,
    optional_args_delete: OptionalArgsDelete,
    optional_args_set_max_tokens: OptionalArgsSetMaxTokens,
    conversation_send: ConversationSend,
    json_response_get: JsonResponseGet,
    json_response_delete: JsonResponseDelete,
}

impl Api {
    unsafe fn load(library: &Library) -> Result<Self, String> {
        macro_rules! symbol {
            ($name:literal, $kind:ty) => {
                *library
                    .get::<$kind>($name)
                    .map_err(|error| format!("LiteRT-LM is missing a required API: {error}"))?
            };
        }
        Ok(Self {
            engine_settings_create: symbol!(
                b"litert_lm_engine_settings_create\0",
                EngineSettingsCreate
            ),
            engine_settings_delete: symbol!(
                b"litert_lm_engine_settings_delete\0",
                EngineSettingsDelete
            ),
            engine_settings_set_max_tokens: symbol!(
                b"litert_lm_engine_settings_set_max_num_tokens\0",
                EngineSettingsSetMaxTokens
            ),
            engine_create: symbol!(b"litert_lm_engine_create\0", EngineCreate),
            engine_delete: symbol!(b"litert_lm_engine_delete\0", EngineDelete),
            sampler_create: symbol!(b"litert_lm_sampler_params_create\0", SamplerCreate),
            sampler_delete: symbol!(b"litert_lm_sampler_params_delete\0", SamplerDelete),
            sampler_set_top_k: symbol!(b"litert_lm_sampler_params_set_top_k\0", SamplerSetTopK),
            sampler_set_temperature: symbol!(
                b"litert_lm_sampler_params_set_temperature\0",
                SamplerSetTemperature
            ),
            session_config_create: symbol!(
                b"litert_lm_session_config_create\0",
                SessionConfigCreate
            ),
            session_config_delete: symbol!(
                b"litert_lm_session_config_delete\0",
                SessionConfigDelete
            ),
            session_config_set_sampler: symbol!(
                b"litert_lm_session_config_set_sampler_params\0",
                SessionConfigSetSampler
            ),
            conversation_config_create: symbol!(
                b"litert_lm_conversation_config_create\0",
                ConversationConfigCreate
            ),
            conversation_config_delete: symbol!(
                b"litert_lm_conversation_config_delete\0",
                ConversationConfigDelete
            ),
            conversation_config_set_session: symbol!(
                b"litert_lm_conversation_config_set_session_config\0",
                ConversationConfigSetSession
            ),
            conversation_config_set_system_message: symbol!(
                b"litert_lm_conversation_config_set_system_message\0",
                ConversationConfigSetJson
            ),
            conversation_config_set_messages: symbol!(
                b"litert_lm_conversation_config_set_messages\0",
                ConversationConfigSetJson
            ),
            conversation_create: symbol!(b"litert_lm_conversation_create\0", ConversationCreate),
            conversation_delete: symbol!(b"litert_lm_conversation_delete\0", ConversationDelete),
            optional_args_create: symbol!(
                b"litert_lm_conversation_optional_args_create\0",
                OptionalArgsCreate
            ),
            optional_args_delete: symbol!(
                b"litert_lm_conversation_optional_args_delete\0",
                OptionalArgsDelete
            ),
            optional_args_set_max_tokens: symbol!(
                b"litert_lm_conversation_optional_args_set_max_output_tokens\0",
                OptionalArgsSetMaxTokens
            ),
            conversation_send: symbol!(b"litert_lm_conversation_send_message\0", ConversationSend),
            json_response_get: symbol!(b"litert_lm_json_response_get_string\0", JsonResponseGet),
            json_response_delete: symbol!(b"litert_lm_json_response_delete\0", JsonResponseDelete),
        })
    }
}

struct LoadedRuntime {
    api: Api,
    engine: *mut c_void,
    model_path: PathBuf,
    _library: Library,
}

unsafe impl Send for LoadedRuntime {}

impl Drop for LoadedRuntime {
    fn drop(&mut self) {
        unsafe { (self.api.engine_delete)(self.engine) };
    }
}

#[derive(Default)]
pub struct NativeAiRuntime(Mutex<Option<LoadedRuntime>>);

fn library_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let bundled = app
        .path()
        .resource_dir()
        .map_err(|error| format!("Could not locate Zerus's runtime resources: {error}"))?
        .join("vendor/litert-lm/libCLiteRTLM_mac.dylib");
    if bundled.is_file() {
        return Ok(bundled);
    }
    let development =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("vendor/litert-lm/libCLiteRTLM_mac.dylib");
    development
        .is_file()
        .then_some(development)
        .ok_or_else(|| "The bundled LiteRT-LM runtime is missing".to_string())
}

pub fn available(app: &tauri::AppHandle) -> bool {
    library_path(app).is_ok()
}

fn c_string(value: &str, label: &str) -> Result<CString, String> {
    CString::new(value).map_err(|_| format!("{label} contains an unsupported null character"))
}

fn load_runtime(app: &tauri::AppHandle, model_path: &Path) -> Result<LoadedRuntime, String> {
    load_runtime_from_library(&library_path(app)?, model_path)
}

fn load_runtime_from_library(
    library_path: &Path,
    model_path: &Path,
) -> Result<LoadedRuntime, String> {
    let library = unsafe { Library::new(library_path) }
        .map_err(|error| format!("Could not load the bundled LiteRT-LM runtime: {error}"))?;
    let api = unsafe { Api::load(&library)? };
    let model = c_string(&model_path.to_string_lossy(), "The model path")?;
    let backend = c_string("gpu", "The backend")?;
    let settings = unsafe {
        (api.engine_settings_create)(model.as_ptr(), backend.as_ptr(), ptr::null(), ptr::null())
    };
    if settings.is_null() {
        return Err("LiteRT-LM could not configure the Gemma model".to_string());
    }
    unsafe { (api.engine_settings_set_max_tokens)(settings, 4096) };
    let engine = unsafe { (api.engine_create)(settings) };
    unsafe { (api.engine_settings_delete)(settings) };
    if engine.is_null() {
        return Err(
            "LiteRT-LM could not load Gemma. The model may be incompatible with this Mac"
                .to_string(),
        );
    }
    Ok(LoadedRuntime {
        api,
        engine,
        model_path: model_path.to_path_buf(),
        _library: library,
    })
}

pub fn chat(
    app: &tauri::AppHandle,
    state: &NativeAiRuntime,
    model_path: &Path,
    system_message_json: &str,
    context_messages_json: &str,
    prompt_json: &str,
) -> Result<String, String> {
    let mut guard = state.0.lock().unwrap_or_else(|error| error.into_inner());
    if guard
        .as_ref()
        .is_none_or(|runtime| runtime.model_path != model_path)
    {
        *guard = Some(load_runtime(app, model_path)?);
    }
    let runtime = guard.as_ref().expect("runtime was initialized");
    send(
        runtime,
        system_message_json,
        context_messages_json,
        prompt_json,
    )
}

fn send(
    runtime: &LoadedRuntime,
    system_message_json: &str,
    context_messages_json: &str,
    prompt_json: &str,
) -> Result<String, String> {
    let api = runtime.api;
    let system = c_string(system_message_json, "The system message")?;
    let context = c_string(context_messages_json, "The conversation history")?;
    let prompt = c_string(prompt_json, "The prompt")?;

    unsafe {
        let sampler = (api.sampler_create)(1);
        let session = (api.session_config_create)();
        let config = (api.conversation_config_create)();
        if sampler.is_null() || session.is_null() || config.is_null() {
            if !sampler.is_null() {
                (api.sampler_delete)(sampler);
            }
            if !session.is_null() {
                (api.session_config_delete)(session);
            }
            if !config.is_null() {
                (api.conversation_config_delete)(config);
            }
            return Err("LiteRT-LM could not create a conversation".to_string());
        }
        (api.sampler_set_top_k)(sampler, 40);
        (api.sampler_set_temperature)(sampler, 0.2);
        (api.session_config_set_sampler)(session, sampler);
        (api.conversation_config_set_session)(config, session);
        (api.conversation_config_set_system_message)(config, system.as_ptr());
        (api.conversation_config_set_messages)(config, context.as_ptr());
        let conversation = (api.conversation_create)(runtime.engine, config);
        (api.conversation_config_delete)(config);
        (api.session_config_delete)(session);
        (api.sampler_delete)(sampler);
        if conversation.is_null() {
            return Err("LiteRT-LM could not initialize the conversation context".to_string());
        }
        let optional_args = (api.optional_args_create)();
        if !optional_args.is_null() {
            (api.optional_args_set_max_tokens)(optional_args, 2048);
        }
        let response =
            (api.conversation_send)(conversation, prompt.as_ptr(), ptr::null(), optional_args);
        if !optional_args.is_null() {
            (api.optional_args_delete)(optional_args);
        }
        (api.conversation_delete)(conversation);
        if response.is_null() {
            return Err("Gemma did not return a response".to_string());
        }
        let json_ptr = (api.json_response_get)(response);
        let json = if json_ptr.is_null() {
            Err("Gemma returned an empty response".to_string())
        } else {
            CStr::from_ptr(json_ptr)
                .to_str()
                .map(str::to_owned)
                .map_err(|error| format!("Gemma returned invalid text: {error}"))
        };
        (api.json_response_delete)(response);
        json
    }
}

#[cfg(test)]
mod tests {
    use super::{load_runtime_from_library, send};
    use std::path::Path;

    #[test]
    fn native_gemma_probe_when_model_path_is_set() {
        let Ok(model_path) = std::env::var("ZERUS_LITERT_MODEL_PATH") else {
            return;
        };
        let library_path =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("vendor/litert-lm/libCLiteRTLM_mac.dylib");
        let runtime = load_runtime_from_library(&library_path, Path::new(&model_path))
            .expect("load the bundled runtime and downloaded model");
        let response = send(
            &runtime,
            r#"{"role":"system","content":[{"type":"text","text":"Answer only from the supplied Zerus context."}]}"#,
            r#"[{"role":"user","content":[{"type":"text","text":"Zerus note context: The verification code is ORCHID-731."}]}]"#,
            r#"{"role":"user","content":[{"type":"text","text":"What is the verification code in this note?"}]}"#,
        )
        .expect("generate a native response");
        assert!(
            response.contains("ORCHID-731"),
            "unexpected response: {response}"
        );
    }
}
