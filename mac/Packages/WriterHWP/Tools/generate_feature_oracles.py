#!/usr/bin/env python3
"""Synthetic feature vectors from the untouched frozen reference implementation."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True
parser=argparse.ArgumentParser();parser.add_argument('--protocol',type=Path,default=Path(__file__).resolve().parents[4]/'protocol/v0');args=parser.parse_args();root=args.protocol.resolve()
subprocess.run([sys.executable,str(root/'tools/check_freeze.py')],check=True)
sys.path.insert(0,str(root))
from hwp0 import core
from hwp0.algorithm.fixtures import Builder,TEXT
from hwp0.algorithm.replay import replay,make_units
from hwp0.algorithm.features import extract,adequate,FEATURE_NAMES
cases=[]
for profile in ['keyboard','touch-tap','ime','gesture']:
    cases.append((profile,Builder(profile=profile).type(TEXT*2,seed=42).bundle()))
b=Builder().type(TEXT*2,seed=13)
b.control('navigate',start=5,end=5).splice(2,5,'xyz').control('undo').control('redo')
b.control('copy',from_doc='d',start=20,end=90,to=len(b.text)).control('move',start=10,end=25,to=150)
b.splice(40,44,'next').splice(140,144,'next').splice(140,144,'back').pause().type(' fresh later ideas',seed=8)
cases.append(('edits-moves-revisions',b.bundle()))
b=Builder().type(TEXT,seed=37).gap().type(TEXT,seed=11);b.splice(15,20,'wrong','spelling');b.splice(200,200,'copied text','paste')
cases.append(('gaps-spelling-paste',b.bundle()))
b=Builder().type('cafe\u0301 \ufeff☕\r\n'+TEXT,seed=88).splice(0,5,'café','spelling').type('追加',seed=2)
cases.append(('unicode-exact',b.bundle()))
parent=Builder(did='é').type(TEXT,seed=1).record();child=Builder(did='e\u0301').control('copy',from_doc='é',start=0,end=100,to=0,parent_text=TEXT).type(TEXT,seed=2)
cases.append(('byte-distinct-ancestor',child.bundle([parent])))
b=Builder().splice(0,0,TEXT,'paste').splice(0,len(TEXT),'','unknown').type(TEXT,seed=3)
cases.append(('observed-source-reuse',b.bundle()))
rows=[]
for name,bundle in cases:
    c=replay(bundle);units=[]
    for did in c.documents:
        uu,_=make_units(c,did)
        for u in uu:
            enough=adequate(c,u);values=extract(c,u)
            assert list(values)==list(FEATURE_NAMES)
            units.append({'id':u.uid,'adequate':enough,'values':list(values.values())})
    rows.append({'id':name,'bundle':core.encode(bundle).hex(),'units':units})
output={'source_sha256':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [root/'hwp0/algorithm/replay.py',root/'hwp0/algorithm/features.py']},'cases':rows}
p=Path(__file__).resolve().parents[1]/'Tests/WriterHWPTests/Fixtures/feature-oracle.json';p.write_text(json.dumps(output,ensure_ascii=True,sort_keys=True,separators=(',',':'))+'\n');print(f'{len(rows)} histories; {sum(len(r["units"]) for r in rows)} complete vectors; {p.stat().st_size} bytes')
