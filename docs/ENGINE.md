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
