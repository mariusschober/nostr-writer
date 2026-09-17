# Security, inference and falsification contract

This is an adversarial reconciliation by the same assistant, not an independent third-party security audit. The protocol freezes testable rules and trust boundaries. It does not assert that its observers or behavioural model have already earned production admission.

## Assets, adversaries and assumptions

Protect the exact document and selected claim, source/parent ancestry, event order and completeness relative to an admitted capture, chosen release/model/threshold, evaluator mode, author association, and historical interpretation. Raw histories, deleted text and salts are sensitive private witnesses. Availability and future cryptographic strength are distinct assets requiring archival maintenance.

Adversaries may know every feature, threshold and implementation; generate or adapt simulated histories; physically type or transcribe; relay model output; use a second screen or memory; inject or automate events; transplant valid source proofs; choose scopes; submit malformed encodings; reuse observations; change policies; try many times; steal keys; or control an evaluator/capture source. Explicitly separate attacks *within* a release's promised trusted boundary from compromise of an authority on which the verifier relies. The latter can invalidate the conditional claim without breaking a hash or signature.

Core primitive assumptions are collision/second-preimage resistance and signature unforgeability for the required lifetime, correct parsing/equality checks, and correct installed verifier execution. Capture assumptions are truthful observed source labels, complete in-document delivery/mutation capture, faithful clock/order, actual independent native delivery attribution, non-generated admitted motor decoding, prospective release commitment and single finalization. Evaluator assumptions are correct execution and truthful appraisals under the exact release. Curator assumptions are honest empirical/profile review and externally selected trust inputs. Distinct keys do not prove these parties are independent.

The end-to-end accepted proposition is conditional on those assumptions and on the release's measured operating domain. A proof establishes who asserted what about which exact evidence and result. It does not convert unmeasured hypotheses into cryptographic theorems.

## Attack dispositions

| Attack | Enforced rule or counterexample | Remaining boundary |
|---|---|---|
| Document substitution or newline/Unicode normalization | Exact signed Ref and separately supplied document equality; no normalization | Rendering/format exports are unclaimed |
| Scope shrinking, gap, split scalar, all-excluded proof | Complete maximal UTF-8 partition and nonvacuity; underlying scores unchanged | Choosing a subset is allowed only with explicit selected-range semantics and tested false-scalar endpoint |
| Favourable target chosen among equal final texts | Exact signed target_capture and signed capture-end.document | No inference of identity from a matching text |
| Alternative model/threshold after observing process | Target capture-start commits the exact release; all artifact/dossier bindings checked | A dishonest collector can lie about prospective timing; no wall-clock guarantee |
| Fabrication of delivery fields or timestamps | Actual native observations required; strict total order and one-use causality; source appraisal | Echoing a supplied payload into both sides is not native observation; a dishonest admitted source can fabricate a structurally valid history |
| Retrospective event insertion, reorder, truncation after commitment | Start/index/salt-bound ordered Merkle root, exact finalized count and full openings | A collector that signs invented data before commitment can defeat this premise |
| Reusing valid history as a new session | Leaves bind exact signed start; unique session declaration and precommitted plan | Re-verifying the same old proof is valid. Hidden duplicate real-time capture or undisclosed forks require source integrity/external comparison |
| Copying a valid paragraph and claiming fresh composition | Occurrence/root test; wording-origin must be explicit | Wording ancestry does not certify new assembly logic |
| Same bytes from a different parent proof | Actual source capture and root equality plus literal certified parent coverage | Hidden sources of newly typed wording remain a behavioural inference |
| Self-approved record/model/fixture | Policy pin supplied independently; exact profile/release refs; conformance stage cannot qualify under production | A relying party deliberately trusting dishonest curators still has a dishonest trust premise |
| Approval or disclosure-mode downgrade | Exact signed mode, all required signatures and policy gates; no ZK/mock fallback | A separately issued, differently signed attested statement is a different proof and claims a different execution assurance |
| Author attached retrospectively | Target subject signed at start, participation and final endorsement required | Key association is not physical-person identity or nontransferable proof of who typed |
| Forged statistics through omitted attempts | Frozen complete ledgers, campaign max, adverse ambiguity, independent-block checks | Actual task labels and independence cannot be established by ledger identifiers alone |
| Many adaptively optimized attempts | Required B=1/B=100 campaign evaluation, full-budget accounting | No unconditional bound for unlimited retries, shared adaptive state or distribution shift |
| Flooding refs, deeply nested data, hidden invalid tree branches | Common size/depth/count limits, strict canonical parse, all model branches validated, no automatic network/code | Finite limits are not a benchmark of worst-case operational cost |
| Company disappearance | Complete public object/source closure, pinned semantics, explicit archival evidence inventory | No hash retrieves data that all custodians lost |
| Later key compromise or obsolete algorithms | Current/as-of policy separation, optional timestamp and timely evidence renewal | Offline files do not reveal future revocations; late renewal cannot restore lost historical assurance |

## Guarantees that do follow

**Exact binding.** If the selected digest and signature schemes remain secure and the verifier is correct, altering an authenticated document, scope, release, start, end, root/count, parent reference, lineage commitment or required endorsement without a corresponding authorized new assertion is rejected.

**No favourable neighbourhood choice.** Scope selection never changes the algorithm's evidence units. A positive whole-document result implies every required scalar satisfies the same pinned process decision; global averages cannot override an unsupported span. This does not prove the cognitive cause of a short insertion hidden in a supported neighbourhood.

**Positive-only public meaning.** Neither absent proof, invalid proof, test-only proof nor non-admission produces an AI-written label. There is no negative result type to sign as HWP.

**Deterministic compatibility.** Given identical supported observations, exact exported model/release, scope, policy and optional disclosures, conforming implementations have the same defined computation and output semantics. Cross-language fixtures test the public verifier and binding primitives. They are not empirical accuracy estimates or a proof that every implementation is bug-free.

**Historical isolation.** New weights or evidence do not mutate an old statement's meaning. Changing the interpretation requires a new definition and new statement; a newer policy may refuse an older proof without rewriting its original bytes.

## Guarantees that do not follow

For genuine observation distribution P and attack distribution Q, any acceptance region A obeys `Q(A) >= P(A)-TV(P,Q)`. With identical admissible observations, deterministic or randomized classification cannot recover a different hidden cause. With a deterministic feature map F, `TV(F#P,F#Q) <= TV(P,Q)`; a collision in the current feature representation cannot be resolved by deeper trees on those same features.

The exact meaningful-text feature collision remains in the test suite. A conformance fixture with a deliberately lying admitted evaluator can produce a cryptographically valid attested assertion over a pasted trace; disclosed recomputation rejects it. This regression must remain visible. “Fixing” it by claiming that signature verification proves evaluator honesty would be a security regression, not an improvement. Disclosed recomputation still cannot distinguish a fabricated but admitted trace that passes the actual detector from the same trace honestly observed.

Likewise, local timing regularity does not identify mechanical input, revisions do not prove reasoning, and a challenge response would not retrospectively authenticate all earlier wording. No camera, audio, unrelated computer activity, or secret liveness challenge is implicitly required by this version.

## Empirical tests that can disqualify a release

Run paired human composition and human transcription under controlled source/device/skill conditions, including genuine AI-informed composition and memorized source text. Add timing-matched and topology-matched staged histories; meaningful revision simulations; tiny mixed-origin insertions at every boundary; exact feature collisions; held-out languages and device decoders; legitimate fluent and interrupted writers; source/controller injection; malicious appraisals; parameter/policy swaps; withheld attempts and many-query campaigns.

Measure complete-document coverage and any-false-scalar campaign admission with prespecified independent blocks. Keep ambiguity and operational failures visible. Test the actual advertised capture boundary rather than granting the attacker laboratory admission and reporting that as a hardware attack result. A fixed-distribution confidence bound is not a deployment posterior probability; prevalence and adversarial distribution shifts matter. A false-certification target that leaves no useful coverage must be reported as such.

The normative wire/replay bridge can be frozen and falsified now. Behavioural separability, actual native capture integrity, real-world privacy/latency, and useful risk/coverage remain unmeasured. This package grants no empirical release approval.
