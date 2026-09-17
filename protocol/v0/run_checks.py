"""Run all tests, independent public verification and deterministic-vector checks.

Default mode never edits the frozen distribution. --write is a pre-freeze
maintainer operation that records this execution's report and normalized log.
"""
from pathlib import Path
import sys,unittest,subprocess,os,tempfile,json,hashlib,io,importlib.metadata,re,argparse
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT));os.chdir(ROOT)

def ids(suite):
    result=[]
    for test in suite:
        result.extend(ids(test)) if isinstance(test,unittest.TestSuite) else result.append(test.id())
    return result

def execute(write=False):
    suite=unittest.defaultTestLoader.discover('tests');names=ids(suite);stream=io.StringIO()
    result=unittest.TextTestRunner(stream=stream,verbosity=2).run(suite)
    output=stream.getvalue()
    print(output,file=sys.stderr)
    peer=subprocess.run(['node','tools/check_interop.mjs'],capture_output=True,text=True,check=False)
    peer_result=json.loads(peer.stdout) if peer.returncode==0 else {'status':'FAIL','stderr':peer.stderr}
    with tempfile.TemporaryDirectory() as tmp:
        copies=[]
        for value in ('0','987'):
            p=Path(tmp)/(value+'.json');env=dict(os.environ,PYTHONHASHSEED=value)
            subprocess.run([sys.executable,'tools/generate_vectors.py',str(p)],env=env,check=True,capture_output=True,text=True)
            copies.append(p.read_bytes())
        expected=(ROOT/'vectors/interchange.json').read_bytes()
        deterministic=(copies[0]==copies[1]==expected)
    failed={t.id() for t,_ in result.errors+result.failures};skipped={t.id() for t,_ in result.skipped}
    report={'protocol':'hwp/0','revision':'0.0.0','tests_run':result.testsRun,
      'passed':result.testsRun-len(failed)-len(skipped),'failures':len(result.failures),'errors':len(result.errors),'skipped':len(result.skipped),
      'passed_test_ids':sorted(set(names)-failed-skipped),'independent_verifier':peer_result,
      'vectors_equal_across_hashseed_0_987_and_frozen_file':deterministic,
      'interchange_sha256':hashlib.sha256(expected).hexdigest(),
      'protocol_definition_sha256':hashlib.sha256(bytes.fromhex((ROOT/'manifests/protocol.cbor.hex').read_text())).hexdigest(),
      'environment':{'python':sys.version.split()[0],**{k:importlib.metadata.version(k) for k in ['cryptography','numpy','scipy','jsonschema','asn1crypto']},
                     'openssl':subprocess.check_output(['openssl','version'],text=True).strip()},
      'baseline_tests_executed_before_reconciliation':{'hwp-a/0.3':100,'hwp-c/1':95},
      'real_human_sessions':0,'models_trained_on_real_human_data':0,'evaluated_native_capture_paths':0,
      'empirically_approved_releases':0,'real_human_writing_proofs_issued':0,'zk_proofs_generated':0,
      'warnings':['All integration keys, input traces and models are synthetic conformance fixtures.',
                  'Class V independently checks public attestation and commitments, not a second behavioural implementation.',
                  'One deliberately dishonest admitted evaluator passes attestation and fails disclosed recomputation.',
                  'No human-detection accuracy, third-party security review or eternal cryptographic lifetime is claimed.']}
    if write:
        (ROOT/'vectors/results.json').write_text(json.dumps(report,sort_keys=True,indent=2)+'\n')
        (ROOT/'vectors/test-output.txt').write_text(re.sub(r'Ran (\d+) tests in [0-9.]+s',r'Ran \1 tests (elapsed time omitted)',output))
    print(json.dumps(report,sort_keys=True,indent=2))
    return 0 if result.wasSuccessful() and peer.returncode==0 and deterministic else 1
if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--write',action='store_true');a=ap.parse_args();raise SystemExit(execute(a.write))
