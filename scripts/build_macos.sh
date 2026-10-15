#!/usr/bin/env bash
# Builds 6browser for macOS and packages a .dmg.  *** UNTESTED: written on Windows. ***
#
# Output: dist/6browser-macos.dmg
#
# NOTE: webview_cef needs Podfile / Runner changes on macOS (deployment target
# 12.0, the CEF helper post_install hook; see
# third_party/webview_cef/README.md, "macOS"). They have NOT been applied in this
# repo yet. The .app is also unsigned/unnotarized, so Gatekeeper will warn.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build macos --release
app=build/macos/Build/Products/Release/browser6.app
mkdir -p dist
rm -f dist/6browser-macos.dmg
hdiutil create -volname "6browser" -srcfolder "$app" -ov -format UDZO dist/6browser-macos.dmg
echo "DMG: dist/6browser-macos.dmg"
