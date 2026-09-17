"""Reproduce conformance tests and synthetic/mechanical artifacts, not human accuracy."""
from pathlib import Path
import io,json,platform,sys,time,unittest
import numpy,scipy
from hwp_a.fixtures import Builder,TEXT,permissive_fixture_model
from hwp_a.replay import replay,make_units,utf8_offsets
from hwp_a.features import extract
from hwp_a.verify import score,verify,TrustedInputs
from hwp_a.calibration import upper,zero_failure_n
from hwp_a.release import evaluation_cells
from hwp_a.attacks import adaptive_retiming,staged_transcription

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'artifacts'; OUT.mkdir(exist_ok=True)

def write(name,obj):
    (OUT/name).write_text(json.dumps(obj,ensure_ascii=False,sort_keys=True,indent=2)+'\n',encoding='utf-8')

def names(suite):
    for child in suite:
        if isinstance(child,unittest.TestSuite): yield from names(child)
        else: yield child.id()

def main():
    suite=unittest.defaultTestLoader.discover(str(ROOT/'tests'))
    test_names=list(names(suite)); log=io.StringIO(); start=time.perf_counter()
    result=unittest.TextTestRunner(stream=log,verbosity=2).run(suite)
    elapsed=time.perf_counter()-start
    (OUT/'test-output.txt').write_text(log.getvalue(),encoding='utf-8')
    if not result.wasSuccessful():
        print(log.getvalue()); raise SystemExit(1)
    records=[]
    for profile in ('keyboard','touch-tap','ime','gesture'):
        bundle=Builder(did=profile,profile=profile).type(TEXT,seed=123).bundle()
        write(profile+'.trace.json',bundle); records.extend(bundle['documents'])
    combined={'version':'hwp-a/0.2','documents':records,'target':'keyboard'}
    fixture_model=permissive_fixture_model(combined)
    write('fixture-model.json',fixture_model)
    kb={'version':'hwp-a/0.2','documents':[records[0]],'target':'keyboard'}
    context=TrustedInputs(frozenset({'keyboard'}),False,None,frozenset(fixture_model['domains']))
    scored=score(kb,fixture_model,context)
    public=verify(kb,fixture_model,context=context)
    c=replay(kb); units,_=make_units(c,'keyboard'); first=units[0]
    write('feature-vector.json',{'fixture':True,'unit':first.uid,'roots':list(first.roots),'features':extract(c,first)})
    write('public-verdict.json',public)
    write('origin-vector.json',{'text':c.documents['keyboard'].text,'utf8_offsets':utf8_offsets(c.documents['keyboard'].text),
         'origins':[{'id':aid,'roots':sorted(c.atoms[aid].roots),'home':c.atoms[aid].home} for aid in c.documents['keyboard'].live]})
    attack=adaptive_retiming(kb,fixture_model,context,budget=8,seed=11)
    write('timing-attack.json',attack)
    cells,human=evaluation_cells([('keyboard','en')]); alpha=.025/(len(cells)*32)
    report={'date':'2026-09-15','algorithm':'hwp-a/0.2','test_methods':result.testsRun,
            'failures':len(result.failures),'errors':len(result.errors),'skipped':len(result.skipped),
            'success':result.wasSuccessful(),'test_names':test_names,'test_runtime_seconds':elapsed,
            'environment':{'python':sys.version.split()[0],'numpy':numpy.__version__,'scipy':scipy.__version__,'platform':platform.system()},
            'feature_count':len(extract(c,first)),'synthetic_keyboard_scalar_count':len(c.documents['keyboard'].text),
            'synthetic_keyboard_unit_count':len(units),'fixture_candidate_document_score':scored['document_score'],
            'fixture_public_verdict':public['verdict'],
            'observational_equivalence':{'same_observations_different_alleged_causes_same_features':True,
                                         'interpretation':'Unit-tested counterexample, not a real-human detector evaluation.'},
            'numerical_examples':{'single_fixed_test_zero_failure_n_epsilon_0_001_alpha_0_05':zero_failure_n(.001,.05),
                'single_fixed_test_upper_at_n_2995':upper(0,2995,.05),
                'one_domain_registered_attack_cells':len(cells),'candidate_threshold_count_example':32,
                'per_cell_alpha_example':alpha,'zero_failure_n_per_registered_cell_example':zero_failure_n(.001,alpha),
                'independent_1000_attempt_success_if_p_0_001':1-(1-.001)**1000},
            'attack_harness':{'attempts':8,'statistical_campaigns':1,'model':'deliberately permissive fixture'},
            'real_human_sessions':0,'real_human_trained_models':0,'approved_releases':0,'real_capture_paths_tested':0,
            'human_accuracy_measured':False,'security_audit_completed':False,
            'publication':{'repository':'mariusschober/nostr-writer','remote_write_verified':False},
            'scope':'Algorithm only; synthetic tests and exact arithmetic do not establish human composition accuracy.'}
    write('results.json',report)
    print(json.dumps({k:report[k] for k in ('success','test_methods','feature_count','fixture_public_verdict','human_accuracy_measured')},indent=2))

if __name__=='__main__': main()
