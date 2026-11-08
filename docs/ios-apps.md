# iOS app coexistence

Zerus keeps the desktop/web app, Tauri iOS app, and SwiftUI iOS preview in one
repository. Both iOS implementations remain supported during native evaluation.

| Area | Owner |
| --- | --- |
| Desktop/web and Tauri mobile interface | `src/` |
| Tauri runtime, mobile bridge, platform packaging | `src-tauri/` |
| SwiftUI interface, editor, vault implementation, icons, native configuration | `native-ios/` |
| Shared iOS integrations and ChatGPT protocol | `packages/apple/` |

## Build and release selection

| Command | Target |
| --- | --- |
| `pnpm desktop:build` | macOS desktop DMG |
| `pnpm ios:new-build` or `pnpm ios:tauri:new-build` | Existing Tauri iOS archive and IPA |
| `pnpm testflight` or `pnpm ios:tauri:testflight` | Upload the existing Tauri IPA |
| `pnpm ios:native:build --device <UDID>` | SwiftUI development-signed device preview |
| `pnpm ios:native:build --simulator <UDID>` | SwiftUI Simulator preview |
| `pnpm ios:native:verify` | SwiftUI identity, sources, assets, and package boundaries |
| `pnpm ios:shared:test` | Shared ChatGPT core tests |

The Tauri build number remains in `src-tauri/tauri.conf.json`. Native marketing
and build versions remain in `native-ios/project.yml`. Reorganizing the repository
does not advance either version or submit a release. The SwiftUI preview has no
archive/export/TestFlight command yet.

## Shared files, independent implementations

SwiftUI and desktop implement vault operations in their own languages. Changes to
portable Markdown, frontmatter properties and relations, attachments, or `.zerus`
metadata must account for both implementations. Use the existing parity guide
and relevant storage tests to verify compatibility; a folder reorganization must
not silently introduce a new vault format or migrate user files.

Review format changes in one commit where possible, including both consumers and
their existing behavioral checks. App-private preferences, security-scoped access,
credentials, and provider continuation data remain app-private.

## Eventual replacement

Keep the native preview's separate identity until its acceptance is explicit.
Before replacing the shipping iOS app, review the production bundle identity,
App Store signing and entitlements, local data and settings, Keychain access, and
saved vault permissions. Verify the exact release binary and existing-user upgrade
on a physical device. Only then switch the default iOS release commands and remove
the Tauri mobile interface/bridge. Desktop Tauri remains independent of that work.

## Continuous integration

`.github/workflows/native-ios.yml` checks the native app boundaries, runs the
shared ChatGPT core tests, and builds the native app for an available iPhone
Simulator with iOS 26 or newer. It does not require signing credentials or install
on a physical device. The existing desktop/web/Rust workflow stays in place.
Hosted native unit tests and UI journeys remain explicit local checks; some UI
journeys require QA services or provider fixtures.
