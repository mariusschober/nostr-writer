"""Command-line access to the algorithm. No capture, UI, networking, or signing."""
import argparse
import json
from pathlib import Path
from .verify import verify,score,TrustedInputs
from .model import fit
from .dataset import extract_dataset
from .calibration import calibrate

def pairs(p):
    out={}
    for k,v in p:
        if k in out: raise ValueError('DUPLICATE_JSON_KEY')
        out[k]=v
    return out

def load(path):
    raw=Path(path).read_bytes()
    if len(raw)>100_000_000: raise ValueError('FILE_RESOURCE_LIMIT')
    return json.loads(raw.decode('utf-8'),object_pairs_hook=pairs,parse_constant=lambda x:(_ for _ in ()).throw(ValueError('NONFINITE_JSON')))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    subs=parser.add_subparsers(dest='command',required=True)
    p=subs.add_parser('verify'); p.add_argument('trace'); p.add_argument('--model'); p.add_argument('--threshold',type=int,default=0)
    p=subs.add_parser('extract'); p.add_argument('cases')
    p=subs.add_parser('fit'); p.add_argument('rows')
    p=subs.add_parser('calibrate'); p.add_argument('request')
    parser.add_argument('--output')
    args=parser.parse_args()
    if args.command=='verify':
        # There is intentionally no --trust-me flag. This CLI cannot authenticate
        # capture or approve a release by reading an author-supplied JSON file.
        result=verify(load(args.trace),load(args.model) if args.model else None,args.threshold)
    elif args.command=='extract': result=extract_dataset(load(args.cases))
    elif args.command=='fit': result=fit(load(args.rows))
    else:
        request=load(args.request)
        result=calibrate(**request)
    text=json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n'
    if args.output: Path(args.output).write_text(text,encoding='utf-8')
    else: print(text,end='')

if __name__=='__main__': main()
