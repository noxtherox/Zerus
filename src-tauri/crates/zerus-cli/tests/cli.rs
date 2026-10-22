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
        "---\nzerus-id: 019f7923-8fae-7733-8357-48b16a134c39\nzerus-archived: true\n---\n# Old Plan\n",
    )
    .unwrap();
    directory
}

fn cli() -> Command {
    Command::cargo_bin("zerus").unwrap()
}

fn run_json(vault: &TempDir, args: &[&str]) -> Value {
    let output = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "--no-input",
        ])
        .args(args)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).unwrap()
}

#[test]
fn task_writes_preserve_lists_and_unknown_metadata() {
    let vault = fixture();
    fs::create_dir_all(vault.path().join(".zerus")).unwrap();
    let path = vault.path().join(".zerus/tasks.json");
    fs::write(
        &path,
        serde_json::to_vec(&serde_json::json!({
            "generalListName": "Inbox", "lists": [{"id":"work", "name":"Work"}],
            "categoryOptions": ["Planning"], "futureSetting": {"enabled":true},
            "tasks": [{"id":"task-1", "title":"Ship", "listId":"work", "category":"Planning",
                "updatedAt":"2026-10-01T00:00:00Z", "futureField":[1,2]}]
        }))
        .unwrap(),
    )
    .unwrap();
    for args in [
        vec!["task", "complete", "task-1"],
        vec!["task", "reopen", "task-1"],
        vec!["task", "update", "task-1", "--priority", "high"],
        vec!["task", "category", "add", "Other"],
    ] {
        run_json(&vault, &args);
        let saved: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        assert_eq!(saved["generalListName"], "Inbox");
        assert_eq!(saved["lists"][0]["id"], "work");
        assert_eq!(saved["tasks"][0]["listId"], "work");
        assert_eq!(saved["futureSetting"]["enabled"], true);
        assert_eq!(saved["tasks"][0]["futureField"], serde_json::json!([1, 2]));
        assert_ne!(saved["tasks"][0]["updatedAt"], "2026-10-01T00:00:00Z");
    }
}

fn paired_vault() -> TempDir {
    let vault = fixture();
    fs::create_dir_all(vault.path().join(".zerus")).unwrap();
    fs::write(
        vault.path().join(".zerus/properties.json"),
        r#"{
        "work":[{"name":"Related","type":"relation","relationTypeKey":"work",
            "relationMultiple":true,"relationPairId":"pair-1"}]
    }"#,
    )
    .unwrap();
    vault
}

#[test]
fn paired_relations_update_both_notes_and_undo_as_one_change() {
    let vault = paired_vault();
    let a = vault.path().join("work/Plan.md");
    let b = vault.path().join("work/Archived.md");
    let original_a = fs::read_to_string(&a).unwrap();
    let original_b = fs::read_to_string(&b).unwrap();
    let revision = run_json(&vault, &["note", "get", "work/Plan.md"])["data"]["note"]["revision"]
        .as_str()
        .unwrap()
        .to_string();
    let created = run_json(
        &vault,
        &[
            "note",
            "property",
            "set",
            "work/Plan.md",
            "Related",
            "[\"Old Plan\"]",
            "--if-revision",
            &revision,
        ],
    );
    let linked_b = fs::read_to_string(&b).unwrap();
    assert!(linked_b.contains("019f7922-8fae-7733-8357-48b16a134c38"));
    assert!(fs::read_to_string(&a)
        .unwrap()
        .contains("019f7923-8fae-7733-8357-48b16a134c39"));
    // A stale caller cannot change either side.
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "note",
            "property",
            "unset",
            "work/Plan.md",
            "Related",
            "--if-revision",
            &revision,
        ])
        .assert()
        .failure();
    assert_eq!(fs::read_to_string(&b).unwrap(), linked_b);
    let removed = run_json(
        &vault,
        &["note", "property", "unset", "work/Plan.md", "Related"],
    );
    assert!(!fs::read_to_string(&b).unwrap().contains("Related:"));
    run_json(
        &vault,
        &["undo", removed["data"]["transactionId"].as_str().unwrap()],
    );
    assert_eq!(fs::read_to_string(&b).unwrap(), linked_b);
    // A later edit on either endpoint blocks the whole undo before any writes.
    fs::write(&b, format!("{linked_b}\nNewer edit\n")).unwrap();
    let linked_a = fs::read_to_string(&a).unwrap();
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "undo",
            created["data"]["transactionId"].as_str().unwrap(),
        ])
        .assert()
        .failure();
    assert_eq!(fs::read_to_string(&a).unwrap(), linked_a);
    fs::write(&b, &linked_b).unwrap();
    run_json(
        &vault,
        &["undo", created["data"]["transactionId"].as_str().unwrap()],
    );
    assert_eq!(fs::read_to_string(&a).unwrap(), original_a);
    assert_eq!(fs::read_to_string(&b).unwrap(), original_b);
}

#[test]
fn relation_writes_refuse_missing_pairs_without_partial_edits() {
    let vault = paired_vault();
    fs::create_dir_all(vault.path().join("other")).unwrap();
    fs::write(
        vault.path().join("other/Target.md"),
        "---\nzerus-id: 019f7923-8fae-7733-8357-48b16a134c41\n---\n# Target\n",
    )
    .unwrap();
    fs::write(vault.path().join(".zerus/properties.json"), r#"{"work":[{"name":"Related","type":"relation","relationMultiple":true,"relationPairId":"pair-1"}]}"#).unwrap();
    let before = fs::read(vault.path().join("work/Plan.md")).unwrap();
    let output = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "note",
            "property",
            "set",
            "work/Plan.md",
            "Related",
            "Target",
        ])
        .output()
        .unwrap();
    assert!(!output.status.success());
    let failure: Value = serde_json::from_slice(&output.stderr).unwrap();
    assert!(failure["error"]["message"]
        .as_str()
        .unwrap()
        .contains("inverse definition"));
    assert_eq!(fs::read(vault.path().join("work/Plan.md")).unwrap(), before);
}

#[test]
fn task_list_selection_matches_the_app_and_preserves_other_tasks() {
    let vault = fixture();
    fs::create_dir_all(vault.path().join(".zerus")).unwrap();
    fs::write(vault.path().join(".zerus/tasks.json"), r#"{"generalListName":"Inbox","lists":[{"id":"work","name":"Work"}],"tasks":[],"categoryOptions":[]}"#).unwrap();
    let lists = run_json(&vault, &["task", "lists"]);
    assert_eq!(lists["data"][0]["name"], "Inbox");
    let task = run_json(&vault, &["task", "create", "Ship", "--list", "Work"]);
    assert_eq!(task["data"]["listId"], "work");
    run_json(&vault, &["task", "create", "Personal"]);
    assert_eq!(
        run_json(&vault, &["task", "list", "--list", "work"])["data"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        run_json(&vault, &["task", "list", "--list", "Inbox"])["data"][0]["title"],
        "Personal"
    );
    run_json(&vault, &["task", "update", "Ship", "--clear-list"]);
    assert_eq!(
        run_json(&vault, &["task", "list", "--list", "general"])["data"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
    run_json(&vault, &["task", "update", "Ship", "--list", "work"]);
    assert_eq!(
        run_json(&vault, &["task", "get", "Ship"])["data"]["listId"],
        "work"
    );
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "task",
            "update",
            "Ship",
            "--list",
            "missing",
        ])
        .assert()
        .failure();
    assert_eq!(
        run_json(&vault, &["task", "get", "Ship"])["data"]["listId"],
        "work"
    );
}

#[test]
fn interrupted_relation_transaction_can_be_recovered_without_overwriting_edits() {
    for interrupted_undo in [false, true] {
        let vault = paired_vault();
        let transaction = run_json(
            &vault,
            &[
                "note",
                "property",
                "set",
                "work/Plan.md",
                "Related",
                "Old Plan",
            ],
        );
        let transaction = if interrupted_undo {
            run_json(
                &vault,
                &[
                    "undo",
                    transaction["data"]["transactionId"].as_str().unwrap(),
                ],
            )
        } else {
            transaction
        };
        let id = transaction["data"]["transactionId"].as_str().unwrap();
        let journal_path = vault.path().join(format!(".zerus/history/cli/{id}.json"));
        let mut journal: Value = serde_json::from_slice(&fs::read(&journal_path).unwrap()).unwrap();
        journal["pending"] = true.into();
        // Model a crash after only the source note was written.
        let inverse = &journal["changes"][1];
        fs::write(
            vault.path().join(inverse["path"].as_str().unwrap()),
            inverse["before"].as_str().unwrap(),
        )
        .unwrap();
        fs::write(&journal_path, serde_json::to_vec(&journal).unwrap()).unwrap();
        let blocked = cli()
            .args([
                "--vault",
                vault.path().to_str().unwrap(),
                "--json",
                "note",
                "property",
                "unset",
                "work/Plan.md",
                "Related",
            ])
            .output()
            .unwrap();
        assert!(!blocked.status.success());
        assert_eq!(
            serde_json::from_slice::<Value>(&blocked.stderr).unwrap()["error"]["code"],
            "transaction_pending"
        );
        run_json(&vault, &["undo", id]);
        for change in journal["changes"].as_array().unwrap() {
            assert_eq!(
                fs::read_to_string(vault.path().join(change["path"].as_str().unwrap())).unwrap(),
                change["before"].as_str().unwrap()
            );
        }
        run_json(
            &vault,
            &[
                "note",
                "property",
                "set",
                "work/Plan.md",
                "Related",
                "Old Plan",
            ],
        );
    }
}

#[test]
fn relation_bulk_and_schema_removal_cannot_bypass_synchronization() {
    let vault = paired_vault();
    let before = fs::read(vault.path().join("work/Plan.md")).unwrap();
    for args in [
        vec![
            "bulk",
            "property-set",
            "Plan",
            "Related",
            "Old Plan",
            "--yes",
        ],
        vec![
            "schema",
            "remove",
            "work",
            "Related",
            "--purge-values",
            "--yes",
        ],
    ] {
        cli()
            .args(["--vault", vault.path().to_str().unwrap()])
            .args(args)
            .assert()
            .failure();
    }
    assert_eq!(fs::read(vault.path().join("work/Plan.md")).unwrap(), before);
    assert_eq!(
        run_json(&vault, &["schema", "list", "work"])["data"][0]["relationPairId"],
        "pair-1"
    );
    run_json(
        &vault,
        &[
            "note",
            "property",
            "set",
            "--path",
            "work/Plan.md",
            "Related",
            "Old Plan",
        ],
    );
    cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "type",
            "move",
            "work/Plan.md",
            "--to",
            "other",
        ])
        .assert()
        .failure();
    assert!(vault.path().join("work/Plan.md").is_file());
    assert!(!vault.path().join("other/Plan.md").exists());
}

#[test]
fn occupied_single_inverse_blocks_relation_replacement_before_any_writes() {
    let vault = paired_vault();
    fs::create_dir_all(vault.path().join("other")).unwrap();
    fs::write(vault.path().join(".zerus/properties.json"), r#"{
        "work":[{"name":"Related","type":"relation","relationTypeKey":"other","relationMultiple":true,"relationPairId":"pair-1"}],
        "other":[{"name":"Owner","type":"relation","relationTypeKey":"work","relationMultiple":false,"relationPairId":"pair-1"}]
    }"#).unwrap();
    let target = vault.path().join("other/Target.md");
    fs::write(&target, "---\nzerus-id: 019f7923-8fae-7733-8357-48b16a134c41\nOwner: Old Plan\n---\n# Target, with comma\n").unwrap();
    let before_a = fs::read(vault.path().join("work/Plan.md")).unwrap();
    let before_b = fs::read(&target).unwrap();
    let output = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "note",
            "property",
            "set",
            "work/Plan.md",
            "Related",
            "[\"Target, with comma\"]",
        ])
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(
        serde_json::from_slice::<Value>(&output.stderr).unwrap()["error"]["message"]
            .as_str()
            .unwrap()
            .contains("already points")
    );
    assert_eq!(
        fs::read(vault.path().join("work/Plan.md")).unwrap(),
        before_a
    );
    assert_eq!(fs::read(&target).unwrap(), before_b);
    run_json(
        &vault,
        &["note", "property", "unset", "other/Target.md", "Owner"],
    );
    run_json(
        &vault,
        &[
            "note",
            "property",
            "set",
            "work/Plan.md",
            "Related",
            "[\"Target, with comma\"]",
        ],
    );
    assert!(fs::read_to_string(&target)
        .unwrap()
        .contains("019f7922-8fae-7733-8357-48b16a134c38"));
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
    assert_eq!(value["data"][0]["properties"]["status"], "active");
    assert_eq!(
        value["data"][0]["properties"]["zerus-id"],
        "019f7922-8fae-7733-8357-48b16a134c38"
    );
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
            "019f7922",
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
    assert_eq!(value["data"]["properties"]["status"], "active");
    assert_eq!(value["data"]["note"]["properties"]["status"], "active");
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
    assert_eq!(value["data"][0]["properties"]["status"], "active");
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

#[test]
fn stable_id_backlinks_survive_renames_and_do_not_match_prefixes_or_stale_labels() {
    let vault = fixture();
    fs::write(
        vault.path().join("work/Plan.md"),
        "---\nzerus-id: 019f7922-8fae-7733-8357-48b16a134c38\n---\n# Renamed Plan\n",
    )
    .unwrap();
    fs::create_dir_all(vault.path().join(".zerus")).unwrap();
    fs::write(
        vault.path().join(".zerus/properties.json"),
        r#"{"work":[{"name":"Related","type":"relation"}]}"#,
    )
    .unwrap();
    fs::write(vault.path().join("work/Source.md"),
        "---\nRelated: \"zerus:019f7922-8fae-7733-8357-48b16a134c38|Old title\"\n---\n# Source\n\n[[zerus:019f7922-8fae-7733-8357-48b16a134c38|Old title]]\n").unwrap();
    fs::write(
        vault.path().join("work/Unrelated.md"),
        "# Unrelated\n\n[[Renamed Plan Extended]] [[zerus:missing|Renamed Plan]]\n",
    )
    .unwrap();
    let output = cli()
        .args([
            "--vault",
            vault.path().to_str().unwrap(),
            "--json",
            "links",
            "work/Plan.md",
        ])
        .output()
        .unwrap();
    assert!(output.status.success());
    let value: Value = serde_json::from_slice(&output.stdout).unwrap();
    let backlinks = value["data"]["backlinks"].as_array().unwrap();
    assert_eq!(backlinks.len(), 1);
    assert_eq!(backlinks[0]["viaBody"], true);
    assert_eq!(backlinks[0]["viaRelation"], true);
}
