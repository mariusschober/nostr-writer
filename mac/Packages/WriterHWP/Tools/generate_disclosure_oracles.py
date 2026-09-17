#!/usr/bin/env python3
"""Read the frozen reference transport; write ONLY this package's oracle fixture.

The immutable protocol is never modified. This script verifies the freeze, then
imports the frozen `hwp0` transport/commitment code and writes a native-only
expectation file.

Run with the repository oracle environment so the frozen reference imports its
actual pinned dependencies. No dependency or protocol code is substituted.
"""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True

parser = argparse.ArgumentParser()
parser.add_argument("--protocol", type=Path,
                    default=Path(__file__).resolve().parents[4] / "protocol/v0")
args = parser.parse_args()
root = args.protocol.resolve()


subprocess.run([sys.executable, str(root / "tools/check_freeze.py")], check=True)
sys.path.insert(0, str(root))
from hwp0 import core as c  # noqa: E402
from hwp0 import disclosure as d  # noqa: E402


def digest(label: str) -> bytes:
    return hashlib.sha256(label.encode()).digest()


def event_bytes(value: dict) -> bytes:
    return c.encode(value)


def ref(sha256: bytes, size: int) -> dict:
    return {"sha256": sha256, "size": size}


def ladder_ref(entry: dict) -> dict:
    """The vector file stores digests as hex; the frozen API takes raw bytes."""
    return ref(bytes.fromhex(entry["sha256"]), entry["size"])


def hexify(value: dict) -> dict:
    """Bytes -> hex, in exactly the shape the native tests rebuild."""
    return {
        "logs": [{
            "capture": {"sha256_hex": log["capture"]["sha256"].hex(), "size": log["capture"]["size"]},
            "openings": [{"index": o["index"], "salt_hex": o["salt"].hex(), "event_hex": o["event"].hex()}
                         for o in log["openings"]],
        } for log in value["logs"]],
        "lineage_salts": [{"statement": {"sha256_hex": s["statement"]["sha256"].hex(),
                                         "size": s["statement"]["size"]},
                           "salt_hex": s["salt"].hex()} for s in value["lineage_salts"]],
    }


def signature(value: dict) -> list:
    """Order-insensitive identity, since `unpack` sorts logs and lineage salts."""
    return sorted(
        (log["capture"]["sha256"],
         tuple((o["index"], o["salt"], o["event"]) for o in log["openings"]))
        for log in value["logs"]) + sorted(
        (s["statement"]["sha256"], s["salt"]) for s in value["lineage_salts"])


interchange = (root / "vectors/interchange.json").read_bytes()
ladder = json.loads(interchange)["ladder"]

# 1. Two sessions and one lineage salt, with mixed event shapes and exact UTF-8.
small = {
    "logs": [
        {"capture": ref(digest("small-capture-a"), 123), "openings": [
            {"index": 0, "salt": digest("small-salt-a0"),
             "event": event_bytes({"kind": "header", "session": digest("small-session-a")})},
            {"index": 1, "salt": digest("small-salt-a1"),
             "event": event_bytes({"kind": "delta", "text": "e\u0301\r\n"})},
            {"index": 2, "salt": digest("small-salt-a2"),
             "event": event_bytes({"kind": "end", "count": 3})},
        ]},
        {"capture": ref(digest("small-capture-b"), 45), "openings": [
            {"index": 0, "salt": digest("small-salt-b0"), "event": event_bytes({"kind": "header"})},
            {"index": 1, "salt": digest("small-salt-b1"), "event": event_bytes({"kind": "end"})},
        ]},
    ],
    "lineage_salts": [{"statement": ref(digest("small-statement"), 9),
                       "salt": digest("small-lineage-salt")}],
}

# 2. 300 openings straddle the 256-opening transport block boundary.
chunked = {
    "logs": [{"capture": ref(digest("chunked-capture"), 4096),
              "openings": [{"index": n, "salt": digest(f"chunked-salt:{n}"), "event": event_bytes({"i": n})}
                           for n in range(300)]}],
    "lineage_salts": [],
}

# 3. The frozen salted capture's real event/salt bytes under the real capture-end ref.
# The vector stores a proof subset (indices 0,1,2,1249), while the transport requires
# consecutive openings; the transport is content-agnostic, so the frozen material is
# carried at consecutive positions and the original indices are recorded.
selected = ladder["selected_openings"]
capture = {
    "logs": [{"capture": ladder_ref(ladder["end"]),
              "openings": [{"index": position, "salt": bytes.fromhex(o["salt_hex"]),
                            "event": bytes.fromhex(o["event_hex"])}
                           for position, o in enumerate(selected)]}],
    "lineage_salts": [],
}

cases = {"small": small, "chunked": chunked, "capture": capture}

# 6. Two lineage salts authored in descending digest order, so `pack` must sort them.
statement_high = digest("salts-statement-high")
statement_low = digest("salts-statement-low")
if statement_low > statement_high:
    statement_high, statement_low = statement_low, statement_high
salts_case = {
    "logs": [{"capture": ref(digest("salts-capture"), 64), "openings": [
        {"index": 0, "salt": digest("salts-salt-0"), "event": event_bytes({"kind": "header"})},
        {"index": 1, "salt": digest("salts-salt-1"), "event": event_bytes({"kind": "end"})},
    ]}],
    "lineage_salts": [{"statement": ref(statement_high, 11), "salt": digest("salts-lineage-high")},
                      {"statement": ref(statement_low, 12), "salt": digest("salts-lineage-low")}],
}
cases["salts"] = salts_case

fixture = {
    "source_sha256": {
        "disclosure.py": hashlib.sha256((root / "hwp0/disclosure.py").read_bytes()).hexdigest(),
        "core.py": hashlib.sha256((root / "hwp0/core.py").read_bytes()).hexdigest(),
        "interchange.json": hashlib.sha256(interchange).hexdigest(),
    },
}
for name, case in cases.items():
    raw = d.pack(case)
    opened = d.unpack(raw)
    assert d.pack(opened) == raw, f"frozen {name} repack mismatch"
    assert signature(opened) == signature(case), f"frozen {name} unpack mismatch"
    # `value` is the canonical reopened form; `input` keeps the authored order so
    # the native port must reproduce the frozen sort as well as the bytes.
    fixture[name] = {"value": hexify(opened), "input": hexify(case), "pack_hex": raw.hex(),
                     "opening_counts": [len(log["openings"]) for log in case["logs"]]}
fixture["capture"]["source_indices"] = [o["index"] for o in selected]
fixture["capture"]["source_capture"] = ladder_ref(ladder["end"])["sha256"].hex()

# Negative oracle: reversing the two lineage salts produces a bundle the frozen
# implementation rejects as non-canonical (`unpack` rebuilds it from `pack`).
salts_raw = bytes.fromhex(fixture["salts"]["pack_hex"])
salts_store, salts_root = c.Store.unpack(salts_raw)
salts_manifest = salts_store.obj(salts_root)
salts_manifest["lineage_salts"] = list(reversed(salts_manifest["lineage_salts"]))
reduced = c.Store()
reduced.add(salts_store.get(salts_manifest["logs"][0]["parts"][0]))
reduced_root = reduced.put(salts_manifest)
reordered_raw = reduced.pack(reduced_root)
try:
    d.unpack(reordered_raw)
    raise AssertionError("frozen unpack accepted reversed lineage salts")
except c.Reject as rejection:
    assert str(rejection) == "private-disclosure-noncanonical", str(rejection)
fixture["salts"]["reordered_pack_hex"] = reordered_raw.hex()

# 5. The frozen ladder's complete disclosure: 1250 real openings across 5 blocks.
# The vector stores the raw ABI map, so the transport bytes come from `pack` itself.
objects = json.loads(interchange)["objects"]
full_abi = c.decode(bytes.fromhex(objects[ladder["disclosures"]]))
full_packed = d.pack(full_abi)
full_openings = full_abi["logs"][0]["openings"]
assert d.pack(d.unpack(full_packed)) == full_packed, "frozen full repack mismatch"
ladder_start = ladder_ref(ladder["start"])
full_events = c.open_transcript(ladder_start, ladder["count"], bytes.fromhex(ladder["root_hex"]),
                                full_openings)
assert len(full_events) == ladder["count"], "frozen full opening count mismatch"
assert full_events[0]["kind"] == "header" and full_events[-1]["kind"] == "end", "frozen full terminals"
fixture["full"] = {
    "pack_hex": full_packed.hex(),
    "start": {"sha256_hex": ladder_start["sha256"].hex(), "size": ladder_start["size"]},
    "count": ladder["count"],
    "root_hex": ladder["root_hex"],
    "capture_hex": full_abi["logs"][0]["capture"]["sha256"].hex(),
    "opening_counts": [len(log["openings"]) for log in full_abi["logs"]],
    "blocks": (len(full_openings) + 255) // 256,
    "lineage_salts": len(full_abi["lineage_salts"]),
}

# 4. Frozen commitment openings for a complete header..end transcript.
transcript_events = [{"kind": "header", "session": digest("transcript-session")},
                     {"kind": "delta", "text": "first"},
                     {"kind": "delta", "text": "second"},
                     {"kind": "end", "count": 4}]
transcript_salts = [digest(f"transcript-salt:{n}") for n in range(len(transcript_events))]
transcript_start = ladder_ref(ladder["start"])
transcript_root, transcript_openings = c.commit_events(transcript_start, transcript_events, transcript_salts)
fixture["transcript"] = {
    "start": {"sha256_hex": transcript_start["sha256"].hex(), "size": transcript_start["size"]},
    "events_hex": [c.encode(event).hex() for event in transcript_events],
    "salts_hex": [salt.hex() for salt in transcript_salts],
    "root_hex": transcript_root.hex(),
    "openings": [{"index": o["index"], "salt_hex": o["salt"].hex(), "event_hex": o["event"].hex()}
                 for o in transcript_openings],
}

output = Path(__file__).resolve().parents[1] / "Tests/WriterHWPTests/Fixtures"
output.mkdir(parents=True, exist_ok=True)
(output / "disclosure-oracle.json").write_text(json.dumps(fixture, separators=(",", ":")) + "\n")
print(json.dumps({"small_bytes": len(fixture["small"]["pack_hex"]) // 2,
                  "chunked_bytes": len(fixture["chunked"]["pack_hex"]) // 2,
                  "capture_bytes": len(fixture["capture"]["pack_hex"]) // 2,
                  "chunked_openings": fixture["chunked"]["opening_counts"],
                  "fixture_bytes": (output / "disclosure-oracle.json").stat().st_size}))
