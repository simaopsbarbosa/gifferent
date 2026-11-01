#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="${GIFFERENT_ARTIFACTS_DIR:-$REPO_ROOT/.build/ci}"
PROJECT="$REPO_ROOT/gifferent.xcodeproj"
SCHEME="gifferent"
TEST_DERIVED_DATA="$ARTIFACTS_DIR/TestDerivedData"

test_signing_args=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
if [[ -n "${GIFFERENT_TEST_DEVELOPMENT_TEAM:-}" ]]; then
  test_signing_args=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="Apple Development" CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$GIFFERENT_TEST_DEVELOPMENT_TEAM")
fi

test_fingerprint() {
  python3 "$SCRIPT_DIR/test-build-fingerprint.py"
}

require_test_build() {
  local stamp="$TEST_DERIVED_DATA/gifferent-build-fingerprint"
  if [[ ! -f "$stamp" ]] || [[ "$(cat "$stamp")" != "$(test_fingerprint)" ]]; then
    echo "test build missing or stale; run bash Scripts/build-tests.sh first" >&2
    exit 1
  fi
}

test_filters() {
  local target="$1"
  shift
  test_filter_args=()
  for selector in "$@"; do
    if [[ "$selector" != "$target/"* || "$selector" == -* ]]; then
      echo "expected a test selector such as $target/TestClass/testMethod: $selector" >&2
      exit 2
    fi
    test_filter_args+=("-only-testing:$selector")
  done
  if [[ ${#test_filter_args[@]} == 0 ]]; then
    test_filter_args=("-only-testing:$target")
  fi
}

require_project() {
  if [[ ! -d "$PROJECT" ]]; then
    echo "missing Xcode project: $PROJECT" >&2
    exit 1
  fi
}

new_run_dir() {
  mkdir -p "$ARTIFACTS_DIR"
  mktemp -d "$ARTIFACTS_DIR/$1-XXXXXX"
}

print_command() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
}

run_xcodebuild() {
  local log_file="$1"
  shift
  print_command xcodebuild "$@"
  xcodebuild "$@" 2>&1 | tee "$log_file"
}
