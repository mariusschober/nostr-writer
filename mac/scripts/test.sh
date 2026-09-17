#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/environment.sh"
# Xcode injects additional test-manager entitlements while UI testing. Never
# overwrite the ordinary built app with that test-instrumented product.
WRITER_DERIVED_DATA="${WRITER_TEST_DERIVED_DATA:-$WRITER_MAC_ROOT/.build/NativeTestDerivedData}"
"$DEVELOPER_DIR/usr/bin/xcodebuild" -project "$WRITER_MAC_ROOT/NostrWriter.xcodeproj" \
  -scheme NostrWriter -derivedDataPath "$WRITER_DERIVED_DATA" -resolvePackageDependencies
python3 "$WRITER_MAC_ROOT/scripts/verify_build_plugin.py" "$WRITER_DERIVED_DATA"
for package in "$WRITER_MAC_ROOT"/Packages/*; do
  [[ -f "$package/Package.swift" ]] || continue
  if [[ -d "$package/Tests" ]]; then
    "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" test \
      --package-path "$package" --scratch-path "$WRITER_MAC_ROOT/.build/$(basename "$package")"
  else
    "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" build \
      --package-path "$package" --scratch-path "$WRITER_MAC_ROOT/.build/$(basename "$package")"
  fi
done
exec "$DEVELOPER_DIR/usr/bin/xcodebuild" -project "$WRITER_MAC_ROOT/NostrWriter.xcodeproj" \
  -scheme NostrWriter -configuration Debug -derivedDataPath "$WRITER_DERIVED_DATA" \
  -destination 'platform=macOS' -skipPackagePluginValidation \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES test "$@"
