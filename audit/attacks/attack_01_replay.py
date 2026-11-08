#!/usr/bin/env python3
"""Attack 01: replay a genuine-looking trace as the same proof and as a new session.

The trace is a synthetic conformance fixture.  The point is structural: the
second proof commits the *same record bytes* under a fresh start/session/salts.
No human is observed in either case.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import emit, js_verify, make, py_verify, trace_facts  # noqa: E402


def main():
    genuine = make(name="replay-genuine")
    replayed = make(name="replay-new-session", record=genuine["record"])

    cases = []
    for label, fixture in (("same-proof-resubmitted", genuine), ("same-events-new-session", replayed)):
        cases.append(
            {
                "case": label,
                "trace": trace_facts(fixture["record"]),
                "document_hex": fixture["document"].hex(),
                "proof_sha256_hex": fixture["proof"]["sha256"].hex(),
                "computed_internal_result": fixture["computed"].get("result"),
                "python": [
                    py_verify(fixture),
                    py_verify(fixture, recompute=True),
                ],
                "javascript_attested": js_verify(fixture),
            }
        )

    emit(
        {
            "attack": "replay of a genuine human trace",
            "description": (
                "First re-submit an unchanged valid proof. Then re-commit the exact "
                "same record events under a fresh session ID, nonce and salts and "
                "present the result as a new writing session."
            ),
            "expected_in_principle": (
                "Not detectable by the verifier alone. Re-verifying an old proof is "
                "valid by design; hidden duplicate sessions require source integrity "
                "or external comparison (SPECIFICATION.md section 6; THREAT-MODEL.md "
                "row 'Reusing valid history as a new session')."
            ),
            "same_record_bytes": genuine["record"] == replayed["record"],
            "same_final_document": genuine["document"] == replayed["document"],
            "different_proof": genuine["proof"] != replayed["proof"],
            "cases": cases,
            "notes": (
                "The replayed proof has a different Merkle root because the start "
                "object is different, but it reconstructs the identical record and "
                "final text. Both public verifiers treat it as a valid conformance "
                "proof (TEST-ONLY / NOT PROVABLE), not as a replay failure."
            ),
        }
    )


if __name__ == "__main__":
    main()
