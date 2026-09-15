# 1. Foundation: what a human-writing proof must mean

Research draft · 2026-09-15 · Proposed protocol name: Human Writing Provenance (HWP). This is a working name, not an assigned standard. Normative language describes the proposed contract; it does not assert an implemented or validated system.

## 1.1 The object of the claim

The target is **human composition**, not absence of AI influence. A qualifying human may read research, consult AI, understand a proposed argument, and subsequently compose their own text. The protocol does not certify originality of ideas, correctness, ownership, absence of plagiarism, educational compliance, or the intelligence of the writer.

The nonqualifying alternatives are importing finished language without qualifying provenance, mechanical transcription of supplied language, scripted input, and fabricated writing behaviour. A text can therefore be entirely non-AI and still be NOT PROVABLE. Conversely, genuine human composition informed by AI can qualify.

The difficult boundary is not keyboard versus clipboard. A person can physically type every character while merely transcribing. Another person can think through a sentence before typing it fluently with no visible revision. Both can produce the same observable input. Consequently, no pause, deletion quota, typing speed, or apparent imperfection is a necessary definition of human composition.

The scientific target is the **process that originated the wording within the certified scope**. The protocol must not quietly substitute a more convenient target, such as human contact with a device, human review of text, familiarity with an argument, or willingness to sign a declaration.

## 1.2 A precise binary interface

For document bytes D, evidence bundle B, scope S, and a relying party's externally selected trust policy T:

`Verify(D, B, S, T) -> HUMAN-WRITTEN | NOT PROVABLE`

HUMAN-WRITTEN means that the exact content in S has an admissible, sufficiently supported human-composition provenance under the named policy, capture assumptions, and validated operating domain. This is an assurance claim, not logical certainty about mental states.

NOT PROVABLE includes missing evidence, unapproved profiles, unsupported input modes, insufficient local evidence, failed cryptography, capture gaps, incompatible policy, ambiguity, or a model's failure to admit the process. No negative conclusion about the author's honesty or use of AI follows.

Reason codes may explain abstention but MUST NOT become a third authorship verdict. Neither a confidence score nor a signature-valid indicator is an authorship verdict. A relying party MUST recompute the result; it must not display an issuer's requested verdict without checking its evidence.

An unconditional interpretation—zero false certifications against every adversary who can reproduce the observations—is not equivalent to this policy-bound interpretation. The former has the identifiability limitation below. The distinction must remain visible in the standard, not merely in a disclaimer.

## 1.3 The observational boundary, derived

Let C denote qualifying composition, A a nonqualifying process, and O the complete observation available to a detector. Let V(O) be any possibly randomized acceptance procedure, including every downstream cryptographic transformation of O.

If C and A produce the same observation o, V cannot infer their different hidden causes from o. A valid signature on o does not supply that missing distinction.

More generally, let P_C and P_A be distributions over all observations, including challenges and responses. For an acceptance region R:

`P_C(R) - P_A(R) <= TV(P_C, P_A)`

where TV is total variation distance. For a randomized detector, the same bound applies to the expectation of its acceptance probability. Writing beta for the non-admission rate on composition and alpha for the false-certification rate on the attack gives:

`alpha + beta >= 1 - TV(P_C, P_A)`.

Thus, if an attack reproduces the observation distribution within epsilon, its acceptance rate is at least the genuine-composition acceptance rate minus epsilon. This is a mathematical statement about observational equivalence, not a claim that every practical attacker can match every protected sensor.

There is a particularly direct attack when the adversary controls the entire collector and all its signing keys: the adversary can submit an accepted transcript without having performed it. Hashing, signing, timestamping, or proving the classifier's execution on that invented transcript does not repair its origin. An independent capture boundary changes the observations and the attack's capabilities; it is therefore a substantive additional assumption, not cosmetic hardening.

Higher timestamp resolution may improve empirical separability. It cannot distinguish two causes that still induce the same enriched observations. A physical-keyboard signature also cannot, by itself, distinguish a finger from an actuator. A genuine person's live response to a challenge does not prove who composed earlier sentences.

The constructive consequence is to maximize evidence that is difficult to fabricate within an explicit threat model, measure the remaining error, and abstain outside that model. It is not to abandon process provenance or to pretend that cryptography measures cognition.

## 1.4 Four different questions that must stay separate

1. **Content integrity:** are these the exact bytes to which the evidence refers?
2. **Capture integrity:** did an admissible capture mechanism actually observe the committed events, under what input-path assumptions?
3. **Computation integrity:** did the specified replay, provenance analysis, and detector execute correctly on that same record?
4. **Scientific validity:** does the detector's acceptance justify the claim for this population, device, writing mode, and adversarial setting?

Identity is an optional fifth question. Possession of a signing key identifies a keyholder; it does not establish a natural person, the person at the keyboard, or the source of their wording. Identified authorship needs additional explicitly bound evidence. Pseudonymous authorship should not require public behavioural biometrics.

Remote attestation separates evidence, appraisal, and reliance rather than treating an attestation as truth about arbitrary real-world events; HWP adopts that separation [S07](06-sources.md#s07). A signed public key bundled with a certificate is not automatically a trusted capture source.

## 1.5 Scope and quotations

The binary result must be attached to an exact scope. Two scopes are proposed:

- `entire_text`: every byte of the identified text object is accounted for and every substantive authored range is supported by qualifying provenance. No unproven quotation or imported passage is silently excluded.
- `author_contribution`: a complete range map explicitly identifies the contribution being certified and all excluded quotations, imported passages, or transformations. The meaningful human-facing claim is HUMAN-WRITTEN for that contribution, with exclusions—not an unqualified claim about every word in the document.

A map partitions the full text, including titles, notes, and relevant markup. It cannot omit inconvenient bytes. Excluded material retains a provenance descriptor, optional source reference, and its own binary verification status where applicable. A verified quotation from another human may carry its own proof chain, but not become this author's composition.

An empty contribution cannot qualify by vacuous truth. A one-sentence original introduction cannot certify a long imported article. A byte-coverage fraction describes coverage, not a percentage of human thought. Minimum evidence and acceptable scope use must be independently calibrated; they are not arbitrary percentages of edits.

Rich-file rendering is distinct from the exact text object. A later PDF, HTML, or word-processing representation needs a separately bound transformation and an appropriate verifier. The initial text contract must not imply that hashing one text stream authenticates every visible or hidden element of another format.

## 1.6 Assistance without provenance laundering

The current request establishes AI-informed human composition as permissible. The following are proposed explicit policy branches, not additional user requirements:

- In-session spelling corrections can preserve ancestry as a declared transformation of qualifying text.
- Grammar changes and autocomplete require attributable transformation records and an admitted assistance policy; length alone is not a safe distinction between assistance and generated prose.
- Dictation requires an independently validated speech-composition profile. A microphone signal is not proof that the speaker is composing rather than reading or replaying audio.
- Translation can support a claim that an output is a declared translation of human-composed source text. It cannot silently claim that the human typed or composed the exact translated wording.

The default research profile approves none of these automatically. Accessibility modes must be evaluated without describing unsupported users as suspicious.

The system preserves a difference between **external ideas** and **inherited wording**. Understanding an external argument does not permanently contaminate all future composition. But changing a few words, reviewing a paragraph, or accepting a rewrite cannot automatically turn inherited text into certified composition. This boundary is handled with retained lineage plus new composition evidence, not with a fixed edit-distance threshold.

## 1.7 What this foundation commits to

Proceed with an open evidence and verification contract, a falsifiable composition detector, authenticated capture profiles, and private computation proofs. Do not yet issue HUMAN-WRITTEN certificates. The research package supplies an algorithmic specification, adversarial test contract, cryptographic design, and executed mechanics checks; it supplies no trained or independently validated classifier.

These are original design proposals and deductions informed by the cited primary sources. No patent novelty, standards adoption, or exhaustive prior-art clearance is asserted.
