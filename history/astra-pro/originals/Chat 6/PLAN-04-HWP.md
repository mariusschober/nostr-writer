# PLAN 04 — real native HWP producer and independent verification

## Outcome and entry

Implement the complete frozen Human Writing Protocol path natively and expose an honest proof experience. Own **M22–M29**. Read HWP.md, INPUTS, SECURITY, frozen SPECIFICATION/docs/BINDING/OUTPUT/CONFORMANCE, all hwp0 runtime modules and the exact frozen vectors. Inspect Stage03's native capability findings. This stage must not redesign or retrain the behavioural algorithm, silently relax capture admission, or present synthetic positives as real certification.

## Port the actual computation

Implement WriterHWP and the native `hwp-verify` CLI. Reproduce the frozen Python semantics, not just equivalent-looking statistical concepts. Port telemetry validation, shared event ordering, one-use causes/deliveries, exact source replay, ancestry, support checks, all required evidence views, the179 fixed-point features, every model branch validation rule, threshold comparison, source veto, scope exclusions and exact output commitments. Follow the frozen joined binding rather than the obsolete HWP-C callback tests.

Python integer arithmetic is not Swift Int arithmetic. Use the selected BigInt library for products/intermediates where the frozen program is unbounded, explicit floor division for negative operands, checked conversions at native boundaries, prescribed integer quantiles and no floating approximation to produce a decision. Lexical ordering, CBOR byte comparison and exact UTF-8 identity must not use Swift's canonical-equivalence String comparison. No locale-dependent formatting, Foundation dictionary iteration, wall clock or random value may enter deterministic assessment.

Port strict deterministic CBOR/COSE Ed25519 (-19), content-addressed objects, hashes, salted ordered Merkle roots and both inclusion/consistency verification. CryptoKit's algorithm availability is not proof its accepted encodings exactly match the frozen suite: enforce the frozen canonical point/subgroup/scalar rules and cross-check negative vectors. Do not hand-roll new crypto primitives. Use vetted implementations and explicit structural validation; no hidden algorithm fallback or detached signature over the wrong payload.

Implement exact captured-record reconstruction, target selection, precommitted operational release, complete scope map, origin-based parent mapping, deterministic assessment commitment and private disclosure transport. The producer must refuse positive proof creation when any selected span, release, capture profile, mode, key grant or independent policy condition fails. A self-generated local key and app signature cannot make an app-owned capture profile evaluated. Never put fixture keys or a force-approve switch in the distributable target.

## Verifier interfaces and admission

Implement both V attested verification and R disclosed recomputation as actual, separately identified modes. V checks admitted assertions; R opens and recomputes the exact underlying algorithm using the installed native implementation. An R request cannot degrade to V when history or recomputation is unavailable. Evidence imported from a file never authorizes its own policy or executable. The caller selects exact trusted policy/release roots independently; unknown or unsupported objects fail closed with diagnostics.

Ship the frozen empty production trust policy. UI result for this first release is normally NOT PROVABLE: the current model/capture path is not empirically approved. This is correct functionality, not permission to omit the pipeline. In an isolated conformance target run complete synthetic P→V/R round trips, require exact vector bytes, and mark all public outcomes TEST-ONLY/NOT PROVABLE. In production builds prevent importing fixture releases/capture authorities as a shortcut to an authentic badge.

Implement empirical-release admission checks already frozen in v0, including operational-candidate identity and later approval evidence binding. Do not fabricate empirical reports. A future legitimately approved release may support future captures; do not retrospectively replace a run's precommitted release. Keep policy history/assessment time explicit. A locally imported present-day trust policy is not evidence of historical trust or absence of revocation. The app must not claim cryptography lasts forever.

## Product interaction and durable evidence

Build UX U04/U05: origin inspector, check progress/cancellation, detailed reasons, exact revision/scope, disclosure mode and selected trust policy. No real-time human probability. Positive states distinguish whole document and contribution. If editing proceeds during an asynchronous check, keep its result attached to that old SourceSnapshot and mark it stale in the current document. Verify before offering “Export Human Writing Proof”; NOT PROVABLE enables no HWP signature.

Retain private detailed evidence locally in encrypted storage by default, following consent. Publish nothing merely because a check completes. Allow export/import of exact source+public proof and optional stronger private evidence via DATA's encrypted transport. Preview what disclosure reveals: deleted drafts, timings, origin links and possible identity correlations. Partial Merkle openings remain inspections, not whole-algorithm verification. Do not introduce a nominal ZK toggle or remote proof service.

Separate author endorsement and capture/evaluator authority keys. Optional Nostr association is integrated later; never reinterpret secp256k1 bytes as Ed25519 keys. Identity can be chosen anonymously initially; adding an endorsement after capture cannot invent participation at its start. A copy of source text or rendered PDF does not acquire the original exact proof automatically.

## Conformance and adversarial evidence

Create native fixtures by reading the frozen external vector bytes, not by changing Python outputs. Run every applicable positive and negative canonical/proof case through native code and compare full normalized results. Generate native objects and have Python/Node check them, and vice versa. Replay the signed-paste/dishonest-evaluator fixture: V admits the assertion only under the isolated test policy; R rejects it. That boundary must remain visible, not patched away by treating V as R.

Run substitution attacks on document, source record, target, profile, model, threshold, exclusions, role key, release purpose, quorum, disclosure chunk order/count, parent range and current revision. Run Unicode-normalization and numeric overflow tests, resource exhaustion caps and cancellation. Fuzz parsers in bounded subprocesses. Release verifier must not automatically fetch URLs, unzip unsafe paths or execute archive code.

Measure full deterministic evaluation on representative synthetic small/large histories off the main thread. Test cancellation immediately frees UI and stops worker growth. Where the frozen complexity is expensive, optimize with differential conformance tests, not different windows/features. A performance cap can return NOT PROVABLE, never a simplified accepting computation.

## Exit

M22–M29 require actual complete native P/V/R and cross-language parity, not a permanent stub returning NP. The distributable app truthfully keeps certification unavailable under the current empty approval set, while its verified implementation can process future genuinely admissible evidence. Report separately: algorithm conformance, cryptographic conformance, observed Mac capabilities and still-unmeasured empirical accuracy. No scientific conclusion is inferred from green unit tests.

## Execution contract

You are the implementing coding agent, not a planning agent. Read this PLAN and the named contracts in the current checkout, inspect current HEAD, then implement and verify the assigned stage. Do not return another roadmap. Preserve unrelated changes and all frozen protocol bytes. Resolve routine API and implementation details yourself; a discovered platform limitation must be handled honestly, not by weakening provenance or claiming an unrun test passed.

Work on a stage branch from the predecessor's accepted commit. Run relevant earlier tests as well as the new tests. Keep deterministic tests independent of live relays, Apple accounts and real author keys. Native UI acceptance requires actual macOS runs; Linux results are not Mac results. Use synthetic documents and test keys only. Commit coherent source, tests, resources and reports; do not commit build products, credentials or private writing.

Write `product/mac/evidence/STAGE-04.md` with input/output commits, changed contracts, exact commands and results, screenshots/inspection where applicable, every assigned acceptance ID, remaining genuine external blockers and next-stage state. Include a machine-readable `STAGE-04.json` mapping assigned IDs to PASS/FAIL/BLOCKED and evidence paths. No required BLOCKED/FAIL row is completion. Do not edit the acceptance matrix to excuse missing work. The next stage must be able to start from the report and repository without reconstructing this conversation.
