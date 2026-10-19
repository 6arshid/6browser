# 6browser engine decision

Status: accepted (phase 1). Revisit after the Chrome-runtime spike (see below).

## Decision

Use **CEF via the `webview_cef` Flutter plugin** (off-screen rendering into a
Flutter texture) for the first phase, hidden behind an `Engine` interface in
`lib/engine`. Before the extensions step, run a time-boxed spike on a custom
native plugin using **CEF's Chrome runtime in windowed mode**, the only route
with a realistic chance of full extension support.

## Options considered

| Option | Extensions | Effort | Notes |
|---|---|---|---|
| A. `webview_cef` (OSR) | Poor (Alloy runtime) | Low | CEF 149, GPU zero-copy on Windows/macOS, software path on Linux |
| B. Custom native CEF plugin, Chrome runtime, windowed | Best | High | Flutter overlays over a native child window are awkward |
| C. Embed real Chromium with `--load-extension` | Full | Medium, fragile | Window embedding differs per OS; not a true CEF integration |

## Extension limitations (known / unverified)

- CEF extension code lives in Chromium's `chrome/` layer, while CEF builds on
  the Content layer (CEF issue #1947). The Alloy runtime has minimal support.
- The Chrome runtime is opt-in and, per CEF docs, aimed at windowed mode.
  Whether it works with off-screen rendering is **unverified**; assume not.
- `webview_cef` documents no extension support. **With option A, expect
  Chrome extensions (MV3 service workers, toolbar popups, Web Store install)
  to NOT work.** Extension features will not be faked in the UI.
- Fallback if the spike fails: implement a subset of APIs through a native
  bridge, or fall back to option C. Document exactly which APIs are missing.

## Consequences

- All engine access goes through `lib/engine` so the backend can be swapped
  without touching features.
- Build needs CMake, a C++20 toolchain (Visual Studio C++ workload on Windows)
  and Flutter >= 3.27.

## Findings from the step 3 build (Windows, webview_cef 0.6.2, CEF 149)

- The Windows runner **must** call `initCEFProcesses(instance)` first in
  `wWinMain` and forward messages with `handleWndProcForCEF`. Without it CEF
  aborts at start-up (`CefTask_0_CToCpp called with invalid version -1`).
- The zero-copy GPU texture path failed here (`Could not create external
  texture`, blank page, with and without Impeller). `windows/CMakeLists.txt`
  sets `WEBVIEW_CEF_GPU_TEXTURE=OFF` to use the software pixel-buffer path.
  This costs performance; re-test the GPU path on other machines.
- `webview_cef` exposes no stop-loading call, so the Stop button is not
  implemented (`BrowserView.supportsStop == false`).
- The CEF log shows Chrome's own extension code
  (`chrome/browser/extensions/external_registry_loader_win.cc`) running, so
  this CEF build includes some Chrome-layer extension machinery. It is
  unverified whether extensions can actually be loaded; this goes in the
  step 6 spike.

## Extension spike results (step 4.5)

Question: can `webview_cef` (option A) run Chrome extensions?

**Answer: no, not with this architecture.** Based on CEF documentation and
issue tracker (not yet confirmed by a running experiment):

- `webview_cef` creates browsers with `SetAsWindowless` (off-screen
  rendering). CEF docs state windowless browsers always use the **Alloy**
  runtime style; Chrome style is only available for windowed browsers
  (`CefWindowInfo.runtime_style`). Chrome-style OSR is an open feature request
  (CEF issue #3293).
- CEF maintainers state extensions are only supported with Chrome-style windows
  that show part of the Chrome UI (e.g. the toolbar).
- Therefore MV3 extensions, the extension toolbar/popups and Web Store install
  cannot work in option A. Not faked in the UI.

## Security findings in webview_cef 0.6.2 (affects option A)

`common/webview_app.cc` unconditionally adds these Chromium switches:

| Switch | Effect |
|---|---|
| `disable-web-security` | Disables same-origin policy: any page can read other origins |
| `allow-running-insecure-content` | Mixed content allowed on HTTPS pages |
| `no-sandbox` | Renderer sandbox off |
| `disable-features=SameSiteByDefaultCookies,CookiesWithoutSameSiteMustBeSecure` | Weakens cookie protections |

This is acceptable for an embedded webview demo, **not for a general-purpose
browser**. Before 6browser is used on real sites we must patch or fork the
plugin (e.g. `dependency_overrides` with a vendored copy) to remove them.
Status: **fixed except `no-sandbox`.** webview_cef is vendored in
`third_party/webview_cef` (pubspec path dependency) and patched in
`common/webview_app.cc`: `disable-web-security`, `allow-running-insecure-content`,
the SameSite feature overrides and `ignore-certificate-errors` are removed.
Verified by inspecting the command lines of the running browser6.exe processes.
`no-sandbox` remains: CEF's sandbox needs the executable linked against
`cef_sandbox`, which the Flutter runner does not do. Renderer processes are
therefore unsandboxed; this must be revisited before any public release.
When upgrading webview_cef, re-apply the patch (search for `6browser patch`).

## Camera and microphone (Windows)

Alloy denies media requests by default. The vendored `WebviewHandler` now
registers a `CefPermissionHandler` and shows a native Yes/No prompt containing
the requesting origin and the requested devices. Yes grants precisely the
requested camera/microphone permissions; No or closing the prompt denies them.
Decisions are not saved, including in private tabs. Screen capture remains
unsupported because it needs a source picker. Other platforms retain CEF's
default behavior.

Manual verification on HTTPS or localhost: request audio only, video only, and
both with `navigator.mediaDevices.getUserMedia`; verify Yes returns the requested
tracks, No rejects with `NotAllowedError`, and a subsequent request prompts
again. Stop the returned tracks after testing. Repeat in a private tab. Windows
privacy settings must also allow desktop apps to access the devices.

## Downloads (step 5)

`webview_cef` 0.6.2 has no download handler, so downloads silently did
nothing. The vendored copy now has a second patch (`6browser patch` markers in
`common/webview_handler.{h,cc}`, `common/webview_plugin.cc`,
`lib/src/webview_manager.dart`): a `CefDownloadHandler` that saves into the
user's Downloads folder (Windows: `FOLDERID_Downloads`, never overwriting an
existing file) and reports progress to Dart (`WebviewManager.downloadEvents`).

Verified on Windows by loading a `Content-Disposition: attachment` URL: the file
was written and the database row reached `complete`.

Limitations:
- No pause/cancel/resume yet (needs a method-channel call into the native
  `CefDownloadItemCallback`).
- Linux/macOS fall back to CEF's own save dialog; untested.
- Incognito (step 7) must not persist downloads or history.

## Profile and incognito (step 7)

Findings and patches in the vendored plugin:

- **No persistent profile upstream.** `webview_cef` never set `cache_path`, so
  CEF ran fully in memory (cookies/localStorage lost on every start). On
  Windows `startCEF` now uses `%APPDATA%\6arshid\6browser\cef_profile`
  as `root_cache_path`/`cache_path`. Linux/macOS are NOT patched yet.
  Side effect: a second 6browser instance on the same profile exits (CEF
  singleton lock).
- **Incognito** = tab-level, not a separate OS window. Private tabs get a shared
  in-memory `CefRequestContext` (`createIncognito` method); it is dropped when
  the last private tab closes. Private tabs: no history, no list entry for
  downloads (the file itself is still saved), nothing written to the profile.
  Flutter has no stable multi-window support, hence tabs instead of a window.
- Start private from the command line: `browser6.exe --incognito [url]`.

Verified on Windows with the real app: a cookie with `Max-Age` set in a normal
tab appeared in `cef_profile\Default\Network\Cookies`; the same cookie set in a
`--incognito` run did not. (The private run's page load was not observed
directly.)

## Extension spike #2: CEF Chrome style, windowed (2026-10-15)

Setup: CEF 149's own `cefsimple` sample, built from the downloaded distribution
(outside the repo, `E:\6b_spike`), run with `--use-native` (windowed, Chrome
style, top-level native window - not yet a child of the Flutter window),
`--load-extension=<uBOL>,<Dark Reader>`, `--remote-debugging-port`.
Extensions: uBlock Origin Lite 2026.1012.1545 (MV3) and Dark Reader 4.9.133
(MV3), official GitHub release zips. Everything checked via the DevTools
protocol, no desktop input.

| Check | Result |
|---|---|
| `--load-extension` (unpacked MV3) | Works: both service workers running |
| uBOL `declarativeNetRequest` blocking | Works: ad script request blocked, normal request loaded |
| Dark Reader content scripts | Works: 8 `style.darkreader` tags, light page turned dark |
| `chrome.tabs.create` | Works (Dark Reader opened its help tab) |
| Extension popup pages | Render with `chrome.*` APIs when opened as a tab |
| `chrome://extensions` management page | Works (list, enable/disable, remove, details) |
| Chrome Web Store | `chrome.webstorePrivate` present, "Add to Chrome" button exists, but the store shows "Switch to Chrome". **Clicking install not tested** (needs a click in Chrome's native confirmation dialog) |
| Toolbar icons / badge / anchored popups | **Not available**: native mode has no Chrome toolbar, and CEF has no C++ API to list extensions, read badges or open an action popup for our own toolbar |
| External extensions from the Windows registry | Picked up (McAfee WebAdvisor appeared, disabled). Must be turned off for 6browser |

Conclusion: the extension *engine* works in CEF Chrome style. The open problems
are (1) the toolbar/popup UI, (2) Web Store install confirmation, (3) hosting
the windowed browser as a child of the Flutter window, and (4) ignoring other
programs' registry-installed extensions. These decide whether option B is
viable for 6browser.

## Crash fix: "Add to Chrome" on the Web Store (2026-10-15)

Reported by the user: clicking "Add to Chrome" closed 6browser. Reproduced via
CDP: the **browser process** crashed in `libcef.dll` (access violation, offset
`0x42520b5`) right after the click. The Alloy/OSR engine still exposes
`chrome.webstorePrivate` on the store, but calling its install path crashes.

Fix (`6browser patch` in `common/webview_handler.cc`, `OnLoadEnd`): after a Web
Store page loads, delete `chrome.webstorePrivate` from the page. Doing it in the
renderer's `OnContextCreated` did not work, because Chrome's bindings add the
property after that point. The store then cannot start an install. The Flutter UI
shows a notice on Web Store pages that extensions cannot be installed yet.

Verified: two runs, click "Add to Chrome" via CDP, app alive, no crash events.
Residual risk: a click during the page load, before `OnLoadEnd`, could still
reach the old path.

## Extension spike #3: Chrome toolbar and child-window hosting (2026-10-15)

Scripts kept in `spikes/` (`patch_cefsimple_child_host.py` adds a
`--child-host` mode to CEF's `cefsimple`; `cdp_check.mjs` is the CDP checker).
Both runs used the same uBlock Origin Lite + Dark Reader builds as spike #2.

| Mode | Extensions run | Extension UI | Notes |
|---|---|---|---|
| `cefclient --use-views --show-chrome-toolbar` | Yes | **Full Chrome UI**: tab strip, toolbar, extensions (puzzle) button | It is a whole Chrome window, not our UI |
| `cefsimple --child-host` (Chrome style, `SetAsChild` inside our own parent window) | **Yes**: uBOL blocked the ad request, Dark Reader darkened a light page (8 styles) | None (no toolbar) | This is the mode 6browser would use inside the Flutter window |

New findings:
- **Extension-opened tabs escape the host.** Dark Reader's `chrome.tabs.create`
  opened a separate, full Chrome window ("Help – Dark Reader - Chromium")
  outside our parent window. A real integration must intercept new tabs/popups
  (to verify: `CefLifeSpanHandler::OnBeforePopup` / Chrome-style new-tab hooks).
- **Child bounds:** the page appeared to cover the 64 px "Flutter toolbar" strip
  reserved via `SetAsChild(parent, CefRect(0, 64, ...))`. A later measurement
  was unreliable (window state changed). To verify; the host will have to
  position the browser HWND itself on every resize anyway.
- **External registry extensions** can be turned off with
  `--disable-features=ExternalExtensions` (McAfee did not appear in these runs).

What a 6browser on Chrome-style CEF would need to build itself, since CEF has no
API for it: an extensions toolbar (read installed extensions' manifests from the
profile for name/icon/popup), popups as small CEF child browsers
(`chrome-extension://<id>/<popup>`; active-tab context and badge text are not
available that way), and routing extension-created tabs into Flutter tabs.
Still untested: Web Store "Add to Chrome" in Chrome style (needs a manual click).

## Proprietary codecs: YouTube live (2026-10-19)

YouTube live streams showed "Your browser can't play this video". Live streams
are served only as H.264 video with AAC audio (there is no Opus track for
live), and the CEF builds from the Spotify CDN are built without proprietary
codecs, so MSE rejects them. Normal videos still play (VP9/AV1 + Opus).

There is no runtime switch: CEF must be built from source with
`proprietary_codecs=true ffmpeg_branding=Chrome`. (CEF issue #3559, using only
the OS decoders, works for H.264 on Windows but still has no AAC decoder.)

- Build setup lives in `E:\cef_build` (`build.bat` + `retry.sh`): CEF branch
  7827, commit `2f1bfd8` (same as the CDN version), Chromium source from the
  official tarball `chromium-149.0.7827.156.tar.xz` (git fetches from
  googlesource kept failing on this network), `--minimal-distrib-only`.
  Needs the Windows SDK "Debugging Tools" (installed) and VS Build Tools on E:.
- Finished distribution goes to `E:\6browser-cef\cef_codecs`. The plugin uses
  it when the `CEF_CUSTOM_DISTRIB` environment variable points to it (a
  directory, archive or URL); `scripts/build_windows.ps1` and
  `scripts/build_msix.ps1` set it automatically when that folder exists.
  Delete `third_party/webview_cef/third/cef/version.txt` to force a re-copy.
- Licensing: shipping a software H.264/AAC decoder in a distributed app can
  require patent licences (Via LA). This is the publisher's decision; the CDN
  build stays the default for anyone without the custom distribution.

## Keyboard shortcuts (2026-10-19)

Chrome's shortcuts are listed once in `lib/ui/browser_commands.dart` and run by
the shell; the main menu and the "Keyboard shortcuts" page read their labels
from there. On Windows the plugin hands keys to CEF from the window procedure
*and* Flutter sees them, so the page also receives e.g. Esc. The plugin was
extended (`stopLoad`, `reloadIgnoreCache`, `zoom` with the resulting level
reported per site, `find`/`stopFinding` with `CefFindHandler` results, and
`print`) for find in page, zoom, hard reload, stop and print. Not available on
the Android WebView backend (`supportsPageTools` is false).
