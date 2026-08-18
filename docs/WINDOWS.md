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
