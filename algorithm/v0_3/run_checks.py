"""Reproduce synthetic regression results and deterministic inference vectors."""
from pathlib import Path
import importlib.metadata
import io
import json
import platform
import unittest
from hwp_a.fixtures import Builder, TEXT, permissive_fixture_model
from hwp_a.replay import replay, make_units
from hwp_a.features import extract, FEATURE_NAMES
from hwp_a.verify import TrustedInputs, snapshot, score

BASE = Path(__file__).resolve().parent


def stable_vectors():
    result = {}
    for profile in ('keyboard', 'touch-tap', 'ime', 'gesture'):
        bundle = Builder(profile=profile).type(TEXT, seed=47).bundle()
        model = permissive_fixture_model(bundle)
        context = TrustedInputs(
            admissible_documents=frozenset(d['id'] for d in bundle['documents']),
            allowed_domains=frozenset(model['domains']),
            document_snapshots=frozenset((d['id'], snapshot(d)) for d in bundle['documents']),
            fresh_documents=frozenset(d['id'] for d in bundle['documents']))
        corpus = replay(bundle)
        units, _ = make_units(corpus, bundle['target'])
        scored = score(bundle, model, context)
        result[profile] = {
            'first_unit': units[0].uid,
            'features': extract(corpus, units[0]),
            'unit_count': len(units),
            'scalar_scores': scored['scalar_scores'],
            'document_score': scored['document_score'],
            'source': 'SYNTHETIC_FIXTURE',
            'certification_approved': False}
    return result


class RecordedResult(unittest.TextTestResult):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.passed_ids = []

    def addSuccess(self, test):
        super().addSuccess(test)
        self.passed_ids.append(test.id())


def main():
    suite = unittest.defaultTestLoader.discover(str(BASE / 'tests'))
    text = io.StringIO()
    runner = unittest.TextTestRunner(stream=text, verbosity=2, resultclass=RecordedResult)
    result = runner.run(suite)
    artifacts = BASE / 'artifacts'
    artifacts.mkdir(exist_ok=True)
    (artifacts / 'test-output.txt').write_text(text.getvalue())
    vectors = stable_vectors()
    (artifacts / 'deterministic-vectors.json').write_text(json.dumps(vectors, sort_keys=True, indent=2) + '\n')
    (artifacts / 'feature-vector.json').write_text(json.dumps(vectors['keyboard']['features'], indent=2) + '\n')
    report = {
        'algorithm_version': 'hwp-a/0.3', 'package_version': '0.3.0',
        'scope': 'Synthetic reference conformance, mathematical checks and adversarial regressions only',
        'tests_run': result.testsRun, 'passed': len(result.passed_ids),
        'failures': len(result.failures), 'errors': len(result.errors), 'skipped': len(result.skipped),
        'passed_test_ids': sorted(result.passed_ids),
        'environment': {'python': platform.python_version(),
                        **{name: importlib.metadata.version(name) for name in ('numpy', 'scipy', 'jsonschema')}},
        'feature_count': len(FEATURE_NAMES),
        'random_splice_checks_within_one_test': 2000,
        'old_baseline_tests_before_revision': 76,
        'old_counterexamples': 'v02-counterexamples.json',
        'representation_collision_resolved': False,
        'actual_human_participant_sessions': 0,
        'models_trained_on_real_human_data': 0,
        'native_capture_paths_tested': 0,
        'empirically_approved_releases': 0,
        'human_detection_accuracy': None,
        'end_to_end_capture_attack_resistance': None,
        'synthetic_positive_verdicts_are_not_real_certification': True}
    (artifacts / 'results.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps({key: report[key] for key in ('tests_run', 'passed', 'failures', 'errors', 'skipped')}))
    if not result.wasSuccessful():
        raise SystemExit(1)


if __name__ == '__main__':
    main()
