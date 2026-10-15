#!/usr/bin/env bash
# Builds 6browser for Linux and packages it.  *** UNTESTED: written on Windows. ***
#
# Output: dist/6browser-linux-x64.tar.gz, plus dist/6browser-x86_64.AppImage
# when `appimagetool` is on PATH.
#
# Needs (Debian/Ubuntu): clang cmake ninja-build pkg-config libgtk-3-dev
# libnss3 libxss1 libgbm1 libasound2, and Flutter.
#
# NOTE: webview_cef needs extra edits to linux/runner (see
# third_party/webview_cef/README.md, "Linux"). They have NOT been applied in this
# repo yet, so this build is expected to need those changes first.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build linux --release
bundle=build/linux/x64/release/bundle
mkdir -p dist
tar -C "$bundle" -czf dist/6browser-linux-x64.tar.gz .
echo "Tarball: dist/6browser-linux-x64.tar.gz"

if command -v appimagetool >/dev/null 2>&1; then
  appdir=build/6browser.AppDir
  rm -rf "$appdir" && mkdir -p "$appdir/usr/bin"
  cp -r "$bundle"/. "$appdir/usr/bin/"
  cp assets/logo.png "$appdir/6browser.png"
  cat > "$appdir/6browser.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=6browser
Exec=browser6
Icon=6browser
Categories=Network;WebBrowser;
EOF
  printf '#!/bin/sh\nexec "$(dirname "$0")/usr/bin/browser6" "$@"\n' > "$appdir/AppRun"
  chmod +x "$appdir/AppRun"
  ARCH=x86_64 appimagetool "$appdir" dist/6browser-x86_64.AppImage
  echo "AppImage: dist/6browser-x86_64.AppImage"
else
  echo "appimagetool not found; skipped the AppImage."
fi
