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
Status: NOT yet fixed.
