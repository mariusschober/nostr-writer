# 3. Cryptographic proof and privacy architecture

Research draft · The cryptographic primitives are established; their proposed HWP composition is not audited. The supplied experiments test a deliberately small subset, not this entire protocol.

## 3.1 Design objective and trust boundary

An independent verifier should be able to check exact document binding, authenticated evidence binding, execution of an approved algorithm, and its policy-qualified conclusion without contacting the original company or seeing the detailed writing history.

Four signatures have different meanings: an author endorses a claim; a capture source attests observations; an evaluator attests an appraisal; a time witness attests receipt/existence. No role substitutes for the others. A quorum of witnesses to an invented log is still not a quorum of witnesses to human composition.

The critical trust anchor is an admissible source of observations outside the adversary's control. Possible future profiles include a tightly specified protected input path or an independent observer's signed capture appraisal. Each has different privacy, device-coverage, and trust consequences. A signed application build, a secure key store, an isolated classifier, or a remote attestation of code alone does not establish that the input events came from human composition.

For a protected-source profile, the evaluated boundary must bind actual event acquisition, text mutations, session continuity, and final-state commitment. A generic API that signs an arbitrary root provided by untrusted application code is insufficient. A secure classifier receiving untrusted precomputed features is also insufficient. RFC 9334 supplies the attestation-role model; RFC 9711 is a possible carrier for relevant attestation claims, not an HWP certification by itself [S07](06-sources.md#s07), [S08](06-sources.md#s08).

This research has not established a generally available protected end-to-end capture path for all requested desktop and touchscreen platforms. That is a specific unresolved engineering/security requirement, not an assumption that a commodity device already fulfils it.

## 3.2 Primitive profile and exact encoding

Proposed baseline: SHA-256 for content digests; Ed25519 for the detached HWP envelope; RFC 8785 JCS for constrained JSON objects; RFC 9162's ordered Merkle-tree shape for the event commitment [S09](06-sources.md#s09), [S10](06-sources.md#s10), [S11](06-sources.md#s11).

HWP JSON has ASCII object keys, valid Unicode scalar strings, booleans/null, arrays, objects, and integers in `[-(2^53-1), 2^53-1]`. Floating-point JSON numbers are forbidden. Larger counters use schema-constrained decimal strings. Duplicate keys, invalid UTF-8, lone surrogates, noncanonical serialization in signed canonical objects, unknown critical fields, and unsupported algorithms fail verification. No Unicode normalization occurs. The experiment's canonicalizer implements only this restricted domain, not general JCS.

Define an injective binary framing function:

```text
F(label, p1, ..., pk) =
    ASCII("HWP0") || U32BE(len(label_bytes)) || ASCII(label)
    || U32BE(k)
    || U64BE(len(p1)) || p1 || ... || U64BE(len(pk)) || pk
H_label(parts...) = SHA256(F(label, parts...))
```

Lengths are byte lengths. Encoders reject lengths that cannot fit the specified fields. Framing separates domains and argument boundaries. The format's security is inherited from its primitives only when implementations also enforce these encoding and binding rules.

For interchange with existing systems, the document digest is simply `SHA256(exact_document_bytes)`. A media type, byte length, and text/profile identifier are separately bound in the statement. A plain hash never excuses checking that the supplied bytes are the same object the claim describes.

## 3.3 Session and event commitments

A SessionStart object binds: protocol version, a fresh random session identifier, start challenge/nonce where required, initial document and lineage state, parent provenance references, capture public key, observation capabilities, clock description, capture profile digest, and the precommitted evaluation-plan digest. The plan identifies the release/model/policy used for the original certification attempt. Later retrospective evaluation is a new statement, not a rewrite of the original history.

Every private event includes its session and contiguous index. Commit each with a fresh secret 32-byte random salt:

```text
leaf_i = SHA256(0x00 || JCS({
    namespace: "hwp-log-0",
    session: session_id,
    index: i,
    salt: lowercase_hex(salt_i),
    event: event_i
}))
```

A leaf's event contains the actual observation/transaction, not only an author-supplied feature vector. The ordered tree uses `SHA256(0x01 || left || right)`, the RFC 9162 largest-power-of-two split, and `SHA256(empty)` for an empty tree. The final root is always accompanied by its leaf count. HWP salts and payloads are its own profile; HWP is not thereby a Certificate Transparency log.

Salts must remain private and independently unpredictable; public salt values would permit guessing low-entropy keystrokes. Deterministic salts in the test vectors are explicitly unsafe outside fixtures. Public intermediate document hashes can also leak candidate drafts, so intermediate state commitments stay inside the private event record or use independently hiding commitments.

The capture source periodically commits to the current ordered root/count and signs a final SessionEnd object binding: SessionStart digest, session ID, event root/count, final document digest/length, final lineage commitment, capability changes, gap status, and final sequence state. Signing must be atomic with freezing that observed state. After finalization, edits require a new session/version.

A Merkle root proves consistency with a committed record, not completeness of real-world observation. Completeness remains a capture claim. The final count and explicit end receipt prevent undetected truncation relative to that receipt; they do not prove that the collector was honest before signing it.

## 3.4 Online witnesses, forks, and freshness

Optional time witnesses issue unpredictable session challenges and signed receipts over a session ID, root, count, previous receipt digest, and declared receipt time. Required Merkle consistency proofs establish that later witnessed roots extend earlier ones. Witness verification requires externally trusted witness keys and a declared collusion assumption.

These receipts limit after-the-fact alteration and expose some equivocation when conflicting histories are compared. They do not rule out multiple unseen forks, undisclosed abandoned sessions, or an adaptive simulator operating in real time. A server nonce only establishes ordering for commitments that contain it; it does not prove that every committed keystroke occurred after the nonce unless an admissible collector enforces that claim.

A timestamp supplies a bound on existence, not an exact creation time or time spent thinking. Local clocks are not trusted wall-clock evidence. Offline-only histories lack independent live freshness unless the capture profile provides an evaluated alternative. They cannot silently receive an online witness assurance level.

Full decentralization makes global retry control difficult: attackers can use multiple pseudonyms, devices, or witnesses. Session counters and registration can add friction but are not proofs of one-person-one-attempt.

## 3.5 Acyclic statement and bundle structure

The binding graph must be acyclic:

`document/events -> capture end -> public statement -> computation evidence -> claim -> signatures -> timestamp/Nostr discovery`

The public statement binds at least:

- protocol and statement schema identifiers;
- exact document digest, byte length, media type, and text representation profile;
- session start/end identifiers and required capture receipt digests;
- event root/count and lineage commitment;
- full public range-map digest and the exact certified/excluded scope;
- replay, feature-extractor, model, calibration, segmentation, policy, and capture-profile digests;
- execution-proof mode and required proof-system/program identifiers;
- declared input strata, permitted transformations, optional author association, and claim limitations.

`statement_digest = H_statement(JCS(statement))`.

A computation proof or evaluator attestation binds that digest and the computed binary result. The claim then references the statement, the computation-evidence digests, and required supporting artifacts. The claim does not contain a hash of its own signatures. A proof does not depend on the hash of a claim that already contains that proof. Timestamps and transport announcements bind the completed envelope afterwards.

The downloadable bundle contains exact document bytes or an explicit separate artifact reference; canonical statement; complete range map; relevant capture receipts and attestation chains; computation evidence; required policy/model/program artifacts or archived content-addressed copies; signed claim envelope(s); and optional time/transport records. A content-addressed URL is not a substitute for retaining the bytes needed for verification.

A format-specific profile must enumerate allowed fields, bounds, critical extensions, signature roles, and required artifact sets. This draft describes those requirements but does not supply a completed production JSON Schema or certification wire registry. The experiment's miniature envelope is marked `fixture_only` and is not a conformant HUMAN-WRITTEN certificate.

## 3.6 Signature contract

Each detached envelope has `protected`, `payload`, and `signature`. The protected object includes protocol, algorithm identifier, signer role, and public key. For the baseline:

```text
message = F("signature", JCS(protected), JCS(payload))
signature = Ed25519.Sign(private_key, message)
```

This uses ordinary Ed25519, not an invented prehash variant. Verify with a maintained, strict implementation. The protected fields are authenticated; an algorithm, role, or key substitution must fail. A key identifier is a locator, never the authority for what a signer may claim.

A future schema enumerates real roles such as author, capture source, and evaluator. The test suite deliberately permits only `research_fixture`. Required signature sets and proof modes are chosen by the relying party's policy. Removing a required signature or selecting a weaker fallback must yield NOT PROVABLE.

The evidence bundle may include endorsements and trust-policy snapshots, but cannot authorize itself. The relying party supplies trusted policy roots and approved release digests independently. Copying an `approved: true` field or minting a new issuer key does not grant certification authority. Pseudonymous author keys can be optional when an approved evaluator attests anonymous composition; identified authorship requires an additional checked association.

## 3.7 Private independent verification

Three evidence modes must remain distinct:

**Disclosed transcript.** The verifier recomputes replay and classification from the complete record, while separately checking its capture origin. This is computationally inspectable but exposes drafts, timing, and deleted content. Selective openings alone do not establish an entire transcript's completeness or classifier result.

**Attested local computation.** A trusted, evaluated boundary runs the pinned algorithm over its bound observations and signs the output. Detailed history can remain local, but the relying party trusts that boundary and its appraisal infrastructure. Isolation of the classifier is not isolation of the input path.

**Zero-knowledge computation plus admissible capture.** This is the preferred research target for minimizing evaluator trust while preserving local history. The public input binds the statement digest, captured event root/count, document digest, lineage/range commitments, model/program/policy digests, and result. The private witness includes all events, salts, necessary intermediate states, and supporting private openings.

The proof relation must establish all of the following:

```text
R(public, private) =
    committed_events_match_public_root_and_count
    AND all_replay_transitions_are_valid
    AND final_bytes_hash_to_public_document_digest
    AND lineage_and_complete_range_map_match_the_statement
    AND pinned_feature_extraction_runs_on_those_same_events
    AND pinned_model_and_policy_execute_on_those_features
    AND aggregate_result_equals_the_public_binary_result
```

The verifier separately validates admissible capture receipts and confirms that their root/count/session/document bindings are exactly the values used in the proof. Signature verification may occur inside or outside the circuit; neither arrangement permits a root substitution. All external preprocessing must either be recomputed in the proof or be supported by an accepted attestation bound to its input and output.

A zkVM can prove execution of a specified program while exposing selected public outputs [S20](06-sources.md#s20). That capability does not prove the program's inputs correspond to human events. HWP must never implement only `there exists a transcript that passes` and call that human-writing proof.

No zero-knowledge system, circuit, proving time, memory budget, or mobile feasibility has been evaluated for HWP. Transparent proof systems and succinct systems have different setup/performance assumptions. Selection requires actual measurement and review. A development/mock receipt must always be rejected outside tests. Remote proof generation also changes privacy if it receives the witness.

## 3.8 Verification order and failure behaviour

A conforming verifier first applies resource and schema limits; checks exact bytes and requested scope; resolves the externally approved policy; authenticates required signatures and capture evidence; verifies commitments and proof-public-input equality; checks pinned program/model/profile identities; verifies execution and local coverage; and finally returns the binary result. Unknown versions, missing artifacts, stale required trust evidence, or incompatible scope yield NOT PROVABLE.

Malformed proof parsing must not trigger arbitrary code execution, arbitrary network fetching, archive path traversal, unbounded decompression, or proof-verification denial of service. An offline verifier treats bundle URLs as untrusted locators and never automatically executes included programs.

Under explicitly stated assumptions, a failure decomposition can be bounded by a union bound over binding, capture, execution, classification, and scope failures. These terms are not independent and must not be multiplied. A measured classification error on a test distribution does not bound an untested adaptive adversary or an unmeasured capture failure.

## 3.9 Local privacy and durability

Retain detailed events, salts, deleted wording, biometric timing, and optional personalization locally in an encrypted archive. Publish the minimum sufficient statement and proof. Even a document digest may reveal which known text is involved; pseudonyms, hardware attestation identifiers, issuance times, and exclusion maps can also correlate activity. A separate blinded-document profile is needed for private documents whose public hashes would be revealing.

A proof can remain verifiable after the witness is deleted, but new model-based re-evaluation may then be impossible. Preserve that tradeoff. Deletion of local records cannot revoke already published data or fingerprints.

Long-term validity requires archived verifier specifications/program identifiers, model and policy versions, public keys, attestation endorsements, issuance-time status evidence, and any final timestamp proof. Cryptographic validity as of issuance and acceptance under today's trust policy are different questions. An offline package cannot prove that no later compromise or revocation occurred. No signature algorithm is promised secure forever; renewal before obsolescence follows the evidence-renewal principle in RFC 4998 [S19](06-sources.md#s19).
