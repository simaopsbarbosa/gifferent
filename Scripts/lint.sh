#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

cd "$REPO_ROOT"
print_command xcrun swift-format lint --strict --recursive Sources Tests
xcrun swift-format lint --strict --recursive Sources Tests
