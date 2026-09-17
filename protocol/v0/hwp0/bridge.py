"""HWP v0's closed algorithm binding; no caller-selected executable or echo callback."""
from __future__ import annotations
from . import core as c
from .algorithm import verify as av
from .algorithm.replay import replay, utf8_offsets, SPACE
ADAPTER='hwp-a-v0-cbor/1'
OUTPUT='hwp-a-v0-output/1'


def json_domain(x,depth=0):
    c.require(depth<=32,'adapter-depth')
    if x is None or type(x) is bool:return
    if type(x) is int:c.integer(x,-(2**53-1),2**53-1);return
    if type(x) is str:x.encode('utf-8','strict');return
    if type(x) is list:
        c.require(len(x)<=1_000_000,'adapter-items')
        for v in x:json_domain(v,depth+1)
        return
    if type(x) is dict and all(type(k) is str for k in x):
        for k,v in x.items():json_domain(k,depth+1);json_domain(v,depth+1)
        return
    raise c.Reject('adapter-json-domain')


def record_events(record):
    """Serialize actual existing observations; cannot synthesize absent native deliveries."""
    c.fields(record,'id language resolution_us paths observations transactions final_text');json_domain(record)
    stream=[(o['seq'],'observation',o) for o in record['observations']]+[(t['seq'],'transaction',t) for t in record['transactions']]
    stream.sort(key=lambda x:x[0]);c.require([s for s,_,_ in stream]==list(range(len(stream))),'adapter-event-order')
    h={k:record[k] for k in ('id','language','resolution_us','paths')}
    return [dict(h,kind='header',adapter=ADAPTER)]+[dict(kind=k,value=v) for _,k,v in stream]+[dict(kind='end',final_text=record['final_text'])]


def decode_record(events):
    c.require(type(events) is list and 2<=len(events)<=c.MAX_EVENTS,'adapter-event-count')
    h,e=events[0],events[-1];c.fields(h,'kind adapter id language resolution_us paths');c.fields(e,'kind final_text')
    c.require(h['kind']=='header' and h['adapter']==ADAPTER and e['kind']=='end','adapter-markers')
    out={k:h[k] for k in ('id','language','resolution_us','paths')};out.update(observations=[],transactions=[],final_text=e['final_text'])
    for seq,w in enumerate(events[1:-1]):
        c.fields(w,'kind value');c.require(w['kind'] in ('observation','transaction'),'adapter-wrapper')
        v=w['value'];c.require(type(v) is dict and type(v.get('seq')) is int and v['seq']==seq,'adapter-event-order')
        out['observations' if w['kind']=='observation' else 'transactions'].append(v)
    json_domain(out);return out


def reconstruct(evidence,infos,target):
    c.require(type(evidence) is list and 1<=len(evidence)<=32,'adapter-record-count')
    records={};by_id={};by_cap={}
    for item in evidence:
        c.fields(item,'capture events');cap=item['capture'];c.valid_ref(cap)
        meta=infos.get(cap['sha256']);c.require(meta is not None and meta['ref']==cap,'adapter-capture-set')
        r=decode_record(item['events']);rid=r['id']
        c.require(type(rid) is str and rid not in records,'duplicate-record-id')
        c.require(cap['sha256'] not in by_cap,'duplicate-capture')
        c.require(c.ref(r['final_text'].encode('utf-8'))==meta['end']['document'],'capture-replayed-document')
        profile=meta['profile']
        c.require(type(r['resolution_us']) is int and 1<=r['resolution_us']<=profile['max_resolution_us'],'capture-resolution')
        c.require(type(r['paths']) is dict,'capture-paths')
        for p,path in r['paths'].items():c.require('|'.join((p,path,r['language'])) in profile['domains'],'capture-path-not-admitted')
        records[rid]=r;by_id[rid]=cap;by_cap[cap['sha256']]=rid
    c.require(set(by_cap)==set(infos),'adapter-capture-set')
    c.require(target['sha256'] in by_cap and infos[target['sha256']]['ref']==target,'adapter-target')
    deps={}
    for rid,r in records.items():
        d={t['from_doc'] for t in r['transactions'] if t.get('op')=='copy' and t.get('from_doc')!=rid}
        c.require(d<=records.keys(),'unknown-record-dependency')
        expected=c.reference_list([by_id[k] for k in d])
        declared=[x['capture'] for x in infos[by_id[rid]['sha256']]['start']['parents']]
        c.require(expected==declared,'captured-dependencies-mismatch');deps[rid]=d
    target_id=by_cap[target['sha256']];needed=set()
    def visit(x,active):
        c.require(x not in active,'record-cycle')
        if x in needed:return
        needed.add(x)
        for y in deps[x]:visit(y,active|{x})
    visit(target_id,set());c.require(needed==set(records),'unrelated-record')
    order=[];remaining=set(records)
    while remaining:
        ready=[x for x in remaining if deps[x]<=set(order)];c.require(ready,'record-cycle')
        rid=min(ready,key=lambda s:s.encode('utf-8'));order.append(rid);remaining.remove(rid)
    bundle={'version':'hwp-a/v0','documents':[records[k] for k in order],'target':target_id}
    return bundle,replay(bundle),by_id,by_cap


def selected_scope(scope,document):
    c.typed(scope,'scope','document kind ranges');c.require(c.ref(document)==scope['document'],'scope-document-binding')
    text=document.decode('utf-8','strict');bounds=set(utf8_offsets(text))
    c.require(scope['kind'] in ('whole-document','selected-ranges'),'scope-kind')
    c.require(type(scope['ranges']) is list and 1<=len(scope['ranges'])<=10000,'scope-range-count')
    prev=0;meaningful=False;exclusions=[];previous=None
    for r in scope['ranges']:
        c.fields(r,'start end origin');a=c.integer(r['start'],0,len(document));b=c.integer(r['end'],a+1,len(document))
        c.require(a==prev and a in bounds and b in bounds,'scope-partition');prev=b
        o=r['origin'];c.require(type(o) is list and o,'origin-structure')
        if o[0]=='excluded':
            c.require(len(o)==2 and type(o[1]) is str and 1<=len(o[1])<=1024,'exclusion-reason')
            exclusions.append({'start':a,'end':b,'source':o[1]})
        else:
            meaningful|=any(ch not in SPACE for ch in document[a:b].decode('utf-8'))
            if o[0]=='observed':c.require(len(o)==2,'observed-origin');c._ref_list(o[1],1,32)
            elif o[0]=='inherited':
                c.require(len(o)==4,'inherited-origin');c.valid_ref(o[1]);c.integer(o[2]);c.integer(o[3],o[2]+1)
                c.require(o[3]-o[2]==b-a,'inherited-length')
            else:raise c.Reject('unsupported-origin')
        if previous is not None:
            p=previous['origin']
            mergeable=(p==o and o[0]!='inherited') or (p[0]==o[0]=='inherited' and p[1]==o[1] and p[3]==o[2])
            c.require(not mergeable,'scope-not-maximal')
        previous=r
    c.require(prev==len(document) and meaningful,'scope-completeness-or-vacuity')
    c.require((scope['kind']=='whole-document')==(not exclusions),'whole-document-scope')
    return exclusions


def positions(text):return {n:i for i,n in enumerate(utf8_offsets(text))}


def run(evidence,release,request,infos,store):
    """Compute positive output and private lineage or reject; never echo expected values."""
    bundle,corpus,by_id,by_cap=reconstruct(evidence,infos,request['target_capture'])
    target=corpus.documents[bundle['target']];document=target.text.encode('utf-8')
    policy=c.decode(request['artifacts']['decision_policy']);model=c.decode(request['artifacts']['model'])
    exclusions=selected_scope(request['requested_scope'],document)
    ctx=av.TrustedInputs(admissible_documents=frozenset(by_id),fresh_documents=frozenset(by_id),
        document_snapshots=frozenset((r['id'],av.snapshot(r)) for r in bundle['documents']),
        allowed_domains=frozenset(policy['allowed_domains']),approved_release=True,
        approved_threshold=policy['threshold'],approved_claim=release['claim'],model_snapshot=av.snapshot(model))
    assessment=av.verify(bundle,model,policy['threshold'],ctx,exclusions,release['claim'])
    key='verdict' if request['requested_scope']['kind']=='whole-document' else 'contribution_verdict'
    c.require(assessment[key]==c.PASS,'hwp-not-qualifying')
    pos=positions(target.text)
    for entry in request['requested_scope']['ranges']:
        o=entry['origin']
        if o[0]=='excluded':continue
        atoms=[corpus.atoms[aid] for aid in target.live[pos[entry['start']]:pos[entry['end']]]]
        c.require(all(a.roots for a in atoms),'unsupported-selected-origin')
        if o[0]=='observed':
            c.require(all(all(corpus.atoms[root].home==target.did for root in a.roots) for a in atoms),'observed-origin-laundering')
            required=set().union(*(set(a.requirements) for a in atoms))
            c.require(c.reference_list([by_id[x] for x in required])==o[1],'observed-dependencies-not-exact')
        else:
            c.require(release['claim']=='wording-origin','inherited-not-fresh')
            pp=store.obj(o[1]);c.typed(pp,'proof','statement appraisals author')
            ps=store.obj(pp['statement']);parent_cap=ps['target_capture'];parent_id=by_cap.get(parent_cap['sha256'])
            c.require(parent_id is not None and by_id[parent_id]==parent_cap and parent_id!=target.did,'parent-not-captured-source')
            c.require(any(x['capture']==parent_cap and x['proof']==o[1] for m in infos.values() for x in m['start']['parents']),'unplanned-parent-proof')
            parent=corpus.documents[parent_id];po=positions(parent.text)
            c.require(o[2] in po and o[3] in po,'parent-scalar-boundary')
            pa=[corpus.atoms[i] for i in parent.live[po[o[2]]:po[o[3]]]]
            c.require(len(atoms)==len(pa) and all(a.char==b.char and a.roots==b.roots for a,b in zip(atoms,pa)),'parent-is-not-actual-lineage')
    lineage=c.encode({'adapter':OUTPUT,'target_record_id':target.did,
        'record_captures':[{'id':r['id'],'capture':by_id[r['id']]} for r in bundle['documents']],
        'assessment':assessment})
    result={'document':c.ref(document),'scope':c.ref(c.encode(request['requested_scope'])),
        'lineage':c.lineage_commitment(request['lineage_salt'],lineage),'release':c.ref(c.encode(release)),
        'captures':c.reference_list([m['ref'] for m in infos.values()]),'target_capture':by_id[target.did],'result':c.PASS}
    return result,lineage
