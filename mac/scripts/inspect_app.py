#!/usr/bin/env python3
"""Inspect the actual ordinary built app, rejecting UI-test instrumentation."""
import argparse
import hashlib
import json
import plistlib
import re
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=Path)
parser.add_argument("--development-team", help="Verify an owner-signed Debug build for this explicit team")
args = parser.parse_args()
if args.development_team and not re.fullmatch(r"[A-Z0-9]{10}", args.development_team):
    raise SystemExit("FAIL: supply the actual 10-character Apple Developer team identifier")
app = args.app.resolve()
binary = app / "Contents/MacOS/NostrWriter"
def run(*args):
    return subprocess.run(args, check=True, capture_output=True)

entitlements = plistlib.loads(run("codesign", "-d", "--entitlements", "-", "--xml", str(app)).stdout)
required = {"com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-write", "com.apple.security.network.client"}
allowed = required | {"com.apple.security.get-task-allow"}
if args.development_team:
    allowed |= {"com.apple.application-identifier", "com.apple.developer.team-identifier", "keychain-access-groups"}
    bundle_id = plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"]
    app_id = entitlements.get("com.apple.application-identifier", "")
    prefix, separator, suffix = app_id.partition(".")
    if (bundle_id != "com.mariusschober.nostrwriter.development" or not separator
            or not re.fullmatch(r"[A-Z0-9]{10}", prefix) or suffix != bundle_id
            or entitlements.get("keychain-access-groups") != [app_id]
            or entitlements.get("com.apple.developer.team-identifier", args.development_team) != args.development_team):
        raise SystemExit("FAIL: unresolved/wrong development identity or broader-than-required Keychain access")
if set(entitlements) - allowed or not all(entitlements.get(key) is True for key in required):
    raise SystemExit("FAIL: missing required entitlement or forbidden/test-only entitlement present")
signature = run("codesign", "-dvvv", str(app)).stderr.decode()
if args.development_team:
    if not re.search(r"^TeamIdentifier=" + re.escape(args.development_team) + r"$", signature, re.MULTILINE):
        raise SystemExit("FAIL: actual signing certificate does not belong to the selected team")
    if not re.search(r"^Authority=Apple Development:", signature, re.MULTILINE):
        raise SystemExit("FAIL: an existing Apple Development certificate is required")
if "runtime)" not in signature:
    raise SystemExit("FAIL: actual signature does not enable hardened runtime")
run("codesign", "--verify", "--deep", "--strict", str(app))
architectures = run("xcrun", "lipo", "-archs", str(binary)).stdout.decode().split()
if set(architectures) != {"arm64", "x86_64"}:
    raise SystemExit("FAIL: app does not contain both required architectures")
load_commands = run("xcrun", "vtool", "-show-build", str(binary)).stdout.decode()
minimums = re.findall(r"\bminos\s+(\S+)", load_commands)
if len(minimums) != 2 or any(value != "14.0" for value in minimums):
    raise SystemExit("FAIL: actual deployment load commands do not target macOS 14.0")
print(json.dumps({
    "status": "PASS", "scope": ("Owner-signed development build; real Keychain runtime not yet verified; not Developer ID or notarization"
                               if args.development_team else "Ordinary ad-hoc local build; not Developer ID or notarization"),
    "app": str(app), "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
    "architectures": architectures, "entitlements": entitlements,
    "minimum_os_versions": minimums, "load_commands": load_commands,
    "signature": signature, "strict_signature_verification": "PASS"
}, indent=2))
