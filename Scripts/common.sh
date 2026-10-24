#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="${GIFFERENT_ARTIFACTS_DIR:-$REPO_ROOT/.build/ci}"
PROJECT="$REPO_ROOT/gifferent.xcodeproj"
SCHEME="gifferent"

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
