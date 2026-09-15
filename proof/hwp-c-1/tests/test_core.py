import copy
import ctypes
import ctypes.util
import hashlib
import json
import random
import unittest
import hwp_crypto as h
from fixtures import make,check,seed,change_policy,change_statement

class Encoding(unittest.TestCase):
    def test_roundtrip(self):
        cases=[0,23,24,255,256,65535,65536,2**32,2**64-1,-1,-24,-25,-2**63,True,False,None,b'',b'abc','é\r\n',[1,False],{1:'a',-1:b'k','z':None},h.Tag(18,[b'',{},b'',bytes(64)])]
        for x in cases: self.assertEqual(h.decode(h.encode(x)),x)
    def test_rfc8949_examples(self):
        for raw,val in [('00',0),('1818',24),('1903e8',1000),('20',-1),('3863',-100),('f4',False),('f6',None),('6449455446','IETF'),('83010203',[1,2,3])]: self.assertEqual(h.encode(val).hex(),raw)
    def test_core_not_length_first(self):
        self.assertEqual(h.encode({-1:0,24:0}).hex(),'a21818002000')
    def test_reject_noncanonical(self):
        bad=['1800','190018','a201000101','a202000100','9f01ff','5f4101ff','fa00000000','f7','c001','f818','0000','63eda080','a1f400','1b0000000000000001','3bffffffffffffffff']
        for raw in bad:
            with self.subTest(raw=raw), self.assertRaises(h.Reject): h.decode(bytes.fromhex(raw))
    def test_reject_truncated(self):
        raw=h.encode({'a':[1,2,b'longer byte string']})
        for i in range(len(raw)):
            with self.assertRaises(h.Reject): h.decode(raw[:i])
    def test_reject_floats_surrogates(self):
        for x in [float('nan'),1.0,'\ud800',{True:1},(1,2)]:
            with self.assertRaises(h.Reject): h.encode(x)
    def test_depth(self):
        x=0
        for _ in range(40): x=[x]
        with self.assertRaises(h.Reject): h.encode(x)
    def test_random_roundtrips(self):
        r=random.Random(741)
        for _ in range(1000):
            x={'a':r.randrange(-10**12,10**12),'b':[r.randbytes(8),bool(r.randrange(2)),None],'c':'é😀'}
            self.assertEqual(h.decode(h.encode(x)),x)

class Signatures(unittest.TestCase):
    def test_rfc8032_empty_message(self):
        sk=bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')
        pub=bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')
        sig=bytes.fromhex('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b')
        self.assertEqual(h.public_key(sk),pub)
        self.assertEqual(h.Ed25519PrivateKey.from_private_bytes(sk).sign(b''),sig)
        self.assertTrue(h.valid_point(pub)); self.assertTrue(h.valid_point(sig[:32]))
    def test_cose_roundtrip(self):
        payload={'v':h.VERSION,'type':'test','value':'é'}; k=h.key_bytes(h.public_key(seed('s')))
        envelope=h.sign(payload,seed('s'))
        self.assertEqual(h.verify_signature(envelope,k),(payload,h.digest(k)))
    def test_all_signature_byte_mutations(self):
        k=h.key_bytes(h.public_key(seed('s'))); env=h.decode(h.sign({'v':h.VERSION,'type':'test'},seed('s')))
        for i in range(64):
            x=copy.deepcopy(env); sig=bytearray(x.value[3]); sig[i]^=1; x.value[3]=bytes(sig)
            with self.assertRaises(h.Reject): h.verify_signature(h.encode(x),k)
    def test_algorithm_downgrade(self):
        k=h.key_bytes(h.public_key(seed('s'))); env=h.decode(h.sign({'v':h.VERSION,'type':'test'},seed('s')))
        p=h.decode(env.value[0]); p[1]=-8; env.value[0]=h.encode(p)
        with self.assertRaises(h.Reject): h.verify_signature(h.encode(env),k)
    def test_unprotected_header(self):
        k=h.key_bytes(h.public_key(seed('s'))); env=h.decode(h.sign({'v':h.VERSION,'type':'test'},seed('s'))); env.value[1][4]=b'x'
        with self.assertRaises(h.Reject): h.verify_signature(h.encode(env),k)
    def test_bad_key_points(self):
        for pub in [bytes(32),b'\x01'+bytes(31),((1<<255)-19).to_bytes(32,'little'),((1<<255)+1).to_bytes(32,'little')]:
            self.assertFalse(h.valid_point(pub))
            with self.assertRaises(h.Reject): h.key_bytes(pub)
    def test_mixed_order_key(self):
        # Add the order-two point (0,-1) to a valid public point: (x,y)->(-x,-y).
        raw=h.public_key(seed('x')); n=int.from_bytes(raw,'little'); y=n&((1<<255)-1); sign=n>>255
        mixed=((h._P-y)%h._P | ((1-sign)<<255)).to_bytes(32,'little')
        self.assertFalse(h.valid_point(mixed))
    def test_scalar_malleability(self):
        k=h.key_bytes(h.public_key(seed('s'))); env=h.decode(h.sign({'v':h.VERSION,'type':'test'},seed('s')))
        sig=env.value[3]; env.value[3]=sig[:32]+(int.from_bytes(sig[32:],'little')+h._L).to_bytes(32,'little')
        with self.assertRaises(h.Reject): h.verify_signature(h.encode(env),k)
    def test_cross_backend_libsodium(self):
        lib=ctypes.CDLL(ctypes.util.find_library('sodium')); lib.sodium_init()
        fn=lib.crypto_sign_verify_detached; fn.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_ulonglong,ctypes.c_char_p]; fn.restype=ctypes.c_int
        for i in range(20):
            sk=seed('cross'+str(i)); pub=h.public_key(sk); msg=hashlib.sha512(str(i).encode()).digest()*i
            sig=h.Ed25519PrivateKey.from_private_bytes(sk).sign(msg)
            self.assertEqual(fn(sig,msg,len(msg),pub),0)
            self.assertNotEqual(fn(sig,msg+b'x',len(msg)+1,pub),0)

class Merkle(unittest.TestCase):
    def test_all_small_inclusions(self):
        for n in range(1,66):
            leaves=[h.digest(b'\x00'+str(i).encode()) for i in range(n)]; root=h.tree_root(leaves)
            for i in range(n):
                p=h.inclusion(leaves,i)
                self.assertTrue(h.verify_inclusion(leaves[i],i,n,p,root))
                self.assertFalse(h.verify_inclusion(leaves[i],i,n,p+[bytes(32)],root))
    def test_all_small_consistency(self):
        for n in range(1,66):
            leaves=[h.digest(b'\x00'+str(i).encode()) for i in range(n)]
            for m in range(1,n+1):
                p=h.consistency(leaves,m)
                self.assertTrue(h.verify_consistency(m,n,h.tree_root(leaves[:m]),h.tree_root(leaves),p),(m,n))
                self.assertFalse(h.verify_consistency(m,n,bytes(32),h.tree_root(leaves),p))
    def test_empty_consistency(self):
        self.assertTrue(h.verify_consistency(0,0,h.digest(b''),h.digest(b''),[]))
        self.assertFalse(h.verify_consistency(0,0,h.digest(b''),bytes(32),[]))
    def test_domain_separation(self):
        event=h.encode({'kind':'record','x':1}); r=seed('start'); salt=seed('salt')
        self.assertNotEqual(h.leaf(r,0,salt,event),h.leaf(r,1,salt,event))
        self.assertNotEqual(h.leaf(r,0,salt,event),h.leaf(seed('other'),0,salt,event))
    def test_complete_opening(self):
        f=make(); end,_=f['store'].signed(f['end'])
        self.assertEqual(h.open_transcript(f['start'],end['count'],end['root'],f['openings']),f['events'])
    def test_opening_truncation(self):
        f=make(); end,_=f['store'].signed(f['end'])
        with self.assertRaises(h.Reject): h.open_transcript(f['start'],end['count'],end['root'],f['openings'][:-1])
    def test_event_reorder(self):
        f=make(); end,_=f['store'].signed(f['end']); o=copy.deepcopy(f['openings']); o[0],o[1]=o[1],o[0]
        with self.assertRaises(h.Reject): h.open_transcript(f['start'],end['count'],end['root'],o)
    def test_salt_reuse(self):
        with self.assertRaises(h.Reject): h.commit_events(h.ref(b'start'),[{},{}],[bytes(32),bytes(32)])
    def test_lineage_salt(self):
        self.assertNotEqual(h.lineage_commitment(seed('1'),b'x'),h.lineage_commitment(seed('2'),b'x'))

class Protocol(unittest.TestCase):
    def test_anonymous_private(self): self.assertEqual(check(make())['status'],'VALID-HWP')
    def test_attributed_private(self): self.assertEqual(check(make(author=True))['author'],'pseudonymous-key-endorsement')
    def test_identified_private(self): self.assertEqual(check(make(author=True,identity=True))['author']['kind'],'attested-key-controller')
    def test_selected_ranges(self): self.assertEqual(check(make(selected=True))['scope'],'selected-ranges')
    def test_disclosed(self): self.assertEqual(check(make(mode='disclosed-v1'))['status'],'VALID-HWP')
    def test_no_external_policy(self): self.assertEqual(h.verify_bundle(make()['bundle'],make()['document'])['status'],'NO-VALID-HWP')
    def test_policy_pin(self): self.assertEqual(check(make(),expected_policy_digest=bytes(32))['reason'],'external-policy-pin')
    def test_exact_newline(self):
        f=make(); self.assertEqual(check(f,document=f['document'].replace(b'\n',b'\r\n'))['status'],'NO-VALID-HWP')
    def test_unicode_no_normalization(self):
        f=make(); self.assertEqual(check(f,document=f['document'].replace('é'.encode(),'e\u0301'.encode()))['status'],'NO-VALID-HWP')
    def test_statement_without_resign(self):
        f=change_statement(make(),lambda s:s.update(nonce=seed('changed')),False)
        self.assertEqual(check(f)['reason'],'appraisal-result-or-statement')
    def test_unknown_signer(self):
        f=change_statement(make(),lambda s:s.update(nonce=seed('changed')),True,'untrusted')
        self.assertEqual(check(f)['reason'],'evaluator-role-or-duplicate')
    def test_no_mode_fallback(self):
        f=change_statement(make(),lambda s:s.update(mode='zk-unregistered'))
        self.assertEqual(check(f)['reason'],'execution-mode-not-authorized')
    def test_missing_runner(self):
        self.assertEqual(check(make(mode='disclosed-v1'),runners={})['reason'],'no-independently-installed-runner')
    def test_disclosed_bad_output(self):
        f=make(mode='disclosed-v1')
        self.assertEqual(check(f,runners={f['release']['sha256']:lambda *_:True})['reason'],'recomputed-output-mismatch')
    def test_disclosure_missing(self):
        self.assertEqual(check(make(mode='disclosed-v1'),disclosures={'logs':[],'lineage_salts':[]})['reason'],'missing-disclosed-session')
    def test_disclosure_changed(self):
        f=make(mode='disclosed-v1'); f['openings'][1]['event']=h.encode({'kind':'record','text':'changed'})
        self.assertEqual(check(f)['reason'],'transcript-root')
    def test_quorum_removal(self):
        f=change_policy(make(),lambda p:p.update(quorum=2)); self.assertEqual(check(f)['reason'],'evaluator-quorum')
    def test_quorum_success(self):
        f=change_policy(make(),lambda p:p.update(quorum=2)); st=f['store']; p=st.obj(f['proof'])
        second=h.sign_appraisal(st,f['statement'],f['computed'],seed('evaluator2')); p['appraisals']=h.reference_list([f['appraisal'],second]); f['bundle']=st.pack(st.put(p))
        self.assertEqual(check(f)['status'],'VALID-HWP')
    def test_duplicate_quorum(self):
        f=make(); st=f['store']; p=st.obj(f['proof']); p['appraisals']*=2; f['bundle']=st.pack(st.put(p))
        self.assertEqual(check(f)['reason'],'reference-order-or-duplicate')
    def test_denied_evaluator(self):
        f=make(); change_policy(f,lambda p:p.update(denied=[f['keys']['evaluator']['sha256']]))
        self.assertEqual(check(f)['reason'],'denied-key')
    def test_denied_model(self):
        f=make(); change_policy(f,lambda p:p.update(denied=[f['artifacts']['model']['sha256']]))
        self.assertEqual(check(f)['reason'],'denied-object')
    def test_capture_authority_not_author(self):
        f=make(); change_policy(f,lambda p:p['capture_authorities'][0].update(keys=[f['keys']['author']]))
        self.assertEqual(check(f)['reason'],'capture-authority')
    def test_author_strip(self):
        f=make(author=True); st=f['store']; p=st.obj(f['proof']); p['author']=None; f['bundle']=st.pack(st.put(p))
        self.assertEqual(check(f)['reason'],'missing-author-endorsement')
    def test_after_the_fact_author(self):
        f=make(); change_statement(f,lambda s:s.update(author=f['keys']['author']))
        self.assertEqual(check(f)['reason'],'observed-subject-binding')
    def test_untrusted_identity(self):
        f=change_policy(make(author=True,identity=True),lambda p:p.update(identity_authorities=[]))
        self.assertEqual(check(f)['reason'],'identity-authority')
    def test_missing_artifact(self):
        f=make(); del f['store'].objects[f['artifacts']['model']['sha256']]; f['bundle']=f['store'].pack(f['proof'])
        self.assertEqual(check(f)['reason'],'missing-object')
    def test_blob_alteration(self):
        f=make(); b=h.decode(f['bundle']); b['objects'][0][1]+=b'x'
        self.assertEqual(check(f,bundle=h.encode(b))['reason'],'object-digest')
    def test_unknown_scope_field(self):
        f=make(); st=f['store']; scope=st.obj(f['scope']); scope['approved']=True
        change_statement(f,lambda s:s.update(scope=st.put(scope)))
        self.assertEqual(check(f)['reason'],'object-fields')
    def test_scope_gap(self):
        f=make(); st=f['store']; scope=st.obj(f['scope']); scope['ranges'][0]['start']=1
        change_statement(f,lambda s:s.update(scope=st.put(scope)))
        self.assertEqual(check(f)['reason'],'scope-partition')
    def test_scope_multibyte_boundary(self):
        f=make(selected=True); st=f['store']; scope=st.obj(f['scope']); scope['ranges'][0]['end']=4; scope['ranges'][1]['start']=4
        change_statement(f,lambda s:s.update(scope=st.put(scope)))
        self.assertEqual(check(f)['reason'],'scope-partition')
    def test_whole_scope_lie(self):
        f=make(selected=True); st=f['store']; scope=st.obj(f['scope']); scope['kind']='whole-document'
        change_statement(f,lambda s:s.update(scope=st.put(scope)))
        self.assertEqual(check(f)['reason'],'whole-document-scope')
    def test_all_excluded(self):
        f=make(); st=f['store']; scope=st.obj(f['scope']); scope['kind']='selected-ranges'; scope['ranges'][0]['origin']=['excluded','all']
        change_statement(f,lambda s:s.update(scope=st.put(scope)))
        self.assertEqual(check(f)['reason'],'scope-completeness-or-vacuity')
    def test_refuse_negative_issuance(self):
        f=make(); result=copy.deepcopy(f['computed']); result['result']='NOT PROVABLE'
        with self.assertRaises(h.Reject): h.sign_appraisal(f['store'],f['statement'],result,seed('evaluator'))
    def test_positive_assembly(self):
        f=make(); r,b=h.assemble_proof(f['store'],f['statement'],[f['appraisal']],None,f['document'],f['policy_bytes'],f['policy_digest'])
        self.assertEqual(r,f['proof']); self.assertEqual(b,f['bundle'])
    def test_negative_assembly(self):
        f=make()
        with self.assertRaises(h.Reject): h.assemble_proof(f['store'],f['statement'],[f['appraisal']],None,b'wrong',f['policy_bytes'],f['policy_digest'])
    def test_archive_binds_actual_bytes(self):
        f=make(); a=h.archive_inventory(f['bundle'],f['policy_bytes'],[b'prior timestamp'])
        b=h.archive_inventory(f['bundle'],f['policy_bytes'],[b'other timestamp'])
        self.assertNotEqual(a,b); o=h.decode(a)
        for sha,raw in o['sha512_objects']: self.assertEqual(sha,hashlib.sha512(raw).digest())
    def test_private_bundle_has_no_history_or_salts(self):
        f=make(); self.assertNotIn(b'NOT real human telemetry',f['bundle'])
        for salt in f['salts']: self.assertNotIn(salt,f['bundle'])
    def test_malformed_public_api(self):
        f=make()
        for raw in [b'',b'\xff',None,b'\xa1\x01\x01']:
            out=check(f,bundle=raw); self.assertEqual(out['status'],'NO-VALID-HWP'); self.assertIsNone(out['authorship_inference'])



class BindingRegressions(unittest.TestCase):
    def test_capture_truncation_signed_by_wrong_key(self):
        f=make(); st=f['store']; end,_=st.signed(f['end']); end['count']-=1
        altered=st.add(h.sign(end,seed('untrusted')))
        change_statement(f,lambda s:s.update(captures=[altered],target_capture=altered))
        self.assertEqual(check(f)['reason'],'capture-key-changed')
    def test_signed_capture_equivocation(self):
        f=make(); st=f['store']; end,_=st.signed(f['end']); end['root']=seed('different-root')
        altered=st.add(h.sign(end,seed('capture')))
        change_statement(f,lambda s:s.update(captures=h.reference_list([f['end'],altered])))
        self.assertEqual(check(f)['reason'],'capture-equivocation-in-bundle')
    def test_false_complete_flag(self):
        f=make(); st=f['store']; end,_=st.signed(f['end']); end['complete']=False
        altered=st.add(h.sign(end,seed('capture')))
        change_statement(f,lambda s:s.update(captures=[altered],target_capture=altered))
        self.assertEqual(check(f)['reason'],'capture-not-complete')
    def test_capture_participation_required(self):
        f=make(author=True); st=f['store']; end,_=st.signed(f['end']); end['participation']=None
        altered=st.add(h.sign(end,seed('capture')))
        change_statement(f,lambda s:s.update(captures=[altered],target_capture=altered))
        self.assertEqual(check(f)['reason'],'missing-participation')
    def test_same_role_key_is_not_independence(self):
        f=make(); change_policy(f,lambda p:p.update(evaluators=[f['keys']['capture']]))
        change_statement(f,lambda s:s.update(nonce=seed('role')),seedname='capture')
        self.assertEqual(check(f)['reason'],'capture-evaluator-key-separation')
    def test_replay_same_valid_proof_is_valid(self):
        f=make(); self.assertEqual(check(f),check(f))
        # Replay protection must not make archived proof verification one-use.
    def test_negative_signed_result_is_not_certificate(self):
        f=make(); st=f['store']; p=st.obj(f['proof'])
        p['appraisals']=[st.add(h.sign({'v':h.VERSION,'type':'appraisal','statement':f['statement'],'result':'NOT PROVABLE'},seed('evaluator')))]
        f['bundle']=st.pack(st.put(p)); self.assertEqual(check(f)['reason'],'appraisal-result-or-statement')
    def make_inherited(self,parent_selected=False,claim='wording-origin'):
        parent=make(name='parent',selected=parent_selected); f=make(name='child'); st=f['store']
        for raw in parent['store'].objects.values(): st.add(raw)
        release=st.obj(f['release']); release['claim']=claim; rr=st.put(release)
        scope=st.obj(f['scope']); scope['ranges'][0]['origin']=['inherited',parent['proof'],0,len(f['document'])]; sr=st.put(scope)
        change_statement(f,lambda s:s.update(release=rr,scope=sr))
        change_policy(f,lambda p:p.update(releases=h.reference_list([parent['release'],rr]) if rr!=parent['release'] else [rr]))
        return f
    def test_inherited_wording_success(self):
        out=check(self.make_inherited()); self.assertEqual(out['status'],'VALID-HWP'); self.assertEqual(out['claim'],'wording-origin')
    def test_inherited_cannot_claim_fresh(self):
        self.assertEqual(check(self.make_inherited(claim='fresh-composition'))['reason'],'inherited-not-fresh')
    def test_uncertified_parent_range(self):
        self.assertEqual(check(self.make_inherited(parent_selected=True))['reason'],'parent-range-not-certified')
    def test_extraneous_bundle_object_not_trust(self):
        f=make(); f['store'].put({'approved':True,'issuer':'anyone'}); f['bundle']=f['store'].pack(f['proof'])
        self.assertEqual(check(f)['status'],'VALID-HWP')
        change_policy(f,lambda p:p.update(evaluators=[f['keys']['untrusted']]))
        self.assertEqual(check(f)['status'],'NO-VALID-HWP')

class VoluntaryAudit(unittest.TestCase):
    def test_full_audit_without_changing_certificate(self):
        f=make(); base=check(f); audited=check(f,force_recompute=True)
        self.assertEqual(base['proof'],audited['proof']); self.assertEqual(audited['mode'],'attested-v1'); self.assertEqual(audited['execution_checked'],'recomputed')
    def test_audit_requires_all_evidence(self):
        self.assertEqual(check(make(),force_recompute=True,disclosures={})['status'],'NO-VALID-HWP')
    def test_audit_cannot_accept_mismatch(self):
        f=make(); self.assertEqual(check(f,force_recompute=True,runners={f['release']['sha256']:lambda *_:{}})['reason'],'recomputed-output-mismatch')

class TargetBinding(unittest.TestCase):
    def test_unknown_target_capture(self):
        f=make(); change_statement(f,lambda s:s.update(target_capture=h.ref(b'other')))
        self.assertEqual(check(f)['reason'],'target-capture-binding')
    def test_missing_lineage_randomness(self):
        f=make(mode='disclosed-v1'); f['disclosures']['lineage_salts']=[]
        self.assertEqual(check(f)['reason'],'missing-lineage-salt')
    def test_wrong_lineage_randomness(self):
        f=make(mode='disclosed-v1'); f['disclosures']['lineage_salts'][0]['salt']=seed('wrong')
        self.assertEqual(check(f)['reason'],'fixture-runner-input')
    def test_computed_target_cannot_be_substituted(self):
        f=make(); computed=dict(f['computed']); computed['target_capture']=h.ref(b'other')
        with self.assertRaises(h.Reject): h.sign_appraisal(f['store'],f['statement'],computed,seed('evaluator'))

class StrictReferenceAndResourceTests(unittest.TestCase):
    def test_cached_proof_reference_size_rechecked(self):
        f=make(); v=h.Verifier(f['store'],f['policy_bytes'],f['policy_digest'])
        v.verify(f['proof']); bad=dict(f['proof']); bad['size']+=1
        with self.assertRaises(h.Reject): v.verify(bad)
    def test_evaluator_grant_size_checked(self):
        f=make(); change_policy(f,lambda p:next(r for r in p['evaluators'] if r['sha256']==f['keys']['evaluator']['sha256']).update(size=1))
        self.assertEqual(check(f)['status'],'NO-VALID-HWP')
    def test_capture_grant_size_checked(self):
        f=make(); change_policy(f,lambda p:p['capture_authorities'][0]['keys'][0].update(size=1))
        self.assertEqual(check(f)['status'],'NO-VALID-HWP')
    def test_identity_grant_size_checked(self):
        f=make(author=True,identity=True); change_policy(f,lambda p:p['identity_authorities'][0].update(size=1))
        self.assertEqual(check(f)['status'],'NO-VALID-HWP')
    def test_oversize_document(self):
        f=make(); huge=f['store'].add(b'a'*(h.MAX_DOCUMENT_BYTES+1)); change_statement(f,lambda s:s.update(document=huge))
        self.assertEqual(check(f,document=b'a'*(h.MAX_DOCUMENT_BYTES+1))['reason'],'document-size')
    def test_disclosure_budget_counts_before_running(self):
        f=make(mode='disclosed-v1'); f['disclosures']['logs'][0]['openings']*=333334
        self.assertEqual(check(f)['reason'],'disclosure-event-budget')

if __name__=='__main__': unittest.main()
