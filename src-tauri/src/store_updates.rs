//! Microsoft Store updates for the MSIX app. Store calls start on the window's
//! UI thread; waiting for the asynchronous operation never blocks that thread.

#[cfg(target_os = "windows")]
mod platform {
    use tauri::WebviewWindow;
    use windows::{
        core::Interface,
        ApplicationModel::Package,
        Services::Store::{StoreContext, StorePackageUpdate, StorePackageUpdateState},
        Win32::{Foundation::HWND, UI::Shell::IInitializeWithWindow},
    };

    async fn on_ui<T: Send + 'static>(
        window: &WebviewWindow,
        action: impl FnOnce(WebviewWindow) -> Result<T, String> + Send + 'static,
    ) -> Result<T, String> {
        let (sender, receiver) = tokio::sync::oneshot::channel();
        let owned_window = window.clone();
        window
            .run_on_main_thread(move || {
                let _ = sender.send(action(owned_window));
            })
            .map_err(|error| error.to_string())?;
        receiver.await.map_err(|error| error.to_string())?
    }

    fn context(window: &WebviewWindow) -> Result<StoreContext, String> {
        // Unpackaged EXE builds cannot use the Store's package update API.
        Package::Current().map_err(|_| {
            "Store updates require the Microsoft Store version of Zerus.".to_string()
        })?;
        let context = StoreContext::GetDefault().map_err(|error| error.to_string())?;
        let interop: IInitializeWithWindow = context.cast().map_err(|error| error.to_string())?;
        let hwnd = window.hwnd().map_err(|error| error.to_string())?;
        // The live Tauri window owns this HWND. Microsoft requires this binding
        // for Store dialogs in packaged desktop apps.
        unsafe { interop.Initialize(HWND(hwnd.0)) }.map_err(|error| error.to_string())?;
        Ok(context)
    }

    pub async fn check(window: WebviewWindow) -> Result<Option<String>, String> {
        let (_context, operation) = on_ui(&window, |window| {
            let context = context(&window)?;
            let operation = context
                .GetAppAndOptionalStorePackageUpdatesAsync()
                .map_err(|error| error.to_string())?;
            Ok((context, operation))
        })
        .await?;
        let packages = tokio::time::timeout(std::time::Duration::from_secs(30), async {
            operation.await
        })
        .await
        .map_err(|_| "Microsoft Store update check timed out.".to_string())?
        .map_err(|error| error.to_string())?;
        let mut identities = Vec::new();
        for package in packages {
            let id = package
                .Package()
                .and_then(|package| package.Id())
                .and_then(|id| id.FullName())
                .map_err(|error| error.to_string())?;
            identities.push(id.to_string());
        }
        identities.sort();
        Ok((!identities.is_empty()).then(|| identities.join(";")))
    }

    pub async fn install(window: WebviewWindow) -> Result<&'static str, String> {
        // Re-query so an update installed by the Store in the meantime is a
        // harmless no-op, and never accept package identifiers from JavaScript.
        let (context, operation) = on_ui(&window, |window| {
            let context = context(&window)?;
            let operation = context
                .GetAppAndOptionalStorePackageUpdatesAsync()
                .map_err(|error| error.to_string())?;
            Ok((context, operation))
        })
        .await?;
        let packages = {
            let packages = tokio::time::timeout(std::time::Duration::from_secs(30), async {
                operation.await
            })
            .await
            .map_err(|_| "Microsoft Store update check timed out.".to_string())?
            .map_err(|error| error.to_string())?;
            // The collection interface is apartment-bound. Transfer only its
            // agile StorePackageUpdate objects, then create a new UI iterable.
            let mut updates = Vec::new();
            for index in 0..packages.Size().map_err(|error| error.to_string())? {
                updates.push(Some(
                    packages.GetAt(index).map_err(|error| error.to_string())?,
                ));
            }
            updates
        };
        if packages.is_empty() {
            return Ok("up-to-date");
        }
        let (_context, operation) = on_ui(&window, move |_| {
            let packages: windows_collections::IIterable<StorePackageUpdate> = packages.into();
            let operation = context
                .RequestDownloadAndInstallStorePackageUpdatesAsync(&packages)
                .map_err(|error| error.to_string())?;
            Ok((context, operation))
        })
        .await?;
        let result = operation.await.map_err(|error| error.to_string())?;
        match result.OverallState().map_err(|error| error.to_string())? {
            StorePackageUpdateState::Completed => Ok("completed"),
            StorePackageUpdateState::Canceled => Ok("canceled"),
            state => Err(format!("Microsoft Store could not finish the update (state {}). Check your connection, battery, and Store downloads, then try again.", state.0)),
        }
    }
}

#[tauri::command]
pub async fn check_store_update(window: tauri::WebviewWindow) -> Result<Option<String>, String> {
    #[cfg(target_os = "windows")]
    {
        platform::check(window).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = window;
        Ok(None)
    }
}

#[tauri::command]
pub async fn install_store_update(window: tauri::WebviewWindow) -> Result<&'static str, String> {
    #[cfg(target_os = "windows")]
    {
        platform::install(window).await
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = window;
        Err("Microsoft Store updates are available only on Windows.".into())
    }
}
