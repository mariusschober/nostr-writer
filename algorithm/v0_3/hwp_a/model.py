"""Pinned, trainable fixed-point tree ensemble and local support test.

Fitting uses NumPy binary64 arithmetic. Exported inference uses integers only.
The exported integers, not a future refit, define a model's decisions.
"""
from __future__ import annotations
from collections import Counter, defaultdict
from .features import Q, quantile, FEATURE_NAMES
from .replay import need, num, shape

HEADS = ('transcription','automation','simulation','mixed')
ROUNDS = 32
DEPTH = 2
LEARNING_RATE = 0.125
LAMBDA = 0.001
MAX_PROTOTYPES = 128
SUPPORT_MIN_CLUSTERS = 99
SCORE_FLOOR = -10**9

def domain(profile: str,language: str,view: str,path: str) -> str:
    return profile+'|'+path+'|'+language+'|'+view

def tree_score(tree: dict,x: list[int]) -> int:
    node=tree
    for _ in range(DEPTH+1):
        if 'value' in node:
            need(set(node)=={'value'},'TREE_LEAF_FIELDS')
            return num(node['value'],-1250,1250)
        shape(node,{'feature','threshold','left','right'})
        j=num(node['feature'],0,len(x)-1); v=num(node['threshold'],-Q,Q)
        node=node['left'] if x[j] <= v else node['right']
    raise ValueError('TREE_DEPTH')

def vector(features: dict[str,int],names: list[str]) -> list[int]:
    need(list(features)==names,'FEATURE_SCHEMA')
    return [num(features[k],-Q,Q) for k in names]

def distance(x: list[int],p: list[int],scales: list[int]) -> int:
    need(len(x)==len(p)==len(scales) and bool(x),'SUPPORT_DIMENSION')
    return sum(Q*abs(a-b)//num(s,500,2*Q) for a,b,s in zip(x,p,scales))//len(x)

def support_distance(x: list[int],artifact: dict) -> int:
    dd=sorted(distance(x,p,artifact['scales']) for p in artifact['prototypes'])
    need(bool(dd),'NO_SUPPORT_REFERENCE')
    return dd[min(4,len(dd)-1)]

def evaluate(features: dict[str,int],artifact: dict,names: list[str]) -> tuple[int,bool,dict]:
    x=vector(features,names)
    need(set(artifact['heads'])==set(HEADS),'MISSING_ATTACK_HEAD')
    margins={}
    for name in HEADS:
        trees=artifact['heads'][name]
        need(type(trees) is list and len(trees)==ROUNDS,'TREE_COUNT')
        margins[name]=sum(tree_score(t,x) for t in trees)
    d=support_distance(x,artifact); reference=artifact['support_calibration']
    need(type(reference) is list and all(type(a) is int and a>=0 for a in reference),'SUPPORT_CALIBRATION')
    numerator=1+sum(a>=d for a in reference); denominator=1+len(reference)
    supported=len(reference)>=SUPPORT_MIN_CLUSTERS and 100*numerator>denominator
    return min(margins.values()),supported,{'heads':margins,'support_distance':d,'support_rank':[numerator,denominator]}


def validate_splits(rows: list[dict]) -> None:
    """Reject links across partitions, including writer/source/campaign dependencies."""
    need(type(rows) is list, 'DATA_ROWS')
    memberships={}; seen=set()
    for r in rows:
        need(type(r) is dict and type(r.get('id')) is str and bool(r['id']), 'DATA_ROW_ID')
        links=r.get('links',{})
        need(type(links) is dict and links.keys() <= {'writer','source','prompt','campaign','actor'}, 'DATA_LINK_FIELDS')
        for values in links.values():
            need(type(values) is list and all(type(v) is str and bool(v) for v in values) and len(values)==len(set(values)), 'DATA_LINK_IDS')
        need(r['split'] in ('train','development','calibration','test','ambiguity'),'DATA_SPLIT')
        need(r['label'] in ('H','U')+HEADS,'DATA_LABEL')
        uid=r['id']; need(uid not in seen,'DUPLICATE_DATA_ROW'); seen.add(uid)
        need(type(r['cluster']) is str and bool(r['cluster']),'DATA_CLUSTER')
        for link in [('cluster',r['cluster'])]+[(k,v) for k in ('writer','source','prompt','campaign','actor') for v in r.get('links',{}).get(k,[])]:
            if link in memberships: need(memberships[link]==r['split'],'DEPENDENT_SPLIT_LEAKAGE')
            memberships[link]=r['split']
        need(r['label']!='U' or r['split']=='ambiguity','AMBIGUOUS_TRAINING_LABEL')


def _weights(rows: list[dict]):
    import numpy as np
    # Half mass per class, equal cluster mass, equal document mass within cluster,
    # equal window mass within each document. Windows are never independent trials.
    groups=defaultdict(lambda:defaultdict(Counter))
    for r in rows: groups[r['binary']][r['cluster']][r['document']]+=1
    return np.array([0.5/len(groups[r['binary']])/len(groups[r['binary']][r['cluster']])/groups[r['binary']][r['cluster']][r['document']] for r in rows])


def _fit_head(rows: list[dict],names: list[str]) -> list[dict]:
    import numpy as np
    X=np.array([vector(r['features'],names) for r in rows],dtype=np.int64)
    y=np.array([r['binary'] for r in rows],dtype=np.float64)
    weight=_weights(rows); logits=np.zeros(len(rows),dtype=np.float64)
    # At most 16 fixed training-quantile cuts per feature. Ties are stable.
    cuts=[]
    for j in range(len(names)):
        values=sorted(set(int(x) for x in X[:,j]))
        cuts.append(sorted({values[min(len(values)-2,(len(values)*k)//17)] for k in range(1,17)}) if len(values)>1 else [])
    trees=[]
    for _ in range(ROUNDS):
        prob=1/(1+np.exp(-np.clip(logits,-30,30)))
        g=weight*(y-prob); h=weight*prob*(1-prob)
        def build(indices,depth):
            G=float(g[indices].sum()); H=float(h[indices].sum())
            # Round to nearest integer; exact half ties away from zero.
            step=max(-1.,min(1.,G/(H+LAMBDA)))*LEARNING_RATE*Q
            leaf={'value':int(step+0.5) if step>=0 else -int(-step+0.5)}
            if depth==DEPTH or len(indices)<4: return leaf
            base=G*G/(H+LAMBDA); best_gain=0.; best=None
            for j,thresholds in enumerate(cuts):
                for cut in thresholds:
                    left=indices[X[indices,j]<=cut]; right=indices[X[indices,j]>cut]
                    if len(left)<2 or len(right)<2: continue
                    gl=float(g[left].sum()); hl=float(h[left].sum()); gr=G-gl; hr=H-hl
                    gain=gl*gl/(hl+LAMBDA)+gr*gr/(hr+LAMBDA)-base
                    if gain>best_gain+1e-12:
                        best_gain=gain; best=(j,cut,left,right)
            if best is None: return leaf
            j,cut,left,right=best
            return {'feature':j,'threshold':cut,'left':build(left,depth+1),'right':build(right,depth+1)}
        tree=build(np.arange(len(rows)),0); trees.append(tree)
        logits+=np.array([tree_score(tree,list(map(int,x)))/Q for x in X])
    return trees


def fit(rows: list[dict],purpose: str = 'research') -> dict:
    """Fit complete supported domains; missing training families exclude the domain.

    Development is used for the human-support calibration only. Threshold/risk
    calibration is a separate function and cannot approve this artifact.
    """
    validate_splits(rows)
    train=sorted((r for r in rows if r['split']=='train'),key=lambda r:r['id']); dev=sorted((r for r in rows if r['split']=='development' and r['label']=='H'),key=lambda r:r['id'])
    need(bool(train),'NO_TRAINING_DATA')
    names=list(train[0]['features']); need(names==list(FEATURE_NAMES),'FEATURE_ORDER')
    for r in train+dev: vector(r['features'],names)
    domains={}
    for z in sorted({r['domain'] for r in train}):
        tt=[r for r in train if r['domain']==z]; hh=[r for r in tt if r['label']=='H']
        if not hh or any(not any(r['label']==head for r in tt) for head in HEADS): continue
        heads={}
        for head in HEADS:
            rr=[dict(r,binary=int(r['label']=='H')) for r in tt if r['label'] in ('H',head)]
            heads[head]=_fit_head(rr,names)
        vectors=[vector(r['features'],names) for r in sorted(hh,key=lambda r:r['id'])]
        scales=[max(500,quantile([v[j] for v in vectors],75)-quantile([v[j] for v in vectors],25)) for j in range(len(names))]
        # Deterministic bounded farthest-first medoids; no random inference component.
        prototypes=[vectors[0]]; remaining=list(vectors[1:])
        while remaining and len(prototypes)<MAX_PROTOTYPES:
            scores=[min(distance(v,p,scales) for p in prototypes) for v in remaining]
            k=max(range(len(scores)),key=lambda i:(scores[i],-i))
            if scores[k]==0: break
            prototypes.append(remaining.pop(k))
        artifact={'heads':heads,'scales':scales,'prototypes':prototypes,'support_calibration':[]}
        clusters={}
        for r in sorted((r for r in dev if r['domain']==z),key=lambda r:r['id']):
            clusters.setdefault(r['cluster'],r) # one preselected unit per independent cluster
        artifact['support_calibration']=[support_distance(vector(r['features'],names),artifact) for r in clusters.values()]
        domains[z]=artifact
    return {'version':'hwp-a-model/0.3','purpose':purpose,'features':names,'domains':domains,
            'training':{'rounds':ROUNDS,'depth':DEPTH,'learning_rate':LEARNING_RATE,'lambda':LAMBDA,
                        'rows':len(train),'domains':len(domains),'support_min_clusters':SUPPORT_MIN_CLUSTERS}}


def validate_model(model: dict) -> None:
    """Validate EVERY tree branch and every numeric value before any inference."""
    from .replay import PROFILES
    shape(model, {'version','purpose','features','domains'}, {'training'})
    need(model['version']=='hwp-a-model/0.3', 'MODEL_VERSION')
    need(model['purpose'] in ('fixture','research','validated-release'), 'MODEL_PURPOSE')
    need(type(model['features']) is list and model['features']==list(FEATURE_NAMES), 'MODEL_FEATURE_SCHEMA')
    need(type(model['domains']) is dict and 0 < len(model['domains']) <= 128, 'MODEL_DOMAIN_LIMIT')
    def visit(node, depth):
        need(type(node) is dict, 'TREE_NODE')
        if 'value' in node:
            shape(node, {'value'}); num(node['value'],-1250,1250); return
        need(depth < DEPTH, 'TREE_DEPTH')
        shape(node, {'feature','threshold','left','right'})
        num(node['feature'],0,len(FEATURE_NAMES)-1); num(node['threshold'],-Q,Q)
        visit(node['left'],depth+1); visit(node['right'],depth+1)
    for z,a in model['domains'].items():
        need(type(z) is str and len(z)<=256, 'MODEL_DOMAIN')
        parts=z.split('|')
        need(len(parts)==4 and parts[0] in PROFILES and parts[1] and parts[2] and parts[3] in ('birth','retained','layout','global'), 'MODEL_DOMAIN')
        shape(a, {'heads','scales','prototypes','support_calibration'})
        need(type(a['heads']) is dict and set(a['heads'])==set(HEADS), 'MODEL_HEADS')
        for trees in a['heads'].values():
            need(type(trees) is list and len(trees)==ROUNDS, 'TREE_COUNT')
            for t in trees: visit(t,0)
        need(type(a['scales']) is list and len(a['scales'])==len(FEATURE_NAMES), 'SUPPORT_DIMENSION')
        for v in a['scales']: num(v,500,2*Q)
        need(type(a['prototypes']) is list and 1<=len(a['prototypes'])<=MAX_PROTOTYPES, 'PROTOTYPE_COUNT')
        for vector_ in a['prototypes']:
            need(type(vector_) is list and len(vector_)==len(FEATURE_NAMES), 'SUPPORT_DIMENSION')
            for v in vector_: num(v,-Q,Q)
        ref=a['support_calibration']
        need(type(ref) is list and len(ref)<=100_000, 'SUPPORT_CALIBRATION_LIMIT')
        for v in ref: num(v,0,10**9)
