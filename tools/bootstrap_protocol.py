#!/usr/bin/env python3
"""Verify the directly committed, immutable HWP v0 distribution.

The historical bootstrap reconstructed files from a transport archive.  The
final 69-file distribution is now committed directly, so this command only
checks it.  ``--extract-only`` remains accepted for command compatibility; it
does not extract, generate, or modify anything.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from typing import Any


FREEZE_SHA256 = "c04ded3b82a462aa22a7289a5bcbeccd5719124a4718cb5fbd4f47c297993d88"
PROTOCOL_DEFINITION_SHA256 = (
    "58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4"
)
EXPECTED_DISTRIBUTION_FILES = 69
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")


class ProtocolVerificationError(ValueError):
    """The committed protocol distribution is absent, changed, or unsafe."""


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _inventory_path(protocol_root: Path, raw: object) -> tuple[str, Path]:
    if not isinstance(raw, str) or not raw or "\\" in raw or "\0" in raw:
        raise ProtocolVerificationError("unsafe-inventory-path")
    relative = PurePosixPath(raw)
    if (
        relative.is_absolute()
        or any(part in ("", ".", "..") for part in relative.parts)
        or relative.as_posix() != raw
    ):
        raise ProtocolVerificationError(f"unsafe-inventory-path:{raw}")
    current = protocol_root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise ProtocolVerificationError(f"protocol-symlink:{raw}")
    if not current.is_file():
        raise ProtocolVerificationError(f"missing-inventory-file:{raw}")
    return raw, current


def verify_protocol(repo_root: Path) -> dict[str, Any]:
    """Return verification details without changing the repository."""

    root = repo_root.resolve()
    protocol_dir = root / "protocol"
    protocol_root = protocol_dir / "v0"
    freeze_path = protocol_root / "FREEZE.json"
    freeze_digest_path = protocol_root / "FREEZE.sha256"
    checker = protocol_root / "tools" / "check_freeze.py"

    for required in (protocol_dir, protocol_root, freeze_path, freeze_digest_path, checker):
        if required.is_symlink():
            raise ProtocolVerificationError(f"symlink-not-allowed:{required.relative_to(root)}")
        if not required.exists():
            raise ProtocolVerificationError(f"missing:{required.relative_to(root)}")

    raw_freeze = freeze_path.read_bytes()
    observed_freeze_digest = _sha256(raw_freeze)
    if observed_freeze_digest != FREEZE_SHA256:
        raise ProtocolVerificationError(
            f"freeze-digest:{observed_freeze_digest}:expected:{FREEZE_SHA256}"
        )

    declared_freeze_digest = freeze_digest_path.read_text(encoding="utf-8").split()
    if not declared_freeze_digest or declared_freeze_digest[0] != FREEZE_SHA256:
        raise ProtocolVerificationError("freeze-sha256-file")

    try:
        freeze = json.loads(raw_freeze)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProtocolVerificationError(f"freeze-json:{exc}") from exc
    if not isinstance(freeze, dict):
        raise ProtocolVerificationError("freeze-json-root")
    if freeze.get("protocol_definition_sha256") != PROTOCOL_DEFINITION_SHA256:
        raise ProtocolVerificationError("protocol-definition-digest")
    files = freeze.get("files")
    if not isinstance(files, list) or len(files) + 2 != EXPECTED_DISTRIBUTION_FILES:
        raise ProtocolVerificationError("freeze-file-count")

    listed: set[str] = set()
    for index, entry in enumerate(files):
        if not isinstance(entry, dict) or set(entry) != {"path", "sha256", "size"}:
            raise ProtocolVerificationError(f"freeze-entry-schema:{index}")
        name, path = _inventory_path(protocol_root, entry["path"])
        if name in listed:
            raise ProtocolVerificationError(f"duplicate-inventory-path:{name}")
        listed.add(name)
        expected_size = entry["size"]
        expected_digest = entry["sha256"]
        if (
            isinstance(expected_size, bool)
            or not isinstance(expected_size, int)
            or expected_size < 0
        ):
            raise ProtocolVerificationError(f"inventory-size:{name}")
        if not isinstance(expected_digest, str) or SHA256_RE.fullmatch(expected_digest) is None:
            raise ProtocolVerificationError(f"inventory-sha256:{name}")
        if path.stat().st_size != expected_size or _sha256_file(path) != expected_digest:
            raise ProtocolVerificationError(f"changed-inventory-file:{name}")

    for path in protocol_root.rglob("*"):
        if path.is_symlink():
            raise ProtocolVerificationError(
                f"protocol-symlink:{path.relative_to(protocol_root).as_posix()}"
            )

    present = {
        path.relative_to(protocol_root).as_posix()
        for path in protocol_root.rglob("*")
        if path.is_file()
        and "__pycache__" not in path.parts
        and path.suffix != ".pyc"
        and path.name not in ("FREEZE.json", "FREEZE.sha256")
    }
    if present != listed:
        missing = sorted(listed - present)
        unlisted = sorted(present - listed)
        raise ProtocolVerificationError(
            f"inventory-membership:missing={missing}:unlisted={unlisted}"
        )

    # The original checker is itself covered by the verified inventory above.
    # Invoke it only after all payload bytes, including the checker, are trusted.
    environment = dict(os.environ)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    completed = subprocess.run(
        [sys.executable, str(checker)],
        cwd=protocol_root,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = (completed.stdout + completed.stderr).strip()
        raise ProtocolVerificationError(f"original-freeze-checker:{detail}")
    try:
        original_result = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise ProtocolVerificationError("original-freeze-checker-output") from exc
    if original_result.get("status") != "PASS":
        raise ProtocolVerificationError("original-freeze-checker-status")
    if original_result.get("files") != len(files):
        raise ProtocolVerificationError("original-freeze-checker-count")
    if original_result.get("freeze_sha256") != FREEZE_SHA256:
        raise ProtocolVerificationError("original-freeze-checker-freeze-digest")
    if original_result.get("protocol_definition_sha256") != PROTOCOL_DEFINITION_SHA256:
        raise ProtocolVerificationError("original-freeze-checker-protocol-digest")

    return {
        "status": "PASS",
        "mode": "read-only-verification",
        "distribution_files": EXPECTED_DISTRIBUTION_FILES,
        "inventoried_files": len(files),
        "freeze_sha256": FREEZE_SHA256,
        "protocol_definition_sha256": PROTOCOL_DEFINITION_SHA256,
        "original_freeze_checker": "PASS",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--extract-only",
        action="store_true",
        help="accepted for legacy compatibility; still performs read-only verification",
    )
    args = parser.parse_args(argv)
    repo_root = Path(__file__).resolve().parents[1]
    try:
        result = verify_protocol(repo_root)
        if args.extract_only:
            result["compatibility_option"] = "--extract-only accepted; no extraction performed"
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0
    except (OSError, ProtocolVerificationError) as exc:
        print(json.dumps({"status": "FAIL", "reason": str(exc)}, indent=2), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
