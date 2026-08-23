# Repository release instructions

## Web preview handoff

- When a web preview is requested or ready from this Mac mini, share the private Tailscale Serve URL `https://mac-mini-m4-nox.ibex-oratrice.ts.net/` instead of a localhost URL.
- Before sharing it, confirm both the frontend development server and the Tailscale Serve proxy respond successfully.
- Never enable Tailscale Funnel unless the user explicitly requests public exposure.

## Build target resolution

- When the active workspace or repository directory is named
  `Zerus-desktop-work`, **new build** by itself means a macOS desktop DMG. Run
  `pnpm desktop:build` without asking which platform the user means.
- In any workspace that does not explicitly establish its target platform,
  **new build** by itself is ambiguous. Ask whether the user wants a macOS
  desktop DMG or an iOS App Store build before running a build command.
- Do not infer the target from recent conversation or the last platform that
  was built.
- Explicit requests such as **build the DMG**, **new desktop build**, or
  **new iOS build** do not require clarification.

## macOS desktop terminology

- **New desktop build**, **macOS build**, or **build the DMG** means run
  `pnpm desktop:build`. This creates and verifies the macOS desktop artifacts,
  including the DMG.

## iOS terminology

- **New iOS build** or **new App Store build** means run `pnpm ios:new-build`.
  This advances the canonical iOS build number, creates the signed Xcode archive,
  verifies it, and exports its IPA. The command computes the next number from
  the persistent configuration and latest completed archive; do not assume a
  build number from conversation history.
- **Push/upload the current build** means do not rebuild or increment anything.
  Run `pnpm testflight` to validate and upload the existing IPA.
- **New iOS build and push it** means run `pnpm ios:new-build`, then
  `pnpm testflight`.

Never pass Tauri's `--build-number` option for an absolute App Store build
number; Tauri treats it as a suffix. The canonical record is
`bundle.iOS.bundleVersion` in `src-tauri/tauri.conf.json`.

Uploading requires the one-time App Store Connect API-key setup documented in
`docs/testflight-cli.md`. Building and exporting do not require that API key.
Do not fall back to Xcode UI or computer use when credentials are missing;
report the exact missing setup instead.
