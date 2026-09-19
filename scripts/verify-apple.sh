#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Apple SDK compilation requires macOS and Xcode 26 or newer.' >&2
  exit 1
fi
xcodebuild -version
./scripts/generate.sh
mkdir -p .build-artifacts
xcodebuild -project Mossling.xcodeproj -scheme Mossling \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build-artifacts/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Mossling.xcodeproj -scheme MosslingWatch \
  -configuration Debug -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath .build-artifacts/WatchDerivedData \
  CODE_SIGNING_ALLOWED=NO build
# Domain tests also run against Apple's Foundation implementation.
./scripts/verify-core.sh
