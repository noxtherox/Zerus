# Repository release instructions

## iOS terminology

- **New build** means create the next App Store build. Run `pnpm ios:new-build`.
  This advances the canonical iOS build number, creates the signed Xcode
  archive, verifies it, and exports its IPA. The command computes the next
  number from the persistent configuration and latest completed archive; do
  not assume a build number from conversation history.
- **Push/upload the current build** means do not rebuild or increment anything.
  Run `pnpm testflight` to validate and upload the existing IPA.
- **New build and push it** means run `pnpm ios:new-build`, then
  `pnpm testflight`.

Never pass Tauri's `--build-number` option for an absolute App Store build
number; Tauri treats it as a suffix. The canonical record is
`bundle.iOS.bundleVersion` in `src-tauri/tauri.conf.json`.

Uploading requires the one-time App Store Connect API-key setup documented in
`docs/testflight-cli.md`. Building and exporting do not require that API key.
Do not fall back to Xcode UI or computer use when credentials are missing;
report the exact missing setup instead.
