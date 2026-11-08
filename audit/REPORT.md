# HWP v0 adversarial audit report

**Branch:** `hwp-adversarial-audit`
**Audit date:** 2026-11-08 (Europe/Berlin)
**Frozen input:** `protocol/v0`, definition `58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4`
**Constraint honoured:** no file under `protocol/v0/` was modified; no Mac application was built, started or observed.

## 1. Verdict

HWP v0 cannot prove human authorship. Under the conformance policy used by the
frozen fixtures, the forged variants of all six required attack classes were conditionally
accepted by the real behavioural computation but projected to `TEST-ONLY / NOT PROVABLE`;
among those classes, the only rejected controls were an explicit paste and a copy
represented as fresh composition. The sole literal `VALID-HWP / HUMAN-WRITTEN` result was obtained by minting a production
policy that admitted a fabricated “empirical” release, arbitrary report bytes, an arbitrary
capture evaluation and the attacker's capture key: that proof passed the Python R verifier
in both attestation and full recomputation, and the independent JavaScript V verifier. This
is not a hash or signature break — it is the verifier faithfully applying the trust anchor
it was given. HWP v0 can honestly certify a **policy-relative consistency statement about a
captured trace**; it cannot certify that a human authored the text, that human hands
produced the events, that the capture client was honest, or that the wording was not
retyped from an AI system.

## 2. What was executed

| Command | Result | Raw evidence |
|---|---|---|
| `python3 tools/check_preparation.py` | `PASS` (all five checks; frozen protocol PASS) | [`01-check-preparation.txt`](evidence/01-check-preparation.txt) |
| `python3 tools/bootstrap_protocol.py` | `PASS` (69 files, definition and freeze digests) | [`02-bootstrap-protocol.txt`](evidence/02-bootstrap-protocol.txt) |
| `cd protocol/v0 && PYTHONDONTWRITEBYTECODE=1 ../../.venv-hwp/bin/python run_checks.py` | **178 tests, 0 failures, 0 errors, 0 skipped**; independent JS verifier `PASS`; deterministic vectors `true` | [`03-frozen-run-checks.txt`](evidence/03-frozen-run-checks.txt) |
| `cd protocol/v0 && PYTHONDONTWRITEBYTECODE=1 ../../.venv-hwp/bin/python tools/check_freeze.py` | `PASS`, 67 inventoried files | [`04-check-freeze.txt`](evidence/04-check-freeze.txt) |
| `.venv-hwp/bin/python audit/attacks/run_all.py` | all 7 attack scripts exit 0; frozen tree untouched before/after | [`17-run-all.txt`](evidence/17-run-all.txt), [`attack-summary.json`](evidence/attack-summary.json) |

The frozen suite reports `Ran 178 tests in 25.792s`, `OK`, `"failures": 0`,
`"errors": 0`, `"independent_verifier": {"status": "PASS"}`, and
`"vectors_equal_across_hashseed_0_987_and_frozen_file": true`
([`03-frozen-run-checks.txt`](evidence/03-frozen-run-checks.txt) lines 182–214,
405). The audit environment is recorded in [`06-environment.txt`](evidence/06-environment.txt):
Python 3.12.3, `cryptography` 46.0.4, NumPy 2.3.5, SciPy 1.17.0, Node v24.22.2,
OpenSSL 3.0.13, Linux aarch64. No Mac application, Word/Pages, provider, signing,
notarization or real human session was used.

Protocol section citations below refer to the line-numbered excerpts in
[`05-protocol-citations.txt`](evidence/05-protocol-citations.txt), produced with
`nl -ba <file> | sed -n '<range>p'` on the frozen files; no frozen file was edited.
Every attack script imports the frozen verifier and fixtures read-only; none patches
verifier code, expected statuses or the frozen package. The runner checks
`git status --porcelain -- protocol/v0` and `git diff --stat -- protocol/v0` before and
after the suite and records both as clean ([`17-run-all.txt`](evidence/17-run-all.txt)).

## 3. Findings

`TEST-ONLY / NOT PROVABLE` is **not detection**. It is the protocol's fixed projection for
conformance releases (`protocol/v0/SPECIFICATION.md` §9, lines 164–172). In the rows marked
“conditional pass”, the real replay → features → model → scope → lineage computation
returned `HUMAN-WRITTEN`; only the conformance policy label prevented a production claim.
The internal result is recorded as `computed_internal_result` in each evidence file.

| # | Attack | Detectable by HWP v0 in principle? | Internal algorithm | Public Python R verifier | Public JavaScript V verifier | Evidence |
|---|---|---|---|---|---|---|
| 1 | Replay the same valid proof | **No** — re-verification is valid by design; hidden duplicates need source integrity/external comparison | `HUMAN-WRITTEN` | `TEST-ONLY / NOT PROVABLE` (attested and recomputed) | `TEST-ONLY / NOT PROVABLE` | [`10-replay.txt`](evidence/10-replay.txt) |
| 2 | Re-commit the same events under a fresh session/salts | **No** — new signed start over old observations; no cross-session registry | `HUMAN-WRITTEN` | `TEST-ONLY / NOT PROVABLE` (attested and recomputed) | `TEST-ONLY / NOT PROVABLE` | [`10-replay.txt`](evidence/10-replay.txt) |
| 3 | Synthetic keystroke timing generated to mimic humans | **No as a protocol guarantee**; a trained model may statistically separate some generators | `HUMAN-WRITTEN` | `TEST-ONLY / NOT PROVABLE` | `TEST-ONLY / NOT PROVABLE` | [`11-synthetic-timing.txt`](evidence/11-synthetic-timing.txt) |
| 4 | Human retypes AI-generated text | **No** — no screen, clipboard, gaze or source observation; direct insertions remain candidates | `HUMAN-WRITTEN` | `TEST-ONLY / NOT PROVABLE` | `TEST-ONLY / NOT PROVABLE` | [`12-retype-ai.txt`](evidence/12-retype-ai.txt) |
| 4a | Control: same final text inserted as explicit paste | **Yes** — the paste transaction is visible and unsupported | `NOT PROVABLE` | issuance refused: `Reject: hwp-not-qualifying` | not reached (no proof) | [`12-retype-ai.txt`](evidence/12-retype-ai.txt) |
| 5 | Autotyper / HID device driven by software | **No**, if observation-equivalent to a keyboard; no hardware provenance | `HUMAN-WRITTEN` | `TEST-ONLY / NOT PROVABLE` | `TEST-ONLY / NOT PROVABLE` | [`13-autotyper.txt`](evidence/13-autotyper.txt) |
| 6 | Modified client fabricates the whole capture | **No** — signatures authenticate the key, not the client's honesty | `HUMAN-WRITTEN` | `TEST-ONLY / NOT PROVABLE` (attested and **recomputed**) | `TEST-ONLY / NOT PROVABLE` | [`14-modified-client.txt`](evidence/14-modified-client.txt) |
| 7 | Splice two sessions, represented as copy/inherited | **Partial** — fresh composition is rejected; wording-origin can carry ancestry | `HUMAN-WRITTEN` (`wording-origin`) | `TEST-ONLY / NOT PROVABLE` (`claim: wording-origin`) | `TEST-ONLY / NOT PROVABLE` | [`15-splice.txt`](evidence/15-splice.txt) |
| 7a | Control: copied segments claimed fresh | **Yes** — copy edge is visible | `NOT PROVABLE` | issuance refused: `Reject: hwp-not-qualifying` | not reached (no proof) | [`15-splice.txt`](evidence/15-splice.txt) |
| 8 | Splice relabeled as typed by a modified client | **No** — no copy edge; same as modified client | `HUMAN-WRITTEN` (`fresh-composition`) | `TEST-ONLY / NOT PROVABLE` | `TEST-ONLY / NOT PROVABLE` | [`15-splice.txt`](evidence/15-splice.txt) |
| 9 | Self-issued production policy over a fabricated empirical release | **No** — the policy pin is the trust anchor; the verifier cannot establish its provenance | `HUMAN-WRITTEN` | **`VALID-HWP / HUMAN-WRITTEN`** (attested and recomputed) | **`VALID-HWP / HUMAN-WRITTEN`** | [`16-self-issued-production.txt`](evidence/16-self-issued-production.txt) |
| 9a | Control: identical proof under a conformance-purpose policy | N/A | `HUMAN-WRITTEN` | `TEST-ONLY / NOT PROVABLE` | `TEST-ONLY / NOT PROVABLE` | [`16-self-issued-production.txt`](evidence/16-self-issued-production.txt) |
| 9b | Control: identical proof, independently wrong pin | N/A | N/A | `NO-VALID-HWP / NOT PROVABLE` (`external-policy-pin`) | `NO-VALID-HWP / NOT PROVABLE` (`external-policy-pin`) | [`16-self-issued-production.txt`](evidence/16-self-issued-production.txt) |

### 3.1 What each row actually demonstrates

**Replay (1–2).** The second proof commits the identical record bytes under a new
start/session/salts and has a different proof identity. The verifier returns the same
public projection, and the internal algorithm returns `HUMAN-WRITTEN`. The protocol's own
threat model says this is expected: “Re-verifying the same old proof is valid. Hidden
duplicate real-time capture or undisclosed forks require source integrity/external
comparison” (`protocol/v0/docs/THREAT-MODEL.md`, “Reusing valid history as a new session”).
Fresh IDs and nonces “are not proof of physical input, trusted wall time or one attempt per
person” (`protocol/v0/SPECIFICATION.md` §6, line 120). Evidence:
[`10-replay.txt`](evidence/10-replay.txt).

**Synthetic timing (3).** The trace uses a hand-written variable-delay schedule with three
sentence-like pauses; 312 transactions over 936 observations, all `source: device`, no
human measurement. It is conditionally accepted. The protocol says there is no universal
defence against behavioural imitation (`protocol/v0/README.md` line 44) and fixes the
observational-equivalence bound `Q(A) >= P(A) - TV(P,Q)`
(`protocol/v0/docs/ALGORITHM.md` “Falsifiable limitations retained”). Evidence:
[`11-synthetic-timing.txt`](evidence/11-synthetic-timing.txt).

**Retyping (4).** The typed and pasted cases share the same final text. The typed case is
accepted; the paste control is refused with `hwp-not-qualifying`. This is the cleanest
demonstration that HWP sees the *transaction type*, not the source of the words. The
normative target excludes “mechanical transcription” (`protocol/v0/SPECIFICATION.md` §2,
line 17), but the observation alphabet contains no screen, clipboard, gaze or external-source
inventory (`protocol/v0/docs/AUDIT.md` “Deliberate scope decisions”). The algorithm says:
“Direct candidate insertions remain new candidates even when informed by earlier external
ideas: there is no semantic contamination rule”
(`protocol/v0/docs/ALGORITHM.md` “Deterministic reconstruction”). Evidence:
[`12-retype-ai.txt`](evidence/12-retype-ai.txt).

**Autotyper/HID (5).** The fixed 32 ms cadence is machine-like, but the client labels the
source `device` and the events are structurally valid. The protocol treats source as an
observed capture classification, not a writer declaration
(`algorithm/v0_3/TELEMETRY.md` “What a collector must actually observe”;
`algorithm/v0_3/SPECIFICATION.md` §3), and `faithful-device-origin` and
`native-delivery-binding` are capture assumptions, not verified facts
(`protocol/v0/SPECIFICATION.md` §5; §3). Evidence:
[`13-autotyper.txt`](evidence/13-autotyper.txt).

**Modified client (6).** The final text was chosen first; the client synthesized every
keystroke, delivery, mutation and pause, then signed the capture with the admitted key.
Attestation and disclosed recomputation both pass. The protocol states the boundary:
“Neither mode proves that the source did not fabricate data before committing it”
(`protocol/v0/SPECIFICATION.md` §3); “Its root is not a proof that this collector was
honest before signing” (§6); “Low-level possession of an issuer seed can sign lies”
(§8). `docs/BINDING.md` §6: “Neither independently verifies the physical truth of a
dishonest capture source's initially fabricated observations.” Evidence:
[`14-modified-client.txt`](evidence/14-modified-client.txt).

**Splicing (7–8).** The represented copy is correctly limited to `wording-origin`; the
fresh-copy control is refused. The relabeled typed version has the same final document but
no copy edge, and is conditionally accepted as `fresh-composition`. This is the strongest
*protocol-level* positive result: HWP can distinguish represented ancestry, but not a
client that omits the ancestry. Evidence:
[`15-splice.txt`](evidence/15-splice.txt).

**Self-issued production (9).** The attack mints an empirical release whose six reports and
capture evaluation are arbitrary bytes, labels the permissive fixture model
`validated-release`, and mints a policy that admits all of it. The literal result is
`VALID-HWP / HUMAN-WRITTEN` in both verifiers, including full Python recomputation. The
control on the identical proof under a conformance-purpose policy is `TEST-ONLY`; the
control with an independently wrong pin is `NO-VALID-HWP` (`external-policy-pin`). This
shows the label is a function of the external trust input, not of the trace. The
specification requires the pin to come from an independent relying-party choice
(`protocol/v0/SPECIFICATION.md` §3; `protocol/v0/README.md` line 36) and says report hashes
and approval signatures do not establish ground truth (§12; `docs/THREAT-MODEL.md`
“Self-approved record/model/fixture”). Evidence:
[`16-self-issued-production.txt`](evidence/16-self-issued-production.txt).

### 3.2 Additional retained limitation: feature collision

The frozen suite deliberately keeps an exact 179-feature collision: four meaningful word
replacements (`writer→reader`, `claim→point`, `changes→revises`, `follows→studies`) leave
all feature vectors identical, and the test passes
(`protocol/v0/tests/test_algorithm.py#L248-L253`;
[`03-frozen-run-checks.txt`](evidence/03-frozen-run-checks.txt) line 25). The
algorithm audit calls this “not solved by current feature family”
(`algorithm/v0_3/AUDIT.md` last rows). Deeper trees on the same features cannot recover
information the representation discarded. This is independent of the capture debate and
limits any claim of semantic authorship detection.

## 4. The strongest honest claim HWP can make

HWP v0 can honestly certify:

> **Under an independently selected verification policy that admits this exact release,
> model, capture profile and capture/evaluator authorities, every selected scalar of this
> exact document passes the frozen `hwp-a/v0` computation for its declared claim kind over
> the committed capture trace; the proof binds the document, scope, release, trace, lineage
> and result, and the required signatures verify.**

That is a conditional, policy-relative statement about a captured trace. It is not any of
the following:

- **“Authored by a human.”** No. The protocol explicitly does not assert mental causation,
  personhood, legal authorship, a physical typist's identity, a creation date or absence of
  AI influence (`protocol/v0/SPECIFICATION.md` §2, lines 17–30; `protocol/v0/docs/OUTPUT.md`
  lines 46–58).
- **“Typed by human hands in a trusted client.”** Not unconditionally. The “trusted client”
  clause is doing all the work: a modified client with the admitted key can fabricate a
  self-consistent capture (finding 6), and a hardware autotyper is a keyboard to the OS
  (finding 5). If an independent relying party has separately established that the client
  and sensor are honest, and that the admitted path actually observed a human, then the
  proof can support a statement about *what that admitted capture reported*. HWP v0 does not
  establish those premises; it explicitly says no trusted native sensor path or evaluated
  native capture profile is shipped (`protocol/v0/README.md` line 44;
  `protocol/v0/SPECIFICATION.md` §1 line 5).
- **“Fresh composition” in the sense of original human thought.** The protocol's own
  definition is narrower: new wording in the target record that passes the pinned
  computation. A human retyping AI text creates new direct insertions and is conditionally
  accepted (finding 4); the algorithm has no semantic contamination rule
  (`protocol/v0/docs/ALGORITHM.md` “Deterministic reconstruction”).
- **A production claim from the shipped package.** No production-admitted release or
  evaluated capture profile exists. The production approval set is empty; every supplied
  positive fixture is `TEST-ONLY` (`protocol/v0/README.md` lines 13, 40;
  `protocol/v0/SPECIFICATION.md` §1). The literal `HUMAN-WRITTEN` output in finding 9 is
  reachable only by supplying a production policy that admits an attacker-minted empirical
  release — a trust decision, not evidence of human writing.

In short: **HWP v0 can certify “this admitted trace passes this pinned computation under
this policy.” It cannot certify “a human wrote this.”** The first is useful for provenance
and audit; the second is the claim a reader will naturally hear, and it is not supported.

## 5. What would close each gap

These are recommendations for a **future version or deployment**, not changes to the frozen
v0 tree. Some gaps are not closable by protocol changes at all; the table says which.

| Gap | Change that would narrow it | Residual limit |
|---|---|---|
| Replay / re-commit under a new session | Source-side transparency log or witnessed one-time session declaration; trusted clock; cross-session duplicate detection; require a fresh external nonce in capture-start | An offline verifier still cannot discover an undisclosed fork or a capture never published. A log needs an authoritative online source. |
| Synthetic timing | Richer observation channel (hardware timing, pressure, liveness) and an empirically admitted model with the required `adaptive_simulation` / `scripted_input` attack families at B=1 and B=100 | If the attack's observation distribution equals the genuine distribution, no observer-only rule can distinguish it (`Q(A) >= P(A) - TV(P,Q)`). No universal guarantee is possible. |
| Human retypes AI text | Capture source exposure (screen/OCR, clipboard/application provenance) under a separate privacy/consent contract, or narrow the claim to “not copied from captured sources” | A human can memorize, read from another device, or retype; observation-only capture cannot prove the mental source. A claim change is more honest than a detector promise. |
| Autotyper / HID | Hardware-backed input provenance / trusted sensor path / device attestation; possibly physical-presence evidence outside the current observation alphabet | Device attestation proves which device produced events, not that a human actuated it. A robot can type on a trusted keyboard. |
| Modified client fabricates capture | Trusted execution/remote attestation of the capture client; reproducible builds; multiple independent capture authorities; out-of-band session evidence; curator audits | An authorized signer can still lie. This is a trust-anchor problem, not a hash problem. |
| Splicing, represented as copy/inherited | Existing parent-proof and maximal-partition checks already handle represented copies; make copy/inherited representation mandatory at the trusted capture layer | A modified client can omit the copy transaction and relabel the same atoms as typed. Same residual as modified client. |
| Splicing, relabeled as typed | Source-side per-atom provenance bound to an unbroken session identity; trusted capture client | A fabricated typed history is indistinguishable from a genuine one if the client/key is admitted. |
| Self-issued production policy/release | Out-of-band policy distribution; curator signatures over exact release/dossier; transparency log of admitted releases; release-approval quorum; explicitly reject self-issued empirical releases | The verifier cannot infer curator honesty from hashes. The independent policy pin is the trust anchor; if the relying party trusts the attacker's pin, no verifier can save it. |
| Exact feature collision | New feature representation and a new versioned computation, with fresh empirical validation | No fix within v0; deeper trees on the same features cannot recover discarded information. |

The protocol's empirical contract — eight attack families at B=1 and B=100, adverse handling
of ambiguity, per-path/language/claim cells, exact binomial eligibility and a new held-out
evaluation (`protocol/v0/docs/ALGORITHM.md` “Empirical release contract”;
`algorithm/v0_3/SPECIFICATION.md` §9) — is the right mechanism for **statistical risk**
against modelled attacks. It cannot turn an observer-only capture into proof of mental
causation. The distinction between “measured risk under a declared distribution” and
“authorship” must remain explicit in any marketing or UI.

## 6. Why finding 9 is not a cryptographic break

The verifier checks that the policy bytes hash to the supplied pin, that the release is in
the policy, that the dossier has the right shape and six report roles, that the candidate
release and dossier agree, and that the capture/evaluator keys are authorized. It does not
check that the reports describe a real study, that the curator is independent, or that the
pin came from an independent source. The specification says exactly this: “A pin read from
the same untrusted bundle is not an independent trust decision”
(`protocol/v0/SPECIFICATION.md` §3). The threat model's “Self-approved
record/model/fixture” row says: “A relying party deliberately trusting dishonest curators
still has a dishonest trust premise” (`protocol/v0/docs/THREAT-MODEL.md`).

Against a relying party who independently pins an honest production policy that admits only
curator-approved releases and keys, the fabricated release fails at `release-not-authorized`
or `capture-authority`. The attack succeeds only when the verifier is configured to trust
the attacker's policy. That is why the result is evidence about **what a policy-relative
label means**, not evidence that HWP's cryptography is broken.

## 7. Reproduction

Setup (not committed; `.venv*/` is gitignored):

```sh
python3 -m venv .venv-hwp
.venv-hwp/bin/python -m pip install -r protocol/v0/requirements.txt
```

Checks:

```sh
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
(cd protocol/v0 && PYTHONDONTWRITEBYTECODE=1 ../../.venv-hwp/bin/python run_checks.py)
(cd protocol/v0 && PYTHONDONTWRITEBYTECODE=1 ../../.venv-hwp/bin/python tools/check_freeze.py)
```

Attacks:

```sh
.venv-hwp/bin/python audit/attacks/run_all.py
```

Individual scripts:

```sh
.venv-hwp/bin/python audit/attacks/attack_01_replay.py
.venv-hwp/bin/python audit/attacks/attack_02_synthetic_timing.py
.venv-hwp/bin/python audit/attacks/attack_03_retype_ai.py
.venv-hwp/bin/python audit/attacks/attack_04_autotyper.py
.venv-hwp/bin/python audit/attacks/attack_05_modified_client.py
.venv-hwp/bin/python audit/attacks/attack_06_splice.py
.venv-hwp/bin/python audit/attacks/attack_07_self_issued_production.py
```

The runner saves each attack's exact stdout/stderr and exit code under
`audit/evidence/`, checks the frozen tree before and after, and writes
[`attack-summary.json`](evidence/attack-summary.json). The protocol excerpts cited
above are captured verbatim in [`05-protocol-citations.txt`](evidence/05-protocol-citations.txt).

## 8. Limitations of this audit

- **Synthetic traces.** Every positive trace is a conformance fixture built by the frozen
  `Builder`; no real human session, participant corpus or trained real-world detector was
  used. The audit measures verifier logic and trust boundaries, not detector accuracy or
  false-certification rates.
- **Permissive model.** The attack fixtures use the deliberately permissive
  `permissive_fixture_model`; it is a test double, not a trained human-writing model. A
  production model could reject some of these traces statistically; that would not change
  the in-principle analysis of replay, retyping, autotyper/HID, modified clients, splicing
  or self-issued policy.
- **The “AI text” is a local stand-in.** `attack_03_retype_ai.py` uses a locally written
  paragraph as a stand-in for machine-generated text; no AI service was called. The
  observation-contract argument does not depend on the particular string.
- **The production forgery requires an attacker-minted policy.** It is not a break against
  an honestly pinned production policy. The honest finding is the trust boundary, not a
  signature forgery.
- **No Mac app.** The repository's product/mac tree is a contract, not a built application.
  Native capture, trusted sensor paths, providers, export and notarization were not
  measured.
- **No independent security review.** This is an adversarial audit by the same agent that
  read the frozen package; it is not a third-party audit. The frozen suite's own warnings
  say no human-detection accuracy, third-party security review or eternal cryptographic
  lifetime is claimed ([`03-frozen-run-checks.txt`](evidence/03-frozen-run-checks.txt)
  lines 405–412).

## 9. Evidence index

| File | Contents |
|---|---|
| [`01-check-preparation.txt`](evidence/01-check-preparation.txt) | Raw `tools/check_preparation.py` output and exit code |
| [`02-bootstrap-protocol.txt`](evidence/02-bootstrap-protocol.txt) | Raw `tools/bootstrap_protocol.py` output and exit code |
| [`03-frozen-run-checks.txt`](evidence/03-frozen-run-checks.txt) | Full 178-test run, independent JS verifier, deterministic vector check, result JSON |
| [`04-check-freeze.txt`](evidence/04-check-freeze.txt) | Frozen freeze-checker output |
| [`05-protocol-citations.txt`](evidence/05-protocol-citations.txt) | Line-numbered excerpts of every cited protocol section |
| [`06-environment.txt`](evidence/06-environment.txt) | Host, Python, Node, OpenSSL, package versions, frozen-tree status |
| [`10-replay.txt`](evidence/10-replay.txt) | Replay attack raw output, Python and JS verdicts |
| [`11-synthetic-timing.txt`](evidence/11-synthetic-timing.txt) | Synthetic timing attack raw output |
| [`12-retype-ai.txt`](evidence/12-retype-ai.txt) | Retype-AI typed case and explicit-paste control |
| [`13-autotyper.txt`](evidence/13-autotyper.txt) | Autotyper/HID attack raw output |
| [`14-modified-client.txt`](evidence/14-modified-client.txt) | Modified-client fabricated capture, attestation and recomputation |
| [`15-splice.txt`](evidence/15-splice.txt) | Inherited splice, fresh-copy control, typed relabel |
| [`16-self-issued-production.txt`](evidence/16-self-issued-production.txt) | Attacker production policy, conformance-policy control, wrong-pin control |
| [`17-run-all.txt`](evidence/17-run-all.txt) | Full attack-run log and frozen-tree check |
| [`attack-summary.json`](evidence/attack-summary.json) | Machine-readable summary of every collected verdict |
