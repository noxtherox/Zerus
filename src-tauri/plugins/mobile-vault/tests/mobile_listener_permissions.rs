use std::{collections::BTreeMap, fs, path::Path};

use tauri::utils::{
    acl::{
        capability::Capability,
        manifest::{Manifest, PermissionFile},
        resolved::Resolved,
        ExecutionContext,
    },
    platform::Target,
};

fn permission_files(directory: &Path) -> Vec<PermissionFile> {
    let mut files = Vec::new();
    for entry in fs::read_dir(directory).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            files.extend(permission_files(&path));
        } else if path
            .extension()
            .is_some_and(|extension| extension == "toml")
        {
            files.push(toml::from_str(&fs::read_to_string(path).unwrap()).unwrap());
        }
    }
    files
}

#[test]
fn main_ios_webview_can_subscribe_to_and_remove_native_stream_listeners() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let manifest = Manifest::new(permission_files(&root.join("permissions")), None);
    let mut capability: Capability =
        serde_json::from_str(include_str!("../../../capabilities/default.json")).unwrap();
    capability
        .permissions
        .retain(|permission| permission.identifier().get_prefix() == Some("mobile-vault"));
    let resolved = Resolved::resolve(
        &BTreeMap::from([("mobile-vault".into(), manifest)]),
        BTreeMap::from([(capability.identifier.clone(), capability)]),
        Target::Ios,
    )
    .unwrap();

    // These names are the @tauri-apps/api addPluginListener/PluginListener contract.
    for command in ["register_listener", "remove_listener"] {
        let permissions = resolved
            .allowed_commands
            .get(&format!("plugin:mobile-vault|{command}"))
            .unwrap_or_else(|| panic!("Native streaming command {command} is blocked by ACL"));
        assert!(permissions.iter().any(|permission| {
            permission.context == ExecutionContext::Local
                && permission
                    .webviews
                    .iter()
                    .any(|pattern| pattern.matches("main"))
        }));
        assert!(permissions
            .iter()
            .all(|permission| permission.context == ExecutionContext::Local));
    }
}
