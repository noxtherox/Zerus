//! Shared vault rules for the Zerus desktop app and command-line tool.
//!
//! This crate intentionally has no Tauri dependency. Filesystem and UI layers
//! can use the same metadata, migration, revision, and portable-path contract.

pub mod frontmatter;
pub mod metadata;
pub mod path;
pub mod registry;
pub mod vault;

pub use frontmatter::{note_body, note_properties, note_title, PropertyValue};

pub use metadata::{
    content_revision, plan_note_metadata_migration, plan_vault_metadata_migration,
    read_note_metadata, MetadataError, MetadataMigrationPlan, MetadataMigrationSummary,
    MigrationIssue, MigrationNoteInput, NoteMetadata, PlannedNoteMigration,
    VaultMetadataMigrationPlan, ZERUS_ARCHIVED_KEY, ZERUS_ID_KEY, ZERUS_PINNED_KEY,
};
pub use path::{
    find_case_insensitive_collisions, validate_portable_relative_path, PortablePathError,
};
pub use registry::{
    default_registry_path, load_registry, resolve_vault, save_registry, RegistryError, VaultRecord,
    VaultRegistry,
};
pub use vault::{
    diagnose_vault, load_or_create_manifest, read_vault_manifest, scan_vault, write_vault_manifest,
    DiagnosticIssue, DiagnosticReport, ScannedNote, VaultError, VaultManifest,
};
mod edit;
pub use edit::*;
