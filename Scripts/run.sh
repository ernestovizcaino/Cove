#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Build the app on macOS with Xcode. 'swift test' runs the portable core on Linux." >&2
  exit 1
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Install/open Xcode and select its command-line tools in Xcode Settings → Locations." >&2
  exit 1
fi
mkdir -p "$ROOT/.build-macos"
xcodebuild -project "$ROOT/Cove.xcodeproj" -scheme Cove \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/.build-macos" build 2>&1 | tee "$ROOT/.build-macos/build.log"
open "$ROOT/.build-macos/Build/Products/Debug/Cove.app"
