"""Descriptive accuracy/coverage from labelled raw cases. No automatic approval."""
from .replay import replay,SPACE,need
from .dataset import labels_for
from .verify import score
from .model import SCORE_FLOOR


def evaluate_cases(cases: list[dict],model: dict,contexts: dict,threshold: int) -> dict:
    """Report candidate admissions, including unsupported captures in coverage.

    Labelled U scalars are excluded from known-class confusion and counted
    separately. A benchmark precision number is not a document's probability of
    human authorship. Confidence/cluster risk control belongs to calibration.py.
    """
    totals={'qualifying_documents':0,'nonqualifying_documents':0,'ambiguous_documents':0,
            'qualifying_admitted':0,'nonqualifying_admitted':0,'ambiguous_admitted':0,
            'qualifying_scalars':0,'false_origin_scalars':0,'ambiguous_scalars':0,
            'qualifying_scalars_admitted':0,'false_origin_scalars_admitted':0,'ambiguous_scalars_admitted':0,
            'invalid_attempts':0,'unlabelled_invalid_attempts':0}
    campaigns={}; details=[]
    for case in cases:
        need(case['id'] in contexts,'MISSING_EXPERIMENT_CONTEXT')
        result=score(case['bundle'],model,contexts[case['id']]); valid=result['valid']
        if not valid:
            totals['invalid_attempts']+=1
            # Preserve known task-condition denominators even when replay fails.
            labels={x.get('label') for x in case.get('labels',[]) if type(x) is dict}
            category='qualifying' if labels=={'H'} else 'nonqualifying' if labels-{'H','U',None} else 'ambiguous' if 'U' in labels else None
            if category: totals[category+'_documents']+=1
            else: totals['unlabelled_invalid_attempts']+=1
            campaigns.setdefault(case['cluster'],False)
            details.append({'id':case['id'],'valid':False,'candidate_admitted':False,'reason':result.get('reason')})
            continue
        c=replay(case['bundle']); lab=labels_for(case,c); d=c.documents[case['bundle']['target']]
        kinds=[]
        for aid in d.live:
            atom=c.atoms[aid]
            ls={lab[(c.atoms[r].home,c.atoms[r].birth)] for r in atom.roots}
            if atom.spelling: ls.add(lab[(atom.home,atom.birth)])
            kinds.append('false_origin' if not ls or ls-{'H','U'} else 'ambiguous' if 'U' in ls else 'qualifying')
        passed=[v>=threshold for v in result['scalar_scores']]
        qualifying=bool(kinds) and set(kinds)=={'qualifying'} and any(ch not in SPACE for ch in d.text)
        category='qualifying' if qualifying else 'nonqualifying' if 'false_origin' in kinds else 'ambiguous'
        whole=bool(passed) and all(passed) and any(ch not in SPACE for ch in d.text)
        totals[category+'_documents']+=1; totals[category+'_admitted']+=int(whole)
        for k,p in zip(kinds,passed):
            totals[k+'_scalars']+=1; totals[k+'_scalars_admitted']+=int(p)
        bad=any(p and k=='false_origin' for p,k in zip(passed,kinds))
        campaigns[case['cluster']]=campaigns.get(case['cluster'],False) or bad
        details.append({'id':case['id'],'valid':True,'condition':case['condition'],'category':category,
                        'candidate_admitted':whole,'any_false_scalar_admitted':bad})
    def fraction(a,b): return a/b if b else None
    tp=totals['qualifying_admitted']; fp=totals['nonqualifying_admitted']
    return {'threshold':threshold,'counts':totals,'attempts':len(cases),
            'document_coverage':fraction(tp,totals['qualifying_documents']),
            'document_false_admission':fraction(fp,totals['nonqualifying_documents']),
            'benchmark_precision':fraction(tp,tp+fp),
            'campaigns':len(campaigns),'campaigns_with_false_scalar':sum(campaigns.values()),
            'details':details,'approval_granted':False,
            'interpretation':'Candidate decisions on this labelled benchmark, not per-document probabilities. Known task-condition labels preserve invalid-attempt document denominators; unlabelled invalid attempts require resolution against the preregistered ledger.'}
