## Task 4

Published HWP-C/1 — Human Writing Proof, Cryptographic Core 1, release candidate 1.0.0-candidate.1, to main in commit c53e794. All 22 files are published, including executable source, schemas, tests and interoperability vectors. I verified every uploaded file’s Git blob identity against the tested local package and confirmed the branch update. The behavioural algorithm and earlier research remain unchanged.

Complete specification · Package and implementation guide · Download the complete packageReader

The construction binds evidence, execution and scope—not merely an author’s assertion that a document is human-written. Its private verification mode is explicitly attestation-based. It does not disguise trust in a recorder or evaluator as a mathematical proof of cognition.

What a Human Writing Proof establishes

A proof binds the exact document bytes to one precisely identified positive HWP assessment. That assessment identifies the captured records, the specific target record, the algorithm specification, executable, model, decision policy, evidence adapter, output contract and certified ranges.

Those are immutable content references, not mutable model names, repository branches or service URLs. Changing the document, threshold, evidence source, scope or interpretation requires a new assessment and new proof. The public verifier accepts only the signed result HUMAN-WRITTEN; a failed or nonqualifying assessment receives no HWP. Verification failure returns NO-VALID-HWP with no inference that the document is AI-generated.

The evidence chain separates responsibilities:

Capture authority. An admitted observation source signs the start of a session and, when complete, its finalized event commitment and event count. Its responsibility is to bind the actual observed process—not to sign an arbitrary transcript supplied by the writer.

Evaluator. An independently authorized evaluator executes the exact approved HWP release on those same captured observations and signs the statement only when its exact scope qualifies. A configurable quorum can require multiple distinct evaluator keys, but distinct keys are not assumed to mean independent operators.

Author, optionally. A separate author key can endorse the statement. That signature establishes a key association; it cannot substitute for capture or evaluation.

This distinction follows the separation between attestation evidence, appraisal and relying-party trust in the IETF attestation architecture. A correctly verified signature does not, by itself, establish that its signer’s real-world assertion is true.

The cryptographic construction

The implementation uses deterministic CBOR, COSE_Sign1, Ed25519 and SHA-256, rather than inventing a signature scheme. COSE supplies the signed-envelope structure; the profile uses the fully specified Ed25519 identifier -19 registered by RFC 9864, not the older polymorphic identifier. Exact protected headers, authenticated context, public-key encoding and accepted signature encodings are fixed in the specification.

The reference rejects alternative encodings that could create implementation disagreement: duplicate map keys, noncanonical serialization, unknown fields, unsupported algorithms, invalid Unicode, trailing data and ambiguous numeric types. It also checks canonical Ed25519 points and scalar values rather than leaving those acceptance details entirely to whichever cryptographic library an engineer selects.

Private events are committed into an ordered, independently salted Merkle tree. Each leaf binds its event bytes, sequence index, secret random salt and the exact signed session start. The finalized receipt binds both the root and the number of events. The package implements root calculation, inclusion proofs, append-only consistency proofs and complete transcript opening.

This supplies an important but bounded guarantee: altering, rearranging or truncating a history after an honest capture source has committed it is detectable. It cannot detect a history that a dishonest source fabricated before signing. Nor can it correct a behavioural algorithm that admits a sophisticated imitation. Those assumptions are explicit in the security contract.

The proof bundle is a bounded collection of content-addressed objects. Verification performs no automatic network retrieval or execution of bundled programs. A proof also cannot approve itself: the relying party supplies a separately selected trust policy identifying acceptable releases, capture authorities, evaluators, quorum requirements and denied keys or artifacts.

Privacy without overstating independence

Two verification modes are implemented.

Attested private verification allows detailed writing history to remain local. The public proof contains commitments and authorized capture/evaluation statements rather than raw drafts, deleted passages and keystroke timings. An independent verifier can check those statements offline without the original company’s infrastructure.

The qualification matters: keeping evaluation local is credible only when the relying party has a defensible basis for trusting that local execution and observation boundary. Ordinary software fully controlled by an adversarial writer does not automatically become an admissible evaluator merely because it can sign its output.

Disclosed recomputation additionally opens the complete committed histories and runs an independently installed implementation of the exact HWP release. The verifier checks the recomputed document, scope, lineage and positive result against the signed statement. It never downloads and executes a program merely because the proof contains a reference to it. An existing private proof can also undergo this stronger voluntary audit without changing its original signed statement or proof identity.

Selective event disclosure is supported for inspection, but is not misrepresented as complete algorithm verification. Proving that a few events belong to a committed history does not prove that the entire history qualifies.

No zero-knowledge proof suite is activated in this release. The package specifies the required public inputs, private witness, computation relation and activation conditions for a future suite. It does not label a placeholder, development receipt or generic zkVM recommendation an implemented proof. Unknown ZK modes fail rather than falling back to weaker verification.

That leaves a complete attestation-based core available now, while preserving the requirement that any future ZK construction prove execution on the same authenticated history, not simply the existence of some transcript that passes.

Passage provenance and author association

The public scope is a complete partition of the exact UTF-8 document. Every range is explicitly observed, inherited from a verified parent proof, or excluded. Boundaries are byte offsets aligned to Unicode scalar boundaries; normalization or newline conversion changes the bound document.

A selected-range proof cannot be presented as a whole-document proof. Inherited wording must match the parent’s exact certified bytes and is permitted only under the distinct wording-origin claim. It cannot become evidence that the recipient freshly composed the passage or assembled the resulting argument.

I also resolved a subtle target ambiguity: two captured records can end with identical text. The statement therefore names the exact target capture, rather than asking implementations to infer the target by matching the final document.

For an attributed proof, the author key is associated at session start, signs participation in that session and later endorses the final statement. That prevents an anonymous capture from being retrospectively relabelled simply by attaching an author signature.

An optional trusted identity assertion can associate that key controller with an identified subject. Its meaning remains narrow: identity associated with the key is not independent proof of who physically typed. The protocol does not silently turn key ownership into verified physical authorship.

Verification decades later

The format separates three questions that are often conflated:

Do the original bytes and signatures verify? Was the proof already in existence by a particular time? Is its trust policy acceptable now—or justified for a historical assessment?

The package implements detached RFC 3161 timestamp verification, including the exact message imprint, external timestamp-authority trust anchors, policy identifiers, optional request nonce, signature and certificate-chain checks. It reports the timestamp’s declared accuracy and explicitly reports that revocation was not assessed. The timestamp is supporting existence evidence, not evidence of when composition began or how long a human spent writing.

Long-term preservation requires retaining the actual document, proof objects, required release artifacts, verification specifications and trust evidence. A content hash cannot recover a file that has disappeared. Old assessments retain their original model, scope and interpretation; a later assessment produces a new proof rather than rewriting the old one.

No signature algorithm is promised secure forever. The archival specification requires renewal before the relevant cryptographic protection becomes unsafe, using established evidence-record principles. It includes an executable SHA-512 inventory of actual archived bytes as input to renewal, but does not claim that this helper is a complete RFC 4998 evidence-renewal engine. Renewal must preserve the earlier evidence chain; hashing an already-untrustworthy digest cannot repair its history.

The full procedure is in ARCHIVAL.md.

Nostr remains optional. The interoperability specification defines discovery, exact article-version binding and optional association between a Nostr key and the HWP author key. C2PA, OpenTimestamps and transparency receipts have separately defined roles. None is allowed to replace a required HWP observation or evaluation statement. These adapter specifications are published; their execution is not included in the tested implementation.

What was actually tested

All 95 tests pass, with zero failures, errors or skips. I then extracted the final ZIP into a clean directory and reran the suite successfully. The tests cover signature and encoding attacks, document substitution, changed scopes, unsupported execution modes, capture participation, evaluator quorum, inherited provenance, incomplete disclosure, exact recomputation outputs and RFC 3161 token validation.

A separately written JavaScript checker reproduced the CBOR encodings, content hashes, COSE signatures and Merkle vectors. Ed25519 signature cases were also cross-checked with libsodium. The interchange vectors were byte-identical across two separate Python processes. This is interoperability evidence—not a second complete HWP verifier or an independent security audit.

The published package includes the normative specification, CDDL schema, Python creation/verification library, timestamp adapter, security and archival contracts, HWP-A/0.3 binding specification, test sources, vector generator, JavaScript checker and recorded results.

No real Human Writing Proof was issued. The fixtures use public synthetic keys and synthetic evaluator outputs. There is no newly implemented behavioural detector, trusted native capture path, ZK prover, live revocation service or complete archival-renewal engine in this deliverable. Those boundaries are recorded in both the implementation guide and machine-readable results.

The resulting foundation is an executable, versioned proof protocol with explicit trust and privacy semantics—not merely a signed badge. The next gate should be an independent cryptographic review of this pinned candidate before real-world issuance.
