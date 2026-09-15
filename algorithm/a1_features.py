"""Fixed HWP-A1 evidence units and integer process features."""
from __future__ import annotations
from a1_types import *

@dataclass
class Unit:
    uid: str
    roots: tuple[int, ...]
    mode: str
    axis: str


def windows(xs: list[int], width: int) -> list[tuple[int, ...]]:
    if not xs:
        return []
    starts = list(range(0, max(1, len(xs)-width+1), width//2))
    starts.append(max(0, len(xs)-width))
    return [tuple(sorted(set(xs[a:a+width]))) for a in sorted(set(starts))]


def units(r: Replay) -> list[Unit]:
    """Two immutable axes; final order cannot erase short birth-lane gates."""
    out: list[Unit] = []
    run: list[int] = []
    previous = None
    def add(xs: list[int], axis: str):
        for width in (64, 256):
            for roots in windows(xs, width):
                out.append(Unit(f"{axis}:{len(out)}", roots, r.roots[roots[0]].mode, axis))
    for atom in r.live:
        rr = r.roots[atom.root]
        key = (rr.source, rr.mode, rr.epoch)
        if key != previous or rr.source != "candidate":
            add(run, "final"); run = []
        if rr.source == "candidate":
            run.append(atom.root)
        previous = key
    add(run, "final")
    groups = defaultdict(list)
    for root_id in sorted({a.root for a in r.live}):
        rr = r.roots[root_id]
        if rr.source == "candidate":
            groups[(rr.mode, rr.epoch, rr.lane)].append(root_id)
    for xs in groups.values():
        add(xs, "birth")
    # Duplicate memberships on an axis add no information and are removed.
    unique = {}
    for u in out:
        unique.setdefault((u.axis, u.roots), u)
    return list(unique.values())

BASE_FEATURES = [
    "root_count", "action_count", "mutation_count", "survival", "repeat_occurrence",
    "delete_ratio", "replace_fraction", "remote_fraction", "move_fraction", "history_fraction",
    "jump_mean", "jump_q90", "revision_age_q50", "revision_age_q90", "external_parent_fraction",
    "insert_q50", "insert_q90", "input_batch_q90", "boundary_fraction", "sentence_fraction",
    "interval_count", "interval_missing", "interval_q10", "interval_q50", "interval_q90",
    "interval_mad", "word_pause", "sentence_pause", "inner_pause", "pause_context_difference",
    "dwell_missing", "dwell_q50", "dwell_q90", "burst_q50", "burst_q90", "adjacent_revision",
    "lag_change", "pause_revision_joint", "lexical_response", "lexical_response_missing",
    "quantum", "birth_axis", "revision_chain_depth", "temporary_fraction"
]
PAUSE_CUTS = (20_000, 50_000, 100_000, 250_000, 500_000, 1_000_000, 2_000_000, 5_000_000, 10_000_000)
FEATURES = BASE_FEATURES + [f"interval_le_{x}" for x in PAUSE_CUTS] + [f"transition_{i}_{j}" for i in range(5) for j in range(5)]
INTERACTIONS = ((5, 26), (6, 36), (7, 37), (8, 38), (13, 38), (14, 6), (3, 43), (10, 27),
                (15, 23), (17, 24), (18, 26), (19, 27), (23, 6), (25, 7), (29, 38), (34, 5))


def tokens(s: str) -> set[str]:
    # Equality-only local tokens, no language model or authorship vocabulary.
    out, buf = set(), []
    for c in s + " ":
        if c in WS or c in STOPS or c in ",;:()[]{}\"":
            if buf:
                out.add("".join(buf)); buf = []
        else:
            buf.append(c)
    return out


def features(r: Replay, u: Unit) -> tuple[list[int], list[str]]:
    target = set(u.roots)
    closure = set(target)
    todo = list(target)
    depth = {v: 0 for v in target}
    while todo:
        a = todo.pop()
        for p in r.roots[a].parents:
            if p not in closure:
                closure.add(p); depth[p] = depth[a]+1; todo.append(p)
                require(len(closure) <= LIMITS["closure"], "ANCESTRY_LIMIT")
    ms = [m for m in r.mutations if m.touched & closure]
    cause_ids = sorted({c for a in target for c in r.roots[a].causes})
    support = [c for c in cause_ids if r.inputs[c]["source"] == "candidate"]
    reasons = []
    if len(target) < 32:
        reasons.append("SHORT_SURVIVING_TEXT")
    if len(support) < 16:
        reasons.append("SHORT_SURVIVING_INPUT")
    if not ms:
        reasons.append("NO_PROCESS")
    ins = [len(m.created) for m in ms if m.created]
    dels = [len(m.removed) for m in ms]
    age = [min(60_000_000, m.age) for m in ms if m.removed]
    jumps = [min(4096, m.jump) for m in ms]
    external_parents = {v for v in closure-target if r.roots[v].source != "candidate"}
    boundary_by_input = {c: m.boundary for m in ms for c in m.causes}
    mutation_by_input = {c: m for m in ms for c in m.causes}
    intervals, conditioned, revision_joint = [], defaultdict(list), []
    bursts, current_burst = [], 1
    for a, b in zip(cause_ids, cause_ids[1:]):
        ia, ib = r.inputs[a], r.inputs[b]
        dt = ib["t_us"]-ia["t_us"]
        valid = ib["ordinal"] == ia["ordinal"]+1 and ia["epoch"] == ib["epoch"] and 0 <= dt < 30_000_000
        if valid:
            intervals.append(dt)
            conditioned[boundary_by_input.get(b, 0)].append(dt)
            m = mutation_by_input.get(b)
            revision_joint.append(int(dt >= 500_000 and m is not None and (m.removed or m.jump > 64)))
        if valid and dt < 2_000_000:
            current_burst += 1
        else:
            bursts.append(current_burst); current_burst = 1
    if cause_ids:
        bursts.append(current_burst)
    dwell = [min(2_000_000, r.releases[c]-r.inputs[c]["t_us"]) for c in cause_ids if c in r.releases]
    med = quantile(intervals, 50)
    changes = [abs(b-a) for a, b in zip(intervals, intervals[1:])]
    statuses = []
    for m in ms:
        statuses.append(4 if m.op in ("move", "copy", "undo", "redo") else 3 if not m.created else 2 if m.jump > 64 else 1 if m.removed else 0)
    adjacent = [(a, b) for a, b in zip(ms, ms[1:]) if a.epoch == b.epoch and b.t-a.t < 30_000_000]
    opportunities = responses = 0
    for i, m in enumerate(ms):
        old, new = tokens(m.before), tokens(m.after)
        lost, gained = old-new, new-old
        if lost and gained:
            opportunities += 1
            later = set().union(*(tokens(mm.after) for mm in ms[i+1:i+9]))
            responses += int(bool(gained & later) and not bool(lost & later))
    total_created = {v for m in ms for v in m.created}
    all_final = {a.root for a in r.live}
    duplicates = sum(a.root in target for a in r.live)
    vals = [
        logsize(len(target)), logsize(len(support)), logsize(len(ms)), ratio(len(target), len(closure)), ratio(duplicates-len(target), duplicates),
        ratio(sum(dels), sum(ins)+sum(dels)), ratio(sum(bool(m.removed and m.created) for m in ms), len(ms)),
        ratio(sum(m.jump > 64 for m in ms), len(ms)), ratio(sum(m.op in ("move", "copy") for m in ms), len(ms)),
        ratio(sum(m.op in ("undo", "redo") for m in ms), len(ms)), ratio(mean(jumps),4096), ratio(quantile(jumps,90),4096),
        ratio(quantile(age,50),60_000_000), ratio(quantile(age,90),60_000_000), ratio(len(external_parents),len(closure)),
        ratio(quantile(ins,50),256), ratio(quantile(ins,90),256), ratio(quantile([len(m.causes) for m in ms],90),64),
        ratio(sum(m.boundary >= 1 for m in ms),len(ms)), ratio(sum(m.boundary == 2 for m in ms),len(ms)),
        logsize(len(intervals)), ratio(max(0,len(cause_ids)-1-len(intervals)),max(1,len(cause_ids)-1)),
        ratio(quantile(intervals,10),30_000_000), ratio(med,30_000_000), ratio(quantile(intervals,90),30_000_000),
        ratio(quantile([abs(x-med) for x in intervals],50),30_000_000), ratio(quantile(conditioned[1],50),30_000_000),
        ratio(quantile(conditioned[2],50),30_000_000), ratio(quantile(conditioned[0],50),30_000_000),
        ratio(abs(quantile(conditioned[1]+conditioned[2],50)-quantile(conditioned[0],50)),30_000_000),
        ratio(len(cause_ids)-len(dwell),len(cause_ids)), ratio(quantile(dwell,50),2_000_000), ratio(quantile(dwell,90),2_000_000),
        ratio(quantile(bursts,50),256), ratio(quantile(bursts,90),256),
        ratio(sum(bool(a.removed or b.removed) for a,b in adjacent),len(adjacent)), ratio(mean(changes),30_000_000),
        ratio(sum(revision_joint),len(revision_joint)), ratio(responses,opportunities), Q if not opportunities else 0,
        ratio(r.quantum,20_000), Q if u.axis == "birth" else 0, ratio(max(depth.values(),default=0),64),
        ratio(len(total_created-all_final),len(total_created)),
    ]
    vals += [ratio(sum(d <= cut for d in intervals), len(intervals)) for cut in PAUSE_CUTS]
    pairs = list(zip(statuses, statuses[1:]))
    vals += [ratio(sum(a == i and b == j for a,b in pairs),len(pairs)) for i in range(5) for j in range(5)]
    require(len(vals) == len(FEATURES), "FEATURE_DIMENSION")
    return vals, reasons


