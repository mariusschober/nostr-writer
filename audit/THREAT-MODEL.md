# HWP v0 adversarial threat model

Status: audit of the frozen `protocol/v0` distribution on branch
`hwp-adversarial-audit`. No file under `protocol/v0/` was modified. No Mac
application was built, started or observed.

## 1. Scope and method

This model asks a narrower question than “is the detector accurate?”:

> Given the exact HWP v0 verifier and the trust inputs it is handed, which
> forgeries can it distinguish, which can it only assume away, and which can it
> not see at all?

The frozen package answers part of this itself. It is a conformance protocol,
not an empirical approval: “No production approval, evaluated native capture
path or model trained on real human sessions accompanies this release”
(`protocol/v0/SPECIFICATION.md` §1). All supplied positive examples are
synthetic and project to `TEST-ONLY / NOT PROVABLE` (§1, §9;
`docs/CONFORMANCE.md` “Classes and required behaviour”). The production
approval set is empty (`README.md`; `docs/AUDIT.md` “Deliberate scope
decisions”).

The attack scripts in `audit/attacks/` therefore separate two questions:

1. **Conditional algorithm admission.** Does the frozen replay → features →
   model → scope → lineage computation accept the fabricated trace when the
   evaluator is allowed to treat it as admitted conformance evidence?
2. **Public certification.** Does the public verifier emit `HUMAN-WRITTEN`
   rather than `TEST-ONLY / NOT PROVABLE`?

A `TEST-ONLY` result is not detection. It is the protocol's fixed projection
for conformance releases (`SPECIFICATION.md` §9, outcome table). A forged trace
that is conditionally admitted but publicly `TEST-ONLY` has still defeated the
behavioural check; only the policy label prevents a production claim.

## 2. The trust boundary in one paragraph

The verifier checks canonical encodings, signatures, exact object bindings,
release/profile/domain closure, capture-start/end consistency, scope and
lineage. It does **not** observe the physical world. The capture assumptions it
relies on are listed verbatim: `complete-document-observation`,
`faithful-device-origin`, `faithful-monotonic-order`, `native-delivery-binding`,
`no-hidden-prediction`, `precommitted-release`, `single-finalization`
(`SPECIFICATION.md` §5, capture-profile). A source “must justify all of them
for the admitted path. Naming a path does not prove them” (ibid.). The
authoritative audit says the same: “Conditional: actual event acquisition;
truth of device/synthetic origin; absence of hidden decoder generation;
honesty of capture/evaluation and approval authorities”
(`docs/AUDIT.md` “What is fixed versus assumed”).

That is the whole boundary. Everything below follows from it.

## 3. Required attack classes

### 3.1 Replay of genuine human traces

**Attack.** Re-submit an already valid proof, or re-commit the same observed
event sequence under a fresh session ID and fresh salts, and present it as a
new writing session.

**What HWP checks.** The Merkle leaves bind the exact signed capture-start,
event index, salt and event bytes (`SPECIFICATION.md` §6). Re-committing the
same events under a new start produces a different, internally consistent tree.
The verifier checks one finalized end per `(capture key, session ID)` and
conflicting ends in one graph (`SPECIFICATION.md` §6; `docs/THREAT-MODEL.md`
row “Reusing valid history as a new session”). It does not consult a global
session registry and does not compare against earlier real-time captures.

**Detectable in principle?** **No, not by the verifier alone.** The protocol
states the boundary explicitly: “Re-verifying the same old proof is valid.
Hidden duplicate real-time capture or undisclosed forks require source
integrity/external comparison” (`docs/THREAT-MODEL.md`, same row). Fresh IDs
and nonces “bind records; they are not proof of physical input, trusted wall
time or one attempt per person” (`SPECIFICATION.md` §6). A re-committed trace
is a new signed capture over old observations; nothing in the proof says the
observations were re-observed.

**What would change the answer.** A source-side uniqueness/transparency
mechanism (published session commitments, a witnessed nonce, a trusted clock)
and cross-session duplicate detection. Offline verification still cannot find
an undisclosed fork; the protocol says so.

### 3.2 Synthetic keystroke timing generated to mimic humans

**Attack.** Generate a complete observation stream from a program, with
human-looking delays, dwell times, bursts and pauses, and label the events as
ordinary device input. No human types.

**What HWP checks.** Timestamps must be monotonic, quantized to the declared
resolution, and consistent with the event state machine
(`SPECIFICATION.md` §6; `docs/ALGORITHM.md` “Deterministic reconstruction”;
`algorithm/v0_3/TELEMETRY.md`). The algorithm extracts timing, pause, dwell,
burst and revision features (`docs/ALGORITHM.md` “Fixed evidence neighbourhoods
and inference”; `algorithm/v0_3/SPECIFICATION.md` §7). It does not have an
independent clock or a sensor that says “this delay came from a human”.

**Detectable in principle?** **No as a protocol guarantee; only statistically,
and only against a modelled generator.** The protocol explicitly refuses the
universal claim: “a universal defence against behavioural imitation” is not
implemented or claimed (`README.md` “Files and implementation boundaries”).
The formal statement is the observational-equivalence bound: for genuine
distribution P and attack Q, `Q(A) >= P(A) - TV(P,Q)`; “If a permitted
adversary can reproduce exactly an accepted observation, no observer-only
nonvacuous rule can distinguish its different hidden cause”
(`docs/ALGORITHM.md` “Falsifiable limitations retained”;
`docs/THREAT-MODEL.md` “Guarantees that do not follow”). A particular synthetic
generator may be statistically separable, but that is an empirical release
question (`algorithm/v0_3/SPECIFICATION.md` §9), not a property the verifier
can establish from the proof.

**What would change the answer.** A new observation channel with an
independent physical correlate (trusted sensor, liveness, hardware timing
attestation) or a trained and empirically admitted model. Neither exists in
this distribution. Even a perfect statistical detector cannot distinguish an
attack whose observation distribution equals the human distribution.

### 3.3 A human retyping AI-generated text

**Attack.** An AI system produces text. A human reads it and types it into the
capture client, character by character, with normal human timing. The client
records direct device insertions. There is no paste, no copy transaction and no
captured external source.

**What HWP checks.** The normative target excludes “imported wording,
mechanical transcription, automation, replay or staged imitation”
(`SPECIFICATION.md` §2). But the observation alphabet contains no screen,
clipboard, gaze, thought or external-source inventory
(`docs/AUDIT.md` “Deliberate scope decisions”). The algorithm's source veto
only covers exact 32-scalar shingles from earlier **captured** external
insertions in the same record, propagated through real ancestry
(`algorithm/v0_3/SPECIFICATION.md` §5; `docs/ALGORITHM.md` “Deterministic
reconstruction”). A retyped AI paragraph creates direct candidate insertions:
“Direct candidate insertions remain new candidates even when informed by
earlier external ideas: there is no semantic contamination rule”
(`docs/ALGORITHM.md` “Deterministic reconstruction”). The threat model says the
same: “local timing regularity does not identify mechanical input, revisions do
not prove reasoning” (`docs/THREAT-MODEL.md` “Guarantees that do not follow”).

**Detectable in principle?** **No, not from the HWP v0 observation alphabet.**
The proof can show that the characters were typed; it cannot show where the
human read them. This is a gap between the normative word “transcription” and
the observable contract. If the same AI text had been pasted, the `paste`
transaction would be unsupported (`docs/ALGORITHM.md`; `algorithm/v0_3/
SPECIFICATION.md` §4). Retyping removes that evidence.

**What would change the answer.** Capture of source exposure (screen/OCR,
clipboard lineage, browser/application provenance) with its own privacy and
consent contract; or a narrower claim that says “not copied from captured
sources”, not “human-authored”. A behavioural model might flag some
AI-like style, but style is not source provenance and the protocol does not
claim semantic detection.

### 3.4 An autotyper or HID device driven by software

**Attack.** A hardware or software device emits keystrokes/taps that the OS
delivers as ordinary input. The capture client records the events, the native
deliveries and the mutations, labels the source `device`, and signs the
capture. No human hand is involved.

**What HWP checks.** The source label is “an observed capture classification,
not a writer declaration” (`algorithm/v0_3/TELEMETRY.md` “What a collector must
actually observe”; `algorithm/v0_3/SPECIFICATION.md` §3). The verifier checks
the signed start/end, profile, adapter, one-use delivery binding, focus and
timing state machine, and exact final document. It does not verify that the
device was a human hand. The capture profile's `faithful-device-origin` and
`native-delivery-binding` assumptions are trust claims, not machine-checked
facts (`SPECIFICATION.md` §5; §3 “Conditional guarantee and trust inputs”).
The threat model lists “inject or automate events” as an adversary capability
and the remaining boundary as “a dishonest admitted source can fabricate a
structurally valid history” (`docs/THREAT-MODEL.md` “Assets, adversaries and
assumptions” and row “Fabrication of delivery fields or timestamps”).

**Detectable in principle?** **No, if the device's output is indistinguishable
from a keyboard/tap at the observation layer.** A HID device is a keyboard to
the OS; the protocol has no hardware provenance. A particular autotyper may be
statistically detectable by timing or topology, but no such detector is
shipped and no universal guarantee is claimed (`README.md`; `docs/ALGORITHM.md`
“Falsifiable limitations retained”). The only boundary is the admitted capture
path's integrity.

**What would change the answer.** Hardware-backed input provenance (secure
sensor, signed HID/device attestation, OS trusted-event path) and an empirical
release that measures the actual device boundary. Even hardware attestation
does not prove a human moved the actuator; it only proves which device
produced the event. A robot can type.

### 3.5 A modified client that fabricates capture data

**Attack.** The attacker controls the capture client, or the key it uses. The
client invents a complete observation history consistent with a chosen final
text, computes the Merkle commitments, signs capture-start/end with the
admitted capture key, and has an admitted evaluator sign the resulting
statement. No observation ever happened.

**What HWP checks.** Signatures authenticate the capture key, not the honesty
of the software that holds it. “Both modes rely on admitted capture sources for
the truth and completeness of observations … Neither mode proves that the
source did not fabricate data before committing it” (`SPECIFICATION.md` §3).
“Its root is not a proof that this collector was honest before signing”
(`SPECIFICATION.md` §6). “Low-level possession of an issuer seed can sign lies;
no API guard prevents its holder from bypassing software” (`SPECIFICATION.md`
§8). The audit lists “a dishonest admitted source can fabricate a structurally
valid history” as the explicit residual boundary (`docs/THREAT-MODEL.md` row
“Fabrication of delivery fields or timestamps”; `docs/AUDIT.md` “What is fixed
versus assumed”). Disclosed recomputation only checks that the disclosed
openings match the signed commitments and that the algorithm accepts them; it
does not check that the openings came from a physical session
(`docs/BINDING.md` §6 “Explicit boundaries”).

**Detectable in principle?** **No, not by the reference verifier.** If the
modified client uses an admitted capture key and produces a self-consistent
record that the model accepts, attestation and recomputation both pass. This is
not a hash or signature break; it is the trust assumption the protocol names.
A verifier that does not trust the capture authority must not admit the proof.

**What would change the answer.** A trusted execution/attestation chain for the
capture client, independent capture authorities with cross-checking, or
out-of-band evidence that the session occurred. None is in v0. The protocol
already requires the relying party to select capture authorities independently;
the attack succeeds only against a policy that admits the attacker's key.

### 3.6 Splicing segments from several sessions

**Attack.** Take wording from two or more sessions and present it as one fresh
composition. There are two materially different representations:

- **Represented as copy/inherited.** The record contains `copy` transactions
  and the scope uses `inherited` origins. HWP can see the dependency and
  parent proof.
- **Represented as typed.** A modified client re-emits the same characters as
  direct device insertions in one new record, with no `copy` transaction.

**What HWP checks.** For the first representation, `fresh-composition` rejects
copied occurrences; `wording-origin` can carry literal ancestry only with the
exact parent proof, predeclared parent capture and actual root equality
(`SPECIFICATION.md` §7; `docs/ALGORITHM.md` “Deterministic reconstruction”;
`docs/BINDING.md` §4). The verifier checks the maximal partition, parent proof
verification, byte coverage and root equality. For the second representation,
there is no copy edge to check; the events look like direct typing, and the
same reasoning as §3.5 applies.

**Detectable in principle?** **Partial.** Represented copy/inherited splicing is
detectable as *not fresh composition* (and may be certifiable as
`wording-origin`, which explicitly “does not certify human authorship of the
current assembly” — `SPECIFICATION.md` §2). Fabricated typed splicing is not
detectable by the verifier; it is the modified-client case. The protocol's
source veto is record-local and only covers captured earlier external
insertions (`algorithm/v0_3/SPECIFICATION.md` §5), so uncaptured or
cross-session sources are outside it.

**What would change the answer.** Require an unbroken, source-side session
provenance for every atom (so a new record cannot claim old atoms as newly
typed), plus trusted capture. For represented copies, the existing parent-proof
machinery is the right model; the gap is the client that simply omits the copy
transaction.

## 4. Additional attack: self-issued production trust anchor

**Attack.** The attacker mints a `production` verification policy that admits
an “empirical” release the attacker also minted, with arbitrary report objects,
an “evaluated” capture profile whose evaluation object is arbitrary bytes, and
the attacker's capture/evaluator keys. The policy pin is computed from the
attacker's own policy. A fabricated trace is then signed under that release.
This is executable (see `audit/attacks/attack_07_self_issued_production.py`).

**What HWP checks.** The verifier checks that the policy bytes hash to the
supplied pin, that the release is in the policy, that the dossier has the right
shape and six report roles, that the candidate release and dossier agree, and
that the keys are authorized. It does not check that the reports describe a
real study, that the curator is independent, or that the policy pin came from
an independent source. The specification says the pin “must come from an
independent relying-party choice, not the submitted proof”
(`README.md`; `SPECIFICATION.md` §3: “A pin read from the same untrusted bundle
is not an independent trust decision”). The audit's row “Self-approved
record/model/fixture” states the boundary: “A relying party deliberately
trusting dishonest curators still has a dishonest trust premise”
(`docs/THREAT-MODEL.md`).

**Detectable in principle?** **No, not by the verifier alone.** This is not a
cryptographic forgery; it is a trust-anchor substitution. Against a relying
party who independently pins an honest policy, the attack fails at the first
release/key check. Against a verifier that accepts the attacker's pin, it
produces the protocol's literal `VALID-HWP / HUMAN-WRITTEN` output. The
protocol's public meaning is therefore policy-relative: the verifier reports
what the pinned policy admits, not what the physical world contained.

**What would change the answer.** Out-of-band policy distribution, curator
signatures over the exact release/dossier, a transparency log of admitted
releases, and a rule that a production policy must not admit self-issued
empirical releases. The verifier can check signatures and freshness; it cannot
manufacture an independent trust decision.

## 5. Cross-cutting limits

### 5.1 Signatures are not observation

A valid signature proves that a key holder signed exact bytes
(`SPECIFICATION.md` §4). It does not prove that the bytes describe a physical
event, that the key holder is a human, or that the key holder is independent of
the attacker. The protocol says this repeatedly (`SPECIFICATION.md` §3, §6, §8;
`docs/BINDING.md` §6; `docs/THREAT-MODEL.md` “Guarantees that do not follow”).

### 5.2 Disclosed recomputation is consistency, not truth

`disclosed-v1` opens the private history and runs the real algorithm
(`SPECIFICATION.md` §9; `docs/BINDING.md` §5-6). It catches a lying evaluator
who asserts a result the disclosed trace does not support; the frozen suite
contains exactly that regression (`protocol/v0/tests/test_protocol.py::
test_attestor_lie_is_not_cryptographically_discoverable`). It does not catch a
capture source that fabricated a trace which the algorithm accepts. The
protocol says so: “Disclosed recomputation still cannot distinguish a
fabricated but admitted trace that passes the actual detector from the same
trace honestly observed” (`docs/THREAT-MODEL.md` “Guarantees that do not
follow”).

### 5.3 The feature representation has known collisions

The 179-feature map has a retained exact collision under changed meaningful
wording (`algorithm/v0_3/AUDIT.md` last rows; `docs/ALGORITHM.md`
“Falsifiable limitations retained”). Deeper trees on the same features cannot
recover discarded information. This is a limit on any claim of semantic
authorship detection, independent of the capture debate.

### 5.4 What the shipped package can and cannot output

Under the shipped conformance policy, the public verifier always projects
`TEST-ONLY / NOT PROVABLE`; no conformance example exits 0
(`docs/OUTPUT.md` “Public verification projection”; `docs/CONFORMANCE.md`
“Reproduce locally”). The literal `VALID-HWP / HUMAN-WRITTEN` output is
reachable only with a production policy that admits an empirical release and
evaluated capture profile. No such release/profile exists in the distribution
(`README.md`; `docs/AUDIT.md` “Deliberate scope decisions”). The production
policy is an external trust input, not a property of the proof.

## 6. Summary table

| Attack | Detectable by HWP v0 in principle? | Governing sections |
|---|---|---|
| Replay genuine trace (same proof) | No; re-verification is valid | `SPECIFICATION.md` §6; `THREAT-MODEL.md` row “Reusing valid history as a new session” |
| Replay/re-commit events as a new session | No; requires source integrity/external comparison | `SPECIFICATION.md` §6; `THREAT-MODEL.md` same row |
| Synthetic human-like timing | No protocol guarantee; statistical only | `ALGORITHM.md` “Falsifiable limitations retained”; `THREAT-MODEL.md` “Guarantees that do not follow” |
| Human retypes AI text | No; no source observation | `SPECIFICATION.md` §2; `ALGORITHM.md` “Deterministic reconstruction”; `AUDIT.md` “Deliberate scope decisions” |
| Autotyper / HID | No, if observation-equivalent; needs trusted device path | `SPECIFICATION.md` §3, §5, §6; `THREAT-MODEL.md` row “Fabrication of delivery fields or timestamps” |
| Modified client fabricates capture | No; admitted source can lie | `SPECIFICATION.md` §3, §6, §8; `BINDING.md` §6; `AUDIT.md` “What is fixed versus assumed” |
| Splice, represented as copy/inherited | Yes for “not fresh”; wording-origin only | `SPECIFICATION.md` §7; `ALGORITHM.md` “Deterministic reconstruction”; `BINDING.md` §4 |
| Splice, relabeled as typed | No; modified-client case | `SPECIFICATION.md` §7; `THREAT-MODEL.md` row “Fabrication of delivery fields or timestamps” |
| Self-issued production policy/release | No; policy pin is the trust anchor | `SPECIFICATION.md` §3, §12; `THREAT-MODEL.md` row “Self-approved record/model/fixture” |

## 7. Consequence for the claim

HWP v0 can honestly certify a **policy-relative statement about a captured
trace**: under the exact policy, release, model, capture profile and
authorities the relying party independently selected, every selected scalar
passes the frozen computation over the committed observations. It cannot
certify that a human authored the text, that human hands produced the
keystrokes, that the capture client was honest, or that the wording was not
retyped from an AI system. The strongest defensible claim is stated in
`audit/REPORT.md`.
