"""Deterministic Unicode-scalar replay, exact origin tracking, and evidence windows.

A valid trace is not authenticated capture and is not proof of composition.
The caller supplies capture admissibility separately. See SPECIFICATION.md.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any
import json

MAX_SCALARS = 200_000
MAX_EVENTS = 500_000
MAX_DOCS = 32
MAX_ATOMS = 1_000_000
MAX_IDS_STORED = 5_000_000
MAX_EFFECT_EDGES = 5_000_000
MAX_EXTERNAL_SCALARS = 1_000_000
MAX_INT = 2**53 - 1
MIN_ROOTS = 64
WINDOWS = ((64, 32), (256, 128))
RUN_GAP = 120_000_000
MAX_CAUSE_DELAY = 250_000
PROFILES = {
    'keyboard': ('press', 8, 16),
    'touch-tap': ('touch_down', 8, 16),
    'ime': ('ime_commit', 256, 4),
    'gesture': ('gesture_end', 64, 4),
}
SPACE = frozenset('\t\n\v\f\r \u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000')
ENDS = {'release': 'press', 'touch_up': 'touch_down', 'ime_commit': 'ime_start', 'gesture_end': 'gesture_start'}
UPDATES = {'touch_move': 'touch_down', 'ime_update': 'ime_start', 'gesture_update': 'gesture_start'}
STARTS = set(ENDS.values())
OBS_KINDS = STARTS | set(ENDS) | set(UPDATES) | {'repeat', 'command', 'focus_out', 'focus_in', 'suspend', 'resume', 'gap', 'delivery'}

class InvalidTrace(ValueError):
    pass

def need(ok: bool, reason: str) -> None:
    if not ok:
        raise InvalidTrace(reason)

def num(x: Any, low: int = 0, high: int = MAX_INT) -> int:
    need(type(x) is int and low <= x <= high, 'INTEGER_DOMAIN')
    return x

def string(x: Any, maximum: int = MAX_SCALARS) -> str:
    need(type(x) is str and len(x) <= maximum and not any(0xD800 <= ord(c) <= 0xDFFF for c in x), 'TEXT_DOMAIN')
    return x

def shape(x: Any, required: set[str], optional: set[str] = frozenset()) -> None:
    need(type(x) is dict and required <= x.keys() and x.keys() <= required | optional, 'OBJECT_FIELDS')

def utf8_offsets(s: str) -> list[int]:
    out = [0]
    for ch in s:
        out.append(out[-1] + len(ch.encode('utf-8')))
    return out

def scalar_range(s: str, start: int, end: int) -> tuple[int, int]:
    oo = utf8_offsets(s); table = {b: i for i, b in enumerate(oo)}
    num(start, 0, oo[-1]); num(end, start, oo[-1])
    need(start in table and end in table, 'SPLIT_UNICODE_SCALAR')
    return table[start], table[end]

def edit_distance(a: str, b: str) -> int:
    need(len(a) <= 32 and len(b) <= 32, 'SPELLING_LIMIT')
    row = list(range(len(b)+1))
    for i, ca in enumerate(a, 1):
        nxt = [i]
        for j, cb in enumerate(b, 1):
            nxt.append(min(nxt[-1]+1, row[j]+1, row[j-1]+(ca != cb)))
        row = nxt
    return row[-1]

@dataclass(frozen=True)
class Atom:
    aid: str
    char: str
    roots: frozenset[str]
    kind: str                # candidate, external, derived
    home: str
    birth: int
    run: str
    profile: str
    requirements: frozenset[str]
    spelling: bool = False

@dataclass
class Effect:
    index: int
    time: int
    op: str
    source: str
    profile: str
    run: str
    pos: int
    before_length: int
    old: str
    new: str
    born: tuple[str, ...]
    touched: frozenset[str]
    causes: tuple[int, ...]
    preceding: int
    navigation: int
    ages: tuple[int, ...]
    barrier: bool

@dataclass
class Document:
    did: str
    language: str
    resolution: int
    observations: list[dict]
    effects: list[Effect]
    live: list[str]
    text: str
    gap: bool
    runs: dict[str, list[str]]
    paths: dict[str, str]
    durations: dict[int, int]
    unsafe_control: bool

@dataclass
class Corpus:
    documents: dict[str, Document] = field(default_factory=dict)
    atoms: dict[str, Atom] = field(default_factory=dict)
    root_effects: dict[str, list[tuple[str, int]]] = field(default_factory=dict)
    external: list[tuple[str,int,str]] = field(default_factory=list)
    external_scalars: int = 0
    effect_edges: int = 0
    analysis_edges: int = 0
    stored_ids: int = 0
    def text(self, ids) -> str:
        return ''.join(self.atoms[a].char for a in ids)


def parse_observations(items: Any, resolution: int) -> tuple[list[dict], bool]:
    need(type(items) is list and len(items) <= MAX_EVENTS, 'OBSERVATION_LIMIT')
    active, used_tokens = {}, set()
    last, gap, focused, suspended = 0, False, True, False
    for i, o in enumerate(items):
        shape(o, {'i','t','seq','kind','token','source','profile'}, {'basis','effect'})
        need(num(o['i']) == i, 'OBSERVATION_SEQUENCE')
        num(o['seq'])
        t = num(o['t']); need(t >= last and t % resolution == 0, 'OBSERVATION_CLOCK'); last = t
        kind = o['kind']; need(type(kind) is str and kind in OBS_KINDS, 'OBSERVATION_KIND')
        need(type(o['profile']) is str and o['profile'] in PROFILES, 'PROFILE')
        need(o['source'] in ('device','synthetic','unknown'), 'OBSERVATION_SOURCE')
        token = string(o['token'], 128); need(bool(token), 'TOKEN')
        if kind == 'gap': gap = True
        if kind == 'focus_out': need(focused, 'FOCUS_STATE'); focused = False
        if kind == 'focus_in': need(not focused, 'FOCUS_STATE'); focused = True
        if kind == 'suspend': need(not suspended, 'SUSPEND_STATE'); suspended = True
        if kind == 'resume': need(suspended, 'SUSPEND_STATE'); suspended = False
        if kind in STARTS:
            need(focused and not suspended, 'INPUT_OUTSIDE_OBSERVATION')
            key = (kind, token)
            need(key not in used_tokens, 'INPUT_TOKEN_REUSE')
            if kind=='ime_start': need(not any(k[0]=='ime_start' for k in active),'OVERLAPPING_IME')
            used_tokens.add(key); active[key] = o
        elif kind in ENDS:
            if kind in ('ime_commit','gesture_end'): need(focused and not suspended, 'INPUT_OUTSIDE_OBSERVATION')
            key = (ENDS[kind], token); need(key in active, 'END_WITHOUT_START')
            begin = active.pop(key)
            need(begin['profile'] == o['profile'] and begin['source'] == o['source'], 'EPISODE_CHANGED')
            if kind == 'ime_commit':
                basis = o.get('basis')
                need(type(basis) is list and 0 < len(basis) <= 1024, 'IME_BASIS')
                need(all(type(b) is int for b in basis) and len(set(basis)) == len(basis), 'IME_BASIS')
                for b in basis:
                    num(b, 0, i-1)
                    need(items[b]['kind'] in ('press','touch_down') and begin['t'] <= items[b]['t'] <= t and begin['seq'] < items[b]['seq'] < o['seq'], 'IME_MOTOR_BASIS')
                    need(items[b]['source'] == o['source'] and items[b]['profile'] == o['profile'], 'IME_MOTOR_SOURCE')
        elif kind == 'repeat':
            need(focused and not suspended, 'INPUT_OUTSIDE_OBSERVATION')
            need(('press',token) in active and o['profile']=='keyboard', 'REPEAT_WITHOUT_PRESS')
            need(active[('press',token)]['source']==o['source'], 'EPISODE_CHANGED')
        elif kind in UPDATES:
            need(focused and not suspended, 'INPUT_OUTSIDE_OBSERVATION')
            key = (UPDATES[kind], token); need(key in active, 'UPDATE_WITHOUT_START')
            need(active[key]['source'] == o['source'] and active[key]['profile'] == o['profile'], 'EPISODE_CHANGED')
        need('basis' not in o or kind == 'ime_commit', 'UNEXPECTED_BASIS')
        need(('effect' in o) == (kind == 'delivery'), 'DELIVERY_FIELDS')
        if kind == 'delivery': need(type(o['effect']) is dict, 'DELIVERY_EFFECT')
    need(not active, 'UNCLOSED_INPUT')
    return items, gap


def replay(bundle: dict) -> Corpus:
    shape(bundle, {'version','documents','target'})
    need(bundle['version'] == 'hwp-a/v0', 'VERSION')
    need(type(bundle['documents']) is list and 0 < len(bundle['documents']) <= MAX_DOCS, 'DOCUMENT_LIMIT')
    c = Corpus()
    for doc in bundle['documents']:
        replay_document(doc, c)
    need(type(bundle['target']) is str and bundle['target'] in c.documents, 'TARGET')
    return c


def replay_document(d: dict, c: Corpus) -> None:
    shape(d, {'id','language','resolution_us','paths','observations','transactions','final_text'})
    did = string(d['id'], 64); need(did and ':' not in did and '/' not in did and did not in c.documents, 'DOCUMENT_ID')
    language = string(d['language'], 40); need(bool(language) and not any(x in language for x in '|/\\'), 'LANGUAGE_DOMAIN')
    paths = d['paths']
    need(type(paths) is dict and bool(paths) and paths.keys() <= PROFILES.keys(), 'INPUT_PATHS')
    for value in paths.values(): need(bool(string(value,128)) and '|' not in value, 'INPUT_PATH_ID')
    res = num(d['resolution_us'], 1, 10_000)
    obs, gap = parse_observations(d['observations'], res)
    txs = d['transactions']; need(type(txs) is list and len(txs) <= MAX_EVENTS, 'TRANSACTION_LIMIT')
    timeline = sorted(obs + txs, key=lambda e: num(e.get('seq')))
    need([e['seq'] for e in timeline] == list(range(len(timeline))), 'GLOBAL_SEQUENCE')
    need(all(a['t'] <= b['t'] for a,b in zip(timeline,timeline[1:])), 'GLOBAL_CLOCK')
    need(all(a['seq'] < b['seq'] for a,b in zip(obs,obs[1:])) and all(a['seq'] < b['seq'] for a,b in zip(txs,txs[1:])), 'STREAM_ORDER')
    need(all(o['profile'] in paths for o in obs), 'UNDECLARED_INPUT_PATH')
    prefix_barriers = []; count = 0
    for o in obs:
        count += o['kind'] in ('focus_out','suspend','gap')
        prefix_barriers.append(count)
    live, effects, undo, redo = [], [], [], []
    unsafe_control = False
    runs, consumed = {}, set()
    last_time, last_pos, run_n, cursor, pending_nav = 0, 0, 0, 0, 0
    last_profile, last_source = None, None
    focused, suspended, pending_barrier = True, False, False
    common = {'i','t','seq','op','profile','causes','delivery'}
    fields = {'splice': {'start','end','text','deleted','source'}, 'copy': {'from_doc','start','end','to'},
              'move': {'start','end','to'}, 'undo': {'ref'}, 'redo': {'ref'}, 'navigate': {'start','end'}}
    for i, tx in enumerate(txs):
        need(type(tx) is dict and type(tx.get('op')) is str and tx['op'] in fields, 'OPERATION')
        op = tx['op']; shape(tx, common | fields[op])
        need(num(tx['i']) == i, 'TRANSACTION_SEQUENCE')
        t = num(tx['t']); need(t >= last_time and t % res == 0, 'TRANSACTION_CLOCK')
        profile = tx['profile']; need(type(profile) is str and profile in PROFILES, 'PROFILE')
        while cursor < len(obs) and obs[cursor]['seq'] < tx['seq']:
            o = obs[cursor]; k = o['kind']
            if k in ('focus_out','suspend','gap'): pending_barrier = True
            if k == 'focus_out': focused = False
            if k == 'focus_in': focused = True
            if k == 'suspend': suspended = True
            if k == 'resume': suspended = False
            cursor += 1
        delivery = num(tx['delivery'],0,len(obs)-1)
        delivered = obs[delivery]
        need(delivered['kind']=='delivery' and delivered['seq'] < tx['seq'] and delivery not in consumed, 'DELIVERY_BINDING')
        need(delivered['profile']==profile and 0 <= t-delivered['t'] <= MAX_CAUSE_DELAY, 'DELIVERY_DELAY_OR_PROFILE')
        effect_contract = {k:v for k,v in tx.items() if k not in ('i','t','seq','delivery')}
        need(json.dumps(delivered['effect'],sort_keys=True,ensure_ascii=True,allow_nan=False) == json.dumps(effect_contract,sort_keys=True,ensure_ascii=True,allow_nan=False), 'DELIVERY_EFFECT_MISMATCH')
        consumed.add(delivery)
        causes = tx['causes']
        need(type(causes) is list and 0 < len(causes) <= 1024 and all(type(n) is int for n in causes), 'CAUSES')
        need(len(set(causes)) == len(causes), 'CAUSE_REUSE')
        for n in causes:
            num(n, 0, len(obs)-1)
            o = obs[n]
            need(o['seq'] < delivered['seq'] and o['t'] <= t and n not in consumed, 'CAUSE_REUSE_OR_FUTURE')
            need(o['profile'] == profile and o['kind'] in ('press','repeat','touch_down','ime_commit','gesture_end','command'), 'CAUSE_PROFILE')
            consumed.add(n)
            for b in o.get('basis', []):
                need(b not in consumed, 'IME_DOUBLE_SPEND'); consumed.add(b)
        need(focused and not suspended, 'TRANSACTION_OUTSIDE_OBSERVATION')
        need(all(0 <= t-obs[n]['t'] <= MAX_CAUSE_DELAY for n in causes), 'DELAYED_INPUT_BINDING')
        need(all(prefix_barriers[n] == prefix_barriers[delivery] for n in causes), 'CAUSE_CROSSES_INTERRUPTION')
        if op in ('copy','move','undo','redo','navigate') and (delivered['source']!='device' or any(obs[n]['source']!='device' for n in causes)):
            unsafe_control = True
        source = tx.get('source','control')
        need(source in (('direct','paste','generated','unknown','spelling') if op=='splice' else ('control',)), 'TEXT_SOURCE')
        before_len = len(live)
        start = num(tx['start'], 0, len(live)) if op in ('splice','move','navigate') else min(last_pos, len(live))
        end = num(tx['end'], start, len(live)) if op in ('splice','move','navigate') else start
        barrier = pending_barrier or t-last_time > RUN_GAP or profile != last_profile or abs(start-last_pos) > 256
        barrier |= source not in ('direct','spelling','control') or last_source not in (None,'direct','spelling','control')
        if barrier: run_n += 1
        run = f'{did}:run:{run_n}'; runs.setdefault(run, [])
        old = new = ''; born, touched, ages = [], set(), []
        preceding_char = c.atoms[live[start-1]].char if start else '\n'
        preceding = 3 if preceding_char in '\n\r\u2028\u2029' else 2 if preceding_char in '.!?。！？' else 1 if preceding_char in SPACE else 0
        delta = None
        if op == 'navigate':
            pending_nav += abs(start-last_pos); last_pos = start
        elif op == 'splice':
            old, new = string(tx['deleted']), string(tx['text'])
            removed = live[start:end]
            if removed and (delivered['source']!='device' or any(obs[n]['source']!='device' for n in causes)):
                unsafe_control = True
            need(c.text(removed) == old and bool(old or new), 'MUTATION_PRESTATE')
            for a in removed: touched.update(c.atoms[a].roots)
            candidate = source == 'direct'
            if candidate:
                need(all(prefix_barriers[n] == prefix_barriers[delivery] for n in causes), 'CAUSE_CROSSES_INTERRUPTION')
                need(focused and not suspended, 'MUTATION_OUTSIDE_OBSERVATION')
                need(all(t-obs[n]['t'] <= MAX_CAUSE_DELAY for n in causes), 'DELAYED_INPUT_BINDING')
                need(all(obs[n]['kind'] in (('press','repeat') if profile=='keyboard' else (PROFILES[profile][0],)) for n in causes), 'DIRECT_CAUSE')
                need(len(new) <= PROFILES[profile][1] * len(causes), 'BULK_DIRECT_INSERTION')
                if delivered['source'] != 'device' or any(obs[n]['source'] != 'device' for n in causes):
                    candidate = False; source = 'unknown'
            # Assisted spelling does not establish human composition of new wording.
            # The complete replaced span is unsupported; no edit-distance exemption.
            need(len(live)-(end-start)+len(new) <= MAX_SCALARS and len(c.atoms)+len(new) <= MAX_ATOMS, 'REPLAY_RESOURCE_LIMIT')
            inserted = []
            requirements = frozenset({did}.union(*(c.atoms[a].requirements for a in removed)))
            for j, ch in enumerate(new):
                aid = f'{did}:{i}:{j}'; need(aid not in c.atoms, 'ATOM_COLLISION')
                if candidate:
                    a = Atom(aid,ch,frozenset({aid}),'candidate',did,i,run,profile,frozenset({did}))
                    born.append(aid); runs[run].append(aid)
                else:
                    a = Atom(aid,ch,frozenset(),'external',did,i,run,profile,frozenset({did}))
                c.atoms[aid] = a; inserted.append(aid)
            if source != 'direct' and new:
                c.external_scalars += len(new); need(c.external_scalars <= MAX_EXTERNAL_SCALARS, 'SOURCE_INDEX_LIMIT')
                c.external.append((did,i,new))
            live[start:end] = inserted; delta = (start, removed, inserted, i)
            touched.update(born); last_pos = start+len(new)
        elif op == 'copy':
            parent = tx['from_doc']; need(type(parent) is str and (parent == did or parent in c.documents), 'PARENT_UNAVAILABLE')
            source_live = live if parent == did else c.documents[parent].live
            s = num(tx['start'], 0, len(source_live)); e = num(tx['end'], s+1, len(source_live))
            to = num(tx['to'], 0, len(live)); start = to
            need(len(live)+e-s <= MAX_SCALARS and len(c.atoms)+e-s <= MAX_ATOMS, 'REPLAY_RESOURCE_LIMIT')
            originals = list(source_live[s:e]); inserted = []
            for j, original in enumerate(originals):
                a = c.atoms[original]; aid = f'{did}:{i}:{j}'; need(aid not in c.atoms, 'ATOM_COLLISION')
                c.atoms[aid] = Atom(aid,a.char,a.roots,a.kind,a.home,a.birth,a.run,a.profile,a.requirements | {did},a.spelling)
                inserted.append(aid); touched.update(a.roots)
            live[to:to] = inserted; new = c.text(inserted); delta = (to, [], inserted, i); last_pos = to+len(inserted)
        elif op == 'move':
            need(start < end, 'EMPTY_MOVE')
            to = num(tx['to'], 0, len(live)-(end-start)) # destination after removal
            lo, hi = min(start,to), max(end,to+end-start)
            old_ids = list(live[lo:hi]); moved = list(live[start:end]); del live[start:end]; live[to:to] = moved
            delta = (lo, old_ids, list(live[lo:hi]), i)
            for a in moved: touched.update(c.atoms[a].roots)
            old = new = c.text(moved); last_pos = to+len(moved)
        else:
            stack, other = (undo,redo) if op == 'undo' else (redo,undo)
            ref = num(tx['ref'],0,i-1); need(bool(stack) and stack[-1][3] == ref, 'HISTORY_TARGET')
            pos, pre, post, original = stack.pop()
            expected, restore = (post,pre) if op == 'undo' else (pre,post)
            need(live[pos:pos+len(expected)] == expected, 'HISTORY_PRESTATE')
            live[pos:pos+len(expected)] = restore; other.append((pos,pre,post,original))
            start = pos; old = c.text(expected); new = c.text(restore)
            for a in set(pre) | set(post): touched.update(c.atoms[a].roots)
            last_pos = pos+len(restore)
        if delta is not None:
            undo.append(delta); redo.clear(); c.stored_ids += len(delta[1])+len(delta[2])
        need(len(live) <= MAX_SCALARS and len(c.atoms) <= MAX_ATOMS and c.stored_ids <= MAX_IDS_STORED, 'REPLAY_RESOURCE_LIMIT')
        ages = [i-c.atoms[r].birth for r in touched if c.atoms[r].home == did]
        effect = Effect(i,t,op,source,profile,run,start,before_len,old,new,tuple(born),frozenset(touched),tuple(causes),preceding,pending_nav,tuple(ages),barrier)
        effects.append(effect)
        c.effect_edges += len(touched); need(c.effect_edges <= MAX_EFFECT_EDGES, 'EVIDENCE_EDGE_LIMIT')
        for r in touched:
            c.root_effects.setdefault(r,[]).append((did,i))
        last_time, last_profile, last_source = t, profile, source
        if op != 'navigate': pending_nav = 0
        pending_barrier = False
    # Fresh atom IDs and stack-checked operations preserve uniqueness inductively.
    # Check the final invariant without quadratic rescans during ordinary typing.
    need(len(live) == len(set(live)), 'DUPLICATE_LIVE_ID')
    final = string(d['final_text']); need(c.text(live) == final, 'FINAL_TEXT_MISMATCH')
    need(all(o['i'] in consumed for o in obs if o['kind']=='delivery'), 'UNACCOUNTED_DELIVERY')
    starts, durations = {}, {}
    for o in obs:
        if o['kind'] in ('press','touch_down','gesture_start'): starts[(o['kind'],o['token'])] = o
        if o['kind'] in ('release','touch_up','gesture_end'):
            begin = starts[({'release':'press','touch_up':'touch_down','gesture_end':'gesture_start'}[o['kind']],o['token'])]
            durations[begin['i']] = o['t']-begin['t']
            if o['kind']=='gesture_end': durations[o['i']] = o['t']-begin['t']
    c.documents[did] = Document(did,language,res,obs,effects,live,final,gap,runs,dict(paths),durations,unsafe_control)

@dataclass(frozen=True)
class Unit:
    uid: str
    doc: str
    view: str
    roots: tuple[str,...]
    profile: str
    language: str


def windows(items: list[str], width: int, stride: int) -> list[tuple[str,...]]:
    if not items: return []
    if len(items) <= width: return [tuple(items)]
    starts = set(range(0,len(items)-width+1,stride)); starts.add(len(items)-width)
    return [tuple(items[s:s+width]) for s in sorted(starts)]


def make_units(c: Corpus, did: str) -> tuple[list[Unit],dict[str,list[str]]]:
    d = c.documents[did]; out, members = [], {}
    def add(view: str, group: str, rr: list[str]):
        for width,stride in WINDOWS:
            for n,w in enumerate(windows(rr,width,stride)):
                u = Unit(f'{did}/{view}/{group}/{width}/{n}',did,view,w,c.atoms[w[0]].profile,d.language)
                out.append(u)
                for r in w: members.setdefault(r,[]).append(u.uid)
    for run,rr in d.runs.items(): add('birth',run,rr)
    # Retention is defined from the home version, never from a requested scope.
    groups, buf, seen_roots, run = [], [], set(), None
    def flush():
        nonlocal buf,seen_roots
        if buf: groups.append(list(buf))
        buf=[]; seen_roots=set()
    for aid in d.live:
        a=c.atoms[aid]
        if not a.roots or any(c.atoms[r].home!=did for r in a.roots): flush(); run=None; continue
        root_runs={c.atoms[r].run for r in a.roots}
        if len(root_runs)!=1: flush(); run=None; continue
        arun=next(iter(root_runs))
        if arun!=run: flush(); run=arun
        for r in sorted(a.roots,key=lambda r:(c.atoms[r].birth,int(r.rsplit(':',1)[1]))):
            if r not in seen_roots: buf.append(r); seen_roots.add(r)
    flush()
    seen=set()
    for i,rr in enumerate(groups):
        key=tuple(rr)
        if key not in seen:
            add('layout',str(i),rr)
            add('retained',str(i),sorted(rr,key=lambda r:(c.atoms[r].birth,int(r.rsplit(':',1)[1]))))
            seen.add(key)
    # Omnibus process check: one final-origin set per input profile, across runs.
    by_profile={}
    for aid in d.live:
        for r in c.atoms[aid].roots:
            if c.atoms[r].home==did: by_profile.setdefault(c.atoms[r].profile,set()).add(r)
    for profile,rr in sorted(by_profile.items()):
        ordered=tuple(sorted(rr,key=lambda r:(c.atoms[r].birth,int(r.rsplit(':',1)[1]))))
        if ordered:
            u=Unit(f'{did}/global/{profile}',did,'global',ordered,profile,d.language)
            out.append(u)
            for r in ordered: members.setdefault(r,[]).append(u.uid)

    return out,members


def related(c: Corpus, u: Unit) -> list[Effect]:
    c.analysis_edges += sum(len(c.root_effects.get(r,[])) for r in u.roots)
    need(c.analysis_edges <= 50_000_000, 'ANALYSIS_WORK_LIMIT')
    ii = {i for r in u.roots for did,i in c.root_effects.get(r,[]) if did == u.doc}
    return [c.documents[u.doc].effects[i] for i in sorted(ii) if c.documents[u.doc].effects[i].op not in ('copy','navigate')]


def observed_source_matches(c: Corpus, did: str) -> set[str]:
    """Earlier same-record source exposure only; bundle order is not evidence of reading."""
    first = {}
    for owner, tx, text in c.external:
        if owner != did: continue
        for i in range(max(0,len(text)-31)):
            shingle = text[i:i+32]
            first[shingle] = min(first.get(shingle,tx),tx)
    need(len(first) <= MAX_EXTERNAL_SCALARS, 'SOURCE_INDEX_LIMIT')
    d = c.documents[did]; blocked = set()
    for i in range(max(0,len(d.text)-31)):
        exposed_at = first.get(d.text[i:i+32])
        if exposed_at is None: continue
        atoms = [c.atoms[a] for a in d.live[i:i+32]]
        if all(a.roots and all(c.atoms[r].home==did and c.atoms[r].birth>exposed_at for r in a.roots) for a in atoms):
            blocked.update(d.live[i:i+32])
    return blocked
