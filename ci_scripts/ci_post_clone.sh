#!/bin/bash
# Optional Xcode Cloud hook. Configure build/test only until beta release is authorized.
set -euo pipefail
cd "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is required}"
./scripts/bootstrap.sh
./scripts/generate.sh
