# Security contract, attacks and limits

This is a cryptographic binding and evidence-authentication protocol, not a new human-composition test. A successful check is conditional on the externally selected policy and its admitted observers/evaluators. This document is normative for interpreting HWP-C/1.

## Security experiments and assumptions

Assume the verifier receives the expected document and policy pin independently of an adversarial package. Assume canonical parsers and scope checks implement the specification; Ed25519 remains unforgeable for uncompromised role keys; SHA-256 remains collision/second-preimage resistant for these objects; salts are secret independent 256-bit values; required capture sources honestly record the appraised observation boundary; and the required evaluator quorum honestly executes the approved release on that same captured input. Then changing the document, selected range, release, target capture, history root, declared subject or appraisal result while retaining acceptance requires breaking at least one of those assumptions or obtaining a new authorized assertion. This is a reduction argument by following signed references, not a machine-checked protocol proof.

A false human-composition claim can also arise when the approved behavioural algorithm admits a nonqualifying process. Let B denote binding/verification failure, C capture failure, E evaluator failure, A algorithmic false admission and S scope/interpretation failure. Any overall false claim is contained in B∪C∪E∪A∪S under the model. A union bound applies if defensible bounds for those events exist; their probabilities must not be multiplied as though independent. No empirical bounds for C, E, A or S are supplied here. The cryptographic tests do not estimate them.

A verifier cannot establish the truth of an external policy simply by receiving its hash from the same adversary who supplied the proof. A policy pin is an input trust decision, not a magical approval mechanism. Different relying parties may accept different issuer sets or historical policy snapshots. A bundle's extra `approved:true`, certificate, release label or key cannot change the selected policy.

## What fabricated-history detection actually means

After an honest capture source has frozen and signed a root/count bound to a start, altered event bytes, indices, order, salts, truncation or extension cannot match that end receipt without breaking the commitments or obtaining a new authorized receipt. Substituting an authentic root with favourable model features is prevented by the evaluator's complete output/input binding and, in disclosed mode, recomputation. The final count and explicit terminal event prevent prefix acceptance as the finalized transcript.

A collector that signs arbitrary caller-supplied roots is not an honest capture source for this purpose. A malicious collector can invent a history and sign it correctly; a compromised evaluator can endorse it. No signature format can distinguish that situation from an honest observation using only the signatures. A physically real person can also transcribe a prepared script; origin authentication does not solve the behavioural distinction. Therefore the protocol never claims unconditional detection of every fabricated history.

The capture profile must specify acquisition boundary, source classification, trusted normalization, loss/gap detection, decoder/IME handling, finalization, session uniqueness, protected key use, and adversary capabilities. An application code signature, TLS connection or key stored in secure hardware does not by itself supply these properties. Separate role keys are enforced; separate operators or failure domains are not inferred from different public keys. A quorum only improves assurance to the extent the relying policy has justified independence and corruption assumptions.

## Attack and response matrix

| Attack | Required outcome or explicit boundary |
|---|---|
| Change one document byte; Unicode-normalize; alter CRLF | Exact expected-document comparison and raw hash reference fail |
| Change excluded/selected offsets or origins | New scope/statement bytes require new appraisals and author endorsement |
| Choose a different target among equal final texts | Required target_capture Ref and evaluator output tuple prevent ambiguity |
| Substitute program, model, threshold policy, adapter or scope contract | Exact release and artifact references no longer match the externally approved release |
| Reinterpret COSE -8 as -19, alter key or external AAD | Strict protected-header/key profile or signature verification fails |
| Small/mixed-order public key or R; S+L malleability | Canonical prime-order point/scalar checks reject before acceptance |
| Reuse one key as two evaluator votes | Duplicate signer rejection; quorum counts distinct admitted keys |
| Strip an appraisal below quorum or remove required author consent | Verification fails; no weaker fallback |
| Drop surplus optional evidence | Core claim may remain valid if all selected-policy requirements still hold; whole bundle hash changes. Pin the complete bundle where exact packaging matters |
| Relabel an anonymous capture with an author key later | Subject was null at start; observed-origin subject equality fails |
| Attach a real identity to someone else's key | Trusted identity assertion must bind exact subject key; controller identity is not physical typist identity |
| Replay the same valid proof for its unchanged document | Allowed and necessary for archival verification; it is not a new composition assertion |
| Reuse old roots as a newly observed session | Fresh session/start binding must be enforced by admitted capture/evaluator; unseen previous sessions cannot be globally ruled out offline |
| Two conflicting ends for one session | Detected when encountered within verified dependency graph; no claim to discover an unseen fork |
| Pretend a Merkle opening proves complete execution | Selective openings authenticate only their events; disclosed mode requires the entire transcript and installed release runner |
| Supply a runner, trust roots or URL in the bundle | Never automatically loaded, executed, trusted or fetched |
| Provide a dev/mock ZK receipt | No ZK mode is activated; unknown modes fail closed |
| Claim a local timestamp proves pre-compromise issuance | No trusted clock is inferred. Independent timestamp plus appropriate status evidence is required |
| Omit later revocation evidence from an old archive | Old offline snapshot remains explicitly historical/knowledge-limited, not current-good status |

## Privacy leakage and selective opening

Secret salted leaves hide low-entropy event guesses against an observer who sees only the commitments under standard hash-hiding assumptions for random salts. They do not hide event count, capture/evaluator identity, selected range shape, the exact public document hash, or optional author associations. Once a leaf salt and event are disclosed, that leaf's confidentiality is gone. Salt disclosure for one leaf must not derive any other salt. The lineage salt must be separate. Randomness failures and seed reuse are security failures, not alternative profiles.

Public document bytes are included by this core, so it does not promise document confidentiality. A future private-document commitment profile would need different scope and disclosure semantics. Do not publish an unsalted private-document digest under the assumption it prevents known-document guessing. Hardware identifiers and stable keys can link writers even when no legal name is supplied.

For voluntary audit, disclose exact openings and a lineage salt through an appropriate confidential channel; public proof objects never need to contain them. This package does not design a local encryption/password-recovery system. Deleting the private witness does not invalidate an attested proof, but prevents later disclosed recomputation unless a copy survives. A disclosed-v1 proof has an explicit witness dependency; public storage of the witness should be chosen knowingly.

## Implementation hardening and residual review

No network access or dynamic code loading occurs in core verification. Bundles are flat maps of raw bytes, avoiding archive traversal and decompression. Bound canonical CBOR nesting, total items, object count, document size, signature work, proof graph, and private disclosure size before large allocations. One proof package is capped at64MiB; an individual document at1MiB. Private disclosed event bytes plus salts are capped at64MiB, with at most1,000,000 aggregate events. A streaming implementation must enforce these before allocating untrusted structures.

The reference uses cryptography/OpenSSL for private signing and standard Ed25519 verification. A small public-only group-arithmetic routine narrows A and R to canonical nonidentity prime-order points; this routine requires independent review before a high-stakes deployment. It does not implement secret-key arithmetic. Ed25519 verification interoperability has historically depended on handling noncanonical/small-order encodings, so the accepted subset is explicit rather than backend-dependent. Signature vectors are cross-checked with another backend; that is not a formal audit.

Core parse/cryptographic failures return NO-VALID-HWP with no authorship inference. An installed evaluator callback is trusted executable code supplied by the relying party; its own crash or timeout must never be converted into acceptance. Run it with a separately enforced resource budget. The reference does not sandbox arbitrary callbacks because it never accepts one from the package.
