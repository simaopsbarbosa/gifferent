#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="${GIFFERENT_GIFSKI_SOURCE_DIR:-$repo_root/.build/gifski-source}"
output="${GIFFERENT_GIFSKI_OUTPUT:-$repo_root/Vendor/Gifski-1.34.0/gifski}"
revision="1060eab4500a20f27e2fa3ab7e85473d0e921cbd"
toolchain="1.85.0"

if ! command -v cargo >/dev/null || ! command -v rustup >/dev/null; then
  echo "install Rust $toolchain with rustup before rebuilding Gifski" >&2
  exit 1
fi

if [[ ! -d "$source_dir/.git" ]]; then
  mkdir -p "$(dirname "$source_dir")"
  git clone --filter=blob:none --no-checkout --depth 1 \
    --branch 1.34.0 https://github.com/ImageOptim/gifski.git "$source_dir"
  git -C "$source_dir" checkout --detach "$revision"
fi

actual_revision="$(git -C "$source_dir" rev-parse HEAD)"
if [[ "$actual_revision" != "$revision" ]]; then
  echo "expected Gifski $revision, found $actual_revision at $source_dir" >&2
  exit 1
fi

for target in aarch64-apple-darwin x86_64-apple-darwin; do
  rustup target add --toolchain "$toolchain" "$target"
  cargo "+$toolchain" build \
    --manifest-path "$source_dir/Cargo.toml" \
    --locked --release --target "$target"
done

mkdir -p "$(dirname "$output")"
temporary_output="${output}.tmp"
lipo -create \
  "$source_dir/target/aarch64-apple-darwin/release/gifski" \
  "$source_dir/target/x86_64-apple-darwin/release/gifski" \
  -output "$temporary_output"
chmod 755 "$temporary_output"
if [[ "$(lipo -archs "$temporary_output")" != "x86_64 arm64" ]]; then
  echo "Gifski build did not produce the expected universal binary" >&2
  rm -f "$temporary_output"
  exit 1
fi
if [[ "$("$temporary_output" --version)" != "gifski 1.34.0" ]]; then
  echo "Gifski build returned an unexpected version" >&2
  rm -f "$temporary_output"
  exit 1
fi
mv "$temporary_output" "$output"
shasum -a 256 "$output"
echo "built Gifski 1.34.0 for arm64 and x86_64 at $output"
