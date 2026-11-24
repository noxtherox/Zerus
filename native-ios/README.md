# Zerus native iOS app

The production SwiftUI iPhone/iPad app uses `com.zerus.notes` and replaces
Tauri mobile. Requires iOS 26+. `pnpm ios:new-build` archives and exports it;
`pnpm testflight` uploads the existing IPA.

The app owns `Sources/`, `Resources/` (including its icons), `Info.plist`,
`Entitlements.plist`, and `project.yml`. Shared Apple services live in
`../packages/apple/`; no native build input comes from `src-tauri/`.

Last launch-verified physical delivery: **0.3.107 (1)** is installed and launch-verified on
**iPhone 18 Pro Max / iOS 27.2**, including the new menu/navigation update. The
existing 483-note workspace reopened. Local delivery evidence and the retained
signed app are under `artifacts/native-ios/delivery107/`.

## Navigation

The top-left menu opens the folder Library as a drawer, shifting the current
screen to the right. Swipe right from the left edge to open it; swipe left,
tap the shifted screen, or use Close folders to dismiss it. Closing the drawer
keeps the current tab and scroll position. Folder actions, collections and
vault switching remain available in the drawer. All notes, External notes, Files
and Saved links appear above folders; Archive, Recently Deleted and Vaults appear
at the bottom. Pinned remains available through the Notes collection picker. The
icon beside the Folders heading creates a folder; folder names, note counts
and action menus use consistent columns. Notes, folder collections, Files and
Saved links have a separate Sort and filter button beside their search field.
It opens the same collection controls available in Settings.

The five bottom actions stay the same. They slide away when scrolling down
and return when scrolling up or reaching the top. Opening the drawer or
changing destinations restores them. VoiceOver keeps them visible, and Reduce
Motion disables the drawer and navigation transitions.

Vault setup and the saved-vault list offer Files/iCloud Drive and on-device
storage. Google Drive vault choices and vault-specific sync settings have been
removed. Saved Drive records, working copies and conflict recovery are retained;
linked-file location mapping remains separate.

## Development

Use macOS with Xcode and its iOS SDK, XcodeGen (`brew install xcodegen`), Node.js,
and pnpm. Run commands from the repository root after `pnpm install`:

```sh
pnpm ios:native:verify
pnpm ios:shared:test
pnpm ios:native:build --simulator <simulator-UDID>
pnpm ios:native:test --simulator <simulator-UDID> --unit-only
pnpm ios:native:test --simulator <simulator-UDID>
pnpm ios:native:build --device <physical-iphone-UDID>
pnpm ios:native:install --device <physical-iphone-UDID>
```

Builds regenerate the ignored Xcode project from `project.yml`. Build products
stay under `artifacts/native-ios/`. `--unit-only` runs the hosted unit tests;
omitting it also runs UI journeys, some of which require their documented QA
services. Tests require an explicitly selected Simulator. Physical installation
is a separate, explicit command and requires the configured signing team.

See [the native guide](../docs/native-ios.md) for device checks and current
limitations, and [the coexistence guide](../docs/ios-apps.md) for ownership and
release boundaries.
