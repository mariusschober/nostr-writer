# Human Writing Protocol v0

**Frozen conformance revision0.0.0. No production-approved detector or native capture profile.**

This package reconciles the actual HWP-A0.3 behavioural implementation with the HWP-C1 cryptographic candidate. It supplies a real, closed observation→algorithm→provenance→proof bridge; exact prospective release and source bindings; immutable interpretation identities; and independently checkable public proof verification. It does not design a writing application.

Start with [SPECIFICATION.md](SPECIFICATION.md), then the [reconciliation audit](docs/AUDIT.md), [binding](docs/BINDING.md), [behavioural contract](docs/ALGORITHM.md), [output contract](docs/OUTPUT.md) and [threat model](docs/THREAT-MODEL.md). [Conformance](docs/CONFORMANCE.md) defines independent implementations and all supported modes. The [CDDL](schema.cddl) and [telemetry schema](telemetry.schema.json) complement—not replace—the semantic checks.

## Scope and meaning

The only production outcome labels are HUMAN-WRITTEN and NOT PROVABLE. Absence or failure never means AI-generated. Whole-document, selected contribution, fresh composition and inherited wording-origin are explicitly distinct. The public proof binds exact text, scope, captured records, model/release, result and optional key association. It does not reveal mental causation, prove personhood or eliminate the need to trust admitted capture/evaluation and empirical approval.

All supplied positive examples are synthetic. They return **TEST-ONLY / NOT PROVABLE**, even when the internal algorithm and signatures satisfy the conformance fixture. A production policy rejects their conformance releases and fixture capture profiles. Scientific experiments must measure conditional candidate decisions, not count that public safeguard as perfect detection.

Private history can remain local in attested mode. Disclosed mode and voluntary full audit run the real algorithm on complete authenticated openings. Neither can establish that a dishonest admitted source's initially fabricated observations happened in reality. One regression deliberately preserves that distinction: a lying admitted evaluator's pasted-history assertion passes attestation but fails recomputation.

## Run and inspect

```
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
node tools/check_interop.mjs
python run_checks.py
python tools/check_freeze.py
```

The Python verifier supports public attestation and full disclosed recomputation. The separately implemented JavaScript verifier supports the full public attestation path and explicitly refuses required behavioural recomputation. It also checks the cross-language commitment/record/lineage ladder. It is not a second independent behavioural classifier.

The CLI is:

```
python -m hwp0 proof.hwp document.txt --policy selected.cbor --policy-pin TRUSTED_HEX
python -m hwp0 proof.hwp document.txt --policy selected.cbor --policy-pin TRUSTED_HEX --disclosure private.hwp --recompute
```

The trust pin must come from an independent relying-party choice, not the submitted proof. Nothing fetches remote artifacts or executes included source. Exact source/normative objects required by v0 accompany the public bundle. No live service is necessary for the supplied tests.

## Files and implementation boundaries

`hwp0/protocol.py` is the complete public verifier and guarded issuance entry point. `bridge.py` implements the actual algorithm binding. `core.py` implements the strictly profiled CBOR/COSE/Merkle mechanism; its lower-level mechanics class is not an alternative v0 public verifier. `algorithm/` contains replay, all179 fixed-point features, model fitting/inference, lineage and statistical evaluation. `disclosure.py` implements the bounded private transport. `rfc3161.py` provides the stated timestamp validation subset.

`vectors/interchange.json` contains exact-byte object pools, public expectations, private conformance records and a computation/commitment ladder. Private fixture keys and salts are intentionally public. `vectors/results.json` records actual execution counts and limitations. `baseline/` retains the audited component documents and reproduced counterexamples. Original repository versions are not overwritten.

Not implemented or claimed: a trusted native sensor path; empirically trained/admitted human-writing model; ZK proof suite; production identity/capture authorities; live revocation; a complete RFC4998 renewal engine; Nostr/C2PA/OTS adapters; a universal defence against behavioural imitation; or indefinite cryptographic security. Those are not silently filled with placeholders or stronger labels.

## Freeze and publication

`FREEZE.json` inventories every shipped source, document, schema and test/vector file, excluding itself and its checksum. The protocol-definition digest pins normative interpretation; the program manifest pins the portable reference computation. A repository tag is a locator, not a substitute for these identities. Verifiers must not run the maintainer manifest-rebuilder to make changed code appear valid.

The repository-publication status for this execution is recorded in [PUBLICATION.md](PUBLICATION.md). A locally frozen package must not be called remotely published until the actual repository commit and tag have been verified.

New original/adapted HWP material in this distribution is under the included MIT license; external standards and dependencies retain their own terms. No patent assurance, standards-body adoption or third-party security approval is asserted.
