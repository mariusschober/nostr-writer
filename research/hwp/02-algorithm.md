# 2. Candidate detection algorithm and text lineage

Research draft · Not trained, calibrated, or validated. All model-dependent parameters below must be pinned in a future evaluated profile. Missing parameters or an unapproved profile yield NOT PROVABLE; they must not be replaced with guessed defaults.

## 2.1 Hypothesis

The strongest candidate signal is not irregular timing. It is the relationship between a writer's current text, the edits they make, the passages they revisit, and what they write next. Composition may produce dependencies spanning motor actions, local phrasing, and document-level revision that are absent in ordinary transcription. An adaptive simulator can also create such dependencies; their incremental value is therefore an empirical hypothesis, not a security theorem.

Published work supports investigating process signals. Crossley et al. report differences in pauses, insertions, deletions, and revisions between authentic and transcribed essays [S01](06-sources.md#s01). Existing academic-dishonesty labels are not the HWP target: some classify assisted paraphrasing as negative, although genuine AI-informed composition is allowed here [S03](06-sources.md#s03).

Proposed pipeline:

`authenticated observations -> deterministic replay -> lineage graph -> scoped process features -> selective composition test -> binary scope aggregation`

These stages are separable so improved detectors can reuse the evidence format without changing what a cryptographic signature means.

## 2.2 Observation contract

Record events rather than sampling screenshots or collecting continuous surveillance. The signed capability declaration identifies what can actually be observed. Never invent unavailable key-up events, touch pressure, or sub-millisecond precision.

Each session declares a random session identifier, capture-channel capabilities, clock source and actual resolution, device/input mode, trusted capture boundary, initial state, and any verified parent sessions. Each event has a contiguous sequence number, a monotonic observation time with a declared uncertainty/resolution, type, source channel, and relevant state transition. Large clock values are decimal strings in canonical records, not floating-point approximations.

Two layers are retained locally:

**Input observations.** Physical key-down/key-up where available; repeat and modifier states; pointer/caret navigation; focus changes; observed paste/drop commands; undo/redo; IME composition lifecycle; touchscreen/gesture observations only where actually accessible; and assistance acceptance/correction events with attributable source information.

**Text transactions.** An authoritative record of each actual text mutation: pre-state digest, operation, affected range or stable atom references, inserted text, removed atom references, post-state digest, and links to the observations or transformation responsible. A key event is not itself a text mutation. A transaction without an attributable input episode is not labelled typed merely because it contains a small number of characters.

Capture timing is assigned at the declared capture boundary. Client-provided timestamps, wall-clock values, and an operating system's assertions of origin are not automatically trusted. Timestamp uncertainty, batching, event loss, focus changes, and suspended observation are explicit data. An interruption is not a cognitive pause, and a pause is not evidence of thinking.

The browser's `isTrusted` attribute distinguishes user-agent event dispatch from script dispatch; it is not a human-composition attestation [S05](06-sources.md#s05). Android input can arrive through IME text commits and corrections rather than one raw key event per character [S06](06-sources.md#s06). Device-specific capture profiles are therefore necessary.

Capture is limited to the document's writing session. The baseline does not require cameras, audio, eye tracking, unrelated keystrokes, full desktop recording, or an inventory of private research sources. No absence of observed external input is interpreted as proof that no second device or memorized source existed.

## 2.3 Deterministic replay and origin graph

The canonical text is a valid UTF-8 byte stream. No Unicode normalization, newline conversion, whitespace trimming, or silent correction occurs during verification. Edits must respect Unicode scalar boundaries; grapheme-cluster behaviour belongs to the recorded input adapter. UTF-16 and platform-specific offsets must be explicitly converted and tested.

Every inserted Unicode scalar receives a stable origin identity, such as `(session_id, transaction_index, insertion_offset)`. Implementations may compress adjacent atoms into runs, but cannot alter their ancestry. The graph stores creation events, derivations, moves, copies, removals, and restoration relationships.

Operation semantics:

- Insert new text: create new atoms with an observed origin descriptor. `direct_candidate` is a candidate for composition, not an accepted human label.
- Delete: remove atoms from the live text, retaining their historical identities in the private record.
- Move/cut-and-paste within an authenticated document: preserve ancestry. It is not a new composition episode.
- Copy/duplicate: create new live identities that reference the copied origins. Copying a verified range can preserve its original provenance but must not be counted as new human effort.
- Undo/redo: restore the recorded atoms and their origins. It cannot reset imported text to a typed origin.
- Replace/correct/translate: record an explicit transformation edge. Untouched atoms retain their ancestry; generated replacements do not inherit a direct-composition label automatically.
- Import: attach a verifiable parent proof with a compatible scope, or label the imported material external/unknown. A foreign document digest without its supporting proof does not qualify.

The initial state is empty or entirely accounted for by parent provenance/external-origin entries. A partially observed session cannot be made complete by selecting a convenient start point. Resume and multi-device sessions identify their parent state and their own capture capabilities. Concurrent branches are allowed; every contributing branch must be accounted for in a certified merge.

New wording can be independently composed from an external idea. It receives a new candidate episode and is evaluated as such. There is no permanent semantic contamination rule. Conversely, the system does not assume that changing every character one at a time establishes independent composition. Structural derivation and the full creation episode remain relevant. A hidden mental transcription can still be observationally ambiguous and must not be treated as solved by lineage.

Required replay invariants are: contiguous event sequence, valid pre/post state transitions, unique live atom identities, no dangling/cyclic ancestry, authenticated parent references, complete origin coverage, and exact reconstruction of the claimed final text. Failure is a provenance failure, not evidence of AI use.

## 2.4 Provenance resolution is not inference resolution

Final verification ranges are half-open UTF-8 byte intervals `[start,end)`. They form a complete, ordered, non-overlapping partition of the text. This supports character-level origin bookkeeping and accurate quotation boundaries.

Behavioural inference needs larger evidence neighbourhoods. A three-word insertion may have precise provenance but insufficient evidence of independent composition. Its assessment can use the creation episode and related revisions; it cannot borrow a high score from an unrelated paragraph elsewhere. A model's scope and evidence neighbourhood must be reproducible from the pinned segmentation algorithm.

The segmenter is fixed before acceptance is evaluated. It combines origin discontinuities, paragraph/sentence boundaries where supported, and bounded overlapping process windows. It also evaluates longer continuous candidate regions to detect strategically fragmented imports. The writer may not choose only favourable windows or keep trying alternative segmentations until one passes.

Short or ambiguous ranges remain NOT PROVABLE. A whole-document average cannot override an unsupported range. Minimum evidence is calibrated by input/language stratum; it is not a mandatory number of deletions, minutes, or errors.

## 2.5 Candidate feature families

**Sensor validity and motor context.** Timing availability, actual resolution, down/up consistency where observable, repeat behaviour, transaction-to-input consistency, batching, and device/input-mode changes. Inter-key flight times may be negative during overlapping physical keypresses; such values are not automatically malformed. These features primarily characterize capture and input, not thought.

**Contextual production.** Burst lengths and durations, pause distributions relative to word/sentence boundaries, navigation before resumption, and changes in production rate conditioned on input mode and writing context. Long gaps are censored or separately modelled rather than rewarded as authenticity.

**Revision topology.** Insertion/deletion/replacement spans; distance and elapsed time between creation and revision; revisits to older material; moves; abandoned alternatives; and the relationship between local changes and document-level restructuring. The model must distinguish a meaningful restructuring episode from repeated artificial backspace activity without treating either as definitive.

**Cross-event dependencies.** Whether subsequent text and revisions respond consistently to earlier changes; whether an altered premise is reflected in later wording; and whether navigation/revision decisions are associated with the text actually being revised. Local deterministic semantic encoders are a research option, not an external LLM judging whether the final prose sounds human.

**Process consistency and shifts.** Changes within a document in attribution quality, input mode, or process features, including a qualifying warm-up followed by an unsupported passage. Changes can also arise from fatigue, expertise, subject changes, or accessibility tools; they cause re-evaluation/abstention, not accusation.

The detector must not simply learn author identity, topic, writing quality, typing speed, or the style of a particular generative model. Final-text-only AI detectors are excluded from the baseline. Text may contextualize the writing process; it must not substitute for it.

## 2.6 A concrete selective decision rule

Let E be the reconstructed event record, G its lineage graph, s a candidate final range, and z the predeclared/derived input stratum. Let F(E,G,s,z) be a pinned deterministic feature extractor. The initial empirical baseline should be a small interpretable model family, such as regularized logistic models and bounded decision-tree ensembles. More complex sequence models must earn their place through held-out ablations.

For each nonqualifying family j—human transcription, scripted/replayed input, staged revision, and adaptive simulation—fit a discriminative score `f_j(F)`, with larger values favouring composition. Convert it to a calibrated margin `m_j` using held-out development data. These scores are not probabilities that a particular document is human.

One conservative candidate score is:

`R(s) = min_j m_j(F(E,G,s,z))`.

Acceptance requires every known-family margin to exceed its fixed threshold, together with capture, adequacy, and support checks. The minimum is not protection against unrepresented attacks; that limitation belongs in the release's threat model.

An optional sequence extension models complete episodes rather than multiplying independent keystroke probabilities. For sequence models with explicit densities, a candidate margin is:

`r_j(s) = [log p_theta(E_s | composition,z) - log p_theta(E_s | attack_j,z)] / max(1,n_s)`.

Here n_s is a fixed normalization count, not a claim that the events are independent. Density validity, model specification, and calibration must be established empirically. A discriminative logit must not be presented as this likelihood ratio without justified assumptions.

The following procedure specifies the acceptance logic:

```text
assess(document, evidence, requested_scope, trusted_release):
    if trusted_release is absent or not externally approved:
        return NOT PROVABLE
    if required capture/receipt bindings or sequence integrity fail:
        return NOT PROVABLE
    text, graph, capabilities = deterministic_replay(evidence)
    if text != exact_document_bytes:
        return NOT PROVABLE
    partition = deterministic_scope_partition(text, graph, requested_scope)
    if partition is incomplete, invalid, or vacuously empty:
        return NOT PROVABLE
    for each required candidate range s in partition:
        neighbourhood = pinned_evidence_neighbourhood(s, graph)
        if capture_is_inadmissible(neighbourhood, capabilities):
            return NOT PROVABLE
        if unsupported_stratum_or_insufficient_evidence(neighbourhood):
            return NOT PROVABLE
        features = pinned_feature_extractor(neighbourhood)
        if out_of_domain(features) or any_known_family_margin_below_threshold(features):
            return NOT PROVABLE
    if any required imported/transformed range lacks compatible accepted provenance:
        return NOT PROVABLE
    if the complete document-level policy test fails:
        return NOT PROVABLE
    return HUMAN-WRITTEN for the exact requested scope
```

The complete pipeline, including segmentation and aggregation, must be calibrated at document level. Strong per-window metrics do not justify a whole-document false-certification bound.

For private verifiable execution, feature extraction, tokenization, any semantic encoder, model weights, quantization, missing-data handling, thresholds, and aggregation are all part of the pinned computation. An author cannot supply unverified favourable feature vectors. A compact fixed-point implementation is a reasonable proof target, but this package does not assume its performance.

## 2.7 Research probes, not magical anti-bot tests

A useful ablation destroys cross-event relationships while preserving local timing and edit counts. If relational features add no held-out value over the preserved statistics, the central hypothesis is weakened. Synthetic controls are diagnostics, not genuine composition ground truth.

Unpredictable challenges may bind an interaction to a live session and test responsiveness to a newly introduced constraint. They cannot retrospectively certify earlier paragraphs. A model can answer, a human can relay the answer, and a transcriber can understand a text. A future challenge profile must demonstrate measurable benefit under those attacks before it affects certification.

Do not impose artificial errors or forced revisions to generate evidence. That would train people to perform the detector's stereotype rather than compose naturally. The correct output for fluent but under-observed composition is NOT PROVABLE.

## 2.8 Evidence required to instantiate this algorithm

A future release must supply the trained model files, feature and replay implementations, segmentation rules, operating domains, fixed thresholds, accepted capture profiles, calibration data descriptions, attack coverage, and an externally approved policy digest. Until then, the algorithm is a detailed research specification with fail-closed semantics, not a validated detector.
