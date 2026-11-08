#!/usr/bin/env python3
"""Attack 06: splice segments from several sessions.

Two controls are compared:

* represented copy/inherited: the child really carries copy transactions and
  inherited ranges, and must not be certified as fresh composition;
* relabeled as typed: a modified client re-emits the same final bytes as direct
  device insertions with no copy transaction.

The second case is the interesting forgery.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import Builder, TEXT, emit, js_verify, make, py_verify, trace_facts  # noqa: E402

SECOND = (
    "A second independent session records a different paragraph, different words and a "
    "different rhythm. It exists only as a synthetic fixture. The audit asks whether the "
    "protocol can tell that these bytes came from another session when a modified client "
    "re-emits them as typed."
)


def main():
    session_a = make(name="splice-a", record=Builder("a", "keyboard").type(TEXT, seed=21).record())
    session_b = make(name="splice-b", record=Builder("b", "keyboard").type(SECOND, seed=22).record())

    child_record = (
        Builder("child", "keyboard")
        .control("copy", from_doc="a", start=0, end=len(TEXT), to=0, parent_text=TEXT)
        .control("copy", from_doc="b", start=0, end=len(SECOND), to=len(TEXT), parent_text=SECOND)
        .record()
    )

    def inherited_scope(_end):
        return [
            {
                "start": 0,
                "end": len(session_a["document"]),
                "origin": ["inherited", session_a["proof"], 0, len(session_a["document"])],
            },
            {
                "start": len(session_a["document"]),
                "end": len(session_a["document"]) + len(session_b["document"]),
                "origin": ["inherited", session_b["proof"], 0, len(session_b["document"])],
            },
        ]

    inherited = make(
        name="splice-inherited",
        claim="wording-origin",
        record=child_record,
        parents=(session_a, session_b),
        scope_ranges=inherited_scope,
    )
    inherited_python = [py_verify(inherited), py_verify(inherited, recompute=True)]

    fresh_copy_case = {
        "case": "copied-segments-claimed-fresh-control",
        "trace": trace_facts(child_record),
    }
    try:
        fresh_copy = make(
            name="splice-fresh-copy",
            claim="fresh-composition",
            record=child_record,
            parents=(session_a, session_b),
            scope_ranges=inherited_scope,
        )
        fresh_copy_case["computed_internal_result"] = fresh_copy["computed"].get("result")
        fresh_copy_case["python"] = [py_verify(fresh_copy), py_verify(fresh_copy, recompute=True)]
        fresh_copy_case["javascript_attested"] = js_verify(fresh_copy)
    except BaseException as exc:
        fresh_copy_case["issuance_rejected"] = f"{type(exc).__name__}: {exc}"
        fresh_copy_case["python"] = []
        fresh_copy_case["javascript_attested"] = None

    forged_text = TEXT + SECOND
    forged_record = Builder("forged-child", "keyboard").type(forged_text, seed=23).record()
    forged = make(name="splice-forged-fresh", record=forged_record)
    forged_python = [py_verify(forged), py_verify(forged, recompute=True)]

    emit(
        {
            "attack": "splicing segments from several sessions",
            "description": (
                "Two synthetic sessions supply two paragraphs. A child record first "
                "represents the union as copy transactions with inherited ranges. A "
                "second, modified client re-emits the identical final bytes as direct "
                "typed events in one new record."
            ),
            "expected_in_principle": (
                "Partial. A represented copy is visible: fresh-composition must reject "
                "it and wording-origin may carry literal ancestry (SPECIFICATION.md "
                "section 7; ALGORITHM.md 'Deterministic reconstruction'; BINDING.md "
                "section 4). A typed relabel has no copy edge and is the modified-client "
                "case, which the verifier cannot distinguish."
            ),
            "sessions": {
                "a": {"record": trace_facts(session_a["record"]), "document_hex": session_a["document"].hex()},
                "b": {"record": trace_facts(session_b["record"]), "document_hex": session_b["document"].hex()},
            },
            "same_final_document": inherited["document"] == forged["document"],
            "inherited_control": {
                "computed_internal_result": inherited["computed"].get("result"),
                "claim": inherited_python[0]["result"].get("claim"),
                "trace": trace_facts(child_record),
                "python": inherited_python,
                "javascript_attested": js_verify(inherited),
            },
            "fresh_copy_control": fresh_copy_case,
            "forged_fresh_relabel": {
                "computed_internal_result": forged["computed"].get("result"),
                "claim": forged_python[0]["result"].get("claim"),
                "trace": trace_facts(forged_record),
                "python": forged_python,
                "javascript_attested": js_verify(forged),
            },
            "notes": (
                "The inherited and forged proofs cover the same final document. The "
                "inherited one is limited to wording-origin; the forged one is internally "
                "certified as fresh composition because it carries no copy transaction."
            ),
        }
    )


if __name__ == "__main__":
    main()
