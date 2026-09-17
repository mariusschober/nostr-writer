"""Fixed finite-family calibration with exact binomial confidence bounds.

The statistical unit is an independent participant/attack campaign cluster.
Every adaptive attempt and every falsely certified passage inside that cluster
is aggregated BEFORE counting a Bernoulli trial. Unknown attacks are not covered.
"""
from __future__ import annotations
from collections import defaultdict
from fractions import Fraction
from math import ceil,log,expm1
from .replay import need,num
from .model import SCORE_FLOOR

FAMILIES=('human_transcription','scripted_input','replay','staged_revision','adaptive_simulation','mixed_origin','lineage_laundering','capture_fabrication')
EPSILON=0.001
DELTA=0.05
MIN_COVERAGE=0.50
MAX_THRESHOLDS=32


def upper(k: int,n: int,alpha: float) -> float:
    from scipy.stats import beta
    need(type(k) is int and type(n) is int and 0<=k<=n and 0<alpha<1,'BINOMIAL_ARGUMENTS')
    if n==0 or k==n: return 1.0
    if k==0: return -expm1(log(alpha)/n)
    return float(beta.ppf(1-alpha,k+1,n-k))

def lower(k: int,n: int,alpha: float) -> float:
    from scipy.stats import beta
    need(type(k) is int and type(n) is int and 0<=k<=n and 0<alpha<1,'BINOMIAL_ARGUMENTS')
    return 0.0 if n==0 or k==0 else float(beta.ppf(alpha,k,n-k+1))

def zero_failure_n(epsilon: float,alpha: float) -> int:
    need(0<epsilon<1 and 0<alpha<1,'PROBABILITY_ARGUMENTS')
    return ceil(log(alpha)/log(1-epsilon))


def exact_lower_tail_at_most(k: int,n: int,p,alpha) -> bool:
    """Exact rational binomial test; floating quantiles never grant eligibility.

    Evaluate Pr[Binomial(n,p) <= k] <= alpha by nonnegative integer terms.
    Stop as soon as the partial sum exceeds the threshold. Decimal input
    probabilities are interpreted by Fraction(str(value)). No independence
    assumption is created by this arithmetic; that remains a study requirement.
    """
    p=p if isinstance(p,Fraction) else Fraction(str(p))
    alpha=alpha if isinstance(alpha,Fraction) else Fraction(str(alpha))
    need(type(k) is int and type(n) is int and 0<=k<=n and 0<=p<=1 and 0<alpha<1,'EXACT_BINOMIAL_ARGUMENTS')
    if n==0: return False
    if p==0: return False
    if p==1: return k<n
    a,b=p.numerator,p.denominator
    right=alpha.numerator*pow(b,n)
    term=pow(b-a,n); total=0
    for i in range(k+1):
        total+=term
        if total*alpha.denominator>right: return False
        if i<k: term=term*(n-i)*a//((i+1)*(b-a))
    return True


def thresholds(development_scores: list[int]) -> list[int]:
    valid=sorted(set(num(x,SCORE_FLOOR+1,10**9-1) for x in development_scores if x>SCORE_FLOOR))
    if not valid: return [10**9]
    # Include all-pass / reject-all boundaries. Grid fixed before calibration.
    idx={min(len(valid)-1,len(valid)*k//30) for k in range(30)}
    return sorted({valid[0],10**9}|{valid[i] for i in idx})[:MAX_THRESHOLDS]


def calibrate(records: list[dict],candidates: list[int],required_cells: list[str],required_human_cells: list[str],epsilon: float=EPSILON,delta: float=DELTA,min_coverage: float=MIN_COVERAGE) -> dict:
    """records: cell, cluster, kind='attack'|'human', score.

    An attack score is the MAXIMUM false-origin score over all attempts/passages
    for that campaign. A human score is the MINIMUM document score of that
    participant's prespecified qualifying tasks. Required cells must be fixed
    externally before evaluation; this function never infers them from successes.
    """
    need(0<epsilon<1 and 0<delta<1 and 0<=min_coverage<=1,'CALIBRATION_TARGETS')
    need(0<len(candidates)<=MAX_THRESHOLDS and candidates==sorted(set(candidates)),'THRESHOLD_GRID')
    for t in candidates: num(t,SCORE_FLOOR+1,10**9)
    need(bool(required_cells) and len(required_cells)==len(set(required_cells)),'REQUIRED_CELLS')
    attacks=defaultdict(dict); humans=defaultdict(dict)
    need(bool(required_human_cells) and len(set(required_human_cells))==len(required_human_cells),'REQUIRED_HUMAN_CELLS')
    human_cells=set(required_human_cells)
    for r in records:
        need(set(r)=={'cell','cluster','kind','score'},'CALIBRATION_FIELDS')
        need(type(r['cell']) is str and type(r['cluster']) is str and r['cluster'],'CALIBRATION_ID')
        num(r['score'],SCORE_FLOOR,10**9)
        if r['kind']=='attack':
            need(r['cell'] in required_cells,'UNREGISTERED_ATTACK_CELL')
            old=attacks[r['cell']].get(r['cluster'],SCORE_FLOOR)
            attacks[r['cell']][r['cluster']]=max(old,r['score'])
        elif r['kind']=='human':
            need(r['cell'] in human_cells,'UNREGISTERED_HUMAN_CELL')
            old=humans[r['cell']].get(r['cluster'],10**9)
            humans[r['cell']][r['cluster']]=min(old,r['score'])
        else: need(False,'CALIBRATION_KIND')
    # Missing a required attack cell prevents any release, even with zero observed errors.
    exact_alpha_attack=Fraction(str(delta))/2/(len(required_cells)*len(candidates))
    exact_alpha_human=Fraction(str(delta))/2/(len(human_cells)*len(candidates))
    alpha_attack=float(exact_alpha_attack); alpha_human=float(exact_alpha_human)
    reports=[]
    for t in candidates:
        cells={}; valid=bool(human_cells)
        for cell in required_cells:
            ss=list(attacks[cell].values()); k=sum(x>=t for x in ss); bound=upper(k,len(ss),alpha_attack)
            passes=exact_lower_tail_at_most(k,len(ss),epsilon,exact_alpha_attack) if ss else False
            cells[cell]={'n':len(ss),'failures':k,'upper':bound,'exact_test_passed':passes}; valid &= passes
        cover={}
        for cell in sorted(human_cells):
            ss=list(humans[cell].values()); k=sum(x>=t for x in ss); bound=lower(k,len(ss),alpha_human)
            passes=bool(ss) and (min_coverage==0 or exact_lower_tail_at_most(len(ss)-k,len(ss),1-Fraction(str(min_coverage)),exact_alpha_human))
            cover[cell]={'n':len(ss),'all_tasks_passed':k,'lower':bound,'exact_test_passed':passes}; valid &= passes
        reports.append({'threshold':t,'attack':cells,'coverage':cover,'eligible':bool(valid)})
    selected=next((r['threshold'] for r in reports if r['eligible']),None)
    return {'threshold':selected,'eligible':selected is not None,'epsilon':epsilon,'delta':delta,
            'min_coverage':min_coverage,'alpha_attack':alpha_attack,'alpha_human':alpha_human,
            'required_cells':required_cells,'required_human_cells':required_human_cells,'reports':reports,
            'scope':'fixed campaign distributions and assumptions; not universal adversarial soundness',
            'approval_granted':False}


def campaign_score(scored_attempts: list[dict],false_scalar_masks: list[list[bool]]) -> int:
    """Any false certified scalar is a failure; no paragraph-size exception."""
    need(len(scored_attempts)==len(false_scalar_masks) and bool(scored_attempts),'CAMPAIGN_ALIGNMENT')
    result=SCORE_FLOOR
    for attempt,mask in zip(scored_attempts,false_scalar_masks):
        if not attempt.get('valid'): continue
        scores=attempt['scalar_scores']; need(len(scores)==len(mask) and all(type(b) is bool for b in mask),'GROUND_TRUTH_ALIGNMENT')
        result=max(result,max((s for s,bad in zip(scores,mask) if bad),default=SCORE_FLOOR))
    return result
