# Executable interfaces

Run commands inside `algorithm/v0_3`. The package has no application, publishing, networking or cryptographic component.

```sh
python -m unittest discover -s tests -v
python run_checks.py
python -m hwp_a verify artifacts/telemetry-example.json
```

The last command returns NOT PROVABLE. The example is synthetic, short and unapproved. The command-line verifier intentionally has no flag that treats an author-supplied JSON object as trusted capture or approval.

## Core use

```python
from hwp_a.verify import verify, TrustedInputs

# context must be provided by a separately justified relying verifier.
# Defaults deliberately authorize nothing.
result = verify(bundle, model, threshold=0, context=TrustedInputs())
assert result['verdict'] == 'NOT PROVABLE'
```

The trusted integration selects exact record snapshots, model snapshot, allowed path domains, freshness, threshold and claim from independent evidence. `snapshot(value)` supplies the deterministic JSON representation used for exact equality; calling it on a submitted record does NOT justify admitting that record. Tests explicitly supply those assumptions for synthetic fixtures and are labelled accordingly.

Use `score(bundle, model, context, claim_kind)` for the threshold-independent result: validity, exact text, UTF-8 offsets, per-scalar margins, origin/dependency metadata, complete unit diagnostics and document score. These diagnostics are not certificates. `decide` is an internal formatting helper and must not be exposed as an author-facing route to certify arbitrary scores.

The default claim is fresh-composition. To test inherited wording, explicitly select wording-origin in score, verification, context approval and evaluation ledger. Merely changing the display label is invalid. `excluded` is either None or a list of `{start,end,source}` objects in byte order. It cannot change segmentation or grant origin credit. Whole-document and contribution verdicts remain distinct.

## Data and model fitting

`dataset.extract_dataset(cases)` validates case-level dependencies, replays evidence and creates exact feature rows. `model.fit(rows)` fits all complete domains; absent heads exclude a domain. `model.validate_model(model)` checks the complete artifact. These operations never approve the result. Rows/cases and exact fields are specified in DATASET_PROTOCOL.md and source.

```sh
python -m hwp_a extract cases.json
python -m hwp_a fit rows.json
python -m hwp_a calibrate numeric-calibration-request.json
```

The numeric calibration command is an analysis primitive; production study eligibility additionally requires the ledger and mandatory matrix.

## Release experiments

`release.evaluation_cells(input_domains, claim_kind)` returns required path-specific attack and genuine cells. `release.run_release(ledger,cases,model,contexts,candidates,input_domains)` runs raw attempts, checks task-condition/matrix coverage and returns the statistical report plus every attempt result. `ledger.phase_separation(calibration_ledger,final_ledger)` rejects declared cross-phase data reuse. External study review must still establish actual sampling and ground truth.

`ledger.evaluate_ledger` and `release.evaluate_release` accept independently checked numeric attempt outputs. They must not be used to replace omitted attempts with invented failures. Statistical eligibility always returns `approval_granted: false`; no result here authorizes a real-world release.

## Adversarial and deterministic tests

`attacks.staged_transcription` constructs synthetic staged edit histories. `attacks.retime` perturbs timestamps without changing the event order. `attacks.adaptive_retiming` keeps every attempted trace and score within a single bounded conditional-simulation campaign. The report explicitly says that capture authenticity and human accuracy were not measured.

Test fixtures are not migration tools. `Builder.record()` manufactures native-delivery fixtures for tests; it MUST NOT be used to claim absent native observations in old logs. The 0.2 package is not imported at runtime and prior semantics remain untouched.
