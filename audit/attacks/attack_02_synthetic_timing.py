#!/usr/bin/env python3
"""Attack 02: synthetic keystroke timing generated to look human.

The event stream is produced by a program with a hand-written variable-delay
schedule and sentence pauses.  It contains no observation of a person.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import TEXT, emit, js_verify, make, make_human_like_timing, py_verify, trace_facts  # noqa: E402


def main():
    text = TEXT * 2
    record = make_human_like_timing(text, did="synthetic-timing")
    fixture = make(name="synthetic-timing", record=record)
    facts = trace_facts(record)
    facts["schedule"] = {
        "kind": "hand-written variable delays with pauses",
        "delays_ms": [120, 95, 210, 80, 300, 140, 90, 250, 110, 180, 70, 230],
        "pauses_us": {"40": 1200000, "120": 900000, "220": 1500000},
        "human_observation": False,
    }
    emit(
        {
            "attack": "synthetic keystroke timing generated to mimic humans",
            "description": (
                "A program inserts every character with a variable delay schedule "
                "and three sentence-like pauses. The client records ordinary device "
                "sources and native deliveries."
            ),
            "expected_in_principle": (
                "No protocol guarantee of detection. Timing is only an input feature; "
                "the verifier has no independent clock. An observer-only rule cannot "
                "distinguish an attack whose observation distribution equals the "
                "genuine distribution (ALGORITHM.md 'Falsifiable limitations retained'; "
                "THREAT-MODEL.md 'Guarantees that do not follow')."
            ),
            "trace": facts,
            "computed_internal_result": fixture["computed"].get("result"),
            "python": [py_verify(fixture), py_verify(fixture, recompute=True)],
            "javascript_attested": js_verify(fixture),
            "notes": (
                "The permissive conformance model accepts the trace. A trained model "
                "might separate this particular schedule, but no production model is "
                "shipped and no universal timing detector is claimed."
            ),
        }
    )


if __name__ == "__main__":
    main()
