#!/usr/bin/env python3
"""Check committed Swift resolution and license bytes against the reviewed inventory."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
inventory = json.loads((root / "ThirdParty/dependencies.json").read_text())["dependencies"]
expected = {row["name"].lower(): row["revision"] for row in inventory}
locks = [root / "NostrWriter.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"]
locks += sorted((root / "Packages").glob("*/Package.resolved"))
for lock in locks:
    pins = json.loads(lock.read_text())["pins"]
    actual = {pin["identity"].lower(): pin["state"]["revision"] for pin in pins}
    assert len(actual) == len(pins), f"Duplicate dependency identity in {lock}"
    assert all(expected.get(name) == revision for name, revision in actual.items()), f"Unreviewed dependency in {lock}"
    if lock == locks[0]:
        assert actual == expected, "App lockfile does not match full dependency inventory"
for row in inventory:
    license_path = root / row["license_file"]
    assert hashlib.sha256(license_path.read_bytes()).hexdigest() == row["license_sha256"], f"Changed license for {row['name']}"
print(f"PASS: {len(expected)} dependency revisions and licenses; {len(locks)} lockfiles")
