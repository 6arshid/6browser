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
| **Chrome extensions / Chrome Web Store install** | **Not supported** (Web Store pages show a notice; "Add to Chrome" is disabled to avoid an engine crash) |

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
  ported; see [Building release packages](#building-release-packages).
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

## Building release packages

All outputs go to `dist/`. Each platform must be built on that platform:
Flutter cannot cross-compile desktop apps. The first build downloads CEF
(several hundred MB) and takes a while.

| Platform | Output | Status |
|---|---|---|
| Windows | `6browser-setup.exe`, `6browser-windows-x64.zip` | Verified (install, run, uninstall) |
| macOS | `6browser-macos.dmg` (unsigned) | Builds in CI; not run on a Mac yet |
| Linux | `6browser-linux-x64.tar.gz`, AppImage | Untested |

The Windows installer and zip are about 130 MB / 180 MB because they contain Chromium.

### Windows

Requirements: Flutter, CMake, Visual Studio 2022 (or Build Tools) with the
**Desktop development with C++** workload, and [Inno Setup 6](https://jrsoftware.org/isinfo.php)
for the installer (`winget install JRSoftware.InnoSetup`).

```powershell
flutter pub get
powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1
```

Produces `dist/6browser-windows-x64.zip` (portable) and, if Inno Setup is
found, `dist/6browser-setup.exe`.

### macOS

Requirements: a Mac (macOS 12+), Xcode, CocoaPods, Flutter, and
`brew install cmake ninja`.

```bash
flutter pub get
WEBVIEW_CEF_MACOS_ARCH=arm64 bash scripts/build_macos.sh   # or x86_64 / universal / host
```

Produces `dist/6browser-macos.dmg`. The app is not signed or notarized, so on
first launch right-click the app and choose **Open**.

**No Mac?** Use GitHub Actions: the workflow in
[.github/workflows/macos.yml](.github/workflows/macos.yml) builds an arm64
`.dmg`. Run it from the **Actions** tab ("macOS build" → **Run workflow**), or
push to the `ci/macos-build` branch, then download `6browser-macos-arm64` from
the run's **Artifacts**.

### Linux

Requirements (Debian/Ubuntu):

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libnss3 libxss1 libgbm1 libasound2
```

```bash
flutter pub get
bash scripts/build_linux.sh
```

Produces `dist/6browser-linux-x64.tar.gz`, plus `dist/6browser-x86_64.AppImage`
when `appimagetool` is on `PATH`. This path has not been tested yet and may
need the `linux/runner` changes described in `third_party/webview_cef/README.md`.

## ساخت خروجی (فارسی)

<div dir="rtl">

همه‌ی خروجی‌ها در پوشه‌ی <code>dist/</code> ساخته می‌شوند. هر پلتفرم را باید روی
همان سیستم‌عامل ساخت؛ Flutter برنامه‌ی دسکتاپ را برای سیستم‌عامل دیگر نمی‌سازد.
بیلد اول CEF را دانلود می‌کند (چند صد مگابایت) و چند دقیقه طول می‌کشد.

### ویندوز

پیش‌نیازها: Flutter، CMake، Visual Studio 2022 (یا Build Tools) با workload
<b>Desktop development with C++</b>، و برای ساخت نصب‌کننده
<a href="https://jrsoftware.org/isinfo.php">Inno Setup 6</a>
(<code>winget install JRSoftware.InnoSetup</code>).

</div>

```powershell
flutter pub get
powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1
```

<div dir="rtl">

خروجی: <code>dist/6browser-windows-x64.zip</code> (بدون نصب) و اگر Inno Setup
پیدا شود، <code>dist/6browser-setup.exe</code> (نصب‌کننده).

### macOS

پیش‌نیازها: یک مک (macOS 12 به بالا)، Xcode، CocoaPods، Flutter و
<code>brew install cmake ninja</code>.

</div>

```bash
flutter pub get
WEBVIEW_CEF_MACOS_ARCH=arm64 bash scripts/build_macos.sh   # یا x86_64 / universal / host
```

<div dir="rtl">

خروجی: <code>dist/6browser-macos.dmg</code>. برنامه امضا و notarize نشده؛ بار اول
روی برنامه راست‌کلیک کنید و <b>Open</b> را بزنید.

<b>مک ندارید؟</b> از GitHub Actions استفاده کنید: workflow موجود در
<code>.github/workflows/macos.yml</code> یک <code>.dmg</code> برای مک‌های
Apple Silicon می‌سازد. در تب <b>Actions</b> گزینه‌ی «macOS build» و بعد
<b>Run workflow</b> را بزنید (یا روی شاخه‌ی <code>ci/macos-build</code> push کنید)،
بعد فایل <code>6browser-macos-arm64</code> را از بخش <b>Artifacts</b> همان اجرا
دانلود کنید.

### لینوکس

پیش‌نیازها (Debian/Ubuntu):

</div>

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libnss3 libxss1 libgbm1 libasound2
```

```bash
flutter pub get
bash scripts/build_linux.sh
```

<div dir="rtl">

خروجی: <code>dist/6browser-linux-x64.tar.gz</code> و اگر <code>appimagetool</code>
نصب باشد، <code>dist/6browser-x86_64.AppImage</code>. این مسیر هنوز تست نشده و
ممکن است تغییرات <code>linux/runner</code> که در
<code>third_party/webview_cef/README.md</code> آمده لازم باشد.

</div>

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
