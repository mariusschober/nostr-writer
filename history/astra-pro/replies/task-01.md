## Task 1

Published to main in mariusschober/nostr-writer, commit a29313c. The repository contains the algorithm specification, cryptographic architecture, adversarial validation framework, primary-source research, executable checks, and their results. I verified the branch update and confirmed that the uploaded experimental files exactly match the files executed locally.

The strongest defensible design is an authenticated writing-process record, a conservative composition detector, and an independently verifiable proof of the detector’s execution. None of those three can substitute for another.

The working name is Human Writing Provenance—HWP. It is a research foundation, not yet a validated certification system.

What the proof must actually establish

Your distinction between composition and transcription is the right one. It also exposes the hardest problem: a person can physically type every character without composing anything, while another person can compose an entire sentence mentally and type it without a single correction.

Consider two cases. In one, someone thinks through a sentence, pauses, types it, and revises a word. In another, someone follows a prepared script producing precisely the same observable actions. When the evidence is identical, a detector cannot recover the different hidden causes. A signature on that evidence cannot recover them either.

The specification formalizes this boundary:

$$ \text{false-certification rate} + \text{genuine-writing non-admission rate} \;\geq\; 1-\operatorname{TV}(P_{\text{composition}},P_{\text{attack}}) $$

Here, total variation measures how distinguishable the two observation distributions are. When an attack closely reproduces the observable distribution of genuine composition, accepting genuine writers also means accepting that attack frequently.

This does not establish that practical attackers can reproduce every useful signal. It establishes what the research needs to discover: which observations remain meaningfully different under deliberate imitation, and which independent capture mechanisms make those observations credible.

Consequently, HUMAN-WRITTEN must mean that a precisely identified contribution satisfies an explicitly defined, evaluated assurance policy. It cannot honestly mean mathematical certainty about an unobservable mental process against every possible adversary.

The algorithm: evaluate how writing decisions develop

The proposed algorithm is specified in 02-algorithm.md. Its central hypothesis is:

The useful signal lies in the relationships between writing, revision, navigation, and subsequent decisions—not merely in human-looking timing.

For example, a writer changes a premise in an earlier paragraph, revisits a later argument, removes an incompatible example, and rewrites the conclusion. That sequence contains relationships between actions and the evolving text. Arbitrarily inserting pauses and backspaces does not reproduce those relationships.

A sophisticated simulator might reproduce them. The algorithm therefore treats their usefulness as a hypothesis to test, not as an already-established human fingerprint.

The processing chain is:

Authenticated observations → exact text reconstruction → passage ancestry → process analysis → conservative acceptance.

First, reconstruct what actually happened. The record contains both input observations and actual text mutations. A keypress is not automatically a character insertion; an unexplained insertion is not automatically typing. Every mutation must connect to its input episode or an explicitly recorded transformation.

This matters particularly on touchscreen devices. Android input methods can commit text, maintain composing regions, and issue corrections rather than deliver one physical-key-style event per character. The design therefore uses explicit input capabilities and separate evaluation for different input modes—not a desktop classifier with missing mobile measurements filled in.

Second, preserve the ancestry of the text. Every inserted text unit receives an origin identity. Moving a paragraph, cutting and pasting within a document, undoing a deletion, or replacing individual words does not erase its ancestry. Imported text remains attributable to its source or marked unsupported. A verified passage imported from another document can carry its existing proof, without becoming the importing author’s original composition.

This prevents a major failure mode: pasting a paragraph, making enough superficial changes, and obtaining a fresh “human” label.

At the same time, ancestry must not become permanent contamination by an idea. Reading an AI-generated argument and independently composing new wording remains permissible. The algorithm evaluates the new composition episode rather than declaring everything influenced by that argument nonhuman.

Third, evaluate process evidence at the relevant passage. Candidate features include contextual pauses and bursts, revision distances, revisits to older text, restructuring, changes in writing behaviour, and dependencies between earlier revisions and later wording. The initial model should be interpretable; a more complex sequence model must demonstrate additional value on held-out adversarial tests.

Acceptance requires adequate evidence, an admitted input mode, valid capture, and sufficiently strong performance against the specified nonqualifying-process families. Missing or ambiguous evidence produces NOT PROVABLE.

There is no mandatory number of mistakes, pauses, or revisions. Such requirements would encourage people to perform the detector’s stereotype instead of writing naturally.

Passage-level provenance without false precision

Character-level origin bookkeeping is not character-level certainty about composition.

The system can know exactly where three newly inserted words came from while lacking enough behavioural evidence to classify that episode. It must preserve that distinction.

Likewise, a strong whole-document score cannot conceal an unsupported paragraph. Passage segmentation is fixed before acceptance is calculated, and a genuine introduction cannot supply “authenticity credit” to copied material elsewhere.

Quotations are handled through explicit scope. The author’s contribution can receive HUMAN-WRITTEN while quoted ranges remain separately identified. That is not equivalent to an unqualified assertion that every word in the document was composed by that author. The signed scope map makes the difference independently checkable.

Cryptographic proof: bind the evidence, not just the verdict

The architecture is in 03-proof-system.md.

The obvious implementation—“run a local classifier, then sign HUMAN-WRITTEN”—would be inadequate. Someone controlling that local software could fabricate the log or simply sign the desired result.

The proposed architecture separates four obligations.

Capture authenticity. An admissible capture source must bind the actual observed event sequence to the final document. A protected signing key is insufficient when untrusted software can ask it to sign any invented history. Likewise, attesting that an approved classifier ran does not establish that its input was genuine. This separation follows the attestation architecture’s distinction between evidence, appraisal, and the relying party’s trust decisions.

Private, tamper-evident commitments. Events are committed into an ordered, salted Merkle tree. A final capture receipt binds the session, event count, root, exact document digest, and provenance state. Secret random salts prevent simple guessing of low-entropy events from exposed commitments. Detailed events, intermediate drafts, and deleted wording remain private.

Correct computation on that same record. The proof must establish that the specified replay, provenance analysis, feature extraction, model, and acceptance policy all ran on the committed events—not on separately supplied favourable features.

Exact content and scope binding. The signed statement identifies the exact document bytes, certified ranges, exclusions, model and policy versions, capture assumptions, and execution evidence. Changing the document, scope, or policy invalidates that binding or requires a new proof.

The proposed detached envelope uses Ed25519 signatures, SHA-256 digests, constrained canonical serialization, and explicit separation between different types of signed messages. The specification also prevents circular dependencies between document hashes, execution proofs, signatures, and publication records.

Keeping the behavioural history local

The preferred privacy research target is zero-knowledge execution combined with authenticated capture.

An independent verifier would check that a private event record matches the captured commitment, reconstructs the exact document, preserves the declared passage ancestry, and passes the pinned algorithm—without receiving the private writing history.

Existing zero-knowledge virtual machines support proving execution of an identified program while exposing selected outputs. That supplies a relevant mechanism, but not an answer to whether the program’s input came from human writing.

The crucial distinction is:

A proof that some transcript passes the classifier is not a proof that the author performed that transcript.

The capture receipt and the computation proof must bind to the same transcript. Otherwise, zero knowledge would merely make fabricated evidence privately verifiable.

No HWP zero-knowledge implementation or performance benchmark has been produced here. Nor has this research established a generally available, protected end-to-end keyboard/touchscreen capture path. Those remain substantive requirements—not assumptions hidden beneath the cryptography.

Nostr, C2PA, and timestamps have separate jobs

I recommend making the HWP evidence bundle independent of its transport.

Nostr can associate a pseudonymous author with a proof, announce it, and replicate references. For long-form content, the proof must bind to the exact article version and event ID—not merely an address that may later resolve to an edited article. NIP-23 explicitly supports editable, addressable long-form content.

C2PA can carry an HWP assertion inside a compatible asset-provenance workflow. It should not become the source of the human-writing determination. Its manifests, assertions, and content bindings provide an interoperability framework; they do not remove the need to substantiate the underlying claim.

OpenTimestamps can optionally anchor the completed proof’s prior existence through Bitcoin. This establishes an existence bound, not who composed the text, how long composition took, or whether the captured observations were genuine. No per-keystroke blockchain transactions are needed.

Company-independent verification requires more than permanent signatures. The document, proof, verifier specification, required public keys, model and policy artifacts, and relevant attestation evidence must remain available. A hash can authenticate a surviving file; it cannot retrieve one that everyone has lost.

Decentralization can remove dependence on the original company. It cannot remove the need to justify trust in the observations.

What the research and executed checks establish

There is empirical reason to pursue process-based detection. A 2024 study reported 99% accuracy distinguishing authentic essays from transcribed essays using keystroke-derived features. Its reported confusion matrix nevertheless admitted two transcribed essays as authentic. That is encouraging evidence of signal—not evidence of resistance to an adaptive adversary.

There is also an important objective mismatch in some existing research: assisted paraphrasing is labelled nonqualifying in settings where your definition could permit genuine AI-informed composition. Importing those labels would risk building an anti-AI detector instead of the standard you intend.

I executed and re-executed 33 synthetic assertion checks covering selected commitment and signature mechanics, exact-byte handling, range gaps and overlaps, substitution attacks, and statistical calculations. The script, deterministic vectors, and results are committed. These are not human-writing detection trials, a complete protocol verifier, or a security audit.

Two calculations are especially consequential.

To support a one-sided 95% upper false-certification bound of 0.1%, observing zero failures would require 2,995 independent trials from the specified, fixed attack distribution. Thousands of windows from one writer do not meet that requirement, and the result would not cover arbitrary adaptive attacks.

Moreover, a 0.1% per-attempt success probability becomes approximately 63.2% probability of at least one success over 1,000 independent attempts. An open detector must therefore be evaluated against repeated attempts and deliberate optimization—not just random held-out examples. The executable results include both calculations.

No human participant data was collected, no detector was trained, and no certification profile was approved. The research policy therefore authorizes no HUMAN-WRITTEN certificates. This prevents the experimental cryptography from being mistaken for an empirically supported authorship claim.

The next decision-changing experiment is controlled genuine composition versus human transcription, including permitted AI-informed rewriting, matched timing/edit statistics, and adaptive staged histories. It should test whether the proposed relational signals retain useful discrimination under deliberate imitation.

My recommendation is to pursue that experiment before building the writing application or optimizing a zero-knowledge circuit. The intellectual foundation is now explicit enough to falsify: the project succeeds by finding defensible process evidence and authenticating its origin—not by attaching stronger cryptography to an uncertain verdict.
