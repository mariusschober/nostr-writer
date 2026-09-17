#!/usr/bin/env python3
"""Read-only frozen computation; outputs stay in native synthetic test resources."""
import argparse, copy, hashlib, json, random, subprocess, sys
from pathlib import Path
sys.dont_write_bytecode = True
parser=argparse.ArgumentParser();parser.add_argument('--protocol',type=Path,default=Path(__file__).resolve().parents[4]/'protocol/v0');args=parser.parse_args();root=args.protocol.resolve()
subprocess.run([sys.executable,str(root/'tools/check_freeze.py')],check=True)
sys.path.insert(0,str(root))
from hwp0 import core
from hwp0.algorithm import features as f, model as m
rng=random.Random(1478);names=list(f.FEATURE_NAMES);n=len(names);domain='keyboard|fixture-path/keyboard|en|birth'
def branch(j):
    return {'feature':j%n,'threshold':rng.randint(-10000,10000),'left':{'feature':(j+1)%n,'threshold':0,'left':{'value':rng.randint(-1250,1250)},'right':{'value':rng.randint(-1250,1250)}},'right':{'value':rng.randint(-1250,1250)}}
a={'heads':{h:[branch(i*11+z*7) for i in range(32)] for z,h in enumerate(m.HEADS)},'scales':[rng.randint(500,20000) for _ in range(n)],'prototypes':[[rng.randint(-10000,10000) for _ in range(n)] for _ in range(8)],'support_calibration':[rng.randint(0,60000) for _ in range(99)]}
base={'version':'hwp-a-model/v0','purpose':'fixture','features':names,'domains':{domain:a}}
def check(label,value):
    try:m.validate_model(value);reason=None
    except Exception as e:reason=str(e)
    return {'id':label,'model':core.encode(value).hex(),'reason':reason}
rows=[check('valid-all-branches',base)]
mutations=[('version',lambda x:x.update(version='obsolete')),('purpose',lambda x:x.update(purpose='self-approved')),('feature-order',lambda x:x['features'].reverse()),('missing-head',lambda x:x['domains'][domain]['heads'].pop('mixed')),('tree-count',lambda x:x['domains'][domain]['heads']['automation'].pop()),('leaf-extra',lambda x:x['domains'][domain]['heads']['mixed'].__setitem__(31,{'value':0,'surprise':True})),('hidden-invalid-leaf',lambda x:x['domains'][domain]['heads']['mixed'][0].__setitem__('right',{'value':1251})),('hidden-deep-tree',lambda x:x['domains'][domain]['heads']['mixed'][0]['left'].__setitem__('right',copy.deepcopy(a['heads']['mixed'][0]))),('feature-index',lambda x:x['domains'][domain]['heads']['mixed'][0].__setitem__('feature',179)),('boolean-feature',lambda x:x['domains'][domain]['heads']['mixed'][0].__setitem__('feature',False)),('tree-threshold',lambda x:x['domains'][domain]['heads']['mixed'][0].__setitem__('threshold',10001)),('scale-dimension',lambda x:x['domains'][domain]['scales'].pop()),('scale-zero',lambda x:x['domains'][domain]['scales'].__setitem__(0,0)),('no-prototypes',lambda x:x['domains'][domain].__setitem__('prototypes',[])),('prototype-number',lambda x:x['domains'][domain]['prototypes'][0].__setitem__(0,-10001)),('negative-calibration',lambda x:x['domains'][domain]['support_calibration'].__setitem__(0,-1)),('boolean-calibration',lambda x:x['domains'][domain]['support_calibration'].__setitem__(0,True)),('unknown-field',lambda x:x.update(extra=1)),('empty-domain',lambda x:x.__setitem__('domains',{})),('malformed-domain',lambda x:x.__setitem__('domains',{'keyboard|missing|en':a})),('unknown-profile',lambda x:x.__setitem__('domains',{'other|path|en|birth':a})),('empty-path',lambda x:x.__setitem__('domains',{'keyboard||en|birth':a}))]
for label,mutation in mutations:
    value=copy.deepcopy(base);mutation(value);rows.append(check(label,value))
evaluations=[]
for i in range(8):
    values=[rng.randint(-10000,10000) for _ in range(n)] if i else [0]*n
    score,supported,details=m.evaluate(dict(zip(names,values)),a,names)
    evaluations.append({'id':f'varied-{i}','model':None,'values':values,'score':score,'supported':supported,'details':core.encode(details).hex()})
for count,displaced in [(98,False),(99,False),(99,True),(100,True)]:
    value=copy.deepcopy(base);artifact=value['domains'][domain];artifact['prototypes']=[[0]*n];artifact['support_calibration']=[0]*count
    values=[1 if displaced else 0]*n;score,supported,details=m.evaluate(dict(zip(names,values)),artifact,names)
    evaluations.append({'id':f'support-{count}-{displaced}','model':core.encode(value).hex(),'values':values,'score':score,'supported':supported,'details':core.encode(details).hex()})
floors=[(a,b) for a in [-10**140-7,-7,0,7,10**140+7] for b in [-10**80-1,-3,3,10**80+1]]
ratios=[(n,d) for n,d in [(-1,3),(1,3),(-5,3),(7,0),(10**100,10**110),(-10**100,10**99)]]
correlations=[([2**53-1,0,2**53-2,1],[0,2**53-1,1,2**53-2]),([1,1,1],[1,2,3]),([1,2],[3,4]),([1,2,3,4],[4,8,12,16]),([3,-7,11,42],[100,2,-7,8])]
quantiles=[{'values':xx,'percent':p,'result':f.quantile(xx,p)} for xx in [[],[-9,-3,0,9,42],list(range(64))] for p in [10,50,90]]
output={'source_sha256':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [root/'hwp0/algorithm/model.py',root/'hwp0/algorithm/features.py']},'domain':domain,'validation':rows,'evaluation':evaluations,'floor':[{'a':str(a),'b':str(b),'result':str(a//b)} for a,b in floors],'ratio':[{'a':str(a),'b':str(b),'result':f.ratio(a,b)} for a,b in ratios],'correlation':[{'xs':x,'ys':y,'result':f.corr(x,y)} for x,y in correlations],'quantile':quantiles}
p=Path(__file__).resolve().parents[1]/'Tests/WriterHWPTests/Fixtures/model-oracle.json';p.write_text(json.dumps(output,sort_keys=True,separators=(',',':'))+'\n');print(f'{len(rows)} validation, {len(evaluations)} evaluation, {len(floors)+len(ratios)+len(correlations)+len(quantiles)} arithmetic cases; {p.stat().st_size} bytes')
