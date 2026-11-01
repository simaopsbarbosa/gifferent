#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}

if [[ "${GIFFERENT_SKIP_TOOLCHAIN_CHECK:-}" == "1" ]]; then
  echo "warning: skipping the pinned Xcode check; results may differ from GitHub Actions"
else
  run bash Scripts/check-toolchain.sh
fi
run bash Scripts/quality.sh
run bash Scripts/build-tests.sh
run bash Scripts/test-unit.sh --no-build
run bash Scripts/test-ui.sh --no-build
