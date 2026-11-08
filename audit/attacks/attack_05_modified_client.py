#!/usr/bin/env python3
"""Attack 05: a modified client fabricates the whole capture.

The final text is chosen first.  The client then synthesizes observations,
native deliveries, mutations, a Merkle tree and signed start/end under the
admitted capture key.  No physical session occurred.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import Builder, emit, js_verify, make, py_verify, trace_facts  # noqa: E402

FABRICATED_TEXT = (
    "Nothing in this paragraph was observed. The capture client was modified to "
    "synthesize every keystroke, delivery and pause after the final text was chosen. "
    "The resulting trace is internally consistent, and the reference verifier has no "
    "way to tell it from a real session. This is the admitted-source boundary."
)


def main():
    record = Builder("modified-client", "keyboard").type(FABRICATED_TEXT, seed=17).record()
    fixture = make(name="modified-client", record=record)
    facts = trace_facts(record)
    facts["construction"] = {
        "final_text_chosen_before_events": True,
        "events_synthesized": True,
        "physical_session_observed": False,
    }
    emit(
        {
            "attack": "modified client fabricates capture data",
            "description": (
                "A modified capture client invents a complete, structurally valid "
                "history consistent with a chosen final document, signs the start and "
                "end with the admitted capture key, and has the admitted evaluator sign "
                "the statement."
            ),
            "expected_in_principle": (
                "Not detectable by the reference verifier. Signatures authenticate the "
                "key, not the client's honesty. A dishonest admitted source can "
                "fabricate a structurally valid history (SPECIFICATION.md sections 3, 6, 8; "
                "BINDING.md section 6; AUDIT.md 'What is fixed versus assumed'; "
                "THREAT-MODEL.md row 'Fabrication of delivery fields or timestamps')."
            ),
            "trace": facts,
            "computed_internal_result": fixture["computed"].get("result"),
            "python": [py_verify(fixture), py_verify(fixture, recompute=True)],
            "javascript_attested": js_verify(fixture),
            "notes": (
                "Unlike the frozen paste-based lying-attestor regression, this trace "
                "fabricates device events that the real bridge replays and accepts. "
                "Disclosed recomputation therefore passes too: it checks consistency, "
                "not physical occurrence."
            ),
        }
    )


if __name__ == "__main__":
    main()
