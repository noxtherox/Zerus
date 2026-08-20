use tauri::{
    plugin::{Builder, TauriPlugin},
    Manager, Runtime,
};

pub use models::*;

#[cfg(desktop)]
mod desktop;
#[cfg(mobile)]
mod mobile;

mod commands;
mod error;
mod models;

pub use error::{Error, Result};

#[cfg(desktop)]
use desktop::MobileVault;
#[cfg(mobile)]
use mobile::MobileVault;

/// Extensions to [`tauri::App`], [`tauri::AppHandle`] and [`tauri::Window`] to access the mobile-vault APIs.
pub trait MobileVaultExt<R: Runtime> {
    fn mobile_vault(&self) -> &MobileVault<R>;
}

impl<R: Runtime, T: Manager<R>> crate::MobileVaultExt<R> for T {
    fn mobile_vault(&self) -> &MobileVault<R> {
        self.state::<MobileVault<R>>().inner()
    }
}

/// Initializes the plugin.
pub fn init<R: Runtime>() -> TauriPlugin<R> {
    Builder::new("mobile-vault")
        .invoke_handler(tauri::generate_handler![
            commands::pick_vault_folder,
            commands::restore_vault_folder,
            commands::clear_vault_folder,
            commands::pick_external_notes,
            commands::pick_files,
            commands::pick_external_folder,
            commands::open_file,
            commands::cloud_ai_status,
            commands::configure_cloud_ai,
            commands::connect_openrouter,
            commands::cloud_ai_models,
            commands::generate_cloud_ai,
            commands::stop_cloud_ai,
            commands::start_speech_recognition,
            commands::speech_recognition_progress,
            commands::stop_speech_recognition,
            commands::cancel_speech_recognition,
            commands::device_name,
        ])
        .setup(|app, api| {
            #[cfg(mobile)]
            let mobile_vault = mobile::init(app, api)?;
            #[cfg(desktop)]
            let mobile_vault = desktop::init(app, api)?;
            app.manage(mobile_vault);
            Ok(())
        })
        .build()
}
