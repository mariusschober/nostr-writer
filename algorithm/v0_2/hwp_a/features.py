"""Fixed-point process features. Text contextualizes actions; no AI prose detector.

Every numeric feature is an integer. Q=10000 represents one. Counts/quantiles
have declared caps. Missing measurements have explicit presence indicators.
"""
from __future__ import annotations
from collections import Counter
from math import isqrt
from .replay import Corpus, Unit, Effect, related, PROFILES

Q = 10_000
GAP_EDGES = (50_000,150_000,400_000,1_000_000,3_000_000,10_000_000,30_000_000)
LENGTH_EDGES = (0,1,4,16,64)
KINDS = ('insert','delete','replace','move','undo','redo')

def ratio(n: int,d: int) -> int:
    return min(Q,max(-Q,Q*n//d)) if d else 0

def scale(n: int,cap: int) -> int:
    return ratio(min(max(n,0),cap),cap)

def quantile(xx: list[int], numerator: int, denominator: int = 100) -> int:
    if not xx: return 0
    ss = sorted(xx)
    return ss[max(0,(len(ss)*numerator+denominator-1)//denominator-1)]

def bucket(x: int, edges: tuple[int,...]) -> int:
    return next((i for i,b in enumerate(edges) if x <= b),len(edges))

def kind(e: Effect) -> str:
    if e.op != 'splice': return e.op
    return 'replace' if e.old and e.new else 'delete' if e.old else 'insert'

def stats(out: dict,prefix: str,values: list[int],cap: int) -> None:
    out[prefix+'.present'] = Q if values else 0
    for p in (10,50,90): out[prefix+f'.p{p}'] = scale(quantile(values,p),cap)
    out[prefix+'.mean'] = scale(sum(values)//len(values),cap) if values else 0
    out[prefix+'.spread'] = scale(quantile(values,90)-quantile(values,10),cap) if values else 0

def hist(out: dict,prefix: str,values: list[int],edges: tuple[int,...]) -> None:
    counts = Counter(bucket(x,edges) for x in values)
    for b in range(len(edges)+1): out[f'{prefix}.{b}'] = ratio(counts[b],len(values))

def corr(xs: list[int],ys: list[int]) -> int:
    if len(xs) < 3: return 0
    n = len(xs); sx=sum(xs); sy=sum(ys)
    ax = [n*x-sx for x in xs]; ay = [n*y-sy for y in ys]
    den = isqrt(sum(x*x for x in ax)*sum(y*y for y in ay))
    return ratio(sum(x*y for x,y in zip(ax,ay)),den)


def extract(c: Corpus,u: Unit) -> dict[str,int]:
    d = c.documents[u.doc]; es = related(c,u); rr = set(u.roots)
    n = len(es); f = {}
    for view in ('birth','retained','layout','global'): f['view.'+view] = Q if u.view == view else 0
    f['roots'] = scale(len(rr),256)
    f['events'] = scale(n,1024)
    productions = [e for e in es if rr.intersection(e.born)]
    f['production.events'] = scale(len(productions),256)
    f['production.per_root'] = ratio(len(productions),len(rr))
    f['resolution'] = scale(d.resolution,10000)
    f['syntactic.barrier_fraction'] = ratio(sum(e.barrier for e in es),n)
    for op in KINDS: f['op.'+op] = ratio(sum(kind(e)==op for e in es),n)
    for source in ('direct','spelling','paste','generated','unknown','control'):
        f['source.'+source] = ratio(sum(e.source==source for e in es),n)
    hist(f,'insert.length',[len(e.new) for e in es],LENGTH_EDGES)
    hist(f,'delete.length',[len(e.old) for e in es],LENGTH_EDGES)
    inserted = sum(len(e.new) for e in es if e.op == 'splice')
    deleted = sum(len(e.old) for e in es if e.op == 'splice')
    f['deleted.per_inserted'] = ratio(deleted,inserted)
    f['surviving.evidence_fraction'] = ratio(len(rr),sum(len(e.born) for e in productions))
    f['at_document_front'] = ratio(sum(e.pos*4 < max(1,e.before_length) for e in es),n)
    f['at_document_tail'] = ratio(sum(e.pos >= e.before_length for e in es),n)
    stats(f,'navigation',[e.navigation for e in es],4096)
    stats(f,'revision.age',[age for e in es for age in e.ages if age>0],4096)
    touched_counts = Counter(r for e in es for r in e.touched if r in rr)
    f['revisited.roots'] = ratio(sum(k>1 for k in touched_counts.values()),len(rr))
    f['revisited.repeat_fraction'] = ratio(sum(max(0,k-1) for k in touched_counts.values()),sum(touched_counts.values()))
    # Only consecutive, uninterrupted source-document transactions provide pause evidence.
    gaps, contexts, pairs, uncertain, excluded = [],[],[],0,0
    for a,b in zip(es,es[1:]):
        if b.index != a.index+1 or a.run != b.run or b.barrier:
            excluded += 1; continue
        gap = b.time-a.time
        lo,hi = max(0,gap-2*d.resolution),gap+2*d.resolution
        if hi > GAP_EDGES[-1] or bucket(lo,GAP_EDGES) != bucket(hi,GAP_EDGES):
            uncertain += 1; continue
        gaps.append(gap); contexts.append(b.preceding); pairs.append((a,b))
    f['gap.censored'] = ratio(uncertain+excluded,max(0,n-1))
    stats(f,'gap',gaps,GAP_EDGES[-1]); hist(f,'gap.bin',gaps,GAP_EDGES)
    for ctx in range(4):
        cg = [g for g,x in zip(gaps,contexts) if x == ctx]
        f[f'context.{ctx}.present'] = Q if cg else 0
        f[f'context.{ctx}.pause'] = scale(quantile(cg,50),3_000_000)
        for b in range(len(GAP_EDGES)+1):
            f[f'context.{ctx}.gap.{b}'] = ratio(sum(x==ctx and bucket(g,GAP_EDGES)==b for g,x in zip(gaps,contexts)),len(gaps))
    f['gap.identical_adjacent'] = ratio(sum(a==b for a,b in zip(gaps,gaps[1:])),max(0,len(gaps)-1))
    f['gap.concentration'] = ratio(sum(v*v for v in Counter(gaps).values()),len(gaps)**2)
    for a in KINDS:
        for b in KINDS: f[f'transition.{a}.{b}'] = ratio(sum(kind(x)==a and kind(y)==b for x,y in pairs),len(pairs))
    # Motor dwell is distinct from process pause. Overlap between presses is legal.
    starts, durations = {}, {}
    for o in d.observations:
        if o['kind'] in ('press','touch_down','gesture_start'): starts[(o['kind'],o['token'])] = o
        if o['kind'] in ('release','touch_up','gesture_end'):
            sk = {'release':'press','touch_up':'touch_down','gesture_end':'gesture_start'}[o['kind']]
            begin = starts.get((sk,o['token']))
            if begin:
                durations[begin['i']] = o['t']-begin['t']
                if o['kind']=='gesture_end': durations[o['i']] = o['t']-begin['t']
    causes = {i for e in productions for i in e.causes}
    motor = set(causes)
    for i in causes: motor.update(d.observations[i].get('basis',[]))
    dwells = [durations[i] for i in motor if i in durations]
    stats(f,'motor.dwell',dwells,1_000_000)
    f['motor.coverage'] = ratio(len(dwells),len(motor))
    f['motor.actions_per_production'] = scale(len(motor)//max(1,len(productions)),32)
    movements = [abs(b.pos-a.pos-len(a.new)) for a,b in zip(es,es[1:])]
    stats(f,'edit.distance',movements,4096)
    f['edit.backward'] = ratio(sum(b.pos<a.pos for a,b in zip(es,es[1:])),max(0,n-1))
    f['edit.remote'] = ratio(sum(v>32 for v in movements),len(movements))
    # No inference that these lexical relations are semantic understanding.
    cancel, propagation, opportunities, coupling = 0,0,0,[]
    for i,e in enumerate(es):
        if e.op == 'splice' and e.new:
            prior = es[max(0,i-8):i]
            cancel += any(p.old == e.new and p.old and e.time-p.time <= 5_000_000 for p in prior)
        if e.op == 'splice' and e.old and e.new and e.old != e.new and max(len(e.old),len(e.new)) <= 64:
            opportunities += 1
            following = es[i+1:i+65]
            propagation += any(p.old == e.old and p.new == e.new and abs(p.pos-e.pos)>32 for p in following)
            a = {e.new[k:k+3] for k in range(max(0,len(e.new)-2))}
            later = ''.join(p.new for p in following[:8])[:128]
            b = {later[k:k+3] for k in range(max(0,len(later)-2))}
            if a and b: coupling.append(ratio(len(a&b),len(a|b)))
    f['revision.cancel_fraction'] = ratio(cancel,n)
    f['revision.propagation_present'] = Q if opportunities else 0
    f['revision.propagation_fraction'] = ratio(propagation,opportunities)
    stats(f,'revision.lexical_coupling',coupling,Q)
    bursts=[]; current=0
    for i,e in enumerate(es):
        if i and (e.index != es[i-1].index+1 or e.run != es[i-1].run or e.time-es[i-1].time > 1_000_000):
            if current: bursts.append(current)
            current=0
        current += len(rr.intersection(e.born))
    if current: bursts.append(current)
    stats(f,'burst.roots',bursts,256)
    f['pause.next_insert_correlation'] = corr(gaps,[len(b.new) for a,b in pairs])
    # Explicit process shifts: four chronological quarters, no average erasing a switch.
    quarter_gaps, quarter_revisions = [],[]
    for k in range(4):
        part=es[n*k//4:n*(k+1)//4]
        pg=[b.time-a.time for a,b in zip(part,part[1:]) if b.index==a.index+1 and a.run==b.run and not b.barrier and b.time-a.time<=30_000_000]
        if pg: quarter_gaps.append(scale(quantile(pg,50),3_000_000))
        if part: quarter_revisions.append(ratio(sum(kind(e) in ('delete','replace','move','undo','redo') for e in part),len(part)))
    f['shift.gap'] = max(quarter_gaps)-min(quarter_gaps) if quarter_gaps else 0
    f['shift.revision'] = max(quarter_revisions)-min(quarter_revisions) if quarter_revisions else 0
    return dict(sorted(f.items()))


def adequate(c: Corpus,u: Unit) -> bool:
    if len(set(u.roots)) < 64: return False
    es=related(c,u); rr=set(u.roots)
    # Count distinct producing transactions, not characters, moves, copies, or preedit updates.
    production={(c.documents[u.doc].observations[i]['kind'] if c.documents[u.doc].observations[i]['kind']!='repeat' else 'press',c.documents[u.doc].observations[i]['token']) for e in es if rr.intersection(e.born) for i in e.causes}
    return len(production) >= PROFILES[u.profile][2]
