# 6browser

A desktop web browser with a Flutter UI on top of the Chromium engine (CEF).

> **Status: Windows works; Linux and macOS are untested. Chrome extensions are
> NOT supported.** See [Limitations](#limitations) before relying on it.

## Features

| Feature | Status |
|---|---|
| Multi-tab: new, close, duplicate, pin, reorder (drag), middle-click close | Works |
| Address bar: search or URL, HTTPS lock, history autocomplete | Works |
| Back / forward / reload / home, DevTools (F12) | Works |
| Stop-loading button | Not available (engine has no API) |
| Bookmarks (star in the address bar), history (search, delete, clear) | Works |
| Downloads manager (progress, open, show in folder) | Works on Windows; no pause/cancel |
| Settings: theme (system/light/dark), search engine, home page | Works |
| Persistent profile (cookies, localStorage, cache) | Works on Windows |
| Incognito tabs (`Ctrl+Shift+N`, or `6browser.exe --incognito [url]`) | Works on Windows, as tabs, not a separate window |
| Responsive layout (tab strip becomes a tab button below 720 px) | Works |
| **Chrome extensions / Chrome Web Store install** | **Not supported** |

Shortcuts: `Ctrl+T` new tab, `Ctrl+W` close, `Ctrl+Shift+N` incognito tab,
`Ctrl+L` focus address bar, `Ctrl+Tab` / `Ctrl+Shift+Tab` switch tab, `F5`
reload, `F12` DevTools.

## Limitations

- **No extensions.** The engine layer (`webview_cef`) renders off-screen, and
  CEF only supports Chrome extensions in windowed Chrome-style browsers. Getting
  real extension support needs a different engine integration (a custom native
  CEF plugin or embedding Chromium). Details and options:
  [docs/ENGINE.md](docs/ENGINE.md).
- **Renderer sandbox is off** (`no-sandbox`); the Flutter runner is not linked
  against CEF's sandbox library. Other unsafe switches that upstream
  `webview_cef` enabled (`disable-web-security`, etc.) were removed in the
  vendored copy. Do not treat this as a hardened browser.
- **Incognito is tab-level.** Private tabs share one in-memory session, leave no
  history, and are not listed in downloads (the downloaded file is still saved).
  Flutter has no stable multi-window API, so there is no separate private window.
- **Windows only so far.** The profile directory, download folder and the build
  and installer scripts are verified on Windows 11 only. Linux/macOS need the
  `webview_cef` runner changes (see its README) and the profile/download patches
  ported; `scripts/build_linux.sh` and `scripts/build_macos.sh` are untested.
- The GPU texture path of `webview_cef` failed on the dev machine, so it is
  disabled (`WEBVIEW_CEF_GPU_TEXTURE=OFF`); rendering is software-based.
- UI strings are English only.

## Build and run (Windows)

Requirements: Flutter (stable, >= 3.27), CMake, and Visual Studio 2022 (or
Build Tools) with the **Desktop development with C++** workload.

```powershell
flutter pub get
flutter run -d windows        # first build downloads CEF (~870 MB) and takes minutes
```

Checks:

```powershell
flutter analyze
flutter test
```

If you change `lib/data/database.dart`, regenerate the drift code:

```powershell
dart run build_runner build --delete-conflicting-outputs
```

## Packaging

| Platform | Command | Output | Status |
|---|---|---|---|
| Windows | `powershell -File scripts/build_windows.ps1` | `dist/6browser-windows-x64.zip`, `dist/6browser-setup.exe` (needs [Inno Setup 6](https://jrsoftware.org/isinfo.php)) | Verified (install, run, uninstall) |
| Linux | `scripts/build_linux.sh` | `.tar.gz`, AppImage (needs `appimagetool`) | Untested |
| macOS | `scripts/build_macos.sh` | `.dmg` (unsigned) | Untested |

The installer and zip are about 130 MB / 177 MB because they contain Chromium.

## Where data lives (Windows)

- App database (bookmarks, history, settings, downloads):
  `%APPDATA%\team.whitestudio\browser6\6browser.sqlite`
- Browser profile (cookies, cache, localStorage):
  `%APPDATA%\team.whitestudio\browser6\cef_profile`

Only one 6browser instance can use the profile at a time.

## Project layout

```
lib/
  main.dart                 app entry, theme, launch options
  data/                     drift database + providers
  engine/                   BrowserEngine / BrowserView interface + CEF backend
  features/
    tabs/                     tab state, controller (Riverpod), URL input
    bookmarks/ history/ downloads/ settings/
  ui/                       shell, tab strip, toolbar (responsive)
third_party/webview_cef/    vendored + patched plugin (search "6browser patch")
windows/                    runner (CEF init hooks), CMake
installer/                  Inno Setup script
scripts/                    build and packaging scripts, icon generator
docs/ENGINE.md              engine decision, findings, patches, limitations
test/                       unit and widget tests (fake engine, in-memory DB)
```

All engine access goes through `lib/engine`, so the backend can be replaced
without touching the features. UI tests use a fake engine and an in-memory
database; the real engine is only exercised by running the app.

## Vendored plugin

`third_party/webview_cef` is `webview_cef` 0.6.2 with patches: removal of
insecure Chromium switches, a download handler, a persistent profile (Windows),
and incognito browsers. Each change is marked `6browser patch`; re-apply them
when upgrading the plugin. CEF binaries are downloaded at build time and are
git-ignored.
