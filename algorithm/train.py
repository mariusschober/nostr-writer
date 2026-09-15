"""Offline HWP-A1 model fitting and risk calibration. No human dataset is bundled.

Usage is demonstrated in experiment.py. NumPy/SciPy are training dependencies;
reference.py inference requires only Python's standard library.
"""
from __future__ import annotations
from collections import defaultdict
from copy import deepcopy
import math
from fractions import Fraction
from typing import Any
import numpy as np
from scipy.optimize import minimize
from scipy.special import expit
from scipy.stats import binom, beta
from reference import (VERSION, Q, FEATURES, INTERACTIONS, MODES, Invalid, require,
                       integer, quantile, normalize, lifted, support_distance, model_check, replay, units, features, offsets)

REQUIRED_FAMILIES = ("automation", "mixed", "simulation", "transcription")
LAMBDA_GRID = (0.01, 0.1, 1.0, 10.0)


def check_rows(rows: list[dict], mode: str, language: str) -> None:
    require(bool(rows), "EMPTY_DATASET")
    for row in rows:
        require(set(row) == {"cluster", "case", "source", "label", "mode", "language", "x"}, "ROW_SCHEMA")
        require(all(type(row[k]) is str and row[k] for k in ("cluster", "case", "source", "label")), "ROW_ID")
        require(row["mode"] == mode and row["language"] == language, "ROW_STRATUM")
        require(row["label"] == "human" or row["label"] in REQUIRED_FAMILIES, "ROW_LABEL")
        require(type(row["x"]) is list and len(row["x"]) == len(FEATURES), "ROW_FEATURES")
        for v in row["x"]:
            integer(v,0,Q)
    owners = {}
    for row in rows:
        key = (row["cluster"], row["source"])
        require(row["case"] not in owners or owners[row["case"]] == key, "CASE_METADATA_CONFLICT")
        owners[row["case"]] = key


def rows_from_trace(trace: dict, annotation: list[dict], metadata: dict) -> tuple[list[dict],dict]:
    """Derive training units from a complete, independently labelled final text.

    Labels are study ground truth, never author declarations at verification.
    Copied occurrences and hard-blocked origins cannot manufacture training
    support for their original creator's root.
    """
    require(set(metadata) == {"cluster","case","source"},"DATA_METADATA")
    r=replay(trace); bs=offsets(r.document)
    require(bool(annotation),"EMPTY_ANNOTATION")
    labels={}; end=0
    for span in annotation:
        require(set(span) == {"start","end","label"},"ANNOTATION_SCHEMA")
        a,b,label=span["start"],span["end"],span["label"]
        require(type(a) is int and type(b) is int and a == end and a in bs and b in bs and a < b,"ANNOTATION_PARTITION")
        require(label in ("human","ambiguous",*REQUIRED_FAMILIES),"ANNOTATION_LABEL")
        for i in range(bs.index(a),bs.index(b)):
            atom=r.live[i]
            if atom.copied_from is None and r.roots[atom.root].source == "candidate":
                require(atom.root not in labels or labels[atom.root] == label,"ROOT_LABEL_CONFLICT")
                labels[atom.root]=label
        end=b
    require(end == bs[-1],"ANNOTATION_COVERAGE")
    out=[]; skipped=defaultdict(int)
    for u in units(r):
        x,reasons=features(r,u)
        ls={labels[v] for v in u.roots if v in labels}
        if reasons:
            skipped["insufficient_evidence"]+=1; continue
        if "ambiguous" in ls or not ls:
            skipped["ambiguous_or_no_fresh_target"]+=1; continue
        label="human" if ls == {"human"} else next(iter(ls)) if len(ls) == 1 else "mixed"
        out.append(dict(metadata,label=label,mode=u.mode,language=r.language,x=x))
    return out,dict(skipped)


def balanced_weights(rows: list[dict], family: str) -> np.ndarray:
    """Class -> cluster -> case -> unit equal weighting, rather than window count."""
    classes = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))
    for row in rows:
        label = "human" if row["label"] == "human" else family
        classes[label][row["cluster"]][row["case"]] += 1
    w = []
    for row in rows:
        label = "human" if row["label"] == "human" else family
        groups = classes[label]
        cases = groups[row["cluster"]]
        w.append(0.5/(len(groups)*len(cases)*cases[row["case"]]))
    return np.asarray(w)


def loss(theta, X, y, w, lam):
    logits = X@theta[:-1]+theta[-1]
    value = np.sum(w*(np.logaddexp(0,logits)-y*logits))+lam*np.sum(theta[:-1]**2)/2
    err = w*(expit(logits)-y)
    grad = np.r_[X.T@err+lam*theta[:-1],np.sum(err)]
    return float(value),grad


def fit(training: list[dict], development: list[dict], mode: str, language: str,
        model_id: str) -> tuple[dict,dict]:
    require(mode in MODES and bool(model_id), "FIT_STRATUM")
    check_rows(training,mode,language); check_rows(development,mode,language)
    for key in ("cluster", "case", "source"):
        require(not ({r[key] for r in training} & {r[key] for r in development}), "SPLIT_LEAKAGE:"+key)
    labels = {"human", *REQUIRED_FAMILIES}
    require({r["label"] for r in training} == labels and {r["label"] for r in development} == labels, "MISSING_CLASS")
    for label in labels:
        require(len({r["cluster"] for r in training if r["label"] == label}) >= 5, "TRAIN_GROUPS")
    cols = list(zip(*(row["x"] for row in training)))
    center = [quantile(col,50) for col in cols]
    scale = [max(Q//100,quantile(col,75)-quantile(col,25),
                 (max(abs(v-c) for v in col)+3)//4) for col,c in zip(cols,center)]
    model = dict(version=VERSION,id=model_id,mode=mode,language=language,
                 center=center,scale=scale,weights={},bias={},prototypes={},support_k=5,
                 radius2=0,threshold=None,families=list(REQUIRED_FAMILIES))
    require(all(normalize(r["x"],model)[1] for r in training), "TRAINING_NORMALIZATION_SUPPORT")
    norm = lambda x: normalize(x,model)[0]
    matrix = lambda rows: np.asarray([lifted(norm(r["x"])) for r in rows],dtype=np.float64)/Q
    candidates = []
    for lam in LAMBDA_GRID:
        weights, biases, losses = {},{},{}
        for family in REQUIRED_FAMILIES:
            tr = [r for r in training if r["label"] in ("human",family)]
            dv = [r for r in development if r["label"] in ("human",family)]
            X,y,w = matrix(tr),np.asarray([r["label"] == "human" for r in tr],dtype=float),balanced_weights(tr,family)
            initial = np.zeros(X.shape[1]+1)
            result = minimize(loss,initial,args=(X,y,w,lam),jac=True,method="L-BFGS-B",
                              options={"maxiter":2000,"ftol":1e-13,"gtol":1e-8,"maxls":40})
            require(np.all(np.isfinite(result.x)) and np.max(np.abs(result.jac)) <= 1e-5, "OPTIMIZER_NOT_CONVERGED")
            # Freeze quantized inference before any validation or calibration.
            weights[family] = [int(v) for v in np.rint(result.x[:-1]*Q)]
            biases[family] = int(np.rint(result.x[-1]*Q))
            Xv = matrix(dv)
            logits = Xv@np.asarray(weights[family])/Q+biases[family]/Q
            yv = np.asarray([r["label"] == "human" for r in dv],dtype=float)
            losses[family] = float(np.sum(balanced_weights(dv,family)*(np.logaddexp(0,logits)-yv*logits)))
        candidates.append((max(losses.values()),lam,weights,biases,losses))
    # Exact tie -> larger regularization. Development is never calibration data.
    chosen = min(candidates,key=lambda c:(c[0],-c[1]))
    model["weights"],model["bias"] = chosen[2],chosen[3]
    by_group = defaultdict(set)
    for row in training:
        if row["label"] == "human":
            by_group[row["cluster"]].add(tuple(norm(row["x"])))
    for group, vectors in sorted(by_group.items()):
        ordered = sorted(vectors)
        ids = sorted({i*(len(ordered)-1)//max(1,min(20,len(ordered))-1) for i in range(min(20,len(ordered)))})
        model["prototypes"][group] = [list(ordered[i]) for i in ids]
    distances = defaultdict(list)
    for row in development:
        if row["label"] == "human":
            z,_ = normalize(row["x"],model)
            distances[row["cluster"]].append(support_distance(z,model))
    model["radius2"] = quantile([max(ds) for ds in distances.values()],99)
    model_check(model)
    metadata = dict(selected_lambda=chosen[1],development_worst_balanced_logloss=chosen[0],
                    grid=[dict(lam=c[1],losses=c[4]) for c in candidates],
                    train_clusters=len({r["cluster"] for r in training}),
                    development_clusters=len({r["cluster"] for r in development}),
                    training_rows=len(training),development_rows=len(development),
                    quantized_before_calibration=True,approved=False)
    return model,metadata


def np_order(n: int, alpha: float, delta: float) -> tuple[int,float] | None:
    """Order-statistic search with exact rational verification of the tail.

    Decimal inputs are interpreted as exact fractions. SciPy only proposes a
    starting rank; integer arithmetic decides whether that rank is safe.
    For >4096 tail terms the conservative maximum order is used instead.
    """
    a,d = Fraction(str(alpha)),Fraction(str(delta))
    require(type(n) is int and 0 <= n <= 200_000 and 0 < a < 1 and 0 < d < 1,"CALIBRATION_ARGUMENT")
    if n == 0:
        return None
    good, bad = a.denominator-a.numerator, a.numerator
    denominator = a.denominator**n
    def exact_tail(k):
        term = math.comb(n,k)*good**k*bad**(n-k)
        total = term
        for j in range(k,n):
            term = term*(n-j)*good//((j+1)*bad)
            total += term
        return total
    def safe(tail):
        return tail*d.denominator <= d.numerator*denominator
    if not safe(good**n):
        return None
    lo,hi=1,n
    while lo < hi:
        k=(lo+hi)//2
        if float(binom.sf(k-1,n,1-float(a))) <= float(d):
            hi=k
        else:
            lo=k+1
    k=lo if n-lo <= 4096 else n
    tail=exact_tail(k)
    while not safe(tail):
        k+=1; tail=exact_tail(k)
    while k > 1 and n-k+1 <= 4096:
        earlier=exact_tail(k-1)
        if not safe(earlier):
            break
        k-=1; tail=earlier
    return k,float(Fraction(tail,denominator))


def calibrate(campaigns: list[dict], alpha: float = 0.001, delta: float = 0.05,
              total_profiles: int = 1) -> dict:
    """Campaign scores already include all attempts and all false-target roots.

    A caller must generate scores with frozen extractors/scorers/support gates.
    None means a structural rejection (minus infinity), NOT a missing trial.
    Independence/exchangeability cannot be checked from identifiers alone.
    """
    require(type(total_profiles) is int and total_profiles >= 1,"PROFILE_COUNT")
    require(0 < alpha < 1 and 0 < delta < 1,"CALIBRATION_ARGUMENT")
    ids = set(); grouped = defaultdict(list)
    for c in campaigns:
        require(set(c) == {"cluster","family","score","budget"},"CAMPAIGN_SCHEMA")
        require(type(c["cluster"]) is str and bool(c["cluster"]) and c["cluster"] not in ids,"CAMPAIGN_DUPLICATE")
        ids.add(c["cluster"])
        require(c["family"] in REQUIRED_FAMILIES,"CAMPAIGN_FAMILY")
        integer(c["budget"],1,10**9)
        if c["score"] is not None:
            integer(c["score"],-10**30,10**30)
        grouped[c["family"]].append(c)
    require(set(grouped) == set(REQUIRED_FAMILIES),"CALIBRATION_MISSING_FAMILY")
    require(len({c["budget"] for c in campaigns}) == 1,"CAMPAIGN_BUDGET_MISMATCH")
    alpha_cell = Fraction(str(alpha))/total_profiles
    delta_cell = Fraction(str(delta))/(total_profiles*len(REQUIRED_FAMILIES))
    cells, thresholds = {},[]
    for family in REQUIRED_FAMILIES:
        rows = grouped[family]
        order = np_order(len(rows),alpha_cell,delta_cell)
        if order is None:
            return dict(enabled=False,reason="INSUFFICIENT_INDEPENDENT_CAMPAIGNS",family=family,
                        n=len(rows),required_max_order_n=math.ceil(math.log(float(delta_cell))/math.log1p(-float(alpha_cell))))
        k,bound = order
        sorted_scores = sorted((r["score"] for r in rows),key=lambda s: (s is not None,0 if s is None else s))
        threshold = sorted_scores[k-1]
        # A bottom threshold can be valid mathematically. Refuse to enable the
        # reference profile from exclusively structurally blocked tail data.
        if threshold is None:
            return dict(enabled=False,reason="NO_FINITE_CALIBRATION_TAIL",family=family)
        thresholds.append(threshold)
        cells[family] = dict(n=len(rows),k=k,threshold=threshold,violation_bound=bound)
    return dict(enabled=True,approved=False,threshold=max(thresholds),alpha=alpha,delta=delta,
                alpha_cell=str(alpha_cell),delta_cell=str(delta_cell),total_profiles=total_profiles,
                exact_rational_tail_checked=True,
                budget=campaigns[0]["budget"],cells=cells,
                scope="fixed campaign distributions, bounded budget, frozen scoring pipeline")


def upper_binomial(failures: int, trials: int, delta: float = 0.05) -> float:
    require(type(trials) is int and type(failures) is int and 0 <= failures <= trials and trials > 0 and 0 < delta < 1,"BINOMIAL_ARGUMENT")
    return 1.0 if failures == trials else float(beta.ppf(1-delta,failures+1,trials-failures))


GENUINE_CONDITIONS = ("unaided", "ai-informed", "fluent", "revision-heavy")

def audit_gate(attack_counts: dict[str,tuple[int,int]],
               genuine_counts: dict[str,tuple[int,int]], alpha: float = 0.001,
               delta: float = 0.05, total_profiles: int = 1,
               minimum_coverage: float = 0.50) -> dict:
    """A necessary statistical release gate, not authentication of study data.

    Attack pairs are (false-certifying campaigns, total campaigns).
    Genuine pairs are (accepted whole documents, total complete genuine trials).
    Every trial includes abstentions; there is no dropping unsupported sessions.
    """
    require(set(attack_counts) == set(REQUIRED_FAMILIES),"AUDIT_ATTACK_FAMILIES")
    require(set(genuine_counts) == set(GENUINE_CONDITIONS),"AUDIT_GENUINE_CONDITIONS")
    require(type(total_profiles) is int and total_profiles >= 1 and 0 < alpha < 1 and 0 < delta < 1 and 0 < minimum_coverage < 1,"AUDIT_ARGUMENT")
    d=delta/(total_profiles*(len(REQUIRED_FAMILIES)+len(GENUINE_CONDITIONS)))
    attacks,genuine={},{}
    passed=True
    for family,(k,n) in attack_counts.items():
        upper=upper_binomial(k,n,d)
        attacks[family]=dict(failures=k,trials=n,upper=upper)
        passed &= upper <= alpha/total_profiles
    for condition,(k,n) in genuine_counts.items():
        require(type(k) is int and type(n) is int and 0 <= k <= n and n>0,"AUDIT_COUNTS")
        lower=0.0 if k == 0 else float(beta.ppf(d,k,n-k+1))
        genuine[condition]=dict(accepted=k,trials=n,lower=lower)
        passed &= lower >= minimum_coverage
    return dict(statistical_gate_passed=bool(passed),approved=False,attacks=attacks,genuine=genuine,
                alpha=alpha,delta=delta,total_profiles=total_profiles,minimum_coverage=minimum_coverage,
                caveat="Counts require independent protocol review and genuine target labels; identifiers do not prove independence.")
