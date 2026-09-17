from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

from check_preparation import (  # noqa: E402
    IntegrityError,
    SNAPSHOT_FORMAT,
    verify_current_markdown_links,
    verify_snapshot_manifest,
)
import bootstrap_protocol  # noqa: E402


class SnapshotManifestCorruptionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="nostr-writer-check-")
        self.root = Path(self.temp.name)
        self.payload = self.root / "payload.txt"
        self.payload.write_bytes(b"preserved bytes\n")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_manifest(self, **overrides: object) -> None:
        entry = {
            "path": "payload.txt",
            "bytes": self.payload.stat().st_size,
            "sha256": hashlib.sha256(self.payload.read_bytes()).hexdigest(),
            "provenance": "synthetic regression fixture",
        }
        entry.update(overrides)
        manifest = {"format": SNAPSHOT_FORMAT, "files": [entry]}
        (self.root / "SOURCE-OF-TRUTH-MANIFEST.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )

    def test_valid_manifest_passes(self) -> None:
        self.write_manifest()
        self.assertEqual(verify_snapshot_manifest(self.root)["listed_files"], 1)

    def test_changed_bytes_fail(self) -> None:
        self.write_manifest()
        self.payload.write_bytes(b"changed\n")
        with self.assertRaises(IntegrityError):
            verify_snapshot_manifest(self.root)

    def test_parent_traversal_fails(self) -> None:
        self.write_manifest(path="../payload.txt")
        with self.assertRaises(IntegrityError):
            verify_snapshot_manifest(self.root)

    def test_symlink_fails(self) -> None:
        target = self.root / "target.txt"
        target.write_bytes(self.payload.read_bytes())
        self.payload.unlink()
        self.payload.symlink_to(target)
        self.write_manifest()
        with self.assertRaises(IntegrityError):
            verify_snapshot_manifest(self.root)


class MarkdownLinkCorruptionTests(unittest.TestCase):
    def test_broken_current_local_link_fails(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nostr-writer-links-") as temp:
            root = Path(temp)
            (root / "README.md").write_text("[missing](docs/missing.md)\n", encoding="utf-8")
            (root / "docs").mkdir()
            with self.assertRaises(IntegrityError):
                verify_current_markdown_links(root)


class ProtocolBootstrapOrderingTests(unittest.TestCase):
    def test_changed_original_checker_is_rejected_before_invocation(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nostr-writer-protocol-") as temp:
            root = Path(temp)
            protocol = root / "protocol" / "v0"
            checker = protocol / "tools" / "check_freeze.py"
            checker.parent.mkdir(parents=True)
            checker.write_text("print('synthetic checker')\n", encoding="utf-8")
            payloads = [checker]
            for index in range(66):
                path = protocol / "payload" / f"{index:02d}.bin"
                path.parent.mkdir(exist_ok=True)
                path.write_bytes(f"payload-{index}\n".encode())
                payloads.append(path)
            entries = []
            for path in payloads:
                data = path.read_bytes()
                entries.append(
                    {
                        "path": path.relative_to(protocol).as_posix(),
                        "sha256": hashlib.sha256(data).hexdigest(),
                        "size": len(data),
                    }
                )
            freeze = {
                "files": entries,
                "protocol_definition_sha256": bootstrap_protocol.PROTOCOL_DEFINITION_SHA256,
            }
            freeze_bytes = json.dumps(freeze, sort_keys=True).encode()
            freeze_digest = hashlib.sha256(freeze_bytes).hexdigest()
            (protocol / "FREEZE.json").write_bytes(freeze_bytes)
            (protocol / "FREEZE.sha256").write_text(
                f"{freeze_digest}  FREEZE.json\n", encoding="utf-8"
            )
            checker.write_text("print('modified checker')\n", encoding="utf-8")

            with mock.patch.object(bootstrap_protocol, "FREEZE_SHA256", freeze_digest):
                with mock.patch.object(bootstrap_protocol.subprocess, "run") as run:
                    with self.assertRaises(bootstrap_protocol.ProtocolVerificationError):
                        bootstrap_protocol.verify_protocol(root)
                    run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
