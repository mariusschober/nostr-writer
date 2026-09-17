## Task 3

Completed the second adversarial pass as HWP-A 0.3.0. The revised specification, audit, telemetry schema, feature definitions, counterexamples and test results are published on main in commit 73679e0. I verified the branch update and the published files’ content identities.

The executable source was not published to GitHub: both source-upload attempts were blocked by an indeterminate tool safety check. The repository explicitly records that limitation. The complete 38-file package, including the revised implementation and tests, is available here:

Download HWP-A 0.3.0Reader · Technical specification · Adversarial audit

The central conclusion is more demanding than “the algorithm passes its tests”: the evidence-processing and evaluation foundation is stronger, but the current behavioural feature representation must not yet be accepted as a demonstrated solution to composition-versus-imitation. The audit found both repairable defects and an exact representational blind spot.

What the audit broke—and repaired

The spelling exception could change a substantive claim while inheriting human provenance. I reproduced 100 → 900 receiving HUMAN-WRITTEN under the old conditional test setup. Small edit distance does not establish preservation of meaning or composition. The revised algorithm therefore grants no automatic human-origin inheritance to assisted replacement text. Directly typed replacements receive new origins and their own assessment. This deliberately sacrifices some harmless autocorrection coverage rather than granting an unjustified exception.

Approval did not adequately identify what had been approved. A Boolean approval flag, threshold or model name could be reused with different model contents; a record ID could likewise refer to substituted observations. The revised entry point requires independently selected exact record and model snapshots, threshold, input-path domains, freshness conditions and claim semantics. Every model branch and numeric value is validated before inference, including branches that a particular example never visits. These are algorithmic equality and admission requirements—not a new cryptographic system.

The observation record could be internally plausible without establishing the claimed causal sequence. Equal timestamps did not impose an unambiguous order across input and mutation streams. The revision introduces one total sequence and requires:

Observed input cause → independently observed native text/edit delivery → authoritative mutation.

Each delivery must match the exact operation and be consumed once. Future causes, reused causes, inconsistent input profiles, unaccounted deliveries and input crossing forbidden interruptions are rejected. I also reproduced and repaired a held-key repeat accepted outside focus. Crucially, manufacturing matching fields from the same submitted payload does not satisfy the independent-observation requirement.

Preserved wording was being confused with fresh composition. The default claim is now explicitly fresh-composition. Copied occurrences cannot manufacture new composition credit. A separately identified wording-origin claim can preserve previously established ancestry, but cannot assert that the present assembler composed those words or the resulting argument. Both retain the binary verdict vocabulary; the claim identifier prevents two different propositions from hiding behind the same label.

Source detection could operate backward in time. Adding an unrelated later source document could change the verdict on earlier writing. The source-reuse veto now uses earlier, same-record exposure and propagates through actual ancestry—not bundle order or invented knowledge of what the author read. Synthetic control operations and automated deletion also no longer inherit an accepted process merely because they manipulate previously supported wording.

The statistical repair goes beyond confidence intervals

The earlier exact binomial calculations were not enough. A mathematically correct bound calculated from selectively retained attempts is still misleading.

The revised evaluation requires a frozen ledger accounting for every scheduled attack attempt and genuine-writing task. Missing attempts, pending results, incomplete labels, duplicated attempts and declared dependencies between supposedly independent blocks prevent eligibility. A claimed “100-attempt campaign” must actually contain the full registered budget.

For attacks, one falsely admitted scalar anywhere in the campaign counts as a failure. For genuine-writing coverage, all required tasks within the participant block must pass. Windows and keystrokes never become independent participants merely because there are many of them.

Ambiguous cases remain explicitly ambiguous. They count adversely when establishing release eligibility and cannot inflate genuine-writing coverage. AI-informed, fluent-expert, revision-heavy, interrupted, second-language and unaided composition have separate coverage requirements for each proposed input-path/language domain. This prevents an apparently successful detector from quietly excluding precisely the legitimate writing processes it is supposed to support.

Threshold selection still uses exact rational tests with simultaneous correction across the frozen candidate thresholds and required evaluation cells. The specification now explicitly distinguishes calibration from a new, fixed-threshold final evaluation. It does not claim that ledger metadata proves actual independence, that two separate 95% statements automatically yield joint 95% confidence, or that measured finite-budget risk covers unlimited adaptive attempts.

The finding that training alone cannot repair

I constructed different meaningful wording that produces identical values for all 179 features in corresponding evidence units. This is an exact collision in the representation, not merely a suspicion that an attacker might imitate pauses. The regression remains in the package as a documented limitation.

The consequence is precise: a deeper model trained on those same features cannot distinguish those examples. The missing information has already been discarded. This does not prove that every such example will pass a properly calibrated detector; it proves that the feature representation cannot separate them when their scores need to differ.

Accordingly, the revised specification treats the 179-feature model as a fully executable baseline, not the theoretically optimal detector or an immutable definition of human composition. Collision attacks, meaningful staged revision and matched human transcription are mandatory evaluation cases. A release may discover that no threshold provides both the required false-certification bound and useful genuine-writing coverage.

This representational limitation is distinct from the broader observation limit: even a richer representation cannot distinguish different hidden causes when their admissible observations are identical. The theory document separates those two boundaries and states exactly which statistical conclusions depend on which sampling assumptions.

What is executable and verified

The complete package implements telemetry validation, replay, origin inheritance, fixed evidence neighbourhoods, feature extraction, model fitting and integer inference, passage/document aggregation, dataset checks, attack construction, complete-campaign accounting and release eligibility.

All 100 tests pass, with zero failures, errors or skips. They include four normalized input profiles and 2,000 randomized splice/replay comparisons inside one test. Separate Python processes produced byte-identical deterministic inference vectors. I also extracted the final ZIP into a clean directory and reran all 100 tests successfully. These are implementation and mathematical checks, not human-writing accuracy measurements.

No human participant sessions were collected, no model was trained on real human-writing data, and no native capture path was validated. The positive-verdict tests use deliberately permissive synthetic models to test control flow. They do not certify the generated examples as human-written.

The older implementation and research remain unchanged. Version 0.3 has its own directory and interpretation-bearing identifiers. New models can be evaluated later without changing what earlier assessments meant; changes to telemetry, features, segmentation, assistance rules or claim semantics require explicitly versioned computations. Missing observations in old records cannot be invented during migration.

My recommendation is to accept the revised evidence, provenance, decision-interface and evaluation contract as the working foundation—not to freeze the current feature model as the standard. The next decisive experiment is matched genuine composition versus skilled human transcription and adaptive staged revision, including the demonstrated feature-collision family. That experiment can now invalidate or improve the empirical component without requiring the surrounding method to be reinvented.
