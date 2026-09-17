#!/usr/bin/env python3
"""Admit only the inspected, pinned P256K source-copy build plugin."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
checkouts = Path(sys.argv[1]) / "SourcePackages" / "checkouts"
expected = "6f24e4851744dee70c8df365caab692d0d0c1dee8c5649b4695ba51893b93af0"
plugin = checkouts / "swift-secp256k1/Plugins/SharedSourcesPlugin/Plugin.swift"
pins = json.loads((root / "NostrWriter.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())["pins"]
pin = next(row for row in pins if row["identity"] == "swift-secp256k1")
if pin["state"]["revision"] != "e70a10e036a55fffea31568f0af92d69b6d449cd":
    raise SystemExit("Unreviewed P256K revision; inspect before building.")
if hashlib.sha256(plugin.read_bytes()).hexdigest() != expected:
    raise SystemExit("Build plugin differs from the inspected source-copy plugin.")
plugins = set(checkouts.glob("*/Plugins/**/*.swift"))
if plugins != {plugin}:
    raise SystemExit("Unreviewed dependency build plugin found.")
print("PASS: exact inspected P256K source-copy build plugin")
