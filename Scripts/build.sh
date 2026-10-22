#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_project
run_dir="$(new_run_dir build)"

run_xcodebuild "$run_dir/build.log" \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$ARTIFACTS_DIR/DerivedData" \
  -resultBundlePath "$run_dir/Result.xcresult" \
  CODE_SIGNING_ALLOWED=NO build

echo "build evidence: $run_dir"
