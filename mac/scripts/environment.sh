#!/bin/bash
set -euo pipefail
WRITER_MAC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$WRITER_MAC_ROOT/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
WRITER_DERIVED_DATA="${WRITER_DERIVED_DATA:-$WRITER_MAC_ROOT/DerivedData}"
if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "Missing Xcode at $DEVELOPER_DIR; set DEVELOPER_DIR to an installed Xcode." >&2
  exit 1
fi
mkdir -p "$CLANG_MODULE_CACHE_PATH"
