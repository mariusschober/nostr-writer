#!/bin/bash
# Owner-controlled development signing, separate from release/notarization.
set -euo pipefail
if [[ ! "${WRITER_DEVELOPMENT_TEAM:-}" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "Set WRITER_DEVELOPMENT_TEAM to your existing Apple Developer team identifier." >&2
  exit 2
fi
if [[ $# != 0 ]]; then
  echo "This fixed Debug build takes no extra build-setting arguments." >&2
  exit 2
fi
if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq '"Apple Development:'; then
  echo "No existing Apple Development identity is available. Configure your team and identity in Xcode/Keychain first." >&2
  exit 2
fi
WRITER_SIGNING_MAC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export WRITER_DERIVED_DATA="$WRITER_SIGNING_MAC_ROOT/.build/SignedDevelopment"
export WRITER_CONFIGURATION=Debug
# Do not request automatic provisioning or create identities on the owner's behalf.
"$WRITER_SIGNING_MAC_ROOT/scripts/build.sh" \
  DEVELOPMENT_TEAM="$WRITER_DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  WRITER_APP_ENTITLEMENTS=NostrWriter/DeveloperSigning.entitlements
python3 "$WRITER_SIGNING_MAC_ROOT/scripts/inspect_app.py" \
  "$WRITER_DERIVED_DATA/Build/Products/Debug/NostrWriter.app" \
  --development-team "$WRITER_DEVELOPMENT_TEAM"
