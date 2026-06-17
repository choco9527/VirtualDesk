#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_TRIPLE="$(rustc -Vv | awk '/host:/ { print $2 }')"

echo "Building VirtualDesk Swift agent..."
swift build --package-path "$ROOT_DIR" -c release

mkdir -p "$ROOT_DIR/src-tauri/binaries"
cp "$ROOT_DIR/.build/release/VirtualDesk" \
  "$ROOT_DIR/src-tauri/binaries/virtualdesk-agent-$TARGET_TRIPLE"

echo "Prepared src-tauri/binaries/virtualdesk-agent-$TARGET_TRIPLE"
