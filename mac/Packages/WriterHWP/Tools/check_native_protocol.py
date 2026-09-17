#!/usr/bin/env python3
"""Offline CLI/interoperability checks using only immutable public synthetic data."""
from pathlib import Path
import argparse, hashlib, json, os, random, subprocess, sys, tempfile
sys.dont_write_bytecode = True
ap = argparse.ArgumentParser()
ap.add_argument('--binary', type=Path, required=True)
ap.add_argument('--native-sample', type=Path, required=True)
args = ap.parse_args()
root = Path(__file__).resolve().parents[4] / 'protocol/v0'
subprocess.run([sys.executable, str(root / 'tools/check_freeze.py')], check=True)
sys.path.insert(0, str(root))
from hwp0 import core, protocol, disclosure
vector = json.loads((root / 'vectors/interchange.json').read_bytes())
objects = {k: bytes.fromhex(v) for k, v in vector['objects'].items()}
assert all(hashlib.sha256(raw).hexdigest() == key for key, raw in objects.items())
binary = str(args.binary.resolve())
checks = []
def json_value(v):
    if isinstance(v, bytes): return v.hex()
    if isinstance(v, list): return [json_value(x) for x in v]
    if isinstance(v, dict): return {k: json_value(x) for k, x in v.items()}
    return v

def run(name, argv, expected=None, status=None, timeout=30):
    p = subprocess.run([binary, *map(str, argv)], capture_output=True, timeout=timeout)
    assert p.returncode in (0, 1, 2), (name, p.returncode, p.stderr.decode())
    actual = json.loads(p.stdout)
    desired = status or expected['status']
    assert actual['status'] == desired, (name, actual, desired)
    assert p.returncode == {'VALID-HWP': 0, 'TEST-ONLY': 2, 'NO-VALID-HWP': 1}[desired], name
    if expected and desired != 'NO-VALID-HWP': assert actual == json_value(expected), (name, actual, expected)
    if desired == 'NO-VALID-HWP':
        assert actual['outcome'] == 'NOT PROVABLE' and actual['authorship_inference'] is None, name
    checks.append({'name': name, 'status': 'PASS', 'exit': p.returncode})
    return actual

with tempfile.TemporaryDirectory(prefix='nostr-writer-cli-public-') as folder:
    temp = Path(folder)
    for row in vector['cases']:
        for field, filename in [('bundle', 'proof.hwp'), ('document', 'source.md'), ('policy', 'policy.cbor')]:
            (temp / filename).write_bytes(objects[row[field]])
        private = core.decode(objects[row['disclosures']])
        (temp / 'private.hwp').write_bytes(disclosure.pack(private))
        base = [temp/'proof.hwp', temp/'source.md', '--policy', temp/'policy.cbor', '--policy-pin', row['policy_pin']]
        for mode in ('V', 'R'):
            argv = [*base, '--mode', mode]
            if mode == 'R': argv += ['--disclosure', temp/'private.hwp']
            expected = protocol.verify(objects[row['bundle']], objects[row['document']], objects[row['policy']], bytes.fromhex(row['policy_pin']), private if mode == 'R' else None, mode == 'R')
            run(row['id']+'/'+mode, argv, expected)
    # Every subprocess remains bounded. Deterministic malformed inputs are generated
    # outside the frozen directory; this is a small parser corpus, not a fuzz claim.
    row = next(c for c in vector['cases'] if c['id'] == 'keyboard')
    (temp/'proof.hwp').write_bytes(objects[row['bundle']]); (temp/'source.md').write_bytes(objects[row['document']])
    (temp/'policy.cbor').write_bytes(objects[row['policy']]); (temp/'private.hwp').write_bytes(disclosure.pack(core.decode(objects[row['disclosures']])))
    base = [temp/'proof.hwp', temp/'source.md', '--policy', temp/'policy.cbor', '--policy-pin', row['policy_pin']]
    failures = {
        'missing-independent-pin': base[:-2],
        'wrong-independent-pin': [*base[:-1], '0'*64],
        'unknown-option': [*base, '--allow-untrusted'],
        'duplicate-option': [*base, '--policy-pin', row['policy_pin']],
        'V-cannot-silently-use-disclosure': [*base, '--mode', 'V', '--disclosure', temp/'private.hwp'],
        'R-cannot-downgrade-without-evidence': [*base, '--mode', 'R'],
        'directory-not-file': [temp, *base[1:]],
    }
    for name, argv in failures.items(): run(name, argv, status='NO-VALID-HWP', timeout=5)
    fifo = temp/'pipe'; os.mkfifo(fifo)
    run('FIFO-cannot-hang', [fifo, *base[1:]], status='NO-VALID-HWP', timeout=5)
    oversized = temp/'oversized'
    with oversized.open('wb') as out: out.truncate(64*1024*1024+1)
    run('oversized-sparse-file', [oversized, *base[1:]], status='NO-VALID-HWP', timeout=5)
    (temp/'source.md').write_bytes(objects[row['document']]+b'\n')
    run('exact-document-mismatch', base, status='NO-VALID-HWP', timeout=5)
    (temp/'source.md').write_bytes(objects[row['document']])
    (temp/'private.hwp').write_bytes((temp/'private.hwp').read_bytes()[:-1])
    run('truncated-private-transport', [*base, '--mode', 'R', '--disclosure', temp/'private.hwp'], status='NO-VALID-HWP', timeout=5)
    rng = random.Random(20260917)
    malformed = [b'', b'\xff', b'\xa0', b'\x9f\xff', b'\x5a\xff\xff\xff\xff', bytes.fromhex('d28240a0')]
    malformed += [bytes(rng.randrange(256) for _ in range(n)) for n in (1,2,7,31,128,1024)]
    for index, raw in enumerate(malformed):
        (temp/'proof.hwp').write_bytes(raw)
        run('bounded-parser-corpus/'+str(index), base, status='NO-VALID-HWP', timeout=5)

sample = args.native_sample
bundle, document, policy_bytes = ((sample/name).read_bytes() for name in ('proof.hwp','document.txt','policy.cbor'))
pin = hashlib.sha256(policy_bytes).digest()
private = core.decode((sample/'private.cbor').read_bytes())
assert disclosure.unpack((sample/'private.hwp').read_bytes()) == private
checks.append({'name':'native-private-transport-to-frozen-Python','status':'PASS'})
for audit in (False, True):
    result = protocol.verify(bundle, document, policy_bytes, pin, private, audit)
    assert result['status'] == 'TEST-ONLY' and result['outcome'] == 'NOT PROVABLE' and result['result'] is None, result
    assert result['execution_checked'] == ('recomputed' if audit else 'attestation'), result
    checks.append({'name':'native-issued-proof-to-frozen-Python/'+('R' if audit else 'V'),'status':'PASS'})
p = subprocess.run(['node',str(root/'tools/verify_attested.mjs'),str(sample/'proof.hwp'),'--document',str(sample/'document.txt'),'--policy',str(sample/'policy.cbor'),'--policy-pin',pin.hex()],capture_output=True,timeout=30)
node = json.loads(p.stdout)
assert p.returncode == 2 and node['status'] == 'TEST-ONLY' and node['outcome'] == 'NOT PROVABLE', (p.returncode,node)
assert node['execution_checked'] == 'attestation'
checks.append({'name':'native-issued-proof-to-frozen-Node/V','status':'PASS'})
print(json.dumps({'status':'PASS','checks':checks,'count':len(checks),'native_sample_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sample.iterdir()) if p.is_file()}},indent=2))
