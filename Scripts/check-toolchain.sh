#!/usr/bin/env bash
set -euo pipefail

expected_version="Xcode 27.1"
expected_build="Build version 27A9275"
actual="$(xcodebuild -version)"
printf '%s\n' "$actual"

if [[ "$actual" != "$expected_version"$'\n'"$expected_build" ]]; then
  echo "expected $expected_version ($expected_build); select /Applications/Xcode_27.1.app" >&2
  exit 1
fi
