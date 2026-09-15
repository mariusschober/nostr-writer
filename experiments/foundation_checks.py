#!/usr/bin/env python3
"""Synthetic HWP foundation checks, not a detector or production verifier.

Run: python experiments/foundation_checks.py
Requires Python >=3.10 and cryptography. Writes deterministic vectors/results
beside this script. The published signing seed is FOR TESTS ONLY.
"""
from __future__ import annotations

import copy
import hashlib
import importlib.metadata
import json
import math
import platform
from pathlib import Path
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey, Ed25519PublicKey,
)
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

MAX_INT = 2**53 - 1


def sha256(data: bytes) -> bytes:
    return hashlib.sha256(data).digest()


def frame(label: str, *parts: bytes) -> bytes:
    tag = label.encode('ascii')
    return (b'HWP0' + len(tag).to_bytes(4, 'big') + tag
            + len(parts).to_bytes(4, 'big')
            + b''.join(len(p).to_bytes(8, 'big') + p for p in parts))


def canonical(value: Any) -> bytes:
    """RFC 8785-compatible restricted domain: ASCII keys, no float numbers."""
    def validate(x: Any) -> None:
        if x is None or type(x) is bool:
            return
        if type(x) is int:
            if abs(x) > MAX_INT:
                raise ValueError('integer outside interoperable domain')
            return
        if type(x) is str:
            x.encode('utf-8', errors='strict')  # Reject lone surrogates.
            return
        if type(x) is list:
            for item in x:
                validate(item)
            return
        if type(x) is dict:
            for key, item in x.items():
                if type(key) is not str or not key.isascii():
                    raise ValueError('object keys must be ASCII strings')
                validate(item)
            return
        raise ValueError('unsupported JSON type; floats are forbidden')
    validate(value)
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(',', ':'), allow_nan=False).encode('utf-8')


def parse_canonical(raw: bytes) -> Any:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate object key')
            result[key] = value
        return result
    obj = json.loads(raw.decode('utf-8'), object_pairs_hook=pairs)
    if canonical(obj) != raw:
        raise ValueError('noncanonical serialization')
    return obj


def leaf(session: str, index: int, event: dict[str, Any], salt: bytes) -> bytes:
    if len(salt) != 32 or not 0 <= index <= MAX_INT:
        raise ValueError('bad leaf parameters')
    payload = {'namespace': 'hwp-log-0', 'session': session, 'index': index,
               'salt': salt.hex(), 'event': event}
    return sha256(b'\x00' + canonical(payload))


def merkle(leaves: list[bytes]) -> bytes:
    """RFC 9162 tree shape; input elements are already hashed leaves."""
    if not leaves:
        return sha256(b'')
    if len(leaves) == 1:
        return leaves[0]
    split = 1 << ((len(leaves) - 1).bit_length() - 1)
    return sha256(b'\x01' + merkle(leaves[:split]) + merkle(leaves[split:]))


def byte_boundary(data: bytes, position: int) -> bool:
    if type(position) is not int or not 0 <= position <= len(data):
        return False
    try:
        data[:position].decode('utf-8')
        data[position:].decode('utf-8')
        return True
    except UnicodeDecodeError:
        return False


def replay(events: list[dict[str, Any]]) -> bytes:
    """Tiny synthetic replay subset. Does NOT implement the lineage spec."""
    data = b''
    for event in events:
        at = event['at']
        if not byte_boundary(data, at):
            raise ValueError('invalid edit boundary')
        if event['op'] == 'insert':
            data = data[:at] + event['text'].encode('utf-8') + data[at:]
        elif event['op'] == 'delete':
            end = event['end']
            if end <= at or not byte_boundary(data, end):
                raise ValueError('invalid deletion')
            data = data[:at] + data[end:]
        else:
            raise ValueError('unsupported operation')
    return data


def ranges_valid(data: bytes, ranges: list[dict[str, Any]]) -> bool:
    cursor = 0
    for item in ranges:
        if (item['start'] != cursor or item['end'] <= cursor
                or not byte_boundary(data, item['end'])
                or item['kind'] not in {'candidate', 'external', 'transformed', 'unknown'}):
            return False
        cursor = item['end']
    return cursor == len(data) and len(data) > 0


def sign(payload: dict[str, Any], key: Ed25519PrivateKey) -> dict[str, Any]:
    public = key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    protected = {'algorithm': 'Ed25519', 'protocol': 'hwp-0',
                 'role': 'research_fixture', 'public_key': public.hex()}
    message = frame('signature', canonical(protected), canonical(payload))
    return {'protected': protected, 'payload': payload,
            'signature': key.sign(message).hex()}


def signature_valid(envelope: dict[str, Any]) -> bool:
    try:
        p = envelope['protected']
        if (set(p) != {'algorithm', 'protocol', 'role', 'public_key'}
                or p['algorithm'] != 'Ed25519' or p['protocol'] != 'hwp-0'
                or p['role'] != 'research_fixture'):
            return False
        key = Ed25519PublicKey.from_public_bytes(bytes.fromhex(p['public_key']))
        key.verify(bytes.fromhex(envelope['signature']),
                   frame('signature', canonical(p), canonical(envelope['payload'])))
        return True
    except (ValueError, TypeError, KeyError, InvalidSignature):
        return False


def run() -> None:
    passed: list[str] = []

    def check(name: str, condition: bool) -> None:
        if not condition:
            raise AssertionError(name)
        passed.append(name)

    def rejects(name: str, action: Any) -> None:
        try:
            action()
        except (ValueError, UnicodeError):
            passed.append(name)
            return
        raise AssertionError(name)

    check('framing separates labels', frame('a', b'x') != frame('b', b'x'))
    check('framing separates argument boundaries',
          frame('x', b'ab', b'c') != frame('x', b'a', b'bc'))
    check('canonical object order is stable', canonical({'b': 1, 'a': 2}) == b'{"a":2,"b":1}')
    rejects('duplicate JSON key rejected', lambda: parse_canonical(b'{"a":1,"a":2}'))
    rejects('floating point JSON rejected', lambda: canonical({'a': 1.0}))
    rejects('oversized integer rejected', lambda: canonical({'a': 2**53}))
    rejects('lone Unicode surrogate rejected', lambda: canonical({'a': '\ud800'}))
    rejects('noncanonical whitespace rejected', lambda: parse_canonical(b'{ "a":1}'))
    check('no silent Unicode normalization', sha256('é'.encode()) != sha256('e\u0301'.encode()))
    check('line ending change changes exact digest', sha256(b'a\nb') != sha256(b'a\r\nb'))

    doc = b'Research fixture; not human-certified.\n'
    events = [{'op': 'insert', 'at': 0, 'text': 'draft'},
              {'op': 'delete', 'at': 0, 'end': 5},
              {'op': 'insert', 'at': 0, 'text': doc.decode()}]
    salts = [sha256(f'TEST-ONLY-salt-{i}'.encode()) for i in range(len(events))]
    sid = sha256(b'TEST-ONLY-session').hex()
    leaves = [leaf(sid, i, event, salts[i]) for i, event in enumerate(events)]
    root = merkle(leaves)
    check('synthetic replay produces exact document', replay(events) == doc)
    check('empty Merkle tree uses RFC empty hash', merkle([]) == sha256(b''))
    check('three-leaf tree has unambiguous shape',
          root == sha256(b'\x01' + sha256(b'\x01' + leaves[0] + leaves[1]) + leaves[2]))
    check('changing leaf order changes root', root != merkle([leaves[1], leaves[0], leaves[2]]))
    check('deleting a leaf changes root', root != merkle(leaves[:-1]))
    check('fresh salt changes commitment', leaves[0] != leaf(sid, 0, events[0], b'\xff' * 32))
    check('session identifier binds commitment', leaves[0] != leaf('another-session', 0, events[0], salts[0]))
    same_observations = copy.deepcopy(events)
    check('different alleged causes with identical observations have identical roots',
          root == merkle([leaf(sid, i, e, salts[i]) for i, e in enumerate(same_observations)]))
    ranges = [{'start': 0, 'end': len(doc), 'kind': 'candidate'}]
    check('complete range partition accepted mechanically', ranges_valid(doc, ranges))
    check('range gap rejected', not ranges_valid(doc, [{'start': 1, 'end': len(doc), 'kind': 'candidate'}]))
    check('range overlap rejected', not ranges_valid(doc, [ranges[0], ranges[0]]))
    check('UTF-8 split rejected', not ranges_valid('é'.encode(), [
        {'start': 0, 'end': 1, 'kind': 'candidate'}, {'start': 1, 'end': 2, 'kind': 'candidate'}]))
    check('empty scope cannot pass vacuously', not ranges_valid(b'', []))

    seed = bytes(range(32))  # Published fixture seed, never a real signing key.
    key = Ed25519PrivateKey.from_private_bytes(seed)
    payload = {'protocol': 'hwp-0', 'fixture_only': True,
               'computed_verdict': 'NOT PROVABLE', 'profile_id': 'research-only',
               'document': {'sha256': sha256(doc).hex(), 'byte_length': len(doc)},
               'log': {'session': sid, 'root': root.hex(), 'event_count': len(events)},
               'range_map_sha256': sha256(canonical(ranges)).hex()}
    envelope = sign(payload, key)
    check('Ed25519 signature verifies', signature_valid(envelope))
    altered = copy.deepcopy(envelope)
    altered['payload']['computed_verdict'] = 'HUMAN-WRITTEN'
    check('claim tampering invalidates signature', not signature_valid(altered))
    altered = copy.deepcopy(envelope)
    altered['protected']['algorithm'] = 'none'
    check('algorithm substitution rejected', not signature_valid(altered))
    altered = copy.deepcopy(envelope)
    altered['protected']['role'] = 'capture_verifier'
    check('signer role substitution rejected', not signature_valid(altered))
    altered = copy.deepcopy(envelope)
    altered['protected']['public_key'] = key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)[::-1].hex()
    check('public-key substitution rejected', not signature_valid(altered))
    check('valid signature does not validate altered document',
          signature_valid(envelope) and sha256(doc + b'!').hex() != payload['document']['sha256'])
    forged_claim = copy.deepcopy(payload)
    forged_claim['computed_verdict'] = 'HUMAN-WRITTEN'
    forged_claim['profile_id'] = 'self-declared-approved'
    forged_envelope = sign(forged_claim, key)
    externally_approved_profiles: frozenset[str] = frozenset()
    check('self-signed approval does not create externally approved policy',
          signature_valid(forged_envelope)
          and forged_claim['profile_id'] not in externally_approved_profiles)
    # This is a counterexample to ungrounded certification, not a trained detector.
    p, alpha = 0.001, 0.05
    counts = {str(target): math.ceil(math.log(alpha) / math.log1p(-target))
              for target in (0.01, 0.001, 0.0001)}
    n = counts['0.001']
    check('zero-failure sample bound meets target', 1 - alpha**(1/n) <= p)
    check('one fewer sample fails target bound', 1 - alpha**(1/(n-1)) > p)
    check('independent retry calculation', 0.632 < -math.expm1(1000 * math.log1p(-p)) < 0.633)

    vectors = {'status': 'SYNTHETIC TEST FIXTURES; NOT A HUMAN-WRITTEN CERTIFICATE',
               'test_private_seed_hex': seed.hex(), 'document_utf8': doc.decode(),
               'events': events, 'salts_hex': [s.hex() for s in salts],
               'leaf_hashes_hex': [v.hex() for v in leaves], 'ranges': ranges,
               'envelope': envelope, 'signature_message_hex': frame(
                   'signature', canonical(envelope['protected']), canonical(payload)).hex()}
    results = {'status': 'synthetic mechanics only; no human detector evaluated',
               'python': platform.python_version(),
               'cryptography': importlib.metadata.version('cryptography'),
               'checks_passed': len(passed), 'checks': passed,
               'zero_failure_trials_95pct_one_sided': counts,
               'zero_failure_upper_bound_at_2995': 1 - alpha**(1/2995),
               'twenty_family_bonferroni_trials_each_at_0_001':
                   math.ceil(math.log(alpha/20) / math.log1p(-p)),
               'independent_retry_success_p_0_001_q_1000':
                   -math.expm1(1000 * math.log1p(-p)),
               'approved_certification_profiles': [],
               'human_participant_sessions': 0,
               'trained_detectors': 0, 'zk_proofs_generated': 0,
               'hardware_capture_paths_tested': 0}
    here = Path(__file__).resolve().parent
    for filename, obj in [('vectors.json', vectors), ('results.json', results)]:
        (here / filename).write_text(json.dumps(obj, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    run()
