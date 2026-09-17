#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/environment.sh"
"$DEVELOPER_DIR/usr/bin/xcodebuild" -project "$WRITER_MAC_ROOT/NostrWriter.xcodeproj" \
  -scheme NostrWriter -derivedDataPath "$WRITER_DERIVED_DATA" -resolvePackageDependencies
python3 "$WRITER_MAC_ROOT/scripts/verify_build_plugin.py" "$WRITER_DERIVED_DATA"
exec "$DEVELOPER_DIR/usr/bin/xcodebuild" -project "$WRITER_MAC_ROOT/NostrWriter.xcodeproj" \
  -scheme NostrWriter -configuration "${WRITER_CONFIGURATION:-Debug}" \
  -derivedDataPath "$WRITER_DERIVED_DATA" -destination 'generic/platform=macOS' \
  -skipPackagePluginValidation build "$@"
