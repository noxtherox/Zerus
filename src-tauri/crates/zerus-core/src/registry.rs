use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use thiserror::Error;
use uuid::Uuid;

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultRecord {
    pub id: Uuid,
    pub name: String,
    pub path: PathBuf,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VaultRegistry {
    pub version: u32,
    pub default_vault_id: Option<Uuid>,
    pub vaults: Vec<VaultRecord>,
}

#[derive(Debug, Error)]
pub enum RegistryError {
    #[error("could not determine the user configuration directory")]
    ConfigDirectory,
    #[error("could not read the vault registry: {0}")]
    Read(#[source] std::io::Error),
    #[error("the vault registry is invalid: {0}")]
    Invalid(#[source] serde_json::Error),
    #[error("could not save the vault registry: {0}")]
    Write(#[source] std::io::Error),
    #[error("no vault matches '{0}'")]
    NotFound(String),
    #[error("no default Zerus vault is configured")]
    NoDefault,
}

pub fn default_registry_path() -> Result<PathBuf, RegistryError> {
    let config = dirs::config_dir().ok_or(RegistryError::ConfigDirectory)?;
    let current = config.join("zerus").join("vaults.json");
    let legacy = config.join("zerus").join("vaults.json");
    Ok(if current.exists() || !legacy.exists() {
        current
    } else {
        legacy
    })
}

pub fn load_registry(path: &Path) -> Result<VaultRegistry, RegistryError> {
    if !path.exists() {
        return Ok(VaultRegistry {
            version: 1,
            ..VaultRegistry::default()
        });
    }
    let raw = fs::read_to_string(path).map_err(RegistryError::Read)?;
    serde_json::from_str(&raw).map_err(RegistryError::Invalid)
}

pub fn save_registry(path: &Path, registry: &VaultRegistry) -> Result<(), RegistryError> {
    let parent = path.parent().ok_or(RegistryError::ConfigDirectory)?;
    fs::create_dir_all(parent).map_err(RegistryError::Write)?;
    let temporary = path.with_extension(format!("tmp-{}", std::process::id()));
    let bytes = serde_json::to_vec_pretty(registry).expect("registry is serializable");
    fs::write(&temporary, bytes).map_err(RegistryError::Write)?;
    fs::rename(&temporary, path).map_err(RegistryError::Write)
}

pub fn resolve_vault<'a>(
    registry: &'a VaultRegistry,
    selector: Option<&str>,
) -> Result<&'a VaultRecord, RegistryError> {
    if let Some(selector) = selector {
        let normalized = selector.to_lowercase();
        return registry
            .vaults
            .iter()
            .find(|vault| {
                vault.name.to_lowercase() == normalized
                    || vault.id.to_string() == normalized
                    || vault.id.to_string().starts_with(&normalized)
                    || vault.path == Path::new(selector)
            })
            .ok_or_else(|| RegistryError::NotFound(selector.to_string()));
    }
    let id = registry.default_vault_id.ok_or(RegistryError::NoDefault)?;
    registry
        .vaults
        .iter()
        .find(|vault| vault.id == id)
        .ok_or(RegistryError::NoDefault)
}
