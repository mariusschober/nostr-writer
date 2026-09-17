# Human Writing Protocol / Nostr Writer

This repository is the source of truth for the Human Writing Provenance research, **Human Writing Protocol v0**, and the implementation-ready **Nostr Writer for Mac** handoff.

The project does not claim that failed verification means AI authorship. The only positive protocol claim is **HUMAN-WRITTEN** under an exact, independently selected protocol/release/scope/trust policy. Everything else is **NOT PROVABLE** and receives no Human Writing Proof. Current real-world detector/capture approval remains empty; synthetic conformance fixtures are not production certificates.

## Current authoritative layers

- [`protocol/v0/`](protocol/v0/) — frozen joined Human Writing Protocol v0. Protocol-definition SHA-256: `58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4`.
- [`product/mac/`](product/mac/) — complete Mac MVP product/UX/architecture contracts, 8 implementation PLANs, 8 short START prompts, and 60 mandatory completion criteria.
- [`mac/Packages/WriterFoundation/`](mac/Packages/WriterFoundation/) — pre-implementation pure-Swift kernels. See [`RECONCILIATION.md`](RECONCILIATION.md) for provenance.
- [`algorithm/v0_3/`](algorithm/v0_3/) — HWP-A 0.3 behavioural reference and adversarial audit. This is an executable research baseline, not an approved production detector.
- [`proof/hwp-c-1/`](proof/hwp-c-1/) — cryptographic core candidate and interoperability vectors.
- [`research/hwp/`](research/hwp/) — first-principles research foundation and earlier evidence chain.

Start product implementation with [`product/mac/README.md`](product/mac/README.md) and [`product/mac/plans/PLAN-01-FOUNDATION.md`](product/mac/plans/PLAN-01-FOUNDATION.md). Coding agents should also read [`AGENTS.md`](AGENTS.md).

## Reconciliation and permanent recovery

[`RECONCILIATION.md`](RECONCILIATION.md) documents what had reached GitHub, what previously failed to upload, which artifacts were byte-preserved, and the one preparation kernel whose source had to be explicitly reconstructed from preserved contracts.

`artifacts/source-of-truth/astra-history-2026-09-16.tar.xz` is a deterministic compressed recovery archive containing the complete generated A0.3, C1, v0, Mac-handoff and preparation material. Its SHA-256 is `4897634b27d11cbe251ca627cc256ce9d54a32e3646f3f21d5eac2bd08ea671d`; the embedded manifest gives per-file SHA-256/provenance. The direct working tree is the normal interface; the archive is the durable fallback.

## Scientific boundary

Writing-process evidence can support a falsifiable assurance claim, but it cannot give direct access to hidden cognition when qualifying composition and an adversarial process produce identical admissible observations. Cryptography binds exact bytes, evidence, execution, scope and trust assertions; it cannot make fabricated observations genuine. The repository therefore keeps observation authenticity, behavioural inference, proof verification, author/key association and product discipline as separate obligations.

No human participant detector model, independently admitted native Mac capture profile, production Human Writing Proof authority, or real proof issuance is established merely by this source reconciliation.
