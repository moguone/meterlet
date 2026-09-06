#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
version="${VERSION:-0.2.0}"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { printf '%s\n' 'VERSION must be a dotted numeric version.' >&2; exit 1; }
output_dir="${OUTPUT_DIR:-$PWD/dist}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
app="$output_dir/Meterlet.app"
python3 scripts/check-package-target.py "$app"
public_key="$(cat updates/public-key.txt)"
build_args=(--configuration "$configuration" --arch arm64 --disable-sandbox --cache-path "$PWD/.build/cache")
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
if [[ -d "$app" ]]; then rm -rf "$app"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin_dir/Meterlet" "$app/Contents/MacOS/Meterlet"
ditto "$bin_dir/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/Third-Party Notices.md"
# L10n resolves the packaged bundle here; SwiftPM's accessor remains the development fallback.
ditto "$bin_dir/Meterlet_MeterletCore.bundle" "$app/Contents/Resources/Meterlet_MeterletCore.bundle"
swift scripts/make-icon.swift
iconutil --convert icns .build/AppIcon.iconset --output "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Meterlet</string>
  <key>CFBundleDisplayName</key><string>Meterlet</string>
  <key>CFBundleIdentifier</key><string>io.github.moguone.meterlet</string>
  <key>CFBundleExecutable</key><string>Meterlet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ja</string></array>
  <key>SUFeedURL</key><string>https://github.com/moguone/meterlet/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>$public_key</string>
  <key>SUEnableAutomaticChecks</key><false/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>SUAutomaticallyUpdate</key><false/>
  <key>SUAllowsAutomaticUpdates</key><false/>
  <key>SUEnableSystemProfiling</key><false/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SURequireSignedFeed</key><true/>
</dict></plist>
PLIST

identity="${CODE_SIGN_IDENTITY:--}"
if [[ -n "${NOTARY_PROFILE:-}" && "$identity" == "-" ]]; then
  printf '%s\n' 'Notarization requires CODE_SIGN_IDENTITY for a Developer ID Application certificate.' >&2
  exit 1
fi
python3 scripts/sign-framework.py "$app/Contents/Frameworks/Sparkle.framework" "$identity"
sign_args=(--force --options "$( [[ "$identity" == "-" ]] && printf 0 || printf runtime )" --sign "$identity")
if [[ "$identity" != "-" ]]; then sign_args+=(--timestamp); fi
codesign "${sign_args[@]}" "$app"
codesign --verify --deep --strict "$app"
archive="$output_dir/Meterlet-$version-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose "$app"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
fi
(cd "$output_dir" && shasum -a 256 "$(basename "$archive")") > "$archive.sha256"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  ./scripts/make-appcast.sh "$archive"
fi
printf 'App: %s\nArchive: %s\n' "$app" "$archive"
