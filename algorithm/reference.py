"""Public HWP-A1 algorithm API and integer decision procedure.

No capture authentication, cryptography or UI. Trusted admission is required.
Replay and feature definitions are imported from the accompanying core modules.
"""
from __future__ import annotations
from a1_types import *
from a1_replay import replay
from a1_features import *

def lifted(z: list[int]) -> list[int]:
    return z + [v*v//Q for v in z] + [z[a]*z[b]//Q for a,b in INTERACTIONS]


def normalize(x: list[int], model: dict) -> tuple[list[int], bool]:
    require(len(x) == len(FEATURES), "FEATURE_DIMENSION")
    z = [(v-c)*Q//s for v,c,s in zip(x,model["center"],model["scale"])]
    return [max(-8*Q,min(8*Q,v)) for v in z], all(abs(v) <= 8*Q for v in z)


def model_check(m: dict) -> None:
    needed = {"version", "id", "mode", "language", "center", "scale", "weights", "bias", "prototypes", "support_k", "radius2", "threshold", "families"}
    exact_keys(m, needed)
    require(m["version"] == VERSION and type(m["id"]) is str and bool(m["id"]), "MODEL_VERSION")
    require(m["mode"] in MODES and type(m["language"]) is str, "MODEL_STRATUM")
    require(type(m["families"]) is list and m["families"] == list(FAMILIES), "MODEL_FAMILIES")
    require(len(m["center"]) == len(m["scale"]) == len(FEATURES), "MODEL_DIMENSION")
    for v in m["center"]:
        integer(v,0,Q)
    for v in m["scale"]:
        integer(v,1,8*Q)
    require(set(m["weights"]) == set(m["bias"]) == set(m["families"]), "MODEL_HEADS")
    dim = 2*len(FEATURES)+len(INTERACTIONS)
    for f in m["families"]:
        require(len(m["weights"][f]) == dim, "MODEL_WEIGHT_DIMENSION")
        for w in m["weights"][f]+[m["bias"][f]]:
            integer(w,-10**12,10**12)
    require(type(m["prototypes"]) is dict, "PROTOTYPES")
    for group, vectors in m["prototypes"].items():
        require(type(group) is str and 1 <= len(vectors) <= 20, "PROTOTYPES")
        for v in vectors:
            require(len(v) == len(FEATURES), "PROTOTYPE_DIMENSION")
            for a in v:
                integer(a,-8*Q,8*Q)
    integer(m["support_k"],5,5)
    require(len(m["prototypes"]) >= 5, "PROTOTYPE_GROUP_COUNT")
    integer(m["radius2"],0,10**30)
    if m["threshold"] is not None:
        integer(m["threshold"],-10**30,10**30)


def support_distance(z: list[int], m: dict) -> int:
    distances = [min(sum((a-b)**2 for a,b in zip(z,p)) for p in ps) for ps in m["prototypes"].values()]
    return sorted(distances)[m["support_k"]-1]


def score(x: list[int], m: dict) -> tuple[int | None, list[str]]:
    z, in_box = normalize(x,m)
    if not in_box or support_distance(z,m) > m["radius2"]:
        return None, ["OUT_OF_SUPPORT"]
    v = lifted(z)
    return min(m["bias"][f]*Q + sum(a*b for a,b in zip(m["weights"][f],v)) for f in m["families"]), []


def analyze(trace: dict, models: dict[str,dict]) -> tuple[Replay, dict[int,int | None], list[dict]]:
    """Pure calculation before threshold or external admission; not certification."""
    r = replay(trace)
    for k,m in models.items():
        model_check(m)
        require(k == m["mode"], "MODEL_KEY")
    scores: dict[int,int | None] = {a.root: None for a in r.live}
    seen: set[int] = set()
    details = []
    for u in units(r):
        x, reasons = features(r,u)
        m = models.get(u.mode)
        val = None
        if m is None or m["language"] != r.language:
            reasons.append("UNSUPPORTED_STRATUM")
        elif not reasons:
            val, more = score(x,m); reasons.extend(more)
        for root_id in u.roots:
            if root_id not in seen:
                scores[root_id] = val; seen.add(root_id)
            elif val is None or scores[root_id] is None:
                scores[root_id] = None
            else:
                scores[root_id] = min(scores[root_id],val)
        details.append(dict(id=u.uid,axis=u.axis,roots=list(u.roots),score=val,reasons=reasons,features=x))
    return r,scores,details

@dataclass(frozen=True)
class Admission:
    """Trusted caller input. Never deserialize this from the submitted trace."""
    capture_accepted: bool = False
    fresh_session_accepted: bool = False
    approved_model_ids: frozenset[str] = frozenset()


def assess(trace: dict, models: dict[str,dict], claims: list[list[int]] | None = None,
           admission: Admission = Admission()) -> dict:
    """Claims are UTF-8 half-open byte ranges. Default claims the whole document.

    Returned range verdicts are contextual assessments of the creation process,
    not independent mental-state proofs about single characters.
    """
    try:
        r,scores,details = analyze(trace,models)
        byte = offsets(r.document)
        if claims is None:
            claims = [[0,byte[-1]]]
        require(type(claims) is list and bool(claims), "EMPTY_SCOPE")
        last = 0
        for c in claims:
            require(type(c) is list and len(c) == 2, "SCOPE_SCHEMA")
            a,b = integer(c[0]), integer(c[1])
            require(a in byte and b in byte and last <= a < b <= byte[-1], "SCOPE_BOUNDARY_OR_OVERLAP")
            last = b
        accepted, reasons = [], set()
        for atom in r.live:
            rr = r.roots[atom.root]
            m = models.get(rr.mode)
            ok = rr.source == "candidate" and atom.copied_from is None and scores[atom.root] is not None and m is not None
            if atom.copied_from is not None:
                reasons.add("COPIED_OCCURRENCE_NOT_FRESH_COMPOSITION")
            if rr.source != "candidate":
                reasons.add("NONCANDIDATE_ORIGIN")
            if ok:
                ok = m["threshold"] is not None and scores[atom.root] > m["threshold"]
            if ok:
                ok = admission.capture_accepted and admission.fresh_session_accepted and m["id"] in admission.approved_model_ids
            accepted.append(bool(ok))
        if not admission.capture_accepted or not admission.fresh_session_accepted:
            reasons.add("CAPTURE_NOT_ADMITTED")
        if any(m["id"] not in admission.approved_model_ids for m in models.values()):
            reasons.add("MODEL_NOT_APPROVED")
        ranges = []
        for a,b in claims:
            lo,hi = byte.index(a),byte.index(b)
            ok = all(accepted[lo:hi])
            ranges.append(dict(start=a,end=b,verdict="HUMAN-WRITTEN" if ok else "NOT PROVABLE"))
        # Complete provenance partition, independent of the requested claim.
        partition = []
        for i,ok in enumerate(accepted):
            rr = r.roots[r.live[i].root]
            source = "internal-copy" if r.live[i].copied_from is not None else rr.source
            key = (ok,source,rr.mode)
            if partition and partition[-1]["_key"] == key:
                partition[-1]["end"] = byte[i+1]
            else:
                partition.append(dict(start=byte[i],end=byte[i+1],verdict="HUMAN-WRITTEN" if ok else "NOT PROVABLE",origin=source,mode=rr.mode,_key=key))
        for p in partition:
            del p["_key"]
        if any(v is None for v in scores.values()):
            reasons.add("UNSUPPORTED_LOCAL_EVIDENCE")
        elif any(not a for a in accepted):
            reasons.add("POLICY_OR_SCORE_NOT_MET")
        return dict(version=VERSION,verdict="HUMAN-WRITTEN" if all(c["verdict"] == "HUMAN-WRITTEN" for c in ranges) else "NOT PROVABLE",
                    claim_kind="whole-document" if claims == [[0,byte[-1]]] else "specified-ranges",
                    claims=ranges,partition=partition,reasons=sorted(reasons),units=details)
    except (Invalid, KeyError, TypeError, IndexError, ZeroDivisionError, RecursionError) as e:
        return dict(version=VERSION,verdict="NOT PROVABLE",reasons=[f"INVALID:{e}"],claims=[],partition=[],units=[])


def attack_score(trace: dict, models: dict[str,dict], bad_ranges: list[list[int]], mode: str) -> int | None:
    """Largest root score on any labelled nonqualifying scalar; bottom is None.

    Taking the maximum over attempts gives one campaign's calibration observation.
    Invalid traces are structural rejections, not silently removed observations.
    """
    try:
        r,scores,_ = analyze(trace,models)
    except Invalid:
        return None
    bs = offsets(r.document)
    require(bool(bad_ranges), "BAD_LABEL_EMPTY")
    previous = 0
    for a,b in bad_ranges:
        require(type(a) is int and type(b) is int and a in bs and b in bs and previous <= a < b <= bs[-1], "BAD_LABEL_RANGE")
        previous = b
    vals = [scores[a.root] for i,a in enumerate(r.live)
            if a.copied_from is None and r.roots[a.root].mode == mode and any(lo <= bs[i] and bs[i+1] <= hi for lo,hi in bad_ranges)
            and scores[a.root] is not None]
    return max(vals) if vals else None
