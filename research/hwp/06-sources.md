# 6. Primary sources and evidence boundaries

Sources checked on 2026-09-15. This is a bounded research bibliography, not an exhaustive literature or patent review. Versioned RFCs and the named C2PA version are explicit references; moving documentation/Nostr pages describe the retrieved state, not a promise of permanent version identity. No third-party performance claim below is an HWP test result.

## S01

Crossley, Tian, Choi, Holmes, and Morris. **Plagiarism Detection Using Keystroke Logs**, Educational Data Mining, 2024. [Proceedings text](https://educationaldatamining.org/edm2024/proceedings/2024.EDM-short-papers.47/index.html); [DOI record](https://zenodo.org/records/12729864).

Reports 99% random-forest accuracy on its test set; its reported confusion matrix includes two transcribed essays admitted as authentic. Supports investigating pauses and revision behaviour. It does not establish an adversarial false-certification guarantee, touchscreen coverage, or the current project's permissive AI-influence definition. The reported train/test procedure must not be assumed to establish all writer/source-disjoint generalizations HWP needs.

## S02

Kundu et al. **Keystroke Dynamics Against Academic Dishonesty in the Age of LLMs**, 2024. [Abstract](https://arxiv.org/abs/2406.15335); [full text](https://arxiv.org/html/2406.15335v1).

Reports condition-specific accuracies of 74.98–85.72% and condition-agnostic accuracies of 52.24–80.54%. This supports a measurable process signal but also illustrates sensitivity to setting. Its assisted-writing labels cannot simply be reused as HWP's nonqualifying labels.

## S03

**Detecting LLM-Assisted Academic Dishonesty using Keystroke Dynamics**, 2025 preprint. [Full text, version 1](https://arxiv.org/html/2511.12468v1).

Extends process-based analysis and discusses deception experiments, cross-context/data variation, and ethical limitations. It includes assisted paraphrasing among its target negatives, unlike HWP. Its deception table uses metric labels whose interpretation should be checked against the experiment definitions; this package does not convert that table into an HWP attack-success rate. Main use: design motivation, label-mismatch warning, and need for adversarial/held-out evaluation.

## S04

Schütz, Cherif, Sayffaerth, Weber, and Chiossi. **Typing Behavior in Human-LLM Interaction: Keystroke Dynamics Reveal Cognitive Effort During Prompting**, 2026. [Abstract](https://arxiv.org/abs/2606.28090); [full text](https://arxiv.org/html/2606.28090v1).

Study with 36 participants comparing task difficulty and desktop/mobile interaction. Reports effort-related typing differences, not a detector proving composition rather than transcription. Supports treating input mode and task context as potential confounders, not equating effort with authenticity.

## S05

WHATWG. **DOM Standard: isTrusted**. [Definition](https://dom.spec.whatwg.org/#dom-event-istrusted). W3C. **UI Events**. [Specification](https://www.w3.org/TR/uievents/).

Defines event-dispatch and input/composition semantics. Neither is a cryptographic human-input guarantee. These references support the distinction between browser event metadata and a trusted capture path.

## S06

Android Developers. **InputConnection**. [Official API reference](https://developer.android.com/reference/android/view/inputmethod/InputConnection).

Describes IME commits, corrections, composing regions, and input communication. Supports modelling text transactions and input-method capabilities rather than assuming a one-key-one-character mobile trace.

## S07

IETF. **RFC 9334: Remote ATtestation procedureS (RATS) Architecture**, 2023. [RFC](https://www.rfc-editor.org/rfc/rfc9334.html).

Source for separating attesters, evidence, verifiers, appraisal, and relying parties. HWP's input-origin requirements are proposed application-specific conditions, not guarantees delivered by the RFC.

## S08

IETF. **RFC 9711: The Entity Attestation Token (EAT)**. [RFC](https://www.rfc-editor.org/rfc/rfc9711.html).

Potential standardized attestation-claim carrier. It does not itself define or validate human-writing claims.

## S09

IETF. **RFC 8785: JSON Canonicalization Scheme (JCS)**, 2020. [RFC](https://www.rfc-editor.org/rfc/rfc8785.html).

Canonical serialization reference. HWP proposes a smaller allowed data domain and rejects ambiguous or unsupported encodings. The experiment is not a general JCS implementation.

## S10

IETF. **RFC 8032: Edwards-Curve Digital Signature Algorithm (EdDSA)**, 2017. [RFC](https://www.rfc-editor.org/rfc/rfc8032.html).

Signature primitive reference. HWP adds role/domain/document/evidence bindings; the signature primitive does not validate the truth of its payload.

## S11

IETF. **RFC 9162: Certificate Transparency Version 2.0**, 2021. [RFC](https://www.rfc-editor.org/rfc/rfc9162.html).

Ordered Merkle-tree, inclusion, and consistency-proof reference. HWP borrows the tree construction but is not a deployed CT log or a claim that CT proves event authenticity.

## S12

C2PA. **Content Credentials: Technical Specification, version 2.4**. [Specification](https://spec.c2pa.org/specifications/specifications/2.4/specs/C2PA_Specification.html).

Asset-provenance manifests, assertions, and bindings. HWP's human-composition appraisal is an additional proposed assertion/evidence contract, not an existing C2PA guarantee.

## S13

Nostr. **NIP-01: Basic protocol flow description**. [Specification](https://github.com/nostr-protocol/nips/blob/master/01.md).

Event serialization, event IDs, key signatures, and storage conventions. Nostr signature verification is key endorsement, not independent time or human-writing verification.

## S14

Nostr. **NIP-23: Long-form Content**. [Specification](https://github.com/nostr-protocol/nips/blob/master/23.md).

Editable/addressable article events. Supports binding the specific version/event ID rather than only an address.

## S15

Nostr. **NIP-94: File Metadata**. [Specification](https://github.com/nostr-protocol/nips/blob/master/94.md).

File announcement metadata including kind 1063 and the file's SHA-256 digest. No HWP-specific event kind is standardized by this proposal.

## S16

Bitcoin Improvement Proposals. **BIP-340: Schnorr Signatures for secp256k1**. [Specification](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki).

Signature scheme used by Nostr. It is distinct from HWP's proposed Ed25519 envelope scheme.

## S17

OpenTimestamps. **A timestamping proof standard**. [Official description and implementation links](https://opentimestamps.org/).

Prior-existence anchoring and independent timestamp verification. Completed chain proofs and retained evidence are necessary; a timestamp does not authenticate human composition.

## S18

IETF. **RFC 3161: Internet X.509 Public Key Infrastructure Time-Stamp Protocol (TSP)**, 2001. [RFC](https://www.rfc-editor.org/rfc/rfc3161.html).

Authority-based timestamping alternative. Its trust and archival requirements remain separate from the writing detector.

## S19

IETF. **RFC 4998: Evidence Record Syntax (ERS)**, 2007. [RFC](https://www.rfc-editor.org/rfc/rfc4998.html).

Long-term evidence renewal and archive concepts. HWP does not promise perpetual security for an unrenewed signature.

## S20

RISC Zero. **zkVM Overview**, retrieved documentation version 3.0. [Official documentation](https://dev.risczero.com/api/zkvm/).

Describes execution receipts, program identity, and public outputs. Used to establish an available category of computation-proof mechanism, not to select an HWP implementation or claim proof-generation feasibility. No HWP zkVM benchmark was run.

## Interpretation rule

Everything called a hypothesis, proposed profile, algorithm, proof relation, or validation requirement in this package is a design contribution to be tested. Source results are not silently transferred to this algorithm. The total-variation bound, zero-failure sample calculations, and retry calculation are mathematical deductions; the executable synthetic checks provide the reported numerical/conformance evidence.
