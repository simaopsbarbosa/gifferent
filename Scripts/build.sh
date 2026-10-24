#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_project
run_dir="$(new_run_dir build)"

# CI builds are only checked, not launched for privacy-protected capture. local
# builds should keep Xcode signing enabled so a configured development identity
# can give Screen Recording permission a stable code identity.
if [[ "${CI:-}" == "true" ]]; then
  signing_args=(CODE_SIGNING_ALLOWED=NO)
else
  signing_args=(CODE_SIGNING_ALLOWED=YES)
fi

run_xcodebuild "$run_dir/build.log" \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$ARTIFACTS_DIR/DerivedData" \
  -resultBundlePath "$run_dir/Result.xcresult" \
  "${signing_args[@]}" build

echo "build evidence: $run_dir"
