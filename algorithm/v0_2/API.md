# Direct implementation interface

All paths below are relative to `algorithm/`. The code is intentionally independent of capture, accounts, networking and proof formats.

## 1. Processing a record

```python
from hwp_a.replay import replay, make_units
from hwp_a.features import extract, adequate

corpus = replay(bundle)  # raises InvalidTrace on malformed/incomplete transitions
units, membership = make_units(corpus, bundle["target"])
features = {u.uid: extract(corpus, u) for u in units}
adequacy = {u.uid: adequate(corpus, u) for u in units}
```

`replay` retains source documents, live scalar occurrences, historical origins and the root-to-effect index. `make_units` returns the complete fixed unit set and root membership, not caller-chosen windows. `extract` returns a sorted mapping of integer feature names to values. `adequate` checks the fixed root and production-episode minimums.

## 2. Fitting from real annotated cases

```python
from hwp_a.dataset import extract_dataset
from hwp_a.model import fit

rows = extract_dataset(cases)  # raw traces + complete origin-creation labels
model = fit(rows)              # default purpose="research"; no approval granted
```

`cases` follows `DATASET_PROTOCOL.md`. Rows preserve split, independent cluster, source/prompt/writer links, document ID and exact model domain. `fit` uses only training rows for trees/prototypes and genuine development rows for support. Missing negative heads remove a domain rather than silently fitting a weaker two-class problem. An unsupported domain or fewer than 99 support-reference clusters cannot certify.

Changing `purpose` text does not approve the model. The relying verifier must independently select the exact model artifact and threshold and check the study and capture prerequisites. The algorithm's source data must never contain an executable instruction to approve itself.

## 3. Full-pipeline scores and verdicts

```python
from hwp_a.verify import TrustedInputs, score, verify

# Values must come from the relying verifier's established admission policy,
# not from fields inside the evidence bundle. No such real policy is supplied.
context = TrustedInputs(
    admissible_documents=frozenset(admitted_document_ids),
    approved_release=False,
    approved_threshold=None,
    allowed_domains=frozenset(admitted_domain_names),
)
scored = score(bundle, model, context)
result = verify(bundle, model, threshold=chosen_threshold, context=context)
```

`score` recomputes replay, features, model inference and origin propagation. It returns threshold-independent per-scalar scores, complete unit diagnostics and origin mappings. Sentinel `-1_000_000_000` means a required gate failed. It is never an uncalibrated “AI score.” A single invalid bundle returns `valid: false` and cannot acquire a positive label.

`verify` permits the positive branch only when `approved_release` is true, `approved_threshold` equals the supplied threshold, and the externally selected model has purpose `validated-release`. The default context and every distributed fixture remain noncertifying. This is an explicit boundary between computation and approval, not a security mechanism against malicious code that edits its own output.

`decide(scored, threshold, certification_enabled=False, excluded=None)` is the lower-level deterministic aggregation function used in tests. A caller must not mistake directly enabling that test function for independently earned assurance.

Quotations are supplied as `excluded=[{"start": byte_start, "end": byte_end, "source": "source-id"}]`. Ranges must be ordered, disjoint and scalar aligned. Exclusions never change model scores or ancestry. Whole-document `verdict`, scoped `contribution_verdict` and every range's own verdict remain distinct.

## 4. Calibration

```python
from hwp_a.dataset import risk_record
from hwp_a.calibration import thresholds
from hwp_a.release import evaluate_release

# Compute development scores before reading calibration outcomes.
candidates = thresholds(genuine_development_document_scores)
# Each record is constructed from the same full pipeline. Repeated records
# sharing a cell/cluster aggregate into one attack or human campaign outcome.
report = evaluate_release(
    records=calibration_records,
    candidates=candidates,
    input_domains=[("keyboard", "en")],
)
```

The example requests one proposed input/language domain; it does not claim English keyboard certification exists. `release.evaluation_cells` returns the exact sixteen required attack-cell names and one human coverage cell for that domain. Use `risk_record(case, model, context, cell, kind)` to construct scores from annotated raw cases. Attack kind is `attack`; genuine coverage kind is `human`.

`calibration.calibrate` also accepts explicitly supplied `required_cells` and `required_human_cells` for experimental or expanded matrices. These lists must be frozen externally, not inferred from available successes. It groups repeated attack rows by maximum score and repeated human rows by minimum score. The exact rational tests determine eligibility. Its result always states `approval_granted: false`.

After successful calibration, freeze the chosen threshold and repeat the registered matrix on independent final-test data with a single candidate threshold. Verify the capture contract, supported domains and study evidence before any relying policy permits the positive label.

## 5. Metrics and attacks

```python
from hwp_a.metrics import evaluate_cases
from hwp_a.attacks import staged_transcription, retime, adaptive_retiming

metrics = evaluate_cases(cases, model, contexts_by_case_id, threshold)
scripted = staged_transcription(target_text, seed=7, profile="keyboard")
variant = retime(scripted, seed=8)
attack = adaptive_retiming(scripted, model, laboratory_context, budget=100, seed=9)
```

Metrics are candidate-decision measurements on supplied labels, never release approval. The per-campaign any-false-scalar endpoint and independent-cluster bounds are stronger than a pooled character accuracy. Ambiguous scalars have a separate denominator.

The attack harness retains every attempted score and reports one statistical unit per search. Its `best_trace` is synthetic. Granting it a laboratory capture assumption tests the behavioural component; it does not make the trace an authenticated human observation. These attack functions are not an exhaustive white-box optimizer or a live device injection tool.

## 6. CLI and JSON

```
python -m hwp_a --output rows.json extract cases.json
python -m hwp_a --output model.json fit rows.json
python -m hwp_a --output calibration.json calibrate calibration-request.json
python -m hwp_a verify trace.json --model model.json --threshold 0
```

`--output` is a global option and precedes the subcommand. A calibration request contains `records`, `candidates`, `required_cells`, `required_human_cells`, and optional experimental targets; the release-level wrapper fixes the standard matrix and default targets.

The CLI intentionally supplies no capture or release approval, and therefore cannot issue HUMAN-WRITTEN merely by opening files. Native capture/admission integration is a later system task. The API and tests demonstrate both conditional decision branches without advertising a standalone file as an authenticated human composition.

## 7. Failure and version behaviour

Unknown fields, malformed Unicode, invalid causal references, unsupported model domains and missing histories fail closed. Specific diagnostic reasons are stable uppercase identifiers in `replay.py` and `verify.py`; callers may explain them but must not reinterpret them as AI-written.

A new algorithm version is required for any change to replay semantics, features, fixed constants, segmentation, exception policy or aggregation. A newly trained release within this version pins its own model and operating domain, passes fresh calibration/testing and does not retroactively upgrade old verdicts.
