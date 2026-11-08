#!/usr/bin/env python3
"""Run every audit attack, save raw evidence, and check the frozen tree.

The evidence files contain the exact command, stdout, stderr and exit code.
The summary is derived only from those outputs.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ATTACK_DIR = REPO / "audit" / "attacks"
EVIDENCE = REPO / "audit" / "evidence"
PYTHON = sys.executable

ATTACKS = [
    ("10-replay", "attack_01_replay.py"),
    ("11-synthetic-timing", "attack_02_synthetic_timing.py"),
    ("12-retype-ai", "attack_03_retype_ai.py"),
    ("13-autotyper", "attack_04_autotyper.py"),
    ("14-modified-client", "attack_05_modified_client.py"),
    ("15-splice", "attack_06_splice.py"),
    ("16-self-issued-production", "attack_07_self_issued_production.py"),
]


def frozen_status():
    """Return git's view of the frozen directory, without changing it."""
    completed = subprocess.run(
        ["git", "status", "--porcelain=v1", "--", "protocol/v0"],
        cwd=str(REPO),
        capture_output=True,
        text=True,
        check=False,
    )
    diff = subprocess.run(
        ["git", "diff", "--stat", "--", "protocol/v0"],
        cwd=str(REPO),
        capture_output=True,
        text=True,
        check=False,
    )
    return {
        "status_porcelain": completed.stdout.strip(),
        "diff_stat": diff.stdout.strip(),
        "clean": not completed.stdout.strip() and not diff.stdout.strip(),
    }


def collect_verdicts(node, path=""):
    """Collect every verifier result object from a nested attack payload."""
    found = []
    if isinstance(node, dict):
        if "status" in node and "outcome" in node:
            found.append(
                {
                    "path": path,
                    "status": node.get("status"),
                    "outcome": node.get("outcome"),
                    "reason": node.get("reason"),
                    "execution_checked": node.get("execution_checked"),
                    "test_conformance": node.get("test_conformance"),
                    "claim": node.get("claim"),
                    "scope": node.get("scope"),
                }
            )
        if "issuance_rejected" in node:
            found.append({"path": path, "issuance_rejected": node["issuance_rejected"]})
        for key, value in node.items():
            if key in ("verbatim_repr", "stdout_verbatim", "stderr_verbatim"):
                continue
            found.extend(collect_verdicts(value, f"{path}.{key}" if path else str(key)))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            found.extend(collect_verdicts(value, f"{path}[{index}]"))
    return found


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    before = frozen_status()
    summary = {"frozen_before": before, "attacks": []}
    failures = []

    for identifier, script in ATTACKS:
        script_path = ATTACK_DIR / script
        command = [PYTHON, str(script_path)]
        environment = dict(os.environ)
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        completed = subprocess.run(
            command,
            cwd=str(REPO),
            capture_output=True,
            text=True,
            env=environment,
            timeout=600,
            check=False,
        )
        raw = (
            f"$ cd {REPO} && PYTHONDONTWRITEBYTECODE=1 {PYTHON} {script_path}\n"
            f"{completed.stdout}"
            f"--- stderr ---\n{completed.stderr}"
            f"[exit code: {completed.returncode}]\n"
        )
        evidence_path = EVIDENCE / f"{identifier}.txt"
        evidence_path.write_text(raw, encoding="utf-8")

        parsed = None
        try:
            parsed = json.loads(completed.stdout)
        except json.JSONDecodeError:
            parsed = None
        verdicts = collect_verdicts(parsed) if parsed is not None else []
        entry = {
            "id": identifier,
            "script": str(script_path.relative_to(REPO)),
            "evidence": str(evidence_path.relative_to(REPO)),
            "exit_code": completed.returncode,
            "parsed": parsed is not None,
            "verdicts": verdicts,
        }
        summary["attacks"].append(entry)
        if completed.returncode != 0 or parsed is None:
            failures.append(identifier)

    after = frozen_status()
    summary["frozen_after"] = after
    summary["frozen_untouched"] = before["clean"] and after["clean"]
    summary["all_attack_scripts_exited_zero"] = not failures
    summary["failures"] = failures
    (EVIDENCE / "attack-summary.json").write_text(
        json.dumps(summary, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, indent=2, sort_keys=True, ensure_ascii=False))
    return 0 if summary["frozen_untouched"] and not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
