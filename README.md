# Human Writing Provenance — research foundation

**Status: research draft, 2026-09-15. No production certification profile is approved.**

This repository develops an open, independently verifiable standard for evidence that text emerged through genuine human composition. Its two possible certification results are **HUMAN-WRITTEN** and **NOT PROVABLE**. The latter never means AI-written, fraudulent, or not human.

The definition permits AI-informed ideas followed by genuine human composition. It distinguishes that process from pasting, mechanical transcription, scripted input, and fabricated writing histories. This is not a detector of AI-like prose, a plagiarism detector, a proof of originality, or a proof of personhood.

## Principal findings

Writing behaviour provides testable evidence, not direct access to cognition. The proposed detector evaluates how writing, revision, navigation, and subsequent decisions fit together, with separate calibration for physical keyboards and touchscreen input. It tracks the provenance of individual text ranges rather than averaging authenticity over an entire document.

Cryptography can bind exact document bytes, an authenticated capture record, a specified computation, and its conclusion. It cannot convert a fabricated input history into a genuine one. A zero-knowledge proof of a classifier accepting a transcript is insufficient unless the same transcript is independently bound to an admissible capture source.

An unrestricted observer-only claim is non-identifiable when composition and transcription produce the same observations. The specification derives this boundary and develops the strongest useful alternative: an explicit, versioned assurance claim with conservative abstention, reproducible evaluation, and no silent exceptions to the advertised threat model.

## Research package

- [Foundation and exact claim semantics](research/hwp/01-foundation.md)
- [Candidate detection algorithm and text lineage](research/hwp/02-algorithm.md)
- [Cryptographic protocol and private verification](research/hwp/03-proof-system.md)
- [Adversarial validation and certification gates](research/hwp/04-validation.md)
- [Nostr, C2PA, timestamps, and long-term verification](research/hwp/05-interoperability.md)
- [Primary sources and evidence boundaries](research/hwp/06-sources.md)
- [Executed checks, results, and unresolved questions](research/hwp/07-results.md)
- [Machine-readable research policy](research/hwp/research-policy.json)
- [Reproducible cryptographic and mathematical experiments](experiments/foundation_checks.py)
- [Machine-readable experimental results](experiments/results.json)
- [Deterministic cryptographic test vectors](experiments/vectors.json)

The protocol documents are specifications and research proposals. The experiment script checks selected cryptographic mechanics and mathematical consequences; it is **not** a writing application, a trained detector, a complete protocol verifier, a hardware-attestation implementation, or a zero-knowledge prover.

## What has and has not been established

The package separates published empirical evidence, mathematical deductions, proposed algorithms, executed synthetic checks, and untested hypotheses. No human participant data was collected for this package. No detector accuracy, adversarial false-acceptance rate, mobile attestation coverage, or proof-generation performance is claimed.

The supplied research policy intentionally authorizes no HUMAN-WRITTEN certificates. A future certification release requires an independently evaluated detector, an explicit capture threat model, verified implementations, published calibration evidence, and an externally chosen trust policy. Merely editing a field in a bundle cannot approve a profile.

A document containing quotations can have a qualified author-contribution claim with explicit excluded ranges. It cannot silently acquire an unqualified whole-document claim. Exact-byte verification and verification of a rendered or transformed document are different operations.

## Scope

Only the human-writing detection algorithm and the cryptographic evidence/signature system are addressed. Application architecture, interface design, publishing experience, and broader product development are deliberately outside this research package.

This is an AI-assisted research deliverable requested by the repository owner. It is not represented as HUMAN-WRITTEN. No standards-body adoption, assigned Nostr extension number, independent security audit, or legal certification is implied. Repository-wide licensing and standards-governance commitments have not been established by this draft.
