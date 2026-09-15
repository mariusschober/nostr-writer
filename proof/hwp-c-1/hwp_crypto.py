"""HWP-C/1 reference: proof mechanics only, not human-writing detection.

No network access, dynamic code loading, bundled trust roots or implicit approval.
The caller supplies an independently chosen verification policy. Fixture keys and
fixture evaluator callbacks MUST NOT be used for real certification.
"""
from __future__ import annotations
from dataclasses import dataclass
from functools import lru_cache
import hashlib
import os
from typing import Any, Callable
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

VERSION = 'hwp-c/1'
AAD = b'HWP-C/1'
MAX_BYTES = 64 * 1024 * 1024
MAX_ITEMS = 100_000
MAX_OBJECTS = 4096
MAX_DOCUMENT_BYTES = 1024 * 1024
MAX_DEPTH = 32
MAX_PROOFS = 64
MAX_EVENTS = 1_000_000
PASS = 'HUMAN-WRITTEN'

class Reject(ValueError):
    """An invalid, unsupported, incomplete or untrusted proof; never an AI label."""


def require(condition: bool, reason: str) -> None:
    if not condition:
        raise Reject(reason)


def integer(x: Any, lo: int = 0, hi: int = (1 << 53) - 1) -> int:
    require(type(x) is int and lo <= x <= hi, 'integer-domain')
    return x


def octets(x: Any, length: int | None = None) -> bytes:
    require(type(x) is bytes and len(x) <= MAX_BYTES, 'byte-string-domain')
    require(length is None or len(x) == length, 'byte-string-length')
    return x


def fields(x: Any, names: str) -> None:
    require(type(x) is dict and set(x) == set(names.split()), 'object-fields')


def typed(x: Any, name: str, names: str) -> None:
    fields(x, 'v type ' + names)
    require(x['v'] == VERSION and x['type'] == name, 'object-version-or-type')


@dataclass(frozen=True)
class Tag:
    number: int
    value: Any


def _head(major: int, value: int) -> bytes:
    require(0 <= value < (1 << 64), 'cbor-integer-overflow')
    if value < 24:
        return bytes([(major << 5) | value])
    for code, width in ((24,1),(25,2),(26,4),(27,8)):
        if value < 1 << (8 * width):
            return bytes([(major << 5) | code]) + value.to_bytes(width,'big')
    raise Reject('cbor-integer-overflow')


def encode(value: Any, depth: int = 0) -> bytes:
    """RFC8949 4.2.1 bytewise-key-order deterministic CBOR, restricted HWP domain."""
    require(depth <= MAX_DEPTH, 'cbor-depth')
    if value is None: return b'\xf6'
    if type(value) is bool: return b'\xf5' if value else b'\xf4'
    if type(value) is int:
        require(-(1 << 63) <= value < (1 << 64), 'cbor-integer-domain')
        return _head(0,value) if value >= 0 else _head(1,-1-value)
    if type(value) is bytes:
        octets(value); return _head(2,len(value))+value
    if type(value) is str:
        try: raw=value.encode('utf-8','strict')
        except UnicodeError as e: raise Reject('unicode-scalar') from e
        require(len(raw)<=MAX_BYTES,'text-size')
        return _head(3,len(raw))+raw
    if type(value) is list:
        require(len(value)<=MAX_ITEMS,'array-size')
        return _head(4,len(value))+b''.join(encode(v,depth+1) for v in value)
    if type(value) is dict:
        require(len(value)<=MAX_ITEMS,'map-size')
        require(all(type(k) in (int,str) for k in value),'map-key-type')
        pairs=sorted((encode(k,depth+1),encode(v,depth+1)) for k,v in value.items())
        return _head(5,len(pairs))+b''.join(k+v for k,v in pairs)
    if type(value) is Tag:
        require(value.number==18,'unsupported-tag')
        return b'\xd2'+encode(value.value,depth+1)
    raise Reject('cbor-type')


def decode(raw: bytes) -> Any:
    """Reject duplicates, tags except18, floats, indefinite forms and noncanonical bytes."""
    octets(raw)
    offset=0; visited=0
    def take(n):
        nonlocal offset
        require(0<=n<=len(raw)-offset,'cbor-truncated')
        out=raw[offset:offset+n]; offset+=n; return out
    def parse(depth):
        nonlocal visited
        require(depth<=MAX_DEPTH,'cbor-depth')
        visited+=1; require(visited<=MAX_ITEMS,'cbor-item-budget')
        first=take(1)[0]; major=first>>5; ai=first&31
        if major==7:
            require(ai in (20,21,22),'cbor-simple-or-float')
            return {20:False,21:True,22:None}[ai]
        require(ai<=27,'cbor-indefinite-or-reserved')
        n=ai if ai<24 else int.from_bytes(take(1 << (ai-24)),'big')
        if ai>=24:
            require(n >= (24 if ai==24 else 1 << (8*(1 << (ai-25)))), 'cbor-nonminimal')
        if major==0: return n
        if major==1:
            require(n<(1<<63),'cbor-integer-domain'); return -1-n
        if major==2: return take(n)
        if major==3:
            try: return take(n).decode('utf-8','strict')
            except UnicodeError as e: raise Reject('invalid-utf8') from e
        if major==4:
            require(n<=MAX_ITEMS,'array-size'); return [parse(depth+1) for _ in range(n)]
        if major==5:
            require(n<=MAX_ITEMS,'map-size')
            out={}; prev=None
            for _ in range(n):
                begin=offset; k=parse(depth+1); kb=raw[begin:offset]
                require(type(k) in (int,str),'map-key-type')
                require(prev is None or prev<kb,'cbor-key-order-or-duplicate')
                require(k not in out,'cbor-duplicate-key')
                prev=kb; out[k]=parse(depth+1)
            return out
        require(major==6 and n==18,'unsupported-tag')
        return Tag(n,parse(depth+1))
    result=parse(0)
    require(offset==len(raw),'cbor-trailing-data')
    require(encode(result)==raw,'cbor-nondeterministic')
    return result


def digest(raw: bytes) -> bytes:
    return hashlib.sha256(octets(raw)).digest()


def ref(raw: bytes) -> dict:
    return {'sha256':digest(raw),'size':len(raw)}


def valid_ref(value: Any) -> None:
    fields(value,'sha256 size'); octets(value['sha256'],32); integer(value['size'],0,MAX_BYTES)


def same_ref(a: Any, b: Any) -> bool:
    valid_ref(a); valid_ref(b); return a==b


# Public-only Edwards point decoding/subgroup checks. Private signing is delegated
# to cryptography/OpenSSL. This stricter profile excludes identity/mixed-order A,R.
_P=(1<<255)-19
_L=(1<<252)+27742317777372353535851937790883648493
_D=(-121665*pow(121666,_P-2,_P))%_P
_I=pow(2,(_P-1)//4,_P)


def _add(p,q):
    x,y,z,t=p; X,Y,Z,T=q
    a=(y-x)*(Y-X)%_P; b=(y+x)*(Y+X)%_P
    c=2*_D*t*T%_P; d=2*z*Z%_P
    e=(b-a)%_P; f=(d-c)%_P; g=(d+c)%_P; h=(b+a)%_P
    return e*f%_P,g*h%_P,f*g%_P,e*h%_P


@lru_cache(maxsize=8192)
def valid_point(raw: bytes) -> bool:
    if type(raw) is not bytes or len(raw)!=32: return False
    n=int.from_bytes(raw,'little'); sign=n>>255; y=n&((1<<255)-1)
    if y>=_P: return False
    den=(_D*y*y+1)%_P
    if not den: return False
    x2=(y*y-1)*pow(den,_P-2,_P)%_P
    x=pow(x2,(_P+3)//8,_P)
    if x*x%_P!=x2: x=x*_I%_P
    if x*x%_P!=x2 or (x==0 and sign): return False
    if x&1 != sign: x=_P-x
    if x==0 and y==1: return False
    p=(x,y,1,x*y%_P); q=(0,1,1,0); n=_L
    while n:
        if n&1: q=_add(q,p)
        p=_add(p,p); n>>=1
    return q[0]==0 and (q[1]-q[2])%_P==0


def public_key(seed: bytes) -> bytes:
    return Ed25519PrivateKey.from_private_bytes(octets(seed,32)).public_key().public_bytes(Encoding.Raw,PublicFormat.Raw)


def key_bytes(public: bytes) -> bytes:
    require(valid_point(octets(public,32)),'ed25519-public-point')
    return encode({1:1,3:-19,-1:6,-2:public})


def parse_key(raw: bytes) -> bytes:
    obj=decode(raw)
    require(type(obj) is dict and set(obj)=={1,3,-1,-2},'cose-key-fields')
    require(type(obj[1]) is int and obj[1]==1 and type(obj[3]) is int and obj[3]==-19 and type(obj[-1]) is int and obj[-1]==6,'cose-key-profile')
    require(valid_point(octets(obj[-2],32)),'ed25519-public-point')
    return obj[-2]


def sign(payload: dict, seed: bytes) -> bytes:
    """COSE_Sign1(tag18). Possession of a key is not authority to issue HWP."""
    require(type(payload) is dict and payload.get('v')==VERSION,'signature-payload-version')
    rawkey=key_bytes(public_key(seed)); protected=encode({1:-19,3:'application/cbor',4:digest(rawkey)})
    body=encode(payload)
    message=encode(['Signature1',protected,AAD,body])
    signature=Ed25519PrivateKey.from_private_bytes(octets(seed,32)).sign(message)
    require(valid_point(signature[:32]),'ed25519-signature-point')
    return encode(Tag(18,[protected,{},body,signature]))


def verify_signature(raw: bytes, key: bytes) -> tuple[dict,bytes]:
    obj=decode(raw)
    require(type(obj) is Tag and obj.number==18 and type(obj.value) is list and len(obj.value)==4,'cose-sign1')
    protected,unprotected,payload,sig=obj.value
    require(type(unprotected) is dict and not unprotected,'unprotected-headers-forbidden')
    p=decode(octets(protected))
    require(type(p) is dict and set(p)=={1,3,4} and type(p[1]) is int and p[1]==-19 and p[3]=='application/cbor','protected-headers')
    kid=octets(p[4],32); require(kid==digest(key),'signature-key-binding')
    public=parse_key(key); sig=octets(sig,64); octets(payload)
    require(valid_point(sig[:32]) and int.from_bytes(sig[32:],'little')<_L,'ed25519-signature-canonicality')
    message=encode(['Signature1',protected,AAD,payload])
    try: Ed25519PublicKey.from_public_bytes(public).verify(sig,message)
    except Exception as e: raise Reject('signature-invalid') from e
    body=decode(payload)
    require(type(body) is dict and body.get('v')==VERSION,'signed-payload-version')
    return body,kid


class Store:
    """Flat bounded content-addressed storage; input cannot request network fetches."""
    def __init__(self): self.objects: dict[bytes,bytes]={}
    def add(self,raw: bytes) -> dict:
        h=digest(raw); require(h not in self.objects or self.objects[h]==raw,'content-hash-collision')
        self.objects[h]=raw; require(len(self.objects)<=MAX_OBJECTS,'object-count')
        return ref(raw)
    def put(self,obj: Any) -> dict: return self.add(encode(obj))
    def get(self,r: dict) -> bytes:
        valid_ref(r); require(r['sha256'] in self.objects,'missing-object')
        raw=self.objects[r['sha256']]
        require(len(raw)==r['size'] and digest(raw)==r['sha256'],'object-reference-mismatch')
        return raw
    def obj(self,r: dict) -> Any: return decode(self.get(r))
    def signed(self,r: dict) -> tuple[dict,bytes]:
        raw=self.get(r); env=decode(raw)
        require(type(env) is Tag and type(env.value) is list and len(env.value)==4,'cose-sign1')
        p=decode(octets(env.value[0]))
        require(type(p) is dict and 4 in p,'signature-kid-missing')
        kid=octets(p[4],32); require(kid in self.objects,'missing-signature-key')
        return verify_signature(raw,self.objects[kid])
    def pack(self,root: dict) -> bytes:
        self.get(root)
        raw=encode({'v':VERSION,'type':'bundle','root':root,'objects':[[k,v] for k,v in sorted(self.objects.items())]})
        require(len(raw)<=MAX_BYTES,'bundle-size'); return raw
    @classmethod
    def unpack(cls,raw: bytes) -> tuple['Store',dict]:
        obj=decode(raw); typed(obj,'bundle','root objects')
        require(type(obj['objects']) is list and len(obj['objects'])<=MAX_OBJECTS,'object-count')
        store=cls(); prev=None
        for pair in obj['objects']:
            require(type(pair) is list and len(pair)==2,'object-entry')
            h,b=pair; octets(h,32); octets(b)
            require(prev is None or prev<h,'object-order-or-duplicate'); prev=h
            require(digest(b)==h,'object-digest'); store.add(b)
        store.get(obj['root']); return store,obj['root']


def leaf(start_digest: bytes, index: int, salt: bytes, event_bytes: bytes) -> bytes:
    octets(start_digest,32); integer(index,0,MAX_EVENTS-1); octets(salt,32)
    decode(event_bytes)  # canonical adapter value, not application execution
    return digest(b'\x00'+encode(['HWP-C/1:event',start_digest,index,salt,event_bytes]))


def tree_root(leaves: list[bytes]) -> bytes:
    require(type(leaves) is list and len(leaves)<=MAX_EVENTS,'tree-size')
    if not leaves: return digest(b'')
    if len(leaves)==1: return octets(leaves[0],32)
    k=1<<((len(leaves)-1).bit_length()-1)
    return digest(b'\x01'+tree_root(leaves[:k])+tree_root(leaves[k:]))


def inclusion(leaves: list[bytes], index: int) -> list[bytes]:
    integer(index,0,len(leaves)-1)
    if len(leaves)==1: return []
    k=1<<((len(leaves)-1).bit_length()-1)
    if index<k: return inclusion(leaves[:k],index)+[tree_root(leaves[k:])]
    return inclusion(leaves[k:],index-k)+[tree_root(leaves[:k])]


def verify_inclusion(h: bytes,index: int,count: int,path: list[bytes],root: bytes) -> bool:
    try:
        integer(count,1,MAX_EVENTS); integer(index,0,count-1); octets(h,32); octets(root,32)
        require(type(path) is list and len(path)<=32,'inclusion-length')
        pos=0
        def walk(i,n):
            nonlocal pos
            if n==1: return h
            k=1<<((n-1).bit_length()-1)
            sub=walk(i,k) if i<k else walk(i-k,n-k)
            require(pos<len(path),'inclusion-truncated'); sibling=octets(path[pos],32); pos+=1
            return digest(b'\x01'+(sub+sibling if i<k else sibling+sub))
        got=walk(index,count)
        return pos==len(path) and got==root
    except Reject: return False


def consistency(leaves: list[bytes], old_count: int) -> list[bytes]:
    integer(old_count,1,len(leaves))
    def sub(m,items,known):
        n=len(items)
        if m==n: return [] if known else [tree_root(items)]
        k=1<<((n-1).bit_length()-1)
        if m<=k: return sub(m,items[:k],known)+[tree_root(items[k:])]
        return sub(m-k,items[k:],False)+[tree_root(items[:k])]
    return sub(old_count,leaves,True)


def verify_consistency(m:int,n:int,old:bytes,new:bytes,path:list[bytes]) -> bool:
    """RFC9162 2.1.4.2, with strict path exhaustion and explicit empty-tree case."""
    try:
        integer(m,0,MAX_EVENTS); integer(n,m,MAX_EVENTS); octets(old,32); octets(new,32)
        require(type(path) is list and len(path)<=32 and all(type(p) is bytes and len(p)==32 for p in path),'consistency-path')
        if m==0: return old==digest(b'') and not path and (n>0 or new==old)
        if m==n: return old==new and not path
        fn=m-1; sn=n-1
        while fn&1: fn>>=1; sn>>=1
        if fn==0: fr=sr=old; cursor=0
        else:
            require(bool(path),'consistency-empty'); fr=sr=path[0]; cursor=1
        for h in path[cursor:]:
            require(sn!=0,'consistency-excess')
            if fn&1 or fn==sn:
                fr=digest(b'\x01'+h+fr); sr=digest(b'\x01'+h+sr)
                while fn!=0 and not(fn&1): fn>>=1; sn>>=1
            else: sr=digest(b'\x01'+sr+h)
            fn>>=1; sn>>=1
        return sn==0 and fr==old and sr==new
    except Reject: return False


def commit_events(start: dict, events: list[Any], salts: list[bytes] | None = None) -> tuple[bytes,list[dict]]:
    valid_ref(start); require(2<=len(events)<=MAX_EVENTS,'event-count')
    salts=[os.urandom(32) for _ in events] if salts is None else salts
    require(len(salts)==len(events) and len(set(salts))==len(salts),'salt-count-or-reuse')
    private=[]; leaves=[]
    for i,(event,salt) in enumerate(zip(events,salts)):
        event_bytes=encode(event); h=leaf(start['sha256'],i,salt,event_bytes)
        leaves.append(h); private.append({'index':i,'salt':salt,'event':event_bytes})
    return tree_root(leaves),private


def open_transcript(start: dict, count:int, root:bytes, openings:list[dict]) -> list[Any]:
    require(type(openings) is list and len(openings)==integer(count,2,MAX_EVENTS),'complete-disclosure-required')
    leaves=[]; events=[]; salts=set()
    for i,o in enumerate(openings):
        fields(o,'index salt event'); require(type(o['index']) is int and o['index']==i,'opening-order')
        octets(o['salt'],32); require(o['salt'] not in salts,'salt-reuse'); salts.add(o['salt'])
        leaves.append(leaf(start['sha256'],i,o['salt'],o['event'])); events.append(decode(o['event']))
    require(tree_root(leaves)==octets(root,32),'transcript-root')
    require(type(events[0]) is dict and events[0].get('kind')=='header','transcript-header')
    require(type(events[-1]) is dict and events[-1].get('kind')=='end','transcript-terminal')
    return events


def lineage_commitment(salt:bytes,lineage_bytes:bytes) -> bytes:
    octets(salt,32); octets(lineage_bytes)
    return digest(encode(['HWP-C/1:lineage',salt,lineage_bytes]))


def _ref_list(values:Any,lo:int=0,hi:int=4096) -> list[dict]:
    require(type(values) is list and lo<=len(values)<=hi,'reference-list-size')
    last=None
    for r in values:
        valid_ref(r); k=r['sha256']
        require(last is None or last<k,'reference-order-or-duplicate'); last=k
    return values


def reference_list(values:list[dict]) -> list[dict]:
    return sorted(values,key=lambda r:r['sha256'])


def policy_check(policy:dict) -> None:
    typed(policy,'verification-policy','label releases capture_authorities evaluators quorum modes require_author identity_authorities denied status_as_of')
    require(type(policy['label']) is str and 0<len(policy['label'])<=256,'policy-label')
    _ref_list(policy['releases'],1); _ref_list(policy['evaluators'],1,64)
    integer(policy['quorum'],1,len(policy['evaluators']))
    require(type(policy['modes']) is list and policy['modes'] and policy['modes']==sorted(set(policy['modes'])) and set(policy['modes'])<={'attested-v1','disclosed-v1'},'policy-modes')
    require(type(policy['require_author']) is bool,'policy-author')
    _ref_list(policy['identity_authorities'],0,64)
    require(type(policy['denied']) is list and policy['denied']==sorted(set(policy['denied'])) and all(type(h) is bytes and len(h)==32 for h in policy['denied']),'policy-deny-list')
    if policy['status_as_of'] is not None: integer(policy['status_as_of'])
    require(type(policy['capture_authorities']) is list and 1<=len(policy['capture_authorities'])<=64,'capture-authorities')
    prev=None
    for entry in policy['capture_authorities']:
        fields(entry,'profile keys'); valid_ref(entry['profile']); _ref_list(entry['keys'],1,64)
        require(prev is None or prev<entry['profile']['sha256'],'capture-authority-order'); prev=entry['profile']['sha256']


class Verifier:
    """All trust and executable callbacks enter from the relying party, never the bundle."""
    def __init__(self,store:Store,policy_bytes:bytes,expected_policy_digest:bytes,
                 runners:dict[bytes,Callable] | None = None, force_recompute:bool=False):
        octets(expected_policy_digest,32)
        require(digest(policy_bytes)==expected_policy_digest,'external-policy-pin')
        self.policy=decode(policy_bytes); policy_check(self.policy)
        require(type(force_recompute) is bool,'audit-flag'); self.force_recompute=force_recompute
        self.store=store; self.policy_digest=expected_policy_digest
        self.runners={} if runners is None else dict(runners)
        self.done={}; self.active=set(); self.seen_starts={}; self.steps=0
    def get(self,r):
        valid_ref(r); require(r['sha256'] not in self.policy['denied'],'denied-object')
        return self.store.get(r)
    def obj(self,r): return decode(self.get(r))
    def signed(self,r):
        self.get(r); body,kid=self.store.signed(r)
        require(kid not in self.policy['denied'],'denied-key')
        return body,kid
    def verify(self,proof_ref:dict,expected_document:bytes | None=None,disclosures:dict | None=None) -> dict:
        valid_ref(proof_ref); self.get(proof_ref); h=proof_ref['sha256']
        require(h not in self.active,'cyclic-proof')
        if h in self.done:
            out=self.done[h]
            if expected_document is not None: require(out['_document']==expected_document,'expected-document-mismatch')
            return out
        self.steps+=1; require(self.steps<=MAX_PROOFS,'proof-graph-budget'); self.active.add(h)
        proof=self.obj(proof_ref); typed(proof,'proof','statement appraisals author')
        _ref_list(proof['appraisals'],1,64)
        statement=self.obj(proof['statement'])
        typed(statement,'statement','document media_type scope release captures target_capture lineage mode author nonce')
        document=self.get(statement['document'])
        require(len(document)<=MAX_DOCUMENT_BYTES,'document-size')
        if expected_document is not None: require(document==octets(expected_document),'expected-document-mismatch')
        try: text=document.decode('utf-8','strict')
        except UnicodeError as e: raise Reject('document-not-utf8') from e
        require(statement['media_type'] in ('text/plain','text/markdown'),'document-media-type')
        octets(statement['lineage'],32); octets(statement['nonce'],32)
        require(statement['mode'] in self.policy['modes'],'execution-mode-not-authorized')
        release=self.obj(statement['release'])
        require(statement['release'] in self.policy['releases'],'release-not-authorized')
        typed(release,'release','algorithm claim artifacts capture_profiles')
        require(type(release['algorithm']) is str and 0<len(release['algorithm'])<=128,'algorithm-id')
        require(release['claim'] in ('fresh-composition','wording-origin'),'claim-semantics')
        fields(release['artifacts'],'algorithm_spec program model decision_policy evidence_adapter output_contract')
        for r in release['artifacts'].values(): self.get(r)
        _ref_list(release['capture_profiles'],1,64)
        for r in release['capture_profiles']: self.get(r)
        _ref_list(statement['captures'],1,64)
        valid_ref(statement['target_capture']); require(statement['target_capture'] in statement['captures'],'target-capture-binding')
        captures=[]; caprefs={r['sha256'] for r in statement['captures']}; capture_kids=set()
        grants={e['profile']['sha256']:(e['profile'],{r['sha256'] for r in e['keys']}) for e in self.policy['capture_authorities']}
        for r in statement['captures']:
            end,kid=self.signed(r); typed(end,'capture-end','start count root complete participation')
            require(end['complete'] is True,'capture-not-complete'); integer(end['count'],2,MAX_EVENTS); octets(end['root'],32)
            start,skid=self.signed(end['start']); typed(start,'capture-start','session profile adapter nonce subject')
            require(kid==skid,'capture-key-changed'); octets(start['session'],32); octets(start['nonce'],32)
            self.get(start['profile']); self.get(start['adapter'])
            if start['subject'] is None:
                require(end['participation'] is None,'unexpected-participation')
            else:
                parse_key(self.get(start['subject']))
                require(end['participation'] is not None,'missing-participation')
                consent,pkid=self.signed(end['participation']); typed(consent,'participation','start')
                require(consent['start']==end['start'] and pkid==start['subject']['sha256'],'participation-binding')
                require(pkid!=kid,'capture-subject-key-separation')
            require(start['profile'] in release['capture_profiles'] and start['adapter']==release['artifacts']['evidence_adapter'],'capture-release-binding')
            grant=grants.get(start['profile']['sha256'])
            require(grant is not None and grant[0]==start['profile'] and kid in grant[1] and any(k['sha256']==kid and k['size']==len(self.store.objects[kid]) for e in self.policy['capture_authorities'] if e['profile']==start['profile'] for k in e['keys']),'capture-authority')
            pair=(kid,start['session']); end_id=r['sha256']
            require(pair not in self.seen_starts or self.seen_starts[pair]==end_id,'capture-equivocation-in-bundle')
            self.seen_starts[pair]=end_id; capture_kids.add(kid)
            captures.append({'ref':r,'start':end['start'],'count':end['count'],'root':end['root'],'subject':start['subject']})
        capture_subjects={c['ref']['sha256']:c['subject'] for c in captures}
        scope=self.obj(statement['scope']); typed(scope,'scope','document kind ranges')
        require(same_ref(scope['document'],statement['document']),'scope-document-binding')
        require(scope['kind'] in ('whole-document','selected-ranges'),'scope-kind')
        require(type(scope['ranges']) is list and 1<=len(scope['ranges'])<=10000,'scope-range-count')
        boundaries={0}; n=0
        for ch in text: n+=len(ch.encode('utf-8')); boundaries.add(n)
        prev=0; selected=[]; excluded=False; meaningful=False
        for entry in scope['ranges']:
            fields(entry,'start end origin'); a=integer(entry['start'],0,len(document)); b=integer(entry['end'],a+1,len(document))
            require(a==prev and a in boundaries and b in boundaries,'scope-partition'); prev=b
            origin=entry['origin']; require(type(origin) is list and origin,'origin-structure')
            if origin[0]=='excluded':
                require(len(origin)==2 and type(origin[1]) is str and len(origin[1])<=1024,'exclusion-reason'); excluded=True; continue
            selected.append([a,b]); meaningful |= any(c not in ' \t\r\n\v\f\u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000' for c in document[a:b].decode('utf-8'))
            if origin[0]=='observed':
                require(len(origin)==2,'observed-origin'); _ref_list(origin[1],1,64)
                require(all(r in statement['captures'] for r in origin[1]),'origin-capture-binding')
                require(all(capture_subjects[r['sha256']]==statement['author'] for r in origin[1]),'observed-subject-binding')
            elif origin[0]=='inherited':
                require(len(origin)==4 and release['claim']=='wording-origin','inherited-not-fresh')
                parent=self.verify(origin[1],None,disclosures)
                pa=integer(origin[2],0,len(parent['_document'])); pb=integer(origin[3],pa+1,len(parent['_document']))
                require(pb-pa==b-a and parent['_document'][pa:pb]==document[a:b],'parent-text-binding')
                require(_covered(pa,pb,parent['ranges']),'parent-range-not-certified')
            else: raise Reject('unsupported-origin')
        require(prev==len(document) and meaningful and selected,'scope-completeness-or-vacuity')
        require((scope['kind']=='whole-document') == (not excluded),'whole-document-scope')
        allowed={r['sha256'] for r in self.policy['evaluators']}; evalkids=set()
        for r in proof['appraisals']:
            body,kid=self.signed(r); typed(body,'appraisal','statement result')
            require(same_ref(body['statement'],proof['statement']) and body['result']==PASS,'appraisal-result-or-statement')
            require(kid in allowed and kid not in evalkids and any(r['sha256']==kid and r['size']==len(self.store.objects[kid]) for r in self.policy['evaluators']),'evaluator-role-or-duplicate')
            require(kid not in capture_kids,'capture-evaluator-key-separation')
            evalkids.add(kid)
        require(len(evalkids)>=self.policy['quorum'],'evaluator-quorum')
        if statement['mode']=='disclosed-v1' or self.force_recompute:
            require(disclosures is not None,'missing-disclosed-evidence')
            fields(disclosures,'logs lineage_salts')
            require(type(disclosures['logs']) is list and len(disclosures['logs'])<=4096 and type(disclosures['lineage_salts']) is list and len(disclosures['lineage_salts'])<=64,'disclosure-count')
            logs={}; salts={}; disclosed_size=0; disclosed_events=0
            for entry in disclosures['logs']:
                fields(entry,'capture openings'); valid_ref(entry['capture'])
                require(type(entry['openings']) is list,'disclosure-openings')
                disclosed_events+=len(entry['openings']); require(disclosed_events<=MAX_EVENTS,'disclosure-event-budget')
                for opening in entry['openings']:
                    fields(opening,'index salt event'); octets(opening['event']); octets(opening['salt'],32)
                    disclosed_size+=len(opening['event'])+32
                    require(disclosed_size<=MAX_BYTES,'disclosure-byte-budget')
                require(entry['capture']['sha256'] not in logs,'duplicate-disclosed-session')
                logs[entry['capture']['sha256']]=(entry['capture'],entry['openings'])
            for entry in disclosures['lineage_salts']:
                fields(entry,'statement salt'); valid_ref(entry['statement']); octets(entry['salt'],32)
                require(entry['statement']['sha256'] not in salts,'duplicate-lineage-salt')
                salts[entry['statement']['sha256']]=(entry['statement'],entry['salt'])
            evidence=[]
            for c in captures:
                pair=logs.get(c['ref']['sha256'])
                require(pair is not None and pair[0]==c['ref'],'missing-disclosed-session')
                evidence.append({'capture':c['ref'],'events':open_transcript(c['start'],c['count'],c['root'],pair[1])})
            salt=salts.get(proof['statement']['sha256'])
            require(salt is not None and salt[0]==proof['statement'],'missing-lineage-salt')
            runner=self.runners.get(statement['release']['sha256'])
            require(callable(runner),'no-independently-installed-runner')
            # Call only a relying-party-installed implementation. The runner must
            # reconstruct the target, apply requested scope, and compute lineage.
            request={'target_capture':statement['target_capture'],'requested_scope':scope,'lineage_salt':salt[1], 'artifacts':{k:self.get(r) for k,r in release['artifacts'].items()}}
            actual=runner(evidence,release,request)
            expected={'document':statement['document'],'scope':statement['scope'],'lineage':statement['lineage'],'release':statement['release'],'captures':statement['captures'],'target_capture':statement['target_capture'],'result':PASS}
            require(encode(actual)==encode(expected),'recomputed-output-mismatch')
        author_status='none'
        if statement['author'] is None:
            require(proof['author'] is None and not self.policy['require_author'],'author-required-or-unexpected')
        else:
            self.get(statement['author']); parse_key(self.get(statement['author']))
            require(proof['author'] is not None,'missing-author-endorsement')
            body,kid=self.signed(proof['author']); typed(body,'author-endorsement','statement identity')
            require(same_ref(body['statement'],proof['statement']) and kid==statement['author']['sha256'],'author-binding')
            require(kid not in capture_kids and kid not in evalkids,'author-authority-key-separation')
            author_status='pseudonymous-key-endorsement'
            if body['identity'] is not None:
                identity,issuer=self.signed(body['identity']); typed(identity,'identity-binding','subject namespace identifier')
                require(any(r['sha256']==issuer and r['size']==len(self.store.objects[issuer]) for r in self.policy['identity_authorities']),'identity-authority')
                require(same_ref(identity['subject'],statement['author']),'identity-key-binding')
                require(type(identity['namespace']) is str and 0<len(identity['namespace'])<=256 and type(identity['identifier']) is str and 0<len(identity['identifier'])<=1024,'identity-fields')
                author_status={'kind':'attested-key-controller','namespace':identity['namespace'],'identifier':identity['identifier']}
        out={'status':'VALID-HWP','result':PASS,'claim':release['claim'],'scope':scope['kind'],'ranges':selected,'proof':proof_ref,'document':statement['document'],'release':statement['release'],'mode':statement['mode'],'policy_sha256':self.policy_digest,'policy_status_as_of':self.policy['status_as_of'],'author':author_status,'timestamp':'not-assessed','execution_checked':'recomputed' if statement['mode']=='disclosed-v1' or self.force_recompute else 'attestation','_document':document}
        self.done[h]=out; self.active.remove(h); return out


def _covered(start:int,end:int,ranges:list[list[int]]) -> bool:
    cursor=start
    for a,b in ranges:
        if b<=cursor: continue
        if a>cursor: return False
        cursor=max(cursor,b)
        if cursor>=end: return True
    return False


def verify_bundle(bundle:bytes,document:bytes,policy_bytes:bytes | None=None,
                  expected_policy_digest:bytes | None=None,disclosures:dict | None=None,
                  runners:dict | None=None,force_recompute:bool=False) -> dict:
    """Fail-closed public API. A failure is not a negative authorship certificate."""
    try:
        require(policy_bytes is not None and expected_policy_digest is not None,'no-external-trust-policy')
        store,root=Store.unpack(bundle)
        verifier=Verifier(store,policy_bytes,expected_policy_digest,runners,force_recompute)
        result=verifier.verify(root,octets(document),disclosures)
        return {k:v for k,v in result.items() if not k.startswith('_')}
    except (Reject,TypeError,KeyError,ValueError,OverflowError,RecursionError) as e:
        return {'status':'NO-VALID-HWP','reason':str(e) if isinstance(e,Reject) else 'malformed-input','authorship_inference':None}


def archive_inventory(bundle_bytes:bytes,policy_bytes:bytes,attachments:list[bytes]) -> bytes:
    """Strong inventory of actual bytes for ERS input; this is not a timestamp."""
    Store.unpack(bundle_bytes); policy_check(decode(policy_bytes))
    require(type(attachments) is list and len(attachments)<=MAX_OBJECTS,'archive-attachment-count')
    items=[bundle_bytes,policy_bytes]+attachments
    require(sum(len(octets(x)) for x in items)<=MAX_BYTES,'archive-byte-budget')
    entries=sorted({hashlib.sha512(octets(x)).digest():x for x in items}.items())
    raw=encode({'v':VERSION,'type':'archive-inventory','sha512_objects':[[h,b] for h,b in entries], 'bundle_sha512':hashlib.sha512(bundle_bytes).digest(),'policy_sha512':hashlib.sha512(policy_bytes).digest()})
    require(len(raw)<=MAX_BYTES,'archive-size'); return raw


def sign_appraisal(store:Store,statement_ref:dict,computed:dict,seed:bytes) -> dict:
    """Trusted evaluator boundary. `computed` MUST originate in its approved runner.

    This guard prevents accidental signing of a failed or misbound result; it is
    not protection from an issuer who controls the seed and chooses to lie.
    """
    s=store.obj(statement_ref)
    typed(s,'statement','document media_type scope release captures target_capture lineage mode author nonce')
    expected={'document':s['document'],'scope':s['scope'],'lineage':s['lineage'],'release':s['release'],'captures':s['captures'],'target_capture':s['target_capture'],'result':PASS}
    require(encode(computed)==encode(expected),'refuse-nonqualifying-or-mismatched-result')
    store.add(key_bytes(public_key(seed)))
    return store.add(sign({'v':VERSION,'type':'appraisal','statement':statement_ref,'result':PASS},seed))


def assemble_proof(store:Store,statement_ref:dict,appraisals:list[dict],author:dict|None,
                   document:bytes,policy_bytes:bytes,expected_policy_digest:bytes,
                   disclosures:dict|None=None,runners:dict|None=None) -> tuple[dict,bytes]:
    """Only return a proof package after the full relying-policy verifier passes."""
    proof={'v':VERSION,'type':'proof','statement':statement_ref,'appraisals':reference_list(appraisals),'author':author}
    root=store.put(proof); raw=store.pack(root)
    result=verify_bundle(raw,document,policy_bytes,expected_policy_digest,disclosures,runners)
    require(result['status']=='VALID-HWP','issuance-refused:'+result.get('reason','unknown'))
    return root,raw


def diagnostic_json(value:Any) -> Any:
    """Display helper only. Hex is NOT the canonical signed encoding."""
    if type(value) is bytes: return value.hex()
    if type(value) is list: return [diagnostic_json(v) for v in value]
    if type(value) is dict: return {str(k):diagnostic_json(v) for k,v in value.items()}
    return value


def main() -> None:
    import argparse, json
    from pathlib import Path
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('proof'); parser.add_argument('document')
    parser.add_argument('--policy',required=True)
    parser.add_argument('--policy-pin',required=True,help='Externally trusted SHA256 of exact policy CBOR, not a value supplied by the proof')
    args=parser.parse_args()
    def read(path):
        p=Path(path); require(p.stat().st_size<=MAX_BYTES,'file-size'); return p.read_bytes()
    try: result=verify_bundle(read(args.proof),read(args.document),read(args.policy),bytes.fromhex(args.policy_pin))
    except (OSError,ValueError) as e: result={'status':'NO-VALID-HWP','reason':'input-error','authorship_inference':None}
    print(json.dumps(diagnostic_json(result),sort_keys=True,indent=2))
    raise SystemExit(0 if result['status']=='VALID-HWP' else 1)

if __name__=='__main__': main()
