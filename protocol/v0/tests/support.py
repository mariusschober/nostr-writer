"""Public synthetic keys and machine-generated writing: NEVER real human evidence."""
from hashlib import sha256
from copy import deepcopy
from hwp0 import core as c, protocol as p, bridge
from hwp0.algorithm.fixtures import Builder,TEXT,permissive_fixture_model

def seed(s):return sha256(('HWP-v0 PUBLIC FIXTURE: '+s).encode()).digest()

def make(profile='keyboard',claim='fresh-composition',mode='attested-v1',author=False,identity=False,record=None,parents=(),scope_ranges=None,name='d',threshold=0):
    rec=record or Builder(name,profile).type(TEXT*2,seed=11).record()
    store=c.Store()
    for f in parents:
        for raw in f['store'].objects.values():store.add(raw)
    proto,fixed=p.install_objects(store)
    keys={k:store.add(c.key_bytes(c.public_key(seed(k)))) for k in ('capture','evaluator','evaluator2','author','identity','other')}
    records=[]
    for f in parents:
        for r in f['records']:
            if r['id'] not in {x['id'] for x in records}:records.append(r)
    records.append(rec)
    bundle={'version':'hwp-a/v0','documents':records,'target':rec['id']}
    model=permissive_fixture_model(bundle);model['purpose']='validated-release'
    mr=store.put(model)
    dp={'threshold':threshold,'claim_kind':claim,'allowed_domains':sorted(model['domains'],key=lambda z:z.encode('utf-8'))}
    dr=store.put(dp)
    domains=sorted({'|'.join(z.split('|')[:3]) for z in model['domains']})
    profile_obj={'v':c.VERSION,'type':'capture-profile','class':'fixture','domains':domains,'max_resolution_us':10000,'assumptions':p.ASSUMPTIONS,'evaluation':None}
    pr=store.put(profile_obj)
    profile_refs=c.reference_list(list({q['sha256']:q for q in [pr]+[q for f in parents for q in f['profiles']]}.values()))
    arts=dict(fixed,model=mr,decision_policy=dr)
    dossier={'v':c.VERSION,'type':'validation-dossier','stage':'conformance','claim':claim,'model':mr,'decision_policy':dr,'program':fixed['program'],
        'capture_profiles':profile_refs,'allowed_domains':dp['allowed_domains'],'risk_target':[1,1000],'coverage_target':[1,2],'confidence':[19,20],'reports':[],'candidate':None}
    rel=store.put({'v':c.VERSION,'type':'release','algorithm':'hwp-a/v0','claim':claim,'artifacts':arts,'capture_profiles':profile_refs,'protocol':proto,'stage':'conformance','validation':store.put(dossier)})
    deps={t['from_doc'] for t in rec['transactions'] if t['op']=='copy' and t['from_doc']!=rec['id']}
    parent_by_id={f['record']['id']:f for f in parents}
    planned=sorted([{'capture':parent_by_id[k]['end'],'proof':parent_by_id[k]['proof']} for k in deps],key=lambda q:q['capture']['sha256'])
    subject=keys['author'] if author else None
    start=store.add(c.sign({'v':c.VERSION,'type':'capture-start','session':seed('session/'+name),'profile':pr,'adapter':fixed['evidence_adapter'],
        'nonce':seed('start/'+name),'subject':subject,'release':rel,'parents':planned},seed('capture')))
    participation=store.add(c.sign({'v':c.VERSION,'type':'participation','start':start},seed('author'))) if author else None
    events=bridge.record_events(rec);salts=[seed(name+'/event/'+str(i)) for i in range(len(events))]
    root,openings=c.commit_events(start,events,salts)
    document=rec['final_text'].encode('utf-8');docref=store.add(document)
    end=store.add(c.sign({'v':c.VERSION,'type':'capture-end','start':start,'count':len(events),'root':root,'complete':True,'participation':participation,'document':docref},seed('capture')))
    captures=[];logs=[];lineage_salts=[];release_refs=[rel]
    for f in parents:
        captures+=f['captures'];logs+=f['disclosures']['logs'];lineage_salts+=f['disclosures']['lineage_salts'];release_refs+=f['policy']['releases']
    def unique(items,key):return list({key(x):x for x in items}.values())
    captures=c.reference_list(unique(captures+[end],lambda q:q['sha256']))
    logs=unique(logs+[{'capture':end,'openings':openings}],lambda q:q['capture']['sha256'])
    lineage_salts=unique(lineage_salts,lambda q:q['statement']['sha256'])
    ranges=scope_ranges(end) if callable(scope_ranges) else scope_ranges
    if ranges is None:ranges=[{'start':0,'end':len(document),'origin':['observed',[end]]}]
    kind='selected-ranges' if any(r['origin'][0]=='excluded' for r in ranges) else 'whole-document'
    scope=store.put({'v':c.VERSION,'type':'scope','document':docref,'kind':kind,'ranges':ranges})
    state={'v':c.VERSION,'type':'statement','document':docref,'media_type':'text/plain','scope':scope,'release':rel,'captures':captures,
        'target_capture':end,'lineage':bytes(32),'mode':mode,'author':subject,'nonce':seed('statement/'+name)}
    policy={'v':c.VERSION,'type':'verification-policy','protocol':proto,'purpose':'conformance','label':'Synthetic conformance only; no human data or approval',
        'releases':c.reference_list(unique(release_refs,lambda q:q['sha256'])),
        'capture_authorities':[{'profile':q,'keys':[keys['capture']]} for q in profile_refs],
        'evaluators':c.reference_list([keys['evaluator'],keys['evaluator2']]),'quorum':1,'modes':['attested-v1','disclosed-v1'],
        'require_author':author,'identity_authorities':[keys['identity']],'denied':[],'status_as_of':None}
    pb=c.encode(policy);pin=c.digest(pb);temporary=store.put(state);salt=seed('lineage/'+name)
    disclosures={'logs':logs,'lineage_salts':lineage_salts+[{'statement':temporary,'salt':salt}]}
    computed,lineage=p.evaluate_statement(store,temporary,pb,pin,disclosures)
    state['lineage']=computed['lineage'];sr=store.put(state)
    disclosures['lineage_salts'][-1]['statement']=sr
    appraisal=c.sign_appraisal(store,sr,computed,seed('evaluator'))
    ar=None
    if author:
        ident=store.add(c.sign({'v':c.VERSION,'type':'identity-binding','subject':subject,'namespace':'test.invalid','identifier':'SYNTHETIC SUBJECT'},seed('identity'))) if identity else None
        ar=store.add(c.sign({'v':c.VERSION,'type':'author-endorsement','statement':sr,'identity':ident},seed('author')))
    proof=store.put({'v':c.VERSION,'type':'proof','statement':sr,'appraisals':[appraisal],'author':ar})
    return dict(store=store,model=model,record=rec,records=records,profiles=profile_refs,keys=keys,release=rel,start=start,end=end,captures=captures,
        events=events,openings=openings,scope=scope,statement=sr,appraisal=appraisal,proof=proof,document=document,bundle=store.pack(proof),
        policy=policy,policy_bytes=pb,policy_pin=pin,disclosures=disclosures,computed=computed,lineage=lineage)


def check(f,**kw):
    args=dict(bundle=f['bundle'],document=f['document'],policy_bytes=f['policy_bytes'],policy_pin=f['policy_pin'],disclosures=f['disclosures'])
    args.update(kw);return p.verify(**args)


def restatement(f,change,resign=True):
    s=f['store'];st=deepcopy(s.obj(f['statement']));change(st);sr=s.put(st);pr=deepcopy(s.obj(f['proof']));pr['statement']=sr
    if resign:pr['appraisals']=[s.add(c.sign({'v':c.VERSION,'type':'appraisal','statement':sr,'result':c.PASS},seed('evaluator')))]
    root=s.put(pr);return dict(f,statement=sr,proof=root,bundle=s.pack(root))


def policy_change(f,fn):
    po=deepcopy(f['policy']);fn(po);pb=c.encode(po);return dict(f,policy=po,policy_bytes=pb,policy_pin=c.digest(pb))
