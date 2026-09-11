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
account** in the folder browser when needed. No production-verification exemption
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
- Google Drive allows duplicate names. Zerus rejects ambiguous paths. New file
  creation checks current siblings and uses pre-generated IDs, but Drive has no
  atomic unique-name guarantee: simultaneous same-name creations by separate
  clients can still produce duplicates that must be renamed in Drive.
- The picker browses **My Drive**. Shared drives and shortcuts are not supported;
  shortcuts are never followed outside the vault. Use actual Markdown files,
  not Google Docs documents.
- File uploads are limited to 25 MB per native request (multipart overhead counts).
  Binary assets use the same vault backend. External filesystem path mappings and
  opening a remote file in another native app are not provided by this integration.
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
