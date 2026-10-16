#!/usr/bin/env bash
# Builds 6browser for macOS and packages a .dmg.
#
# Output: dist/6browser-macos.dmg
#
# Requirements: Flutter, Xcode, CocoaPods, cmake (+ ninja). The first build
# downloads CEF and compiles libcef_dll_wrapper (see
# third_party/webview_cef/README.md, "macOS"). Set CEF_WRAPPER_BUILD_TYPE=Release
# for a release build and WEBVIEW_CEF_MACOS_ARCH (host|arm64|x86_64|universal).
# The .app is ad-hoc signed only (not notarized), so Gatekeeper will warn.
set -euo pipefail
cd "$(dirname "$0")/.."
export CEF_WRAPPER_BUILD_TYPE="${CEF_WRAPPER_BUILD_TYPE:-Release}"

# CocoaPods may skip prepare_command for :path pods, so prepare CEF explicitly.
bash third_party/webview_cef/macos/scripts/download_cef.sh
flutter build macos --release
app=$(ls -d build/macos/Build/Products/Release/*.app | head -1)
mkdir -p dist
rm -f dist/6browser-macos.dmg
hdiutil create -volname "6browser" -srcfolder "$app" -ov -format UDZO dist/6browser-macos.dmg
echo "DMG: dist/6browser-macos.dmg"
