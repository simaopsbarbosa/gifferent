#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_project
run_dir="$(new_run_dir test-unit)"

run_xcodebuild "$run_dir/test-unit.log" \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$ARTIFACTS_DIR/DerivedData" \
  -resultBundlePath "$run_dir/Result.xcresult" \
  -only-testing:gifferentTests \
  CODE_SIGNING_ALLOWED=NO test

echo "unit and integration evidence: $run_dir"
