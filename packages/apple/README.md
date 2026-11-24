# Shared Apple code

These local Swift packages support the Apple applications. None depends
on React, Rust, Tauri, or the SwiftUI app target.
The native macOS migration target also links `ChatGPTCore` and compiles the shared
ChatGPT account manager and cloud request/response types directly from
`IOSServices`. Its account presentation uses AppKit, while the iOS presentation
continues to use UIKit. Drive and speech services remain iOS-specific. The Mac
caller supplies its own Keychain service and HTTP session; iOS defaults retain
their existing configuration. Mac account and API-key access use the shared
background Keychain worker; passive status reads are bounded and never create
a registration or request authorization UI. Explicit connection actions retain
normal Keychain authorization.

- `ChatGPTCore`: authorization, account protocol, Responses transport, model
  catalog, and private continuation storage. Its existing tests run on macOS with
  `pnpm ios:shared:test`.
- `ZerusMarkdown` (the `Markdown` package): shared safe image markup parsing,
  legacy width metadata and per-occurrence dimensions for native Mac and iOS
  image management and exports. It depends on Swift Markdown and SwiftSoup,
  without an AppKit or UIKit dependency.
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
