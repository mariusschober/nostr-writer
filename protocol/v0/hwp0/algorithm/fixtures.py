"""Synthetic fixtures only. None are evidence of a real human writing process."""
from __future__ import annotations
from copy import deepcopy
from random import Random
from .replay import replay,make_units
from .features import extract
from .model import HEADS,ROUNDS,domain

class Builder:
    def __init__(self,did='d',profile='keyboard',language='en'):
        self.did,self.profile,self.language=did,profile,language
        self.observations=[]; self.transactions=[]; self.text=''; self.time=100_000
        self.history=[]; self.redo_history=[]
    def observation(self,kind,time,token,source='device',basis=None):
        o={'i':len(self.observations),'t':time,'kind':kind,'token':token,'source':source,'profile':self.profile}
        if basis is not None: o['basis']=basis
        self.observations.append(o); return o['i']
    def cause(self,command=False,source='device',delay=150_000):
        t=self.time+delay; token=f'p{len(self.observations)}'
        if command:
            cause=self.observation('command',t,token,source); self.time=t+40_000; return cause,t
        if self.profile in ('keyboard','touch-tap'):
            begin,end=('press','release') if self.profile=='keyboard' else ('touch_down','touch_up')
            cause=self.observation(begin,t,token,source); self.observation(end,t+30_000,token,source)
            self.time=t+30_000; return cause,t
        if self.profile=='ime':
            self.observation('ime_start',t,token,source)
            b=self.observation('touch_down',t+1000,token+'-tap',source)
            self.observation('touch_up',t+30_000,token+'-tap',source)
            self.observation('ime_update',t+40_000,token,source)
            cause=self.observation('ime_commit',t+50_000,token,source,[b]); self.time=t+50_000; return cause,self.time
        self.observation('gesture_start',t,token,source)
        self.observation('gesture_update',t+100_000,token,source)
        cause=self.observation('gesture_end',t+200_000,token,source); self.time=t+200_000; return cause,self.time
    def add(self,op,cause,t,**kwargs):
        tx={'i':len(self.transactions),'t':t,'op':op,'profile':self.profile,'causes':[cause],**kwargs}
        self.transactions.append(tx); return tx
    def splice(self,start,end,text,source='direct',delay=150_000,observed_source='device'):
        cause,t=self.cause(source!='direct',observed_source,delay)
        old=self.text[start:end]; before=self.text
        tx=self.add('splice',cause,t,start=start,end=end,text=text,deleted=old,source=source)
        self.text=self.text[:start]+text+self.text[end:]
        self.history.append((before,self.text,tx['i'])); self.redo_history=[]
        return self
    def type(self,text,seed=None):
        rng=Random(seed) if seed is not None else None
        chunks=list(text) if self.profile in ('keyboard','touch-tap') else [text[i:i+4] for i in range(0,len(text),4)]
        for chunk in chunks: self.splice(len(self.text),len(self.text),chunk,delay=rng.randrange(60,450)*1000 if rng else 150_000)
        return self
    def control(self,op,**kwargs):
        cause,t=self.cause(True); before=self.text
        if op=='copy':
            need_parent=kwargs.pop('parent_text',self.text)
            frag=need_parent[kwargs['start']:kwargs['end']]; to=kwargs['to']
            self.text=self.text[:to]+frag+self.text[to:]
        elif op=='move':
            a,b,to=kwargs['start'],kwargs['end'],kwargs['to']; frag=self.text[a:b]
            s=self.text[:a]+self.text[b:]; self.text=s[:to]+frag+s[to:]
        elif op in ('undo','redo'):
            stack,other=(self.history,self.redo_history) if op=='undo' else (self.redo_history,self.history)
            pre,post,ref=stack.pop(); self.text=pre if op=='undo' else post; kwargs={'ref':ref}; other.append((pre,post,ref))
        tx=self.add(op,cause,t,**kwargs)
        if op not in ('undo','redo','navigate'): self.history.append((before,self.text,tx['i'])); self.redo_history=[]
        return self
    def gap(self):
        self.time+=1000; self.observation('gap',self.time,'gap'); return self
    def pause(self,us=121_000_000): self.time+=us; return self
    def record(self):
        # Synthetic normalized deliveries: never a converter for real legacy records.
        obs = deepcopy(self.observations); txs = deepcopy(self.transactions)
        stream = [(o['t'],0,i,o) for i,o in enumerate(obs)]
        for tx in txs:
            delivery = {'i':len(obs),'t':tx['t'],'kind':'delivery','token':'delivery-'+str(tx['i']),
                        'source':obs[tx['causes'][0]]['source'],'profile':tx['profile'],
                        'effect':{k:v for k,v in tx.items() if k not in ('i','t')}}
            tx['delivery']=delivery['i']; obs.append(delivery)
            stream.extend([(tx['t'],1,tx['i'],delivery),(tx['t'],2,tx['i'],tx)])
        stream.sort(key=lambda x:x[:3])
        for seq,(_,_,_,event) in enumerate(stream): event['seq']=seq
        order = sorted(obs,key=lambda o:o['seq']); mapping={o['i']:i for i,o in enumerate(order)}
        for i,o in enumerate(order):
            o['i']=i
            if 'basis' in o: o['basis']=[mapping[n] for n in o['basis']]
            if o['kind']=='delivery': o['effect']['causes']=[mapping[n] for n in o['effect']['causes']]
        for tx in txs:
            tx['causes']=[mapping[n] for n in tx['causes']]; tx['delivery']=mapping[tx['delivery']]
        return {'id':self.did,'language':self.language,'resolution_us':1000,'paths':{self.profile:'fixture-path/'+self.profile},'observations':order,
                'transactions':txs,'final_text':self.text}
    def bundle(self,parents=()):
        return {'version':'hwp-a/v0','documents':list(parents)+[self.record()],'target':self.did}

TEXT='A writer considers a claim, changes the wording, and follows the consequences through a longer argument. This synthetic fixture proves no human authorship. '


def permissive_fixture_model(bundle):
    """Deliberately permissive TEST double, never a trained or approved detector."""
    c=replay(bundle); domains={}; names=None
    for did in c.documents:
        uu,_=make_units(c,did)
        for u in uu:
            f=extract(c,u); names=list(f)
            z=domain(u.profile,u.language,u.view,c.documents[u.doc].paths[u.profile])
            domains[z]={'heads':{h:[{'value':0} for _ in range(ROUNDS)] for h in HEADS},
                        'scales':[10000]*len(f),'prototypes':[list(f.values())],
                        'support_calibration':[10**9]*99}
    return {'version':'hwp-a-model/v0','purpose':'fixture','features':names or [],'domains':domains}
