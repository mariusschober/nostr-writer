"""Offline HWP-v0 verifier; no external fetching, execution or implicit trust."""
import argparse,json
from pathlib import Path
from .core import MAX_BYTES,diagnostic_json
from .protocol import verify
from .disclosure import unpack

def read(path):
    p=Path(path)
    if p.stat().st_size>MAX_BYTES:raise ValueError('file-limit')
    return p.read_bytes()

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('proof');ap.add_argument('document');ap.add_argument('--policy',required=True);ap.add_argument('--policy-pin',required=True)
    ap.add_argument('--disclosure');ap.add_argument('--recompute',action='store_true');a=ap.parse_args()
    try:
        d=unpack(read(a.disclosure)) if a.disclosure else None
        result=verify(read(a.proof),read(a.document),read(a.policy),bytes.fromhex(a.policy_pin),d,a.recompute)
    except (ValueError,OSError):result={'protocol':'hwp/0','status':'NO-VALID-HWP','outcome':'NOT PROVABLE','reason':'input-error','authorship_inference':None}
    print(json.dumps(diagnostic_json(result),sort_keys=True,ensure_ascii=True,indent=2))
    raise SystemExit(0 if result['status']=='VALID-HWP' else 2 if result['status']=='TEST-ONLY' else 1)
if __name__=='__main__':main()
