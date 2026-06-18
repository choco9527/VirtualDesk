#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BINARY_DIR="$ROOT_DIR/src-tauri/binaries"

fail() {
  echo "VirtualDesk agent build failed: $1" >&2
  exit 1
}

warn() {
  echo "VirtualDesk agent build warning: $1" >&2
}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || fail "missing required command: $command_name"
}

resolve_target_triple() {
  if command -v rustc >/dev/null 2>&1; then
    rustc -Vv | awk '/host:/ { print $2 }'
    return
  fi

  local architecture
  architecture="$(uname -m)"
  case "$architecture" in
    arm64)
      echo "aarch64-apple-darwin"
      ;;
    x86_64)
      echo "x86_64-apple-darwin"
      ;;
    *)
      fail "unsupported macOS architecture: $architecture"
      ;;
  esac
}

validate_macos_toolchain() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "this build script only supports macOS"

  require_command swift
  if command -v xcrun >/dev/null 2>&1; then
    xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 || \
      warn "xcrun cannot resolve the macOS SDK path; swift build will report the actionable error if this is fatal."
    xcrun --sdk macosx --show-sdk-platform-path >/dev/null 2>&1 || \
      warn "xcrun cannot resolve macOS PlatformPath; continuing because SwiftPM can still build without full Xcode."
  else
    warn "xcrun is unavailable; continuing with SwiftPM only."
  fi
}

TARGET_TRIPLE="$(resolve_target_triple)"

echo "Building VirtualDesk Swift agent..."
validate_macos_toolchain
swift build --package-path "$ROOT_DIR" -c release

mkdir -p "$BINARY_DIR"
cp "$ROOT_DIR/.build/release/VirtualDesk" \
  "$BINARY_DIR/virtualdesk-agent-$TARGET_TRIPLE"

echo "Prepared src-tauri/binaries/virtualdesk-agent-$TARGET_TRIPLE"
