#!/usr/bin/env python3
"""Conditional algorithm fixtures; no empirical or production admission evidence."""
import argparse,copy,dataclasses,hashlib,json,subprocess,sys
from pathlib import Path
sys.dont_write_bytecode=True
parser=argparse.ArgumentParser();parser.add_argument('--protocol',type=Path,default=Path(__file__).resolve().parents[4]/'protocol/v0');args=parser.parse_args();root=args.protocol.resolve()
subprocess.run([sys.executable,str(root/'tools/check_freeze.py')],check=True);sys.path.insert(0,str(root))
from hwp0 import core
from hwp0.algorithm.fixtures import Builder,TEXT,permissive_fixture_model
from hwp0.algorithm.verify import TrustedInputs,verify,snapshot
rows=[]
def add(name,bundle,claim='fresh-composition',excluded=None,threshold=0,context_change=None,model_change=None):
    model=permissive_fixture_model(bundle);model['purpose']='validated-release'
    if model_change:model_change(model)
    context=TrustedInputs(admissible_documents=frozenset(d['id'] for d in bundle['documents']),approved_release=True,approved_threshold=threshold,allowed_domains=frozenset(model['domains']),document_snapshots=frozenset((d['id'],snapshot(d)) for d in bundle['documents']),fresh_documents=frozenset(d['id'] for d in bundle['documents']),model_snapshot=snapshot(model),approved_claim=claim)
    if context_change:context=context_change(context)
    result=verify(bundle,model,threshold,context,excluded,claim)
    rows.append({'id':name,'bundle':core.encode(bundle).hex(),'model':core.encode(model).hex(),'threshold':threshold,'claim':claim,'excluded':core.encode(excluded).hex(),'context':{'admissible':sorted(context.admissible_documents),'release':context.approved_release,'threshold':context.approved_threshold,'domains':sorted(context.allowed_domains),'documents':[{'id':i,'snapshot':s} for i,s in sorted(context.document_snapshots)],'fresh':sorted(context.fresh_documents),'model':context.model_snapshot,'claim':context.approved_claim},'expected':core.encode(result).hex()})
for profile in ['keyboard','touch-tap','ime','gesture']:add('conditional-'+profile,Builder(profile=profile).type(TEXT,seed=7).bundle())
base=Builder().type(TEXT,seed=19).bundle()
add('empty-independent-context',base,context_change=lambda c:TrustedInputs())
add('unapproved-release',base,context_change=lambda c:dataclasses.replace(c,approved_release=False))
add('wrong-threshold-pin',base,context_change=lambda c:dataclasses.replace(c,approved_threshold=1))
add('wrong-model-pin',base,context_change=lambda c:dataclasses.replace(c,model_snapshot='different model'))
add('wrong-claim-pin',base,context_change=lambda c:dataclasses.replace(c,approved_claim='wording-origin'))
add('wrong-record-pin',base,context_change=lambda c:dataclasses.replace(c,document_snapshots=frozenset()))
add('not-freshly-admitted',base,context_change=lambda c:dataclasses.replace(c,fresh_documents=frozenset()))
add('unsupported-domain',base,context_change=lambda c:dataclasses.replace(c,allowed_domains=frozenset()))
add('unapproved-model-purpose',base,model_change=lambda m:m.update(purpose='fixture'))
add('below-threshold',base,threshold=1)
add('invalid-threshold',base,threshold=-10**9)
add('invalid-claim',base,claim='invented')
add('short-neighbourhood',Builder().type('short').bundle())
add('white-space-vacuity',Builder().type(' '*80).bundle())
add('same-record-source-veto',Builder().splice(0,0,TEXT,'paste').splice(0,len(TEXT),'','unknown').type(TEXT,seed=3).bundle())
add('gap',Builder().type(TEXT).gap().type(TEXT).bundle())
prefix='Quoted source. ';quoted=Builder().splice(0,0,prefix,'paste').type(TEXT,seed=5).bundle()
add('explicit-excluded-quote',quoted,excluded=[{'start':0,'end':len(prefix.encode()),'source':'quoted'}])
add('malformed-exclusion-object',base,excluded={})
add('overlapping-exclusions',base,excluded=[{'start':0,'end':5,'source':'a'},{'start':4,'end':6,'source':'b'}])
add('nontext-exclusion-source',base,excluded=[{'start':0,'end':5,'source':7}])
add('empty-exclusion-source',base,excluded=[{'start':0,'end':5,'source':''}])
parent=Builder('parent').type(TEXT,seed=1).record();child=Builder('child').control('copy',from_doc='parent',start=0,end=len(TEXT),to=0,parent_text=TEXT).type(TEXT,seed=2)
add('inherited-not-fresh',child.bundle([parent]));add('conditional-wording-origin',child.bundle([parent]),claim='wording-origin')
b=Builder().type('é'+TEXT,seed=6).bundle();add('split-unicode-scope',b,excluded=[{'start':1,'end':2,'source':'quote'}])
json_values=['"\\\b\f\n\r\t\x00\x1f\x7f\u0085é\u0301☕😀\ufeff', {'é':1,'e\u0301':2,'x':False,'null':None}, {10:'ten',2:'two',-3:'negative'},[0,-1,2**64-1,True,None]]
json_rows=[{'value':core.encode(x).hex(),'snapshot':snapshot(x)} for x in json_values]
blobs={};snapshots={}
for row in rows:
    for field in ['bundle','model']:
        raw=bytes.fromhex(row[field]);key=hashlib.sha256(raw).hexdigest();blobs[key]=row[field];row[field]=key
    for pin in row['context']['documents']:
        value=pin['snapshot'];key=hashlib.sha256(value.encode()).hexdigest();snapshots[key]=value;pin['snapshot']=key
    value=row['context']['model']
    if value is not None:
        key=hashlib.sha256(value.encode()).hexdigest();snapshots[key]=value;row['context']['model']=key
result={'source_sha256':hashlib.sha256((root/'hwp0/algorithm/verify.py').read_bytes()).hexdigest(),'cases':rows,'json':json_rows,'blobs':blobs,'snapshots':snapshots}
p=Path(__file__).resolve().parents[1]/'Tests/WriterHWPTests/Fixtures/assessment-oracle.json';p.write_text(json.dumps(result,sort_keys=True,separators=(',',':'))+'\n');print(f'{len(rows)} full conditional assessments; {len(json_rows)} JSON snapshots; {p.stat().st_size} bytes')
