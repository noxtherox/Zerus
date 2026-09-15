# Repository release instructions

## Release documentation review

- Before every release, review `README.md` against the release's current
  features, supported platforms, setup steps, commands, dependencies, and
  limitations. Add newly relevant information, update changed behavior, and
  remove obsolete claims before creating the version commit and tag.

## Microsoft Store release requirement

- A request to **make a new release** includes the Microsoft Store release,
  unless the user explicitly limits the release to another platform or channel.
  The request authorizes building, submitting, and publishing the matching Store
  version; do not ask for separate permission for these release steps.
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

## Web preview handoff

- After every new implementation or feature, start or refresh the web version and
  provide a working preview without waiting for the user to request one.
- When a web preview is requested or ready from this Mac mini, share the private Tailscale Serve app URL `https://mac-mini-m4-nox.ibex-oratrice.ts.net/app`. Always include `/app` so the preview opens the application; the root URL opens the website. Do not share a localhost URL.
- Before sharing it, confirm the `/app` route responds successfully through both the frontend development server and the Tailscale Serve proxy.
- Never enable Tailscale Funnel unless the user explicitly requests public exposure.

## Build target resolution

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
