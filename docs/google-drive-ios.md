# Retired direct Google Drive integration

Direct Google Drive integration is excluded from the native iOS/macOS goal.
The native iOS app no longer offers Drive vaults, linked-file Drive mappings,
account/folder browsing, sign-in or sync/conflict controls. New native Drive
requests fail locally without authenticating or accessing the network.

Use Files/iCloud Drive or on-device storage. For a linked document, choose its
folder in File locations or locate the individual document through Files.
Existing shared location names and relative note paths remain usable with those
local mappings. Mac folder access continues through the normal system picker.

Existing records, Keychain credentials, working copies, sync ledgers and recovery
drafts are kept. No remote file, credential or note is deleted automatically.
Legacy data models and transport owners remain for retained-record compatibility;
they do not expose a new native Google Drive workflow. The configuration script
and shared service code remain legacy tooling, not native setup instructions.
No Google OAuth client, consent or live Drive acceptance is a completion gate.

Removal evidence: `artifacts/native-macos/features489/verification.json`.
