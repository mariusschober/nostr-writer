#!/usr/bin/env python3
"""Read-only integrity checks for the recovered Nostr Writer preparation."""

from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import sys
from typing import Any, Iterable
from urllib.parse import unquote, urlsplit
import zipfile

sys.dont_write_bytecode = True
from bootstrap_protocol import verify_protocol


SNAPSHOT_FORMAT = "nostr-writer-source-of-truth/1"
RECOVERY_FORMAT = "nostr-writer-recovery/1"
SNAPSHOT_NAME = "SOURCE-OF-TRUTH-MANIFEST.json"
RECOVERY_NAME = "history/astra-pro/RECOVERY-INVENTORY.json"
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
GIT_SHA1_RE = re.compile(r"[0-9a-f]{40}\Z")
INLINE_LINK_RE = re.compile(
    r"!?\[[^\]\n]*\]\(\s*(?:<([^>\n]+)>|([^\s)]+))(?:\s+[^)]*)?\)"
)
REFERENCE_LINK_RE = re.compile(
    r"^\s{0,3}\[[^\]\n]+\]:\s*(?:<([^>\n]+)>|([^\s]+))", re.MULTILINE
)
ZIP_INDEX_DISPOSITION = "Original index preserved in ZIP; active algorithm index revised"
FINDER_DISPOSITION = "Finder metadata retained inside original ZIP only"


class IntegrityError(ValueError):
    """A recovery or preparation integrity condition failed."""


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_relative_path(raw: object, label: str) -> PurePosixPath:
    if not isinstance(raw, str) or not raw or "\\" in raw or "\0" in raw:
        raise IntegrityError(f"{label}:invalid-path")
    path = PurePosixPath(raw)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise IntegrityError(f"{label}:unsafe-path:{raw}")
    if path.as_posix() != raw:
        raise IntegrityError(f"{label}:noncanonical-path:{raw}")
    return path


def repo_file(repo_root: Path, raw: object, label: str) -> Path:
    relative = safe_relative_path(raw, label)
    current = repo_root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise IntegrityError(f"{label}:symlink:{relative.as_posix()}")
    if not current.is_file():
        raise IntegrityError(f"{label}:missing:{relative.as_posix()}")
    return current


def require_exact_keys(value: object, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise IntegrityError(f"{label}:not-object")
    actual = set(value)
    if actual != expected:
        raise IntegrityError(
            f"{label}:keys:missing={sorted(expected-actual)}:extra={sorted(actual-expected)}"
        )
    return value


def require_nonnegative_int(value: object, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise IntegrityError(f"{label}:not-nonnegative-integer")
    return value


def require_digest(value: object, label: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise IntegrityError(f"{label}:invalid-sha256")
    return value


def read_json(path: Path, label: str) -> Any:
    try:
        return json.loads(path.read_bytes())
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise IntegrityError(f"{label}:json:{exc}") from exc


def verify_snapshot_manifest(repo_root: Path) -> dict[str, Any]:
    manifest_path = repo_file(repo_root, SNAPSHOT_NAME, "snapshot")
    manifest = require_exact_keys(
        read_json(manifest_path, "snapshot"), {"format", "files"}, "snapshot"
    )
    if manifest["format"] != SNAPSHOT_FORMAT:
        raise IntegrityError("snapshot:format")
    entries = manifest["files"]
    if not isinstance(entries, list) or not entries:
        raise IntegrityError("snapshot:files")

    seen: set[str] = set()
    for index, raw_entry in enumerate(entries):
        label = f"snapshot:files[{index}]"
        entry = require_exact_keys(
            raw_entry, {"path", "bytes", "sha256", "provenance"}, label
        )
        relative = safe_relative_path(entry["path"], label)
        name = relative.as_posix()
        if name == SNAPSHOT_NAME:
            raise IntegrityError(f"{label}:manifest-self-reference")
        if name in seen:
            raise IntegrityError(f"{label}:duplicate:{name}")
        seen.add(name)
        expected_size = require_nonnegative_int(entry["bytes"], label)
        expected_digest = require_digest(entry["sha256"], label)
        provenance = entry["provenance"]
        if not isinstance(provenance, str) or not provenance.strip():
            raise IntegrityError(f"{label}:provenance")
        path = repo_file(repo_root, name, label)
        observed_size = path.stat().st_size
        if observed_size != expected_size:
            raise IntegrityError(
                f"{label}:size:{name}:observed={observed_size}:expected={expected_size}"
            )
        observed_digest = sha256_file(path)
        if observed_digest != expected_digest:
            raise IntegrityError(f"{label}:sha256:{name}")

    return {"format": SNAPSHOT_FORMAT, "listed_files": len(entries)}


def _validate_originals(repo_root: Path, rows: object) -> dict[str, dict[str, Any]]:
    if not isinstance(rows, list) or len(rows) != 47:
        raise IntegrityError("recovery:originals:expected-47")
    by_supplied: dict[str, dict[str, Any]] = {}
    archived_paths: set[str] = set()
    for index, raw_row in enumerate(rows):
        label = f"recovery:originals[{index}]"
        row = require_exact_keys(
            raw_row, {"supplied_path", "archive_path", "bytes", "sha256"}, label
        )
        supplied = safe_relative_path(row["supplied_path"], label).as_posix()
        archived = safe_relative_path(row["archive_path"], label).as_posix()
        if supplied in by_supplied or archived in archived_paths:
            raise IntegrityError(f"{label}:duplicate")
        expected_size = require_nonnegative_int(row["bytes"], label)
        expected_digest = require_digest(row["sha256"], label)
        path = repo_file(repo_root, archived, label)
        if path.stat().st_size != expected_size or sha256_file(path) != expected_digest:
            raise IntegrityError(f"{label}:identity:{archived}")
        by_supplied[supplied] = row
        archived_paths.add(archived)
    return by_supplied


def _zip_member_digest(archive: zipfile.ZipFile, info: zipfile.ZipInfo) -> str:
    digest = hashlib.sha256()
    with archive.open(info, "r") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_archive_members(repo_root: Path, rows: object) -> dict[str, int]:
    if not isinstance(rows, list) or not rows:
        raise IntegrityError("recovery:archive-members")
    allowed = {
        "archive",
        "member",
        "bytes",
        "sha256",
        "remote_at_start",
        "recovered_path",
        "disposition",
    }
    required = {"archive", "member", "bytes", "sha256"}
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    seen: set[tuple[str, str]] = set()
    for index, raw_row in enumerate(rows):
        label = f"recovery:archive-members[{index}]"
        if not isinstance(raw_row, dict):
            raise IntegrityError(f"{label}:not-object")
        keys = set(raw_row)
        if not required <= keys or not keys <= allowed:
            raise IntegrityError(f"{label}:keys")
        archive = safe_relative_path(raw_row["archive"], label).as_posix()
        member = safe_relative_path(raw_row["member"], label).as_posix()
        pair = (archive, member)
        if pair in seen:
            raise IntegrityError(f"{label}:duplicate")
        seen.add(pair)
        require_nonnegative_int(raw_row["bytes"], label)
        require_digest(raw_row["sha256"], label)
        grouped[archive].append(raw_row)

    recovered_verified = 0
    archive_member_count = 0
    for archive_name, inventory_rows in sorted(grouped.items()):
        archive_path = repo_file(repo_root, archive_name, "recovery:archive")
        try:
            with zipfile.ZipFile(archive_path) as archive:
                file_infos = [info for info in archive.infolist() if not info.is_dir()]
                names = [info.filename for info in file_infos]
                if len(names) != len(set(names)):
                    raise IntegrityError(f"recovery:archive:duplicate-member:{archive_name}")
                expected_names = {row["member"] for row in inventory_rows}
                if set(names) != expected_names:
                    raise IntegrityError(f"recovery:archive:member-set:{archive_name}")
                rows_by_member = {row["member"]: row for row in inventory_rows}
                for info in file_infos:
                    label = f"recovery:archive:{archive_name}:{info.filename}"
                    safe_relative_path(info.filename, label)
                    mode = info.external_attr >> 16
                    if stat.S_ISLNK(mode):
                        raise IntegrityError(f"{label}:symlink")
                    row = rows_by_member[info.filename]
                    if info.file_size != row["bytes"]:
                        raise IntegrityError(f"{label}:size")
                    if _zip_member_digest(archive, info) != row["sha256"]:
                        raise IntegrityError(f"{label}:sha256")
                    archive_member_count += 1

                    recovered = row.get("recovered_path")
                    disposition = row.get("disposition")
                    if recovered is None:
                        if disposition != FINDER_DISPOSITION:
                            raise IntegrityError(f"{label}:unexplained-unrecovered-member")
                        continue
                    if disposition == ZIP_INDEX_DISPOSITION:
                        if recovered != archive_name:
                            raise IntegrityError(f"{label}:index-disposition-path")
                        continue
                    recovered_path = repo_file(repo_root, recovered, label)
                    if (
                        recovered_path.stat().st_size != row["bytes"]
                        or sha256_file(recovered_path) != row["sha256"]
                    ):
                        raise IntegrityError(f"{label}:recovered-identity:{recovered}")
                    recovered_verified += 1
        except (OSError, zipfile.BadZipFile) as exc:
            raise IntegrityError(f"recovery:archive:{archive_name}:{exc}") from exc

    return {
        "archives": len(grouped),
        "archive_members": archive_member_count,
        "recovered_members_verified": recovered_verified,
    }


def _validate_chat6_mapping(
    repo_root: Path, rows: object, originals: dict[str, dict[str, Any]]
) -> int:
    if not isinstance(rows, list) or len(rows) != 35:
        raise IntegrityError("recovery:chat6-mapping:expected-35")
    seen_sources: set[str] = set()
    seen_targets: set[str] = set()
    for index, raw_row in enumerate(rows):
        label = f"recovery:chat6-mapping[{index}]"
        row = require_exact_keys(raw_row, {"source", "target", "original_sha256"}, label)
        source = safe_relative_path(row["source"], label).as_posix()
        target = safe_relative_path(row["target"], label).as_posix()
        digest = require_digest(row["original_sha256"], label)
        if source in seen_sources or target in seen_targets:
            raise IntegrityError(f"{label}:duplicate")
        seen_sources.add(source)
        seen_targets.add(target)
        original = originals.get(source)
        if original is None or original["sha256"] != digest:
            raise IntegrityError(f"{label}:original-identity:{source}")
        # Current product documents contain explicit recovery corrections.  Their
        # current bytes are pinned by SOURCE-OF-TRUTH-MANIFEST.json, not by the
        # original attachment hash.
        repo_file(repo_root, target, label)
    return len(rows)


def _validate_baseline_records(rows: object) -> int:
    if not isinstance(rows, list) or not rows:
        raise IntegrityError("recovery:baseline-files")
    seen: set[str] = set()
    for index, raw_row in enumerate(rows):
        label = f"recovery:baseline-files[{index}]"
        row = require_exact_keys(raw_row, {"path", "git_blob", "bytes", "sha256"}, label)
        name = safe_relative_path(row["path"], label).as_posix()
        if name in seen:
            raise IntegrityError(f"{label}:duplicate")
        seen.add(name)
        if not isinstance(row["git_blob"], str) or GIT_SHA1_RE.fullmatch(row["git_blob"]) is None:
            raise IntegrityError(f"{label}:git-blob")
        require_nonnegative_int(row["bytes"], label)
        require_digest(row["sha256"], label)
    return len(rows)


def verify_recovery_inventory(repo_root: Path) -> dict[str, Any]:
    inventory_path = repo_file(repo_root, RECOVERY_NAME, "recovery")
    inventory = require_exact_keys(
        read_json(inventory_path, "recovery"),
        {
            "format",
            "date",
            "repository",
            "baseline_commit",
            "originals",
            "archive_members",
            "chat6_mapping",
            "baseline_files",
        },
        "recovery",
    )
    if inventory["format"] != RECOVERY_FORMAT:
        raise IntegrityError("recovery:format")
    if not isinstance(inventory["baseline_commit"], str) or GIT_SHA1_RE.fullmatch(
        inventory["baseline_commit"]
    ) is None:
        raise IntegrityError("recovery:baseline-commit")
    originals = _validate_originals(repo_root, inventory["originals"])
    archive_result = _validate_archive_members(repo_root, inventory["archive_members"])
    mapped = _validate_chat6_mapping(repo_root, inventory["chat6_mapping"], originals)
    baseline = _validate_baseline_records(inventory["baseline_files"])
    return {
        "originals": len(originals),
        **archive_result,
        "chat6_mappings": mapped,
        "baseline_records": baseline,
    }


def verify_plans_and_acceptance(repo_root: Path) -> dict[str, Any]:
    expected_plans = {f"PLAN-{number:02d}-{name}.md" for number, name in enumerate(
        ("FOUNDATION", "DOCUMENTS", "EDITOR", "HWP", "EXPORT", "NOSTR", "FOCUS", "RELEASE"),
        start=1,
    )}
    expected_starts = {f"START-{number:02d}.md" for number in range(1, 9)}
    plans_dir = repo_root / "product" / "mac" / "plans"
    starts_dir = repo_root / "product" / "mac" / "starts"
    observed_plans = {path.name for path in plans_dir.glob("PLAN-*.md") if path.is_file()}
    observed_starts = {path.name for path in starts_dir.glob("START-*.md") if path.is_file()}
    if observed_plans != expected_plans:
        raise IntegrityError("preparation:plans:not-exactly-01-through-08")
    if observed_starts != expected_starts:
        raise IntegrityError("preparation:starts:not-exactly-01-through-08")
    for name in sorted(expected_plans):
        repo_file(repo_root, f"product/mac/plans/{name}", "preparation:plan")
    for name in sorted(expected_starts):
        repo_file(repo_root, f"product/mac/starts/{name}", "preparation:start")

    preparation = read_json(
        repo_file(repo_root, "product/mac/PREPARATION.json", "preparation"), "preparation"
    )
    if not isinstance(preparation, dict):
        raise IntegrityError("preparation:json-root")
    if (
        preparation.get("plans") != 8
        or preparation.get("start_prompts") != 8
        or preparation.get("mandatory_mvp_criteria") != 60
    ):
        raise IntegrityError("preparation:declared-counts")

    acceptance = read_json(
        repo_file(repo_root, "product/mac/contracts/acceptance.json", "acceptance"),
        "acceptance",
    )
    if not isinstance(acceptance, dict) or not isinstance(acceptance.get("criteria"), list):
        raise IntegrityError("acceptance:schema")
    criteria = acceptance["criteria"]
    expected_ids = {f"M{number:02d}" for number in range(1, 61)}
    observed_ids: set[str] = set()
    observed_stages: set[str] = set()
    for index, criterion in enumerate(criteria):
        label = f"acceptance:criteria[{index}]"
        if not isinstance(criterion, dict):
            raise IntegrityError(f"{label}:not-object")
        identifier = criterion.get("id")
        stage = criterion.get("stage")
        if not isinstance(identifier, str) or identifier in observed_ids:
            raise IntegrityError(f"{label}:id")
        if stage not in {f"{number:02d}" for number in range(1, 9)}:
            raise IntegrityError(f"{label}:stage")
        if criterion.get("mandatory") is not True:
            raise IntegrityError(f"{label}:not-mandatory")
        observed_ids.add(identifier)
        observed_stages.add(stage)
    if observed_ids != expected_ids or len(criteria) != 60:
        raise IntegrityError("acceptance:ids:not-M01-through-M60")
    if observed_stages != {f"{number:02d}" for number in range(1, 9)}:
        raise IntegrityError("acceptance:stages:not-01-through-08")

    return {
        "plans": 8,
        "starts": 8,
        "mandatory_acceptance_definitions": 60,
        "stages": 8,
        "application_acceptance_measured": False,
    }


def _without_fenced_code(text: str) -> str:
    output: list[str] = []
    fence: str | None = None
    for line in text.splitlines(keepends=True):
        stripped = line.lstrip()
        marker = stripped[:3]
        if fence is None and marker in ("```", "~~~"):
            fence = marker
            output.append("\n")
        elif fence is not None and stripped.startswith(fence):
            fence = None
            output.append("\n")
        elif fence is None:
            output.append(line)
        else:
            output.append("\n")
    return "".join(output)


def markdown_destinations(text: str) -> Iterable[str]:
    visible = _without_fenced_code(text)
    for match in INLINE_LINK_RE.finditer(visible):
        yield match.group(1) or match.group(2)
    for match in REFERENCE_LINK_RE.finditer(visible):
        yield match.group(1) or match.group(2)


def _current_markdown_files(repo_root: Path) -> list[Path]:
    files = set(repo_root.glob("*.md"))
    for directory in (repo_root / "docs", repo_root / "product", repo_root / "mac" / "docs"):
        if directory.is_dir():
            files.update(directory.rglob("*.md"))
    return sorted(path for path in files if path.is_file())


def verify_current_markdown_links(repo_root: Path) -> dict[str, int]:
    checked_files = _current_markdown_files(repo_root)
    checked_links = 0
    failures: list[str] = []
    resolved_root = repo_root.resolve()
    for source in checked_files:
        try:
            text = source.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            raise IntegrityError(f"markdown:{source.relative_to(repo_root)}:{exc}") from exc
        for destination in markdown_destinations(text):
            if destination.startswith("#") or destination.startswith("//"):
                continue
            parsed = urlsplit(destination)
            if parsed.scheme:
                continue
            local = unquote(parsed.path)
            if not local:
                continue
            checked_links += 1
            if local.startswith("/") or "\\" in local:
                failures.append(f"{source.relative_to(repo_root)} -> {destination} (unsafe)")
                continue
            candidate = source.parent / local
            try:
                candidate.resolve(strict=False).relative_to(resolved_root)
            except ValueError:
                failures.append(f"{source.relative_to(repo_root)} -> {destination} (outside repo)")
                continue
            if not candidate.exists():
                failures.append(f"{source.relative_to(repo_root)} -> {destination} (missing)")
    if failures:
        raise IntegrityError("markdown-links:\n" + "\n".join(failures))
    return {"markdown_files": len(checked_files), "local_links": checked_links}


def run_checks(repo_root: Path) -> tuple[dict[str, Any], list[str]]:
    checks: dict[str, Any] = {}
    errors: list[str] = []
    operations = (
        ("snapshot_manifest", verify_snapshot_manifest),
        ("recovery_inventory", verify_recovery_inventory),
        ("plans_and_acceptance", verify_plans_and_acceptance),
        ("current_markdown_links", verify_current_markdown_links),
        ("frozen_protocol", verify_protocol),
    )
    for name, operation in operations:
        try:
            checks[name] = {"status": "PASS", **operation(repo_root)}
        except (OSError, IntegrityError, ValueError) as exc:
            checks[name] = {"status": "FAIL", "reason": str(exc)}
            errors.append(f"{name}:{exc}")
    return checks, errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help=argparse.SUPPRESS,
    )
    args = parser.parse_args(argv)
    checks, errors = run_checks(args.repo_root.resolve())
    result = {"status": "FAIL" if errors else "PASS", "checks": checks}
    if errors:
        result["errors"] = errors
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
