# Reconciliation audit and freeze disposition

The reviewed inputs are the complete mounted HWP-A0.3.0 and HWP-C1.0.0-candidate.1 archives, with digests in `baseline/INPUTS.json`, and repository main `c53e794a11aa801b553af462fe5da33593e12eee`. The original algorithm100-test and crypto95-test suites both passed before this reconciliation. Passing each separately did not demonstrate compatibility: the C1 tests never executed the actual A03 algorithm.

This work is a new adversarial pass by the same assistant. “Independent” here means checking the components against their actual code and counterexamples rather than assuming earlier conclusions were correct; it is not a third-party audit or externally reviewed standard.

| Finding | v0 resolution | Evidence/remaining condition |
|---|---|---|
| C1's execution bridge was a specification plus a synthetic echo callback | Closed, real decode→replay→features→model→scope→lineage implementation; public API has no arbitrary-runner parameter | Integration tests run every declared input profile through actual inference and signed binding |
| Capture-start did not bind the planned release/model/threshold | Signed start.release equals exact target release; source parents predeclared | Old approved model substitution without resigning start reproduces; v0 regression rejects |
| Capture-end did not explicitly bind the final document | Signed end.document Ref checked against target statement and every opened record | Removes a real binding ambiguity without claiming signatures alone authenticate cognition |
| Identical final texts could obscure target/source selection | Exact target capture and deterministic closed record graph | Unknown target, unrelated record and parent substitutions reject |
| A claimed parent proof could match bytes but not actual source | Actual atom roots and planned source capture/proof relation checked by bridge | Public private-mode assurance remains an evaluator assertion; full disclosure checks it |
| A03 control events escaped direct-typing focus/age barriers | Same observed-focus, maximum-delay and interruption gates for all transactions | Baseline out-of-focus control accepted; v0 test rejects |
| Suspected non-whitespace mismatch | Rechecked against the actual archived C1 source; the suspicion was false | C1 already rejects all-U+2028 text. v0 retains the same boundary and tests it, not a claimed repair |
| Parent/child invocations with the same release could replace a release-keyed runner | Closed runners keyed by release **and statement** | Same-release inherited proof recomputation regression passes |
| Different valid public partitions could conceal scope interpretation drift | Maximal exact-origin partition, same selected/whole semantics, UTF-8 scalar boundaries | Nonmaximal, all-excluded, empty-source and whole-scope downgrades reject |
| Positive fixtures could be mistaken for empirical approval | Conformance stage/purpose yields TEST-ONLY/NOT PROVABLE; production rejects fixture releases/profiles | No production-admitted release distributed; all published positive paths explicitly synthetic |
| Release name, model bytes, threshold and validation reports could refer to different objects | Exact model/decision/dossier/domain/program/profile closure | No automatic inference that report contents are scientifically true |
| A monolithic CBOR disclosure would hit a parser-item limit before algorithm event limits | Canonical256-opening private chunks plus fixed aggregate budgets | Native API and portable private transport have the same complete evidence semantics |
| Old format ambiguities could be inherited silently | New wire/algorithm/model/adapter/output IDs; no legacy upgrade | Old source and documents preserved separately; v0 rejects old markers |
| Remote company execution or code retrieval could be required | Full source/normative artifact closure; locally installed fixed bridge; no network | Actual archival retention and future implementation maintenance still necessary |
| Conformance rejection could manufacture perfect benchmark accuracy | Research endpoints use actual conditional candidate admissions, not the public test-only outcome; invalid study models abort before counting | Descriptive metrics now carry the explicit claim kind |
| Stronger crypto might appear to fix known detector collisions | Exact feature-collision test and raw-observation equivalence retained | Training on the same representation cannot recover information it discarded |
| A trusted evaluator can lie about a private record | Attested-vs-recomputed guarantee stated explicitly; live test over pasted telemetry passes attestation but fails actual recomputation | Deliberate residual counterexample, not “repaired” with misleading certainty |

## What is fixed versus assumed

Fixed: deterministic serialization, signature domains, object shapes, exact document and scope binding, prospective target release, explicit source dependencies, total-order replay input, actual algorithm invocation, stable output commitment, authority separation, test/production projection, resource contracts, parent root matching, malformed-input failure and repeatable vectors.

Conditional: actual event acquisition; truth of device/synthetic origin; absence of hidden decoder generation; honesty of capture/evaluation and approval authorities; the quality and validity of empirical studies; deployment distribution; sufficient independent samples; cryptographic security during the relevant lifetime; archival availability.

Unmeasured: real composition/transcription discrimination, accuracy against white-box imitation, admitted native keyboard/touch/IME paths, accessibility coverage, end-to-end privacy and performance, useful risk/coverage under repeated attempts, real-world keys/authority operations, ZK generation and renewable decades-long archival practice. No synthetic test count estimates these quantities.

## Deliberate scope decisions

The v0 observation alphabet captures event classes, timing, native deliveries, authoritative text operations and ancestry. It does not record physical key identity, touch coordinates, gaze, thought or a trusted inventory of external sources. Such information cannot be reconstructed from its commitments or assumed available to the features. Richer capture/representation work requires a new precisely defined profile/algorithm version.

The current179-feature model is frozen as an executable baseline interpretation, not as an optimal cognitive detector. Future empirically trained weights can change under new releases; genuinely different features or observations require a new version. No default empirical model is guessed. Certification remains unavailable until a real release has earned independent admission under the specified study contract.

The point of the freeze is to make disagreement and falsification precise. It does not authorize marketing a conditional provenance statement as universal proof of a person's mental process.

## Approval-cycle correction

A new reconciliation counterexample exposed a circular requirement: an empirical release that contains its held-out reports cannot already be the capture-start reference in those reports' experiments. V0 now fixes a conformance candidate before the final trials, binds reports to that candidate and its exact operating point, and creates the empirical release afterwards. Mandatory candidate/artifact/dossier equality prevents a different classifier from inheriting the reports. Production starts name the later empirical release; old experimental captures do not become production proofs. Four staging regressions check the pointer, stage, operational equality and non-authorization of the candidate. Scientific quality of the reports remains an external approval obligation, not a hash-verification conclusion.
