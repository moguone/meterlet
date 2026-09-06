#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/update-tests
framework_dir="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
# Build Sparkle's official command-line driver for isolated integration checks.
python3 - <<'PYTHON'
from pathlib import Path
import plistlib
with Path('.build/checkouts/Sparkle/sparkle-cli/Info.plist').open('rb') as file:
    info = plistlib.load(file)
info.update(CFBundleExecutable='sparkle-cli', CFBundleName='Meterlet Update Test Driver',
            CFBundleIdentifier='io.github.moguone.meterlet.update-test-driver',
            CFBundleVersion='1', CFBundleShortVersionString='1.0', LSMinimumSystemVersion='14.0')
with Path('.build/update-tests/Info.plist').open('wb') as file:
    plistlib.dump(info, file)
PYTHON
clang -fobjc-arc -fmodules -arch arm64 -mmacosx-version-min=14.0 \
  '-DSPU_OBJC_DIRECT=__attribute__((objc_direct))' \
  '-DSPU_OBJC_DIRECT_MEMBERS=__attribute__((objc_direct_members))' \
  -F "$framework_dir" -framework Cocoa -framework Sparkle -Wl,-rpath,"$framework_dir" \
  .build/checkouts/Sparkle/sparkle-cli/main.m \
  .build/checkouts/Sparkle/sparkle-cli/SPUCommandLineDriver.m \
  .build/checkouts/Sparkle/sparkle-cli/SPUCommandLineUserDriver.m \
  -Wl,-sectcreate,__TEXT,__info_plist,"$PWD/.build/update-tests/Info.plist" \
  -o .build/update-tests/sparkle-cli
python3 scripts/test-update-install.py "$@"
