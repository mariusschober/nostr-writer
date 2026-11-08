#!/usr/bin/env python3
"""Attack 03: a human retypes AI-generated text.

The same paragraph is presented twice: once as direct human typing (no paste
transaction) and once as an explicit paste.  The paste is visible to HWP; the
retyping is not.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import Builder, emit, js_verify, make, py_verify, trace_facts  # noqa: E402

# A locally written stand-in for machine-generated prose.  No AI service was
# called; the audit is about the observation contract, not about this string.
AI_TEXT = (
    "Artificial intelligence systems can generate fluent prose at scale. A writer who "
    "copies that prose by hand still produces keystrokes, pauses and corrections. This "
    "paragraph is a locally constructed stand-in for machine-generated text; no AI "
    "service was called. It is long enough to satisfy the fixture evidence floor and it "
    "is not a claim about any real system or person."
)


INTRO = "A short human-written introduction that is not the AI text. "


def main():
    typed_record = Builder("retype-ai", "keyboard").type(INTRO + AI_TEXT, seed=13).record()
    typed = make(name="retype-ai", record=typed_record)

    typed_case = {
        "case": "human-retypes-ai-text-no-paste",
        "trace": trace_facts(typed_record),
        "same_final_text_as_typed": True,
        "computed_internal_result": typed["computed"].get("result"),
        "python": [py_verify(typed), py_verify(typed, recompute=True)],
        "javascript_attested": js_verify(typed),
    }

    paste_builder = Builder("pasted-ai", "keyboard").type(INTRO, seed=1)
    paste_builder.splice(len(paste_builder.text), len(paste_builder.text), AI_TEXT, source="paste")
    paste_record = paste_builder.record()
    paste_case = {
        "case": "same-final-text-explicit-paste-control",
        "trace": trace_facts(paste_record),
        "same_final_text_as_typed": paste_record["final_text"] == typed_record["final_text"],
    }
    try:
        pasted = make(name="pasted-ai", record=paste_record)
        paste_case["computed_internal_result"] = pasted["computed"].get("result")
        paste_case["python"] = [py_verify(pasted), py_verify(pasted, recompute=True)]
        paste_case["javascript_attested"] = js_verify(pasted)
    except BaseException as exc:
        paste_case["issuance_rejected"] = f"{type(exc).__name__}: {exc}"
        paste_case["python"] = []
        paste_case["javascript_attested"] = None

    emit(
        {
            "attack": "human retyping AI-generated text",
            "description": (
                "The same machine-style paragraph is typed character by character with "
                "no paste transaction, then separately inserted as an explicit paste. "
                "The typed trace is fabricated by the fixture Builder; it models a "
                "human at a keyboard reading another screen."
            ),
            "ai_text_origin": "locally written stand-in; no AI service called",
            "expected_in_principle": (
                "Retyping is not detectable from the HWP v0 observation alphabet: no "
                "screen, clipboard, gaze or external-source inventory is captured. "
                "Direct insertions remain candidates even when informed by earlier "
                "external ideas (SPECIFICATION.md section 2; ALGORITHM.md "
                "'Deterministic reconstruction'; AUDIT.md 'Deliberate scope decisions'). "
                "An explicit paste is visible and is not supported."
            ),
            "typed": typed_case,
            "paste_control": paste_case,
            "notes": (
                "The typed and pasted cases have the same final text. The only "
                "difference HWP can see is the transaction source. Retyping removes "
                "the evidence that would have made the paste unsupported."
            ),
        }
    )


if __name__ == "__main__":
    main()
