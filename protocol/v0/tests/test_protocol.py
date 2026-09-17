"""End-to-end protocol tests: actual algorithm, actual commitments, no echo runner.

All keys, source observations, and model parameters are synthetic. TEST-ONLY is
an interoperability result; none of these tests measures human discrimination.
"""
import copy
import unittest
from dataclasses import replace
from hwp0 import core as c, protocol as p, bridge
from hwp0.algorithm.fixtures import Builder,TEXT
from hwp0.algorithm.replay import replay,InvalidTrace,SPACE
from tests.support import make,check,restatement,policy_change,seed


def reproof(f,edit):
    st=f['store'];obj=copy.deepcopy(st.obj(f['proof']));edit(obj);pr=st.put(obj)
    return dict(f,proof=pr,bundle=st.pack(pr))


def rescope(f,edit):
    sc=copy.deepcopy(f['store'].obj(f['scope']));edit(sc);ref=f['store'].put(sc)
    return restatement(f,lambda s:s.update(scope=ref))


def replacement_capture(f,record):
    """Admitted fixture signer deliberately fabricates a different observed history."""
    st=f['store'];events=bridge.record_events(record)
    root,openings=c.commit_events(f['start'],events,[seed('false-event/'+str(i)) for i in range(len(events))])
    old=st.obj(f['end']) if False else st.signed(f['end'])[0]
    end=dict(old,root=root,count=len(events),document=st.add(record['final_text'].encode()))
    er=st.add(c.sign(end,seed('capture')))
    g=rescope(f,lambda sc:sc.update(document=end['document'],ranges=[{'start':0,'end':len(record['final_text'].encode()),'origin':['observed',[er]]}]))
    g=restatement(g,lambda s:s.update(captures=[er],target_capture=er,document=end['document']))
    g['document']=record['final_text'].encode();g['end']=er
    g['disclosures']={'logs':[{'capture':er,'openings':openings}], 'lineage_salts':[{'statement':g['statement'],'salt':seed('lineage/'+record['id'])}]}
    return g


class Integration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.base=make()
    def good(self,f,**kw):
        r=check(f,**kw);self.assertEqual(r['status'],'TEST-ONLY',r);self.assertEqual(r['outcome'],'NOT PROVABLE');return r
    def bad(self,f,**kw):
        r=check(f,**kw);self.assertEqual(r['status'],'NO-VALID-HWP',r);self.assertEqual(r['outcome'],'NOT PROVABLE');return r
    def test_real_bridge_four_profiles(self):
        for profile in ('keyboard','touch-tap','ime','gesture'):
            with self.subTest(profile=profile):
                f=make(profile=profile,name=profile)
                self.assertEqual(self.good(f,recompute=True)['execution_checked'],'recomputed')
    def test_attestation_and_recomputation_same_binding(self):
        a=self.good(self.base);b=self.good(self.base,recompute=True)
        for k in ('document','proof','ranges','release','claim'):self.assertEqual(a[k],b[k])
        self.assertEqual(a['execution_checked'],'attestation')
    def test_disclosed_mode_always_runs_algorithm(self):
        f=make(mode='disclosed-v1');self.assertEqual(self.good(f)['execution_checked'],'recomputed')
        self.bad(f,disclosures=None)
    def test_source_bytes_reconstruct_identically(self):
        f=self.base;record=bridge.decode_record(bridge.record_events(f['record']))
        self.assertEqual(record,f['record'])
        self.assertEqual(c.decode(f['lineage'])['assessment']['verdict'],c.PASS)
    def test_private_bundle_does_not_contain_events_or_salts(self):
        f=self.base;st,_=c.Store.unpack(f['bundle'])
        for opening in f['openings']:
            self.assertNotIn(opening['event'],st.objects.values())
            self.assertNotIn(opening['salt'],st.objects.values())
    def test_production_rejects_conformance_even_with_same_keys(self):
        g=policy_change(self.base,lambda po:po.update(purpose='production'))
        self.assertEqual(self.bad(g)['reason'],'test-release-not-production')
    def test_missing_policy(self):self.bad(self.base,policy_bytes=None,policy_pin=None)
    def test_policy_pin_not_self_selected(self):self.bad(self.base,policy_pin=bytes(32))
    def test_exact_document_bytes(self):self.bad(self.base,document=self.base['document']+b'\n')
    def test_no_arbitrary_runner_parameter(self):
        with self.assertRaises(TypeError):p.verify(self.base['bundle'],self.base['document'],runners={})
    def test_absent_release_authorization(self):self.bad(policy_change(self.base,lambda po:po.update(releases=[])))
    def test_absent_capture_authorization(self):self.bad(policy_change(self.base,lambda po:po.update(capture_authorities=[])))
    def test_absent_evaluator_authorization(self):self.bad(policy_change(self.base,lambda po:po.update(evaluators=[])))
    def test_quorum_cannot_be_satisfied_by_duplication(self):
        g=reproof(self.base,lambda pr:pr.update(appraisals=[self.base['appraisal'],self.base['appraisal']]))
        self.bad(g)
    def test_two_distinct_evaluator_keys(self):
        f=self.base;s=f['store'];ar=s.add(c.sign({'v':c.VERSION,'type':'appraisal','statement':f['statement'],'result':c.PASS},seed('evaluator2')))
        g=reproof(f,lambda pr:pr.update(appraisals=c.reference_list([f['appraisal'],ar])))
        g=policy_change(g,lambda po:po.update(quorum=2));self.good(g)
    def test_no_mode_downgrade(self):self.bad(restatement(self.base,lambda s:s.update(mode='zk-v0')))
    def test_statement_edit_requires_signature(self):self.bad(restatement(self.base,lambda s:s.update(nonce=seed('othernonce')),resign=False))
    def test_lineage_substitution_recomputed(self):
        g=restatement(self.base,lambda s:s.update(lineage=bytes(32)))
        g['disclosures']=copy.deepcopy(self.base['disclosures']);g['disclosures']['lineage_salts'][-1]['statement']=g['statement']
        self.bad(g,recompute=True)
    def test_missing_openings_cannot_recompute(self):self.bad(self.base,recompute=True,disclosures={'logs':[],'lineage_salts':[]})
    def test_wrong_lineage_salt(self):
        d=copy.deepcopy(self.base['disclosures']);d['lineage_salts'][-1]['salt']=bytes(32);self.bad(self.base,disclosures=d,recompute=True)
    def test_truncated_history(self):
        d=copy.deepcopy(self.base['disclosures']);d['logs'][0]['openings'].pop();self.bad(self.base,disclosures=d,recompute=True)
    def test_reordered_history(self):
        d=copy.deepcopy(self.base['disclosures']);d['logs'][0]['openings'][1:3]=reversed(d['logs'][0]['openings'][1:3]);self.bad(self.base,disclosures=d,recompute=True)
    def test_altered_history(self):
        d=copy.deepcopy(self.base['disclosures']);o=d['logs'][0]['openings'][1];v=c.decode(o['event']);v['value']['token']='changed';o['event']=c.encode(v)
        self.bad(self.base,disclosures=d,recompute=True)
    def test_noncanonical_cbor(self):self.bad(self.base,bundle=self.base['bundle']+b'\x00')
    def test_old_wire_is_not_v0(self):
        obj=c.decode(self.base['bundle']);obj['v']='hwp-c/1';self.bad(self.base,bundle=c.encode(obj))
    def test_explicit_target_final_document(self):
        f=self.base;s=f['store'];new=s.add(b'Other text.')
        g=rescope(f,lambda sc:sc.update(document=new,ranges=[{'start':0,'end':new['size'],'origin':['observed',[f['end']]]}]))
        g=restatement(g,lambda st:st.update(document=new));self.bad(g,document=b'Other text.')
    def test_unknown_target_capture(self):self.bad(restatement(self.base,lambda st:st.update(target_capture=self.base['start'])))
    def test_signed_negative_is_not_proof(self):
        f=self.base;ar=f['store'].add(c.sign({'v':c.VERSION,'type':'appraisal','statement':f['statement'],'result':'NOT PROVABLE'},seed('evaluator')))
        self.bad(reproof(f,lambda pr:pr.update(appraisals=[ar])))
    def test_unrelated_capture_cannot_add_evidence(self):
        f=make(name='other');g=self.base
        for raw in f['store'].objects.values():g['store'].add(raw)
        self.bad(restatement(g,lambda st:st.update(captures=c.reference_list([g['end'],f['end']]))))
    def test_release_cannot_be_selected_after_capture(self):
        f=self.base;s=f['store'];old=s.obj(f['release']);d=s.obj(old['artifacts']['decision_policy']);d['threshold']=-1;dr=s.put(d)
        ds=s.obj(old['validation']);ds['decision_policy']=dr
        new=dict(old,artifacts=dict(old['artifacts'],decision_policy=dr),validation=s.put(ds));rr=s.put(new)
        g=restatement(f,lambda st:st.update(release=rr));g=policy_change(g,lambda po:po.update(releases=c.reference_list(po['releases']+[rr])))
        self.assertEqual(self.bad(g)['reason'],'release-not-precommitted')
    def test_model_artifact_not_unversioned_name(self):
        f=self.base;rel=f['store'].obj(f['release']);rel['artifacts']['model']=f['store'].add(b'not a model')
        rr=f['store'].put(rel);g=restatement(f,lambda st:st.update(release=rr));g=policy_change(g,lambda po:po.update(releases=c.reference_list(po['releases']+[rr])))
        self.bad(g)
    def test_pseudonymous_author(self):self.assertEqual(self.good(make(author=True),recompute=True)['author'],'pseudonymous-key-endorsement')
    def test_identified_key_not_physical_authorship(self):self.assertEqual(self.good(make(author=True,identity=True))['author']['kind'],'attested-key-controller')
    def test_author_stripping_fails(self):self.bad(reproof(make(author=True),lambda pr:pr.update(author=None)))
    def test_quotations_change_scope_not_positive_credit(self):
        b=Builder().type(TEXT*2).splice(len(TEXT*2),len(TEXT*2),' EXTERNAL QUOTE',source='paste')
        split=len((TEXT*2).encode());end=len(b.text.encode())
        f=make(record=b.record(),scope_ranges=lambda cap:[{'start':0,'end':split,'origin':['observed',[cap]]},{'start':split,'end':end,'origin':['excluded','quoted source']}])
        self.assertEqual(self.good(f,recompute=True)['scope'],'selected-ranges')
        self.bad(rescope(f,lambda sc:sc.update(kind='whole-document')))
    def test_nonmaximal_scope_rejected(self):
        f=self.base
        self.bad(rescope(f,lambda sc:sc.update(ranges=[{'start':0,'end':64,'origin':['observed',[f['end']]]},{'start':64,'end':len(f['document']),'origin':['observed',[f['end']]]}])))
    def test_empty_exclusion_rejected(self):
        f=self.base;self.bad(rescope(f,lambda sc:sc.update(kind='selected-ranges',ranges=[{'start':0,'end':len(f['document']),'origin':['excluded','']}])) )
    def test_unicode_line_separators_never_meaningful(self):
        for char in ('\u2028','\u2029','\u00a0'):
            with self.subTest(char=ord(char)):
                raw=(char*64).encode();scope={'v':c.VERSION,'type':'scope','document':c.ref(raw),'kind':'whole-document','ranges':[{'start':0,'end':len(raw),'origin':['observed',[self.base['end']]]}]}
                with self.assertRaises(c.Reject):bridge.selected_scope(scope,raw)
    def test_encoder_must_not_upgrade_missing_native_events(self):
        rec=copy.deepcopy(self.base['record']);del rec['transactions'][0]['delivery']
        events=bridge.record_events(rec);decoded=bridge.decode_record(events)
        with self.assertRaises(InvalidTrace):replay({'version':'hwp-a/v0','documents':[decoded],'target':'d'})
    def test_wrapper_fields_exact(self):
        ev=copy.deepcopy(self.base['events']);ev[1]['extra']='hidden'
        with self.assertRaises(c.Reject):bridge.decode_record(ev)
    def test_header_order_and_marker_exact(self):
        ev=copy.deepcopy(self.base['events']);ev[0],ev[1]=ev[1],ev[0]
        with self.assertRaises(c.Reject):bridge.decode_record(ev)
    def test_attestor_lie_is_not_cryptographically_discoverable(self):
        # This exact counterexample must remain: authorized lies can pass attestation.
        rec=Builder().splice(0,0,self.base['record']['final_text'],source='paste').record()
        g=replacement_capture(self.base,rec)
        self.good(g)
        self.assertEqual(self.bad(g,recompute=True)['reason'],'hwp-not-qualifying')
    def test_normal_issuer_refuses_paste(self):
        rec=Builder().splice(0,0,TEXT*2,source='paste').record()
        with self.assertRaises((c.Reject,InvalidTrace)):make(record=rec)
    def test_normal_issuer_signs_only_recomputed_positive(self):
        f=self.base;ar=p.issue_appraisal(f['store'],f['statement'],f['policy_bytes'],f['policy_pin'],f['disclosures'],seed('evaluator'))
        self.assertEqual(ar,f['appraisal'])
    def test_zero_data_default_approval_remains_empty(self):
        po=policy_change(self.base,lambda q:q.update(purpose='production',releases=[],capture_authorities=[],evaluators=[]))
        self.bad(po)


class Inheritance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.parent=make(name='parent',claim='wording-origin')
        f=cls.parent;b=Builder('child').control('copy',from_doc='parent',start=0,end=len(f['record']['final_text']),to=0,parent_text=f['record']['final_text'])
        cls.child=make(name='child',claim='wording-origin',record=b.record(),parents=(f,),scope_ranges=[{'start':0,'end':len(f['document']),'origin':['inherited',f['proof'],0,len(f['document'])]}])
    def test_parent_and_child_actual_recomputation(self):self.assertEqual(check(self.child,recompute=True)['status'],'TEST-ONLY')
    def test_parent_and_child_same_release_do_not_replace_runner(self):
        self.assertEqual(self.parent['release'],self.child['release'])
        self.assertEqual(check(self.child,recompute=True)['status'],'TEST-ONLY')
    def test_parent_disclosure_mandatory_for_full_audit(self):
        f=self.child;d=copy.deepcopy(f['disclosures']);d['logs']=[x for x in d['logs'] if x['capture']==f['end']]
        self.assertEqual(check(f,recompute=True,disclosures=d)['status'],'NO-VALID-HWP')
    def test_copied_wording_cannot_claim_observed_creation(self):
        f=self.child;g=rescope(f,lambda sc:sc.update(ranges=[{'start':0,'end':len(f['document']),'origin':['observed',f['captures']]}]))
        d=copy.deepcopy(g['disclosures']);d['lineage_salts'][-1]['statement']=g['statement']
        self.assertEqual(check(g,recompute=True,disclosures=d)['status'],'NO-VALID-HWP')
    def test_fresh_claim_refuses_copied_paragraph(self):
        f=self.parent;b=Builder('new').control('copy',from_doc='parent',start=0,end=len(f['record']['final_text']),to=0,parent_text=f['record']['final_text'])
        with self.assertRaises(c.Reject):make(name='new',record=b.record(),parents=(f,))
    def test_parent_range_not_arbitrary_same_bytes(self):
        g=rescope(self.child,lambda sc:sc['ranges'][0].update(origin=['inherited',self.parent['proof'],1,len(self.parent['document'])+1]))
        self.assertEqual(check(g)['status'],'NO-VALID-HWP')


class CryptoMechanics(unittest.TestCase):
    def test_rfc8032_known_answer(self):
        seed_=bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')
        self.assertEqual(c.public_key(seed_).hex(),'d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')
    def test_all_small_merkle_inclusion_consistency(self):
        for n in range(1,32):
            leaves=[c.digest(str(i).encode()) for i in range(n)];root=c.tree_root(leaves)
            for i in range(n):self.assertTrue(c.verify_inclusion(leaves[i],i,n,c.inclusion(leaves,i),root))
            for m in range(1,n+1):self.assertTrue(c.verify_consistency(m,n,c.tree_root(leaves[:m]),root,c.consistency(leaves,m)))
    def test_cose_roundtrip_and_domain_separation(self):
        key=c.key_bytes(c.public_key(seed('primitive')));body={'v':c.VERSION,'type':'test','text':'é'};raw=c.sign(body,seed('primitive'))
        self.assertEqual(c.verify_signature(raw,key)[0],body)
        bad=c.decode(raw);pr,uh,payload,sig=bad.value;altered=bytearray(sig);altered[0]^=1
        with self.assertRaises(c.Reject):c.verify_signature(c.encode(c.Tag(18,[pr,uh,payload,bytes(altered)])),key)
    def test_strict_decoding_examples(self):
        for raw in [b'\x18\x00',b'\x9f\xff',b'\xa2\x01\x00\x01\x00',b'\xf9\x00\x00',b'\x00\x00',b'\x61\xff']:
            with self.subTest(raw=raw.hex()),self.assertRaises(c.Reject):c.decode(raw)
    def test_cborkeys_core_not_length_first(self):
        self.assertEqual(c.encode({24:1,-1:2}).hex(),'a21818012002')
    def test_unsafe_public_key_points(self):
        for raw in [bytes(32),b'\x01'+bytes(31),b'\xff'*32]:self.assertFalse(c.valid_point(raw))
    def test_large_integer_encoding_boundaries(self):
        for n in [-2**63,-2**32,-1,0,23,24,255,256,2**53,2**64-1]:self.assertEqual(c.decode(c.encode(n)),n)
    def test_salts_and_index_bind_leaf(self):
        e=c.encode({'kind':'test'});s=seed('start');r=seed('salt')
        self.assertNotEqual(c.leaf(s,0,r,e),c.leaf(s,1,r,e))
        self.assertNotEqual(c.leaf(s,0,r,e),c.leaf(seed('otherstart'),0,r,e))
    def test_no_same_salt_in_commit(self):
        with self.assertRaises(c.Reject):c.commit_events(c.ref(b'start'),[{'kind':'header'},{'kind':'end'}],[bytes(32)]*2)
    def test_strict_signature_scalar(self):
        raw=c.sign({'v':c.VERSION,'type':'test'},seed('primitive'));o=c.decode(raw);sig=o.value[-1]
        o.value[-1]=sig[:32]+(2**255).to_bytes(32,'little')
        with self.assertRaises(c.Reject):c.verify_signature(c.encode(o),c.key_bytes(c.public_key(seed('primitive'))))

class PrivateTransport(unittest.TestCase):
    def test_chunked_roundtrip_and_recomputation(self):
        from hwp0.disclosure import pack,unpack
        f=make(name='chunks');raw=pack(f['disclosures']);opened=unpack(raw)
        self.assertEqual(check(f,disclosures=opened,recompute=True)['status'],'TEST-ONLY')
        st,root=c.Store.unpack(raw);manifest=st.obj(root)
        self.assertEqual(len(manifest['logs'][0]['parts']),5)
    def test_private_transport_is_not_a_proof(self):
        from hwp0.disclosure import pack
        f=make();self.assertEqual(check(f,bundle=pack(f['disclosures']))['status'],'NO-VALID-HWP')
    def test_bad_chunk_offset(self):
        from hwp0.disclosure import pack,unpack
        f=make();st,root=c.Store.unpack(pack(f['disclosures']));m=st.obj(root);rr=m['logs'][0]['parts'][0];block=st.obj(rr);block['offset']=1
        m['logs'][0]['parts'][0]=st.put(block);nr=st.put(m)
        with self.assertRaises(c.Reject):unpack(st.pack(nr))
    def test_native_input_control_focus_gate(self):
        b=Builder().type(TEXT);b.time+=1000;b.observation('focus_out',b.time,'out');b.control('navigate',start=0,end=0)
        with self.assertRaises(InvalidTrace):replay(b.bundle())

class StudyBoundary(unittest.TestCase):
    def test_missing_model_is_not_a_rejected_attack(self):
        from hwp0.algorithm.ledger import run_ledger
        with self.assertRaises(InvalidTrace):run_ledger({},[],None,{},[0])
    def test_metrics_claim_kind_is_explicit(self):
        from hwp0.algorithm.metrics import evaluate_cases
        r=evaluate_cases([],{}, {},0,'wording-origin');self.assertEqual(r['claim_kind'],'wording-origin')

class ApprovalStaging(unittest.TestCase):
    def candidate(self):
        f=make(name='approval');st=f['store'];rel=st.obj(f['release']);d=st.obj(rel['validation'])
        reports=[{'role':role,'artifact':st.add(('SYNTHETIC TEST REPORT, NOT EMPIRICAL EVIDENCE: '+role).encode())} for role in p.REPORT_ROLES]
        d.update(stage='empirical',reports=reports,candidate=f['release']);er=st.put(dict(rel,stage='empirical',validation=st.put(d)))
        g=policy_change(f,lambda po:po.update(releases=c.reference_list(po['releases']+[er])))
        return g,er
    def test_inspecting_candidate_does_not_approve_it(self):
        f,er=self.candidate();v=p.ProtocolVerifier(f['store'],f['policy_bytes'],f['policy_pin']);v.check_release(er)
        # Still conformance purpose: fake reports and fixture paths never yield HWP.
        self.assertEqual(check(f)['status'],'TEST-ONLY')
    def test_candidate_tuple_must_match(self):
        f,er=self.candidate();st=f['store'];rel=st.obj(er);d=st.obj(rel['validation']);can=st.obj(d['candidate']);can['claim']='wording-origin';d['candidate']=st.put(can);rel['validation']=st.put(d);bad=st.put(rel)
        f=policy_change(f,lambda po:po.update(releases=c.reference_list(po['releases']+[bad])))
        with self.assertRaises(c.Reject):p.ProtocolVerifier(st,f['policy_bytes'],f['policy_pin']).check_release(bad)
    def test_candidate_is_not_itself_empirical(self):
        f,er=self.candidate();st=f['store'];rel=st.obj(er);d=st.obj(rel['validation']);d['candidate']=er;rel['validation']=st.put(d);bad=st.put(rel)
        f=policy_change(f,lambda po:po.update(releases=c.reference_list(po['releases']+[bad])))
        with self.assertRaises(c.Reject):p.ProtocolVerifier(st,f['policy_bytes'],f['policy_pin']).check_release(bad)
    def test_conformance_cannot_contain_candidate_pointer(self):
        f=make();st=f['store'];r=st.obj(f['release']);d=st.obj(r['validation']);d['candidate']=f['release'];r['validation']=st.put(d);bad=st.put(r)
        f=policy_change(f,lambda po:po.update(releases=c.reference_list(po['releases']+[bad])))
        with self.assertRaises(c.Reject):p.ProtocolVerifier(st,f['policy_bytes'],f['policy_pin']).check_release(bad)
