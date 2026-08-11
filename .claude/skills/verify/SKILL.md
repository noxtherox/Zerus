---
name: verify
description: Build/launch/drive recipe for verifying Zerus changes in a real browser.
---

# Verifying Zerus

Vite + React notes app with two vault backends: `DesktopVault` (Tauri fs) and
`BrowserVault` (localStorage, auto-selected when not running under Tauri).
Running in a plain browser exercises the full app with the localStorage vault,
which is the practical way to verify UI features headlessly.

## Launch

```bash
npm run dev -- --port 5199 --strictPort   # plain browser build, BrowserVault
```

Tauri desktop build (`npm run desktop:dev`) needs a windowed session — verify
the shared code path in the browser and review the Tauri-only bits by hand
(capabilities in `src-tauri/capabilities/default.json`, `DesktopVault`).

## Drive headlessly

Playwright browsers are cached at `~/Library/Caches/ms-playwright/`
(e.g. `chromium_headless_shell-1228/...-mac-arm64/chrome-headless-shell`), but
the repo has no playwright dep — `npm i playwright-core` in a scratch dir and
launch with `executablePath` pointed at the cached binary.

Gotchas that worked:

- The app seeds demo notes on first load; click the first note-list button
  (`button:has(span.truncate)`) to open the editor (`.cm-content`).
- To simulate pasting an image, dispatch a synthetic
  `ClipboardEvent("paste", { clipboardData })` on `.cm-content` with a `File`
  added to a `DataTransfer` — CodeMirror's `domEventHandlers` receives it.
- Browser-vault storage keys: notes `zerus.browserVault.v1`, image assets
  `zerus.browserVault.assets.v1` (path → base64).
- Image preview widgets: `.cm-image-preview`, resize handle
  `.cm-image-resize-handle` (hover the preview first, then mouse
  down/move/up), missing-asset fallback `.cm-image-preview-missing`.
