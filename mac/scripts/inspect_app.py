#!/usr/bin/env python3
"""Inspect the actual ordinary built app, rejecting UI-test instrumentation."""
import hashlib
import json
import plistlib
import re
from pathlib import Path
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
binary = app / "Contents/MacOS/NostrWriter"
def run(*args):
    return subprocess.run(args, check=True, capture_output=True)

entitlements = plistlib.loads(run("codesign", "-d", "--entitlements", "-", "--xml", str(app)).stdout)
required = {"com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-write", "com.apple.security.network.client"}
allowed = required | {"com.apple.security.get-task-allow"}
if set(entitlements) - allowed or not all(entitlements.get(key) is True for key in required):
    raise SystemExit("FAIL: missing required entitlement or forbidden/test-only entitlement present")
signature = run("codesign", "-dvvv", str(app)).stderr.decode()
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
    "status": "PASS", "scope": "Ordinary ad-hoc local build; not Developer ID or notarization",
    "app": str(app), "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
    "architectures": architectures, "entitlements": entitlements,
    "minimum_os_versions": minimums, "load_commands": load_commands,
    "signature": signature, "strict_signature_verification": "PASS"
}, indent=2))
