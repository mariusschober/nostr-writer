import sys,json,copy
from pathlib import Path
if len(sys.argv)!=2: raise SystemExit('Usage: python reproduce_v02.py /path/to/original/algorithm')
sys.path.insert(0,sys.argv[1])
from hwp_a.fixtures import Builder,TEXT,permissive_fixture_model
from hwp_a.verify import verify,score,TrustedInputs
from hwp_a.replay import replay,make_units
from hwp_a.features import extract

def ctx(b,m,approve=True):return TrustedInputs(frozenset(d['id'] for d in b['documents']),approve,0,frozenset(m['domains']))
def run(b):
 m=permissive_fixture_model(b);m['purpose']='validated-release';return verify(b,m,0,ctx(b,m)),m
out={}
b=Builder().type(TEXT+'The recorded amount is 100 units. '+TEXT)
p=b.text.index('100');b.splice(p,p+3,'900','spelling')
bundle=b.bundle();r,m=run(bundle)
out['semantic_spelling']={'verdict':r['verdict'],'changed_text':'100 -> 900','ranges':r['ranges']}
bundle=Builder().type(TEXT).bundle();m=permissive_fixture_model(bundle);trusted=ctx(bundle,m)
m['purpose']='validated-release'
out['model_substitution']={'verdict':verify(bundle,m,0,trusted)['verdict'],'note':'Same approval flag accepts relabelled test double; no model snapshot binding.'}
a=Builder().type(TEXT).bundle(); b=copy.deepcopy(a)
for tx in b['documents'][0]['transactions']:
 tx['text']=''.join(chr((ord(ch)-97+13)%26+97) if 'a'<=ch<='z' else chr((ord(ch)-65+13)%26+65) if 'A'<=ch<='Z' else ch for ch in tx['text'])
b['documents'][0]['final_text']=''.join(t['text'] for t in b['documents'][0]['transactions'])
ca,cb=replay(a),replay(b);ua,_=make_units(ca,'d');ub,_=make_units(cb,'d')
out['feature_collision']={'units':len(ua),'all_features_identical':all(extract(ca,x)==extract(cb,y) for x,y in zip(ua,ub)),'different_final_text':a['documents'][0]['final_text']!=b['documents'][0]['final_text']}
# An unrelated later imported string retroactively taints the prior document.
a=Builder('a').type(TEXT).record();late=Builder('unrelated').splice(0,0,TEXT,'paste').record()
b1={'version':'hwp-a/0.2','documents':[a],'target':'a'}; b2={'version':'hwp-a/0.2','documents':[a,late],'target':'a'}
r1,_=run(b1);r2,_=run(b2)
out['future_source_taint']={'before':r1['verdict'],'after_unrelated_document':r2['verdict']}
# A held key can produce a repeat outside focused observation, then deliver after refocus.
b=Builder().type('x').bundle();d=b['documents'][0];t=d['observations'][0]['t']
d['observations']=[dict(i=0,t=t,kind='press',token='p',source='device',profile='keyboard'),dict(i=1,t=t+1000,kind='focus_out',token='out',source='device',profile='keyboard'),dict(i=2,t=t+2000,kind='repeat',token='p',source='device',profile='keyboard'),dict(i=3,t=t+3000,kind='focus_in',token='in',source='device',profile='keyboard'),dict(i=4,t=t+4000,kind='release',token='p',source='device',profile='keyboard')]
d['transactions'][0]['causes']=[2];d['transactions'][0]['t']=t+3000
try:replay(b);accepted=True
except Exception:accepted=False
out['repeat_outside_focus']={'trace_structurally_accepted':accepted}
# Spell out that successful fixture verdicts are conditional and not empirical security results.
out['status']='Synthetic counterexamples with an explicitly permissive model; zero real participant observations.'
open(Path(__file__).parent/'v02-counterexamples.json','w').write(json.dumps(out,indent=2)+'\n')
print(json.dumps({k:v if k!='semantic_spelling' else {'verdict':v['verdict']} for k,v in out.items()},indent=2))
