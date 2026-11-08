# Google Drive vaults on iOS

Zerus connects directly to the Google Drive API from the iPhone. Google Drive's
iOS Files provider cannot grant the folder access required by a vault. This
integration opens the selected folder through Google's API instead.

## One-time developer setup

1. Open [Google Cloud Console](https://console.cloud.google.com/) and select or
   create a project for Zerus.
2. Enable the [Google Drive API](https://console.cloud.google.com/apis/library/drive.googleapis.com).
3. In [Google Auth Platform: Branding](https://console.cloud.google.com/auth/branding),
   configure the application name and contact emails.
4. In [Audience](https://console.cloud.google.com/auth/audience), select External
   for personal Google accounts, leave the app in Testing, and add the Google
   accounts that will test it.
5. In [Data Access](https://console.cloud.google.com/auth/scopes), add
   `https://www.googleapis.com/auth/drive`. Existing vaults contain files created
   outside Zerus; the narrower `drive.file` scope does not grant arbitrary access
   to the existing contents of a folder.
6. In [Clients](https://console.cloud.google.com/auth/clients), create an **iOS**
   OAuth client for bundle identifier **`com.zerus.notes`**. Do not create a web
   client or a service account for this integration.
7. Configure the public client ID from the repository root:

   ```sh
   node scripts/configure-google-drive-ios.mjs YOUR_IOS_CLIENT_ID.apps.googleusercontent.com
   ```

   This writes `ZerusGoogleDriveClientID` and the reversed client-ID callback scheme
   into the source iOS plist, the existing generated plist, and the XcodeGen project
   configuration, preserving other
   URL schemes. The ID is public app configuration; no client secret is needed.
8. Include the configuration in the next iOS build. Use `pnpm ios:new-build` when
   explicitly requesting a new iOS build; `pnpm testflight` uploads an existing IPA.

End users do not create Google Cloud projects. They tap **Google Drive** in vault
setup, sign in on Google's system authentication screen, navigate to their vault
folder, and tap **Open this vault**.

## Permissions and credentials

Authorization uses the system authentication session, authorization code + PKCE,
and a random state checked against the callback. Access/refresh tokens remain in
the native layer, stored in the iOS Keychain with device-only accessibility. They
are never returned to JavaScript or sent to a Zerus server. The native HTTP bridge
accepts only Google Drive file endpoints. Reconnecting an existing account rejects
a different account so pending edits cannot be uploaded to the wrong Drive.

The Google consent screen grants broad Drive access. The vault backend confines
its file operations to the chosen folder, although authorization itself is not
limited to that folder. This is a restricted scope: review Google's production
verification requirements before distributing the integration publicly. Google
test-mode refresh tokens commonly expire after seven days; use **Reconnect Google
account** in **Settings → Vault** or the folder browser when needed. Reconnecting
from Settings keeps the current vault and retries saving pending edits before
refreshing. Cancelled sign-in or a different account leaves the connection intact.
No production-verification exemption
or zero-cost assessment is assumed.

## Current behavior and limits

- **Online operation:** folder discovery, reading, saving, and refreshing require
  connectivity. Settings → **Save and refresh Google Drive** loads external changes.
  There is no background/offline sync engine or complete offline vault cache.
- Note edits are staged locally before the save debounce and recovered after
  reopening the vault. These recovery copies use app-local browser storage and
  remain subject to its capacity and app-data deletion; they are not an offline
  backup. Recovery still needs access to the Drive vault. File uploads and metadata
  changes are not queued offline.
- Existing file updates check the observed Drive version and send `If-Match`.
  Conditional metadata reads and updates use Drive v2, which exposes the file
  `etag` in JSON; browsing, downloads, and creation use v3.
  A missing version lock or a conflict stops the update. If Drive changed since
  the note was loaded, review both versions in the mobile conflict dialog.
- Google Drive allows duplicate names. Opening a vault from the Drive picker
  checks for ambiguous paths and offers a duplicate review with dates and text
  previews. Rename individual copies to preserve both and keep the original name
  on the copy existing links should open. Renames apply to Drive on all devices,
  check the reviewed version, and rescan before opening. Folders and shortcuts
  can also be renamed, but have no text preview. New file
  creation checks current siblings and uses pre-generated IDs, but Drive has no
  atomic unique-name guarantee: simultaneous same-name creations by separate
  clients can still produce duplicates. If reopening a saved vault fails with
  duplicates, choose another vault, then select the same folder in the Google
  Drive picker to review them.
- The picker browses **My Drive**. Shared drives and shortcuts are not supported;
  shortcuts are never followed outside the vault. Use actual Markdown files,
  not Google Docs documents.
- File uploads are limited to 25 MB per native request (multipart overhead counts).
  Binary assets use the same vault backend. Any synced file location can select
  **Google Drive** in the iOS provider chooser and use the authenticated Drive
  browser; the device-local
  mapping stores account and folder identifiers, never OAuth tokens. Linked files
  are downloaded on demand for status, PDF/HTML preview, and iOS Quick Look.
- Removal uses Google Drive trash rather than permanently deleting remote items.

## Validation before shipping

Automated tests cover Drive pagination, Markdown and binary transport, writes,
folder creation/renaming, trash, duplicate paths, and conflict rejection. Native
OAuth and actual Drive version-lock behavior must also be tested with the configured
client on an iPhone. Test cancellation, expired/revoked consent, reconnecting,
relaunch, airplane mode during a save, and edits from the desktop Drive client.

References: [Google native-app OAuth](https://developers.google.com/identity/protocols/oauth2/native-app),
[Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth),
[Drive uploads](https://developers.google.com/workspace/drive/api/guides/manage-uploads),
[pre-generated file IDs](https://developers.google.com/workspace/drive/api/guides/create-file).


## Standalone SwiftUI preview

The native preview uses the separate bundle identifier `com.zerus.notes.native`
so it can be tested alongside the existing app. Its direct Drive integration
needs an additional **iOS OAuth client** registered for that identifier, in the
same Google Cloud project if desired. The public client ID is sufficient; no
client secret is needed.

Configure the standalone target explicitly:

```sh
node scripts/configure-google-drive-ios.mjs --native YOUR_NATIVE_IOS_CLIENT_ID.apps.googleusercontent.com
```

This changes only `native-ios/project.yml` and `native-ios/Info.plist`, retaining
other callback schemes and the SwiftUI scene manifest. The configuration
survives XcodeGen. Omitting `--native` continues to configure only the Tauri
app. Never reuse an iOS client registered for the other bundle identifier.
Build and install the native preview with the commands in
[the native guide](native-ios.md).

The native preview now has an account/folder browser at **Settings → File
locations → Google Drive**, and each shared file location offers **Choose
Google Drive folder**. A mapping is stored privately on this device; shared
notes keep their original location ID and relative document path. Existing
connected documents can then download for native Quick Look/sharing or be
copied into the vault. Downloads resolve the path freshly, reject duplicate
names and shortcuts, and check the file and its ancestors again before
exposing the bytes. Ordinary files up to 50 MB are supported. Downloaded
previews are temporary snapshots; they cannot become a connection to the
temporary local file. Disconnecting keeps shared notes, mappings and original
Drive files.

Preview 0.3.56 also offers **Open Google Drive vault** from the welcome screen
and Settings → Vaults. It materializes an ordinary-file working copy in private
app storage, with a separate sync ledger outside the vault. A completed cache
reopens offline; native edits save locally before syncing. The saved-vault list
retains the account/folder association. Cancel leaves the current vault selected.

Sync compares local bytes and observed Drive versions, stages incoming changes
through the native file transaction, preserves foreign file bytes, and presents
conflicting local/Drive versions for explicit review. Uploads and trash use
conditional version locks. Renames retain Drive file IDs, and interrupted creates
retain their preallocated IDs for retry. Preview 0.3.57 also persists the sent
identity and content hash before each upload. If the response is lost, matching
Drive bytes become the acknowledged baseline even if local writing continued or
the local file was removed; newer writing or deletion then syncs separately.
An identity match with different remote bytes still requires review. Records
from earlier previews without sent hashes remain readable. Preview 0.3.58 applies
reviewed note/history resources as one exact-byte transaction instead of deriving
history a second time. Supported local saves already captured their drafts;
unchanged history remains available. Chosen Drive files retain server modified
and creation dates across offline reopening. Drive dates are also applied to
ordinary downloaded changes. Remote writes are per file: Drive does not provide a multi-file atomic
transaction, so interruption can leave a partially synchronized remote tree.

The standalone backend limits uploads to 25 MB, individual downloads to 50 MB,
incoming changed bytes to 256 MB per sync, and enumeration to 100,000 entries
and 64 levels. Duplicate/equivalent paths stop opening; rename duplicates in
Drive before retrying. Google-native documents and shortcuts are not materialized.
Preview 0.3.59 recovers a completed private working copy’s Drive association from
its validated sync record when the saved-vault list is missing, unreadable, or
has an older row without Drive metadata. Unknown list bytes stay intact. Cache
records must match this app’s private account/folder directory; ordinary Files
folders do not acquire Drive authority from a copied record. Damaged, incomplete,
misbound or redirected private caches refuse activation and keep their files.
Queued-create recovery after later remote relocation/replacement,
unsupported-item collisions, and large-vault behavior need further work.

The separate client is still absent in the installed preview. Live OAuth,
consent/reconnect/expiry and actual Drive version-lock behavior remain unverified.
Automated native transport/file-owner checks do not establish those live results.
An unconfigured build explains setup and disables sign-in. Files-based native
vaults remain usable; the full native migration remains in progress.
