"""Deterministic synthetic crypto fixtures; no real HWP detector or human evidence."""
import hashlib
import hwp_crypto as h

def seed(label): return hashlib.sha256(('PUBLIC TEST SEED: '+label).encode()).digest()

def make(mode='attested-v1',author=False,identity=False,selected=False,name=''):
    st=h.Store()
    keys={name:st.add(h.key_bytes(h.public_key(seed(name)))) for name in ['capture','evaluator','evaluator2','author','identity','untrusted']}
    artifacts={name:st.add(('SYNTHETIC FIXTURE ONLY: '+name).encode()) for name in ['algorithm_spec','program','model','decision_policy','evidence_adapter','output_contract']}
    profile=st.add(b'SYNTHETIC CAPTURE PROFILE: NO PHYSICAL CAPTURE')
    release=st.put({'v':h.VERSION,'type':'release','algorithm':'test-only/no-human-detector','claim':'fresh-composition','artifacts':artifacts,'capture_profiles':[profile]})
    subject=keys['author'] if author else None
    start=st.add(h.sign({'v':h.VERSION,'type':'capture-start','session':seed('session'+name),'profile':profile,'adapter':artifacts['evidence_adapter'],'nonce':seed('start-nonce'+name),'subject':subject},seed('capture')))
    consent=st.add(h.sign({'v':h.VERSION,'type':'participation','start':start},seed('author'))) if author else None
    doc='Café — a synthetic cryptographic fixture.\n'.encode('utf-8')
    dref=st.add(doc)
    events=[{'kind':'header','fixture':True},{'kind':'record','text':'NOT real human telemetry'},{'kind':'end','document':doc}]
    salts=[seed('salt'+str(i)) for i in range(len(events))]
    root,openings=h.commit_events(start,events,salts)
    end=st.add(h.sign({'v':h.VERSION,'type':'capture-end','start':start,'count':len(events),'root':root,'complete':True,'participation':consent},seed('capture')))
    ranges=[{'start':0,'end':len(doc),'origin':['observed',[end]]}]
    if selected:
        a=len('Café — '.encode())
        ranges=[{'start':0,'end':a,'origin':['excluded','example quotation']},{'start':a,'end':len(doc),'origin':['observed',[end]]}]
    scope=st.put({'v':h.VERSION,'type':'scope','document':dref,'kind':'selected-ranges' if selected else 'whole-document','ranges':ranges})
    lineage=h.lineage_commitment(seed('lineage-salt'),b'PRIVATE SYNTHETIC LINEAGE')
    statement=st.put({'v':h.VERSION,'type':'statement','document':dref,'media_type':'text/plain','scope':scope,'release':release,'captures':[end],'target_capture':end,'lineage':lineage,'mode':mode,'author':subject,'nonce':seed('statement-nonce'+name)})
    computed={'document':dref,'scope':scope,'lineage':lineage,'release':release,'captures':[end],'target_capture':end,'result':h.PASS}
    appraisal=h.sign_appraisal(st,statement,computed,seed('evaluator'))
    author_ref=None
    if author:
        identity_ref=st.add(h.sign({'v':h.VERSION,'type':'identity-binding','subject':subject,'namespace':'test-only.example:synthetic-id','identifier':'FICTIONAL TEST PERSON'},seed('identity'))) if identity else None
        author_ref=st.add(h.sign({'v':h.VERSION,'type':'author-endorsement','statement':statement,'identity':identity_ref},seed('author')))
    policy={'v':h.VERSION,'type':'verification-policy','label':'SYNTHETIC TEST POLICY: NOT PRODUCTION APPROVAL','releases':[release],'capture_authorities':[{'profile':profile,'keys':[keys['capture']]}],'evaluators':h.reference_list([keys['evaluator'],keys['evaluator2']]),'quorum':1,'modes':['attested-v1','disclosed-v1'],'require_author':author,'identity_authorities':[keys['identity']],'denied':[],'status_as_of':None}
    pbytes=h.encode(policy)
    proof=st.put({'v':h.VERSION,'type':'proof','statement':statement,'appraisals':[appraisal],'author':author_ref})
    bundle=st.pack(proof)
    disclosure={'logs':[{'capture':end,'openings':openings}],'lineage_salts':[{'statement':statement,'salt':seed('lineage-salt')}]}
    def runner(witness,rel,request):
        # Exact synthetic equality assertion only; deliberately NOT a behavioural algorithm.
        if witness!=[{'capture':end,'events':events}] or rel!=st.obj(release) or request['target_capture']!=end or request['lineage_salt']!=seed('lineage-salt') or request['requested_scope']!=st.obj(scope): raise h.Reject('fixture-runner-input')
        return computed
    return {'store':st,'keys':keys,'profile':profile,'artifacts':artifacts,'release':release,'start':start,'end':end,'events':events,'openings':openings,'salts':salts,'statement':statement,'scope':scope,'appraisal':appraisal,'proof':proof,'document':doc,'bundle':bundle,'policy':policy,'policy_bytes':pbytes,'policy_digest':h.digest(pbytes),'disclosures':disclosure,'runner':runner,'computed':computed}

def check(f,**kw):
    args={'bundle':f['bundle'],'document':f['document'],'policy_bytes':f['policy_bytes'],'expected_policy_digest':f['policy_digest'],'disclosures':f['disclosures'],'runners':{f['release']['sha256']:f['runner']}}
    args.update(kw)
    return h.verify_bundle(**args)

def change_statement(f,fn,resign=True,seedname='evaluator'):
    st=f['store']; s=st.obj(f['statement']); fn(s); sref=st.put(s)
    p=st.obj(f['proof']); p['statement']=sref
    if resign:
        p['appraisals']=[st.add(h.sign({'v':h.VERSION,'type':'appraisal','statement':sref,'result':h.PASS},seed(seedname)))]
    root=st.put(p); f['proof']=root; f['statement']=sref; f['bundle']=st.pack(root)
    return f

def change_policy(f,fn):
    fn(f['policy']); f['policy_bytes']=h.encode(f['policy']); f['policy_digest']=h.digest(f['policy_bytes'])
    return f
