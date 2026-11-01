#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
require_project
no_build=false
retry_bootstrap=false
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --no-build) no_build=true ;;
    --retry-bootstrap) retry_bootstrap=true ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
test_filters gifferentUITests "$@"

# a failed bootstrap is an environment failure, not a failed product assertion.
# do not repeatedly take over the desktop when that environment is unchanged.
mkdir -p "$ARTIFACTS_DIR"
bootstrap_key="$( { xcodebuild -version; sw_vers -buildVersion; id -u; sysctl -n kern.boottime; printf '%s\n' "${DEVELOPER_DIR:-}" "${GIFFERENT_TEST_DEVELOPMENT_TEAM:-ad-hoc}"; } | shasum -a 256 | cut -d ' ' -f 1)"
blocker="$ARTIFACTS_DIR/ui-bootstrap-$bootstrap_key.blocked"
if [[ -f "$blocker" && "$retry_bootstrap" == false ]]; then
  cat "$blocker" >&2
  echo "UI runner startup remains blocked; repair the session/signing policy, then use --retry-bootstrap once" >&2
  exit 1
fi
if ! launchctl print "gui/$(id -u)" >/dev/null 2>&1; then
  echo "UI acceptance requires a logged-in graphical macOS session; no UI tests ran" >&2
  exit 1
fi
if [[ "$no_build" == false ]]; then
  bash "$SCRIPT_DIR/build-tests.sh"
fi
require_test_build

run_ui() {
  local phase="$1"
  shift
  local run_dir
  run_dir="$(new_run_dir "$phase")"
  local result=0
  run_xcodebuild "$run_dir/$phase.log" \
    -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$TEST_DERIVED_DATA" \
    -resultBundlePath "$run_dir/Result.xcresult" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 120 \
    -maximum-test-execution-time-allowance 120 \
    "$@" "${test_signing_args[@]}" test-without-building || result=$?
  echo "UI evidence: $run_dir"
  if [[ "$result" != 0 ]]; then
    if ! grep -Fq "Test Case '-[gifferentUITests." "$run_dir/$phase.log"; then
      printf 'UI runner failed before any test case started; inspect %s\n' "$run_dir/$phase.log" > "$blocker"
    fi
    return "$result"
  fi
  python3 "$SCRIPT_DIR/check-test-result.py" "$run_dir/Result.xcresult"
  rm -f "$blocker"
}

# one launch test preflights automation before the full suite. its result bundle
# is part of full acceptance evidence; do not execute the same case twice.
smoke='gifferentUITests/MenuBarSmokeTests/testLaunchShowsIdleContentAndQuitAction'
run_ui test-ui-preflight "-only-testing:$smoke"
if [[ "$#" == 1 && "$1" == "$smoke" ]]; then
  exit 0
fi
run_ui test-ui "${test_filter_args[@]}" "-skip-testing:$smoke"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf 'UI acceptance passed (launch preflight plus selected journeys).\n' >> "$GITHUB_STEP_SUMMARY"
fi
