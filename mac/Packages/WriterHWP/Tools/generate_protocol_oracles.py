#!/usr/bin/env python3
"""Full results from immutable public vectors; output contains no real user evidence."""
from pathlib import Path
import hashlib,json,subprocess,sys
sys.dont_write_bytecode=True
root=Path(__file__).resolve().parents[4]/'protocol/v0'
subprocess.run([sys.executable,str(root/'tools/check_freeze.py')],check=True)
sys.path.insert(0,str(root))
from hwp0 import core,protocol,disclosure
source=(root/'vectors/interchange.json').read_bytes();vectors=json.loads(source)
objects={k:bytes.fromhex(v) for k,v in vectors['objects'].items()}
rows=[]
for case in vectors['cases']:
    bundle,document,policy=(objects[case[k]] for k in ('bundle','document','policy'))
    pin=bytes.fromhex(case['policy_pin']);private=core.decode(objects[case['disclosures']])
    row={'id':case['id']}
    for name,audit,opened in [('public',False,private),('recomputation',True,private),('no_witness',False,None)]:
        row[name]=core.encode(protocol.verify(bundle,document,policy,pin,opened,audit)).hex()
    st,ref=core.Store.unpack(bundle);statement=st.obj(ref)['statement']
    try:
        value,lineage=protocol.evaluate_statement(st,statement,policy,pin,private)
        row['computed']=core.encode(value).hex();row['lineage']=lineage.hex()
    except (core.Reject,ValueError,TypeError,KeyError,IndexError,OverflowError) as error:
        row['evaluation_reject']=str(error)
    rows.append(row)
out={'vector_sha256':hashlib.sha256(source).hexdigest(),'source_sha256':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [root/'hwp0/core.py',root/'hwp0/protocol.py',root/'hwp0/bridge.py']},'cases':rows}
p=Path(__file__).resolve().parents[1]/'Tests/WriterHWPTests/Fixtures/protocol-oracle.json'
p.write_text(json.dumps(out,sort_keys=True,separators=(',',':'))+'\n')
print(len(rows),'complete cases;',sum('computed' in r for r in rows),'successful producer evaluations;',p.stat().st_size,'bytes')
