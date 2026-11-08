"""Shared, read-only attack harness for the frozen HWP v0 verifiers.

No file under protocol/v0 is written.  The harness imports the frozen package,
builds synthetic traces in memory, and invokes the Python R verifier and the
JavaScript V verifier through their public entry points.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PROTO = REPO / "protocol" / "v0"
if str(PROTO) not in sys.path:
    sys.path.insert(0, str(PROTO))

from hwp0 import core as c, protocol as p, bridge  # noqa: E402
from hwp0.algorithm.fixtures import Builder, TEXT, permissive_fixture_model  # noqa: E402
from tests.support import make, seed  # noqa: E402


def jsonable(value):
    """Render the exact verifier result as JSON without losing byte identities."""
    if isinstance(value, bytes):
        return {"$bytes_hex": value.hex()}
    if isinstance(value, dict):
        return {str(k): jsonable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [jsonable(v) for v in value]
    return value


def py_verify(fixture, recompute=False, policy_pin=None, policy_bytes=None):
    """Call the public Python R verifier exactly as a relying party would."""
    pb = fixture["policy_bytes"] if policy_bytes is None else policy_bytes
    pin = fixture["policy_pin"] if policy_pin is None else policy_pin
    call = {
        "verifier": "python protocol/v0 hwp0.protocol.verify",
        "recompute": bool(recompute),
        "policy_pin_hex": pin.hex(),
    }
    try:
        result = p.verify(
            fixture["bundle"],
            fixture["document"],
            pb,
            pin,
            fixture.get("disclosures"),
            recompute=recompute,
        )
        return {
            "call": call,
            "verbatim_repr": repr(result),
            "result": jsonable(result),
        }
    except BaseException as exc:  # the public entry point normally catches; keep evidence
        return {
            "call": call,
            "exception": f"{type(exc).__name__}: {exc}",
        }


def js_verify(fixture, policy_pin=None, policy_bytes=None):
    """Call the independent JavaScript V verifier CLI on the same bytes."""
    pin = fixture["policy_pin"] if policy_pin is None else policy_pin
    pb = fixture["policy_bytes"] if policy_bytes is None else policy_bytes
    with tempfile.TemporaryDirectory(prefix="hwp-audit-") as tmp:
        tmp = Path(tmp)
        proof = tmp / "proof.hwp"
        document = tmp / "document.txt"
        policy = tmp / "policy.cbor"
        proof.write_bytes(fixture["bundle"])
        document.write_bytes(fixture["document"])
        policy.write_bytes(pb)
        command = [
            "node",
            str(PROTO / "tools" / "verify_attested.mjs"),
            str(proof),
            "--document",
            str(document),
            "--policy",
            str(policy),
            "--policy-pin",
            pin.hex(),
        ]
        completed = subprocess.run(
            command,
            cwd=str(REPO),
            capture_output=True,
            text=True,
            timeout=300,
            check=False,
        )
        parsed = None
        if completed.stdout.strip():
            try:
                parsed = json.loads(completed.stdout)
            except json.JSONDecodeError:
                parsed = None
        return {
            "call": {
                "verifier": "node protocol/v0/tools/verify_attested.mjs",
                "policy_pin_hex": pin.hex(),
            },
            "command": " ".join(command),
            "exit_code": completed.returncode,
            "stdout_verbatim": completed.stdout,
            "stderr_verbatim": completed.stderr,
            "result": jsonable(parsed) if parsed is not None else None,
        }


def trace_facts(record):
    """Summarise the fabricated trace so the evidence shows what was built."""
    observations = record["observations"]
    transactions = record["transactions"]
    tx_times = [tx["t"] for tx in transactions]
    gaps = [b - a for a, b in zip(tx_times, tx_times[1:])]
    positive = [g for g in gaps if g > 0]
    return {
        "record_id": record["id"],
        "final_text_chars": len(record["final_text"]),
        "final_text_utf8_bytes": len(record["final_text"].encode("utf-8")),
        "observations": len(observations),
        "transactions": len(transactions),
        "sources": sorted({o["source"] for o in observations}),
        "profiles": sorted({o["profile"] for o in observations}),
        "observation_kinds": sorted({o["kind"] for o in observations}),
        "transaction_ops": sorted({tx["op"] for tx in transactions}),
        "transaction_sources": sorted({tx.get("source") for tx in transactions if "source" in tx}),
        "first_t_us": min(o["t"] for o in observations),
        "last_t_us": max(o["t"] for o in observations),
        "transaction_gap_min_us": min(positive) if positive else None,
        "transaction_gap_max_us": max(positive) if positive else None,
        "transaction_gap_distinct": len(set(positive)),
        "fixed_transaction_cadence": len(set(positive)) == 1 if positive else None,
    }


def emit(payload):
    print(json.dumps(jsonable(payload), indent=2, sort_keys=True, ensure_ascii=False))


def make_human_like_timing(text, did="synthetic-timing", seed_value=31):
    """A programmatic trace with human-looking variation and pauses.

    The delays are a hand-written schedule, not measurements of a person.
    """
    delays_ms = [120, 95, 210, 80, 300, 140, 90, 250, 110, 180, 70, 230]
    pause_at = {40: 1_200_000, 120: 900_000, 220: 1_500_000}
    builder = Builder(did, "keyboard")
    for index, char in enumerate(text):
        if index in pause_at:
            builder.time += pause_at[index]
        builder.splice(
            len(builder.text),
            len(builder.text),
            char,
            delay=delays_ms[index % len(delays_ms)] * 1000,
            observed_source="device",
        )
    return builder.record()


def make_fixed_cadence(text, did="autotyper", delay_us=2_000):
    """A programmatic trace with a single fixed inter-key delay and no pauses."""
    builder = Builder(did, "keyboard")
    for char in text:
        builder.splice(
            len(builder.text),
            len(builder.text),
            char,
            delay=delay_us,
            observed_source="device",
        )
    return builder.record()


def make_production_proof(
    name="self-issued-production",
    text=None,
    record=None,
    profile="keyboard",
    claim="fresh-composition",
):
    """Build a self-consistent *production* proof with an attacker-minted release.

    This is not a study.  The empirical reports and capture evaluation are
    arbitrary byte strings, the model is the permissive conformance fixture,
    and the policy pin is computed from the attacker's own policy.  It exists to
    show what the verifier will accept when the relying party's pin is the
    attacker's pin.
    """
    text = TEXT * 2 if text is None else text
    record = record or Builder(name, profile).type(text, seed=11).record()
    store = c.Store()
    proto, fixed = p.install_objects(store)
    keys = {
        key: store.add(c.key_bytes(c.public_key(seed(key))))
        for key in ("capture", "evaluator", "evaluator2", "author", "identity", "other")
    }
    bundle = {"version": "hwp-a/v0", "documents": [record], "target": record["id"]}
    model = permissive_fixture_model(bundle)
    model["purpose"] = "validated-release"
    model_ref = store.put(model)
    decision = {
        "threshold": 0,
        "claim_kind": claim,
        "allowed_domains": sorted(model["domains"], key=lambda z: z.encode("utf-8")),
    }
    decision_ref = store.put(decision)
    domains = sorted({"|".join(z.split("|")[:3]) for z in model["domains"]})
    evaluation_ref = store.add(
        b"synthetic capture evaluation: no device, no study, no human observation"
    )
    profile_obj = {
        "v": c.VERSION,
        "type": "capture-profile",
        "class": "evaluated",
        "domains": domains,
        "max_resolution_us": 10000,
        "assumptions": p.ASSUMPTIONS,
        "evaluation": evaluation_ref,
    }
    profile_ref = store.put(profile_obj)
    artifacts = dict(fixed, model=model_ref, decision_policy=decision_ref)

    candidate_dossier = {
        "v": c.VERSION,
        "type": "validation-dossier",
        "stage": "conformance",
        "claim": claim,
        "model": model_ref,
        "decision_policy": decision_ref,
        "program": fixed["program"],
        "capture_profiles": [profile_ref],
        "allowed_domains": decision["allowed_domains"],
        "risk_target": [1, 1000],
        "coverage_target": [1, 2],
        "confidence": [19, 20],
        "reports": [],
        "candidate": None,
    }
    candidate_dossier_ref = store.put(candidate_dossier)
    candidate_release = {
        "v": c.VERSION,
        "type": "release",
        "algorithm": "hwp-a/v0",
        "claim": claim,
        "artifacts": artifacts,
        "capture_profiles": [profile_ref],
        "protocol": proto,
        "stage": "conformance",
        "validation": candidate_dossier_ref,
    }
    candidate_ref = store.put(candidate_release)

    reports = []
    for role in p.REPORT_ROLES:
        report_ref = store.add(
            ("synthetic %s report: no experiment, no data, no reviewer" % role).encode()
        )
        reports.append({"role": role, "artifact": report_ref})
    empirical_dossier = {
        "v": c.VERSION,
        "type": "validation-dossier",
        "stage": "empirical",
        "claim": claim,
        "model": model_ref,
        "decision_policy": decision_ref,
        "program": fixed["program"],
        "capture_profiles": [profile_ref],
        "allowed_domains": decision["allowed_domains"],
        "risk_target": [1, 1000],
        "coverage_target": [1, 2],
        "confidence": [19, 20],
        "reports": reports,
        "candidate": candidate_ref,
    }
    empirical_dossier_ref = store.put(empirical_dossier)
    release = {
        "v": c.VERSION,
        "type": "release",
        "algorithm": "hwp-a/v0",
        "claim": claim,
        "artifacts": artifacts,
        "capture_profiles": [profile_ref],
        "protocol": proto,
        "stage": "empirical",
        "validation": empirical_dossier_ref,
    }
    release_ref = store.put(release)

    start = store.add(
        c.sign(
            {
                "v": c.VERSION,
                "type": "capture-start",
                "session": seed("session/" + name),
                "profile": profile_ref,
                "adapter": fixed["evidence_adapter"],
                "nonce": seed("start/" + name),
                "subject": None,
                "release": release_ref,
                "parents": [],
            },
            seed("capture"),
        )
    )
    events = bridge.record_events(record)
    salts = [seed(name + "/event/" + str(i)) for i in range(len(events))]
    root, openings = c.commit_events(start, events, salts)
    document = record["final_text"].encode("utf-8")
    document_ref = store.add(document)
    end = store.add(
        c.sign(
            {
                "v": c.VERSION,
                "type": "capture-end",
                "start": start,
                "count": len(events),
                "root": root,
                "complete": True,
                "participation": None,
                "document": document_ref,
            },
            seed("capture"),
        )
    )
    policy = {
        "v": c.VERSION,
        "type": "verification-policy",
        "protocol": proto,
        "purpose": "production",
        "label": "Attacker-minted production policy; trusts attacker release and capture key",
        "releases": [release_ref],
        "capture_authorities": [{"profile": profile_ref, "keys": [keys["capture"]]}],
        "evaluators": [keys["evaluator"]],
        "quorum": 1,
        "modes": ["attested-v1", "disclosed-v1"],
        "require_author": False,
        "identity_authorities": [],
        "denied": [],
        "status_as_of": None,
    }
    policy_bytes = c.encode(policy)
    policy_pin = c.digest(policy_bytes)
    scope = store.put(
        {
            "v": c.VERSION,
            "type": "scope",
            "document": document_ref,
            "kind": "whole-document",
            "ranges": [{"start": 0, "end": len(document), "origin": ["observed", [end]]}],
        }
    )
    statement = {
        "v": c.VERSION,
        "type": "statement",
        "document": document_ref,
        "media_type": "text/plain",
        "scope": scope,
        "release": release_ref,
        "captures": [end],
        "target_capture": end,
        "lineage": bytes(32),
        "mode": "attested-v1",
        "author": None,
        "nonce": seed("statement/" + name),
    }
    temporary = store.put(statement)
    lineage_salt = seed("lineage/" + name)
    disclosures = {
        "logs": [{"capture": end, "openings": openings}],
        "lineage_salts": [{"statement": temporary, "salt": lineage_salt}],
    }
    computed, _ = p.evaluate_statement(store, temporary, policy_bytes, policy_pin, disclosures)
    statement["lineage"] = computed["lineage"]
    statement_ref = store.put(statement)
    disclosures["lineage_salts"][-1]["statement"] = statement_ref
    appraisal = c.sign_appraisal(store, statement_ref, computed, seed("evaluator"))
    proof = store.put(
        {"v": c.VERSION, "type": "proof", "statement": statement_ref, "appraisals": [appraisal], "author": None}
    )
    return {
        "store": store,
        "proof": proof,
        "bundle": store.pack(proof),
        "document": document,
        "policy_bytes": policy_bytes,
        "policy_pin": policy_pin,
        "disclosures": disclosures,
        "record": record,
        "computed": computed,
        "release": release_ref,
        "profile": profile_ref,
        "start": start,
        "end": end,
        "mode": "production",
    }
