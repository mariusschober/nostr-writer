"""Synthetic fixtures only. No event in this module was collected from a person."""
from __future__ import annotations
from copy import deepcopy
import random
from reference import VERSION, Q, FEATURES, INTERACTIONS, FAMILIES, Replay, replay

class TraceBuilder:
    """Produces normalized telemetry for conformance tests, not a collector."""
    def __init__(self, mode="keyboard", quantum=1000, session_id="SYNTHETIC"):
        self.data = dict(version=VERSION,session_id=session_id,language="en",mode=mode,
                         quantum_us=quantum,events=[],document="")
        self.t = 0
        self.current_mode = mode
        self.history = []
        self.future = []

    def emit(self,op,dt=0,**fields):
        self.t += dt
        q = self.data["quantum_us"]
        self.t = ((self.t+q-1)//q)*q
        seq = len(self.data["events"])
        self.data["events"].append(dict(seq=seq,t_us=self.t,op=op,**fields))
        return seq

    def input(self,intent,txt="",source="candidate",dt=100_000):
        return self.emit("input",dt,intent=intent,text=txt,source=source)

    def edit(self,at,end,txt,source="candidate",dt=100_000,preedit=0):
        before = self.data["document"][at:end]
        cs = []
        if self.current_mode == "ime" and txt:
            for j in range(preedit):
                cs.append(self.input("preedit","x"*(j+1),source,dt))
        cs.append(self.input("text" if txt else "delete",txt,source,dt))
        self.emit("edit",at=at,end=end,before=before,text=txt,causes=cs)
        self.history.append(self.data["document"]); self.future.clear()
        self.data["document"] = self.data["document"][:at]+txt+self.data["document"][end:]
        return cs[-1]

    def type(self,txt,dt=100_000,source="candidate"):
        for c in txt:
            self.edit(len(self.data["document"]),len(self.data["document"]),c,source,dt)
        return self

    def select(self,at):
        c = self.input("select")
        self.emit("select",at=at,causes=[c])

    def copy(self,start,end,at):
        c = self.input("copy")
        self.emit("copy",start=start,end=end,at=at,causes=[c])
        d = self.data["document"]
        self.history.append(d); self.future.clear()
        self.data["document"] = d[:at]+d[start:end]+d[at:]

    def move(self,start,end,at):
        c = self.input("move")
        self.emit("move",start=start,end=end,at=at,causes=[c])
        d = self.data["document"]; frag=d[start:end]; rest=d[:start]+d[end:]
        self.history.append(d); self.future.clear()
        self.data["document"] = rest[:at]+frag+rest[at:]

    def undo(self):
        c = self.input("undo"); self.emit("undo",causes=[c])
        self.future.append(self.data["document"]); self.data["document"] = self.history.pop()

    def redo(self):
        c = self.input("redo"); self.emit("redo",causes=[c])
        self.history.append(self.data["document"]); self.data["document"] = self.future.pop()

    def switch(self,mode):
        self.emit("mode",mode=mode); self.current_mode = mode

    def finish(self):
        return deepcopy(self.data)


def mock_model(mode="keyboard",language="en",threshold=-1):
    """Deliberately permissive UNIT-TEST policy. Never approved for real writing."""
    dim=2*len(FEATURES)+len(INTERACTIONS)
    return dict(version=VERSION,id="UNIT-TEST-ONLY-"+mode,mode=mode,language=language,
                center=[0]*len(FEATURES),scale=[Q]*len(FEATURES),
                weights={f:[0]*dim for f in FAMILIES},bias={f:0 for f in FAMILIES},
                prototypes={f"test-{i}":[[0]*len(FEATURES)] for i in range(5)},
                support_k=5,radius2=10**25,threshold=threshold,families=list(FAMILIES))

SAMPLE = "A writer can inspect an idea and choose new words. Earlier choices shape later revisions, but the record alone does not reveal thought. "


def synthetic(seed: int, label: str, mode="keyboard") -> dict:
    """Controlled toy separability: labels describe generators, not actual cognition.

    'human' is a deliberately separable varied-timing/revision GENERATOR.
    Its success cannot be interpreted as human detector accuracy.
    """
    rng=random.Random(seed)
    b=TraceBuilder(mode=mode,session_id=f"SYNTHETIC-{label}-{seed}")
    for i,c in enumerate(SAMPLE):
        if label == "human":
            dt = rng.randint(70,190)*1000 + (rng.randint(700,1600)*1000 if i and SAMPLE[i-1] == " " else 0)
        elif label == "transcription":
            dt = rng.randint(70,150)*1000
        elif label == "automation":
            dt = 90_000
        elif label == "simulation":
            dt = rng.randint(70,190)*1000 + (rng.randint(700,1600)*1000 if rng.random() < .16 else 0)
        elif label == "mixed":
            dt = rng.randint(70,190)*1000 + (900_000 if i < 65 and i and SAMPLE[i-1] == " " else 0)
        else:
            raise ValueError(label)
        b.edit(len(b.data["document"]),len(b.data["document"]),c,dt=dt)
        if label == "human" and i in (31,67,101):
            # Provisional mistakes are not enough to meet surviving-input gates.
            pos=len(b.data["document"])
            b.edit(pos,pos,"x",dt=80_000)
            b.edit(pos,pos+1,"",dt=200_000)
    return b.finish()
