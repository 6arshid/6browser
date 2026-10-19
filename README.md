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
| Bookmarks with folders (star in the address bar, bookmarks bar, manager), drag and drop to reorder or file them; importing keeps the other browser's folders. History (search, delete, clear) | Works |
| Profiles: each with its own bookmarks, history, settings, passwords and site data, each in its own window | Desktop (tested on Windows); not on Android |
| Saved passwords: offer to save after signing in, fill in on sign-in pages, manager under Settings (Windows Hello before showing a password), import from Chrome/Edge/Brave | Windows (DPAPI) and Android (Keystore); not yet on macOS/Linux |
| Downloads manager (progress, open, show in folder) | Works on Windows; no pause/cancel |
| Settings: theme (system/light/dark), search engine, home page | Works |
| Persistent profile (cookies, localStorage, cache) | Works on Windows |
| Incognito tabs (`Ctrl+Shift+N`, or `6browser.exe --incognito [url]`) | Works on Windows, as tabs, not a separate window |
| Responsive layout (tab strip becomes a tab button below 720 px) | Works |
| Screen sharing (`getDisplayMedia`) | Windows: entire desktop after confirmation. Android: system screen/app picker, with Stop action in the notification. |
| **Chrome extensions / Chrome Web Store install** | **Not supported** (Web Store pages show a notice; "Add to Chrome" is disabled to avoid an engine crash) |

Shortcuts: `Ctrl+T` new tab, `Ctrl+W` close, `Ctrl+Shift+N` incognito tab,
`Ctrl+L` focus address bar, `Ctrl+Tab` / `Ctrl+Shift+Tab` switch tab, `F5`
reload, `F12` DevTools.

## Limitations

- **Screen sharing:** Windows uses CEF's full-desktop capture, with an explicit
  prompt for every request; there is no desktop window/tab picker. Android uses
  MediaProjection and a video-only canvas bridge (up to 1280 px, 10 fps); system
  audio is not captured. Android requires a current System WebView supporting
  document-start scripts and web messages. Capture stops on navigation, tab close,
  the site's stop control, or Android's Stop sharing action. Real Google Meet
  calls still need device validation; successful builds alone do not verify them.

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

For setup from a clean Mac, development, troubleshooting, and exporting the app,
see [macOS from scratch (English)](#macos-from-scratch-english) and
[the Persian guide](#macos-from-scratch-persian).

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

<a id="macos-from-scratch-english"></a>
## macOS from scratch (English)

The macOS runtime is still untested on a physical Mac. These instructions follow
the checked-in runner and packaging scripts; a successful build does not verify
browser features. Build on a Mac, not Windows or Linux. The project's deployment
target is macOS 12+, but your development Mac must also support your chosen
Xcode and Flutter versions.

### 1. Install the development tools

Install the full **Xcode** app from the Mac App Store, launch it once, and finish
its component installation. Command Line Tools alone are insufficient. Then run:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license
```

Read and accept the license when prompted. Install [Homebrew](https://brew.sh/)
using its official instructions, including the displayed shell/PATH setup.
In a new Terminal window, install the remaining tools:

```bash
brew install cmake ninja cocoapods
```

Install Flutter using the [official SDK installation guide](https://docs.flutter.dev/install/manual),
selecting macOS and the correct CPU (Apple Silicon or Intel). Extract the SDK
to `~/develop/flutter`, then add it to the default macOS zsh shell:

```bash
echo 'export PATH="$HOME/develop/flutter/bin:$PATH"' >> ~/.zprofile
source ~/.zprofile
flutter --version
dart --version
pod --version
flutter config --enable-macos-desktop
flutter doctor -v
flutter devices
```

This repo requires **Dart >=3.13.3 and <4.0.0** (`pubspec.yaml`); its macOS CI
pins **Flutter 3.47.3**. Use that Flutter version to match CI, or a stable SDK
meeting the Dart constraint. Resolve Xcode/macOS errors reported by
`flutter doctor`; Android/iOS tooling is unnecessary for a macOS-only build.
`flutter devices` should list `macos`. See also the
[official macOS setup guide](https://docs.flutter.dev/platform-integration/macos/setup).

### 2. Clone and run in development mode

```bash
mkdir -p ~/develop
cd ~/develop
git clone https://github.com/6arshid/6browser.git
cd 6browser
flutter pub get
export WEBVIEW_CEF_MACOS_ARCH=host
export CEF_WRAPPER_BUILD_TYPE=Debug
bash third_party/webview_cef/macos/scripts/download_cef.sh
(cd macos && pod install)
flutter run -d macos
```

`host` selects arm64 on Apple Silicon and x86_64 on Intel. Use a native Terminal
on Apple Silicon rather than running it through Rosetta. Prepare CEF explicitly:
CocoaPods can skip `prepare_command` for this local path dependency. The first
preparation downloads several hundred MB and compiles native code; allow time
and free disk space. The existing runner and Podfile already contain the CEF
integration; do not replace them with `flutter create .`.

Edit Dart code in `lib/` with VS Code (Flutter/Dart extensions) or your editor.
While `flutter run` is active, press `r` for hot reload, `R` for hot restart,
and `q` to quit. Native Swift/Objective-C/CEF changes need a full stop and rebuild.
For native debugging, open `macos/Runner.xcworkspace` after `pod install`.

```bash
flutter analyze
flutter test
# Only after changing the drift database schema:
dart run build_runner build --delete-conflicting-outputs
```

### 3. Export a release app and DMG

Stop the debug app first. From the repository root, in the same Terminal:

```bash
export WEBVIEW_CEF_MACOS_ARCH=host
export CEF_WRAPPER_BUILD_TYPE=Release
bash third_party/webview_cef/macos/scripts/download_cef.sh
(cd macos && pod install)
bash scripts/build_macos.sh
open build/macos/Build/Products/Release
open dist
```

Outputs are `build/macos/Build/Products/Release/browser6.app` and
`dist/6browser-macos.dmg`. The script prepares the Release CEF wrapper, runs
`flutter build macos --release`, and packages the app with `hdiutil`. The DMG is
overwritten on each run. To build just the `.app`, run
`flutter build macos --release` instead of the packaging script after preparation.

Architecture choices for `WEBVIEW_CEF_MACOS_ARCH`: `host` (this Mac), `arm64`
(Apple Silicon), `x86_64` (Intel), or `universal` (both; about 8 GB scratch space
for CEF preparation). To change architecture, set the variable **before both**
CEF preparation and `pod install`, then rebuild. A universal CEF preparation
alone is not proof that the final app contains both slices; verify before sharing:

```bash
lipo -archs build/macos/Build/Products/Release/browser6.app/Contents/MacOS/browser6
```

Mount the DMG and copy the app to Applications. The current packaging provides
ad-hoc signing only, without Developer ID signing or notarization. For a trusted
local build, try Finder **Open**; if macOS blocks it, review the message in
**System Settings > Privacy & Security** and use **Open Anyway** if available.
Public distribution requires a separate Developer ID signing/notarization process;
the script does not perform it. Test the exported app's navigation, tabs,
downloads, and persistence on a Mac before distributing it.

### 4. Common build problems

- **`flutter`, `brew`, or `pod` not found:** finish that tool's PATH setup,
  reopen Terminal, and check `which flutter`, `which brew`, and `which pod`.
- **Xcode not detected:** confirm `xcode-select -p` points inside the full Xcode
  app, complete its first-launch setup, and rerun `flutter doctor -v`.
- **Missing CEF framework or headers:** rerun the explicit download script above,
  then `pod install`; check network access to `cef-builds.spotifycdn.com`.
- **Linker/architecture errors or switching Debug/Release:** set both environment
  variables to the desired values, run `flutter clean`, `flutter pub get`, the
  CEF preparation script, and `pod install`, then rebuild. Debug and Release
  wrappers have different ABIs and must match the Flutter build configuration.
- **Returning to development after export:** repeat step 2's commands from
  `export WEBVIEW_CEF_MACOS_ARCH=host` onward so the wrapper is Debug again.

Without a Mac, use the existing [macOS GitHub Actions workflow](.github/workflows/macos.yml)
to export a DMG as described above; it does not provide an interactive development environment.

<a id="macos-from-scratch-persian"></a>
## راه‌اندازی macOS از صفر (فارسی)

این راهنما مطابق runner و اسکریپت‌های همین مخزن است؛ اجرای واقعی برنامه روی مک
هنوز تأیید نشده است. خروجی macOS باید روی مک ساخته شود. حداقل نسخهٔ هدف برنامه
macOS 12 است، اما مک توسعه باید نسخه‌های انتخابی Xcode و Flutter را هم پشتیبانی کند.

### ۱. نصب ابزارهای توسعه

نسخهٔ کامل **Xcode** را از Mac App Store نصب کنید، یک بار باز کنید و نصب اجزای آن
را تمام کنید. نصب Command Line Tools به‌تنهایی کافی نیست. در Terminal اجرا کنید:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license
```

متن مجوز را بخوانید و تأیید کنید. سپس [Homebrew](https://brew.sh/) را طبق راهنمای
سایت رسمی نصب کنید و دستورهای تنظیم PATH که در پایان نشان می‌دهد را اجرا کنید.
یک پنجرهٔ جدید Terminal باز کنید:

```bash
brew install cmake ninja cocoapods
```

از [راهنمای رسمی نصب Flutter](https://docs.flutter.dev/install/manual)، نسخهٔ macOS
متناسب با پردازندهٔ خود (Apple Silicon یا Intel) را دریافت و در مسیر
`~/develop/flutter` استخراج کنید. برای افزودن آن به PATH در zsh اجرا کنید:

```bash
echo 'export PATH="$HOME/develop/flutter/bin:$PATH"' >> ~/.zprofile
source ~/.zprofile
flutter --version
dart --version
pod --version
flutter config --enable-macos-desktop
flutter doctor -v
flutter devices
```

طبق `pubspec.yaml`، نسخهٔ Dart باید حداقل **3.13.3** و کمتر از **4.0.0** باشد.
workflow مک این مخزن از **Flutter 3.47.3** استفاده می‌کند؛ برای هماهنگی با CI همین
نسخه یا یک SDK پایدار سازگار با محدودیت Dart را نصب کنید. خطاهای بخش Xcode/macOS
در `flutter doctor` را رفع کنید. برای ساخت فقط macOS به ابزارهای Android/iOS نیاز
ندارید. خروجی `flutter devices` باید دستگاه `macos` را نشان دهد.
[راهنمای رسمی تنظیم macOS](https://docs.flutter.dev/platform-integration/macos/setup)
نیز مرجع نصب و بررسی ابزارهاست.

### ۲. دریافت پروژه و اجرای حالت توسعه

```bash
mkdir -p ~/develop
cd ~/develop
git clone https://github.com/6arshid/6browser.git
cd 6browser
flutter pub get
export WEBVIEW_CEF_MACOS_ARCH=host
export CEF_WRAPPER_BUILD_TYPE=Debug
bash third_party/webview_cef/macos/scripts/download_cef.sh
(cd macos && pod install)
flutter run -d macos
```

مقدار `host` معماری همین مک را انتخاب می‌کند: `arm64` برای Apple Silicon و
`x86_64` برای Intel. روی Apple Silicon از Terminal بومی و بدون Rosetta استفاده
کنید. اجرای مستقیم اسکریپت آماده‌سازی CEF لازم است، چون CocoaPods ممکن است مرحلهٔ
`prepare_command` را برای وابستگی محلی اجرا نکند. بار اول چند صد مگابایت دانلود
و کد بومی کامپایل می‌شود؛ زمان و فضای خالی کافی در نظر بگیرید. تنظیمات CEF در
runner و Podfile موجود است؛ آن‌ها را با `flutter create .` جایگزین نکنید.

کدهای `lib/` را در VS Code با افزونه‌های Flutter/Dart یا ویرایشگر دلخواه تغییر
دهید. در Terminal اجرای برنامه، کلید `r` برای hot reload، کلید `R` برای
hot restart و `q` برای خروج است. تغییرات بومی Swift/Objective-C/CEF به توقف کامل
و ساخت مجدد نیاز دارند. برای دیباگ بومی، پس از `pod install` فایل
`macos/Runner.xcworkspace` را در Xcode باز کنید.

```bash
flutter analyze
flutter test
# فقط پس از تغییر ساختار دیتابیس drift:
dart run build_runner build --delete-conflicting-outputs
```

### ۳. گرفتن خروجی Release و فایل DMG

ابتدا اجرای Debug را متوقف کنید. در ریشهٔ پروژه و همان Terminal اجرا کنید:

```bash
export WEBVIEW_CEF_MACOS_ARCH=host
export CEF_WRAPPER_BUILD_TYPE=Release
bash third_party/webview_cef/macos/scripts/download_cef.sh
(cd macos && pod install)
bash scripts/build_macos.sh
open build/macos/Build/Products/Release
open dist
```

خروجی برنامه در `build/macos/Build/Products/Release/browser6.app` و فایل قابل
انتقال در `dist/6browser-macos.dmg` است. اسکریپت، wrapper نسخهٔ Release را آماده
می‌کند، `flutter build macos --release` را اجرا می‌کند و با `hdiutil` فایل DMG
می‌سازد. DMG قبلی با هر اجرا جایگزین می‌شود. اگر فقط `.app` می‌خواهید، بعد از
آماده‌سازی به‌جای اسکریپت بسته‌بندی، `flutter build macos --release` را اجرا کنید.

برای `WEBVIEW_CEF_MACOS_ARCH` می‌توانید `host` (همین مک)، `arm64` (Apple Silicon)،
`x86_64` (Intel) یا `universal` (هر دو؛ حدود ۸ گیگابایت فضای موقت برای CEF) را
انتخاب کنید. هنگام تغییر معماری، متغیر را قبل از آماده‌سازی CEF و `pod install`
تنظیم و دوباره بیلد کنید. آماده شدن CEF به‌شکل universal به‌تنهایی تضمین نمی‌کند
که خروجی نهایی هر دو معماری را دارد؛ قبل از انتشار بررسی کنید:

```bash
lipo -archs build/macos/Build/Products/Release/browser6.app/Contents/MacOS/browser6
```

فایل DMG را باز و برنامه را به Applications کپی کنید. بسته‌بندی فعلی فقط امضای
ad-hoc دارد و Developer ID و notarization انجام نمی‌دهد. برای بیلد محلی مورد
اعتماد، در Finder گزینهٔ **Open** را امتحان کنید؛ اگر macOS مانع اجرا شد، پیام
بخش **System Settings > Privacy & Security** را بررسی کنید و در صورت وجود از
**Open Anyway** استفاده کنید. انتشار عمومی به فرایند جداگانهٔ امضا و notarization
نیاز دارد. قبل از توزیع، جابه‌جایی صفحات، تب‌ها، دانلود و ماندگاری اطلاعات را روی
مک آزمایش کنید.

### ۴. رفع خطاهای رایج

- اگر `flutter`، `brew` یا `pod` پیدا نشد، تنظیم PATH همان ابزار را کامل کنید،
  Terminal را دوباره باز کنید و `which flutter`، `which brew` و `which pod` را بزنید.
- اگر Xcode شناسایی نشد، با `xcode-select -p` مسیر نسخهٔ کامل Xcode را بررسی کنید،
  نصب اولیهٔ اجزا را تمام کنید و دوباره `flutter doctor -v` را اجرا کنید.
- اگر framework یا headerهای CEF پیدا نشد، اسکریپت دانلود و سپس `pod install` را
  تکرار کنید؛ دسترسی اینترنت به `cef-builds.spotifycdn.com` را هم بررسی کنید.
- برای خطای لینک، معماری یا تعویض Debug/Release، هر دو متغیر محیطی را تنظیم کنید؛
  سپس به‌ترتیب `flutter clean`، `flutter pub get`، اسکریپت آماده‌سازی CEF و
  `pod install` را اجرا و دوباره بیلد کنید. ABI مربوط به wrapper حالت Debug و
  Release متفاوت است و باید با نوع بیلد Flutter یکسان باشد.
- برای برگشت به توسعه بعد از خروجی گرفتن، دستورهای مرحلهٔ ۲ از
  `export WEBVIEW_CEF_MACOS_ARCH=host` به بعد را تکرار کنید تا wrapper دوباره Debug شود.

بدون مک می‌توانید از [workflow موجود GitHub Actions](.github/workflows/macos.yml)
برای دریافت DMG استفاده کنید؛ این روش محیط توسعهٔ تعاملی در اختیار شما نمی‌گذارد.

## Where data lives (Windows)

- App database (bookmarks, history, settings, downloads):
  `%APPDATA%\6arshid\6browser\6browser.sqlite`
- Browser profile (cookies, cache, localStorage):
  `%APPDATA%\6arshid\6browser\cef_profile`

These are the Default profile's. Other profiles keep the same files in
`%APPDATA%\6arshid\6browser\profiles\<id>\`; the list is `profiles.json`.
Each profile runs in one window (one process): launching 6browser again
for an open profile (`6browser.exe --profile=<id> [url]`) hands the URL to
that window.

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
