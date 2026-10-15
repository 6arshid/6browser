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
  Windows `startCEF` now uses `%APPDATA%\team.whitestudio\browser6\cef_profile`
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
