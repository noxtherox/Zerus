# Tauri Plugin mobile-vault

This package owns the Tauri iOS bridge, document pickers, vault access, and native
file previews. Shared Drive, cloud AI, ChatGPT, and speech implementations live in
`../../../../packages/apple/IOSServices`; the SwiftUI app uses the same package.

Keep Tauri-specific types in `Sources/MobileVaultPlugin.swift`. Changes to the
shared services belong in `packages/apple/`, without importing Tauri there.
Both apps retain their existing bundle identities, sandbox storage, and Keychain
entitlements. See the repository's `docs/ios-apps.md` for build and release
selection during SwiftUI evaluation.
