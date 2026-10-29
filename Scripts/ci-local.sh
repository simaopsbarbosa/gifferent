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
run python3 Scripts/check-docs.py
run python3 Scripts/check-brand-assets.py
run python3 -m unittest discover -s Benchmarks -p 'test_encoder_benchmark.py' -v
run bash Scripts/format-check.sh
run bash Scripts/lint.sh
CI=true run bash Scripts/build.sh
run bash Scripts/test-unit.sh
run bash Scripts/test-ui.sh
