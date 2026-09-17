from __future__ import annotations
import copy
import json
import math
import unittest
from random import Random
from hwp_a import HUMAN,NOT_PROVABLE
from hwp_a.replay import *
from hwp_a.features import extract,adequate,Q
from hwp_a.fixtures import Builder,TEXT,permissive_fixture_model
from hwp_a.model import evaluate,fit,validate_splits,ROUNDS,HEADS,SCORE_FLOOR,domain
from hwp_a.verify import score,decide,verify,TrustedInputs
from hwp_a.calibration import upper,lower,zero_failure_n,calibrate,thresholds,campaign_score
from hwp_a.dataset import extract_case,false_mask
from hwp_a.__main__ import pairs


def fixture_context(bundle,model,approved=False,threshold=0):
    return TrustedInputs(frozenset(x['id'] for x in bundle['documents']),approved,threshold,frozenset(model['domains']))

class ReplayTests(unittest.TestCase):
    def test_all_four_input_profiles(self):
        for p in PROFILES:
            with self.subTest(profile=p):
                b=Builder(profile=p).type(TEXT,seed=7).bundle(); c=replay(b)
                self.assertEqual(c.documents['d'].text,TEXT)
                self.assertTrue(all(a.roots for a in c.atoms.values()))
    def test_exact_unicode_and_newlines(self):
        text='é e\u0301 汉字 👩\u200d🔬\r\n\n'
        b=Builder().type(text).bundle(); c=replay(b)
        self.assertEqual(c.documents['d'].text.encode(),text.encode())
        self.assertNotEqual('é'.encode(),'e\u0301'.encode())
    def test_byte_boundaries(self):
        self.assertEqual(scalar_range('Aé文',1,3),(1,2))
        with self.assertRaises(InvalidTrace): scalar_range('Aé文',2,3)
    def test_copy_has_fresh_occurrence_same_origin(self):
        b=Builder().type('abcdef').control('copy',from_doc='d',start=0,end=3,to=6).bundle(); c=replay(b); ll=c.documents['d'].live
        self.assertNotEqual(ll[0],ll[6]); self.assertEqual(c.atoms[ll[0]].roots,c.atoms[ll[6]].roots)
    def test_external_copy_and_undo_not_laundered(self):
        b=Builder().splice(0,0,'imported','paste').control('copy',from_doc='d',start=0,end=8,to=8).control('undo').control('redo').bundle()
        c=replay(b); self.assertTrue(all(not c.atoms[a].roots for a in c.documents['d'].live))
    def test_move_forward_backward_and_history(self):
        for start,end,to in ((1,3,4),(4,6,0),(0,2,0),(1,5,1)):
            b=Builder().type('abcdefgh'); original=b.text
            b.control('move',start=start,end=end,to=to); moved=b.text
            c=replay(b.bundle()); self.assertEqual(c.documents['d'].text,moved)
            b.control('undo'); self.assertEqual(replay(b.bundle()).documents['d'].text,original)
            b.control('redo'); self.assertEqual(replay(b.bundle()).documents['d'].text,moved)
    def test_typing_after_undo_clears_redo(self):
        b=Builder().type('ab').control('undo').type('x'); broken=b.bundle()
        cause,t=b.cause(True); b.add('redo',cause,t,ref=1)
        with self.assertRaises(InvalidTrace): replay(b.bundle())
    def test_parent_copy_is_transitive(self):
        a=Builder('a').type(TEXT).record()
        b=Builder('b').control('copy',from_doc='a',start=0,end=len(TEXT),to=0,parent_text=TEXT).bundle([a])
        c=replay(b); atom=c.atoms[c.documents['b'].live[0]]
        self.assertEqual(atom.home,'a'); self.assertEqual(atom.requirements,frozenset({'a','b'}))
    def test_missing_or_future_parent(self):
        b=Builder('b').control('copy',from_doc='a',start=0,end=3,to=0,parent_text='abc').bundle()
        with self.assertRaises(InvalidTrace): replay(b)
    def test_spelling_inherits_roots(self):
        b=Builder().type('teh').splice(0,3,'the','spelling').bundle(); c=replay(b)
        self.assertEqual(len(c.atoms[c.documents['d'].live[0]].roots),3)
        self.assertTrue(all(c.atoms[a].kind=='derived' for a in c.documents['d'].live))
    def test_spelling_cannot_chain_or_launder(self):
        for b in (Builder().splice(0,0,'teh','paste').splice(0,3,'the','spelling'),Builder().type('teh').splice(0,3,'the','spelling').splice(0,3,'thy','spelling')):
            with self.assertRaises(InvalidTrace): replay(b.bundle())
    def test_wrong_final_text_and_deleted_text(self):
        b=Builder().type('abc').bundle()
        wrong=copy.deepcopy(b); wrong['documents'][0]['final_text']='abd'
        with self.assertRaises(InvalidTrace): replay(wrong)
        wrong=copy.deepcopy(b); wrong['documents'][0]['transactions'][0]['deleted']='z'
        with self.assertRaises(InvalidTrace): replay(wrong)
    def test_sequence_and_unknown_field(self):
        b=Builder().type('abc').bundle()
        for field,val in (('i',4),('unrecognized',True)):
            wrong=copy.deepcopy(b); wrong['documents'][0]['transactions'][0][field]=val
            with self.assertRaises(InvalidTrace): replay(wrong)
    def test_cause_reuse_future_and_type(self):
        b=Builder().type('abc').bundle()
        for cause in (0,5,True):
            wrong=copy.deepcopy(b); wrong['documents'][0]['transactions'][1]['causes']=[cause]
            with self.assertRaises(InvalidTrace): replay(wrong)
    def test_clock_resolution_and_negative(self):
        for t in (-1,10.5,True,200001):
            b=Builder().type('a').bundle(); b['documents'][0]['observations'][0]['t']=t
            with self.assertRaises(InvalidTrace): replay(b)
    def test_surrogate_rejected(self):
        b=Builder().type('x').bundle(); b['documents'][0]['final_text']='\ud800'
        with self.assertRaises(InvalidTrace): replay(b)
    def test_unexplained_bulk_direct(self):
        b=Builder().splice(0,0,'x'*9).bundle()
        with self.assertRaises(InvalidTrace): replay(b)
    def test_synthetic_observation_not_candidate(self):
        b=Builder().splice(0,0,'x',observed_source='synthetic').bundle(); c=replay(b)
        self.assertFalse(c.atoms[c.documents['d'].live[0]].roots)
    def test_ime_preedit_not_new_roots(self):
        b=Builder(profile='ime').type('abcd').bundle(); c=replay(b)
        self.assertEqual(len(c.atoms),4); self.assertEqual(len(c.documents['d'].effects),1)
    def test_ime_without_basis_and_double_spend(self):
        b=Builder(profile='ime').type('abcdefgh').bundle()
        bad=copy.deepcopy(b); bad['documents'][0]['observations'][4]['basis']=[]
        with self.assertRaises(InvalidTrace): replay(bad)
        bad=copy.deepcopy(b); bad['documents'][0]['observations'][9]['basis']=[1]
        with self.assertRaises(InvalidTrace): replay(bad)
    def test_overlapping_keys_are_valid(self):
        b=Builder().type('ab').bundle(); d=b['documents'][0]
        obs=d['observations']; obs[1]['t']=obs[2]['t']+1000
        old=sorted(obs,key=lambda o:o['t']); mapping={o['i']:i for i,o in enumerate(old)}
        for i,o in enumerate(old): o['i']=i
        d['observations']=old
        for tx in d['transactions']: tx['causes']=[mapping[i] for i in tx['causes']]
        replay(b)
    def test_duplicate_json_key_rejected(self):
        with self.assertRaises(ValueError): json.loads('{"x":1,"x":2}',object_pairs_hook=pairs)
    def test_random_edit_replay(self):
        rng=Random(123)
        for _ in range(20):
            b=Builder()
            for _ in range(40):
                a=rng.randrange(len(b.text)+1); e=rng.randrange(a,len(b.text)+1)
                new=rng.choice(('x','é','\n','','abc'))
                if a==e and not new: new='z'
                b.splice(a,e,new)
            self.assertEqual(replay(b.bundle()).documents['d'].text,b.text)

class EvidenceTests(unittest.TestCase):
    def test_windows_cover_tail(self):
        roots=[str(i) for i in range(317)]; ww=windows(roots,64,32)
        self.assertEqual(ww[-1][-1],'316'); self.assertEqual(set().union(*map(set,ww)),set(roots))
    def test_windows_independent_of_requested_quotes(self):
        b=Builder().type(TEXT).bundle(); c=replay(b)
        u,_=make_units(c,'d'); self.assertTrue({'birth','layout','retained','global'}<={x.view for x in u})
    def test_short_duplicate_cannot_create_evidence(self):
        b=Builder().type('A'*32)
        for _ in range(4): b.control('copy',from_doc='d',start=0,end=32,to=len(b.text))
        c=replay(b.bundle()); u,_=make_units(c,'d')
        self.assertFalse(any(adequate(c,x) for x in u))
    def test_features_fixed_point_and_deterministic(self):
        b=Builder().type(TEXT,seed=2).bundle(); c=replay(b); u,_=make_units(c,'d')
        a=extract(c,u[0]); self.assertEqual(a,extract(c,u[0]))
        self.assertTrue(all(type(v) is int and -Q<=v<=Q for v in a.values())); self.assertEqual(list(a),sorted(a))
    def test_external_then_retype_is_observed_source_match(self):
        b=Builder().splice(0,0,TEXT,'paste').splice(0,len(TEXT),'').type(TEXT).bundle(); c=replay(b)
        self.assertEqual(len(observed_source_matches(c,'d')),len(TEXT))
    def test_capture_is_external_not_self_asserted(self):
        b=Builder().type(TEXT).bundle(); m=permissive_fixture_model(b)
        self.assertEqual(score(b,m)['document_score'],SCORE_FLOOR)
        self.assertEqual(score(b,m,fixture_context(b,m))['document_score'],0)
    def test_capture_gap_forces_abstention(self):
        b=Builder().type(TEXT).gap().bundle(); m=permissive_fixture_model(b)
        self.assertEqual(score(b,m,fixture_context(b,m))['document_score'],SCORE_FLOOR)
    def test_fixture_cannot_authorize_public_label(self):
        b=Builder().type(TEXT).bundle(); m=permissive_fixture_model(b)
        r=verify(b,m,0,fixture_context(b,m,True))
        self.assertEqual(r['verdict'],NOT_PROVABLE); self.assertTrue(r['candidate_document_pass'])
    def test_threshold_is_pinned(self):
        b=Builder().type(TEXT).bundle(); m=permissive_fixture_model(b); m['purpose']='validated-release'
        r=verify(b,m,-1,fixture_context(b,m,True,0)); self.assertEqual(r['verdict'],NOT_PROVABLE)
    def test_conditional_binary_decision_branch(self):
        b=Builder().type(TEXT).bundle(); m=permissive_fixture_model(b); ss=score(b,m,fixture_context(b,m))
        self.assertEqual(decide(ss,0,True)['verdict'],HUMAN)
        self.assertEqual(decide(ss,1,True)['verdict'],NOT_PROVABLE)
    def test_short_late_insertion_not_helped_by_intro(self):
        b=Builder().type(TEXT).pause().type('copied').bundle(); m=permissive_fixture_model(b)
        ss=score(b,m,fixture_context(b,m)); self.assertTrue(all(v==SCORE_FLOOR for v in ss['scalar_scores'][-6:]))
    def test_exact_observational_equivalence(self):
        b=Builder().type(TEXT,seed=8).bundle(); other=copy.deepcopy(b); m=permissive_fixture_model(b)
        self.assertEqual(score(b,m,fixture_context(b,m)),score(other,m,fixture_context(other,m)))
        # Assigning "composer" versus "transcriber" in an experiment cannot change observations.
    def test_quote_exclusion_does_not_relabel_quote(self):
        b=Builder().type(TEXT).splice(len(TEXT),len(TEXT),'external quote','paste').bundle(); m=permissive_fixture_model(b)
        ss=score(b,m,fixture_context(b,m)); start=len(TEXT.encode()); end=len(ss['text'].encode())
        r=decide(ss,0,True,[{'start':start,'end':end,'source':'quoted source'}])
        self.assertEqual(r['verdict'],NOT_PROVABLE); self.assertEqual(r['contribution_verdict'],HUMAN)
        self.assertEqual(r['ranges'][-1]['verdict'],NOT_PROVABLE); self.assertTrue(r['ranges'][-1]['excluded'])
    def test_invalid_exclusion_and_empty_scope(self):
        b=Builder().type(TEXT).bundle(); m=permissive_fixture_model(b); ss=score(b,m,fixture_context(b,m)); end=len(TEXT.encode())
        for exc in ([{'start':0,'end':end,'source':'all'}],[{'start':2,'end':1,'source':'bad'}]):
            self.assertEqual(decide(ss,0,True,exc)['contribution_verdict'],NOT_PROVABLE)
    def test_range_partition_exact_bytes(self):
        b=Builder().type(TEXT+'é文').bundle(); m=permissive_fixture_model(b); r=decide(score(b,m,fixture_context(b,m)),0,True)
        self.assertEqual(r['ranges'][0]['start'],0); self.assertEqual(r['ranges'][-1]['end'],len((TEXT+'é文').encode()))
        self.assertTrue(all(a['end']==b['start'] for a,b in zip(r['ranges'],r['ranges'][1:])))
    def test_missing_model_and_malformed_are_not_provable(self):
        self.assertEqual(verify(Builder().type(TEXT).bundle())['verdict'],NOT_PROVABLE)
        self.assertEqual(verify({'garbage':True})['verdict'],NOT_PROVABLE)
    def test_inherited_range_is_identified(self):
        a=Builder('a').type(TEXT).record(); b=Builder('b').control('copy',from_doc='a',start=0,end=len(TEXT),to=0,parent_text=TEXT).bundle([a])
        m=permissive_fixture_model(b); r=decide(score(b,m,fixture_context(b,m)),0,True)
        self.assertEqual(r['ranges'][0]['origin'],'inherited'); self.assertEqual(r['ranges'][0]['origin_documents'],['a'])
    def test_no_support_calibration_is_not_supported(self):
        b=Builder().type(TEXT).bundle(); m=permissive_fixture_model(b)
        for a in m['domains'].values(): a['support_calibration']=[]
        self.assertEqual(score(b,m,fixture_context(b,m))['document_score'],SCORE_FLOOR)
    def test_unknown_model_head_fails_closed(self):
        b=Builder().type(TEXT).bundle(); m=permissive_fixture_model(b)
        for a in m['domains'].values(): a['heads'].pop('simulation')
        self.assertFalse(score(b,m,fixture_context(b,m))['valid'])
    def test_no_scope_changes_scores(self):
        b=Builder().type(TEXT).bundle(); m=permissive_fixture_model(b); ss=score(b,m,fixture_context(b,m)); before=copy.deepcopy(ss)
        decide(ss,0,True,[{'start':0,'end':5,'source':'exclusion'}]); self.assertEqual(ss,before)
