#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_project
run_dir="$(new_run_dir build-tests)"
mkdir -p "$TEST_DERIVED_DATA"
rm -f "$TEST_DERIVED_DATA/gifferent-build-fingerprint"
fingerprint="$(test_fingerprint)"

# keep manual app builds and test signing in separate derived data directories.
run_xcodebuild "$run_dir/build-tests.log" \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$TEST_DERIVED_DATA" \
  -resultBundlePath "$run_dir/Result.xcresult" \
  "${test_signing_args[@]}" build-for-testing

if [[ "$fingerprint" != "$(test_fingerprint)" ]]; then
  echo "build inputs changed during compilation; rebuild before testing" >&2
  exit 1
fi
printf '%s\n' "$fingerprint" > "$TEST_DERIVED_DATA/gifferent-build-fingerprint"
echo "test build evidence: $run_dir"
