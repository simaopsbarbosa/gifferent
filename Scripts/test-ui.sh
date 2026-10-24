#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_project
run_dir="$(new_run_dir test-ui)"

run_xcodebuild "$run_dir/test-ui.log" \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$ARTIFACTS_DIR/DerivedData" \
  -resultBundlePath "$run_dir/Result.xcresult" \
  -parallel-testing-enabled NO \
  -only-testing:gifferentUITests \
  CODE_SIGNING_ALLOWED=NO test

echo "deterministic UI evidence: $run_dir"
