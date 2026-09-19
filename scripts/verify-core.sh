#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift --version
swift test --package-path Packages/MosslingCore --parallel
