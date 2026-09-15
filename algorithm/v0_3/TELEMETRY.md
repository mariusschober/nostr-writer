# Normative normalized telemetry — hwp-a/0.3

## What a collector must actually observe

Capture only events belonging to the document session. Do not require global keystroke surveillance, screens, audio, cameras or private research history. Such additional signals are not part of this algorithm. A native collector must independently justify source attribution and mutation completeness; the record itself cannot do so.

There are three logically distinct observations: motor/command events; the decoder's actual native text/edit delivery; and the resulting authoritative text mutation. Their normalized record is not a claim that all operating systems expose those three layers to ordinary applications. An input path that exposes only committed strings cannot invent motor events, and a web application cannot treat its own dispatch flags as protected physical origin.

All time values are monotonic microseconds within one record, with declared actual resolution from 1 to 10,000 microseconds. They are integers, multiples of resolution, nondecreasing across the shared total sequence. No cross-record wall-clock or trusted duration is inferred. The timestamps' real-world authenticity belongs to the admitted path.

## Top-level and record fields

The exact top-level keys are `version`, `documents`, `target`. Version must be `hwp-a/0.3`. Records are topologically ordered, at most 32. The target must exist. A record has exactly:

| Field | Meaning |
|---|---|
| id | Nonempty local ID up to64 scalars, no colon or slash, unique in bundle; not an identity credential |
| language | Nonempty fixed model-domain label up to40 scalars; no pipe, slash or backslash; not language autodetection |
| resolution_us | Actual monotonic timestamp quantum, integer1..10000 |
| paths | Nonempty map from observed profile to independently named capture/decoder path; path IDs up to128 scalars, no pipe |
| observations | Raw input, state, decoder-delivery observations, in contiguous observation-index order |
| transactions | Authoritative mutations/selection operations, in contiguous transaction-index order |
| final_text | Exact final Unicode scalar sequence, at most200000 scalars |

A decoder update, changed predictive settings, remapping or input-source change that alters observable semantics requires a new path or record. A new profile in the same record must be declared and has separate model domains. A self-reported language label can be wrong; the release must test mislabeled/mixed-language attempts, and unknown linguistic support must not be inferred from a matching label.

## Observation fields and state machine

Every observation has exactly `i,t,seq,kind,token,source,profile`, plus the conditional fields below. `i` is its zero-based observation index. `seq` is its index in the combined observation/transaction order, not a timestamp. Source is device/synthetic/unknown. Profile is keyboard/touch-tap/ime/gesture. Tokens uniquely identify starts of episodes of the same kind and cannot be reused.

Starts are press, touch_down, ime_start and gesture_start. Corresponding ends are release, touch_up, ime_commit and gesture_end. Updates are touch_move, ime_update and gesture_update. Other kinds are repeat, command, focus_out, focus_in, suspend, resume, gap and delivery. Each end/update references an active matching token, profile and source. Repeats require an active keyboard press. The record closes all started input episodes; incomplete final episodes are NOT PROVABLE, not silently padded with synthetic release times.

Only one IME composition episode may be active at a time in this profile. An `ime_commit` has a nonempty unique `basis` list of earlier press/touch_down observation indices from that composition episode, with matching source/profile. Basis events precede commit strictly by `seq`, even if timestamps tie. Basis use is consumed once. This requires actual instrumentable IME support; an opaque commit from a third-party decoder does not qualify by declaration.

A `delivery` has an additional `effect` object and no basis. Effect is the exact normalized operation and cause references that the native edit delivery independently supplies. It excludes transaction-only keys `i,t,seq,delivery`. Delivery source/profile are separately observed and checked. Commands that change selection or restore history also require a delivery. Every delivery must have exactly one corresponding transaction; dropped or extra deliveries invalidate completeness.

The profile bulk ceiling per direct cause is8 scalars for keyboard/tap,256 for IME and64 for gesture. These are resource/consistency ceilings, not claims that such output was necessarily composed. Native prediction/autocomplete/rewrite must be recorded as assisted/external even below these limits. IME transliteration support is path-specific; the operator must distinguish motor decoding from generated wording.

## Transaction fields

Common required fields are `i,t,seq,op,profile,causes,delivery`. Causes are1..1024 unique observation references. They precede the referenced delivery; the delivery precedes the transaction. A reference can be consumed only once. Direct mutation cannot cross an interruption; all bound causes and delivery are recent within250ms and match the transaction profile.

| op | Additional exact fields | Semantics |
|---|---|---|
| splice | start,end,text,deleted,source | Replace scalar interval[start,end); exact removed text must equal deleted; nonempty change. source is direct/paste/generated/unknown/spelling |
| copy | from_doc,start,end,to | Copy nonempty source interval from current or earlier record; insert at target position; new occurrence IDs preserve roots |
| move | start,end,to | Move nonempty current interval; to is interpreted after removing it |
| undo / redo | ref | Require exact original transaction at top of applicable history stack |
| navigate | start,end | Set scalar selection/caret context; no text creation |

Transactions use scalar offsets, not native UTF-16 units, bytes or grapheme counts. Scope/quotation ranges use half-open UTF-8 byte offsets and must align to scalar boundaries. The normalizer must test astral scalars, combining sequences, composed/decomposed equivalents, CRLF, emoji sequences and right-to-left text; it may not silently normalize any of them.

## Example and collector conformance

`artifacts/telemetry-example.json` is one synthetic keyboard insertion with press, delivery, mutation and release in explicit total order. It is structurally valid but far too short for positive behavioural support. The fixture Builder *constructs* deliveries for testing; using it to upgrade an old real record would invent evidence and is prohibited.

Required native-adapter conformance tests: exact replay after every edit; command/selection delivery equality; no unexplained buffer changes; resolution and timestamp ordering; equal-tick cause ordering; focus interruption; actual key repeat; IME composition and basis reuse; prediction acceptance; spellcheck; paste/drop and restore; Unicode offsets; undo/redo and cross-record imports; and decoder version changes. The normative Python validator tests supplied telemetry. No native adapter was implemented or tested by this revision.

## Failures and privacy

Malformed syntax, duplicate JSON keys, nonfinite numbers, bool-as-int values, surrogate code points, missing deliveries, changed input sources, excessive resource use or impossible state transitions fail closed. A capture gap makes the affected record inadmissible. `NOT PROVABLE` is not a diagnosis of why a person wrote as they did.

Deleted wording, timings, corrections and input patterns can be sensitive and identifying. The reference runs locally and makes no network calls. Publishing a verdict does not require publishing this private telemetry. This algorithm-only revision does not specify a privacy proof or a signing protocol.
