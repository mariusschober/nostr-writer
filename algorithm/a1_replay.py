"""Deterministic HWP-A1 replay and root/occurrence ancestry."""
from __future__ import annotations
from a1_types import *

def replay(trace: dict) -> Replay:
    exact_keys(trace, {"version", "session_id", "language", "mode", "quantum_us", "events", "document"})
    require(trace["version"] == VERSION, "VERSION")
    sid, language = text(trace["session_id"]), text(trace["language"])
    require(bool(sid) and bool(language), "IDENTIFIER")
    mode = trace["mode"]
    require(mode in MODES, "MODE")
    quantum = integer(trace["quantum_us"], 1, 20_000)
    require(type(trace["events"]) is list and len(trace["events"]) <= LIMITS["events"], "EVENT_LIMIT")
    final = text(trace["document"])
    live: list[Atom] = []
    roots: list[Root] = []
    mutations: list[Mutation] = []
    inputs: dict[int, dict] = {}
    releases: dict[int, int] = {}
    used: set[int] = set()
    # Each history entry is (forward splices, inverse splices, affected roots).
    # Splices contain only changed atoms, not an entire document snapshot.
    undo: list[tuple] = []
    redo: list[tuple] = []
    tprev, epoch, lane, caret = 0, 0, 0, 0
    focused = True
    pending: tuple[int, tuple[int, ...]] | None = None
    occurrence = 0

    def take(e: dict, want: str) -> tuple[int, ...]:
        cs = e["causes"]
        require(type(cs) is list and 1 <= len(cs) <= LIMITS["causes"], "CAUSE_COUNT")
        for c in cs:
            integer(c)
        require(cs == sorted(set(cs)), "CAUSE_ORDER")
        require(all(c in inputs and c not in used for c in cs), "CAUSE_REUSE_OR_UNKNOWN")
        require(all(inputs[c]["epoch"] == epoch and inputs[c]["mode"] == mode for c in cs), "CAUSE_EPOCH")
        require(all(inputs[c]["intent"] in (("text", "preedit") if want == "text" else (want,)) for c in cs), "CAUSE_INTENT")
        used.update(cs)
        return tuple(cs)

    for seq, e in enumerate(trace["events"]):
        require(type(e) is dict and "seq" in e and "t_us" in e and "op" in e, "EVENT_SCHEMA")
        require(integer(e["seq"]) == seq, "SEQUENCE")
        now = integer(e["t_us"])
        require(now >= tprev and now % quantum == 0, "CLOCK")
        tprev = now
        op = e["op"]
        common = {"seq", "t_us", "op"}
        if op == "input":
            exact_keys(e, common | {"intent", "text", "source"})
            require(focused, "INPUT_WITHOUT_FOCUS")
            require(e["intent"] in ("text", "preedit", "delete", "select", "copy", "move", "undo", "redo"), "INTENT")
            require(e["source"] in SOURCES, "SOURCE")
            payload = text(e["text"])
            require(e["intent"] in ("text", "preedit") or payload == "", "COMMAND_PAYLOAD")
            require(e["intent"] != "preedit" or mode == "ime", "PREEDIT_MODE")
            inputs[seq] = dict(e, mode=mode, epoch=epoch, ordinal=len(inputs))
            continue
        if op == "release":
            exact_keys(e, common | {"press"})
            p = integer(e["press"])
            require(p in inputs and p not in releases and inputs[p]["mode"] == "keyboard", "RELEASE")
            releases[p] = now
            continue
        if op == "focus":
            exact_keys(e, common | {"focused"})
            require(type(e["focused"]) is bool and e["focused"] != focused, "FOCUS")
            focused = e["focused"]
            epoch += 1; lane += 1; pending = None
            continue
        if op == "mode":
            exact_keys(e, common | {"mode"})
            require(e["mode"] in MODES and e["mode"] != mode, "MODE")
            mode = e["mode"]
            epoch += 1; lane += 1; pending = None
            continue
        if op == "gap":
            raise Invalid("CAPTURE_GAP")
        require(focused, "MUTATION_WITHOUT_FOCUS")
        forward, inverse = [], []
        size = len(live)
        before = after = ""
        created: set[int] = set()
        removed: set[int] = set()
        touched: set[int] = set()
        age = boundary = 0
        jump = 0
        if op == "select":
            exact_keys(e, common | {"at", "causes"})
            at = integer(e["at"], 0, size)
            cs = take(e, "select")
            if abs(at-caret) > 64:
                lane += 1
            pending = None
            continue
        if op == "edit":
            exact_keys(e, common | {"at", "end", "before", "text", "causes"})
            at = integer(e["at"], 0, size)
            end = integer(e["end"], at, size)
            before, after = text(e["before"]), text(e["text"])
            require(before == "".join(a.char for a in live[at:end]), "PRESTATE")
            require(before != after, "NOOP_EDIT")
            cs = take(e, "text" if after else "delete")
            commits = [inputs[c] for c in cs if inputs[c]["intent"] == "text"]
            if after:
                require("".join(c["text"] for c in commits) == after, "INPUT_TEXT_BINDING")
                require(bool(commits), "NO_COMMIT")
                if mode != "ime":
                    require(all(inputs[c]["intent"] == "text" for c in cs), "PREEDIT_MODE")
                else:
                    require(len(commits) == 1 and inputs[cs[-1]]["intent"] == "text", "IME_COMMIT")
            # Every text-producing action outside this transaction breaks a
            # claimed burst; action ordinals retain that information below.
            jump = abs(at-caret)
            if jump > 64:
                lane += 1; pending = None
            boundary = 2 if at == 0 or live[at-1].char in STOPS else 1 if live[at-1].char in WS else 0
            prior = live[at:end]
            keep = lcs_pairs(before, after)
            kept_old = set(keep.values())
            removed = {a.root for i, a in enumerate(prior) if i not in kept_old}
            parent_set = set(removed)
            if pending is not None and pending[0] == at:
                parent_set.update(pending[1])
            # An observed noncandidate transform never upgrades retained roots.
            source = next((s for s in ("unknown", "injected", "assisted", "external")
                           if any(inputs[c]["source"] == s for c in cs)), "candidate")
            # An IME commit without its observed preedit is never direct evidence.
            if mode == "ime" and after and not any(inputs[c]["intent"] == "preedit" for c in cs):
                source = "unknown"
            replacement = []
            for j, ch in enumerate(after):
                if j in keep:
                    replacement.append(prior[keep[j]])
                else:
                    r = len(roots)
                    roots.append(Root(ch, len(mutations), now, mode, epoch, lane, source, cs, tuple(sorted(parent_set))))
                    created.add(r)
                    replacement.append(Atom(ch, r, occurrence))
                    occurrence += 1
            forward = [(at, len(prior), replacement)]
            inverse = [(at, len(replacement), prior)]
            live[at:end] = replacement
            touched = created | removed
            if removed:
                age = max(now-roots[r].t for r in removed)
            if before and not after:
                pp = tuple(sorted(parent_set))
                pending = (at, pp)
            else:
                pending = None
            caret = at + len(after)
        elif op in ("copy", "move"):
            exact_keys(e, common | {"start", "end", "at", "causes"})
            start = integer(e["start"], 0, size)
            end = integer(e["end"], start+1, size)
            cs = take(e, op)
            fragment = live[start:end]
            if op == "move":
                del live[start:end]
            at = integer(e["at"], 0, len(live))
            if op == "copy":
                copies = []
                for atom in fragment:
                    copies.append(Atom(atom.char, atom.root, occurrence, atom.occurrence))
                    occurrence += 1
                fragment = copies
            if op == "move":
                forward = [(start, end-start, []), (at, 0, fragment)]
                inverse = [(at, len(fragment), []), (start, 0, fragment)]
            else:
                forward = [(at, 0, fragment)]
                inverse = [(at, len(fragment), [])]
            live[at:at] = fragment
            touched = {a.root for a in fragment}
            jump = abs(at-caret)
            caret = at+len(fragment); pending = None; lane += 1
        elif op in ("undo", "redo"):
            exact_keys(e, common | {"causes"})
            cs = take(e, op)
            src, dest = (undo, redo) if op == "undo" else (redo, undo)
            require(bool(src), "HISTORY_EMPTY")
            change = src.pop()
            dest.append(change)
            for pos, count, fragment in (change[1] if op == "undo" else change[0]):
                live[pos:pos+count] = fragment
            touched = set(change[2])
            at = 0
            caret = min(caret, len(live)); pending = None; lane += 1
        else:
            raise Invalid("UNKNOWN_OPERATION")
        if op not in ("undo", "redo"):
            undo.append((forward, inverse, tuple(sorted(touched)))); redo.clear()
        require(len(live) <= LIMITS["scalars"] and len(roots) <= LIMITS["events"], "STATE_LIMIT")
        mutations.append(Mutation(seq, now, op, touched, created, removed, at, size,
                                  jump, age, before, after, boundary, cs, epoch))
    require(all(c in used or i["intent"] not in ("text", "preedit") for c, i in inputs.items()), "UNCONSUMED_TEXT_INPUT")
    require(len({a.occurrence for a in live}) == len(live), "DUPLICATE_LIVE_OCCURRENCE")
    require("".join(a.char for a in live) == final, "FINAL_TEXT")
    return Replay(final, live, roots, mutations, inputs, releases, language, quantum, sid)

