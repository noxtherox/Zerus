# Native macOS navigation archives

Native macOS can recover per-vault window state from private archive files when
its existing `zerus.mac.navigation.v1.*` preference is absent. A current
preference always takes precedence. This includes tabs, pinned tabs, the active
note, collection queries and views, inspector visibility and folder state.
Vault files and folder-access bookmarks are not moved by this mechanism.

This is an offline maintenance operation, not automatic pruning. The maintenance
command only selects version-1 navigation records paired with a matching
bookmark for a missing, unresolvable vault under the current user's OS temporary
directory. Recent vaults, existing vaults and unpaired records stay in preferences.
Unknown historical records are preserved byte for byte rather than discarded.

## Plan and apply

Compile the command from the repository root:

```sh
swiftc -parse-as-library native-macos/Sources/MacNavigationArchive.swift \
  scripts/native-macos-navigation-archive.swift \
  -o /tmp/zerus-navigation-archive
```

Pass an installed native app that supports archives and a private, fresh report
directory. The examples use placeholders for both paths:

```sh
/tmp/zerus-navigation-archive plan /private/path/to/plan '/path/to/Zerus Native.app'
/tmp/zerus-navigation-archive apply /private/path/to/apply '/path/to/Zerus Native.app'
```

Review the plan before applying it. Stop every Zerus Native instance before
`apply` or `restore`; the command refuses while any is running. An app without
`ZerusNavigationArchiveVersion = "1"` in its actual `Contents/Info.plist` is also
refused. Keep native apps stopped until the operation finishes.

Apply creates `navigation-backup.plist` before moving any record. Each exact
navigation value is written under
`~/Library/Application Support/Zerus Native/Navigation Archive/<key-hash>.json`
with private permissions and synchronized before its preference is removed.
A changed preference, conflicting archive, symlink or non-ordinary archive file
is refused. Earlier successful entries remain safely archived if a later entry
fails; retain the backup and inspect the outcome before retrying.

The JSON report records eligible and affected keys, encoded preference-domain
sizes and whether unselected entries remained unchanged. Reports and backups
contain private state; do not publish them.

## Restore and older previews

Older native previews do not understand archive files. Restore inactive window
state before using an older preview if it needs that state:

```sh
/tmp/zerus-navigation-archive restore /private/path/to/apply '/path/to/Zerus Native.app'
```

Use the original apply directory containing `navigation-backup.plist`. Restore
only fills absent preferences; it never overwrites a newer preference. Archive
files remain as fallback copies. Restart an app only after restore finishes.

The measured preference-domain reduction is storage evidence. It does not by
itself establish input latency, rendering speed or launch-time improvements.
