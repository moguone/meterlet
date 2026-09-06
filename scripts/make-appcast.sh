#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
archive="${1:?Usage: make-appcast.sh path/to/Meterlet-version-macOS-arm64.zip}"
archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"
filename="$(basename "$archive")"
version="${filename#Meterlet-}"
version="${version%-macOS-arm64.zip}"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { printf '%s\n' 'Unexpected archive filename.' >&2; exit 1; }
output_dir="$(dirname "$archive")"
staging="$(mktemp -d "$output_dir/.appcast.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
cp "$archive" "$staging/$filename"
cp "updates/$version.md" "$staging/${filename%.zip}.md"
release_url="https://github.com/moguone/meterlet/releases"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --account meterlet --maximum-deltas 0 --maximum-versions 1 --embed-release-notes \
  --download-url-prefix "$release_url/download/v$version/" \
  --link "$release_url/tag/v$version" --full-release-notes-url "$release_url/tag/v$version" \
  -o "$staging/appcast.xml" "$staging"
.build/artifacts/sparkle/Sparkle/bin/sign_update --account meterlet --verify "$staging/appcast.xml"
python3 scripts/verify-appcast.py "$staging/appcast.xml" "$version" --archive "$archive"
cp "$staging/appcast.xml" "$output_dir/appcast.xml"
printf 'Signed update feed: %s\n' "$output_dir/appcast.xml"
