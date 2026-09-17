"""Raw annotated cases -> exact features, risk records, and evaluation counts.

Labels are task-condition annotations, never inferred from an AI-content score.
All creation transactions must be labelled; ambiguous cognition stays U.
"""
from .replay import replay,make_units,need,num,shape
from .features import extract
from .model import domain,HEADS,validate_splits
from .calibration import campaign_score
from .verify import score,TrustedInputs


def labels_for(case: dict,c):
    result={}
    need(type(case['labels']) is list,'GROUND_TRUTH_LABELS')
    for did,d in c.documents.items():
        segments=[x for x in case['labels'] if x['document']==did]
        cursor=0
        for x in segments:
            shape(x,{'document','start_tx','end_tx','label'})
            need(num(x['start_tx'])==cursor and x['label'] in ('H','U')+HEADS,'GROUND_TRUTH_PARTITION')
            end=num(x['end_tx'],cursor+1,len(d.effects))
            for i in range(cursor,end): result[(did,i)]=x['label']
            cursor=end
        need(cursor==len(d.effects),'GROUND_TRUTH_INCOMPLETE')
    need(all(x['document'] in c.documents for x in case['labels']),'GROUND_TRUTH_UNKNOWN_DOCUMENT')
    return result


def extract_case(case: dict) -> list[dict]:
    shape(case,{'id','cluster','split','links','bundle','labels','condition'})
    c=replay(case['bundle']); annotations=labels_for(case,c); out=[]
    derived_labels={}
    for d in c.documents.values():
        for aid in d.live:
            a=c.atoms[aid]
            if a.spelling:
                for root in a.roots: derived_labels.setdefault(root,set()).add(annotations[(a.home,a.birth)])
    for did in c.documents:
        uu,_=make_units(c,did)
        for u in uu:
            labels={annotations[(c.atoms[r].home,c.atoms[r].birth)] for r in u.roots}
            for root in u.roots: labels.update(derived_labels.get(root,()))
            if 'U' in labels: label='U'
            elif labels=={'H'}: label='H'
            elif len(labels-{'H'})==1: label=next(iter(labels-{'H'}))
            else: label='mixed'
            if label=='U' and case['split']!='ambiguity': continue # ambiguous units never enter supervised fitting
            out.append({'id':case['id']+'/'+u.uid,'cluster':case['cluster'],'document':case['id']+'/'+did,
                        'split':case['split'],'links':case['links'],'domain':domain(u.profile,u.language,u.view,c.documents[u.doc].paths[u.profile]),
                        'label':label,'features':extract(c,u)})
    return out


def extract_dataset(cases: list[dict]) -> list[dict]:
    # Validate case dependencies before units are extracted; empty/unsupported cases cannot erase links.
    need(type(cases) is list, 'DATA_CASES')
    validate_splits([{'id':case['id'],'cluster':case['cluster'],'split':case['split'],
                     'links':case['links'],'label':'U' if case['split']=='ambiguity' else 'H'} for case in cases])
    rows=[row for case in cases for row in extract_case(case)]
    validate_splits(rows)
    return rows


def false_mask(case: dict) -> list[bool]:
    c=replay(case['bundle']); lab=labels_for(case,c); target=c.documents[case['bundle']['target']]
    out=[]
    for aid in target.live:
        a=c.atoms[aid]
        # For release RISK use the worst-case interpretation of U; keep descriptive U counts separate.
        out.append(not a.roots or any(lab[(c.atoms[r].home,c.atoms[r].birth)] != 'H' for r in a.roots)
                   or (a.spelling and lab[(a.home,a.birth)] != 'H'))
    return out


def risk_record(case: dict,model: dict,context: TrustedInputs,cell: str,kind: str) -> dict:
    scored=score(case['bundle'],model,context)
    need(kind in ('human','attack'), 'RISK_KIND')
    if kind=='human':
        labels=set(labels_for(case,replay(case['bundle'])).values()) if scored['valid'] else set()
        value=scored['document_score'] if labels=={'H'} else -10**9
    else: value=campaign_score([scored],[false_mask(case)]) if scored['valid'] else -10**9
    return {'cell':cell,'cluster':case['cluster'],'kind':kind,'score':value}
