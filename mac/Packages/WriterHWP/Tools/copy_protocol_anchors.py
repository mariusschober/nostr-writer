#!/usr/bin/env python3
"""Copy immutable public interpretation anchors; never execute or ship fixture authority."""
from pathlib import Path
import hashlib, subprocess, sys
sys.dont_write_bytecode = True
root = Path(__file__).resolve().parents[4] / 'protocol/v0'
subprocess.run([sys.executable, str(root/'tools/check_freeze.py')], check=True)
out = Path(__file__).resolve().parents[1]/'Sources/WriterHWP/ProtocolAnchors'
out.mkdir(exist_ok=True)
for name in ('protocol', 'program', 'production-default'):
    raw = bytes.fromhex((root/f'manifests/{name}.cbor.hex').read_text())
    (out/f'{name}.cbor').write_bytes(raw)
    print(name, len(raw), hashlib.sha256(raw).hexdigest())
for source, target in [('ALGORITHM.md','algorithm-spec.md'), ('BINDING.md','evidence-adapter.md'), ('OUTPUT.md','output-contract.md')]:
    raw = (root/'docs'/source).read_bytes(); (out/target).write_bytes(raw)
    print(target, len(raw), hashlib.sha256(raw).hexdigest())
