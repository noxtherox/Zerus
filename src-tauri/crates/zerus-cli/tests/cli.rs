use assert_cmd::Command;
use serde_json::Value;
use std::fs;
use tempfile::TempDir;

fn fixture() -> TempDir {
    let directory = TempDir::new().unwrap();
    fs::create_dir_all(directory.path().join("work")).unwrap();
    fs::write(
        directory.path().join("work/Plan.md"),
        "---\nzerus-id: 019f7922-8fae-7733-8357-48b16a134c38\nstatus: active\n---\n# Project Plan\n\nAction items\n",
    )
    .unwrap();
    fs::write(
        directory.path().join("work/Archived.md"),
        "---\nzerus-id: 019f7922-8fae-7733-8357-48b16a134c39\nzerus-archived: true\n---\n# Old Plan\n",
    )
    .unwrap();
    directory
}

fn cli() -> Command {
    Command::cargo_bin("zerus").unwrap()
}

#[test]
fn lists_active_notes_as_json() {
    let vault = fixture();
    let output = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "note",
            "list",
        ])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["schemaVersion"], 1);
    assert_eq!(value["data"].as_array().unwrap().len(), 1);
    assert_eq!(value["data"][0]["title"], "Project Plan");
}

#[test]
fn gets_a_note_by_id_prefix_with_body_only_json() {
    let vault = fixture();
    let output = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "note",
            "get",
            "019f7922-8fae-7733-8357-48b16a134c38",
            "--body",
        ])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["data"]["content"], "# Project Plan\n\nAction items\n");
}

#[test]
fn searches_body_and_properties() {
    let vault = fixture();
    let output = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "search",
            "Action",
            "--property",
            "status=active",
        ])
        .output()
        .unwrap();
    assert!(output.status.success());
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(value["data"].as_array().unwrap().len(), 1);
}

#[test]
fn reports_ambiguous_titles_without_prompting() {
    let vault = fixture();
    fs::write(
        vault.path().join("Project Plan.md"),
        "---\nzerus-id: 019f7922-8fae-7733-8357-48b16a134c40\n---\n# Project Plan\n",
    )
    .unwrap();
    let output = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "--no-input",
            "note",
            "get",
            "--title",
            "Project Plan",
        ])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(4));
    let value: Value = serde_json::from_slice(&output.stderr).unwrap();
    assert_eq!(value["error"]["code"], "ambiguous_selector");
    assert_eq!(value["error"]["details"].as_array().unwrap().len(), 2);
}

#[test]
fn mutates_reserved_state_and_can_undo() {
    let vault = fixture();
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "note",
            "pin",
            "work/Plan.md",
        ])
        .assert()
        .success();
    let pinned = fs::read_to_string(vault.path().join("work/Plan.md")).unwrap();
    assert!(pinned.contains("zerus-pinned: true"));
    cli()
        .args(["--vault", vault.path().to_str().unwrap(), "undo"])
        .assert()
        .success();
    let restored = fs::read_to_string(vault.path().join("work/Plan.md")).unwrap();
    assert!(!restored.contains("zerus-pinned"));
}

#[test]
fn migrates_creates_and_trashes_notes() {
    let vault = fixture();
    fs::write(vault.path().join("Loose.md"), "# Loose\n").unwrap();
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "migrate",
            "apply",
            "--yes",
        ])
        .assert()
        .success();
    assert!(fs::read_to_string(vault.path().join("Loose.md"))
        .unwrap()
        .contains("zerus-id:"));
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "note",
            "create",
            "ideas/New",
            "--title",
            "New idea",
        ])
        .assert()
        .success();
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "note",
            "trash",
            "ideas/New.md",
        ])
        .assert()
        .success();
    assert!(vault.path().join(".trash/ideas/New.md").exists());
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "note",
            "restore",
            ".trash/ideas/New.md",
        ])
        .assert()
        .success();
    assert!(vault.path().join("ideas/New.md").exists());
}

#[test]
fn previews_and_applies_the_legacy_brand_migration() {
    let vault = TempDir::new().unwrap();
    fs::create_dir_all(vault.path().join(".grimoire")).unwrap();
    fs::write(
        vault.path().join(".grimoire/vault.json"),
        r#"{"version":1,"vaultId":"019f7922-8fae-7335-8d44-39d5a5822de8","metadataVersion":1,"idsRequired":true}"#,
    )
    .unwrap();
    fs::write(
        vault.path().join("Legacy.md"),
        "---\ngrimoire-id: 019f7922-8fae-7335-8d44-39d5a5822de9\ngrimoire-pinned: true\ngrimoire-file-id: attachment-1\n---\n# Legacy\n",
    )
    .unwrap();

    let preview = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "migrate",
            "preview",
        ])
        .output()
        .unwrap();
    assert!(preview.status.success());
    let preview: Value = serde_json::from_slice(&preview.stdout).unwrap();
    assert_eq!(preview["data"]["notesChanged"], 1);
    assert_eq!(preview["data"]["legacyKeysRenamed"], 3);
    assert_eq!(preview["data"]["movesMetadataDirectory"], true);
    assert_eq!(preview["data"]["changes"][0]["addsId"], false);

    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "migrate",
            "apply",
            "--yes",
        ])
        .assert()
        .success();

    let migrated = fs::read_to_string(vault.path().join("Legacy.md")).unwrap();
    assert!(migrated.contains("zerus-id: 019f7922-8fae-7335-8d44-39d5a5822de9"));
    assert!(migrated.contains("zerus-pinned: true"));
    assert!(migrated.contains("zerus-file-id: attachment-1"));
    assert!(!migrated.contains("grimoire-"));
    assert!(vault.path().join(".zerus/vault.json").is_file());
    assert!(!vault.path().join(".grimoire").exists());
}

#[test]
fn bulk_requires_preview_then_approval() {
    let vault = fixture();
    let preview = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "bulk",
            "property-set",
            "Action",
            "status",
            "done",
        ])
        .output()
        .unwrap();
    assert!(preview.status.success());
    let value: Value = serde_json::from_slice(&preview.stdout).unwrap();
    assert_eq!(value["data"]["approvalRequired"], true);
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "bulk",
            "property-set",
            "Action",
            "status",
            "done",
            "--yes",
        ])
        .assert()
        .success();
    assert!(fs::read_to_string(vault.path().join("work/Plan.md"))
        .unwrap()
        .contains("status: done"));
}

#[test]
fn adds_inherited_and_subtype_relation_schemas() {
    let vault = fixture();
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "schema",
            "add",
            "Development",
            "Company",
            "relation",
            "--relation-type",
            "Companies",
        ])
        .assert()
        .success();
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "schema",
            "add",
            "Development/Initiatives",
            "Epics",
            "relation",
            "--relation-type",
            "Development/Epics",
            "--multiple",
        ])
        .assert()
        .success();

    let schemas: Value =
        serde_json::from_slice(&fs::read(vault.path().join(".zerus/properties.json")).unwrap())
            .unwrap();
    assert_eq!(
        schemas["Development/Initiatives"][0]["relationTypeKey"],
        "Development/Epics"
    );
    assert_eq!(
        schemas["Development/Initiatives"][0]["relationMultiple"],
        true
    );
    assert!(schemas.get("Development").is_some());

    let output = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "schema",
            "list",
            "Development/Initiatives",
        ])
        .output()
        .unwrap();
    assert!(output.status.success());
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    let names = value["data"]
        .as_array()
        .unwrap()
        .iter()
        .map(|definition| definition["name"].as_str().unwrap())
        .collect::<Vec<_>>();
    assert_eq!(names, vec!["Company", "Epics"]);
}

#[test]
fn writes_list_multiplicity_and_rejects_kind_specific_flags() {
    let vault = fixture();
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "schema",
            "add",
            "Development/Epics",
            "Labels",
            "list",
            "--options",
            " Planned, Active,active ",
            "--multiple",
        ])
        .assert()
        .success();
    let schemas: Value =
        serde_json::from_slice(&fs::read(vault.path().join(".zerus/properties.json")).unwrap())
            .unwrap();
    assert_eq!(
        schemas["Development/Epics"][0]["listOptions"],
        serde_json::json!(["Planned", "Active"])
    );
    assert_eq!(schemas["Development/Epics"][0]["listMultiple"], true);

    let output = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "schema",
            "add",
            "Development/Epics",
            "Owner",
            "text",
            "--relation-type",
            "People",
        ])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(3));
    let error: Value = serde_json::from_slice(&output.stderr).unwrap();
    assert_eq!(error["error"]["code"], "schema_invalid");
}

#[test]
fn removing_and_purging_a_subtype_schema_does_not_touch_siblings() {
    let vault = fixture();
    fs::create_dir_all(vault.path().join("Development/Initiatives")).unwrap();
    fs::create_dir_all(vault.path().join("Development/Epics")).unwrap();
    fs::write(
        vault.path().join("Development/Initiatives/Initiative.md"),
        "---\nzerus-id: 019f7922-8fae-7733-8357-48b16a134c41\nEpics: Epic One\n---\n# Initiative One\n",
    )
    .unwrap();
    fs::write(
        vault.path().join("Development/Epics/Epic.md"),
        "---\nzerus-id: 019f7922-8fae-7733-8357-48b16a134c42\nEpics: Keep me\n---\n# Epic One\n",
    )
    .unwrap();
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "schema",
            "add",
            "Development/Initiatives",
            "Epics",
            "relation",
            "--relation-type",
            "Development/Epics",
        ])
        .assert()
        .success();
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "schema",
            "remove",
            "Development/Initiatives",
            "Epics",
            "--purge-values",
            "--yes",
        ])
        .assert()
        .success();

    let initiative =
        fs::read_to_string(vault.path().join("Development/Initiatives/Initiative.md")).unwrap();
    let epic = fs::read_to_string(vault.path().join("Development/Epics/Epic.md")).unwrap();
    assert!(!initiative.contains("Epics:"));
    assert!(epic.contains("Epics: Keep me"));
}

#[test]
fn excludes_trash_and_supports_eight_level_types_and_empty_folders() {
    let vault = fixture();
    fs::create_dir_all(vault.path().join(".trash/work")).unwrap();
    fs::write(
        vault.path().join(".trash/work/Deleted.md"),
        "---\nzerus-id: 019f7922-8fae-7733-8357-48b16a134c50\n---\n# Deleted\n",
    )
    .unwrap();
    fs::create_dir_all(vault.path().join("A/B/C/D/E/F/G/H")).unwrap();

    let listed = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "note",
            "list",
        ])
        .output()
        .unwrap();
    let value: Value = serde_json::from_slice(&listed.stdout).unwrap();
    assert!(value["data"]
        .as_array()
        .unwrap()
        .iter()
        .all(|note| !note["path"].as_str().unwrap().starts_with(".trash/")));

    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "schema",
            "add",
            "A/B/C/D/E/F/G/H",
            "Status",
            "text",
        ])
        .assert()
        .success();
    let types = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "type",
            "list",
        ])
        .output()
        .unwrap();
    let value: Value = serde_json::from_slice(&types.stdout).unwrap();
    assert!(value["data"]
        .as_array()
        .unwrap()
        .contains(&Value::String("A/B/C/D/E/F/G/H".into())));
    assert!(!value["data"]
        .as_array()
        .unwrap()
        .iter()
        .any(|entry| entry.as_str().unwrap().starts_with(".trash")));
}

#[test]
fn manages_tasks_and_saved_links() {
    let vault = fixture();
    let created = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "task",
            "create",
            "Ship Zerus",
            "--priority",
            "high",
            "--link-note",
            "work/Plan.md",
        ])
        .output()
        .unwrap();
    assert!(
        created.status.success(),
        "{}",
        String::from_utf8_lossy(&created.stderr)
    );
    let task: Value = serde_json::from_slice(&created.stdout).unwrap();
    assert_eq!(task["data"]["priority"], "high");
    assert_eq!(task["data"]["linkedNoteIds"].as_array().unwrap().len(), 1);
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "task",
            "complete",
            "Ship Zerus",
        ])
        .assert()
        .success();

    let saved = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "saved-link",
            "create",
            "https://zerus.app/docs",
            "--title",
            "Zerus docs",
        ])
        .output()
        .unwrap();
    assert!(
        saved.status.success(),
        "{}",
        String::from_utf8_lossy(&saved.stderr)
    );
    let saved: Value = serde_json::from_slice(&saved.stdout).unwrap();
    assert!(vault
        .path()
        .join(saved["data"]["path"].as_str().unwrap())
        .is_file());
    assert_eq!(
        serde_json::from_slice::<Value>(&fs::read(vault.path().join(".zerus/links.json")).unwrap())
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn reports_relation_backlinks_and_moves_managed_files() {
    let vault = fixture();
    fs::write(vault.path().join("work/Brief.pdf"), b"pdf").unwrap();
    fs::write(
        vault.path().join("work/Plan.md"),
        "---\nzerus-id: 019f7922-8fae-7733-8357-48b16a134c38\nRelated: Old Plan\nzerus-file-id: file-1\nzerus-file-name: Brief.pdf\nzerus-file-kind: vault\nzerus-file-path: work/Brief.pdf\nzerus-file-managed: true\n---\n# Project Plan\n",
    )
    .unwrap();
    fs::create_dir_all(vault.path().join(".zerus")).unwrap();
    fs::write(
        vault.path().join(".zerus/properties.json"),
        r#"{"work":[{"name":"Related","type":"relation","relationTypeKey":"work","relationMultiple":false}]}"#,
    )
    .unwrap();

    let links = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "links",
            "work/Archived.md",
        ])
        .output()
        .unwrap();
    let value: Value = serde_json::from_slice(&links.stdout).unwrap();
    assert_eq!(value["data"]["backlinks"][0]["viaRelation"], true);

    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "type",
            "move",
            "work/Plan.md",
            "--to",
            "projects",
        ])
        .assert()
        .success();
    assert!(vault.path().join("projects/Brief.pdf").is_file());
    let moved = fs::read_to_string(vault.path().join("projects/Plan.md")).unwrap();
    assert!(moved.contains("zerus-file-path: projects/Brief.pdf"));
}

#[test]
fn undo_refuses_to_overwrite_newer_edits() {
    let vault = fixture();
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "note",
            "append",
            "work/Plan.md",
            "--text",
            "CLI edit",
        ])
        .assert()
        .success();
    fs::write(
        vault.path().join("work/Plan.md"),
        "---\nzerus-id: 019f7922-8fae-7733-8357-48b16a134c38\n---\n# Project Plan\n\nNewer app edit\n",
    )
    .unwrap();
    let output = cli()
        .args(["--vault", vault.path().to_str().unwrap(), "--json", "undo"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(5));
    let error: Value = serde_json::from_slice(&output.stderr).unwrap();
    assert_eq!(error["error"]["code"], "undo_conflict");
    assert!(fs::read_to_string(vault.path().join("work/Plan.md"))
        .unwrap()
        .contains("Newer app edit"));
}

#[test]
fn copies_and_removes_note_attachments() {
    let vault = fixture();
    let source = vault.path().join("source.txt");
    fs::write(&source, "attachment").unwrap();
    let added = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "attachment",
            "add-copy",
            "work/Plan.md",
            "--source",
            source.to_str().unwrap(),
        ])
        .output()
        .unwrap();
    assert!(
        added.status.success(),
        "{}",
        String::from_utf8_lossy(&added.stderr)
    );
    let value: Value = serde_json::from_slice(&added.stdout).unwrap();
    let attachment_id = value["data"]["attachment"]["id"].as_str().unwrap();
    let path = value["data"]["attachment"]["path"].as_str().unwrap();
    assert!(vault.path().join(path).is_file());
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "attachment",
            "remove",
            "work/Plan.md",
            "--attachment-id",
            attachment_id,
            "--delete-managed",
            "--yes",
        ])
        .assert()
        .success();
    assert!(!vault.path().join(path).exists());
}

#[test]
fn renames_type_metadata_and_blocks_unrelated_file_deletion() {
    let vault = fixture();
    fs::create_dir_all(vault.path().join(".zerus")).unwrap();
    fs::write(
        vault.path().join(".zerus/properties.json"),
        r#"{"work":[{"name":"Related","type":"relation","relationTypeKey":"work/sub"}]}"#,
    )
    .unwrap();
    fs::write(
        vault.path().join(".zerus/type-icons.json"),
        r#"{"work":"tabler:Briefcase"}"#,
    )
    .unwrap();
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "type",
            "rename",
            "work",
            "projects",
        ])
        .assert()
        .success();
    let schemas: Value =
        serde_json::from_slice(&fs::read(vault.path().join(".zerus/properties.json")).unwrap())
            .unwrap();
    assert_eq!(schemas["projects"][0]["relationTypeKey"], "projects/sub");
    let icons: Value =
        serde_json::from_slice(&fs::read(vault.path().join(".zerus/type-icons.json")).unwrap())
            .unwrap();
    assert_eq!(icons["projects"], "tabler:Briefcase");

    fs::write(vault.path().join("projects/keep.bin"), "keep").unwrap();
    let deletion = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "type",
            "delete",
            "projects",
            "--yes",
        ])
        .output()
        .unwrap();
    assert_eq!(deletion.status.code(), Some(5));
    assert!(vault.path().join("projects/Plan.md").is_file());
    assert!(vault.path().join("projects/keep.bin").is_file());
}
