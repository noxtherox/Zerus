# Shared Apple code

These local Swift packages support both iOS applications. Neither package depends
on React, Rust, Tauri, or the SwiftUI app target.

- `ChatGPTCore`: authorization, account protocol, Responses transport, model
  catalog, and private continuation storage. Its existing tests run on macOS with
  `pnpm ios:shared:test`.
- `IOSServices`: iOS Drive, cloud AI, ChatGPT account management, and speech
  capture. It depends on `ChatGPTCore` and Apple frameworks. Application-facing
  request/response types and services are public; credential and audio-session
  internals stay inside the package.

The SwiftUI project links these packages through `native-ios/project.yml`. The
Tauri mobile-vault plugin links `IOSServices` through its `ios/Package.swift` and
owns only the Tauri bridge and Files integration. Fix shared behavior here once;
do not maintain separate copies in the two apps.
The plugin's Rust build script watches the shared package manifests and sources
so Cargo rebuilds the Swift bridge after a shared-service edit.

Services continue to use the calling app's bundle configuration, sandbox,
preferences, and Keychain entitlements. Sharing source does not share accounts or
local app data between the two app identities.

The bounded Drive HTTP regression remains in the native app's hosted tests and
imports `ZerusIOSServices` with `@testable`. The helper remains internal rather
than becoming a public API solely for tests.
