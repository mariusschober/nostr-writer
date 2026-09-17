"""Validate the immutable distribution inventory without changing it."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
def main():
    raw=(ROOT/'FREEZE.json').read_bytes();expected=(ROOT/'FREEZE.sha256').read_text().split()[0]
    if hashlib.sha256(raw).hexdigest()!=expected:raise ValueError('freeze-inventory-digest')
    manifest=json.loads(raw);files=manifest['files'];listed=set();errors=[]
    for f in files:
        name=f['path'];p=Path(name)
        if p.is_absolute() or '..' in p.parts:raise ValueError('unsafe-inventory-path')
        listed.add(name)
        path=ROOT/p
        if not path.is_file():errors.append('missing:'+name);continue
        b=path.read_bytes()
        if len(b)!=f['size'] or hashlib.sha256(b).hexdigest()!=f['sha256']:errors.append('changed:'+name)
    present={p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.pyc' and p.name not in ('FREEZE.json','FREEZE.sha256')}
    errors+=['unlisted:'+n for n in sorted(present-listed)]
    if errors:print(json.dumps({'status':'FAIL','errors':errors},indent=2));return 1
    print(json.dumps({'status':'PASS','files':len(files),'protocol_definition_sha256':manifest['protocol_definition_sha256'],'freeze_sha256':expected},indent=2));return 0
if __name__=='__main__':
    try:raise SystemExit(main())
    except (OSError,ValueError,KeyError) as e:print(json.dumps({'status':'FAIL','reason':str(e)}));raise SystemExit(1)
