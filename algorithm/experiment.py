"""Reproduce the SYNTHETIC engineering experiment and test report.

This does not measure human-writing accuracy. It deliberately includes an
observation-equivalent counterexample and uses a relaxed research risk target.
"""
from __future__ import annotations
from copy import deepcopy
import gzip
import json
import platform
from pathlib import Path
import sys
import unittest
import io
import numpy as np
import scipy
from reference import VERSION, FEATURES, Admission, analyze, assess, attack_score, features, replay, units
from fixtures import TraceBuilder, synthetic, mock_model, SAMPLE
from train import fit, calibrate, audit_gate, REQUIRED_FAMILIES
from attack import search

HERE=Path(__file__).resolve().parent

def rows_for(start,count,split):
    out=[]
    for label_index,label in enumerate(("human",*REQUIRED_FAMILIES)):
        for i in range(count):
            seed=start+1000*label_index+i
            trace=synthetic(seed,label)
            r=replay(trace)
            for u in units(r):
                x,reasons=features(r,u)
                if not reasons:
                    out.append(dict(cluster=f"{split}-{label}-{i}",case=f"{split}-{label}-{i}",
                                    source=f"synthetic-source-{split}-{label}-{i}",label=label,
                                    mode="keyboard",language="en",x=x))
    return out


def main():
    tr=rows_for(10_000,8,"train")
    dv=rows_for(20_000,5,"development")
    model,training=fit(tr,dv,"keyboard","en","SYNTHETIC-DEMONSTRATION-NOT-APPROVED")
    # Calibration deliberately uses the SAME observation generator as the
    # positive class, but assigns a nonqualifying scripted cause. This is not
    # a new human attack dataset; it operationalizes the equivalence limit.
    campaigns=[]
    for fidx,family in enumerate(REQUIRED_FAMILIES):
        for i in range(50):
            values=[]
            for attempt in range(2):
                trace=synthetic(30_000+fidx*1000+i*2+attempt,"human")
                values.append(attack_score(trace,{"keyboard":model},[[0,len(trace["document"].encode())]],"keyboard"))
            finite=[v for v in values if v is not None]
            campaigns.append(dict(cluster=f"synthetic-cal-{family}-{i}",family=family,
                                  score=max(finite) if finite else None,budget=2))
    cal=calibrate(campaigns,alpha=.1,delta=.1)
    if cal["enabled"]:
        model["threshold"]=cal["threshold"]
    admission=Admission(True,True,frozenset({model["id"]}))
    counts={}
    uncontrolled={}
    for index,label in enumerate(("human",*REQUIRED_FAMILIES)):
        accepted=0
        zero_pass=0
        for i in range(30):
            trace=synthetic(50_000+1000*index+i,label)
            accepted += assess(trace,{"keyboard":model},admission=admission)["verdict"] == "HUMAN-WRITTEN"
            _,root_scores,_=analyze(trace,{"keyboard":model})
            zero_pass += all(v is not None and v > 0 for v in root_scores.values())
        uncontrolled[label]=dict(synthetic_documents=30,uncontrolled_zero_cut_passes=zero_pass)
        counts[label]=dict(synthetic_documents=30,test_policy_acceptances=accepted)
    unseen_equivalent=0
    for i in range(30):
        trace=synthetic(60_000+i,"human")
        unseen_equivalent += assess(trace,{"keyboard":model},admission=admission)["verdict"] == "HUMAN-WRITTEN"
    trace=synthetic(70_000,"human")
    copy=deepcopy(trace); copy["session_id"]="COUNTERFACTUAL-SCRIPTED-CAUSE"
    ra,sa,da=analyze(trace,{"keyboard":model})
    rb,sb,db=analyze(copy,{"keyboard":model})
    assert sa == sb and [d["features"] for d in da] == [d["features"] for d in db]
    default_verdict=assess(trace,{"keyboard":model})["verdict"]
    golden_r=replay(synthetic(123,"human"))
    golden_u=units(golden_r)[0]
    golden_x,golden_reasons=features(golden_r,golden_u)
    (HERE/"vectors.json").write_text(json.dumps(dict(version=VERSION,synthetic_only=True,
        generator=dict(seed=123,label="human"),unit=dict(id=golden_u.uid,axis=golden_u.axis,roots=list(golden_u.roots)),
        feature_names=FEATURES,features=golden_x,reasons=golden_reasons),indent=2)+"\n")
    (HERE/"example-trace.json").write_text(json.dumps(TraceBuilder().type("Hello.").finish(),indent=2)+"\n")
    (HERE/"toy-model.json.gz").write_bytes(gzip.compress((json.dumps(model,sort_keys=True,separators=(",",":"))+"\n").encode(),mtime=0))
    best_attack,attack_report=search(model,budget=1000,seed=914)
    (HERE/"adaptive-attack.json.gz").write_bytes(gzip.compress((json.dumps(best_attack,sort_keys=True,separators=(",",":"))+"\n").encode(),mtime=0))
    suite=unittest.defaultTestLoader.discover(str(HERE),pattern="test_reference.py")
    stream=io.StringIO()
    test_result=unittest.TextTestRunner(stream=stream,verbosity=2).run(suite)
    if not test_result.wasSuccessful():
        raise RuntimeError(stream.getvalue())
    result=dict(version=VERSION,date="2026-09-15",status="SYNTHETIC ENGINEERING RESULTS; NOT HUMAN VALIDATION",
                environment=dict(python=platform.python_version(),numpy=np.__version__,scipy=scipy.__version__),
                tests=dict(methods_run=test_result.testsRun,failures=len(test_result.failures),errors=len(test_result.errors),
                           additional_randomized_histories=100,edits_per_randomized_history=30),
                training=training,calibration=cal,calibration_synthetic_campaigns=len(campaigns),
                independent_human_participants=0,trained_on_human_data=False,
                uncontrolled_score_diagnostic=uncontrolled,experiment_counts=counts,
                equivalent_scripted_test=dict(synthetic_documents=30,test_policy_acceptances=unseen_equivalent),
                identical_observation_scores_equal=(sa == sb),default_verdict=default_verdict,
                approved_models=0,adaptive_attack=attack_report,
                interpretation="Toy classes were generated, not observed. The equivalence attack uses the positive generator with a different stipulated cause. Acceptance counts under an explicit test-only admission are not deployable human-authorship verdicts or accuracy estimates. Calibration cannot create separability absent from observations.")
    (HERE/"results.json").write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps(result,indent=2))

if __name__ == "__main__":
    main()
