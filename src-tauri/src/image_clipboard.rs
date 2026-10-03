#[tauri::command]
pub fn copy_image_clipboard(
    png: Option<Vec<u8>>,
    html: Option<String>,
    plain: Option<String>,
) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        use objc2_app_kit::NSPasteboard;
        use objc2_foundation::{NSArray, NSData, NSString};

        let mut content = Vec::new();
        if let Some(png) = png {
            if !png.starts_with(b"\x89PNG\r\n\x1a\n") {
                return Err("The clipboard image is not a PNG.".to_string());
            }
            content.push((NSString::from_str("public.png"), NSData::with_bytes(&png)));
        }
        if let Some(html) = html {
            content.push((
                NSString::from_str("public.html"),
                NSData::with_bytes(html.as_bytes()),
            ));
        }
        if let Some(plain) = plain {
            content.push((
                NSString::from_str("public.utf8-plain-text"),
                NSData::with_bytes(plain.as_bytes()),
            ));
        }
        if content.is_empty() {
            return Err("There is no image content to copy.".to_string());
        }
        let pasteboard = NSPasteboard::generalPasteboard();
        pasteboard.clearContents();
        let types = NSArray::from_retained_slice(
            &content
                .iter()
                .map(|(kind, _)| kind.clone())
                .collect::<Vec<_>>(),
        );
        // No deferred owner: all representations are written before returning.
        unsafe {
            pasteboard.declareTypes_owner(&types, None);
        }
        for (kind, data) in content {
            if !pasteboard.setData_forType(Some(&data), &kind) {
                return Err("macOS could not copy the image.".to_string());
            }
        }
        Ok(())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = (png, html, plain);
        Err("The native image clipboard is only used on macOS.".to_string())
    }
}
