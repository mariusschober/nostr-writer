"""Reproducible adversarial mechanics, not measurements of human behaviour.

Every generated trace is scripted, even when a laboratory experiment grants it
an admissible-observation assumption. Adaptive search retains every attempt.
"""
from __future__ import annotations
from copy import deepcopy
from dataclasses import replace
from random import Random
from .fixtures import Builder
from .replay import replay
from .verify import score,TrustedInputs,snapshot
from .model import SCORE_FLOOR


def retime(bundle: dict,seed: int,validate: bool=True) -> dict:
    """Change inter-event intervals while preserving the entire partial order.

    Equal timestamps remain equal; all intervals stay on the declared clock grid.
    No text, source, cause, or mutation is changed. Replaying validates each result.
    """
    rng=Random(seed); out=deepcopy(bundle)
    for d in out['documents']:
        times=sorted({x['t'] for x in d['observations']+d['transactions']})
        mapping={}; now=0; res=d['resolution_us']
        for old in times:
            now+=rng.randrange(1,max(2,450_000//res))*res
            mapping[old]=now
        for x in d['observations']+d['transactions']: x['t']=mapping[x['t']]
    if validate: replay(out)
    return out


def staged_transcription(text: str,seed: int=0,profile: str='keyboard') -> dict:
    """Scripted final wording with deliberate insert/delete/revision theatre."""
    b=Builder(profile=profile); rng=Random(seed)
    for i,ch in enumerate(text):
        if i and i%23==0:
            b.splice(len(b.text),len(b.text),'x',delay=rng.randrange(80,500)*1000)
            b.splice(len(b.text)-1,len(b.text),'',delay=rng.randrange(80,500)*1000)
        b.splice(len(b.text),len(b.text),ch,delay=rng.randrange(60,450)*1000)
    result=b.bundle(); replay(result); return result


def adaptive_retiming(bundle: dict,model: dict,context: TrustedInputs,budget: int=100,seed: int=0) -> dict:
    """White-box-available hill search over timing; count all full-pipeline queries.

    This attack is intentionally bounded and incomplete. It does not search all
    valid histories, physical input, alternative wording, or human-assisted acts.
    Scores from this attack do not quantify resistance to stronger attackers.
    Invalid retimed candidates remain counted attempts and are scored fail-closed.
    """
    if type(budget) is not int or not 1<=budget<=10000: raise ValueError('ATTACK_BUDGET')
    rng=Random(seed); best=deepcopy(bundle); best_score=SCORE_FLOOR; attempts=[]
    for i in range(budget):
        candidate=deepcopy(bundle) if i==0 else retime(best,rng.randrange(2**31),validate=False)
        laboratory=replace(context,approved_release=False,model_snapshot=None,
                           document_snapshots=frozenset((d['id'],snapshot(d)) for d in candidate['documents']),
                           fresh_documents=frozenset(d['id'] for d in candidate['documents']))
        outcome=score(candidate,model,laboratory)
        value=outcome['document_score']; max_passage=max(outcome['scalar_scores'],default=SCORE_FLOOR)
        attempts.append({'attempt':i,'valid':outcome['valid'],'document_score':value,
                         'maximum_scalar_score':max_passage})
        if value>best_score: best,best_score=candidate,value
    return {'synthetic':True,'budget':budget,'seed':seed,'attempts':attempts,
            'best_document_score':best_score,'best_trace':best,
            'any_false_scalar_score':max(x['maximum_scalar_score'] for x in attempts),
            'statistical_units':1,'human_accuracy_measured':False,'attack_layer':'conditional-trace-simulation',
            'capture_authentication_tested':False}
