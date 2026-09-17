# Human Writing Protocol v0

**Normative revision 0.0.0. Wire identifier `hwp/0`.**

This is a frozen *conformance protocol*: an exact observation, inference, evidence and verification contract. It is not an empirical approval of a human-writing detector. No production approval, evaluated native capture path or model trained on real human sessions accompanies this release. The only supplied acceptance examples are machine-generated conformance fixtures. A conforming production verifier rejects those examples as Human Writing Proofs.

## 1. Normative material and interpretation

MUST, MUST NOT, SHOULD and MAY specify conformance obligations. The complete normative set is this document; `docs/ALGORITHM.md`, `docs/BINDING.md`, `docs/OUTPUT.md`, `docs/THREAT-MODEL.md`, `docs/CONFORMANCE.md`, `docs/FEATURE_NAMES.json`; the referenced schema files; and the explicitly incorporated baseline algorithm definitions. The `manifests/protocol.cbor.hex` descriptor identifies their exact bytes. The portable program manifest identifies the exact reference computation. Encodings, cardinality/resource bounds, equations and state transitions are mandatory; illustrative scenarios are not additional hidden rules.

The A03 and C1 documents in `baseline/` preserve the reviewed inputs. They are not competing current specifications. Only the A03 algorithm definitions explicitly incorporated by `docs/ALGORITHM.md` are normative for v0, with the amendments in that document. C1 is retained for audit history, not as an alternative wire format. Previous publication-status text, approval flags, model IDs and signatures do not authorize v0. There is no automatic upgrade of a record lacking actual native-delivery observations.

A discrepancy between the frozen specification, reference computation and vector outputs is a protocol defect. An implementation MUST NOT select whichever interpretation grants a positive result. It must withhold the affected result and identify the discrepancy. Repair of an interpretation-bearing defect requires a distinct version/definition, retaining the original interpretation for historical assessment. Frozen does not mean infallible or adopted by a standards body.

## 2. What is asserted

The target is an *observed composition process*: wording produced through qualifying human writing rather than imported wording, mechanical transcription, automation, replay or staged imitation. Independent composition after AI-informed research is permitted. The observations do not directly reveal thought. No signature makes an ambiguous mental cause observable.

The two HWP outcomes are **HUMAN-WRITTEN** and **NOT PROVABLE**. NOT PROVABLE includes insufficient observations, unsupported input paths, failed binding, rejected empirical profiles, non-admission, missing evidence and unavailable trust. It is never an assertion that the document is AI-generated, fraudulent, plagiarized or not human.

A positive result must identify one of two claims:

- `fresh-composition`: every selected scalar is a newly created, qualifying origin in the target record. Internal or cross-record copying cannot count as new composition.
- `wording-origin`: every selected scalar has qualifying wording ancestry. Internal duplicate occurrences may retain that ancestry; externally inherited ranges additionally require the exact source proof and actual captured lineage. This does not certify human authorship of the current assembly, new argument structure, originality or fresh work by its assembler.

The default objective is fresh composition. The second claim exists to prevent a false inference when proven wording is reused; it is not an alternative way to label copying fresh composition. Claim kind is release-bound, capture-precommitted and signed. A consumer must not omit it from a positive interpretation.

Whole-document and selected-range claims are distinct. Excluded quotations remain bound as part of the exact document but are not certified. A selected-range claim cannot silently become a whole-document claim. Character-level origin bookkeeping is not character-level certainty about cognition: behavioural evidence is contextual, evaluated over fixed neighbourhoods.

A statement does not assert absence of AI influence, accuracy of the content, ownership, legal authorship, personhood, a physical typist's identity, a creation date, thinking duration or protection against every possible adversary.

## 3. Conditional guarantee and trust inputs

A production positive result requires:

```
external policy admits the exact protocol, release and authorities
AND exact document, scope, target and provenance bindings hold
AND required capture and evaluator signatures verify
AND the required evaluation mode succeeds
AND every selected contribution qualifies under the pinned computation
AND no mandatory condition was downgraded or omitted.
```

In attested mode, the fourth and fifth conditions are *asserted by the admitted evaluators*. In disclosed mode the verifier also recomputes them. Both modes rely on admitted capture sources for the truth and completeness of observations, and on independent release approval for the empirical interpretation. Neither mode proves that the source did not fabricate data before committing it.

Assuming collision/second-preimage resistance, signature unforgeability, correct implementations and honest role fulfilment, modification or substitution of the bound objects is detectable. That is distinct from the statistical hypothesis that the observed process distinguishes composition from an attack. The error terms are not independent; cryptographic, capture, evaluator, model and scope failures must not be multiplied to invent a tiny overall error probability.

The relying party supplies exact policy bytes and their independently trusted SHA-256 pin. A pin read from the same untrusted bundle is not an independent trust decision. Two verifiers given the same complete evidence, protocol definition, policy, mode and installed interpretation must agree on the outcome; different independently selected trust policies may legitimately disagree. Policy disagreement is not an encoding ambiguity.

No runtime network query, account, vendor endpoint, repository branch or company-controlled registry is required. Artifact URLs are not trusted instructions or executable locations. Unknown profiles, required algorithms or versions produce NOT PROVABLE, without fallback.

## 4. Encodings and primitive profile

All wire objects use RFC 8949 §4.2.1 core deterministic CBOR: shortest lengths and integer forms, definite lengths, and map keys sorted by the unsigned bytewise lexicographic order of their deterministic encodings. This is **not** the legacy length-first ordering. Map keys are text or integers. Duplicate/equivalent keys, indefinite forms, floats, undefined/simple values other than false/true/null, invalid UTF-8, lone surrogates, trailing bytes and unregistered tags are rejected. Tag 18 is admitted as a syntactic CBOR value; a signature additionally must satisfy the COSE structure below.

Generic CBOR integers range from −2^63 through 2^64−1. Typed protocol counters and algorithm JSON-compatible values are narrower: integers within ±(2^53−1), and usually nonnegative. A Boolean is never an integer. Strings are exact Unicode scalar sequences. Neither text normalization nor newline conversion is performed.

`Ref = {sha256: bstr32, size: uint}` identifies the raw bytes of an object using ordinary SHA-256, with its exact byte length. Every dereference checks both members, including cached objects. Refs are not URLs. A sorted Ref list is strictly ascending by digest bytes, without duplicates; size is validated even when a matching digest is cached.

Keys are canonical COSE_Key maps `{1:1, 3:-19, -1:6, -2:public32}`. Ed25519 uses the fully specified COSE algorithm −19. A signed object is tag 18 around `[protected_bstr, {}, payload_bstr, signature64]`. Protected bytes encode exactly `{1:-19, 3:"application/cbor", 4:SHA256(key_bytes)}`. Unprotected headers must be empty. The signing message is canonical CBOR of `["Signature1", protected_bstr, b"HWP/0", payload_bstr]`. This is ordinary Ed25519, not Ed25519ph or a custom prehash mode. Payload bytes must decode canonically to a v0 typed map.

Both public key A and signature point R require canonical Edwards encodings, an on-curve point in the prime-order subgroup, and nonidentity. The scalar S must be less than the Ed25519 subgroup order. The subgroup check and verification equations are fixed by `hwp0/core.py`; permissive acceptance of noncanonical or mixed-order encodings is not conformant. Private signing must use a maintained cryptographic implementation rather than the public-only point-checking helper.

Signatures authenticate roles through the payload type and externally granted authority. Possession of an arbitrary valid key is not capture, evaluator or identity authority. Distinct keys satisfy a key-count quorum, not proof of organizational independence.

## 5. Object graph and schemas

Every typed object below has `v:"hwp/0"` and the indicated `type`, in addition to the exact fields listed. Unknown fields are rejected; there is no implicit extension or optional field outside these definitions. Arrays and nullable fields must be explicitly represented. `schema.cddl` provides the wire grammar; cross-object conditions here are additional requirements.

| Type | Exact additional fields |
|---|---|
| bundle | `root:Ref, objects:[[digest32,raw_bytes],...]` |
| protocol-definition | `name:"Human Writing Protocol", revision:"0.0.0", artifacts:map(text,Ref)` |
| program | `algorithm:"hwp-a/v0", files:[{path:text,ref:Ref},...]` |
| release | `algorithm:"hwp-a/v0", claim, artifacts, capture_profiles:[Ref], protocol:Ref, stage, validation:Ref` |
| capture-profile | `class, domains:[text], max_resolution_us:uint, assumptions:[text], evaluation:Ref|null` |
| validation-dossier | `stage, claim, model:Ref, decision_policy:Ref, program:Ref, capture_profiles:[Ref], allowed_domains:[text], risk_target, coverage_target, confidence, reports:[{role,artifact:Ref}], candidate:Ref-or-null` |
| capture-start — signed | `session:bstr32, profile:Ref, adapter:Ref, nonce:bstr32, subject:KeyRef|null, release:Ref, parents:[{capture:Ref,proof:Ref|null}]` |
| participation — signed | `start:Ref` |
| capture-end — signed | `start:Ref, count:uint, root:bstr32, complete:bool, participation:Ref|null, document:Ref` |
| scope | `document:Ref, kind, ranges:[{start:uint,end:uint,origin:array}]` |
| statement | `document:Ref, media_type, scope:Ref, release:Ref, captures:[Ref], target_capture:Ref, lineage:bstr32, mode, author:KeyRef|null, nonce:bstr32` |
| appraisal — signed | `statement:Ref, result:"HUMAN-WRITTEN"` |
| author-endorsement — signed | `statement:Ref, identity:Ref|null` |
| identity-binding — signed | `subject:KeyRef, namespace:text, identifier:text` |
| proof | `statement:Ref, appraisals:[Ref], author:Ref|null` |
| verification-policy | `label, releases:[Ref], capture_authorities:[{profile:Ref,keys:[KeyRef]}], evaluators:[KeyRef], quorum:uint, modes:[text], require_author:bool, identity_authorities:[KeyRef], denied:[digest32], status_as_of:uint|null, protocol:Ref, purpose` |

The six release artifacts are exactly `algorithm_spec`, `program`, `model`, `decision_policy`, `evidence_adapter`, `output_contract`. In v0, the first, second, fifth and sixth match the frozen installed definition. Model and decision policy are variable, release-bound artifacts. The program manifest denotes the exact portable reference computation, not a cryptographic attestation of a particular machine's native binary. A conformant independent implementation may compute the same semantics; its real capture/evaluator implementation must still satisfy the authority's admitted profile. The Python reference checks its installed source hashes and never executes bundled source.

The algorithm model is canonical CBOR representing the exact JSON-compatible model schema, with version `hwp-a-model/v0`; it is fully validated, including unvisited tree branches. A decision-policy artifact has exactly `{threshold:int, claim_kind:text, allowed_domains:[text]}`. Domains are UTF-8-sorted unique `profile|path|language|view` strings. Every admitted `(profile,path,language)` has all four required views. Fields and quantities in the dossier bind to these actual objects, not a model name. Its rational targets are exactly risk `[1,1000]`, coverage `[1,2]`, and confidence `[19,20]`.

`stage` is `conformance` or `empirical`; `purpose` is `conformance` or `production`. Production requires empirical releases and evaluated capture profiles. Conformance never yields a production positive result. An empirical dossier contains exactly one ordered report reference for each role: adaptive, annotation, calibration, capture, heldout and reproducibility. A conformance dossier has no empirical reports. A conformance dossier has `candidate:null`. An empirical dossier names the conformance release actually evaluated in its `candidate` field. The reports must exist and be retained. Their scientific adequacy is a release-approval responsibility described in the algorithm contract, not a truth inferred by checking their hashes.

A profile class is `fixture` or `evaluated`. Evaluated profiles reference an available evaluation report; fixture profiles have null evaluation. Domains are UTF-8-sorted `profile|path|language`. Resolution is an actual admitted maximum in 1..10000 microseconds. Assumptions are exactly the sorted codes `complete-document-observation`, `faithful-device-origin`, `faithful-monotonic-order`, `native-delivery-binding`, `no-hidden-prediction`, `precommitted-release`, `single-finalization`. A source must justify all of them for the admitted path. Naming a path does not prove them.

The flat bundle lists unique `[digest,bytes]` pairs in strict digest order and contains its root. All objects required by the proof graph, program and normative reference closure must be present. Extra unreferenced public objects convey no authority and do not alter a proof's identity. Proof identity is its exact proof-object Ref, not a ZIP checksum or mutable download URL. Unknown extra data is never executed. A private-disclosure bundle is not a public proof, even though it uses the same flat storage envelope.

## 6. Capturing and committing an observation record

One capture represents exactly one complete normalized HWP record. It starts empty. Prior text must enter through explicit imports/copies; no initially visible text is silently called typed. The required keyboard/tap/IME/gesture observations and authoritative transactions are fixed by `docs/ALGORITHM.md` and the telemetry schema. Native raw events, actual decoder deliveries and mutations have a single contiguous total `seq` order. Timestamps are monotonic and quantized to the declared actual resolution; a tie cannot authorize a future cause. Source labels require capture justification, not writer declarations.

Before input acquisition, the capture source signs start, committing the exact planned release, input profile and adapter. The 32-byte session ID and nonce are freshly and independently generated. The author, when present, signs participation referencing that start before input is treated as attributed. All source records planned for external copy are declared in start.parents in capture-digest order. A parent proof, when supplied, must target that exact parent capture. V0 requires predeclared imports; it does not invent an earlier declaration when a new source is selected later. A new session/version can declare newly available parents.

The committed sequence is: one header; all actual observation/transaction wrappers in their original combined order; one terminal. Header/end wrappers do not consume HWP `seq`. Their exact schema, conversion and dependency reconstruction are defined in `docs/BINDING.md`. A serializer cannot manufacture missing raw observations, delivery fields, times or start participation to migrate a legacy record.

For event i, generate an independent secret random 32-byte salt s_i. Salts must not repeat within the capture. Let E_i be its canonical CBOR bytes and S the SHA-256 digest of the exact signed capture-start object:

```
leaf_i = SHA256(0x00 || CBOR(["HWP/0:event", S, i, s_i, E_i]))
node   = SHA256(0x01 || left32 || right32)
empty  = SHA256(empty_bytes)
```

The tree splits at the largest power of two strictly less than its leaf count, as in RFC 9162. Every commitment is paired with its count. Inclusion and consistency paths use that tree's recursive order; path exhaustion is mandatory. The empty-prefix consistency case authenticates only the empty prior root, not a history. Complete verification requires exactly the committed events and salt/index sequence, not a selection of favourable openings.

On finalization the source atomically freezes the actual observed record and signs capture-end with complete=true, start, count, root, participation and exact final UTF-8 document Ref. A gap or incomplete state must not be silently completed. Mutations after finalization require a new capture. Its root is not a proof that this collector was honest before signing. The final document hash in a source capture may reveal a guessed prior text; v0 does not promise hiding of those final hashes.

Only one finalized end per `(capture signing key, session ID)` is conformant. Conflicting ends encountered in one verification graph cause failure. Offline verification cannot discover undisclosed forks or abandoned sessions elsewhere. Fresh IDs and nonces bind records; they are not proof of physical input, trusted wall time or one attempt per person.

## 7. Scope and provenance

The document is exact UTF-8 bytes with media type text/plain or text/markdown. The protocol binds source bytes, not a renderer's interpretation, PDF export, Markdown preview, layout, title in a separate metadata field or another content object. Such objects need their own future binding profiles.

Scope ranges cover the entire document, consecutively and without overlap or gaps. Offsets are half-open byte intervals on Unicode scalar boundaries. A range's origin is exactly:

```
["observed", [capture_ref,...]]
["inherited", parent_proof_ref, parent_start_byte, parent_end_byte]
["excluded", nonempty_source_description]
```

Adjacent observed/excluded ranges with equal origins must merge. Adjacent inherited ranges merge when the parent proof is identical and source intervals are contiguous. The partition is therefore maximal for the supplied origin assignment. Selection may be chosen after writing, but cannot alter the fixed algorithm neighbourhoods or remove unfavourable evidence from their computation. The empirical endpoint counts any falsely admitted scalar anywhere, not only full-document successes, so favourable scope selection is part of the tested rule.

For observed ranges, the bridge checks the exact union of required record dependencies and that every underlying origin root was born in the target. Under fresh-composition each occurrence must itself be a new target root. Internal duplication is only eligible under wording-origin and does not create fresh effort. The subject on every required observed capture equals statement.author, including null. The target's subject must always equal statement.author, including inherited-only documents.

For inherited ranges, the parent proof must verify under the same relying policy; its certified bytes must cover and exactly match the claimed interval. The parent must be a predeclared captured source, and the actual target atom roots must equal those of that source slice. Identical wording from another unrelated record is insufficient. The exact target and its transitive copy dependencies are included—no missing parents, unrelated supplementary records, cycles or duplicate record IDs. The target's assessment may re-evaluate the source under the target release as an additional condition; this does not revise the original parent assessment.

At least one selected scalar must be non-whitespace according to the fixed SPACE set shared by algorithm and proof. Unicode U+2028/U+2029 are whitespace. A whole-document proof has no exclusions and every scalar qualifies. A selected-ranges proof has at least one exclusion and every nonexcluded scalar qualifies. Merely attaching a verified parent cannot certify the new assembler's composition.

## 8. Evaluation and positive issuance

The bridge opens and validates each committed record; checks end.document; reconstructs exact dependencies; sorts records deterministically; and executes the exact algorithm/model/threshold/scope with independently admitted capture context. It never accepts an author's feature vector, lineage summary, model identity or precomputed verdict as its computation.

The detailed private lineage is the canonical output specified in `docs/OUTPUT.md`. With separately generated secret random salt s_L:

`lineage = SHA256(CBOR(["HWP/0:lineage", s_L, exact_private_lineage_bytes]))`.

Compute this before constructing the final statement; it does not include a reference to that statement. The proof graph is acyclic: planned release and parents → signed start → committed events/end → computed scope and private lineage → statement → evaluator/author signatures → proof → optional archival timestamp. A lineage-salt disclosure refers to the completed statement but is not part of the committed lineage, avoiding recursion.

The evaluator signs only the exact statement for which the recomputed whole/selected HWP result is HUMAN-WRITTEN, and only after all scope/ancestry checks. `issue_appraisal` performs this normal creation path. Low-level possession of an issuer seed can sign lies; no API guard prevents its holder from bypassing software. This trust limitation is explicitly tested. A failed or unsupported assessment receives no positive appraisal and no Human Writing Proof.

Every appraisal signer is authorized by the external policy, unique within the quorum and different from all capture keys. The policy defines the required quorum. The author key is also separate from capture and evaluator keys. No claim of organizational independence follows merely from using different keys. Required endorsements cannot be stripped without verification failure.

## 9. Verification modes and public outcomes

A conforming verifier first enforces input/canonicalization limits, resolves the exact external policy and installed definition, verifies all referenced bytes and release/dossier/profile bindings, authenticates capture plans/ends and scope dependencies, checks evaluator/author roles, and applies the required mode. It checks the separately supplied exact document rather than accepting a document label or mutable URI.

`attested-v1` independently verifies the authenticated positive evaluation statements without opening the private history. Its execution assurance is explicitly `attestation`. `disclosed-v1` additionally requires complete openings and lineage salts and runs the installed v0 bridge. All recomputed bindings must equal the signed statement, including target capture, document, scope, release, captures and lineage. A verifier may request full recomputation of an attested proof as a stronger voluntary audit; the proof identity remains unchanged. Partial disclosure cannot satisfy either full audit or disclosed mode.

The Python R verifier supports both modes. The independent JavaScript V verifier supports public attested verification and rejects a proof requiring disclosed mode; it must not silently treat it as attested. Unregistered ZK modes, mock receipts, missing models, unavailable source evidence or a missing required authority cause NOT PROVABLE.

Public outcome projection is fixed:

| Condition | status | outcome |
|---|---|---|
| All required checks pass under a production policy admitting empirical releases and evaluated capture | VALID-HWP | HUMAN-WRITTEN |
| Checks pass under a conformance-only policy | TEST-ONLY | NOT PROVABLE |
| Any required check fails or is unsupported | NO-VALID-HWP | NOT PROVABLE |

A TEST-ONLY result has `result:null`; its diagnostics may identify a conditional internal positive but cannot be displayed as real human-writing certification. No production policy admitting an existing release is shipped. The exact proof, document, release, claim, selected ranges, policy pin and execution mode accompany a positive interpretation. Diagnostic reason strings are not negative authorship claims and need not be identical across languages; outcome and successful semantic fields must be identical for equal inputs and supported modes.

### Acyclic empirical approval staging

Capture plans bind a release before its observed execution; final reports necessarily follow their experiments. The protocol therefore forbids making a report depend on the future empirical release that contains that report. Training and calibration may run under registered research plans using exact models, thresholds and raw-record identities, without production certificates. Before final held-out and adaptive evaluation of the chosen operating point, fix a **conformance candidate C** with the selected model, threshold, claim, paths, program and other interpretation-bearing artifacts. Protocol-level trials precommit C and return TEST-ONLY. Their measured endpoint is conditional candidate admission, not the deliberately disabled production result.

After those trials, create **empirical release E** with the resulting reports and `validation.candidate = Ref(C)`. C must have stage conformance, a conformance dossier with no reports and null candidate, and exactly the same canonical `algorithm`, `claim`, `artifacts`, `capture_profiles` and `protocol` fields as E. All bound operational dossier fields, including the risk/coverage/confidence targets, must also match. Only the release stage and validation-dossier reference differ. Verifiers check this equality but do not infer scientific validity from it. Inspecting C as supporting evidence neither grants it production authority nor requires it in the production release allow-list.

An independent curator can then approve E. Production captures start E prospectively; old C captures cannot be relabelled E. The algorithmic operating point, not a future release hash, is what the calibration study fixes. Native capture-evaluation reports likewise describe a preregistered configuration and its observations before a profile wraps those reports; they must not require the hash of the future wrapper containing themselves. Reassessment of a historical C trace is a separate diagnostic, never retroactive E capture compliance.

## 10. Private disclosure, limits and safe parsing

The normalized private API value is `{logs:[{capture,openings:[{index,salt,event_bytes}]}], lineage_salts:[{statement,salt}]}`. On disk/wire, a private-disclosure bundle chunks each log into exact 256-opening blocks, except its final remainder. Blocks are typed `opening-block` objects `{offset,openings}`. The typed private-disclosure root contains sorted `{capture,count,parts:[Ref]}` log entries and sorted statement/salt entries. Block order follows event order, not digest order. All listed blocks, and only those blocks and the manifest, appear in its flat store. Repacking must produce identical bytes. This permits large traces without requiring a single CBOR array to contain every decoded event.

Every object/file is at most 64 MiB; public and private bundles each separately satisfy that cap. Canonical decoding permits depth≤32 and ≤100000 visited CBOR items per object, arrays/maps≤100000, and at most4096 objects per flat bundle. Each public document is at most1 MiB and the algorithm further limits it to200000 scalars. A capture has at most1000000 committed events **including** header/end; total opened events in an audit are at most1000000. At most32 records and64 recursive proofs are admitted; scope has at most10000 ranges. Additional algorithm caps in the incorporated reference are mandatory: 500000 observations and transactions each per record; 1000000 total atoms; 5000000 history IDs/effect edges; 1000000 indexed external scalars; 50000000 related-analysis edge visits; 100000000 characters of compact ASCII JSON input; 20000000 for model input. The effective domain is the intersection, not the largest individual limit.

Limit failures must not truncate histories, change models, skip verification or admit a weaker result. Network fetching, archive path traversal, included-program execution and automatic decompression are outside the verifier. Store keys are hashes, not filesystem paths. Native collectors and file readers should enforce bounds while receiving data, before materializing arbitrarily large structures. These finite caps do not assert a production latency or memory benchmark. A runtime failure or incomplete research trial is not an observed successful rejection and must not inflate experimental denominators.

## 11. Privacy, archival time and survival

Raw observations, salts, intermediate drafts, deleted wording and the detailed lineage may remain local. Public artifacts contain the exact document, its scoped proof, releases, authority keys, final capture hashes, parent links and commitments. This can reveal document identity, language/path domains, approximate event volume, prior-document matches and linkable keys. It is not anonymity, biometric unlinkability or a hiding commitment to the public document. Local evidence storage must be protected according to its sensitivity; the protocol does not require unrelated computer surveillance.

Deleting private witnesses does not invalidate an attested proof, but removes the ability to perform future full recomputation. A disclosed-mode proof cannot be fully verified without its required witness, even when its signatures are intact. No already published data can be withdrawn by local deletion.

Optional RFC3161 timestamps bind the digest of the completed proof/bundle or an explicitly identified archive inventory. They give evidence of prior existence under the selected authority and time-validation assumptions, not composition time. The included adapter checks token binding, chain/signature, selected policy and optional nonce, and explicitly does not claim live revocation checking. The core outcome does not silently acquire a trusted creation time from a local clock or a Nostr timestamp.

Long-term verification needs the actual exact document, proof closure, private witness when required, verification specifications/source, public keys, exact trust policy and relevant historical endorsements/status evidence. The archive inventory hashes actual retained bytes with SHA-512 as input to an evidence-renewal process. It is not itself a timestamp or a complete RFC4998 engine. Renew before the relevant algorithms become unsafe; no signature is promised to last forever. A late renewal cannot retroactively repair already forgeable historical evidence.

Historical cryptographic validity, historical policy admission and current policy acceptance are separate questions. A frozen as-of policy is an explicit input, not proof that no subsequent compromise exists. Offline verification cannot learn future revocations. Nostr, C2PA, OpenTimestamps and ZK are not mandatory or activated v0 verification modes; transporting a proof through them cannot enlarge its claim.

## 12. Release approval, falsification and version preservation

The empirical approval contract is fixed in `docs/ALGORITHM.md` and the incorporated dataset protocol: complete preregistered attempts, adverse handling of ambiguity, independent-block accounting, per-path/language/claim cells, eight attack families at budgets1 and100, six genuine-writing conditions, finite prespecified threshold selection, exact binomial eligibility and new held-out evaluation. Targets are conditional on those sampling assumptions. They are not universal adversarial soundness, an individual's probability of truth or protection against unlimited retries.

A curator must review that evidence and the actual native capture/evaluator boundary before admitting an empirical release. Adding six documents named “report” is not scientific approval. The separately trusted policy is the explicit admission decision; the dossier fixes what it purports to approve. No machine-readable self-approval field in a submitted bundle is authoritative.

Researchers can falsify binding invariants, replay/normalization correctness, cross-language agreement, the capture assumptions, the feature representation, supported-domain generalization, the tested false-scalar risk, or genuine-writing coverage. Exact feature collisions and observational-equivalence arguments are retained, not hidden behind a signature. A zero-eligible-threshold result is a legitimate outcome of the standard's empirical process.

New empirical weights/thresholds/dossiers create new content-addressed releases under unchanged v0 semantics. They must be planned in new capture starts; a prior statement is not edited to adopt them. Changes to observation contracts, input modes, feature rules, origin interpretation, required evidence, wire algorithms or computation require a new protocol definition/version. Old records, results and proofs retain their original meaning. The freeze inventory identifies the delivered implementation/specification/vector package independently of its repository hosting or tag name.
