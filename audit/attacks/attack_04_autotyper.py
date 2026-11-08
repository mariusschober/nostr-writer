#!/usr/bin/env python3
"""Attack 04: an autotyper / HID device driven by software.

Every character is emitted by a program at a fixed cadence.  The capture client
sees ordinary keyboard events and native deliveries, so it labels the source
"device" and signs the capture.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import TEXT, emit, js_verify, make, make_fixed_cadence, py_verify, trace_facts  # noqa: E402


def main():
    record = make_fixed_cadence(TEXT * 2, did="autotyper", delay_us=2_000)
    fixture = make(name="autotyper", record=record)
    facts = trace_facts(record)
    facts["schedule"] = {
        "kind": "fixed 2 ms request delay; keyboard press/release adds 30 ms dwell",
        "effective_inter_key_us": 32_000,
        "human_observation": False,
        "device_label_seen_by_client": "device",
    }
    emit(
        {
            "attack": "autotyper or HID device driven by software",
            "description": (
                "A program emits a fixed 31-32 ms keystroke cadence for every "
                "character. The client records press/release observations, native "
                "deliveries and mutations, labels the source 'device', and signs the "
                "capture. No hand touches the device."
            ),
            "expected_in_principle": (
                "No, if the device is observation-equivalent to a keyboard. HWP v0 "
                "has no hardware provenance; source labels are capture classifications, "
                "not writer declarations, and faithful-device-origin/native-delivery-"
                "binding are assumptions (SPECIFICATION.md sections 3, 5, 6; "
                "algorithm/v0_3/TELEMETRY.md; THREAT-MODEL.md row 'Fabrication of "
                "delivery fields or timestamps')."
            ),
            "trace": facts,
            "computed_internal_result": fixture["computed"].get("result"),
            "python": [py_verify(fixture), py_verify(fixture, recompute=True)],
            "javascript_attested": js_verify(fixture),
            "notes": (
                "A trained timing model might flag this fixed cadence. That is an "
                "empirical detector question, not a protocol guarantee. The frozen "
                "fixture model accepts it, and no production model is shipped."
            ),
        }
    )


if __name__ == "__main__":
    main()
