"""Deterministic conformance, adversarial fixtures, statistical and fuzz tests."""
import copy
import json
import math
import random
import unittest
from reference import *
from fixtures import TraceBuilder, mock_model, synthetic, SAMPLE
from train import np_order, calibrate, upper_binomial, REQUIRED_FAMILIES, check_rows, rows_from_trace, audit_gate, GENUINE_CONDITIONS

class AlgorithmTests(unittest.TestCase):
    def setUp(self):
        self.model=mock_model()
        self.models={"keyboard":self.model}
        self.admission=Admission(True,True,frozenset({self.model["id"]}))
        self.trace=TraceBuilder().type(SAMPLE).finish()

    def approved(self,trace=None,claims=None):
        return assess(trace or self.trace,self.models,claims,self.admission)

    def test_complete_positive_path_only_under_test_policy(self):
        self.assertEqual(self.approved()["verdict"],"HUMAN-WRITTEN")

    def test_default_is_not_certified(self):
        self.assertEqual(assess(self.trace,self.models)["verdict"],"NOT PROVABLE")

    def test_no_model(self):
        self.assertEqual(assess(self.trace,{})["verdict"],"NOT PROVABLE")

    def test_freshness_not_self_asserted(self):
        self.trace["fresh"] = True
        self.assertEqual(self.approved()["verdict"],"NOT PROVABLE")

    def test_invalid_capture_or_approval(self):
        for admission in (Admission(False,True,frozenset({self.model["id"]})),Admission(True,False,frozenset({self.model["id"]})),Admission(True,True)):
            self.assertEqual(assess(self.trace,self.models,admission=admission)["verdict"],"NOT PROVABLE")

    def test_equal_threshold_abstains(self):
        self.model["threshold"]=0
        self.assertEqual(self.approved()["verdict"],"NOT PROVABLE")

    def test_uncalibrated_abstains(self):
        self.model["threshold"]=None
        self.assertEqual(self.approved()["verdict"],"NOT PROVABLE")

    def test_ood_rejects(self):
        self.model["radius2"]=0
        self.assertEqual(self.approved()["verdict"],"NOT PROVABLE")

    def test_unicode_exactness_and_byte_scope(self):
        b=TraceBuilder().type("é😀e\u0301 "*20)
        out=self.approved(b.finish(),[[0,2]])
        self.assertEqual(out["verdict"],"HUMAN-WRITTEN")
        self.assertEqual(self.approved(b.finish(),[[1,2]])["verdict"],"NOT PROVABLE")
        self.assertEqual(replay(b.finish()).document,b.data["document"])

    def test_surrogate_rejected(self):
        self.trace["document"]="\ud800"
        self.assertEqual(self.approved()["verdict"],"NOT PROVABLE")

    def test_exact_document_substitution(self):
        for suffix in ("\n"," ","\r\n"):
            x=copy.deepcopy(self.trace); x["document"]+=suffix
            self.assertEqual(self.approved(x)["verdict"],"NOT PROVABLE")

    def test_duplicate_json_keys_and_float(self):
        for s in ('{"x":1,"x":2}','{"x":0.1}','{"x":NaN}'):
            with self.assertRaises(Invalid): loads(s)

    def test_sequence_and_clock(self):
        for field,val in (("seq",99),("seq",True),("t_us",-1),("t_us",12345)):
            x=copy.deepcopy(self.trace); x["events"][0][field]=val
            self.assertEqual(self.approved(x)["verdict"],"NOT PROVABLE")

    def test_action_text_substitution(self):
        x=copy.deepcopy(self.trace); x["events"][0]["text"]="z"
        self.assertEqual(self.approved(x)["verdict"],"NOT PROVABLE")

    def test_cause_reuse(self):
        x=copy.deepcopy(self.trace); x["events"][3]["causes"]=[0]
        self.assertEqual(self.approved(x)["verdict"],"NOT PROVABLE")

    def test_gap_not_pause(self):
        b=TraceBuilder().type(SAMPLE); b.emit("gap")
        self.assertEqual(self.approved(b.finish())["verdict"],"NOT PROVABLE")

    def test_focus_gap_splits_evidence(self):
        b=TraceBuilder().type("abcd")
        b.emit("focus",focused=False); b.emit("focus",dt=60_000_000,focused=True)
        b.type(SAMPLE)
        out=self.approved(b.finish())
        self.assertEqual(out["verdict"],"NOT PROVABLE")
        self.assertEqual(self.approved(b.finish(),[[4,len(b.data["document"].encode())]])["verdict"],"HUMAN-WRITTEN")

    def test_mutation_out_of_focus(self):
        b=TraceBuilder(); b.emit("focus",focused=False); b.type(SAMPLE)
        self.assertEqual(self.approved(b.finish())["verdict"],"NOT PROVABLE")

    def test_short_support_cannot_borrow_document_history(self):
        b=TraceBuilder().type(SAMPLE*2); b.select(0); b.edit(0,0,"Fake")
        out=self.approved(b.finish())
        self.assertEqual(out["verdict"],"NOT PROVABLE")
        self.assertTrue(any("SHORT_SURVIVING_TEXT" in u["reasons"] for u in out["units"]))

    def test_external_source_types_fail(self):
        for source in ("external","injected","unknown","assisted"):
            b=TraceBuilder().type(SAMPLE,source=source)
            self.assertEqual(self.approved(b.finish())["verdict"],"NOT PROVABLE")

    def test_quotes_excluded_not_forgiven(self):
        b=TraceBuilder(); b.edit(0,0,"A quote. ",source="external"); prefix=len(b.data["document"].encode()); b.type(SAMPLE)
        self.assertEqual(self.approved(b.finish())["verdict"],"NOT PROVABLE")
        out=self.approved(b.finish(),[[prefix,len(b.data["document"].encode())]])
        self.assertEqual(out["verdict"],"HUMAN-WRITTEN")
        self.assertEqual(out["claim_kind"],"specified-ranges")
        self.assertEqual(out["partition"][0]["verdict"],"NOT PROVABLE")

    def test_invalid_scopes(self):
        for claims in ([],[[0,0]],[[0,10],[9,20]],[[10,20],[0,9]],[[0,10**9]],[[True,10]]):
            self.assertEqual(self.approved(claims=claims)["verdict"],"NOT PROVABLE")

    def test_lcs_retains_unchanged_external_text(self):
        b=TraceBuilder(); b.edit(0,0,SAMPLE,source="external")
        b.edit(0,len(SAMPLE),SAMPLE.replace("writer","author"))
        r=replay(b.finish())
        self.assertGreater(sum(r.roots[a.root].source == "external" for a in r.live),100)
        self.assertEqual(self.approved(b.finish())["verdict"],"NOT PROVABLE")

    def test_lcs_tie_is_pinned(self):
        self.assertEqual(lcs_pairs("ab","ba"),{0:1})

    def test_copy_preserves_roots_not_fresh_composition(self):
        b=TraceBuilder().type(SAMPLE); n=len(SAMPLE); b.copy(0,n,n)
        r=replay(b.finish())
        self.assertEqual(len(r.roots),n)
        self.assertEqual(len({a.occurrence for a in r.live}),2*n)
        self.assertEqual([a.root for a in r.live[:n]],[a.root for a in r.live[n:]])
        self.assertEqual(self.approved(b.finish())["verdict"],"NOT PROVABLE")
        self.assertEqual(self.approved(b.finish(),[[0,n]])["verdict"],"HUMAN-WRITTEN")

    def test_move_keeps_origin_and_occurrence(self):
        b=TraceBuilder().type(SAMPLE); original=replay(b.finish()); b.move(0,32,len(SAMPLE)-32)
        r=replay(b.finish())
        self.assertEqual(len(r.roots),len(original.roots))
        self.assertEqual({a.occurrence for a in r.live},{a.occurrence for a in original.live})
        self.assertEqual(self.approved(b.finish())["verdict"],"HUMAN-WRITTEN")

    def test_move_undo_redo(self):
        b=TraceBuilder().type(SAMPLE); before=b.data["document"]
        b.move(0,32,len(SAMPLE)-32); after=b.data["document"]
        b.undo(); self.assertEqual(replay(b.finish()).document,before)
        b.redo(); self.assertEqual(replay(b.finish()).document,after)

    def test_undo_redo_preserves_external_origin(self):
        b=TraceBuilder(); b.edit(0,0,SAMPLE,source="external"); b.undo(); b.redo()
        r=replay(b.finish())
        self.assertTrue(all(r.roots[a.root].source == "external" for a in r.live))
        self.assertEqual(self.approved(b.finish())["verdict"],"NOT PROVABLE")

    def test_copy_undo_redo(self):
        b=TraceBuilder().type(SAMPLE); b.copy(0,32,len(SAMPLE)); expected=b.data["document"]
        b.undo(); b.redo()
        self.assertEqual(replay(b.finish()).document,expected)
        self.assertIsNotNone(replay(b.finish()).live[-1].copied_from)

    def test_discarded_work_does_not_meet_surviving_support(self):
        b=TraceBuilder().type(SAMPLE); b.edit(0,len(SAMPLE),""); b.type("new")
        self.assertEqual(self.approved(b.finish())["verdict"],"NOT PROVABLE")

    def test_pause_censoring_and_context(self):
        b=TraceBuilder().type(SAMPLE[:64]); b.type(SAMPLE[64:],dt=60_000_000)
        r=replay(b.finish()); u=units(r)[-1]; x,_=features(r,u)
        self.assertGreater(x[FEATURES.index("interval_missing")],0)
        self.assertEqual(len(x),len(FEATURES))
        self.assertTrue(all(type(v) is int and 0 <= v <= Q for v in x))

    def test_keyboard_release_and_overlap(self):
        b=TraceBuilder()
        a=b.edit(0,0,"a",dt=100_000); c=b.edit(1,1,"b",dt=50_000)
        b.emit("release",dt=100_000,press=a); b.emit("release",dt=20_000,press=c)
        b.type(SAMPLE); r=replay(b.finish())
        self.assertGreater(r.releases[a],r.inputs[c]["t_us"])

    def test_touch_path(self):
        b=TraceBuilder(mode="touch").type(SAMPLE); m=mock_model("touch")
        a=Admission(True,True,frozenset({m["id"]}))
        self.assertEqual(assess(b.finish(),{"touch":m},admission=a)["verdict"],"HUMAN-WRITTEN")

    def test_ime_requires_preedit(self):
        b=TraceBuilder(mode="ime"); b.edit(0,0,SAMPLE,preedit=0)
        self.assertTrue(all(replay(b.finish()).roots[a.root].source == "unknown" for a in replay(b.finish()).live))

    def test_observed_ime_path(self):
        b=TraceBuilder(mode="ime"); b.edit(0,0,SAMPLE,preedit=20); m=mock_model("ime")
        a=Admission(True,True,frozenset({m["id"]}))
        self.assertEqual(assess(b.finish(),{"ime":m},admission=a)["verdict"],"HUMAN-WRITTEN")

    def test_multi_mode_no_silent_fallback(self):
        b=TraceBuilder().type(SAMPLE); b.switch("touch"); b.type(SAMPLE)
        self.assertEqual(self.approved(b.finish())["verdict"],"NOT PROVABLE")
        touch=mock_model("touch")
        a=Admission(True,True,frozenset({self.model["id"],touch["id"]}))
        self.assertEqual(assess(b.finish(),dict(self.models,touch=touch),admission=a)["verdict"],"HUMAN-WRITTEN")

    def test_identical_observation_counterexample(self):
        copied=copy.deepcopy(self.trace)
        copied["session_id"]="REPLAYED-SYNTHETIC-IDENTICAL-BEHAVIOR"
        a=analyze(self.trace,self.models); b=analyze(copied,self.models)
        self.assertEqual(a[1],b[1])
        self.assertEqual(self.approved(self.trace)["verdict"],self.approved(copied)["verdict"])

    def test_attack_score_uses_weakest_cover_then_worst_target(self):
        v=attack_score(self.trace,self.models,[[0,len(SAMPLE)]],"keyboard")
        self.assertEqual(v,0)
        short=TraceBuilder().type("abc").finish()
        self.assertIsNone(attack_score(short,self.models,[[0,3]],"keyboard"))

    def test_np_sample_size(self):
        self.assertIsNone(np_order(2994,.001,.05))
        k,bound=np_order(2995,.001,.05)
        self.assertEqual(k,2995); self.assertLessEqual(bound,.05)
        self.assertGreater(upper_binomial(0,2994),.001)
        self.assertLess(upper_binomial(0,2995),.001)

    def test_np_nonmax_order_when_data_suffices(self):
        k,bound=np_order(100,.1,.05)
        self.assertLess(k,100); self.assertLessEqual(bound,.05)

    def test_calibration_requires_all_families(self):
        with self.assertRaises(Invalid): calibrate([])

    def test_campaigns_not_windows(self):
        cs=[dict(cluster=f"{f}-{i}",family=f,score=i,budget=10) for f in REQUIRED_FAMILIES for i in range(50)]
        result=calibrate(cs,alpha=.1,delta=.1)
        self.assertTrue(result["enabled"])
        self.assertFalse(result["approved"])
        cs[1]["cluster"]=cs[0]["cluster"]
        with self.assertRaises(Invalid): calibrate(cs,alpha=.1,delta=.1)

    def test_insufficient_campaigns_fail_closed(self):
        cs=[dict(cluster=f,family=f,score=0,budget=1) for f in REQUIRED_FAMILIES]
        self.assertFalse(calibrate(cs)["enabled"])

    def test_missing_attack_family_rejected(self):
        del self.model["weights"]["automation"]
        del self.model["bias"]["automation"]
        self.model["families"].remove("automation")
        self.assertEqual(self.approved()["verdict"],"NOT PROVABLE")

    def test_malformed_model_rejected(self):
        self.model["scale"][0]=0
        self.assertEqual(self.approved()["verdict"],"NOT PROVABLE")

    def test_training_rows_from_complete_annotations(self):
        annotation=[dict(start=0,end=len(SAMPLE.encode()),label="human")]
        rows,skips=rows_from_trace(self.trace,annotation,dict(cluster="writer",case="session",source="task"))
        self.assertTrue(rows); self.assertFalse(skips)
        check_rows(rows,"keyboard","en")
        self.assertTrue(all(r["label"] == "human" for r in rows))

    def test_ambiguous_training_units_not_relabelled(self):
        annotation=[dict(start=0,end=len(SAMPLE.encode()),label="ambiguous")]
        rows,skips=rows_from_trace(self.trace,annotation,dict(cluster="writer",case="session",source="task"))
        self.assertFalse(rows); self.assertTrue(skips["ambiguous_or_no_fresh_target"])

    def test_annotation_must_cover_document(self):
        with self.assertRaises(Invalid):
            rows_from_trace(self.trace,[dict(start=0,end=10,label="human")],dict(cluster="writer",case="session",source="task"))

    def test_mixed_training_units_keep_local_labels(self):
        annotation=[dict(start=0,end=50,label="human"),dict(start=50,end=len(SAMPLE.encode()),label="transcription")]
        rows,_=rows_from_trace(self.trace,annotation,dict(cluster="writer",case="session",source="task"))
        check_rows(rows,"keyboard","en")
        self.assertIn("mixed",{r["label"] for r in rows})
        self.assertIn("transcription",{r["label"] for r in rows})

    def test_all_abstain_cannot_pass_coverage_gate(self):
        attacks={f:(0,6000) for f in REQUIRED_FAMILIES}
        genuine={g:(0,100) for g in GENUINE_CONDITIONS}
        report=audit_gate(attacks,genuine)
        self.assertFalse(report["statistical_gate_passed"])
        self.assertFalse(report["approved"])

    def test_statistical_pass_does_not_self_approve(self):
        attacks={f:(0,6000) for f in REQUIRED_FAMILIES}
        genuine={g:(100,100) for g in GENUINE_CONDITIONS}
        report=audit_gate(attacks,genuine)
        self.assertTrue(report["statistical_gate_passed"])
        self.assertFalse(report["approved"])

    def test_order_tail_matches_direct_rational_sum(self):
        from fractions import Fraction
        k,tail=np_order(100,.1,.05)
        exact=sum(Fraction(math.comb(100,j)*9**j,10**100) for j in range(k,101))
        earlier=exact+Fraction(math.comb(100,k-1)*9**(k-1),10**100)
        self.assertEqual(tail,float(exact))
        self.assertLessEqual(exact,Fraction(1,20))
        self.assertGreater(earlier,Fraction(1,20))

    def test_fuzz_replay_100_histories(self):
        for seed in range(100):
            rng=random.Random(seed); b=TraceBuilder()
            for _ in range(30):
                d=b.data["document"]
                p=rng.randrange(len(d)+1)
                if d and rng.random()<.25:
                    p=rng.randrange(len(d)); end=rng.randrange(p+1,len(d)+1)
                    b.edit(p,end,"")
                else:
                    value=rng.choice(("a","😀","é","e\u0301","\n","bc"))
                    b.edit(p,p,value)
                if rng.random()<.15:
                    b.undo(); b.redo()
            self.assertEqual(replay(b.finish()).document,b.data["document"])

if __name__ == "__main__":
    unittest.main(verbosity=2)
