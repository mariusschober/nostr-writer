#!/usr/bin/env python3
"""Attack 07: self-issued production trust anchor.

This is the only executable route found to the literal VALID-HWP /
HUMAN-WRITTEN output.  The attacker mints a production policy that admits an
"empirical" release they also minted, with arbitrary report bytes and an
attacker-controlled capture key.  The policy pin is the attacker's own pin.

The control with the same proof under a conformance-purpose policy, and the
control with an independently wrong pin, show that the label is a function of
the external trust input, not of the trace.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import c, emit, js_verify, make_production_proof, py_verify, trace_facts  # noqa: E402


def main():
    forged = make_production_proof(name="self-issued-production")

    # Same release, same proof, same trace, but a conformance-purpose policy.
    conformance_policy = c.decode(forged["policy_bytes"])
    conformance_policy["purpose"] = "conformance"
    conformance_policy["label"] = "Conformance-purpose projection of the same fabricated proof"
    conformance_bytes = c.encode(conformance_policy)
    conformance_pin = c.digest(conformance_bytes)

    wrong_pin = bytes(32)
    facts = trace_facts(forged["record"])
    facts["construction"] = {
        "empirical_report_contents": "arbitrary synthetic bytes; no study",
        "capture_evaluation": "arbitrary synthetic bytes; no device",
        "model": "permissive conformance fixture relabelled validated-release",
        "policy_pin_source": "computed from the attacker's own policy bytes",
    }

    emit(
        {
            "attack": "self-issued production policy over a fabricated empirical release",
            "description": (
                "The attacker builds a production verification policy that admits an "
                "empirical release, an evaluated capture profile and capture/evaluator "
                "keys all under the attacker's control. The release's six report objects "
                "and capture evaluation are arbitrary byte strings. A synthetic trace is "
                "then signed and appraised under that release."
            ),
            "expected_in_principle": (
                "Not detectable by the verifier alone. The policy pin is the trust "
                "anchor. The specification requires an independent relying-party pin "
                "(SPECIFICATION.md section 3) and says report hashes and approval "
                "signatures do not establish ground truth (section 12; THREAT-MODEL.md "
                "row 'Self-approved record/model/fixture')."
            ),
            "trace": facts,
            "computed_internal_result": forged["computed"].get("result"),
            "attacker_policy": {
                "python_attested": py_verify(forged),
                "python_recomputed": py_verify(forged, recompute=True),
                "javascript_attested": js_verify(forged),
            },
            "control_same_proof_conformance_policy": {
                "python": py_verify(forged, policy_bytes=conformance_bytes, policy_pin=conformance_pin),
                "javascript_attested": js_verify(
                    forged, policy_bytes=conformance_bytes, policy_pin=conformance_pin
                ),
            },
            "control_same_proof_wrong_independent_pin": {
                "python": py_verify(forged, policy_pin=wrong_pin),
                "javascript_attested": js_verify(forged, policy_pin=wrong_pin),
            },
            "notes": (
                "The attacker-policy run is the literal HUMAN-WRITTEN result. It is "
                "not evidence of human writing: it shows the verifier faithfully "
                "applying the policy it was given. The conformance-policy control on "
                "the identical proof projects TEST-ONLY / NOT PROVABLE; the wrong-pin "
                "control rejects with external-policy-pin."
            ),
        }
    )


if __name__ == "__main__":
    main()
