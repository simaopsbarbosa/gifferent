#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

cd "$REPO_ROOT"
count=0
failed=0
while IFS= read -r -d '' file; do
  ((count += 1))
  print_command xcrun swift-format format "$file"
  if ! xcrun swift-format format "$file" | cmp -s - "$file"; then
    echo "format differs: $file" >&2
    failed=1
  fi
done < <(find Sources Tests -type f -name '*.swift' -print0)

echo "checked $count Swift files"
if (( count == 0 || failed != 0 )); then
  exit 1
fi
