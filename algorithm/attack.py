"""Local defensive score-guided attack harness for HWP-A1 research.

It simulates plausible telemetry for a prewritten fixed document. It does not
acquire authentic capture or generate a real human-writing certification.
"""
from __future__ import annotations
from copy import deepcopy
import random
from reference import analyze, attack_score, replay, Invalid
from fixtures import synthetic


def retime(trace: dict, rng: random.Random, intensity: int = 12) -> dict:
    """Change input intervals without changing words, event order or causality."""
    out=deepcopy(trace)
    events=out["events"]
    deltas=[]
    previous=0
    for e in events:
        deltas.append(e["t_us"]-previous); previous=e["t_us"]
    ids=[i for i,e in enumerate(events) if e["op"] == "input"]
    for i in rng.sample(ids,min(intensity,len(ids))):
        old=deltas[i]
        # All proposals are whole milliseconds, never counterfeit sub-quantum
        # precision. The input trace is explicitly synthetic, not captured.
        if rng.random()<.15:
            deltas[i]=rng.choice((80_000,120_000,250_000,700_000,1_100_000,1_600_000))
        else:
            deltas[i]=max(1_000,old+rng.randint(-50,50)*1000)
    now=0
    q=out["quantum_us"]
    for e,d in zip(events,deltas):
        now+=((d+q-1)//q)*q
        e["t_us"]=now
    replay(out)
    return out


def search(model: dict, budget: int = 128, seed: int = 914) -> tuple[dict,dict]:
    """Greedy random restarts and local retiming, using a full score oracle.

    Includes all final roots as false targets because the output was fixed
    before any simulated typing. Query budget includes seed/restart scoring.
    """
    if type(budget) is not int or budget<1:
        raise ValueError("budget must be a positive integer")
    rng=random.Random(seed)
    models={model["mode"]:model}
    best_trace=None; best=None; accepted_proposals=0
    for q in range(budget):
        if best_trace is None or q%16 == 0:
            candidate=synthetic(rng.randrange(10**9),"human",mode=model["mode"])
        else:
            candidate=retime(best_trace,rng)
        value=attack_score(candidate,models,[[0,len(candidate["document"].encode())]],model["mode"])
        if best_trace is None or (value is not None and (best is None or value > best)):
            best_trace,best=candidate,value
            accepted_proposals+=1
    assert best_trace is not None
    r,roots,details=analyze(best_trace,models)
    tau=model["threshold"]
    over=[root for root,value in roots.items() if value is not None and tau is not None and value>tau]
    report=dict(synthetic_only=True,script_text_fixed_before_typing=True,
                capture_authentication_attempted=False,budget=budget,seed=seed,
                score_improving_proposals=accepted_proposals,best_false_target_score=best,
                frozen_threshold=tau,target_roots_above_threshold=len(over),
                scoped_false_eligibility=bool(over),
                whole_document_score_eligibility=bool(roots) and len(over)==len(roots),
                interpretation="Eligibility is conditional on this unapproved toy model and simulated source observations. This strategy/budget differs from the toy calibration distribution; its result is not a violation of an assumption-free statistical theorem.")
    return best_trace,report
