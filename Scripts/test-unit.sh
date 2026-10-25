#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_project
run_dir="$(new_run_dir test-unit)"
# macOS rejects unsigned XCTest runner apps; ad-hoc signing needs no developer certificate.
test_signing_args=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
if [[ -n "${GIFFERENT_TEST_DEVELOPMENT_TEAM:-}" ]]; then
  test_signing_args=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="Apple Development" CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$GIFFERENT_TEST_DEVELOPMENT_TEAM")
fi

run_xcodebuild "$run_dir/test-unit.log" \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$ARTIFACTS_DIR/DerivedData" \
  -resultBundlePath "$run_dir/Result.xcresult" \
  -only-testing:gifferentTests \
  "${test_signing_args[@]}" test

echo "unit and integration evidence: $run_dir"
