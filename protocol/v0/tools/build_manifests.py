"""Maintainer-only build step before freeze; never called by a verifier."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from hwp0 import core as c
files=[{'path':p.relative_to(ROOT).as_posix(),'ref':c.ref(p.read_bytes())} for p in sorted((ROOT/'hwp0').rglob('*.py'))]
program=c.encode({'v':c.VERSION,'type':'program','algorithm':'hwp-a/v0','files':files})
(ROOT/'manifests/program.cbor.hex').write_text(program.hex()+'\n')
artifacts={'program':c.ref(program)}
for name,path in [('algorithm_spec','docs/ALGORITHM.md'),('evidence_adapter','docs/BINDING.md'),('output_contract','docs/OUTPUT.md')]:artifacts[name]=c.ref((ROOT/path).read_bytes())
for path in ['SPECIFICATION.md','schema.cddl','docs/FEATURE_NAMES.json','docs/THREAT-MODEL.md','docs/CONFORMANCE.md','telemetry.schema.json','baseline/A03-SPECIFICATION.md','baseline/A03-FEATURES.md','baseline/A03-TELEMETRY.md','baseline/A03-DATASET_PROTOCOL.md','baseline/A03-THEORY.md','baseline/C1-SPECIFICATION.md']:
 artifacts[path]=c.ref((ROOT/path).read_bytes())
proto=c.encode({'v':c.VERSION,'type':'protocol-definition','name':'Human Writing Protocol','revision':'0.0.0','artifacts':artifacts})
(ROOT/'manifests/protocol.cbor.hex').write_text(proto.hex()+'\n')
print(c.digest(proto).hex())
