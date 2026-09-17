"""Bounded private-evidence transport. Never confuse this object with a proof.

Chunking avoids an artificial one-CBOR-object limit on long observed histories.
The protocol root commitments, not this transport, authenticate the evidence.
"""
from . import core as c
BLOCK=256

def pack(value):
    c.fields(value,'logs lineage_salts')
    c.require(type(value['logs']) is list and len(value['logs'])<=4096,'disclosure-count')
    c.require(type(value['lineage_salts']) is list and len(value['lineage_salts'])<=64,'disclosure-count')
    st=c.Store();logs=[];seen=set();events=total=0
    for log in value['logs']:
        c.fields(log,'capture openings');c.valid_ref(log['capture']);key=log['capture']['sha256']
        c.require(key not in seen,'duplicate-disclosed-session');seen.add(key)
        oo=log['openings'];c.require(type(oo) is list,'disclosure-openings');parts=[]
        for i,o in enumerate(oo):
            c.fields(o,'index salt event');c.require(type(o['index']) is int and o['index']==i,'opening-order')
            c.octets(o['event']);c.octets(o['salt'],32);c.decode(o['event']);total+=len(o['event'])+32;events+=1
            c.require(total<=c.MAX_BYTES and events<=c.MAX_EVENTS,'disclosure-budget')
        for offset in range(0,len(oo),BLOCK):
            raw=c.encode({'v':c.VERSION,'type':'opening-block','offset':offset,'openings':oo[offset:offset+BLOCK]})
            c.decode(raw);parts.append(st.add(raw))
        logs.append({'capture':log['capture'],'count':len(oo),'parts':parts})
    logs.sort(key=lambda x:x['capture']['sha256']);salts=[];seen=set()
    for s in value['lineage_salts']:
        c.fields(s,'statement salt');c.valid_ref(s['statement']);c.octets(s['salt'],32)
        c.require(s['statement']['sha256'] not in seen,'duplicate-lineage-salt');seen.add(s['statement']['sha256']);salts.append(s)
    salts.sort(key=lambda x:x['statement']['sha256'])
    root=st.put({'v':c.VERSION,'type':'private-disclosure','logs':logs,'lineage_salts':salts})
    return st.pack(root)

def unpack(raw):
    st,root=c.Store.unpack(raw);manifest=st.obj(root);c.typed(manifest,'private-disclosure','logs lineage_salts')
    c.require(type(manifest['logs']) is list and len(manifest['logs'])<=4096,'disclosure-count')
    logs=[];previous=None;used={root['sha256']}
    for log in manifest['logs']:
        c.fields(log,'capture count parts');c.valid_ref(log['capture']);key=log['capture']['sha256']
        c.require(previous is None or previous<key,'disclosure-order');previous=key
        n=c.integer(log['count'],0,c.MAX_EVENTS);parts=log['parts'];c.require(type(parts) is list and len(parts)==(n+BLOCK-1)//BLOCK,'opening-block-count');oo=[]
        for i,ref in enumerate(parts):
            block=st.obj(ref);used.add(ref['sha256']);c.typed(block,'opening-block','offset openings')
            c.require(type(block['offset']) is int and block['offset']==i*BLOCK,'opening-block-offset')
            c.require(type(block['openings']) is list and len(block['openings'])==min(BLOCK,n-i*BLOCK),'opening-block-size');oo.extend(block['openings'])
        logs.append({'capture':log['capture'],'openings':oo})
    value={'logs':logs,'lineage_salts':manifest['lineage_salts']}
    c.require(used==set(st.objects),'unrelated-private-object')
    # Repack validates total budgets, unique references, event CBOR and salt sizes.
    c.require(pack(value)==raw,'private-disclosure-noncanonical')
    return value
