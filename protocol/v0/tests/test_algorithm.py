"""Synthetic conformance/regression tests, not measured human-detection accuracy."""
import copy
import json
import unittest
from random import Random
from dataclasses import replace
from hwp0.algorithm.replay import *
from hwp0.algorithm.fixtures import Builder,TEXT,permissive_fixture_model
from hwp0.algorithm.features import extract,adequate,FEATURE_NAMES
from hwp0.algorithm.model import validate_model,fit,HEADS,evaluate,domain,validate_splits,SCORE_FLOOR
from hwp0.algorithm.verify import score,verify,decide,TrustedInputs,snapshot
from hwp0.algorithm.dataset import extract_dataset,extract_case,false_mask,risk_record
from hwp0.algorithm.ledger import validate_ledger,evaluate_ledger,run_ledger
from hwp0.algorithm.release import evaluation_cells
from hwp0.algorithm.attacks import adaptive_retiming,retime,staged_transcription
from hwp0.algorithm.__main__ import pairs


def context(b,m,approve=False,claim='fresh-composition'):
    # A test controller's explicit conditional assumptions. Not real capture evidence.
    return TrustedInputs(frozenset(d['id'] for d in b['documents']),approve,0,
                         frozenset(m['domains']),frozenset((d['id'],snapshot(d)) for d in b['documents']),
                         frozenset(d['id'] for d in b['documents']),snapshot(m),claim)

def prepared(builder=None,claim='fresh-composition'):
    b=(builder or Builder().type(TEXT)).bundle();m=permissive_fixture_model(b)
    m['purpose']='validated-release'  # Only a permissive synthetic double.
    return b,m,context(b,m,True,claim)


def edit_delivery(b,idx):
    """Synchronize a deliberately synthetic counterexample, not legacy capture migration."""
    d=b['documents'][0];tx=d['transactions'][idx]
    d['observations'][tx['delivery']]['effect']={k:v for k,v in tx.items() if k not in ('i','t','seq','delivery')}


def case(label='H',builder=None,cid='case',split='train'):
    b=(builder or Builder().type(TEXT)).bundle()
    return {'id':cid,'cluster':cid,'split':split,'links':{},'bundle':b,
            'labels':[{'document':d['id'],'start_tx':0,'end_tx':len(d['transactions']),'label':label}
                      for d in b['documents'] if d['transactions']], 'condition':'SYNTHETIC'}


class TimelineTests(unittest.TestCase):
    def test_four_profiles(self):
        for profile in PROFILES:
            with self.subTest(profile=profile):
                b,m,c=prepared(Builder(profile=profile).type(TEXT))
                self.assertEqual(replay(b).documents['d'].text,TEXT)
                self.assertEqual(verify(b,m,0,c)['verdict'],'HUMAN-WRITTEN')
    def test_total_order_contiguous(self):
        b=Builder().type('abc').bundle();d=b['documents'][0]
        self.assertEqual(sorted(x['seq'] for x in d['observations']+d['transactions']),list(range(12)))
    def test_future_equal_tick_cause_rejected(self):
        b=Builder().type('a').bundle();d=b['documents'][0];tx=d['transactions'][0];cause=d['observations'][0]
        tx['seq'],cause['seq']=cause['seq'],tx['seq']
        with self.assertRaises(InvalidTrace):replay(b)
    def test_duplicate_global_seq(self):
        b=Builder().type('a').bundle();b['documents'][0]['observations'][1]['seq']=0
        with self.assertRaises(InvalidTrace):replay(b)
    def test_missing_delivery(self):
        b=Builder().type('a').bundle();del b['documents'][0]['transactions'][0]['delivery']
        with self.assertRaises(InvalidTrace):replay(b)
    def test_delivery_effect_mismatch(self):
        b=Builder().type('a').bundle();b['documents'][0]['transactions'][0]['text']='b';b['documents'][0]['final_text']='b'
        with self.assertRaises(InvalidTrace):replay(b)
    def test_delivery_bool_not_int_equivalence(self):
        b=Builder().type('a').bundle();b['documents'][0]['observations'][1]['effect']['start']=False
        with self.assertRaises(InvalidTrace):replay(b)
    def test_unused_delivery(self):
        b=Builder().type('a').bundle();d=b['documents'][0];tx=d['transactions'].pop();d['final_text']=''
        events=sorted(d['observations'],key=lambda x:x['seq'])
        for i,x in enumerate(events):x['seq']=i
        with self.assertRaises(InvalidTrace):replay(b)
    def test_old_version_not_upgraded(self):
        b=Builder().type('a').bundle();b['version']='hwp-a/0.2'
        with self.assertRaises(InvalidTrace):replay(b)
    def test_cause_reuse(self):
        b=Builder().type('ab').bundle();d=b['documents'][0];d['transactions'][1]['causes']=d['transactions'][0]['causes'];edit_delivery(b,1)
        with self.assertRaises(InvalidTrace):replay(b)
    def test_resolution_quantization(self):
        b=Builder().type('a').bundle();b['documents'][0]['observations'][0]['t']+=1
        with self.assertRaises(InvalidTrace):replay(b)
    def test_synthetic_text_never_candidate(self):
        b=Builder().splice(0,0,'a',observed_source='synthetic').bundle();c=replay(b)
        self.assertFalse(c.atoms[c.documents['d'].live[0]].roots)
    def test_out_of_focus_repeat(self):
        b=Builder();t=b.time+100000
        b.observation('press',t,'p');b.observation('focus_out',t+1000,'f')
        b.observation('repeat',t+2000,'p');b.observation('focus_in',t+3000,'g');b.observation('release',t+4000,'p')
        with self.assertRaises(InvalidTrace):replay(b.bundle())
    def test_cause_crosses_focus_cycle(self):
        b=Builder();c,t=b.cause();b.observation('focus_out',t+1000,'out');b.observation('focus_in',t+2000,'in')
        b.observations.sort(key=lambda x:x['t'])
        for i,o in enumerate(b.observations):o['i']=i
        b.add('splice',0,t+40000,start=0,end=0,text='x',deleted='',source='direct');b.text='x'
        with self.assertRaises(InvalidTrace):replay(b.bundle())
    def test_ime_missing_basis(self):
        b=Builder(profile='ime').type('abc').bundle()
        next(o for o in b['documents'][0]['observations'] if o['kind']=='ime_commit')['basis']=[]
        with self.assertRaises(InvalidTrace):replay(b)
    def test_undeclared_path(self):
        b=Builder().type('abc').bundle();b['documents'][0]['paths']={'ime':'fixture-path/ime'}
        with self.assertRaises(InvalidTrace):replay(b)
    def test_domain_delimiter_rejected(self):
        b=Builder().type('abc').bundle();b['documents'][0]['language']='en|birth'
        with self.assertRaises(InvalidTrace):replay(b)
    def test_duplicate_json_keys(self):
        with self.assertRaises(ValueError):json.loads('{"x":1,"x":2}',object_pairs_hook=pairs)


class ProvenanceTests(unittest.TestCase):
    def test_numeric_spelling_not_inherited(self):
        b=Builder().type(TEXT+'100'+TEXT);p=b.text.index('100');b.splice(p,p+3,'900','spelling')
        bundle,m,ctx=prepared(b);r=verify(bundle,m,0,ctx)
        self.assertEqual(r['verdict'],'NOT PROVABLE')
        c=replay(bundle);self.assertTrue(all(not c.atoms[a].roots for a in c.documents['d'].live[p:p+3]))
    def test_letter_spelling_not_inherited(self):
        b=Builder().type(TEXT);p=b.text.index('writer');b.splice(p,p+6,'writex','spelling');c=replay(b.bundle())
        self.assertTrue(all(not c.atoms[a].roots for a in c.documents['d'].live[p:p+6]))
    def test_copy_is_not_fresh(self):
        b=Builder().type(TEXT).control('copy',from_doc='d',start=0,end=len(TEXT),to=len(TEXT))
        bundle,m,c=prepared(b);r=verify(bundle,m,0,c)
        self.assertEqual(r['verdict'],'NOT PROVABLE')
        self.assertIn('NOT_FRESH_COMPOSITION',{x['reason'] for x in r['ranges']})
    def test_copy_preserves_explicit_wording_origin(self):
        b=Builder().type(TEXT).control('copy',from_doc='d',start=0,end=len(TEXT),to=len(TEXT))
        bundle,m,c=prepared(b,'wording-origin')
        self.assertEqual(verify(bundle,m,0,c,claim_kind='wording-origin')['verdict'],'HUMAN-WRITTEN')
    def test_copy_parent_not_new_composition(self):
        a=Builder('a').type(TEXT).record();b=Builder('b').control('copy',from_doc='a',start=0,end=len(TEXT),to=0,parent_text=TEXT).bundle([a])
        m=permissive_fixture_model(b);m['purpose']='validated-release';c=context(b,m,True)
        self.assertEqual(verify(b,m,0,c)['verdict'],'NOT PROVABLE')
        c=replace(c,approved_claim='wording-origin')
        self.assertEqual(verify(b,m,0,c,claim_kind='wording-origin')['verdict'],'HUMAN-WRITTEN')
    def test_copy_identity_and_undo(self):
        b=Builder().type('abc').control('copy',from_doc='d',start=0,end=3,to=3).control('undo').control('redo')
        c=replay(b.bundle());ll=c.documents['d'].live
        self.assertNotEqual(ll[0],ll[3]);self.assertEqual(c.atoms[ll[0]].roots,c.atoms[ll[3]].roots)
    def test_external_survives_copy_move_history(self):
        b=Builder().splice(0,0,'imported','paste').control('copy',from_doc='d',start=0,end=8,to=8).control('undo').control('redo')
        c=replay(b.bundle());self.assertTrue(all(not c.atoms[a].roots for a in c.documents['d'].live))
    def test_unrelated_later_source_not_retroactive(self):
        a=Builder('a').type(TEXT).record();b=Builder('later').splice(0,0,TEXT,'paste').record()
        bundle={'version':'hwp-a/v0','documents':[a,b],'target':'a'};m=permissive_fixture_model(bundle)
        self.assertEqual(score(bundle,m,context(bundle,m))['document_score'],0)
    def test_source_after_creation_not_retroactive(self):
        b=Builder().type(TEXT).splice(len(TEXT),len(TEXT),TEXT,'paste').control('undo');c=replay(b.bundle())
        self.assertFalse(observed_source_matches(c,'d'))
    def test_source_before_retyping_veto(self):
        b=Builder().splice(0,0,TEXT,'paste').splice(0,len(TEXT),'').type(TEXT);c=replay(b.bundle())
        self.assertEqual(len(observed_source_matches(c,'d')),len(TEXT))
    def test_automated_move_blocks_new_claim(self):
        b=Builder().type(TEXT).control('move',start=0,end=8,to=50)
        o=b.observations[b.transactions[-1]['causes'][0]];o['source']='synthetic'
        bundle,m,c=prepared(b);self.assertEqual(verify(bundle,m,0,c)['verdict'],'NOT PROVABLE')
    def test_unicode_exact_bytes(self):
        s='é e\u0301 文 👩\u200d🔬\r\n';b=Builder().type(s).bundle()
        self.assertEqual(replay(b).documents['d'].text.encode(),s.encode())
        with self.assertRaises(InvalidTrace):scalar_range('é',1,2)
    def test_move_roundtrip(self):
        for a,b,to in [(1,3,4),(4,6,0),(0,2,0),(1,5,1)]:
            bb=Builder().type('abcdefgh');bb.control('move',start=a,end=b,to=to);m=bb.text
            self.assertEqual(replay(bb.bundle()).documents['d'].text,m)
            bb.control('undo');self.assertEqual(replay(bb.bundle()).documents['d'].text,'abcdefgh')
            bb.control('redo');self.assertEqual(replay(bb.bundle()).documents['d'].text,m)
    def test_quotation_changes_scope_not_scores(self):
        b=Builder().type(TEXT).splice(len(TEXT),len(TEXT),'Quote','paste');bundle,m,c=prepared(b)
        r=verify(bundle,m,0,c,excluded=[{'start':len(TEXT.encode()),'end':len((TEXT+'Quote').encode()),'source':'external'}])
        self.assertEqual(r['verdict'],'NOT PROVABLE');self.assertEqual(r['contribution_verdict'],'HUMAN-WRITTEN')
    def test_empty_whitespace_not_vacuous(self):
        for s in ('',' '*100):
            b=Builder().type(s).bundle()
            if s:
                m=permissive_fixture_model(b);m['purpose']='validated-release'
                self.assertEqual(verify(b,m,0,context(b,m,True))['verdict'],'NOT PROVABLE')
            else:self.assertEqual(verify(b)['verdict'],'NOT PROVABLE')
    def test_random_replay_differential(self):
        rng=Random(723)
        for _ in range(40):
            b=Builder()
            for _ in range(50):
                a=rng.randrange(len(b.text)+1);end=rng.randrange(a,len(b.text)+1);new=rng.choice(('abc','é','文','\n','','x'))
                if a==end and not new:new='x'
                b.splice(a,end,new)
            self.assertEqual(replay(b.bundle()).documents['d'].text,b.text)


class AdmissionAndModelTests(unittest.TestCase):
    def test_no_default_approval(self):
        b,m,c=prepared();self.assertEqual(verify(b,m)['verdict'],'NOT PROVABLE')
    def test_old_boolean_not_sufficient(self):
        b,m,c=prepared();old=TrustedInputs(c.admissible_documents,True,0,c.allowed_domains)
        self.assertEqual(verify(b,m,0,old)['verdict'],'NOT PROVABLE')
    def test_model_substitution(self):
        b,m,c=prepared();m['domains'][next(iter(m['domains']))]['heads']['mixed'][0]['value']=1
        self.assertEqual(verify(b,m,0,c)['verdict'],'NOT PROVABLE')
    def test_capture_substitution_same_id(self):
        b,m,c=prepared();b['documents'][0]['resolution_us']=1
        self.assertEqual(verify(b,m,0,c)['verdict'],'NOT PROVABLE')
    def test_missing_freshness(self):
        b,m,c=prepared();self.assertEqual(verify(b,m,0,replace(c,fresh_documents=frozenset()))['verdict'],'NOT PROVABLE')
    def test_claim_approval_not_transferable(self):
        b,m,c=prepared();self.assertEqual(verify(b,m,0,c,claim_kind='wording-origin')['verdict'],'NOT PROVABLE')
    def test_threshold_approval_not_transferable(self):
        b,m,c=prepared();self.assertEqual(verify(b,m,-1,c)['verdict'],'NOT PROVABLE')
    def test_bool_threshold_not_approved(self):
        b,m,c=prepared();self.assertEqual(verify(b,m,0,replace(c,approved_threshold=False))['verdict'],'NOT PROVABLE')
    def test_fixture_purpose_never_certifies(self):
        b,m,c=prepared();m['purpose']='fixture';c=replace(c,model_snapshot=snapshot(m))
        self.assertEqual(verify(b,m,0,c)['verdict'],'NOT PROVABLE')
    def test_unvisited_invalid_branch(self):
        b,m,c=prepared();a=m['domains'][next(iter(m['domains']))]
        a['heads']['mixed'][0]={'feature':0,'threshold':10000,'left':{'value':0},'right':{'value':True}}
        self.assertFalse(score(b,m,c)['valid'])
    def test_float_prototype(self):
        b,m,c=prepared();m['domains'][next(iter(m['domains']))]['prototypes'][0][0]=0.1
        self.assertFalse(score(b,m,c)['valid'])
    def test_oversize_prototype(self):
        b,m,c=prepared();a=m['domains'][next(iter(m['domains']))];a['prototypes']*=129
        self.assertFalse(score(b,m,c)['valid'])
    def test_missing_feature(self):
        b,m,c=prepared();m['features'].pop();self.assertFalse(score(b,m,c)['valid'])
    def test_unknown_path_domain(self):
        b,m,c=prepared();b['documents'][0]['paths']['keyboard']='other-decoder';c=context(b,m,True)
        self.assertEqual(verify(b,m,0,c)['verdict'],'NOT PROVABLE')
    def test_score_and_verdict_pipeline_agree_on_copy(self):
        b=Builder().type(TEXT).control('copy',from_doc='d',start=0,end=len(TEXT),to=len(TEXT));bundle,m,c=prepared(b)
        sc=score(bundle,m,c);self.assertEqual(sc['document_score'],SCORE_FLOOR)
        self.assertFalse(verify(bundle,m,0,c)['candidate_document_pass'])
    def test_score_alignment_rejected(self):
        b,m,c=prepared();sc=score(b,m,c);sc['scalar_scores'].pop()
        self.assertEqual(decide(sc,0,True)['verdict'],'NOT PROVABLE')
    def test_nan_model_rejected(self):
        b,m,c=prepared();m['training']={'nan':float('nan')}
        self.assertFalse(score(b,m,c)['valid'])
    def test_malformed_input_rejection(self):
        for b in (None,[],{},'x',{'version':True}):self.assertEqual(verify(b)['verdict'],'NOT PROVABLE')


class EvidenceAndLearningTests(unittest.TestCase):
    def test_schema_179_integer_features(self):
        b=Builder().type(TEXT).bundle();c=replay(b);uu,_=make_units(c,'d');f=extract(c,uu[0])
        self.assertEqual(len(f),179);self.assertEqual(list(f),list(FEATURE_NAMES));self.assertTrue(all(type(v) is int for v in f.values()))
        from pathlib import Path
        published=json.loads((Path(__file__).parents[1]/'vectors/algorithm-feature-vector.json').read_text())
        self.assertEqual(sorted(published),list(FEATURE_NAMES))
    def test_feature_equivalence_counterexample_remains_visible(self):
        source=TEXT;target=TEXT.replace('writer','reader').replace('claim','point').replace('changes','revises').replace('follows','studies')
        self.assertEqual(len(source),len(target));self.assertNotEqual(source,target)
        a=Builder().type(source).bundle();b=Builder().type(target).bundle()
        ca,cb=replay(a),replay(b);ua,_=make_units(ca,'d');ub,_=make_units(cb,'d')
        self.assertEqual([extract(ca,u) for u in ua],[extract(cb,u) for u in ub])
    def test_short_root_duplication_no_evidence(self):
        b=Builder().type('A'*32)
        for _ in range(4):b.control('copy',from_doc='d',start=0,end=32,to=len(b.text))
        c=replay(b.bundle());uu,_=make_units(c,'d');self.assertFalse(any(adequate(c,u) for u in uu))
    def test_tail_windows_complete(self):
        rr=list(map(str,range(317)));ww=windows(rr,64,32)
        self.assertEqual(set().union(*map(set,ww)),set(rr));self.assertEqual(ww[-1][-1],'316')
    def test_deterministic_features(self):
        b=Builder().type(TEXT,seed=32).bundle();c=replay(b);uu,_=make_units(c,'d')
        self.assertEqual(extract(c,uu[0]),extract(c,uu[0]))
    def test_empty_case_leakage_detected(self):
        a=case(builder=Builder().splice(0,0,'abc','paste'),cid='a');b=case(builder=Builder().splice(0,0,'abc','paste'),cid='b',split='test')
        a['links']=b['links']={'writer':['same']}
        with self.assertRaises(InvalidTrace):extract_dataset([a,b])
    def test_ambiguity_risk_worst_case(self):
        c=case('U');self.assertTrue(all(false_mask(c)));self.assertEqual(extract_case(c),[])
    def test_ambiguity_not_human_coverage(self):
        c=case('U');b=c['bundle'];m=permissive_fixture_model(b)
        self.assertEqual(risk_record(c,m,context(b,m),'h','human')['score'],SCORE_FLOOR)
    def test_incomplete_labels_abort(self):
        c=case();c['labels'][0]['end_tx']-=1
        with self.assertRaises(InvalidTrace):false_mask(c)
    def test_toy_learning_export_reproducible(self):
        rows=[]
        for i,label in enumerate(('H',)+HEADS):
            for j in range(4):
                rows.append({'id':str(i*4+j),'cluster':str(i*4+j),'document':str(i*4+j),'split':'train','links':{},
                             'domain':'keyboard|fixture-path/keyboard|en|birth','label':label,
                             'features':{k:(5000 if label=='H' else -5000) if n==0 else 0 for n,k in enumerate(FEATURE_NAMES)}})
        for i in range(99):
            r=copy.deepcopy(rows[0]);r.update(id='dev-'+str(i),cluster='dev-'+str(i),document='dev-'+str(i),split='development');rows.append(r)
        m=fit(rows);validate_model(m);self.assertEqual(m,fit(list(reversed(rows))))
        a=next(iter(m['domains'].values()));names=m['features'];h=rows[0]['features'];n=rows[4]['features']
        self.assertGreater(evaluate(h,a,names)[0],evaluate(n,a,names)[0])
    def test_staged_transcription_valid(self):
        self.assertEqual(replay(staged_transcription(TEXT,7)).documents['d'].text,TEXT)
    def test_adaptive_search_explicitly_conditional(self):
        b,m,c=prepared();r=adaptive_retiming(b,m,c,3)
        self.assertEqual(len(r['attempts']),3);self.assertEqual(r['statistical_units'],1)
        self.assertFalse(r['capture_authentication_tested'])


class LedgerTests(unittest.TestCase):
    def example(self,n=2):
        ledger={'version':'hwp-a-ledger/0.3','phase':'calibration','claim_kind':'fresh-composition',
                'cells':{'a':{'kind':'attack','attempts_per_block':n,'sampling_contract':'Synthetic fixed policy; no measured independence'},
                         'h':{'kind':'human','attempts_per_block':1,'sampling_contract':'Synthetic'}},'slots':[]}
        for i in range(n):ledger['slots'].append({'id':'a'+str(i),'cell':'a','block':'a','attempt':i,'links':['actor-A']})
        ledger['slots'].append({'id':'h','cell':'h','block':'h','attempt':0,'links':['actor-H']})
        results=[{'id':s['id'],'status':'scored','score':0,'claim_kind':'fresh-composition'} for s in ledger['slots']]
        return ledger,results
    def test_complete_ledger(self):
        l,r=self.example();self.assertEqual(len(validate_ledger(l,r)),3)
    def test_missing_attempt_rejected(self):
        l,r=self.example();r.pop(0)
        with self.assertRaises(InvalidTrace):validate_ledger(l,r)
    def test_duplicate_attempt_rejected(self):
        l,r=self.example();r.append(copy.deepcopy(r[0]))
        with self.assertRaises(InvalidTrace):validate_ledger(l,r)
    def test_budget_name_not_enough(self):
        l,r=self.example(100);l['slots'].pop(0);r.pop(0)
        with self.assertRaises(InvalidTrace):validate_ledger(l,r)
    def test_missing_task_rejected(self):
        l,r=self.example();l['cells']['h']['attempts_per_block']=2
        with self.assertRaises(InvalidTrace):validate_ledger(l,r)
    def test_dependent_blocks_rejected(self):
        l,r=self.example(1);s=copy.deepcopy(l['slots'][0]);s.update(id='extra',block='renamed');l['slots'].append(s)
        r.append(dict(r[0],id='extra'))
        with self.assertRaises(InvalidTrace):validate_ledger(l,r)
    def test_invalid_score_not_positive(self):
        l,r=self.example();r[0]['status']='structural-rejection'
        with self.assertRaises(InvalidTrace):validate_ledger(l,r)
    def test_pending_not_denominator_padding(self):
        l,r=self.example();r[0]['status']='pending'
        with self.assertRaises(InvalidTrace):validate_ledger(l,r)
    def test_frozen_final_threshold(self):
        l,r=self.example();l['phase']='test'
        with self.assertRaises(InvalidTrace):evaluate_ledger(l,r,[0,1])
    def test_claim_change_rejected(self):
        l,r=self.example();r[0]['claim_kind']='wording-origin'
        with self.assertRaises(InvalidTrace):validate_ledger(l,r)
    def test_path_specific_matrix(self):
        a,h=evaluation_cells([('keyboard','path-a','en'),('keyboard','path-b','en')]);self.assertEqual(len(a),32);self.assertEqual(len(h),12)
    def test_insufficient_statistics_not_eligible(self):
        l,r=self.example();v=evaluate_ledger(l,r,[0]);self.assertFalse(v['eligible']);self.assertFalse(v['approval_granted'])
    def test_raw_ledger_executes_all_cases(self):
        l,r=self.example(1);cases=[case('transcription',cid='a0'),case('H',cid='h')]
        m=permissive_fixture_model(cases[0]['bundle']);contexts={c['id']:context(c['bundle'],m) for c in cases}
        result,attempts=run_ledger(l,cases,m,contexts,[0]);self.assertEqual(len(attempts),2)
        self.assertEqual(result['reports'][0]['attack']['a']['failures'],1)


class FurtherRegressionTests(unittest.TestCase):
    def test_whitespace_not_document_success(self):
        b,m,c=prepared(Builder().type(' '*160))
        result=score(b,m,c)
        self.assertEqual(result['document_score'],SCORE_FLOOR)
        self.assertEqual(verify(b,m,0,c)['verdict'],'NOT PROVABLE')
    def test_malformed_empty_exclusion_not_silently_ignored(self):
        b,m,c=prepared()
        for x in ('',{},False):
            self.assertEqual(verify(b,m,0,c,x)['verdict'],'NOT PROVABLE')
    def test_synthetic_deletion_blocks_process(self):
        builder=Builder().type(TEXT);builder.splice(0,1,'',observed_source='synthetic')
        b,m,c=prepared(builder)
        self.assertEqual(verify(b,m,0,c)['verdict'],'NOT PROVABLE')
    def test_human_labels_must_cover_transactions(self):
        l,r=LedgerTests().example(1);cases=[case('transcription',cid='a0'),case('H',cid='h')]
        cases[1]['labels'][0]['end_tx']-=1
        m=permissive_fixture_model(cases[0]['bundle']);cc={c['id']:context(c['bundle'],m) for c in cases}
        with self.assertRaisesRegex(InvalidTrace,'GROUND_TRUTH_INCOMPLETE'):run_ledger(l,cases,m,cc,[0])
    def test_phase_link_leakage_rejected(self):
        from hwp0.algorithm.ledger import phase_separation
        a,_=LedgerTests().example(1);b=copy.deepcopy(a);b['phase']='test'
        for slot in b['slots']:slot['id']='later-'+slot['id']
        with self.assertRaises(InvalidTrace):phase_separation(a,b)
    def test_disjoint_phases_declared(self):
        from hwp0.algorithm.ledger import phase_separation
        a,_=LedgerTests().example(1);b=copy.deepcopy(a);b['phase']='test'
        for slot in b['slots']:
            slot['id']='later-'+slot['id'];slot['links']=['new-'+x for x in slot['links']]
        self.assertTrue(phase_separation(a,b))

class SchemaAndReleaseTests(unittest.TestCase):
    def test_schema_for_all_profiles(self):
        from pathlib import Path
        from jsonschema import Draft202012Validator
        schema=json.loads((Path(__file__).parents[1]/'telemetry.schema.json').read_text())
        Draft202012Validator.check_schema(schema);validator=Draft202012Validator(schema)
        for profile in PROFILES:validator.validate(Builder(profile=profile).type('ab').bundle())
    def test_schema_rejects_missing_delivery(self):
        from pathlib import Path
        from jsonschema import Draft202012Validator
        validator=Draft202012Validator(json.loads((Path(__file__).parents[1]/'telemetry.schema.json').read_text()))
        b=Builder().type('a').bundle();del b['documents'][0]['transactions'][0]['delivery']
        self.assertTrue(list(validator.iter_errors(b)))
    def test_empty_dependency_links_not_independent_sample(self):
        l,r=LedgerTests().example();l['slots'][0]['links']=[]
        with self.assertRaises(InvalidTrace):validate_ledger(l,r)
    def test_mandatory_release_matrix_not_inferred(self):
        from hwp0.algorithm.release import validate_release_matrix
        l,r=LedgerTests().example()
        with self.assertRaises(InvalidTrace):validate_release_matrix(l,[('keyboard','path','en')])
    def test_wrong_condition_rejected_before_scoring(self):
        from hwp0.algorithm.release import run_release
        a,h=evaluation_cells([('keyboard','path','en')])
        l={'version':'hwp-a-ledger/0.3','phase':'calibration','claim_kind':'fresh-composition',
           'cells':{k:{'kind':'attack' if k in a else 'human','attempts_per_block':int(k.rsplit('B',1)[1]) if k in a else 1,'sampling_contract':'Synthetic'} for k in a+h},
           'slots':[{'id':'bad','cell':a[0],'block':'one','attempt':0,'links':['test']} ]}
        wrong=case(cid='bad');wrong['condition']='wrong';m=permissive_fixture_model(wrong['bundle'])
        with self.assertRaises(InvalidTrace):run_release(l,[wrong],m,{'bad':context(wrong['bundle'],m)},[0],[('keyboard','path','en')])

if __name__=='__main__':unittest.main()
