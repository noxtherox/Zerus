# Repository release instructions

## Release documentation review

- Before every release, review `README.md` against the release's current
  features, supported platforms, setup steps, commands, dependencies, and
  limitations. Add newly relevant information, update changed behavior, and
  remove obsolete claims before creating the version commit and tag.

## Desktop release channels

- A request to **make a new release** includes the notarized macOS release and
  the regular Windows release. It does not include building, submitting,
  certifying, or publishing a Microsoft Store MSIX.
- Only prepare or publish a Microsoft Store release when the user explicitly
  requests a new Microsoft Store or Store MSIX version. Do not infer Store
  authorization from a general release request.
- The user's **Microsoft Store notarized version** means the MSIX certified and
  signed by Microsoft through Store publishing. Follow `docs/WINDOWS.md` for
  Store identity, packaging, validation, and submission requirements.
- Build and validate the release's `_store.msix` with the configured production
  Store identity, submit it to the matching product in Microsoft Partner Center,
  and complete certification and publication. A GitHub release containing an
  unsigned MSIX does not fulfill this requirement.
- Verify that Microsoft's live Store package metadata serves the intended
  release version before reporting the Store release as complete. Account for
  the documented app-to-MSIX version mapping.
- If Store access or credentials are missing, report the exact missing setup
  and the prepared package's location. If certification or publication is still
  pending, report that status explicitly. Do not claim the full release is
  complete while the Microsoft Store version is blocked or pending.

## iOS preview handoff

- After every iOS implementation or change, build and install the updated app
  in an iOS Simulator, display the simulator in the user-visible Device panel,
  and open the affected screen so the user can preview it there without asking.
- Use the device tools to select and open the simulator, interact with the app,
  and capture a screenshot. Show the screenshot in the response and leave the
  simulator available for the user to inspect.
- Verify the changed interaction in the simulator when applicable. If simulator
  tooling or the build is blocked, report the exact blocker and mark visual
  verification as pending; do not substitute a web preview for an iOS preview.
- Simulator preview builds must not advance the App Store build number or
  trigger an archive, export, or TestFlight upload.

## Build target resolution

- In any workspace that does not explicitly establish its target platform,
  **new build** by itself is ambiguous. Ask whether the user wants a macOS
  desktop DMG or an iOS App Store build before running a build command.
- Do not infer the target from recent conversation or the last platform that
  was built.
- Explicit requests such as **native DMG**, **Tauri DMG**, or
  **new iOS build** do not require clarification.

## macOS desktop terminology

- During the transition, the SwiftUI app in `native-macos/` is the primary
  desktop codebase and the Tauri/React app remains supported. Tag
  `tauri-baseline` marks the last Tauri-only state.
- **Native macOS build** or **native DMG** means run `pnpm macos:native:dmg`
  (identity `com.zerus.notes.macos.native`, see `docs/native-macos.md`).
- **Tauri build**, **Tauri DMG**, or any **release** request means run
  `pnpm desktop:build`. This creates and verifies the Tauri macOS desktop
  artifacts, including the DMG, and remains the release pipeline until the user
  explicitly switches releases to the native app.
- **New desktop build**, **macOS build**, or **build the DMG** alone is
  ambiguous while both apps are supported; ask whether the user wants the
  native or the Tauri DMG.

## iOS terminology

- SwiftUI in `native-ios/` is the accepted production iOS replacement, using
  `com.zerus.notes`. Shared services remain in `packages/apple/`; native inputs
  must not depend on `src-tauri/` paths.
- `pnpm ios:new-build` and `pnpm testflight` build/export and upload SwiftUI.
  The canonical native version/build record is `native-ios/project.yml`.
- `pnpm ios:native:build`, `ios:native:test`, and `ios:native:install` target
  the production SwiftUI identity. Preserve user vault data on device updates.
- Explicit `ios:tauri:new-build` and `ios:tauri:testflight` retain the legacy
  Tauri release pipeline and its own version configuration for recovery.

- **New iOS build** or **new App Store build** means run `pnpm ios:new-build`.
  This advances the canonical iOS build number, creates the signed Xcode archive,
  verifies it, and exports its IPA. The command computes the next number from
  the persistent configuration and latest completed archive; do not assume a
  build number from conversation history.
- **Push/upload the current build** means do not rebuild or increment anything.
  Run `pnpm testflight` to validate and upload the existing IPA.
- **New iOS build and push it** means run `pnpm ios:new-build`, then
  `pnpm testflight`.

## iOS toolchain and launch preflight

- Before every `pnpm ios:new-build`, direct Xcode archive, or TestFlight upload
  of a newly built binary, run `pnpm platform:verify` and verify the selected
  developer directory and Xcode version with `xcode-select -p` and
  `xcodebuild -version`.
- Before advancing an iOS build number, require Apple device tooling to
  initialize successfully. Check `xcrun devicectl list devices --timeout 5`
  and an Xcode build-settings or generic-device command using the selected
  Xcode. Treat any of the following as a hard blocker: a failure to load
  `DVTCoreDeviceCore`, a missing CoreDevice symbol, an out-of-date
  CoreSimulator framework, or an inability to load simulator/device support.
  These errors mean Xcode and the macOS CoreDevice/CoreSimulator components do
  not match. Stop before changing version files, archiving, exporting, or
  uploading, and report that macOS/Xcode must be updated or repaired.
- Apps built with the iOS 27 SDK must adopt the scene lifecycle. Keep
  `UIApplicationSceneManifest`, `UIApplicationSupportsMultipleScenes = true`,
  the `UIWindowSceneSessionRoleApplication` configuration, and
  `UISceneDelegateClassName = TaoSceneDelegate` in both the canonical iOS plist
  and generated Xcode project. `pnpm platform:verify` must fail if any part is
  missing.
- The `TaoSceneDelegate` requirements apply to Tauri iOS. The standalone SwiftUI
  app owns its lifecycle through `App`/`WindowGroup`; do not add TaoSceneDelegate
  to that target. Verify its own boundaries with `pnpm ios:native:verify`.
- While Tauri 2.11 resolves tao `0.35.x`, retain the pinned upstream tao scene
  ownership fix in `src-tauri/Cargo.toml` and `Cargo.lock`. Do not remove the
  pin until the resolved Tauri runtime accepts tao `>= 0.36.0`; a scene
  manifest without that fix can replace the iOS 27 launch trap with an
  `EXC_BAD_ACCESS` during scene connection.
- After creating an archive, inspect the archived app's actual `Info.plist`,
  not only source configuration. Confirm its bundle version matches the
  canonical configuration and its scene manifest uses the appropriate lifecycle
  (SwiftUI scenes for native; `TaoSceneDelegate` for legacy Tauri).
  Verify the archive signature before export.
- Before uploading a build produced with a newly selected Xcode or iOS SDK,
  install the exact exported release binary on a physical iPhone running that
  OS generation and confirm that it remains open past launch. Check that the
  device produced no new Zerus crash or Jetsam report. If a compatible device
  is unavailable, report physical launch verification as pending and do not
  claim the iOS release is complete.

Never pass Tauri's `--build-number` option for an absolute App Store build
number; Tauri treats it as a suffix. The legacy Tauri record is
`bundle.iOS.bundleVersion` in `src-tauri/tauri.conf.json`; native releases use
`CURRENT_PROJECT_VERSION` in `native-ios/project.yml`.

Uploading requires the one-time App Store Connect API-key setup documented in
`docs/testflight-cli.md`. Building and exporting do not require that API key.
Do not fall back to Xcode UI or computer use when credentials are missing;
report the exact missing setup instead.
