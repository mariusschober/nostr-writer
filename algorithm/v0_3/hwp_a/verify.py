"""Binary verdict and complete UTF-8 passage partition.

TrustedInputs are arguments provided by a relying verifier, NEVER fields read
from an author's telemetry. This module does not authenticate capture or approve
statistical evidence; those are explicit external prerequisites.
"""
from __future__ import annotations
from dataclasses import dataclass
from typing import Any
import json
from . import HUMAN, NOT_PROVABLE
from .replay import replay,make_units,observed_source_matches,utf8_offsets,scalar_range,InvalidTrace,need,num,SPACE
from .features import extract,adequate
from .model import domain,evaluate,validate_model,SCORE_FLOOR

@dataclass(frozen=True)
class TrustedInputs:
    admissible_documents: frozenset[str] = frozenset()
    approved_release: bool = False
    approved_threshold: int | None = None
    # An approved release must cover these exact observable domains/assumptions.
    allowed_domains: frozenset[str] = frozenset()
    document_snapshots: frozenset[tuple[str,str]] = frozenset()
    fresh_documents: frozenset[str] = frozenset()
    model_snapshot: str | None = None
    approved_claim: str = 'fresh-composition'


def snapshot(value: Any) -> str:
    return json.dumps(value,sort_keys=True,ensure_ascii=True,allow_nan=False,separators=(',',':'))


def score(bundle: dict,model: dict | None,context: TrustedInputs = TrustedInputs(),claim_kind: str='fresh-composition') -> dict:
    """Complete threshold-independent computation, used identically in calibration.

    candidate_scores are diagnostics, not certification labels. A valid capture
    assumption is mandatory even for candidate scoring; experiment fixtures must
    explicitly supply their laboratory assumption rather than smuggle it in JSON.
    """
    try:
        need(claim_kind in ('fresh-composition','wording-origin'), 'CLAIM_KIND')
        raw=snapshot(bundle); need(len(raw)<=100_000_000,'INPUT_SIZE_LIMIT'); bundle=json.loads(raw)
        if model is not None:
            raw_model=snapshot(model); need(len(raw_model)<=20_000_000,'MODEL_SIZE_LIMIT'); model=json.loads(raw_model)
        c=replay(bundle); target=c.documents[bundle['target']]
        need(model is not None,'MODEL_UNAVAILABLE'); validate_model(model)
        need(isinstance(context,TrustedInputs), 'TRUST_CONTEXT')
        admitted = {did for did in context.admissible_documents if did in context.fresh_documents and
                    any(d['id']==did and (did,snapshot(d)) in context.document_snapshots for d in bundle['documents'])}
        raw_roots={}; root_reasons={}; unit_reports={}
        all_members={}; unit_by_id={}
        for did in c.documents:
            uu,members=make_units(c,did)
            all_members.update(members)
            for u in uu:
                unit_by_id[u.uid]=u
                reason=None; value=SCORE_FLOOR; details={}
                z=domain(u.profile,u.language,u.view,c.documents[u.doc].paths[u.profile])
                if did not in admitted or c.documents[did].gap or c.documents[did].unsafe_control: reason='CAPTURE_NOT_ADMISSIBLE'
                elif z not in context.allowed_domains or z not in model['domains']: reason='UNSUPPORTED_DOMAIN'
                elif not adequate(c,u): reason='INSUFFICIENT_LOCAL_EVIDENCE'
                else:
                    value,supported,details=evaluate(extract(c,u),model['domains'][z],model['features'])
                    if not supported: value=SCORE_FLOOR; reason='OUTSIDE_SUPPORTED_PROCESS'
                unit_reports[u.uid]={'score':value,'reason':reason,'domain':z,'root_count':len(u.roots),'details':details}
        for r,a in c.atoms.items():
            if a.kind!='candidate' or a.roots!=frozenset({r}): continue
            ids=all_members.get(r,[]); views={unit_by_id[i].view for i in ids}
            if not {'birth','retained','layout','global'}<=views:
                raw_roots[r]=SCORE_FLOOR; root_reasons[r]='NO_COMPLETE_ORIGIN_NEIGHBOURHOOD'
            else:
                worst=min(ids,key=lambda i:(unit_reports[i]['score'],i))
                raw_roots[r]=unit_reports[worst]['score']; root_reasons[r]=unit_reports[worst]['reason']
        # A source match in any ancestor version must not become clean by importing it.
        blocked_roots=set(); blocked_occurrences={}
        for did in c.documents:
            blocked=observed_source_matches(c,did); blocked_occurrences[did]=blocked
            for aid in blocked: blocked_roots.update(c.atoms[aid].roots)
        vals=[]; reasons=[]; origin_types=[]; origin_documents=[]; offsets=utf8_offsets(target.text)
        for aid in target.live:
            a=c.atoms[aid]
            if not a.requirements<=admitted or any(c.documents[d].gap or c.documents[d].unsafe_control for d in a.requirements):
                v,reason=SCORE_FLOOR,'CAPTURE_NOT_ADMISSIBLE'
            elif not a.roots: v,reason=SCORE_FLOOR,'EXTERNAL_OR_UNKNOWN_ORIGIN'
            elif aid in blocked_occurrences[target.did] or a.roots & blocked_roots:
                v,reason=SCORE_FLOOR,'OBSERVED_SOURCE_REUSE'
            else:
                v=min((raw_roots.get(r,SCORE_FLOOR) for r in a.roots),default=SCORE_FLOOR)
                reason=next((root_reasons.get(r) for r in sorted(a.roots) if raw_roots.get(r,SCORE_FLOOR)==v),None)
            if claim_kind=='fresh-composition' and (a.roots!=frozenset({aid}) or a.home!=target.did):
                v,reason=SCORE_FLOOR,'NOT_FRESH_COMPOSITION'
            vals.append(v); reasons.append(reason)
            origin_types.append('external' if not a.roots else 'spelling' if a.spelling else 'direct' if a.roots==frozenset({aid}) else 'inherited')
            origin_documents.append(sorted({c.atoms[r].home for r in a.roots}))
        return {'valid':True,'target':target.did,'text':target.text,'offsets':offsets,'scalar_scores':vals,'reasons':reasons,
                'document_score':min(vals,default=SCORE_FLOOR) if any(ch not in SPACE for ch in target.text) else SCORE_FLOOR,'units':unit_reports,'origin_types':origin_types,'origin_documents':origin_documents,
                'algorithm_version':'hwp-a/0.3','claim_kind':claim_kind,'model_snapshot':snapshot(model)}
    except (InvalidTrace,ValueError,TypeError,KeyError,IndexError,OverflowError,RecursionError) as e:
        return {'valid':False,'reason':str(e) if isinstance(e,InvalidTrace) else 'MALFORMED_INPUT','scalar_scores':[],'document_score':SCORE_FLOOR,'units':{}}


def decide(scored: dict,threshold: int,certification_enabled: bool=False,excluded: list[dict]|None=None,claim_kind: str='fresh-composition') -> dict:
    """No selected favourable segmentation. Exclusions change scope, never origin.

    Whole-document HUMAN requires every byte and no exclusion. The contribution
    verdict is separately scoped. Report spans also distinguish excluded quotes.
    """
    base={'verdict':NOT_PROVABLE,'contribution_verdict':NOT_PROVABLE,'ranges':[],'reason':None}
    if not scored.get('valid'): return dict(base,reason=scored.get('reason','INVALID_TRACE'))
    try:
        num(threshold,SCORE_FLOOR+1,10**9)
        need(claim_kind in ('fresh-composition','wording-origin') and claim_kind==scored['claim_kind'], 'CLAIM_KIND')
        need(type(certification_enabled) is bool, 'CERTIFICATION_FLAG')
        text=scored['text']; vals=scored['scalar_scores']; oo=scored['offsets']
        need(len(vals)==len(text)==len(scored['reasons'])==len(scored['origin_types'])==len(scored['origin_documents']) and oo==utf8_offsets(text), 'SCORE_ALIGNMENT')
        if claim_kind=='fresh-composition':
            vals=[v if scored['origin_types'][i]=='direct' and scored['origin_documents'][i]==[scored['target']] else SCORE_FLOOR for i,v in enumerate(vals)]
        need(excluded is None or type(excluded) is list, 'EXCLUSION_LIST')
        mask=[False]*len(text); exclusion_ids=[None]*len(text); prev=0
        for n,x in enumerate(excluded or []):
            need(type(x) is dict and set(x)=={'start','end','source'},'EXCLUSION_FIELDS')
            a,b=scalar_range(text,x['start'],x['end'])
            need(a<b and a>=prev and type(x['source']) is str and bool(x['source']),'EXCLUSION_PARTITION')
            for i in range(a,b): mask[i]=True; exclusion_ids[i]=n
            prev=b
        passed=[bool(certification_enabled and v>=threshold) for v in vals]
        whole=bool(vals) and all(passed) and not any(mask) and any(ch not in SPACE for ch in text)
        contribution=any(not mask[i] and ch not in SPACE for i,ch in enumerate(text)) and all(passed[i] for i in range(len(vals)) if not mask[i])
        ranges=[]
        for i in range(len(vals)):
            verdict=HUMAN if passed[i] else NOT_PROVABLE
            fresh_blocked=claim_kind=='fresh-composition' and (scored['origin_types'][i]!='direct' or scored['origin_documents'][i]!=[scored['target']])
            reason=('NOT_FRESH_COMPOSITION' if fresh_blocked else scored['reasons'][i]) or ('RELEASE_NOT_APPROVED' if not certification_enabled else 'BELOW_THRESHOLD' if not passed[i] else None)
            item={'start':oo[i],'end':oo[i+1],'verdict':verdict,'excluded':mask[i],'exclusion':exclusion_ids[i],'reason':reason,'origin':scored.get('origin_types',['unknown']*len(vals))[i],'origin_documents':scored.get('origin_documents',[[]]*len(vals))[i]}
            if ranges and all(ranges[-1][k]==item[k] for k in ('verdict','excluded','exclusion','reason','origin','origin_documents')):
                ranges[-1]['end']=item['end']
            else: ranges.append(item)
        return {'verdict':HUMAN if whole else NOT_PROVABLE,'contribution_verdict':HUMAN if contribution else NOT_PROVABLE,
                'ranges':ranges,'reason':None,'candidate_document_pass':bool(vals) and min(vals)>=threshold and any(ch not in SPACE for ch in text),
                'certification_enabled':bool(certification_enabled),'claim_kind':claim_kind,'algorithm_version':'hwp-a/0.3'}
    except (InvalidTrace,ValueError,TypeError,KeyError,IndexError) as e:
        return dict(base,reason=str(e))


def verify(bundle: dict,model: dict|None=None,threshold: int=0,context: TrustedInputs=TrustedInputs(),excluded=None,claim_kind='fresh-composition') -> dict:
    if not isinstance(context,TrustedInputs):
        return {'verdict':NOT_PROVABLE,'contribution_verdict':NOT_PROVABLE,'ranges':[],'reason':'TRUST_CONTEXT'}
    scored=score(bundle,model,context,claim_kind)
    enabled=bool(type(context.approved_release) is bool and context.approved_release and
                 type(context.approved_threshold) is int and context.approved_threshold==threshold and
                 context.approved_claim==claim_kind and context.model_snapshot is not None and
                 scored.get('model_snapshot')==context.model_snapshot and model and model.get('purpose')=='validated-release')
    return decide(scored,threshold,enabled,excluded,claim_kind)
