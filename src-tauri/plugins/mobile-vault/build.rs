const COMMANDS: &[&str] = &[
    "pick_vault_folder",
    "restore_vault_folder",
    "clear_vault_folder",
    "pick_external_notes",
    "pick_files",
    "pick_external_folder",
    "open_file",
    "cloud_ai_status",
    "configure_cloud_ai",
    "generate_cloud_ai",
    "start_speech_recognition",
    "speech_recognition_progress",
    "stop_speech_recognition",
    "cancel_speech_recognition",
    "device_name",
];

fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("ios") {
        println!("cargo:rustc-link-lib=framework=Metal");
        println!("cargo:rustc-link-lib=framework=Accelerate");
        println!("cargo:rustc-link-lib=framework=Security");
        println!("cargo:rustc-link-lib=c++");
    }
    tauri_plugin::Builder::new(COMMANDS)
        .android_path("android")
        .ios_path("ios")
        .build();
}
