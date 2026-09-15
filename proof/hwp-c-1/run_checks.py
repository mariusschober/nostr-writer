"""Run conformance checks and record measured results, not human-writing accuracy."""
from pathlib import Path
import hashlib,importlib.metadata,io,json,os,platform,subprocess,sys,unittest
ROOT=Path(__file__).resolve().parent
os.chdir(ROOT);sys.path[:0]=[str(ROOT),str(ROOT/'tests')]
class Result(unittest.TextTestResult):
    passed=[]
    def addSuccess(self,test):super().addSuccess(test);self.passed.append(test.id())

def main():
    suite=unittest.defaultTestLoader.discover('tests');stream=io.StringIO()
    result=unittest.TextTestRunner(stream=stream,verbosity=2,resultclass=Result).run(suite)
    print(stream.getvalue(),end='')
    hashes=[]
    for hs in ('0','987'):
        p=subprocess.run([sys.executable,'tools/generate_vectors.py'],env=dict(os.environ,PYTHONHASHSEED=hs),capture_output=True,text=True,check=True)
        hashes.append(json.loads(p.stdout)['sha256'])
    if hashes[0]!=hashes[1]:raise AssertionError('nondeterministic-vectors')
    js=subprocess.run(['node','tools/independent_check.mjs'],capture_output=True,text=True,check=True)
    report={'version':'hwp-c/1','publication':'1.0.0-candidate.1','tests_run':result.testsRun,'passed':len(result.passed),'failures':len(result.failures),'errors':len(result.errors),'skipped':len(result.skipped),'passed_test_ids':result.passed,
       'interchange_vectors_sha256':hashes[0],'identical_vectors_across_pythonhashseed':['0','987'],'independent_js_checker':json.loads(js.stdout),
       'environment':{'python':platform.python_version(),'cryptography':importlib.metadata.version('cryptography'),'asn1crypto':importlib.metadata.version('asn1crypto'),'openssl':subprocess.check_output(['openssl','version'],text=True).strip()},
       'real_human_sessions':0,'real_approved_hwp_releases':0,'real_hwp_certificates_issued':0,'native_capture_paths_tested':0,'zk_proofs_generated':0,
       'implemented':['deterministic CBOR','COSE Ed25519','strict point encoding','salted ordered Merkle commitments','complete and selected openings','capture/evaluator/author bindings','external policy and scope verification','private attestation and disclosed callback boundary','RFC3161 token verification','archival inventory'],
       'not_implemented':['behavioural HWP runner','native capture or hardware appraisal','zero-knowledge proof suite','Nostr signature/adapter execution','C2PA manifest creation/validation','OpenTimestamps chain verification','RFC4998 evidence-record renewal engine','live revocation/status service'],
       'warnings':['All positive HWP fixtures are synthetic and use public test private seeds.','Timestamp tests use local synthetic CA/TSA keys, not a public notarization.','JavaScript is an independent primitive/interchange checker, not a complete second HWP verifier.','No security audit, standards-body adoption, indefinite cryptographic lifetime or human-detection accuracy is claimed.']}
    (ROOT/'vectors/results.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    (ROOT/'vectors/test-output.txt').write_text(stream.getvalue())
    print(json.dumps({k:report[k] for k in ['tests_run','passed','failures','errors','skipped','interchange_vectors_sha256']},sort_keys=True))
    if not result.wasSuccessful():raise SystemExit(1)

if __name__=='__main__':main()
