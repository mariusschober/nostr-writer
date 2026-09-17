"""Human Writing Protocol v0: complete, fail-closed public verifier and evaluator.

The relying party pins its policy independently. Only the built-in versioned
bridge is callable; a signed bundle cannot choose an arbitrary Python callback.
"""
from __future__ import annotations
from pathlib import Path
from . import core as c, bridge
from .algorithm.model import validate_model, SCORE_FLOOR

ROOT=Path(__file__).resolve().parents[1]
ASSUMPTIONS=sorted(['complete-document-observation','faithful-device-origin','faithful-monotonic-order',
    'native-delivery-binding','no-hidden-prediction','precommitted-release','single-finalization'])
REPORT_ROLES=sorted(['adaptive','annotation','calibration','capture','heldout','reproducibility'])
ARTIFACTS=('algorithm_spec','program','model','decision_policy','evidence_adapter','output_contract')


def _hex_file(name):return bytes.fromhex((ROOT/'manifests'/name).read_text('ascii').strip())


def installed():
    """Locally installed interpretation anchor. No bundle-provided executable loading."""
    proto=_hex_file('protocol.cbor.hex');program=_hex_file('program.cbor.hex')
    po=c.decode(proto);pr=c.decode(program)
    c.typed(po,'protocol-definition','name revision artifacts');c.typed(pr,'program','algorithm files')
    c.require(po['name']=='Human Writing Protocol' and po['revision']=='0.0.0','installed-definition')
    c.require(pr['algorithm']=='hwp-a/v0','installed-program')
    files={}
    for e in pr['files']:
        c.fields(e,'path ref');p=e['path']
        c.require(type(p) is str and p.startswith('hwp0/') and '..' not in p.split('/') and p not in files,'installed-path')
        raw=(ROOT/p).read_bytes();c.require(c.ref(raw)==e['ref'],'installed-program-changed');files[p]=raw
    artifacts={name:(ROOT/path).read_bytes() for name,path in [('algorithm_spec','docs/ALGORITHM.md'),('evidence_adapter','docs/BINDING.md'),('output_contract','docs/OUTPUT.md')]}
    artifacts['program']=program
    for k,v in artifacts.items():c.require(po['artifacts'][k]==c.ref(v),'installed-artifact-changed')
    return proto,artifacts,files


def install_objects(store):
    proto,arts,files=installed()
    for raw in files.values():store.add(raw)
    for raw in arts.values():store.add(raw)
    # The complete normative dependency closure is public and archival.
    po=c.decode(proto)
    for name,r in po['artifacts'].items():
        if name in arts:continue
        raw=(ROOT/name).read_bytes();c.require(c.ref(raw)==r,'installed-normative-changed');store.add(raw)
    return store.add(proto),{k:store.add(v) for k,v in arts.items()}


def text_order(values,lo=1,hi=4096):
    c.require(type(values) is list and lo<=len(values)<=hi and all(type(x) is str and bool(x) for x in values),'text-list')
    c.require(values==sorted(set(values),key=lambda x:x.encode('utf-8')),'text-list-order')


class ProtocolVerifier(c._MechanicsVerifier):
    def __init__(self,store,policy_bytes,policy_pin,force_recompute=False):
        super().__init__(store,policy_bytes,policy_pin,{},force_recompute)
        self.definition,self.fixed,self.program_files=installed()
        self.protocol_ref=c.ref(self.definition)
        c.require(self.policy['protocol']==self.protocol_ref,'protocol-policy-binding')
        c.require(self.get(self.protocol_ref)==self.definition,'protocol-definition-binding')
        self.releases={};self.lineages={}

    def check_release(self,r):
        raw=self.get(r);key=r['sha256']
        if key in self.releases:return self.releases[key]
        rel=c.decode(raw);c.typed(rel,'release','algorithm claim artifacts capture_profiles protocol stage validation')
        c.require(r in self.policy['releases'],'release-not-authorized')
        c.require(rel['algorithm']=='hwp-a/v0' and rel['protocol']==self.protocol_ref,'release-protocol')
        c.require(rel['claim'] in ('fresh-composition','wording-origin'),'claim-semantics')
        c.require(rel['stage'] in ('conformance','empirical'),'release-stage')
        c.require(self.policy['purpose']!='production' or rel['stage']=='empirical','test-release-not-production')
        c.fields(rel['artifacts'],' '.join(ARTIFACTS))
        for k,r2 in rel['artifacts'].items():
            data=self.get(r2)
            if k in self.fixed:c.require(data==self.fixed[k],'uninstalled-computation')
        # All program and normative source objects must survive in the archive.
        for e in c.decode(self.fixed['program'])['files']:self.get(e['ref'])
        for rr in c.decode(self.definition)['artifacts'].values():self.get(rr)
        model=c.decode(self.get(rel['artifacts']['model']));bridge.json_domain(model);validate_model(model)
        c.require(model['purpose']=='validated-release','model-purpose')
        c.require(len(bridge.av.snapshot(model))<=20_000_000,'model-size')
        dp=c.decode(self.get(rel['artifacts']['decision_policy']))
        c.fields(dp,'threshold claim_kind allowed_domains');c.integer(dp['threshold'],SCORE_FLOOR+1,10**9)
        c.require(dp['claim_kind']==rel['claim'],'decision-claim');text_order(dp['allowed_domains'])
        c.require(set(dp['allowed_domains'])<=set(model['domains']),'decision-model-domain')
        groups={}
        for z in dp['allowed_domains']:
            parts=z.split('|');c.require(len(parts)==4,'domain-format')
            p,path,lang,view=parts
            c.require(p in ('keyboard','touch-tap','ime','gesture') and bool(path) and bool(lang) and view in ('birth','retained','layout','global'),'domain-format')
            groups.setdefault((p,path,lang),set()).add(view)
        c.require(all(v=={'birth','retained','layout','global'} for v in groups.values()),'incomplete-view-domain')
        c._ref_list(rel['capture_profiles'],1,32)
        profiles={}
        for pr in rel['capture_profiles']:
            obj=self.obj(pr);c.typed(obj,'capture-profile','class domains max_resolution_us assumptions evaluation')
            c.require(obj['class'] in ('fixture','evaluated'),'capture-profile-class')
            c.require(self.policy['purpose']!='production' or obj['class']=='evaluated','fixture-capture-not-production')
            text_order(obj['domains']);c.integer(obj['max_resolution_us'],1,10000)
            c.require(obj['assumptions']==ASSUMPTIONS,'capture-assumption-contract')
            for z in obj['domains']:
                q=z.split('|');c.require(len(q)==3 and q[0] in ('keyboard','touch-tap','ime','gesture') and q[1] and q[2],'capture-domain-format')
            if obj['class']=='evaluated':self.get(obj['evaluation'])
            else:c.require(obj['evaluation'] is None,'fixture-evaluation')
            profiles[pr['sha256']]=obj
        c.require(all('|'.join(g) in set().union(*(set(p['domains']) for p in profiles.values())) for g in groups),'release-capture-domains')
        dossier=self.obj(rel['validation'])
        c.typed(dossier,'validation-dossier','stage claim model decision_policy program capture_profiles allowed_domains risk_target coverage_target confidence reports candidate')
        for k,v in [('stage',rel['stage']),('claim',rel['claim']),('model',rel['artifacts']['model']),('decision_policy',rel['artifacts']['decision_policy']),('program',rel['artifacts']['program']),('capture_profiles',rel['capture_profiles']),('allowed_domains',dp['allowed_domains'])]:
            c.require(dossier[k]==v,'validation-dossier-binding')
        c.require(c.encode(dossier['risk_target'])==c.encode([1,1000]) and c.encode(dossier['coverage_target'])==c.encode([1,2]) and c.encode(dossier['confidence'])==c.encode([19,20]),'validation-targets')
        c.require(type(dossier['reports']) is list,'validation-reports')
        roles=[]
        for e in dossier['reports']:
            c.fields(e,'role artifact');c.require(e['role'] in REPORT_ROLES,'validation-report-role');self.get(e['artifact']);roles.append(e['role'])
        c.require(roles==sorted(set(roles)),'validation-report-order')
        if rel['stage']=='empirical':c.require(roles==REPORT_ROLES,'empirical-validation-incomplete')
        else:c.require(not roles,'conformance-not-empirical')
        if rel['stage']=='conformance':
            c.require(dossier['candidate'] is None,'conformance-candidate-pointer')
        else:
            # The tested candidate precedes the reports. Inspecting it here does
            # not authorize it for production or for this proof's captured execution.
            candidate=self.obj(dossier['candidate'])
            c.typed(candidate,'release','algorithm claim artifacts capture_profiles protocol stage validation')
            c.require(candidate['stage']=='conformance','empirical-candidate-stage')
            for k in ('algorithm','claim','artifacts','capture_profiles','protocol'):
                c.require(c.encode(candidate[k])==c.encode(rel[k]),'empirical-candidate-operation-mismatch')
            prior=self.obj(candidate['validation'])
            c.typed(prior,'validation-dossier','stage claim model decision_policy program capture_profiles allowed_domains risk_target coverage_target confidence reports candidate')
            c.require(prior['stage']=='conformance' and prior['candidate'] is None and prior['reports']==[],'empirical-candidate-dossier')
            for k in ('claim','model','decision_policy','program','capture_profiles','allowed_domains','risk_target','coverage_target','confidence'):
                c.require(c.encode(prior[k])==c.encode(dossier[k]),'empirical-candidate-dossier-mismatch')
        # A signed report is not its own scientific approval. External policy is the admission decision.
        self.releases[key]=(rel,dp,profiles);return self.releases[key]

    def admit(self,statement):
        c.typed(statement,'statement','document media_type scope release captures target_capture lineage mode author nonce')
        rel,dp,profiles=self.check_release(statement['release'])
        c._ref_list(statement['captures'],1,32);c.require(statement['target_capture'] in statement['captures'],'target-capture-binding')
        grants={g['profile']['sha256']:g for g in self.policy['capture_authorities']}
        infos={};sessions={}
        for cr in statement['captures']:
            end,kid=self.signed(cr);c.typed(end,'capture-end','start count root complete participation document')
            start,skid=self.signed(end['start']);c.typed(start,'capture-start','session profile adapter nonce subject release parents')
            c.require(kid==skid,'capture-key-changed');c.octets(start['session'],32);c.octets(start['nonce'],32)
            c.require(end['complete'] is True,'capture-not-complete');c.integer(end['count'],2,c.MAX_EVENTS);c.octets(end['root'],32);c.valid_ref(end['document'])
            c.require(start['profile'] in rel['capture_profiles'] and start['adapter']==rel['artifacts']['evidence_adapter'],'capture-release-binding')
            grant=grants.get(start['profile']['sha256'])
            c.require(grant is not None and grant['profile']==start['profile'] and any(k['sha256']==kid and self.get(k)==self.store.objects[kid] for k in grant['keys']),'capture-authority')
            original,_,_=self.check_release(start['release'])
            c.require(original['artifacts']['evidence_adapter']==rel['artifacts']['evidence_adapter'] and start['profile'] in original['capture_profiles'],'original-capture-release')
            if cr==statement['target_capture']:
                c.require(start['release']==statement['release'],'release-not-precommitted')
                c.require(end['document']==statement['document'],'capture-final-document')
                c.require(start['subject']==statement['author'],'target-subject-binding')
            pair=(kid,start['session']);c.require(pair not in sessions,'duplicate-session');sessions[pair]=cr
            if start['subject'] is None:c.require(end['participation'] is None,'unexpected-participation')
            else:
                c.parse_key(self.get(start['subject']));b,pk=self.signed(end['participation']);c.typed(b,'participation','start')
                c.require(b['start']==end['start'] and pk==start['subject']['sha256'] and pk!=kid,'participation-binding')
            c.require(type(start['parents']) is list and len(start['parents'])<=32,'capture-parents');refs=[]
            for p in start['parents']:
                c.fields(p,'capture proof');c.valid_ref(p['capture']);refs.append(p['capture'])
                if p['proof'] is not None:
                    pp=self.obj(p['proof']);c.typed(pp,'proof','statement appraisals author');ps=self.obj(pp['statement'])
                    c.require(ps['target_capture']==p['capture'],'planned-parent-proof-binding')
            c._ref_list(refs,0,32)
            infos[cr['sha256']]={'ref':cr,'end':end,'start':start,'profile':profiles[start['profile']['sha256']]}
        reached=set()
        def visit(cr,active):
            c.require(cr['sha256'] not in active,'capture-cycle')
            c.require(cr['sha256'] in infos and infos[cr['sha256']]['ref']==cr,'capture-parent-missing')
            if cr['sha256'] in reached:return
            reached.add(cr['sha256'])
            for p in infos[cr['sha256']]['start']['parents']:visit(p['capture'],active|{cr['sha256']})
        visit(statement['target_capture'],set());c.require(reached==set(infos),'unrelated-capture')
        return rel,infos

    def verify(self,proof_ref,expected_document=None,disclosures=None):
        self.get(proof_ref)
        c.require(proof_ref['sha256'] not in self.active,'cyclic-proof')
        if proof_ref['sha256'] in self.done:return super().verify(proof_ref,expected_document,disclosures)
        c.require(self.steps<c.MAX_PROOFS,'proof-graph-budget')
        proof=self.obj(proof_ref);c.typed(proof,'proof','statement appraisals author')
        st=self.obj(proof['statement']);rel,infos=self.admit(st)
        bridge.selected_scope(self.obj(st['scope']),self.get(st['document']))
        def runner(evidence,release,request):
            # Derive admissions for this invocation (a parent can share the same release).
            capture_refs=c.reference_list([e['capture'] for e in evidence])
            # Full metadata was authenticated by this proof's admit() before the callback.
            local_infos={r['sha256']:infos[r['sha256']] for r in capture_refs}
            out,lineage=bridge.run(evidence,release,request,local_infos,self.store)
            self.lineages[proof['statement']['sha256']]=lineage;return out
        # Core invokes a parent proof before a child callback. Capture this proof's
        # own callback by adding the immutable statement identity to its request.
        self.runners[(st['release']['sha256'],proof['statement']['sha256'])]=runner
        out=super().verify(proof_ref,expected_document,disclosures)
        return out


def verify(bundle,document,policy_bytes=None,policy_pin=None,disclosures=None,recompute=False):
    """Public result vocabulary: HUMAN-WRITTEN / NOT PROVABLE; test is never certified."""
    try:
        c.require(policy_bytes is not None and policy_pin is not None,'no-external-trust-policy')
        store,root=c.Store.unpack(bundle);v=ProtocolVerifier(store,policy_bytes,policy_pin,recompute)
        got=v.verify(root,c.octets(document),disclosures)
        out={k:x for k,x in got.items() if not k.startswith('_')}
        if v.policy['purpose']=='conformance':
            out.update(status='TEST-ONLY',result=None,outcome='NOT PROVABLE',test_conformance=True)
        else:out.update(status='VALID-HWP',outcome=c.PASS,test_conformance=False)
        out.update(protocol=c.VERSION,authorship_inference=None)
        return out
    except (c.Reject,TypeError,ValueError,KeyError,IndexError,OverflowError,RecursionError,OSError) as e:
        return {'protocol':c.VERSION,'status':'NO-VALID-HWP','outcome':'NOT PROVABLE','reason':str(e) if isinstance(e,c.Reject) else 'malformed-input','authorship_inference':None}


def evaluate_statement(store,statement_ref,policy_bytes,policy_pin,disclosures):
    """Issuance path: recompute actual algorithm output before signing any appraisal."""
    v=ProtocolVerifier(store,policy_bytes,policy_pin,True);st=v.obj(statement_ref);rel,infos=v.admit(st)
    bridge.selected_scope(v.obj(st['scope']),v.get(st['document']))
    c.fields(disclosures,'logs lineage_salts')
    c.require(type(disclosures['logs']) is list and len(disclosures['logs'])<=4096 and type(disclosures['lineage_salts']) is list and len(disclosures['lineage_salts'])<=64,'disclosure-count')
    logs={};total=0;count=0
    for e in disclosures['logs']:
        c.fields(e,'capture openings');c.valid_ref(e['capture']);c.require(e['capture']['sha256'] not in logs,'duplicate-disclosed-session')
        c.require(type(e['openings']) is list and len(e['openings'])<=c.MAX_EVENTS,'disclosure-openings')
        for o in e['openings']:
            c.fields(o,'index salt event');total+=len(c.octets(o['event']))+len(c.octets(o['salt'],32));count+=1
            c.require(total<=c.MAX_BYTES and count<=c.MAX_EVENTS,'disclosure-budget')
        c.require(total<=c.MAX_BYTES and count<=c.MAX_EVENTS,'disclosure-budget');logs[e['capture']['sha256']]=e
    salts={}
    for e in disclosures['lineage_salts']:
        c.fields(e,'statement salt');c.valid_ref(e['statement']);c.octets(e['salt'],32)
        c.require(e['statement']['sha256'] not in salts,'duplicate-lineage-salt');salts[e['statement']['sha256']]=e
    c.require(statement_ref['sha256'] in salts and salts[statement_ref['sha256']]['statement']==statement_ref,'missing-lineage-salt')
    evidence=[]
    for m in infos.values():
        e=logs.get(m['ref']['sha256']);c.require(e is not None and e['capture']==m['ref'],'missing-disclosed-session')
        evidence.append({'capture':m['ref'],'events':c.open_transcript(m['end']['start'],m['end']['count'],m['end']['root'],e['openings'])})
    # Inherited origins are independently verified, not merely byte-matched.
    for r in v.obj(st['scope'])['ranges']:
        if r['origin'][0]=='inherited':v.verify(r['origin'][1],None,disclosures)
    request={'target_capture':st['target_capture'],'requested_scope':v.obj(st['scope']),
             'lineage_salt':salts[statement_ref['sha256']]['salt'],'artifacts':{k:v.get(r) for k,r in rel['artifacts'].items()}}
    return bridge.run(evidence,rel,request,infos,store)


def issue_appraisal(store,statement_ref,policy_bytes,policy_pin,disclosures,evaluator_seed):
    """Normal issuer entry point. Negative or misbound results receive no signature."""
    actual,_=evaluate_statement(store,statement_ref,policy_bytes,policy_pin,disclosures)
    policy=c.decode(policy_bytes);key=c.ref(c.key_bytes(c.public_key(evaluator_seed)))
    c.require(key in policy['evaluators'],'evaluator-not-authorized')
    return c.sign_appraisal(store,statement_ref,actual,evaluator_seed)
