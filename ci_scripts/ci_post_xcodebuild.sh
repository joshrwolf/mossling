#!/bin/sh
set -eu
scripts_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec /usr/bin/env swift "$scripts_dir/helpers/XcodeCloud.swift" post-xcodebuild "$scripts_dir"
