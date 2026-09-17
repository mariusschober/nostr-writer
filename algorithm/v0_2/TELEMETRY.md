# Normalized telemetry and adapter contract

This is the algorithm's input contract. It specifies what a later capture implementation must supply, not a writing application's architecture. `telemetry.schema.json` covers JSON structure; stateful replay provides additional mandatory validation.

## 1. Top-level format

```
{
  "version": "hwp-a/0.2",
  "documents": [record, ...],
  "target": "document-id"
}
```

A record has exactly `id`, `language`, `resolution_us`, `observations`, `transactions`, and `final_text`. Documents are complete versions ordered so a cross-document copy only refers backward. IDs are nonempty, at most 64 Unicode scalars and contain neither `:` nor `/`. Language is a nonempty release-specific identifier of at most 40 scalars. The language declaration does not authorize a model domain.

`final_text` is the exact text obtained by applying all transactions from an empty state. Preexisting content must arrive through an external insertion or a copy from an included parent version. No restoration shortcut, skipped history, final-state-only fallback, or imported boolean human flag is allowed.

JSON numbers used as indices/times must parse as integers, not booleans or floats. Duplicate JSON keys, nonfinite numbers, unpaired surrogates and unknown object fields are rejected. JSON Schema is a structural aid; by itself it does not enforce these parser and state rules. Files are UTF-8. JSON object ordering has no semantic effect; arrays preserve order.

## 2. Observation format

Every observation has exactly:

```
{"i":0,"t":250000,"kind":"press","token":"p0",
 "source":"device","profile":"keyboard"}
```

Only `ime_commit` also has `basis: [observation_index,...]`. The allowed profile values are `keyboard`, `touch-tap`, `ime`, `gesture`. Allowed sources are `device`, `synthetic`, `unknown`.

The index is contiguous from zero. Time is monotonic integer microseconds and a multiple of `resolution_us`. An episode token is a nonempty string of at most 128 scalars. Tokens identify concrete input episodes, not users, passwords or key text.

| Start | Updates | End | Meaning |
|---|---|---|---|
| press | repeat | release | Physical/native keyboard press; repeat requires keyboard profile and an active press |
| touch_down | touch_move | touch_up | A single observed tap/contact |
| ime_start | ime_update | ime_commit | One native composition episode with separately recorded physical motor basis |
| gesture_start | gesture_update | gesture_end | One word-decoding gesture, not a set of independent character presses |

Other observation kinds are `command`, `focus_out`, `focus_in`, `suspend`, `resume`, and `gap`. Commands identify actual observed operations such as paste, correction, undo or navigation; they cannot alone justify `direct` text. Token/source/profile consistency and open/close pairing are mandatory. A source-classification flag supplied by an untrusted caller is not authenticated capture.

IME basis references must be unique, earlier, and point to press/touch-down observations with the same source/profile inside that IME episode. A basis spent by the IME commit cannot be spent again as an independent direct edit. A gesture's updates likewise do not create repeated independent production evidence.

## 3. Transaction format

Every transaction contains `i`, `t`, `op`, `profile`, and a nonempty unique `causes` array of prior causal observation indices. Cause references are consumed once; releasing a key later is legal, while spending that press twice as independent typing is not. Native key-repeat observations can cause repeated text but still represent one held press for minimum evidence.

Each operation additionally contains exactly these fields:

| Operation | Additional fields | Coordinate convention |
|---|---|---|
| splice | start, end, text, deleted, source | Scalar offsets in pre-state |
| copy | from_doc, start, end, to | Source interval in source snapshot; destination offset in destination pre-state |
| move | start, end, to | Source in pre-state; destination **after removal** |
| undo | ref | Original mutating transaction at top of undo stack |
| redo | ref | Original mutating transaction at top of redo stack |
| navigate | start, end | Selected scalar interval in current state |

All ranges are half-open. A splice must match `deleted` exactly. Its source is `direct`, `paste`, `generated`, `unknown`, or `spelling`; no `control` source is accepted in the serialized splice. The source is not inferred from how small the insertion happens to be.

A keyboard direct splice inserts at most eight scalars per physical cause and must be within 250 ms of every cause. Larger text commits require the admitted profile's actual semantics, not an invented sequence of one-character edits. A delete can remove many scalars without creating production roots. A selection and replacement must preserve its actual deleted text and origin graph.

A minimal valid one-character document (necessarily too short to certify) is:

```json
{
  "version":"hwp-a/0.2",
  "target":"d",
  "documents":[{
    "id":"d","language":"en","resolution_us":1000,
    "observations":[
      {"i":0,"t":250000,"kind":"press","token":"p0","source":"device","profile":"keyboard"},
      {"i":1,"t":280000,"kind":"release","token":"p0","source":"device","profile":"keyboard"}
    ],
    "transactions":[
      {"i":0,"t":250000,"op":"splice","profile":"keyboard","causes":[0],
       "start":0,"end":0,"text":"a","deleted":"","source":"direct"}
    ],
    "final_text":"a"
  }]
}
```

`fixtures.py:Builder` generates valid examples for all four profiles, copy/move/history operations and explicit loss. Those generated examples are synthetic fixtures, not observed human data.

## 4. Native-to-normalized mapping

A capture adapter must resolve native events into actual state transitions at its stated observation boundary. It must preserve event timing honestly, distinguish physical output from synthesized injection where its boundary actually can, and expose unsupported cases as unknown or lost evidence. It must never reverse-engineer a plausible typing history from final text.

For native IMEs, provisional text is temporary input-method state. Retain its lifecycle and motor basis; normalize the committed change against the pre-episode committed document. Do not count each temporary candidate update as a deliberate independent deletion/revision. Generic word completion and generative suggestion acceptance are external text; a decoder must be specifically admitted to classify phonetic/gesture decoding as direct input.

Android's `InputConnection` distinguishes text commits, composing state, corrections, completion and key-event dispatch. `commitText` can replace the current composing span and is not a one-key/one-character event. Its coordinate APIs can use UTF-16 code units rather than Unicode scalars. These distinctions motivate the normalized contract; they do not establish that an arbitrary Android editor can obtain all required physical evidence. See the primary API reference [1].

The W3C Input Events specification distinguishes text insertion, composition and replacement. In particular, replacement events can represent different kinds of assistance; their generic category is not proof of this specification's narrow spelling exception [2]. A browser's event provenance is not by itself proof of human cognition or a protected physical input path.

For adapters whose platform observations cannot distinguish generative suggestions from direct decoding, the source must be unknown/external or the profile must remain unadmitted. Future stronger observation contracts can change coverage, but cannot be silently retrofitted to old records.

## 5. Unicode and evidence examples

`"é"` and `"e\u0301"` are distinct exact texts. Both can be valid records. Their bytes, scalar counts and origin roots differ. An emoji sequence may contain several scalars and several UTF-16 code units. Compute a scalar-to-byte offset table from the actual final text; do not multiply an index by an assumed byte width.

A copied quote preserves its source classification after movement and undo. An externally sourced passage can be excluded from a scoped contribution claim but remains visible in the complete partition. A supported parent's imported passage retains the parent's origin identities and requires the parent's and destination's capture admission.

A trace with legitimate human-looking pauses followed by an event-loss gap reconstructs text but has no admissible capture claim in this baseline. A trace of a person transcribing perfectly from a second screen may satisfy every deterministic rule; whether it passes the statistical model is an empirical adversarial question, not a validation-parser bug.

## 6. Explicitly outside the baseline

Voice dictation, handwriting recognition, opaque assistive input, arbitrary rich-text rendering, simultaneous editing of one mutable native document, and snapshots without complete parent histories are not quietly classified as ordinary keyboard writing. Multi-version imports are supported; native concurrent merge adapters and broader input policies need separately specified normalization and fresh evaluation.

These exclusions are conservative scope limits, not assertions that such users do not compose. Their output is NOT PROVABLE under this release, and their exclusion must be counted when reporting overall user coverage.

## Primary references

[1] Android Developers, `InputConnection`, retrieved 15 September 2026: https://developer.android.com/reference/android/view/inputmethod/InputConnection . Used only for native API semantics.

[2] W3C, *Input Events Level 2*, Working Draft 1 May 2026: https://www.w3.org/TR/2026/WD-input-events-2-20260501/ . This is an evolving platform specification, not an adoption of HWP-A.
