#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_project
no_build=false
if [[ "${1:-}" == "--no-build" ]]; then
  no_build=true
  shift
fi
test_filters gifferentTests "$@"
if [[ "$no_build" == false ]]; then
  bash "$SCRIPT_DIR/build-tests.sh"
fi
require_test_build
run_dir="$(new_run_dir test-unit)"

run_xcodebuild "$run_dir/test-unit.log" \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$TEST_DERIVED_DATA" \
  -resultBundlePath "$run_dir/Result.xcresult" \
  "${test_filter_args[@]}" \
  "${test_signing_args[@]}" test-without-building
python3 "$SCRIPT_DIR/check-test-result.py" "$run_dir/Result.xcresult"

echo "unit and integration evidence: $run_dir"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf 'unit/integration tests passed; UI acceptance is a separate required step.\n' >> "$GITHUB_STEP_SUMMARY"
fi
