#!/usr/bin/env bash
set -euo pipefail

expected_version="Xcode 26.2"
expected_build="Build version 17C52"
actual="$(xcodebuild -version)"
printf '%s\n' "$actual"

if [[ "$actual" != "$expected_version"$'\n'"$expected_build" ]]; then
  echo "expected $expected_version ($expected_build); select /Applications/Xcode_26.2.app" >&2
  exit 1
fi
