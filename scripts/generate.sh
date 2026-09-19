#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
generator="${XCODEGEN_BIN:-.tools/xcodegen/bin/xcodegen}"
if [[ ! -x "$generator" ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    generator="$(command -v xcodegen)"
  else
    echo 'Run ./scripts/bootstrap.sh to install the pinned XcodeGen first.' >&2
    exit 1
  fi
fi
expected="$(cat .xcodegen-version)"
actual="$("$generator" --version)"
if [[ "$actual" != *" $expected" ]]; then
  echo "Expected XcodeGen $expected; found $actual. Use scripts/bootstrap.sh." >&2
  exit 1
fi
"$generator" generate --spec project.yml
