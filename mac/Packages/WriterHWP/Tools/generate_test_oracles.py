#!/usr/bin/env python3
"""Read frozen reference code; write ONLY this native test target's oracle fixtures."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
parser = argparse.ArgumentParser()
parser.add_argument("--protocol", type=Path, default=Path(__file__).resolve().parents[4] / "protocol/v0")
args = parser.parse_args()
root = args.protocol.resolve()
subprocess.run([sys.executable, str(root / "tools/check_freeze.py")], check=True)
sys.path.insert(0, str(root))
from hwp0 import core  # noqa: E402

raw = (root / "vectors/interchange.json").read_bytes()
vector = json.loads(raw)
output = Path(__file__).resolve().parents[1] / "Tests/WriterHWPTests/Fixtures"
output.mkdir(parents=True, exist_ok=True)
validity = {}
signatures = {}
for identity, encoded in vector["objects"].items():
    data = bytes.fromhex(encoded)
    try:
        object_value = core.decode(data)
        validity[identity] = True
    except core.Reject:
        validity[identity] = False
        continue
    if not isinstance(object_value, dict) or object_value.get("type") != "bundle":
        continue
    store, _ = core.Store.unpack(data)
    for key_id, candidate in store.objects.items():
        try:
            envelope = core.decode(candidate)
            if type(envelope) is not core.Tag:
                continue
            headers = core.decode(envelope.value[0])
            key = store.objects[headers[4]]
            core.verify_signature(candidate, key)
        except (core.Reject, KeyError):
            continue
        signatures[key_id.hex()] = {"signature": candidate.hex(), "key": key.hex()}
expectations = {"source_sha256": hashlib.sha256(raw).hexdigest(), "objects": validity}
seed = hashlib.sha256(b"native-roundtrip-fixture").digest()
payload = {"v": "hwp/0", "type": "synthetic-only", "text": "e\u0301\r\n"}
points = [hashlib.sha256(f"point-{n}".encode()).digest() for n in range(24)]
points += [n.to_bytes(32, "little") for n in [0, 1, 2, 2**255-19, 2**255-1, 2**255+1]]
cose = {
    "pairs": list(signatures.values()),
    "points": [{"hex": point.hex(), "valid": core.valid_point(point)} for point in points],
    "seed": seed.hex(), "payload": core.encode(payload).hex(),
    "key": core.key_bytes(core.public_key(seed)).hex(), "signature": core.sign(payload, seed).hex(),
}
merkle = dict(vector["merkle"])
ladder = vector["ladder"]
merkle["capture"] = {"start_digest": ladder["start"]["sha256"], "count": ladder["count"],
                     "root_hex": ladder["root_hex"], "openings": ladder["selected_openings"]}
for name, value in [("cbor-expectations", expectations), ("cose-oracle", cose), ("merkle-oracle", merkle)]:
    (output / f"{name}.json").write_text(json.dumps(value, separators=(",", ":")) + "\n")
print(f"Wrote native-only test expectations: {len(validity)} objects, {len(signatures)} signatures.")
