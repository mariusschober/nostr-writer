# 7. Results, limitations, and decision

Research draft · 2026-09-15.

## 7.1 Deliverables established

The package defines the binary claim and scope semantics; derives an observational-equivalence limit; specifies a candidate selective composition algorithm and fine-grained text lineage; defines a cryptographic binding graph and private verification relation; designs Nostr/C2PA/timestamp adapters; and sets an adversarial evaluation and approval contract.

The key constructive result is a separation between **origin of evidence**, **correct execution on evidence**, and **validity of the behavioural inference**. This prevents a system from proving that fabricated data passed a model and advertising the result as proof of human writing.

The candidate detector prioritizes dependencies among text creation, revisions, navigation, and later choices. Its central hypothesis is falsifiable: it must outperform timing/edit-count baselines and survive matched transcription and adaptive process simulation. It does not measure thought directly.

## 7.2 Executed experiments

`python experiments/foundation_checks.py` was executed using Python 3.13.5 and cryptography 46.0.4. It completed **33 assertion checks**. The exact checks and numerical outputs are stored in [results.json](../../experiments/results.json); deterministic fixtures are in [vectors.json](../../experiments/vectors.json).

The checks cover domain/argument framing; a constrained canonical JSON domain; duplicate-key, float, oversized-integer, surrogate, and noncanonical-whitespace rejection; exact newline/Unicode byte distinction; a miniature insert/delete replay; ordered and salted Merkle commitments; selected range-partition failures; Ed25519 signing/verification; payload/role/algorithm/key tampering; exact-document substitution; and external-policy approval rather than self-signed approval.

A synthetic counterexample assigns different alleged causes to identical observations and confirms the same commitment. It illustrates the observational boundary; it is not a measured attack on a trained detector. A second counterexample shows that a valid self-signed HUMAN-WRITTEN assertion does not create an externally approved profile.

All text, salts, events, and signing material in the vectors are synthetic fixtures. The private seed is intentionally published and must never be used for real signing. The fixture's actual binary result is NOT PROVABLE.

The miniature replay does not implement the full origin graph. The script does not implement capture attestation, Merkle inclusion/consistency verification, Nostr signing, a C2PA adapter, timestamp verification, a production certificate parser, a trained detector, or a zero-knowledge prover. Passing these checks is not protocol conformance or a security audit.

## 7.3 Reproducible numerical consequences

With zero observed false certifications in independent fixed-distribution trials, a one-sided 95% upper bound of 0.1% needs **2,995** trials. At that n, the computed bound is approximately **0.0009997444**. A 0.01% target needs **29,956** such trials. These calculations are not observations of detector accuracy.

With twenty prespecified families and a Bonferroni allocation for simultaneous 95% coverage, the illustrative 0.1% target needs **5,989** zero-failure trials per family. Dependencies and adaptive attacks require different analysis; multiplying windows from the same person is not a substitute for independent evidence.

A per-attempt success probability of 0.001 yields approximately **63.2305%** chance of at least one success over 1,000 independent attempts. This establishes why open-detector grinding and an adversary's budget must be part of the assurance claim.

## 7.4 What has not been established

Human participant sessions collected: **0**. Trained detectors: **0**. HWP zero-knowledge proofs generated: **0**. Hardware capture paths tested: **0**. Approved certification profiles: **0**.

There is no supported estimate of HWP's false-certification rate, genuine-writing coverage, paragraph-level discrimination, mobile accuracy, proof-generation time, memory consumption, or resilience to adaptive human-assisted attacks. No results from another paper are presented as these missing measurements.

The package also does not establish a universal protected keyboard/touchscreen acquisition path, the truth of an identified author's cognitive contribution, a complete production wire schema, an audited verifier, or standards-body acceptance.

## 7.5 Strongest unresolved questions

**Behavioural separability.** Do cross-event dependencies retain useful discrimination after a human transcriber or adaptive simulator is allowed to mimic the full process? The answer determines whether the desired assurance has a useful operating point.

**Authentic capture.** What exactly can be independently attested between a real keyboard/touch input source and the final committed text on each supported platform? A protected signing key alone is insufficient.

**Definition and labels.** How can controlled experiments distinguish genuine AI-informed composition from mechanical paraphrasing without using an anti-AI label or pretending to observe cognition? Ambiguous labels must remain visible.

**Private execution.** Can the complete replay/lineage/feature/model computation be proved with acceptable resources, without outsourcing the private witness or trusting unproved preprocessing? This is a measurement question, not a solved cost assumption.

**Open adversarial operation.** What admission rate remains useful when the model is public and adversaries can adapt or make many attempts? Privacy-preserving decentralized systems cannot simply assume unlimited attackers have been rate-limited.

## 7.6 Recommendation

Pursue the intellectual foundation and controlled adversarial validation now; defer writing-application development and expensive proof-system optimization. The first decision-changing experiment is matched composition versus human transcription, including permitted AI-informed rewriting and adaptive staged histories, using the proposed capture/lineage contract.

The durable opportunity is an open standard for independently checkable writing-process provenance with explicit assurance semantics. The standard must earn the stronger HUMAN-WRITTEN label through admissible capture and empirical evidence, rather than treating cryptographic sophistication as a substitute for either.
