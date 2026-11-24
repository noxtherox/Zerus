# iOS app ownership and releases

SwiftUI in `native-ios/` is the production iPhone/iPad app, replacing Tauri mobile.
Desktop/web remain in `src/` and `src-tauri/`; shared Apple services stay in
`packages/apple/`. Native build inputs do not depend on Tauri paths.

`pnpm ios:new-build` creates and exports a signed SwiftUI archive.
`pnpm testflight` uploads it to the existing Zerus app (`com.zerus.notes`).
Marketing/build versions live in `native-ios/project.yml`; new builds exceed
completed native and legacy build numbers. Explicit `ios:tauri:*` commands
retain the legacy pipeline for recovery. Native development commands target the
production identity too; do not install development builds over valuable data
without a backup.

Requires iOS 26 or newer. The production identity preserves the app container
and Keychain group. The native app reads the legacy active vault bookmark and
continues using the same Markdown folder without converting its contents.
If access cannot be restored, select the folder again in Files. Old web-view
preferences and provider sessions are retained in the container but are not
converted to native settings. The former `com.zerus.notes.native` preview has
its own container; select its vault through Files to use it in production.
Physical upgrade verification is required before claiming delivery complete.

## Shared files, independent implementations

SwiftUI and desktop implement vault operations in their own languages. Changes to
portable Markdown, frontmatter properties and relations, attachments, or `.zerus`
metadata must account for both implementations. Use the existing parity guide
and relevant storage tests to verify compatibility; a folder reorganization must
not silently introduce a new vault format or migrate user files.

Review format changes in one commit where possible, including both consumers and
their existing behavioral checks. App-private preferences, security-scoped access,
credentials, and provider continuation data remain app-private.

## Continuous integration

`.github/workflows/native-ios.yml` checks the native app boundaries, runs the
shared ChatGPT core tests, and builds the native app for an available iPhone
Simulator with iOS 26 or newer. It does not require signing credentials or install
on a physical device. The existing desktop/web/Rust workflow stays in place.
Hosted native unit tests and UI journeys remain explicit local checks; some UI
journeys require QA services or provider fixtures.
