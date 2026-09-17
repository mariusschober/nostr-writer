#!/usr/bin/env python3
# Test-only tooling. Runs the frozen hwp0.algorithm.replay module and records
# canonical-CBOR bundles plus canonical-CBOR normalized replay output, so the
# Swift test can replay natively and compare exact bytes.
#
#   HWP_PROTOCOL_ROOT=<repo>/protocol/v0 PYTHONDONTWRITEBYTECODE=1 \
#     <repo>/.venv-hwp/bin/python generate-replay-fixtures.py
#
# Every fixture here is synthetic. None is evidence of a real human writing
# process, capture authentication, admission, or publication.
from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROTOCOL_ROOT = Path(
    os.environ.get("HWP_PROTOCOL_ROOT", str(HERE.parents[3] / "protocol/v0"))
)
sys.dont_write_bytecode = True
subprocess.run([sys.executable, str(PROTOCOL_ROOT / "tools/check_freeze.py")], check=True)
sys.path.insert(0, str(PROTOCOL_ROOT))

from hwp0.core import encode, decode  # noqa: E402
from hwp0.algorithm.replay import (  # noqa: E402
    InvalidTrace,
    Unit,
    edit_distance,
    make_units,
    observed_source_matches,
    related,
    replay,
    scalar_range,
    windows,
)
from hwp0.algorithm.fixtures import Builder, TEXT  # noqa: E402


def ntext(value):
    return [ord(character) for character in value]


def atom_entry(atom):
    return {
        "char": ntext(atom.char),
        "roots": sorted(atom.roots),
        "kind": atom.kind,
        "home": atom.home,
        "birth": atom.birth,
        "run": atom.run,
        "profile": atom.profile,
        "requirements": sorted(atom.requirements),
        "spelling": atom.spelling,
    }


def effect_entry(effect):
    return {
        "index": effect.index,
        "time": effect.time,
        "op": effect.op,
        "source": effect.source,
        "profile": effect.profile,
        "run": effect.run,
        "pos": effect.pos,
        "before_length": effect.before_length,
        "old": ntext(effect.old),
        "new": ntext(effect.new),
        "born": list(effect.born),
        "touched": sorted(effect.touched),
        "causes": list(effect.causes),
        "preceding": effect.preceding,
        "navigation": effect.navigation,
        "ages": sorted(effect.ages),
        "barrier": effect.barrier,
    }


def observation_entry(observation):
    out = {
        "i": observation["i"],
        "t": observation["t"],
        "seq": observation["seq"],
        "kind": observation["kind"],
        "token": observation["token"],
        "source": observation["source"],
        "profile": observation["profile"],
    }
    if "basis" in observation:
        out["basis"] = list(observation["basis"])
    if "effect" in observation:
        out["effect"] = copy.deepcopy(observation["effect"])
    return out


def document_entry(document):
    return {
        "did": document.did,
        "language": document.language,
        "resolution": document.resolution,
        "observations": [observation_entry(o) for o in document.observations],
        "effects": [effect_entry(e) for e in document.effects],
        "live": list(document.live),
        "text": ntext(document.text),
        "gap": document.gap,
        "runs": [[run, list(members)] for run, members in document.runs.items()],
        "paths": [[profile, path] for profile, path in document.paths.items()],
        "durations": [[index, value] for index, value in document.durations.items()],
        "unsafe_control": document.unsafe_control,
    }


def normalize(bundle):
    corpus = replay(bundle)
    documents = [document_entry(corpus.documents[did]) for did in corpus.documents]
    atoms = [[aid, atom_entry(corpus.atoms[aid])] for aid in sorted(corpus.atoms)]
    external = [[owner, tx, text] for owner, tx, text in corpus.external]

    unit_objects = []
    unit_entries = []
    members = {}
    for did in corpus.documents:
        units, member_map = make_units(corpus, did)
        for unit in units:
            unit_objects.append(unit)
            unit_entries.append(
                {
                    "uid": unit.uid,
                    "doc": unit.doc,
                    "view": unit.view,
                    "roots": list(unit.roots),
                    "profile": unit.profile,
                    "language": unit.language,
                }
            )
        for root, uids in member_map.items():
            members.setdefault(root, []).extend(uids)

    related_entries = []
    for unit in unit_objects:
        effects = related(corpus, unit)
        related_entries.append(
            {
                "uid": unit.uid,
                "analysis_edges": corpus.analysis_edges,
                "indices": [effect.index for effect in effects],
            }
        )

    blocked = [[did, sorted(observed_source_matches(corpus, did))] for did in corpus.documents]

    return {
        "version": "hwp-a-replay-normalized/1",
        "documents": documents,
        "atoms": atoms,
        "external": external,
        "counters": {
            "external_scalars": corpus.external_scalars,
            "effect_edges": corpus.effect_edges,
            "analysis_edges": corpus.analysis_edges,
            "stored_ids": corpus.stored_ids,
        },
        "units": unit_entries,
        "members": [[root, members[root]] for root in sorted(members)],
        "related": related_entries,
        "observed_source_matches": blocked,
    }


def transaction_of(bundle, index=0, document=0):
    return bundle["documents"][document]["transactions"][index]


def document_of(bundle, document=0):
    return bundle["documents"][document]


def sync_delivery(bundle, index=0, document=0):
    """Re-derive a synthetic delivery effect from its transaction."""
    doc = document_of(bundle, document)
    transaction = doc["transactions"][index]
    doc["observations"][transaction["delivery"]]["effect"] = {
        key: value
        for key, value in transaction.items()
        if key not in ("i", "t", "seq", "delivery")
    }


def find_observation(bundle, kind, document=0):
    for observation in bundle["documents"][document]["observations"]:
        if observation["kind"] == kind:
            return observation["i"]
    raise LookupError(kind)


def append_observation(bundle, document, **fields):
    observations = bundle["documents"][document]["observations"]
    observation = {
        "i": len(observations),
        "t": 0,
        "seq": 0,
        "kind": "report",
        "token": "token",
        "source": "device",
        "profile": "keyboard",
    }
    observation.update(fields)
    observations.append(observation)
    return observation


def renumber_observations(bundle, document=0):
    """Frozen `i` must equal list position, so renumber after structural edits."""
    for index, observation in enumerate(bundle["documents"][document]["observations"]):
        observation["i"] = index


def valid_cases():
    cases = []
    cases.append(("keyboard-direct", Builder().type("The writer revises a claim. ").bundle()))
    cases.append(("keyboard-long-text", Builder().type(TEXT).bundle()))
    cases.append(("touch-tap", Builder(profile="touch-tap").type("tap the screen").bundle()))
    cases.append(("ime", Builder(profile="ime").type("日本語テキスト ime basis").bundle()))
    cases.append(("gesture", Builder(profile="gesture").type("gesture composed text").bundle()))

    imported = Builder().splice(0, 0, "imported fragment ", "paste").type("typed after import")
    cases.append(("import-paste", imported.bundle()))

    spelling = Builder().type(TEXT)
    spelling.splice(TEXT.index("writer"), TEXT.index("writer") + 6, "writex", "spelling")
    cases.append(("spelling-replacement", spelling.bundle()))

    copied = Builder().type("abcdef").control("copy", from_doc="d", start=0, end=6, to=6)
    copied.control("undo").control("redo")
    cases.append(("copy-undo-redo", copied.bundle()))

    moved = Builder().type("abcdefgh").control("move", start=1, end=3, to=4)
    moved.control("undo").control("redo")
    cases.append(("move-undo-redo", moved.bundle()))

    parent = Builder("a").type(TEXT).record()
    child = Builder("d").control(
        "copy", from_doc="a", start=0, end=len(TEXT), to=0, parent_text=TEXT
    )
    cases.append(("copy-cross-document", child.bundle([parent])))

    cases.append(("gap-and-pause", Builder().type("ab").gap().pause().type("cd").bundle()))
    cases.append(("navigate", Builder().type("abcd").control("navigate", start=0, end=2).bundle()))

    unicode_builder = Builder().type("é e\u0301 文 👩\u200d🔬\r\n")
    unicode_builder.control("copy", from_doc="d", start=0, end=1, to=len(unicode_builder.text))
    cases.append(("unicode-exact", unicode_builder.bundle()))

    cases.append(("empty-document", Builder().type("").bundle()))

    veto = Builder().splice(0, 0, TEXT, "paste").splice(0, len(TEXT), "").type(TEXT)
    cases.append(("observed-source-veto", veto.bundle()))

    later = Builder().type(TEXT).splice(len(TEXT), len(TEXT), TEXT, "paste").control("undo")
    cases.append(("source-after-creation", later.bundle()))

    external = (
        Builder()
        .splice(0, 0, "imported", "paste")
        .control("copy", from_doc="d", start=0, end=8, to=8)
        .control("undo")
        .control("redo")
    )
    cases.append(("external-survives-history", external.bundle()))

    nfc = Builder("é").type("nfc copy").record()
    nfd = Builder("e\u0301").type("nfd copy").record()
    cases.append(
        (
            "unicode-normalization-identity",
            {"version": "hwp-a/v0", "documents": [nfc, nfd], "target": "e\u0301"},
        )
    )

    kitchen = (
        Builder()
        .type("First sentence. Second clause.")
        .splice(0, 0, "cited ", "paste")
        .control("copy", from_doc="d", start=0, end=6,
                 to=len("cited First sentence. Second clause."))
        .control("move", start=0, end=5, to=6)
        .control("undo")
        .control("redo")
        .control("navigate", start=0, end=1)
    )
    cases.append(("combined-operations", kitchen.bundle()))
    return cases


def reject_cases():
    cases = []

    def add(name, bundle, reason):
        cases.append((name, bundle, reason))

    bundle = Builder().type("a").bundle()
    document_of(bundle)["observations"][1]["seq"] = 0
    add("reject-global-sequence", bundle, "GLOBAL_SEQUENCE")

    bundle = Builder().type("a").bundle()
    document_of(bundle)["observations"][1]["i"] = 0
    add("reject-observation-sequence", bundle, "OBSERVATION_SEQUENCE")

    bundle = Builder().type("ab").bundle()
    transaction_of(bundle, 1)["i"] = 0
    add("reject-transaction-sequence", bundle, "TRANSACTION_SEQUENCE")

    bundle = Builder().type("a").bundle()
    bundle["version"] = "hwp-a/0.2"
    add("reject-version", bundle, "VERSION")

    add("reject-document-limit", {"version": "hwp-a/v0", "documents": [], "target": "d"},
        "DOCUMENT_LIMIT")

    bundle = Builder().type("a").bundle()
    bundle["target"] = "missing"
    add("reject-target-missing", bundle, "TARGET")

    bundle = Builder().type("a").bundle()
    document_of(bundle)["id"] = "d:1"
    add("reject-document-id-delimiter", bundle, "DOCUMENT_ID")

    bundle = Builder().type("a").bundle()
    document_of(bundle)["language"] = "en|birth"
    add("reject-language-delimiter", bundle, "LANGUAGE_DOMAIN")

    bundle = Builder().type("a").bundle()
    document_of(bundle)["paths"] = {}
    add("reject-path-empty", bundle, "INPUT_PATHS")

    bundle = Builder().type("ab").bundle()
    document_of(bundle)["paths"] = {"ime": "fixture-path/ime"}
    add("reject-undeclared-path", bundle, "UNDECLARED_INPUT_PATH")

    bundle = Builder().type("a").bundle()
    document_of(bundle)["observations"][0]["extra"] = 1
    add("reject-object-fields", bundle, "OBJECT_FIELDS")

    bundle = Builder().type("a").bundle()
    document_of(bundle)["observations"][0]["token"] = "t" * 129
    add("reject-text-domain", bundle, "TEXT_DOMAIN")

    bundle = Builder().type("a").bundle()
    document_of(bundle)["observations"][0]["t"] = -1
    add("reject-integer-domain", bundle, "INTEGER_DOMAIN")

    bundle = Builder().type("ab").bundle()
    transaction_of(bundle)["t"] = 2**63 + 42
    add("reject-large-clock-before-small-clock", bundle, "GLOBAL_CLOCK")

    bundle = Builder().type("a").bundle()
    token = document_of(bundle)["observations"][0]["token"]
    append_observation(bundle, 0, t=400_000, kind="press", token=token)
    add("reject-token-reuse", bundle, "INPUT_TOKEN_REUSE")

    bundle = Builder().type("a").bundle()
    document = document_of(bundle)
    document["observations"] = [o for o in document["observations"] if o["kind"] != "release"]
    renumber_observations(bundle)
    add("reject-unclosed-input", bundle, "UNCLOSED_INPUT")

    bundle = Builder().type("a").bundle()
    append_observation(bundle, 0, t=300_000, kind="focus_out", token="f1")
    append_observation(bundle, 0, t=301_000, kind="focus_out", token="f2")
    add("reject-focus-state", bundle, "FOCUS_STATE")

    bundle = Builder().type("a").bundle()
    document = document_of(bundle)
    document["observations"] = [o for o in document["observations"] if o["kind"] != "press"]
    renumber_observations(bundle)
    add("reject-end-without-start", bundle, "END_WITHOUT_START")

    bundle = Builder(profile="ime").type("abc").bundle()
    next(o for o in document_of(bundle)["observations"] if o["kind"] == "ime_commit")["basis"] = []
    add("reject-ime-basis-empty", bundle, "IME_BASIS")

    bundle = Builder().type("ab").bundle()
    document = document_of(bundle)
    document["transactions"][1]["causes"] = document["transactions"][0]["causes"]
    sync_delivery(bundle, 1)
    add("reject-cause-already-consumed", bundle, "CAUSE_REUSE_OR_FUTURE")

    bundle = Builder().type("ab").bundle()
    transaction = transaction_of(bundle, 0)
    transaction["causes"] = transaction["causes"] * 2
    sync_delivery(bundle, 0)
    add("reject-cause-reuse", bundle, "CAUSE_REUSE")

    bundle = Builder(profile="ime").type("ab").bundle()
    transaction_of(bundle, 0)["causes"] = [find_observation(bundle, "ime_update")]
    sync_delivery(bundle, 0)
    add("reject-cause-profile", bundle, "CAUSE_PROFILE")

    # The navigate transaction's own command cause is reused as a direct splice
    # cause: admissible evidence, but not a direct keyboard cause.
    bundle = Builder().type("a").control("navigate", start=0, end=1).bundle()
    transaction = transaction_of(bundle, 1)
    transaction.update({"op": "splice", "start": 0, "end": 0, "text": "b", "deleted": "",
                        "source": "direct"})
    document_of(bundle)["final_text"] = "ba"
    sync_delivery(bundle, 1)
    add("reject-direct-cause", bundle, "DIRECT_CAUSE")

    bundle = Builder().type("a").bundle()
    document = document_of(bundle)
    transaction = document["transactions"][0]
    cause = document["observations"][transaction["causes"][0]]
    transaction["seq"], cause["seq"] = cause["seq"], transaction["seq"]
    add("reject-future-cause", bundle, "GLOBAL_SEQUENCE")

    bundle = Builder().type("a").bundle()
    transaction_of(bundle, 0)["delivery"] = 0
    add("reject-delivery-binding", bundle, "DELIVERY_BINDING")

    bundle = Builder().type("a").bundle()
    transaction_of(bundle, 0)["text"] = "b"
    document_of(bundle)["final_text"] = "b"
    add("reject-delivery-effect-mismatch", bundle, "DELIVERY_EFFECT_MISMATCH")

    bundle = Builder().type("a").bundle()
    document = document_of(bundle)
    document["observations"][document["transactions"][0]["delivery"]]["effect"]["start"] = False
    add("reject-delivery-bool", bundle, "DELIVERY_EFFECT_MISMATCH")

    bundle = Builder().type("a").bundle()
    document = document_of(bundle)
    transaction = document["transactions"][0]
    transaction["t"] = document["observations"][transaction["causes"][0]]["t"] + 400_000
    add("reject-delivery-delay", bundle, "DELIVERY_DELAY_OR_PROFILE")

    bundle = Builder().type("a").bundle()
    document = document_of(bundle)
    transaction = document["transactions"][0]
    cause_time = document["observations"][transaction["causes"][0]]["t"]
    transaction["t"] = cause_time + 400_000
    document["observations"][transaction["delivery"]]["t"] = transaction["t"] - 50_000
    for observation in document["observations"]:
        if observation["kind"] == "release":
            observation["t"] = transaction["t"]
    sync_delivery(bundle, 0)
    add("reject-delayed-input-binding", bundle, "DELAYED_INPUT_BINDING")

    bundle = Builder().type("a").bundle()
    document = document_of(bundle)
    transaction = document["transactions"][0]
    transaction["start"], transaction["end"], transaction["text"] = 0, 1, "b"
    document["final_text"] = "b"
    sync_delivery(bundle, 0)
    add("reject-mutation-prestate", bundle, "MUTATION_PRESTATE")

    bundle = Builder().type("ab").bundle()
    transaction_of(bundle, 1)["source"] = "control"
    sync_delivery(bundle, 1)
    add("reject-text-source", bundle, "TEXT_SOURCE")

    bundle = Builder().type("a").bundle()
    transaction_of(bundle, 0)["text"] = "abcdefghi"
    document_of(bundle)["final_text"] = "abcdefghi"
    sync_delivery(bundle, 0)
    add("reject-bulk-direct-insertion", bundle, "BULK_DIRECT_INSERTION")

    bundle = Builder().type("abc").bundle()
    transaction = transaction_of(bundle, 0)
    transaction.pop("text", None)
    transaction.pop("deleted", None)
    transaction.update({"op": "copy", "from_doc": "missing", "to": 0, "start": 0, "end": 1})
    sync_delivery(bundle, 0)
    add("reject-copy-parent-unavailable", bundle, "PARENT_UNAVAILABLE")

    bundle = Builder().type("abcdef").control("undo").bundle()
    transaction_of(bundle, 1)["ref"] = 5
    sync_delivery(bundle, 1)
    add("reject-history-target", bundle, "HISTORY_TARGET")

    bundle = Builder().type("abcdefgh").control("move", start=1, end=3, to=4).bundle()
    transaction = transaction_of(bundle, 1)
    transaction["start"], transaction["end"] = 2, 2
    sync_delivery(bundle, 1)
    add("reject-empty-move", bundle, "EMPTY_MOVE")

    bundle = Builder().type("ab").bundle()
    document = document_of(bundle)
    document["transactions"].pop()
    document["final_text"] = ""
    for index, event in enumerate(sorted(document["observations"], key=lambda o: o["seq"])):
        event["seq"] = index
    add("reject-unaccounted-delivery", bundle, "UNACCOUNTED_DELIVERY")

    bundle = Builder().type("a").bundle()
    document_of(bundle)["final_text"] = "b"
    add("reject-final-text-mismatch", bundle, "FINAL_TEXT_MISMATCH")

    builder = Builder()
    _, cause_time = builder.cause()
    builder.observation("focus_out", cause_time + 1_000, "out")
    builder.observation("focus_in", cause_time + 2_000, "in")
    builder.observations.sort(key=lambda observation: observation["t"])
    for index, observation in enumerate(builder.observations):
        observation["i"] = index
    builder.add("splice", 0, cause_time + 40_000, start=0, end=0, text="x", deleted="",
                source="direct")
    add("reject-cause-crosses-interruption", builder.bundle(), "CAUSE_CROSSES_INTERRUPTION")
    return cases


def helper_cases():
    scalar_entries = []
    probes = (
        ("abc", 0, 3),
        ("abc", 1, 4),
        ("abc", 2, 1),
        ("", 0, 0),
        ("\u00e9", 0, 2),
        ("\u00e9", 1, 2),
        ("a\U0001F600b", 0, 1),
        ("a\U0001F600b", 1, 5),
        ("a\U0001F600b", 5, 6),
    )
    for text, start, end in probes:
        entry = {"text": ntext(text), "start": start, "end": end}
        try:
            low, high = scalar_range(text, start, end)
            entry["result"] = [low, high]
        except InvalidTrace as error:
            entry["reject"] = str(error)
        scalar_entries.append(entry)

    window_entries = []
    for text, width, stride in (("", 4, 2), ("abcd", 4, 2), ("abcdef", 3, 2),
                                ("abcde", 2, 2), ("abcdefgh", 5, 3)):
        result = windows(list(text), width, stride)
        window_entries.append(
            {
                "items": ntext(text),
                "width": width,
                "stride": stride,
                "result": [[ord(character) for character in window] for window in result],
            }
        )
    tail = [str(index) for index in range(317)]
    window_entries.append(
        {
            "items": [ntext(item) for item in tail],
            "width": 64,
            "stride": 32,
            "result": [[ntext(item) for item in window] for window in windows(tail, 64, 32)],
        }
    )

    distance_entries = []
    for left, right in (("", ""), ("abc", "abc"), ("abc", "abd"), ("kitten", "sitting"),
                        ("\u00e9", "e\u0301"), ("x" * 33, "y")):
        entry = {"a": ntext(left), "b": ntext(right)}
        try:
            entry["result"] = edit_distance(left, right)
        except InvalidTrace as error:
            entry["reject"] = str(error)
        distance_entries.append(entry)

    return {"scalar_ranges": scalar_entries, "windows": window_entries,
            "edit_distances": distance_entries}


def main():
    replay_source = PROTOCOL_ROOT / "hwp0" / "algorithm" / "replay.py"
    digest = hashlib.sha256(replay_source.read_bytes()).hexdigest()

    cases = []
    for name, bundle in valid_cases():
        cases.append(
            {
                "name": name,
                "kind": "ok",
                "bundle_cbor": encode(bundle).hex(),
                "normalized_cbor": encode(normalize(decode(encode(bundle)))).hex(),
            }
        )
    for name, bundle, expectation in reject_cases():
        try:
            replay(bundle)
        except InvalidTrace as error:
            reason = str(error)
        else:
            raise SystemExit(f"{name}: expected {expectation}, replay accepted the bundle")
        # Several mutations violate more than one invariant. The untouched
        # reference determines the first rejection; the mutation name is intent.
        if reason != expectation:
            print(f"{name}: intended {expectation}, reference first rejects {reason}")
        cases.append(
            {"name": name, "kind": "reject", "bundle_cbor": encode(bundle).hex(),
             "reason": reason}
        )

    document = {
        "version": "hwp-a-replay-fixtures/1",
        "provenance": {
            "replay_sha256": digest,
            "replay_path": "hwp0/algorithm/replay.py",
            "note": "Synthetic differential fixtures from frozen Python. No human evidence.",
        },
        "cases": cases,
        "helpers_cbor": encode(helper_cases()).hex(),
    }
    output = HERE.parent / "Tests/WriterHWPTests/Fixtures/replay-oracle.json"
    output.write_text(json.dumps(document, ensure_ascii=True, separators=(",", ":"),
                                 sort_keys=True))
    print(f"wrote {output} ({output.stat().st_size} bytes, {len(cases)} cases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
