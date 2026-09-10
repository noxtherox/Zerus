# Windows desktop development

Zerus uses the same React interface and Tauri/Rust backend on macOS and
Windows. Windows builds produce a per-user NSIS installer and do not require
Administrator access.

## Prerequisites

- Windows 10 or 11
- Node.js and pnpm
- Rust with the stable MSVC toolchain
- Visual Studio 2022 Build Tools with **Desktop development with C++**
- Microsoft Edge WebView2 Runtime

## Run locally

```powershell
pnpm install
pnpm windows:dev
```

## Build a local installer

```powershell
pnpm windows:build
```

The installer is written below
`src-tauri\target\release\bundle\nsis\`. The current Windows configuration
deliberately disables updater artifacts so a local build does not need the
release signing key. Code signing and Windows updater publication are separate
release tasks.

## Microsoft Store MSIX

Each configured tagged desktop release also builds an **unsigned x64 MSIX**
alongside the unsigned NSIS EXE. The EXE remains the direct-download installer.
The MSIX is an input to Microsoft Store certification: it cannot be installed
normally from GitHub while unsigned. Microsoft signs it during Store publishing;
this workflow does not submit or publish the app in Partner Center.

### One-time Store identity setup

Reserve Zerus in Microsoft Partner Center, then copy the exact values from
**Product management → Product identity** into these GitHub repository
**Actions variables** (they are public package metadata, not signing secrets):

| Repository variable | Partner Center field |
| --- | --- |
| `MS_STORE_IDENTITY_NAME` | Package/Identity/Name |
| `MS_STORE_PUBLISHER` | Package/Identity/Publisher (including `CN=`) |
| `MS_STORE_PUBLISHER_DISPLAY_NAME` | Package/Properties/PublisherDisplayName |

All three are required for release packaging; absent or partial identity values
fail the release instead of publishing a package under an invented identity.
No certificate, signing password, or Store API credential is needed to build.

### Build and validate

Install the Windows 10/11 SDK (including `MakeAppx.exe`) in addition to the
prerequisites above. On x64 Windows, set those three environment variables to
the Partner Center values and run:

```powershell
pnpm windows:msix:test
pnpm windows:build
pnpm windows:msix
```

The MSIX command rebuilds the app with in-app update checks disabled, stages the
native executable, DLLs, bundled CLI, and Store icons, then runs Windows SDK
manifest validation and checks the unpacked payload against the source files.
Output: `src-tauri/target/release/bundle/msix/Zerus_<version>_x64_store.msix`.
The existing EXE remains in `bundle/nsis/`. MSIX versions use `(app major + 1).minor.patch.0`: app `0.3.17` becomes
package `1.3.17.0`, and app `1.0.0` becomes package `2.0.0.0`. This keeps the
Store-required major component nonzero and preserves upgrade ordering. The
fourth component stays zero for the Store.

For packaging checks before reserving the Store identity:

```powershell
pnpm windows:msix --development
```

This explicitly permits a development identity and labels the artifact
`_development.msix`. The Windows pull-request/manual workflow uses this mode;
development packages must not be submitted to the Store.

### Certification and runtime checks

The MSIX targets Windows 10 version 2004 or newer and Windows 11, x64. It uses
the installed **Microsoft Edge WebView2 Runtime**; unlike the EXE installer,
the MSIX does not bootstrap WebView2. Ensure the runtime is installed on the
test machine. Runtime provisioning on a clean supported Windows installation
must be checked before Store submission.

After packaging, test a locally signed copy (using a trusted development
certificate) on Windows: launch, choose a vault, edit and save a note, export,
install/run the CLI, and uninstall. Packaging validation alone does not verify
these runtime operations. This initial manifest registers the Start menu app;
it does not yet register Windows file associations. The full-trust capability
is required for Zerus's native filesystem and CLI access and needs a capability
justification during Store submission. Store approval is not automatic.

Upload the `_store.msix` from the GitHub release to the matching Partner Center
product, complete the listing and certification requirements, then publish
there. Store updates are managed by Microsoft Store; the EXE continues to use
manual installer downloads.

References: [Microsoft's MSIX packaging guide](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-manual-conversion)
and [Tauri apps with MSIX](https://learn.microsoft.com/en-us/windows/apps/dev-tools/winapp-cli/guides/tauri).
