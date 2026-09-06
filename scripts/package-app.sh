#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
version="${VERSION:-0.1.0}"
app="$PWD/dist/Token Viewer.app"
build_args=(--configuration "$configuration" --arch arm64 --disable-sandbox --cache-path "$PWD/.build/cache")
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
if [[ -d "$app" ]]; then rm -rf "$app"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/TokenViewer" "$app/Contents/MacOS/TokenViewer"
# L10n resolves the packaged bundle here; SwiftPM's accessor remains the development fallback.
ditto "$bin_dir/TokenViewer_TokenViewerCore.bundle" "$app/Contents/Resources/TokenViewer_TokenViewerCore.bundle"
swift scripts/make-icon.swift
iconutil --convert icns .build/AppIcon.iconset --output "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Token Viewer</string>
  <key>CFBundleDisplayName</key><string>Token Viewer</string>
  <key>CFBundleIdentifier</key><string>io.github.moguone.token-viewer</string>
  <key>CFBundleExecutable</key><string>TokenViewer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ja</string></array>
</dict></plist>
PLIST

identity="${CODE_SIGN_IDENTITY:--}"
codesign --force --deep --options runtime --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
archive="$PWD/dist/TokenViewer-$version-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
fi
shasum -a 256 "$archive" | sed "s|$PWD/dist/||" > "$archive.sha256"
printf 'App: %s\nArchive: %s\n' "$app" "$archive"
