# Zerus SwiftUI preview

This is the native iPhone/iPad application, developed alongside the existing
Tauri iOS app in the same repository. It retains the **Zerus Native** display name
and `com.zerus.notes.native` identity so both can stay installed while the native
app is evaluated. It does not replace the Tauri build or its TestFlight workflow.

The app owns `Sources/`, `Resources/` (including its icons), `Info.plist`,
`Entitlements.plist`, and `project.yml`. Shared Apple services live in
`../packages/apple/`; no native build input comes from `src-tauri/`.

Latest physical delivery: **0.3.107 (1)** is installed and launch-verified on
**iPhone 18 Pro Max / iOS 27.2**, including the new menu/navigation update. The
existing 483-note workspace reopened. Local delivery evidence and the retained
signed app are under `artifacts/native-ios/delivery107/`.

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

For Tauri, `pnpm ios:tauri:new-build` and `pnpm ios:tauri:testflight` are explicit
aliases for the established `pnpm ios:new-build` and `pnpm testflight` commands.
These commands do not build or upload SwiftUI. A native App Store identity and
upgrade path will be decided when the SwiftUI app is accepted as the replacement.

See [the native guide](../docs/native-ios.md) for device checks and current
limitations, and [the coexistence guide](../docs/ios-apps.md) for ownership and
release boundaries.
