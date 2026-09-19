#!/bin/bash
# Installs one verified generator in this checkout; does not change global tools.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Project generation bootstrap requires macOS. Core tests also run on Linux.' >&2
  exit 1
fi
version="$(cat .xcodegen-version)"
checksum=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
mkdir -p .tools
if [[ -x .tools/xcodegen/bin/xcodegen ]]; then
  .tools/xcodegen/bin/xcodegen --version
  exit 0
fi
archive="$(mktemp -d)"
trap 'rm -rf "$archive"' EXIT
curl --fail --location --retry 3 \
  "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip" \
  --output "$archive/xcodegen.zip"
(cd "$archive" && echo "$checksum  xcodegen.zip" | shasum -a 256 --check)
unzip -q "$archive/xcodegen.zip" -d "$archive"
mv "$archive/xcodegen" .tools/xcodegen
.tools/xcodegen/bin/xcodegen --version
