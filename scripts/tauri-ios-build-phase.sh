#!/bin/sh
set -eu

if [ "${CONFIGURATION:-debug}" = "release" ] || [ "${CONFIGURATION:-debug}" = "Release" ]; then
  script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
  project_dir="$(dirname "$script_dir")"
  tauri_dir="$project_dir/src-tauri"

  TAURI_CONFIG='{}' \
  TAURI_ENV_PLATFORM=ios \
  TAURI_ENV_ARCH=arm64 \
  TAURI_ENV_FAMILY=unix \
  TAURI_ENV_TARGET_TRIPLE=aarch64-apple-ios \
    cargo build \
      --package app \
      --manifest-path "$tauri_dir/Cargo.toml" \
      --target aarch64-apple-ios \
      --features tauri/custom-protocol \
      --lib \
      --release

  /bin/mkdir -p "$tauri_dir/gen/apple/Externals/arm64/release"
  /bin/cp "$tauri_dir/target/aarch64-apple-ios/release/libapp_lib.a" \
    "$tauri_dir/gen/apple/Externals/arm64/release/libapp.a"
  exit 0
fi

port_is_live() {
  [ -n "${1:-}" ] && /usr/bin/nc -z -w 1 127.0.0.1 "$1" >/dev/null 2>&1
}

find_coordinator_port() {
  for coordinator_pid in $(/usr/bin/pgrep -f '/@tauri-apps/cli/tauri.js ios dev' | /usr/bin/sort -rn); do
    /usr/sbin/lsof -a -p "$coordinator_pid" -nP -iTCP -sTCP:LISTEN -Fn 2>/dev/null \
      | /usr/bin/sed -n 's/^n127\.0\.0\.1:\([0-9][0-9]*\)$/\1/p' \
      | /usr/bin/head -n 1
  done
}

if ! port_is_live "${TAURI_CLI_PORT:-}"; then
  TAURI_CLI_PORT="$(find_coordinator_port | /usr/bin/head -n 1)"
  export TAURI_CLI_PORT
fi

if ! port_is_live "${TAURI_CLI_PORT:-}"; then
  echo "error: No live Tauri iOS development coordinator was found. Run 'pnpm tauri ios dev --open' and keep that terminal open." >&2
  exit 1
fi

exec pnpm tauri ios xcode-script -v \
  --platform "${PLATFORM_DISPLAY_NAME:?}" \
  --sdk-root "${SDKROOT:?}" \
  --framework-search-paths "${FRAMEWORK_SEARCH_PATHS:?}" \
  --header-search-paths "${HEADER_SEARCH_PATHS:?}" \
  --gcc-preprocessor-definitions "${GCC_PREPROCESSOR_DEFINITIONS:-}" \
  --configuration "${CONFIGURATION:?}" \
  ${FORCE_COLOR:-} \
  ${ARCHS:?}
